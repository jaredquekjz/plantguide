#!/usr/bin/env Rscript
# verify_env_aggregation_bill.R - Verify environmental aggregation validity
# Author: Pipeline verification framework, Date: 2025-11-07

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



suppressPackageStartupMessages({library(dplyr); library(arrow)})

check_pass <- function(cond, msg) {
  stat <- if (cond) "✓" else "✗"
  cat(sprintf("  %s %s\n", stat, msg))
  return(cond)
}

cat("========================================================================\n")
cat("VERIFICATION: Environmental Aggregation\n")
cat("========================================================================\n\n")

DATASETS <- c("worldclim", "soilgrids", "agroclime")
DIR <- "data/shipley_checks"
EXPECTED_VARS <- list(worldclim=63, soilgrids=42, agroclime=51)

all_pass <- TRUE

for (ds in DATASETS) {
  cat(sprintf("\n[%s] Checking %s...\n", toupper(ds), ds))
  
  sum_file <- sprintf("%s/%s_species_summary_R.parquet", DIR, ds)
  quant_file <- sprintf("%s/%s_species_quantiles_R.parquet", DIR, ds)
  
  all_pass <- check_pass(file.exists(sum_file), sprintf("Summary file exists")) && all_pass
  all_pass <- check_pass(file.exists(quant_file), sprintf("Quantile file exists")) && all_pass
  
  df_sum <- read_parquet(sum_file)
  df_quant <- read_parquet(quant_file)
  
  all_pass <- check_pass(nrow(df_sum) == 11711, sprintf("Summary: 11,711 species")) && all_pass
  all_pass <- check_pass(nrow(df_quant) == 11711, sprintf("Quantile: 11,711 species")) && all_pass
  
  # Check quantile ordering: q05 < q50 < q95
  q_cols <- grep("_q(05|50|95)", names(df_quant), value=TRUE)
  if (length(q_cols) >= 3) {
    q05_cols <- grep("_q05$", names(df_quant), value=TRUE)
    q50_cols <- grep("_q50$", names(df_quant), value=TRUE)
    q95_cols <- grep("_q95$", names(df_quant), value=TRUE)
    
    if (length(q05_cols) > 0 && length(q50_cols) > 0 && length(q95_cols) > 0) {
      # Check first variable
      var_base <- sub("_q05$", "", q05_cols[1])
      q05 <- df_quant[[paste0(var_base, "_q05")]]
      q50 <- df_quant[[paste0(var_base, "_q50")]]
      q95 <- df_quant[[paste0(var_base, "_q95")]]
      
      ordering_ok <- all(q05 <= q50 & q50 <= q95, na.rm=TRUE)
      all_pass <- check_pass(ordering_ok, sprintf("Quantile ordering valid (checked %s)", var_base)) && all_pass
    }
  }
}

cat("\n========================================================================\n")
if (all_pass) {
  cat("✓ VERIFICATION PASSED\n")
  cat("========================================================================\n\n")
  quit(status = 0)
} else {
  cat("✗ VERIFICATION FAILED\n")
  cat("========================================================================\n\n")
  quit(status = 1)
}
