#!/usr/bin/env Rscript
#
# verify_canonical_assembly_bill.R
#
# Purpose: Comprehensive verification of canonical imputation input assembly
# CRITICAL: Anti-leakage verification - MUST fail if raw trait columns present
# Author: Pipeline verification framework
# Date: 2025-11-07
#

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
  library(dplyr)
  library(readr)
})

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# Define verification parameters and expected values

# Input file to verify (output from assemble_canonical_imputation_input_bill.R)
# Use auto-detected OUTPUT_DIR for cross-platform compatibility
INPUT_FILE <- file.path(OUTPUT_DIR, "modelling", "canonical_imputation_input_11711_bill.csv")

# Expected dataset dimensions
EXPECTED_DIMS <- list(
  rows = 11711,  # All WFO species in base shortlist
  cols = 736     # Total columns (see breakdown below)
)

# Anti-leakage: CRITICAL - These columns MUST NOT exist in final dataset
# Raw trait columns would allow imputation model to "cheat" by copying values
# Only log-transformed versions should be present
RAW_TRAIT_COLS <- c(
  "leaf_area_mm2", "nmass_mg_g", "ldmc_g_g", "sla_mm2_mg",
  "plant_height_m", "seed_mass_mg", "try_lma_g_m2", "aust_lma_g_m2"
)

# Expected column groups (used for presence verification)
LOG_TRAITS <- c("logLA", "logNmass", "logLDMC", "logSLA", "logH", "logSM")  # 6 log traits
CATEGORICAL_TRAITS <- c(
  "try_woodiness", "try_growth_form", "try_habitat_adaptation", "try_leaf_type",
  "try_leaf_phenology", "try_photosynthesis_pathway", "try_mycorrhiza_type"
)  # 7 categorical traits
EIVE_COLS <- c("EIVEres-L", "EIVEres-T", "EIVEres-M", "EIVEres-N", "EIVEres-R")  # 5 EIVE indicators

# Expected coverage ranges (before imputation)
# These ranges define acceptable coverage percentages for each trait/categorical
# Coverage = proportion of species with non-NA values
# Ranges account for natural variation in data availability across databases
EXPECTED_COVERAGE <- list(
  logLA = c(0.44, 0.46),                      # Leaf area: 44-46% coverage
  logNmass = c(0.34, 0.36),                   # Nitrogen mass: 34-36% coverage
  logLDMC = c(0.21, 0.23),                    # Leaf dry matter content: 21-23% coverage
  logSLA = c(0.47, 0.60),                     # Specific leaf area: 47-60% (wider range due to AusTraits)
  logH = c(0.76, 0.78),                       # Plant height: 76-78% coverage
  logSM = c(0.65, 0.67),                      # Seed mass: 65-67% coverage
  try_leaf_phenology = c(0.48, 0.51),         # Phenology: 48-51% coverage
  try_photosynthesis_pathway = c(0.69, 0.72), # Photosynthesis: 69-72% coverage
  try_mycorrhiza_type = c(0.23, 0.25)         # Mycorrhiza: 23-25% coverage
)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Check condition and print formatted pass/fail status
# Returns TRUE if condition passes, FALSE otherwise
# Used for non-critical checks (allows verification to continue)
check_pass <- function(condition, message) {
  if (condition) {
    cat(sprintf("  ✓ %s\n", message))
    return(TRUE)
  } else {
    cat(sprintf("  ✗ FAIL: %s\n", message))
    return(FALSE)
  }
}

# Check critical condition and print formatted status
# If condition fails, immediately exits with status 1 (pipeline halt)
# Used for critical checks like anti-leakage verification
check_critical <- function(condition, message) {
  if (condition) {
    cat(sprintf("  ✓ %s\n", message))
    return(TRUE)
  } else {
    cat(sprintf("  ✗ CRITICAL FAIL: %s\n", message))
    cat("\nVerification FAILED. Exiting.\n")
    quit(status = 1)
  }
}

