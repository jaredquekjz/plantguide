#!/usr/bin/env Rscript
################################################################################
# Stage 3 CSR & Ecosystem Services Calculator (Bill's Verification)
#
# CSR Implementation: MultiTraits R package (CRAN)
#   - Validated against original StrateFy Excel spreadsheet (Pierce et al. 2017)
#   - Recommended by Bill Shipley (co-author of Pierce et al. 2017)
#   - Replaces buggy commonreed/StrateFy R port and custom implementations
#
# Ecosystem Services: Shipley (2025) Parts I & II
#
# Bill's version uses:
#   - CSV input/output (not parquet)
#   - shipley_checks directory structure
#   - Enriched Stage 3 dataset from enrich_bill_with_taxonomy.R
#
# Usage:
#   Rscript calculate_csr_bill.R \
#     --input data/shipley_checks/stage3/bill_enriched_stage3_11711.csv \
#     --output data/shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv
#
# Note: Previous implementation based on commonreed/StrateFy had edge case bugs
#       affecting ~4% of species. MultiTraits provides validated implementation.
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
  library(optparse)
  library(MultiTraits)
})

################################################################################
# CSR Calculation via MultiTraits Package (Validated Implementation)
################################################################################

# ========================================================================
# Calculate CSR scores from three functional traits: LA, LDMC, SLA
# ========================================================================
# Based on StrateFy framework by Pierce et al. (2017) via MultiTraits package
# Reference: Pierce, S., et al. (2017). A global method for calculating plant
#            CSR ecological strategies applied across biomes world-wide.
#            Functional Ecology, 31: 444-457. https://doi.org/10.1111/1365-2435.12722
# Input: LA (leaf area, mm²), LDMC (leaf dry matter content, %), SLA (specific leaf area, mm²/mg)
# Output: data.frame with C, S, R columns (each species sums to 100%)
# Method: Uses MultiTraits::CSR() which matches the StrateFy Excel spreadsheet
calculate_stratefy_csr <- function(LA, LDMC, SLA) {
  # Prepare input data frame with required columns
  csr_input <- data.frame(
    LA = as.numeric(LA),
    LDMC = as.numeric(LDMC),
    SLA = as.numeric(SLA),
    stringsAsFactors = FALSE
  )

  # Call MultiTraits::CSR() function with error handling
  # MultiTraits::CSR() sometimes fails on large datasets, so we use row-by-row fallback
  csr_results_full <- tryCatch({
    suppressWarnings(MultiTraits::CSR(csr_input))
  }, error = function(e) {
    # Fallback: Process row by row (slower but more robust)
    cat(sprintf("  Note: Processing %d species row-by-row (MultiTraits bulk call failed)\n", nrow(csr_input)))

    C_vec <- numeric(nrow(csr_input))
    S_vec <- numeric(nrow(csr_input))
    R_vec <- numeric(nrow(csr_input))

    for (i in 1:nrow(csr_input)) {
      result <- tryCatch({
        suppressWarnings(MultiTraits::CSR(csr_input[i, ]))
      }, error = function(e2) {
        data.frame(C = NA_real_, S = NA_real_, R = NA_real_)
      })
      C_vec[i] <- result$C
      S_vec[i] <- result$S
      R_vec[i] <- result$R

      if (i %% 1000 == 0) cat(sprintf("    Processed %d/%d...\n", i, nrow(csr_input)))
    }

    data.frame(C = C_vec, S = S_vec, R = R_vec)
  })

  # Return only C, S, R columns to match original function signature
  return(data.frame(C = csr_results_full$C, S = csr_results_full$S, R = csr_results_full$R))
}

################################################################################
# Ecosystem Services (Shipley 2025 - Niklas & Enquist 2001 scaling)
################################################################################

