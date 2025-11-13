#!/usr/bin/env Rscript
################################################################################
# Enrich Bill's Dataset with Taxonomy for Stage 3 CSR
#
# Purpose: Add family, genus, height_m, life_form_simple to Stage 2 output
# Input: Stage 2 complete dataset (11,711 species with 100% EIVE)
# Output: Enriched dataset ready for CSR calculation
#
# Adapted from: src/Stage_3/enrich_master_with_taxonomy.py
################################################################################

# ========================================================================
# AUTO-DETECTING PATHS (works on Windows/Linux/Mac, any location)
# ========================================================================
get_repo_root <- function() {
  # First check if environment variable is set (from run_all_bill.R)
  env_root <- Sys.getenv("BILL_REPO_ROOT", unset = NA)
  if (!is.na(env_root) && env_root != "") {
    return(normalizePath(env_root))
  }

  # Otherwise detect from script path
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    # Navigate up from script to repo root
    # Scripts are in src/Stage_X/bill_verification/
    repo_root <- normalizePath(file.path(dirname(script_path), "..", "..", ".."))
  } else {
    # Fallback: assume current directory is repo root
    repo_root <- normalizePath(getwd())
  }
  return(repo_root)
}

repo_root <- get_repo_root()
INPUT_DIR <- file.path(repo_root, "input")
INTERMEDIATE_DIR <- file.path(repo_root, "intermediate")
OUTPUT_DIR <- file.path(repo_root, "output")

# Create output directories
dir.create(file.path(OUTPUT_DIR, "wfo_verification"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "stage3"), recursive = TRUE, showWarnings = FALSE)


suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(arrow)
})

parse_args <- function(args) {
  out <- list()
  for (a in args) {
    if (!grepl('^--[A-Za-z0-9_]+=', a)) next
    kv <- sub('^--', '', a)
    key <- sub('=.*$', '', kv)
    val <- sub('^[^=]*=', '', kv)
    out[[key]] <- val
  }
  out
}

args <- commandArgs(trailingOnly = TRUE)
opts <- parse_args(args)
get_opt <- function(name, default) {
  if (!is.null(opts[[name]]) && nzchar(opts[[name]])) {
    opts[[name]]
  } else {
    default
  }
}

# Paths
INPUT_PATH <- get_opt('input', 'data/shipley_checks/stage2_predictions/bill_complete_with_eive_20251107.csv')
OUTPUT_PATH <- get_opt('output', 'data/shipley_checks/stage3/bill_enriched_stage3_11711.csv')

################################################################################
# Helper Functions
################################################################################

load_taxonomy_from_worldflora <- function(master_ids) {
  # Bill's verification uses enriched parquet files from INTERMEDIATE_DIR
  sources <- c(
    file.path(INTERMEDIATE_DIR, 'tryenhanced_worldflora_enriched.parquet'),
    file.path(INTERMEDIATE_DIR, 'eive_worldflora_enriched.parquet'),
    file.path(INTERMEDIATE_DIR, 'mabberly_worldflora_enriched.parquet')
  )

  taxonomy <- data.frame(
    wfo_taxon_id = character(),
    family = character(),
    genus = character(),
    stringsAsFactors = FALSE
  )

  for (source_path in sources) {
    if (!file.exists(source_path)) {
      cat(sprintf('  ⚠ Skipping %s (not found)\n', basename(source_path)))
      next
    }

    cat(sprintf('Loading %s...\n', basename(source_path)))

    wfo <- arrow::read_parquet(source_path, col_select = c('taxonID', 'family', 'genus'))

    # Filter to master IDs and remove duplicates
    wfo_filtered <- wfo %>%
      filter(taxonID %in% master_ids) %>%
      filter(!is.na(family)) %>%
      distinct(taxonID, .keep_all = TRUE) %>%
      rename(wfo_taxon_id = taxonID)

    # Merge with existing taxonomy (first source wins)
    taxonomy <- bind_rows(taxonomy, wfo_filtered) %>%
      distinct(wfo_taxon_id, .keep_all = TRUE)

    coverage <- nrow(taxonomy)
    cat(sprintf('  Coverage: %d/%d (%.1f%%)\n', coverage, length(master_ids),
                100 * coverage / length(master_ids)))
  }

  cat(sprintf('\nFinal taxonomy coverage: %d/%d (%.1f%%)\n\n',
              nrow(taxonomy), length(master_ids),
              100 * nrow(taxonomy) / length(master_ids)))

  return(taxonomy)
}

