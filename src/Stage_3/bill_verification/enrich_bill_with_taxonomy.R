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
  # Bill's verification uses enriched parquet files from WFO matching
  sources <- c(
    'data/shipley_checks/wfo_verification/tryenhanced_worldflora_enriched.parquet',
    'data/shipley_checks/wfo_verification/eive_worldflora_enriched.parquet',
    'data/shipley_checks/wfo_verification/mabberly_worldflora_enriched.parquet'
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

    # Read all columns first to check availability
    wfo_all <- arrow::read_parquet(source_path)

    # Check which taxonomy columns exist
    has_family <- 'Family' %in% names(wfo_all)
    has_genus <- 'Genus' %in% names(wfo_all)

    if (!has_family || !has_genus) {
      cat(sprintf('  ⚠ Skipping %s (missing Family/Genus columns)\n', basename(source_path)))
      next
    }

    wfo <- wfo_all %>%
      select(wfo_taxon_id, Family, Genus)

    # Filter to master IDs and remove duplicates
    wfo_filtered <- wfo %>%
      filter(wfo_taxon_id %in% master_ids) %>%
      filter(!is.na(Family)) %>%
      distinct(wfo_taxon_id, .keep_all = TRUE) %>%
      rename(family = Family, genus = Genus)

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