# ========================================================================
# Compute 9 ecosystem service ratings using quantile-based thresholds
# ========================================================================
# Based on Shipley (2025) econotes3: NPP and carbon from height allometry,
# other services from CSR quantiles. Reference: Niklas & Enquist 2001.
#
# Input: df (data.frame with columns: C, S, R, height_m, nitrogen_fixation_rating)
# Output: df with 18 added columns (9 service ratings + 9 confidence levels)
# Services: NPP, decomposition, nutrient cycling/retention/loss, carbon storage,
#           leaf carbon recalcitrant, erosion protection, nitrogen fixation
compute_ecosystem_services <- function(df) {
  # ========================================================================
  # STEP 1: Initialize and validate input columns
  # ========================================================================

  # Initialize nitrogen fixation if not present
  if (!"nitrogen_fixation_rating" %in% names(df)) {
    cat("  nitrogen_fixation_rating not found, using 'No Information' fallback\n")
    df$nitrogen_fixation_rating <- "No Information"
    df$nitrogen_fixation_has_try <- FALSE
  } else {
    df$nitrogen_fixation_has_try <- !is.na(df$nitrogen_fixation_rating) &
                                     df$nitrogen_fixation_rating != "No Information"
  }

  # Ensure required columns present

  required_cols <- c("C", "S", "R", "height_m", "nitrogen_fixation_rating")
  missing <- setdiff(required_cols, names(df))
  if (length(missing) > 0) {
    stop("Missing required columns: ", paste(missing, collapse = ", "))
  }

  # ========================================================================
  # STEP 2: Compute quantiles for height-based and CSR-based ratings
  # ========================================================================
  # Niklas & Enquist 2001 scaling: NPP ∝ H^2.837, Carbon ∝ H^3.788
  # Use 20/40/60/80% quantiles over full dataset for rating thresholds

  valid_idx <- !is.na(df$C) & !is.na(df$S) & !is.na(df$R) & !is.na(df$height_m)

  # Height-based scores (Niklas & Enquist 2001)
  npp_score <- df$height_m^2.837
  carbon_score <- df$height_m^3.788

  # CSR-based scores
  C_score <- df$C
  S_score <- df$S
  R_score <- df$R
  RC_max <- pmax(df$R, df$C, na.rm = TRUE)  # max(R, C) for decomposition/cycling

  # Compute quantiles on valid species only
  probs <- c(0.20, 0.40, 0.60, 0.80)
  npp_q <- quantile(npp_score[valid_idx], probs = probs, na.rm = TRUE)
  carbon_q <- quantile(carbon_score[valid_idx], probs = probs, na.rm = TRUE)
  C_q <- quantile(C_score[valid_idx], probs = probs, na.rm = TRUE)
  S_q <- quantile(S_score[valid_idx], probs = probs, na.rm = TRUE)
  R_q <- quantile(R_score[valid_idx], probs = probs, na.rm = TRUE)
  RC_q <- quantile(RC_max[valid_idx], probs = probs, na.rm = TRUE)

  cat(sprintf("  Quantile thresholds (20/40/60/80%%):\n"))
  cat(sprintf("    NPP (H^2.837): %.2f / %.2f / %.2f / %.2f\n", npp_q[1], npp_q[2], npp_q[3], npp_q[4]))
  cat(sprintf("    Carbon (H^3.788): %.2f / %.2f / %.2f / %.2f\n", carbon_q[1], carbon_q[2], carbon_q[3], carbon_q[4]))
  cat(sprintf("    C-score: %.1f / %.1f / %.1f / %.1f\n", C_q[1], C_q[2], C_q[3], C_q[4]))
  cat(sprintf("    S-score: %.1f / %.1f / %.1f / %.1f\n", S_q[1], S_q[2], S_q[3], S_q[4]))
  cat(sprintf("    R-score: %.1f / %.1f / %.1f / %.1f\n", R_q[1], R_q[2], R_q[3], R_q[4]))
  cat(sprintf("    max(R,C): %.1f / %.1f / %.1f / %.1f\n", RC_q[1], RC_q[2], RC_q[3], RC_q[4]))

  # Helper function to assign ratings based on quantiles
  assign_rating <- function(score, quantiles) {
    rating <- rep(NA_character_, length(score))
    rating[!is.na(score) & score >= quantiles[4]] <- "Very High"
    rating[!is.na(score) & score >= quantiles[3] & score < quantiles[4]] <- "High"
    rating[!is.na(score) & score >= quantiles[2] & score < quantiles[3]] <- "Moderate"
    rating[!is.na(score) & score >= quantiles[1] & score < quantiles[2]] <- "Low"
    rating[!is.na(score) & score < quantiles[1]] <- "Very Low"
    return(rating)
  }

  # ========================================================================
  # STEP 3: Initialize rating and confidence columns
  # ========================================================================

  df$npp_rating <- NA_character_
  df$npp_confidence <- "High"  # Height-based allometry
  df$decomposition_rating <- NA_character_
  df$decomposition_confidence <- "High"  # CSR quantiles
  df$nutrient_cycling_rating <- NA_character_
  df$nutrient_cycling_confidence <- "High"
  df$nutrient_retention_rating <- NA_character_
  df$nutrient_retention_confidence <- "High"
  df$nutrient_loss_rating <- NA_character_
  df$nutrient_loss_confidence <- "High"
  df$carbon_storage_rating <- NA_character_
  df$carbon_storage_confidence <- "High"  # Height-based allometry
  df$leaf_carbon_recalcitrant_rating <- NA_character_
  df$leaf_carbon_recalcitrant_confidence <- "High"
  df$erosion_protection_rating <- NA_character_
  df$erosion_protection_confidence <- "Moderate"  # Requires root assumptions
  df$nitrogen_fixation_confidence <- NA_character_

  # ========================================================================
  # STEP 4: Compute ratings for valid species
  # ========================================================================

  # SERVICE 1: NPP - Net Primary Productivity (Niklas & Enquist: H^2.837)
  df$npp_rating[valid_idx] <- assign_rating(npp_score[valid_idx], npp_q)

  # SERVICE 2: Carbon Storage (Niklas & Enquist: H^3.788)
  df$carbon_storage_rating[valid_idx] <- assign_rating(carbon_score[valid_idx], carbon_q)

  # SERVICE 3: Litter Decomposition - max(R, C) drives fast decomposition
  df$decomposition_rating[valid_idx] <- assign_rating(RC_max[valid_idx], RC_q)

  # SERVICE 4: Nutrient Cycling - max(R, C) drives fast cycling
  df$nutrient_cycling_rating[valid_idx] <- assign_rating(RC_max[valid_idx], RC_q)

  # SERVICE 5: Nutrient Retention - C-score (competitors retain nutrients)
  df$nutrient_retention_rating[valid_idx] <- assign_rating(C_score[valid_idx], C_q)

  # SERVICE 6: Nutrient Loss - R-score (ruderals lose nutrients)
  df$nutrient_loss_rating[valid_idx] <- assign_rating(R_score[valid_idx], R_q)

  # SERVICE 7: Leaf Carbon Recalcitrant - S-score (stress-tolerators)
  df$leaf_carbon_recalcitrant_rating[valid_idx] <- assign_rating(S_score[valid_idx], S_q)

  # SERVICE 8: Erosion Protection - C-score (competitors have dense roots)
  df$erosion_protection_rating[valid_idx] <- assign_rating(C_score[valid_idx], C_q)

  # SERVICE 9: Nitrogen Fixation - from TRY data (passed through)
  df$nitrogen_fixation_confidence <- ifelse(
    df$nitrogen_fixation_has_try,
    "High",
    "No Information"
  )

  # ========================================================================
  # STEP 5: Mark invalid species as "Unable to Classify"
  # ========================================================================
  invalid_idx <- !valid_idx
  if (any(invalid_idx)) {
    service_cols <- c("npp_rating", "decomposition_rating", "nutrient_cycling_rating",
                     "nutrient_retention_rating", "nutrient_loss_rating",
                     "carbon_storage_rating", "leaf_carbon_recalcitrant_rating",
                     "erosion_protection_rating")
    for (col in service_cols) {
      df[[col]][invalid_idx] <- "Unable to Classify"
    }

    confidence_cols <- c("npp_confidence", "decomposition_confidence",
                        "nutrient_cycling_confidence", "nutrient_retention_confidence",
                        "nutrient_loss_confidence", "carbon_storage_confidence",
                        "leaf_carbon_recalcitrant_confidence",
                        "erosion_protection_confidence", "nitrogen_fixation_confidence")
    for (col in confidence_cols) {
      df[[col]][invalid_idx] <- "Not Applicable"
    }
  }

  return(df)
}