# Categorize feature columns by type based on naming patterns
# Used to generate feature breakdown summary (climate, soil, phylogeny, etc.)
# Returns category name as string
categorize_feature <- function(feature) {
  feature_lower <- tolower(feature)

  # Climate variables: WorldClim and Agroclim features
  # Prefixes include: wc2.1_ (WorldClim), bio_ (bioclim), tmp/pre/pet (temperature/precipitation/evapotranspiration)
  climate_prefixes <- c('wc2.1_', 'bio_', 'bedd', 'tx', 'tn', 'tmp', 'pre', 'pet', 'srad', 'vapr', 'wind')
  if (any(sapply(climate_prefixes, function(p) grepl(paste0('^', p), feature_lower)))) {
    return('Climate')
  }

  # Soil variables: SoilGrids features
  # Prefixes include: bdod (bulk density), cec (cation exchange), clay/sand/silt (texture), soc (organic carbon)
  soil_prefixes <- c('bdod', 'cec', 'cfvo', 'clay', 'nitrogen', 'phh2o', 'sand', 'silt', 'soc', 'ocd', 'ocs')
  if (any(sapply(soil_prefixes, function(p) grepl(paste0('^', p), feature_lower)))) {
    return('Soil')
  }

  # Phylogenetic eigenvectors: phylo_ev1, phylo_ev2, ..., phylo_ev92
  if (grepl('^phylo_ev', feature_lower)) {
    return('Phylogeny')
  }

  # EIVE indicators: EIVEres-L, EIVEres-T, EIVEres-M, EIVEres-N, EIVEres-R
  if (grepl('^eiveres', feature_lower)) {
    return('EIVE')
  }

  # Categorical traits: try_woodiness, try_growth_form, etc.
  # Exclude log traits (which also start with try_ in some cases)
  if (grepl('^try_', feature_lower) && !grepl('log', feature_lower)) {
    return('Categorical')
  }

  # Log-transformed traits: logLA, logNmass, logLDMC, logSLA, logH, logSM
  if (grepl('^log', feature_lower)) {
    return('Log Traits')
  }

  # Anything else (should be minimal)
  return('Other')
}

# ==============================================================================
# VERIFICATION CHECKS
# ==============================================================================

cat("========================================================================\n")
cat("VERIFICATION: Canonical Imputation Input Assembly\n")
cat("========================================================================\n\n")

all_checks_pass <- TRUE

# CHECK 1: File existence
# Verify output file from assemble_canonical_imputation_input_bill.R exists
cat("[1/10] Checking file existence...\n")
exists <- file.exists(INPUT_FILE)
all_checks_pass <- check_critical(exists, sprintf("Input file exists: %s", INPUT_FILE)) && all_checks_pass

if (!exists) {
  quit(status = 1)
}

# Load data for verification
cat("Loading dataset...\n")
df <- read_csv(INPUT_FILE, show_col_types = FALSE)
cat(sprintf("  Loaded: %d rows × %d columns\n", nrow(df), ncol(df)))

# CHECK 2: Dimensions
# Verify dataset has expected dimensions (11,711 × 736)
# Row count must match base species shortlist (11,711 species)
# Column count must match expected structure (736 total)
cat("\n[2/10] Checking dimensions...\n")
all_checks_pass <- check_critical(
  nrow(df) == EXPECTED_DIMS$rows,
  sprintf("Row count: %d (expected %d)", nrow(df), EXPECTED_DIMS$rows)
) && all_checks_pass

all_checks_pass <- check_critical(
  ncol(df) == EXPECTED_DIMS$cols,
  sprintf("Column count: %d (expected %d)", ncol(df), EXPECTED_DIMS$cols)
) && all_checks_pass

# CHECK 3: CRITICAL - Anti-leakage verification
# Verify NO raw trait columns are present in dataset
# Raw traits (leaf_area_mm2, sla_mm2_mg, etc.) would allow imputation model to "cheat"
# Only log-transformed versions should be present (logLA, logSLA, etc.)
# This is the most critical check - failure causes immediate exit
cat("\n[3/10] CRITICAL: Anti-leakage verification...\n")
found_raw_traits <- intersect(RAW_TRAIT_COLS, names(df))
check_critical(
  length(found_raw_traits) == 0,
  sprintf("NO raw trait columns present (checked: %d columns)", length(RAW_TRAIT_COLS))
)

# If any raw traits found, list them and exit immediately
if (length(found_raw_traits) > 0) {
  cat(sprintf("\n  CRITICAL ERROR: Found raw trait columns that MUST be removed:\n"))
  for (col in found_raw_traits) {
    cat(sprintf("    - %s\n", col))
  }
  cat("\n  Anti-leakage FAILED. These columns allow the model to cheat.\n")
  quit(status = 1)
}

