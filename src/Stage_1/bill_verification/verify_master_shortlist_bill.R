#!/usr/bin/env Rscript
#
# verify_master_shortlist_bill.R
#
# Purpose: Verify master taxa union and shortlist creation logic
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
  library(arrow)
})

# ==============================================================================
# CONFIGURATION
# ==============================================================================

MASTER_UNION_FILE <- "master_taxa_union_bill.parquet"
SHORTLIST_FILE <- "stage1_shortlist_candidates_bill.parquet"

EXPECTED_MASTER_ROWS <- c(86550, 86650)  # 86,592 ± 50
EXPECTED_SHORTLIST_ROWS <- c(24460, 24560)  # 24,511 ± 50

# Expected source counts
EXPECTED_SOURCE_COUNTS <- list(
  duke = c(10600, 10680),
  eive = c(12800, 12900),
  mabberly = c(12600, 12700),
  tryenhanced = c(44200, 44350),
  austraits = c(28000, 28150)
)

# Expected trait-richness counts
EXPECTED_TRAIT_COUNTS <- list(
  eive_ge3 = c(12550, 12650),
  try_ge3 = c(12600, 12700),
  austraits_ge3 = c(3800, 3900)
)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

check_pass <- function(condition, message) {
  if (condition) {
    cat(sprintf("  ✓ %s\n", message))
    return(TRUE)
  } else {
    cat(sprintf("  ✗ FAIL: %s\n", message))
    return(FALSE)
  }
}

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

# ==============================================================================
# VERIFICATION CHECKS
# ==============================================================================

cat("========================================================================\n")
cat("VERIFICATION: Master Taxa Union and Shortlist\n")
cat("========================================================================\n\n")

all_checks_pass <- TRUE

# CHECK 1: File existence
cat("[1/4] Checking file existence...\n")
exists_master <- file.exists(MASTER_UNION_FILE)
exists_shortlist <- file.exists(SHORTLIST_FILE)

check_critical(exists_master, sprintf("Master union file exists: %s", basename(MASTER_UNION_FILE)))
check_critical(exists_shortlist, sprintf("Shortlist file exists: %s", basename(SHORTLIST_FILE)))

if (!exists_master || !exists_shortlist) {
  quit(status = 1)
}

# Load data
cat("\nLoading datasets...\n")
df_master <- read_parquet(MASTER_UNION_FILE)
df_shortlist <- read_parquet(SHORTLIST_FILE)
cat(sprintf("  Master union: %d rows × %d columns\n", nrow(df_master), ncol(df_master)))
cat(sprintf("  Shortlist: %d rows × %d columns\n", nrow(df_shortlist), ncol(df_shortlist)))

# CHECK 2: Master taxa union
cat("\n[2/4] Verifying master taxa union...\n")

# Row count
within_range <- nrow(df_master) >= EXPECTED_MASTER_ROWS[1] && nrow(df_master) <= EXPECTED_MASTER_ROWS[2]
all_checks_pass <- check_pass(
  within_range,
  sprintf("Row count: %d [expected %d-%d]", nrow(df_master), EXPECTED_MASTER_ROWS[1], EXPECTED_MASTER_ROWS[2])
) && all_checks_pass

# No duplicate wfo_taxon_id
n_unique <- length(unique(df_master$wfo_taxon_id))
check_critical(
  n_unique == nrow(df_master),
  sprintf("No duplicate wfo_taxon_id (%d unique / %d rows)", n_unique, nrow(df_master))
)

# Source coverage flags
source_flags <- c("has_duke", "has_eive", "has_mabberly", "has_tryenhanced", "has_austraits")
missing_flags <- setdiff(source_flags, names(df_master))
all_checks_pass <- check_pass(
  length(missing_flags) == 0,
  sprintf("All source flags present: %d/5", 5 - length(missing_flags))
) && all_checks_pass

# Source counts
cat("\n  Source coverage:\n")
for (source in names(EXPECTED_SOURCE_COUNTS)) {
  flag_col <- sprintf("has_%s", source)
  if (flag_col %in% names(df_master)) {
    n_source <- sum(df_master[[flag_col]], na.rm = TRUE)
    expected_range <- EXPECTED_SOURCE_COUNTS[[source]]
    within_range <- n_source >= expected_range[1] && n_source <= expected_range[2]

    status <- ifelse(within_range, "✓", "⚠")
    cat(sprintf("    %s %s: %d taxa [expected %d-%d]\n",
                status, source, n_source, expected_range[1], expected_range[2]))
    all_checks_pass <- check_pass(within_range, sprintf("%s count reasonable", source)) && all_checks_pass
  }
}

# CHECK 3: Shortlist candidates
cat("\n[3/4] Verifying shortlist candidates...\n")

# Row count
within_range <- nrow(df_shortlist) >= EXPECTED_SHORTLIST_ROWS[1] && nrow(df_shortlist) <= EXPECTED_SHORTLIST_ROWS[2]
all_checks_pass <- check_pass(
  within_range,
  sprintf("Row count: %d [expected %d-%d]", nrow(df_shortlist), EXPECTED_SHORTLIST_ROWS[1], EXPECTED_SHORTLIST_ROWS[2])
) && all_checks_pass