################################################################################
# Main Pipeline
################################################################################

# ========================================================================
# Main function: Orchestrate CSR calculation and ecosystem services
# ========================================================================
# Steps:
#   1. Load enriched dataset from enrich_bill_with_taxonomy.R
#   2. Back-transform log-scale traits to original units
#   3. Calculate CSR scores using StrateFy method
#   4. Compute 10 ecosystem services from CSR + life form
#   5. Write output CSV with CSR and service columns
main <- function() {
  # ========================================================================
  # Parse command-line arguments
  # ========================================================================
  option_list <- list(
    make_option(c("--input"), type = "character",
                default = file.path(OUTPUT_DIR, "stage3/bill_enriched_stage3_11711.csv"),
                help = "Input CSV file with enriched traits"),
    make_option(c("--output"), type = "character",
                default = file.path(OUTPUT_DIR, "stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv"),
                help = "Output CSV file with CSR and ecosystem services")
  )

  opt_parser <- OptionParser(option_list = option_list)

  # Filter args to only valid options for this script
  # When sourced by run_all_bill.R, args may contain parent script arguments
  # like "--start-from=phase2" which should be ignored
  all_args <- commandArgs(trailingOnly = TRUE)
  valid_args <- grep("^--(input|output)", all_args, value = TRUE)

  opt <- parse_args(opt_parser, args = valid_args)

  cat("============================================================\n")
  cat("Stage 3 CSR & Ecosystem Services (Bill's Verification)\n")
  cat("============================================================\n\n")

  # ========================================================================
  # STEP 1: Load enriched dataset from enrich_bill_with_taxonomy.R
  # ========================================================================
  cat("Loading data...\n")
  df <- read_csv(opt$input, show_col_types = FALSE)
  cat(sprintf("Loaded %d species\n", nrow(df)))

  # ========================================================================
  # STEP 2: Back-transform traits from log scale to original units
  # ========================================================================
  # Stage 1 created log-transformed traits (logLA, logLDMC, logSLA)
  # CSR calculation requires original units
  cat("\nBack-transforming traits...\n")
  df$LA <- exp(df$logLA)               # Leaf area (mm²)
  df$LDMC <- exp(df$logLDMC) * 100     # Leaf dry matter content (%)
  df$SLA <- exp(df$logSLA)             # Specific leaf area (mm²/mg)

  # Report trait ranges for QC
  cat(sprintf("  LA: %.2f - %.2f mm²\n", min(df$LA, na.rm = TRUE), max(df$LA, na.rm = TRUE)))
  cat(sprintf("  LDMC: %.2f - %.2f %%\n", min(df$LDMC, na.rm = TRUE), max(df$LDMC, na.rm = TRUE)))
  cat(sprintf("  SLA: %.2f - %.2f mm²/mg\n", min(df$SLA, na.rm = TRUE), max(df$SLA, na.rm = TRUE)))

  # ========================================================================
  # STEP 3: Calculate CSR scores using StrateFy method
  # ========================================================================
  cat("\nCalculating CSR scores (StrateFy method)...\n")
  csr_results <- calculate_stratefy_csr(df$LA, df$LDMC, df$SLA)
  df$C <- csr_results$C
  df$S <- csr_results$S
  df$R <- csr_results$R

  # Validation: Check CSR completeness
  valid_csr <- !is.na(df$C) & !is.na(df$S) & !is.na(df$R)
  cat(sprintf("  Valid CSR: %d/%d (%.2f%%)\n",
              sum(valid_csr), nrow(df), 100 * sum(valid_csr) / nrow(df)))
  cat(sprintf("  Failed (NaN): %d species\n", sum(!valid_csr)))

  # Validation: Check CSR sum to 100%
  if (sum(valid_csr) > 0) {
    csr_sum <- df$C[valid_csr] + df$S[valid_csr] + df$R[valid_csr]
    sum_ok <- abs(csr_sum - 100) < 0.01
    cat(sprintf("  CSR sum to 100: %d/%d (%.2f%%)\n",
                sum(sum_ok), sum(valid_csr), 100 * sum(sum_ok) / sum(valid_csr)))
  }

  # ========================================================================
  # STEP 4: Compute ecosystem services from CSR scores
  # ========================================================================
  cat("\nComputing ecosystem services (Shipley 2025)...\n")
  df <- compute_ecosystem_services(df)

  # Report computed services
  cat("  Services computed: 9 (Shipley 2025 / Niklas & Enquist 2001)\n")
  cat("    1. NPP (H^2.837 quantiles)\n")
  cat("    2. Carbon Storage (H^3.788 quantiles)\n")
  cat("    3. Litter Decomposition (max(R,C) quantiles)\n")
  cat("    4. Nutrient Cycling (max(R,C) quantiles)\n")
  cat("    5. Nutrient Retention (C quantiles)\n")
  cat("    6. Nutrient Loss (R quantiles)\n")
  cat("    7. Leaf Carbon Recalcitrant (S quantiles)\n")
  cat("    8. Erosion Protection (C quantiles)\n")
  cat("    9. Nitrogen Fixation (TRY data)\n")

  # ========================================================================
  # STEP 5: Write output file with CSR scores and ecosystem services
  # ========================================================================
  cat("\nWriting output...\n")
  write_csv(df, opt$output)
  cat(sprintf("Saved: %s\n", opt$output))
  cat(sprintf("  %d species × %d columns\n", nrow(df), ncol(df)))

  cat("\n============================================================\n")
  cat("Pipeline Complete\n")
  cat("============================================================\n")
}

# Execute main function when script is run (not when sourced)
if (!interactive()) {
  main()
}