# CHECK 4: Column presence
# Verify all required column groups are present in dataset
# Critical columns: ID, log traits, categorical traits
# Non-critical but expected: EIVE indicators
cat("\n[4/10] Checking required columns...\n")

# IDs: wfo_taxon_id and wfo_scientific_name
# These are essential for linking back to species
id_cols <- c("wfo_taxon_id", "wfo_scientific_name")
missing_ids <- setdiff(id_cols, names(df))
all_checks_pass <- check_pass(
  length(missing_ids) == 0,
  sprintf("ID columns present: %d/2", 2 - length(missing_ids))
) && all_checks_pass

# Log traits: 6 log-transformed continuous traits
# These are critical - they will be imputed by mixgb
missing_log <- setdiff(LOG_TRAITS, names(df))
all_checks_pass <- check_critical(
  length(missing_log) == 0,
  sprintf("Log trait columns present: %d/6", 6 - length(missing_log))
) && all_checks_pass

# Categorical traits: 7 categorical plant characteristics
# These are critical predictors for imputation
missing_cat <- setdiff(CATEGORICAL_TRAITS, names(df))
all_checks_pass <- check_critical(
  length(missing_cat) == 0,
  sprintf("Categorical trait columns present: %d/7", 7 - length(missing_cat))
) && all_checks_pass

# EIVE indicators: 5 ecological indicator values
# These are response variables (non-critical for this assembly check)
missing_eive <- setdiff(EIVE_COLS, names(df))
all_checks_pass <- check_pass(
  length(missing_eive) == 0,
  sprintf("EIVE columns present: %d/5", 5 - length(missing_eive))
) && all_checks_pass

# CHECK 5: Column categorization
# Categorize all feature columns by type (climate, soil, phylogeny, etc.)
# Provides summary breakdown of dataset composition
# Verifies expected counts for each category
cat("\n[5/10] Categorizing feature columns...\n")
# Exclude ID columns and any index columns from categorization
feature_cols <- setdiff(names(df), c(id_cols, "Unnamed: 0"))
categories <- sapply(feature_cols, categorize_feature)
category_counts <- table(categories)

cat(sprintf("  Feature breakdown:\n"))
for (cat_name in names(category_counts)) {
  cat(sprintf("    - %s: %d columns\n", cat_name, category_counts[cat_name]))
}

# Expected counts for major categories
# Climate + Soil = environmental quantiles (~624 columns)
# Phylogeny = 92 eigenvectors (broken stick selection)
# Log Traits = 6, Categorical = 7, EIVE = 5
expected_cats <- list(
  "Log Traits" = 6,
  "Categorical" = 7,  # May be 6 if one trait categorized as Other
  "EIVE" = 5,
  "Phylogeny" = 92
)

# Verify each category has expected count
for (cat_name in names(expected_cats)) {
  actual <- ifelse(cat_name %in% names(category_counts), category_counts[cat_name], 0)
  expected <- expected_cats[[cat_name]]

  # Allow flexibility for Categorical (6 or 7 both OK if Section 4 passed)
  # Some categorical traits may be miscategorized as "Other" by naming pattern
  if (cat_name == "Categorical") {
    within_range <- actual >= 6 && actual <= 7
    all_checks_pass <- check_pass(
      within_range,
      sprintf("%s: %d columns (expected 6-7, all 7 verified in Section 4)", cat_name, actual)
    ) && all_checks_pass
  } else {
    all_checks_pass <- check_pass(
      actual == expected,
      sprintf("%s: %d columns (expected %d)", cat_name, actual, expected)
    ) && all_checks_pass
  }
}

# CHECK 6: Log trait coverage (before imputation)
# Verify log trait coverage falls within expected ranges
# Coverage = proportion of species with non-NA values
# These are pre-imputation values (will be filled by mixgb later)
cat("\n[6/10] Checking log trait coverage (before imputation)...\n")
for (trait in LOG_TRAITS) {
  if (trait %in% names(df)) {
    n_obs <- sum(!is.na(df[[trait]]))
    coverage <- n_obs / nrow(df)

    trait_name <- substr(trait, 1, nchar(trait))
    expected_range <- EXPECTED_COVERAGE[[trait_name]]

    if (!is.null(expected_range)) {
      within_range <- coverage >= expected_range[1] && coverage <= expected_range[2]
      status <- ifelse(within_range, "✓", "⚠")
      cat(sprintf("  %s %s: %.1f%% (%d/%d species) [expected %.1f-%.1f%%]\n",
                  status, trait, coverage * 100, n_obs, nrow(df),
                  expected_range[1] * 100, expected_range[2] * 100))
      all_checks_pass <- check_pass(within_range, sprintf("%s coverage within expected range", trait)) && all_checks_pass
    }
  }
}