# No duplicate wfo_taxon_id
n_unique <- length(unique(df_shortlist$wfo_taxon_id))
check_critical(
  n_unique == nrow(df_shortlist),
  sprintf("No duplicate wfo_taxon_id (%d unique / %d rows)", n_unique, nrow(df_shortlist))
)

# Trait-richness filters
trait_count_cols <- c("eive_numeric_count", "try_numeric_count", "austraits_numeric_count")
missing_counts <- setdiff(trait_count_cols, names(df_shortlist))
all_checks_pass <- check_pass(
  length(missing_counts) == 0,
  sprintf("All trait count columns present: %d/3", 3 - length(missing_counts))
) && all_checks_pass

# Trait counts
cat("\n  Trait-richness filters (≥3 traits):\n")
if ("eive_numeric_count" %in% names(df_shortlist)) {
  n_eive_ge3 <- sum(df_shortlist$eive_numeric_count >= 3, na.rm = TRUE)
  expected_range <- EXPECTED_TRAIT_COUNTS$eive_ge3
  within_range <- n_eive_ge3 >= expected_range[1] && n_eive_ge3 <= expected_range[2]

  status <- ifelse(within_range, "✓", "⚠")
  cat(sprintf("    %s EIVE ≥3: %d species [expected %d-%d]\n",
              status, n_eive_ge3, expected_range[1], expected_range[2]))
  all_checks_pass <- check_pass(within_range, "EIVE count reasonable") && all_checks_pass
}

if ("try_numeric_count" %in% names(df_shortlist)) {
  n_try_ge3 <- sum(df_shortlist$try_numeric_count >= 3, na.rm = TRUE)
  expected_range <- EXPECTED_TRAIT_COUNTS$try_ge3
  within_range <- n_try_ge3 >= expected_range[1] && n_try_ge3 <= expected_range[2]

  status <- ifelse(within_range, "✓", "⚠")
  cat(sprintf("    %s TRY ≥3: %d species [expected %d-%d]\n",
              status, n_try_ge3, expected_range[1], expected_range[2]))
  all_checks_pass <- check_pass(within_range, "TRY count reasonable") && all_checks_pass
}

if ("austraits_numeric_count" %in% names(df_shortlist)) {
  n_aust_ge3 <- sum(df_shortlist$austraits_numeric_count >= 3, na.rm = TRUE)
  expected_range <- EXPECTED_TRAIT_COUNTS$austraits_ge3
  within_range <- n_aust_ge3 >= expected_range[1] && n_aust_ge3 <= expected_range[2]

  status <- ifelse(within_range, "✓", "⚠")
  cat(sprintf("    %s AusTraits ≥3: %d species [expected %d-%d]\n",
              status, n_aust_ge3, expected_range[1], expected_range[2]))
  all_checks_pass <- check_pass(within_range, "AusTraits count reasonable") && all_checks_pass
}

# Qualification flags
qual_flags <- c("qualified_by_eive", "qualified_by_try", "qualified_by_austraits")
missing_qual <- setdiff(qual_flags, names(df_shortlist))
all_checks_pass <- check_pass(
  length(missing_qual) == 0,
  sprintf("All qualification flags present: %d/3", 3 - length(missing_qual))
) && all_checks_pass

# CHECK 4: Data consistency
cat("\n[4/4] Checking data consistency...\n")

# All shortlist species exist in master union
shortlist_ids <- df_shortlist$wfo_taxon_id
master_ids <- df_master$wfo_taxon_id
all_in_master <- all(shortlist_ids %in% master_ids)
all_checks_pass <- check_pass(
  all_in_master,
  "All shortlist species exist in master union"
) && all_checks_pass

# Trait counts are non-negative
for (col in trait_count_cols) {
  if (col %in% names(df_shortlist)) {
    all_non_negative <- all(df_shortlist[[col]] >= 0, na.rm = TRUE)
    all_checks_pass <- check_pass(
      all_non_negative,
      sprintf("%s: all values non-negative", col)
    ) && all_checks_pass
  }
}

# At least one qualification flag TRUE per species
if (all(qual_flags %in% names(df_shortlist))) {
  has_qualification <- rowSums(df_shortlist[qual_flags], na.rm = TRUE) > 0
  all_qualified <- all(has_qualification)
  all_checks_pass <- check_pass(
    all_qualified,
    sprintf("All species have ≥1 qualification (%d/%d)", sum(has_qualification), nrow(df_shortlist))
  ) && all_checks_pass
}

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n========================================================================\n")
cat("SUMMARY\n")
cat("========================================================================\n\n")

cat(sprintf("Master taxa union: %d unique WFO taxa\n", nrow(df_master)))
cat(sprintf("Shortlist candidates: %d species\n", nrow(df_shortlist)))

cat("\n========================================================================\n")
if (all_checks_pass) {
  cat("✓ VERIFICATION PASSED\n")
  cat("========================================================================\n\n")
  quit(status = 0)
} else {
  cat("✗ VERIFICATION FAILED\n")
  cat("========================================================================\n\n")
  quit(status = 1)
}
