#!/usr/bin/env Rscript
# verify_enriched_parquets_bill.R - Verify WFO merge with original datasets
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



suppressPackageStartupMessages({library(arrow)})
check_pass <- function(cond, msg) { stat <- if (cond) "✓" else "✗"; cat(sprintf("  %s %s\n", stat, msg)); return(cond) }

cat("========================================================================\n")
cat("VERIFICATION: Enriched Parquets\n")
cat("========================================================================\n\n")

FILES <- c("duke"=14030, "eive"=14835, "mabberly"=13489, "tryenhanced"=46047)
DIR <- file.path(OUTPUT_DIR, "wfo_verification")

# Expected match rates (some species names don't match in WFO)
EXPECTED_MATCH_RATES <- c("duke"=0.80, "eive"=0.95, "mabberly"=0.98, "tryenhanced"=0.90)

all_pass <- TRUE

for (ds in names(FILES)) {
  file <- sprintf("%s/%s_worldflora_enriched.parquet", DIR, ds)
  all_pass <- check_pass(file.exists(file), sprintf("%s: File exists", ds)) && all_pass

  if (file.exists(file)) {
    df <- read_parquet(file)
    expected <- FILES[[ds]]
    all_pass <- check_pass(abs(nrow(df) - expected) <= 10, sprintf("%s: %d rows [expected %d ± 10]", ds, nrow(df), expected)) && all_pass

    # Check match rate (some NAs expected for invalid/unmatched names)
    n_matched <- sum(!is.na(df$wfo_taxon_id))
    match_rate <- n_matched / nrow(df)
    expected_rate <- EXPECTED_MATCH_RATES[[ds]]

    rate_ok <- match_rate >= expected_rate
    stat <- if (rate_ok) "✓" else "✗"
    cat(sprintf("  %s %s: %.1f%% matched (%d/%d) [expected ≥%.0f%%]\n",
                stat, ds, match_rate * 100, n_matched, nrow(df), expected_rate * 100))
    all_pass <- rate_ok && all_pass
  }
}

cat("\n========================================================================\n")
if (all_pass) { cat("✓ VERIFICATION PASSED\n========================================================================\n\n"); quit(status = 0)
} else { cat("✗ VERIFICATION FAILED\n========================================================================\n\n"); quit(status = 1) }
