#!/usr/bin/env Rscript
################################################################################
# Extract TRY Nitrogen Fixation Data (Bill's Verification)
#
# Purpose: Extract TraitID 8 (nitrogen fixation capacity) from TRY database
#          and assign weighted ordinal ratings for master species
#
# Methodology:
# 1. Extract all TraitID=8 records from TRY raw database
# 2. Classify each value as YES (1), NO (0), or ambiguous (skip)
# 3. Calculate weighted score per species: proportion of YES reports
# 4. Assign ordinal rating:
#    - High: ≥75% yes (strong evidence for N-fixation)
#    - Moderate-High: 50-74% yes (likely fixer)
#    - Moderate-Low: 25-49% yes (unclear evidence)
#    - Low: <25% yes (strong evidence against N-fixation)
#
# Based on: src/Stage_3/extract_try_nitrogen_fixation.py
################################################################################

suppressPackageStartupMessages({
  library(rtry)
  library(dplyr)
  library(readr)
  library(arrow)
})

################################################################################
# Classification Function
################################################################################

classify_nfix_value <- function(value) {
  # Classify a single TRY nitrogen fixation value as YES (1), NO (0), or ambiguous (NA)

  if (is.na(value)) return(NA)

  v <- tolower(trimws(as.character(value)))

  # YES patterns (N-fixing bacteria/symbiosis indicators)
  yes_patterns <- c(
    'yes', 'rhizobia', 'frankia', 'nostocaceae',
    'n2 fixing', 'n fixer', 'n-fixer',
    'likely_rhizobia', 'likely_frankia', 'likely_nostocaceae',
    'present', 'true'
  )

  # Check YES patterns (but exclude negations)
  has_yes <- any(sapply(yes_patterns, function(p) grepl(p, v, fixed = TRUE)))
  has_negation <- grepl('not', v) || grepl('unlikely', v) || grepl('no', v)

  if (has_yes && !has_negation) {
    return(1)
  }

  # NO patterns (explicit non-fixers)
  no_patterns <- c('no', 'not', 'none', 'unlikely', 'false', 'non fixer')
  if (any(sapply(no_patterns, function(p) grepl(p, v, fixed = TRUE)))) {
    return(0)
  }

  # Single character codes
  if (v %in% c('n', '0')) return(0)
  if (v %in% c('y', '1')) return(1)

  # Numeric values are ambiguous
  if (grepl('^[0-9]+$', v)) return(NA)

  # Everything else is ambiguous
  return(NA)
}

################################################################################
# Helper: Parse command line arguments
################################################################################

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

################################################################################
# Paths
################################################################################

TRY_RAW_DIR <- get_opt('try_dir', '/home/olier/ellenberg/data/TRY')
TRY_WFO_PATH <- get_opt('try_wfo', 'data/shipley_checks/wfo_verification/tryenhanced_worldflora_enriched.parquet')
MASTER_PATH <- get_opt('master', 'data/shipley_checks/stage2_predictions/bill_complete_with_eive_20251107.csv')
OUTPUT_PATH <- get_opt('output', 'data/shipley_checks/stage3/try_nitrogen_fixation_bill.csv')

################################################################################
# Main Extraction
################################################################################

cat(strrep('=', 80), '\n')
cat('TRY Nitrogen Fixation Extraction (TraitID 8 - Bill Verification)\n')
cat(strrep('=', 80), '\n\n')

# Step 1: Load master species list
cat('[1/6] Loading master species list...\n')
master <- read_csv(MASTER_PATH, show_col_types = FALSE)
master_ids <- unique(master$wfo_taxon_id)
cat(sprintf('  ✓ Master species: %d\n\n', length(master_ids)))

# Step 2: Load TRY-WFO mapping
cat('[2/6] Loading TRY-WFO mapping...\n')
try_wfo <- read_parquet(TRY_WFO_PATH)
try_wfo_clean <- try_wfo %>%
  select(`TRY 30 AccSpecies ID`, wfo_taxon_id) %>%
  filter(!is.na(wfo_taxon_id)) %>%
  filter(wfo_taxon_id %in% master_ids) %>%
  mutate(AccSpeciesID = as.integer(`TRY 30 AccSpecies ID`)) %>%
  select(AccSpeciesID, wfo_taxon_id) %>%
  distinct()

cat(sprintf('  ✓ TRY species mapped: %d\n\n', nrow(try_wfo_clean)))

# Step 3: Extract TraitID=8 records from TRY text files
cat('[3/6] Extracting TraitID 8 from TRY raw files...\n')