simplify_life_form <- function(woodiness) {
  # Simplify try_woodiness to woody/non-woody/semi-woody

  result <- character(length(woodiness))

  for (i in seq_along(woodiness)) {
    if (is.na(woodiness[i])) {
      result[i] <- NA_character_
      next
    }

    w <- tolower(trimws(as.character(woodiness[i])))

    # Exact matches first
    if (w == 'non-woody') {
      result[i] <- 'non-woody'
    } else if (w == 'woody') {
      result[i] <- 'woody'
    } else if (w == 'semi-woody') {
      result[i] <- 'semi-woody'
    } else if (grepl(';', w) || (grepl('woody', w) && grepl('non-woody', w))) {
      # Mixed cases (contains semicolon or multiple terms)
      result[i] <- 'semi-woody'
    } else if (grepl('non-woody', w)) {
      result[i] <- 'non-woody'
    } else if (grepl('semi-woody', w)) {
      result[i] <- 'semi-woody'
    } else if (grepl('woody', w)) {
      result[i] <- 'woody'
    } else {
      result[i] <- NA_character_
    }
  }

  return(result)
}

################################################################################
# Main
################################################################################

cat(strrep('=', 80), '\n')
cat('STAGE 3 ENRICHMENT (Bill Verification)\n')
cat(strrep('=', 80), '\n\n')

# Load master table from Stage 2
cat('[1/4] Loading Stage 2 complete dataset...\n')
cat(sprintf('  Input: %s\n', INPUT_PATH))

if (!file.exists(INPUT_PATH)) {
  stop(sprintf('ERROR: Input file not found: %s\n', INPUT_PATH))
}

master <- read_csv(INPUT_PATH, show_col_types = FALSE)
cat(sprintf('  ✓ Loaded %d species × %d columns\n\n', nrow(master), ncol(master)))

# Load taxonomy
cat('[2/4] Loading taxonomy from WorldFlora sources...\n')
taxonomy <- load_taxonomy_from_worldflora(master$wfo_taxon_id)

# Merge taxonomy
master <- master %>%
  left_join(taxonomy, by = 'wfo_taxon_id')

tax_coverage <- sum(!is.na(master$family)) / nrow(master) * 100
cat(sprintf('  ✓ Merged taxonomy: %.1f%% coverage\n\n', tax_coverage))

# Back-transform height
cat('[3/4] Back-transforming height and simplifying life form...\n')

if ('logH' %in% names(master)) {
  master <- master %>%
    mutate(height_m = exp(logH))
  cat(sprintf('  ✓ height_m: %.1f%% complete\n',
              100 * sum(!is.na(master$height_m)) / nrow(master)))
} else {
  cat('  ⚠ logH not found, skipping height_m\n')
}

# Simplify life form
if ('try_woodiness' %in% names(master)) {
  master <- master %>%
    mutate(life_form_simple = simplify_life_form(try_woodiness))
  cat(sprintf('  ✓ life_form_simple: %.1f%% complete\n\n',
              100 * sum(!is.na(master$life_form_simple)) / nrow(master)))
} else {
  cat('  ⚠ try_woodiness not found, skipping life_form_simple\n\n')
}

# Save enriched dataset
cat('[4/4] Saving enriched dataset...\n')
write_csv(master, OUTPUT_PATH)

file_info <- file.info(OUTPUT_PATH)
cat(sprintf('  ✓ Saved: %s\n', OUTPUT_PATH))
cat(sprintf('  Dimensions: %d species × %d columns\n', nrow(master), ncol(master)))
cat(sprintf('  Size: %.1f MB\n', file_info$size / 1024 / 1024))

# Summary
cat('\n', strrep('=', 80), '\n')
cat('ENRICHMENT SUMMARY\n')
cat(strrep('=', 80), '\n\n')

cat(sprintf('Species: %d\n', nrow(master)))
cat(sprintf('Columns: %d\n\n', ncol(master)))

cat('Enrichment coverage:\n')
cat(sprintf('  family: %.1f%% (%d/%d)\n',
            100 * sum(!is.na(master$family)) / nrow(master),
            sum(!is.na(master$family)), nrow(master)))
cat(sprintf('  genus: %.1f%% (%d/%d)\n',
            100 * sum(!is.na(master$genus)) / nrow(master),
            sum(!is.na(master$genus)), nrow(master)))
cat(sprintf('  height_m: %.1f%% (%d/%d)\n',
            100 * sum(!is.na(master$height_m)) / nrow(master),
            sum(!is.na(master$height_m)), nrow(master)))
cat(sprintf('  life_form_simple: %.1f%% (%d/%d)\n',
            100 * sum(!is.na(master$life_form_simple)) / nrow(master),
            sum(!is.na(master$life_form_simple)), nrow(master)))

cat('\n✓ Enrichment complete - ready for CSR calculation\n')