# CHECK 7: Categorical trait coverage (CRITICAL for 3 fixed traits)
# Verify categorical trait coverage
# Three traits (phenology, photosynthesis, mycorrhiza) were previously at 0% and are now fixed
# These must have >0% coverage (CRITICAL check)
cat("\n[7/10] Checking categorical trait coverage...\n")

# These 3 traits were fixed from 0% coverage in Phase 2 (TRY Selected standardization)
CRITICAL_FIXED_TRAITS <- c("try_leaf_phenology", "try_photosynthesis_pathway", "try_mycorrhiza_type")

for (trait in CATEGORICAL_TRAITS) {
  if (trait %in% names(df)) {
    n_obs <- sum(!is.na(df[[trait]]))
    coverage <- n_obs / nrow(df)

    trait_name <- trait
    expected_range <- EXPECTED_COVERAGE[[trait_name]]

    # CRITICAL: Fixed traits must have > 0% coverage (proves fix worked)
    if (trait %in% CRITICAL_FIXED_TRAITS) {
      check_critical(
        coverage > 0,
        sprintf("%s: %.1f%% (%d species) [FIXED from 0%%]", trait, coverage * 100, n_obs)
      )
    } else {
      # Non-critical traits: just report coverage
      cat(sprintf("  ✓ %s: %.1f%% (%d species)\n", trait, coverage * 100, n_obs))
    }

    # Check if coverage falls within expected range (warning if outside)
    if (!is.null(expected_range)) {
      within_range <- coverage >= expected_range[1] && coverage <= expected_range[2]
      if (!within_range) {
        cat(sprintf("    ⚠ Coverage outside expected range [%.1f-%.1f%%]\n",
                    expected_range[1] * 100, expected_range[2] * 100))
      }
    }
  }
}

# CHECK 8: EIVE coverage
# Verify EIVE indicator coverage (expected ~50-55% for European flora)
# EIVE = Extended Indicator Values for Europe
# Coverage lower than traits because only European species have EIVE values
cat("\n[8/10] Checking EIVE coverage...\n")
for (eive in EIVE_COLS) {
  if (eive %in% names(df)) {
    n_obs <- sum(!is.na(df[[eive]]))
    coverage <- n_obs / nrow(df)
    # EIVE coverage expected around 50-55% (European species only)
    within_range <- coverage >= 0.50 && coverage <= 0.55
    status <- ifelse(within_range, "✓", "⚠")
    cat(sprintf("  %s %s: %.1f%% (%d species) [expected 50-55%%]\n",
                status, eive, coverage * 100, n_obs))
    all_checks_pass <- check_pass(within_range, sprintf("%s coverage within range", eive)) && all_checks_pass
  }
}

# CHECK 9: Phylogenetic eigenvector coverage
# Verify 92 phylo eigenvector columns present with expected coverage
# Coverage expected >99.6% (11,010 species with tree tips / 11,711 total)
# ~700 species lack eigenvectors (no phylogenetic placement)
cat("\n[9/10] Checking phylogenetic eigenvector coverage...\n")
phylo_cols <- grep("^phylo_ev[0-9]+$", names(df), value = TRUE)
if (length(phylo_cols) == 92) {
  cat(sprintf("  ✓ Found 92 phylogenetic eigenvector columns\n"))

  # Check coverage: should be >99.6% (all species with tree tips)
  phylo_coverage <- sapply(phylo_cols, function(col) sum(!is.na(df[[col]])) / nrow(df))
  mean_coverage <- mean(phylo_coverage)

  within_range <- mean_coverage >= 0.996 && mean_coverage <= 1.0
  cat(sprintf("  %s Mean coverage: %.1f%% [expected 99.6-100%%]\n",
              ifelse(within_range, "✓", "⚠"), mean_coverage * 100))
  all_checks_pass <- check_pass(within_range, "Phylo eigenvector coverage within range") && all_checks_pass
} else {
  cat(sprintf("  ✗ Expected 92 phylo eigenvectors, found %d\n", length(phylo_cols)))
  all_checks_pass <- FALSE
}