try_files <- list.files(TRY_RAW_DIR, pattern = '\\.txt$', full.names = TRUE)
cat(sprintf('  Found %d TRY files\n', length(try_files)))

all_nfix_data <- NULL

for (try_file in try_files) {
  cat(sprintf('  Processing: %s...\n', basename(try_file)))

  # Import TRY data
  try_data <- rtry_import(try_file, encoding = 'Latin-1', separator = '\t')

  # Filter for TraitID 8 (nitrogen fixation)
  nfix_data <- try_data %>%
    filter(TraitID == 8) %>%
    select(AccSpeciesID, OrigValueStr) %>%
    distinct()

  if (nrow(nfix_data) > 0) {
    if (is.null(all_nfix_data)) {
      all_nfix_data <- nfix_data
    } else {
      all_nfix_data <- bind_rows(all_nfix_data, nfix_data)
    }
    cat(sprintf('    → %d records\n', nrow(nfix_data)))
  }

  rm(try_data)
  gc(verbose = FALSE)
}

cat(sprintf('\n  ✓ Total TraitID 8 records: %d\n\n', nrow(all_nfix_data)))

# Step 4: Merge with master species via TRY-WFO mapping
cat('[4/6] Mapping to master species...\n')

nfix_master <- all_nfix_data %>%
  inner_join(try_wfo_clean, by = 'AccSpeciesID') %>%
  filter(wfo_taxon_id %in% master_ids) %>%
  select(wfo_taxon_id, value_raw = OrigValueStr)

cat(sprintf('  ✓ Records for master species: %d\n\n', nrow(nfix_master)))

# Step 5: Classify values and calculate weighted scores
cat('[5/6] Classifying values and calculating weighted scores...\n')

nfix_master$nfix_binary <- sapply(nfix_master$value_raw, classify_nfix_value)

n_yes <- sum(nfix_master$nfix_binary == 1, na.rm = TRUE)
n_no <- sum(nfix_master$nfix_binary == 0, na.rm = TRUE)
n_ambiguous <- sum(is.na(nfix_master$nfix_binary))

cat(sprintf('  YES (N-fixer): %d records\n', n_yes))
cat(sprintf('  NO (non-fixer): %d records\n', n_no))
cat(sprintf('  Ambiguous (skipped): %d records\n\n', n_ambiguous))

# Keep only classified records
classified <- nfix_master %>%
  filter(!is.na(nfix_binary))

# Aggregate by species
species_summary <- classified %>%
  group_by(wfo_taxon_id) %>%
  summarise(
    n_yes = sum(nfix_binary),
    n_total = n(),
    proportion_yes = mean(nfix_binary),
    .groups = 'drop'
  ) %>%
  mutate(n_no = n_total - n_yes)

# Assign ordinal ratings
assign_rating <- function(proportion_yes) {
  if (proportion_yes >= 0.75) {
    return('High')
  } else if (proportion_yes >= 0.50) {
    return('Moderate-High')
  } else if (proportion_yes >= 0.25) {
    return('Moderate-Low')
  } else {
    return('Low')
  }
}

species_summary$nitrogen_fixation_rating <- sapply(species_summary$proportion_yes, assign_rating)

cat(strrep('=', 80), '\n')
cat('RESULTS SUMMARY\n')
cat(strrep('=', 80), '\n\n')

cat(sprintf('Species with TRY N-fixation data: %d/%d (%.1f%%)\n\n',
            nrow(species_summary), length(master_ids),
            100 * nrow(species_summary) / length(master_ids)))

cat('Rating distribution:\n')
rating_counts <- species_summary %>%
  count(nitrogen_fixation_rating) %>%
  arrange(nitrogen_fixation_rating)

for (i in 1:nrow(rating_counts)) {
  rating <- rating_counts$nitrogen_fixation_rating[i]
  count <- rating_counts$n[i]
  pct <- 100 * count / nrow(species_summary)
  cat(sprintf('  %-20s: %4d (%5.1f%%)\n', rating, count, pct))
}

# Step 6: Save results
cat(sprintf('\n[6/6] Saving results to: %s\n', OUTPUT_PATH))

dir.create(dirname(OUTPUT_PATH), recursive = TRUE, showWarnings = FALSE)

output_cols <- c('wfo_taxon_id', 'nitrogen_fixation_rating', 'n_yes', 'n_no', 'n_total', 'proportion_yes')
write_csv(species_summary[, output_cols], OUTPUT_PATH)

cat(sprintf('  ✓ Saved %d species\n', nrow(species_summary)))
cat('\n', strrep('=', 80), '\n')
cat('✓ Extraction complete\n')
cat(strrep('=', 80), '\n')