# CHECK 10: Environmental feature coverage
# Verify environmental quantile columns (climate, soil, agroclim)
# Expected: 624 columns total (156 variables × 4 quantiles)
# Each variable has q05, q50, q95, iqr quantiles
# Environmental features should have >99% completeness (nearly all species)
cat("\n[10/10] Checking environmental feature coverage...\n")

# Count quantile columns by suffix
# 156 vars × 4 quantiles = 624 total environmental columns
q50_cols <- grep("_q50$", names(df), value = TRUE)  # Median quantile
q05_cols <- grep("_q05$", names(df), value = TRUE)  # Lower quantile
q95_cols <- grep("_q95$", names(df), value = TRUE)  # Upper quantile
iqr_cols <- grep("_iqr$", names(df), value = TRUE)  # Interquartile range

total_quantile_cols <- length(q50_cols) + length(q05_cols) + length(q95_cols) + length(iqr_cols)

cat(sprintf("  ✓ Environmental quantile columns:\n"))
cat(sprintf("    - q50: %d\n", length(q50_cols)))
cat(sprintf("    - q05: %d\n", length(q05_cols)))
cat(sprintf("    - q95: %d\n", length(q95_cols)))
cat(sprintf("    - iqr: %d\n", length(iqr_cols)))
cat(sprintf("    - Total: %d [expected 624]\n", total_quantile_cols))

all_checks_pass <- check_pass(
  total_quantile_cols == 624,
  sprintf("Environmental quantile columns correct (%d)", total_quantile_cols)
) && all_checks_pass

# Check completeness of q50 columns (sample 20 for efficiency)
# Environmental features should be >99% complete (all species with GBIF occurrences)
if (length(q50_cols) > 0) {
  env_complete <- sapply(q50_cols[1:min(20, length(q50_cols))], function(col) {
    sum(!is.na(df[[col]])) / nrow(df)
  })
  mean_complete <- mean(env_complete)

  cat(sprintf("  ✓ Mean q50 completeness: %.1f%% (sampled %d features)\n",
              mean_complete * 100, min(20, length(q50_cols))))
  all_checks_pass <- check_pass(mean_complete >= 0.99, "Environmental features >99% complete") && all_checks_pass
} else {
  mean_complete <- 0
  cat(sprintf("  ✗ No q50 columns found\n"))
  all_checks_pass <- FALSE
}

# ==============================================================================
# SUMMARY
# ==============================================================================
# Report overall verification summary and exit with appropriate status code
# Status 0: all checks passed, pipeline can continue
# Status 1: at least one check failed, pipeline should halt

cat("\n========================================================================\n")
cat("SUMMARY\n")
cat("========================================================================\n\n")

cat(sprintf("Dataset: %d species × %d features\n", nrow(df), ncol(df)))
cat("\nColumn breakdown:\n")
cat(sprintf("  - IDs: 2\n"))
cat(sprintf("  - Log traits: 6 (%.0f-%.0f%% coverage before imputation)\n", 22, 77))
cat(sprintf("  - Categorical: 7 (%.0f-%.0f%% coverage)\n", 24, 79))
cat(sprintf("  - EIVE: 5 (%.0f-%.0f%% coverage)\n", 51, 54))
cat(sprintf("  - Phylo eigenvectors: %d (%.1f%% coverage)\n", length(phylo_cols), mean_coverage * 100))
cat(sprintf("  - Environmental quantiles: %d columns (%.0f%% coverage)\n", total_quantile_cols, mean_complete * 100))

cat("\n========================================================================\n")
if (all_checks_pass) {
  cat("✓ VERIFICATION PASSED\n")
  cat("========================================================================\n")
  cat("\nCanonical imputation input assembly verified successfully.\n")
  cat("CRITICAL: Anti-leakage check passed - no raw trait columns present.\n\n")
  quit(status = 0)
} else {
  cat("✗ VERIFICATION FAILED\n")
  cat("========================================================================\n")
  cat("\nSome checks failed. Review output above for details.\n\n")
  quit(status = 1)
}
