#!/usr/bin/env Rscript
################################################################################
# Stage 3 CSR & Ecosystem Services Calculator (Bill's Verification)
#
# Adapted from: src/Stage_3_CSR/calculate_csr_ecoservices_shipley.R
# Original: commonreed/StrateFy (Pierce et al. 2016) + Shipley (2025)
#
# Bill's version uses:
#   - CSV input/output (not parquet)
#   - shipley_checks directory structure
#   - Enriched Stage 3 dataset from enrich_bill_with_taxonomy.R
#
# Usage:
#   Rscript calculate_csr_bill.R \
#     --input data/shipley_checks/stage3/bill_enriched_stage3_11711.csv \
#     --output data/shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv
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
})

################################################################################
# Core StrateFy CSR Calculation (Pierce et al. 2016)
################################################################################

# ========================================================================
# Calculate CSR scores from three functional traits: LA, LDMC, SLA
# ========================================================================
# Based on StrateFy framework by Pierce et al. (2016)
# Input: LA (leaf area, mm²), LDMC (leaf dry matter content, %), SLA (specific leaf area, mm²/mg)
# Output: data.frame with C, S, R columns (each species sums to 100%)
# Method: 5-phase process (transform, project, clip, normalize, balance)
calculate_stratefy_csr <- function(LA, LDMC, SLA) {
  # ========================================================================
  # PHASE 1: Transform traits to calibration space
  # ========================================================================

  # Transform leaf area (LA) using square root normalization
  # Denominator 894205 is the calibration constant from Pierce et al.
  LA_1 <- sqrt(LA / 894205) * 100

  # ENHANCEMENT 1: Clip LDMC to prevent logit explosion
  # Original R implementation: log((LDMC/100)/(1-(LDMC/100)))
  # Problem: LDMC=0 or LDMC=100 cause -Inf or +Inf
  # Solution: Clip to (1e-9, 99.999999) range to keep values finite
  LDMC_safe <- pmax(pmin(LDMC, 99.999999), 1e-9)
  # Logit transformation for LDMC (converts percentage to log-odds)
  LDMC_1 <- log((LDMC_safe / 100) / (1 - (LDMC_safe / 100)))

  # Log transformation for SLA (handles right-skewed distribution)
  SLA_1 <- log(SLA)

  # ========================================================================
  # PHASE 2: Project traits onto CSR axes using calibrated regressions
  # ========================================================================
  # These equations map transformed traits to PCA-calibrated CSR axes
  # Coefficients come from Pierce et al. (2016) calibration study

  # C-axis (Competitive): driven by leaf area (larger leaves = more competitive)
  PC2_C <- -0.8678 + 1.6464 * LA_1

  # S-axis (Stress-tolerant): driven by LDMC (high LDMC = stress tolerance)
  # Uses double exponential to capture non-linear relationship
  PC1_S <- 1.3369 + 0.000010019 * (1 - exp(-0.0000000000022303 * LDMC_1)) +
           4.5835 * (1 - exp(-0.2328 * LDMC_1))

  # R-axis (Ruderal): driven by SLA (high SLA = fast growth, ruderal strategy)
  # Exponential decay: high SLA -> low R score (inverse relationship)
  PC1_R <- -57.5924 + 62.6802 * exp(-0.0288 * SLA_1)

  # ========================================================================
  # PHASE 3: Apply boundary corrections
  # ========================================================================
  # CSR space has defined boundaries based on calibration dataset
  # Species outside these boundaries are clamped to valid range

  # Define minimum boundaries (from Pierce et al. calibration)
  C_min <- 0
  S_min <- -0.756451214853076
  R_min <- -11.3467682227961

  # Clip negative outliers (species below minimum boundary)
  C_neg <- pmax(PC2_C, C_min)
  S_neg <- pmax(PC1_S, S_min)
  R_neg <- pmax(PC1_R, R_min)

  # Define maximum boundaries (from Pierce et al. calibration)
  C_max <- 57.3756711966087
  S_max <- 5.79158377609218
  R_max <- 1.10795515716546

  # Clip positive outliers (species above maximum boundary)
  C_pos <- pmin(C_neg, C_max)
  S_pos <- pmin(S_neg, S_max)
  R_pos <- pmin(R_neg, R_max)

  # ========================================================================
  # PHASE 4: Normalize to 0-100% scale
  # ========================================================================

  # Shift all values to positive range (translate by minimum value)
  C_coef <- abs(C_min)
  S_coef <- abs(S_min)
  R_coef <- abs(R_min)

  C_pos_t <- C_pos + C_coef
  S_pos_t <- S_pos + S_coef
  R_pos_t <- R_pos + R_coef

  # Calculate total range for each axis (max - min after translation)
  PC2_C_range <- C_max + abs(C_min)
  PC1_S_range <- S_max + abs(S_min)
  PC1_R_range <- R_max + abs(R_min)

  # Convert to proportions (0-100 scale)
  C_pro <- C_pos_t / PC2_C_range * 100
  S_pro <- S_pos_t / PC1_S_range * 100
  # Note: R is inverted (100 - x) to match CSR ternary plot convention
  R_pro <- 100 - R_pos_t / PC1_R_range * 100

  # ========================================================================
  # PHASE 5: Normalize so C + S + R = 100%
  # ========================================================================
  # ENHANCEMENT 2: Explicit NaN handling for edge cases
  # When all three proportions are 0 (species hits all boundaries),
  # explicitly assign NA instead of Inf/NaN
  denom <- C_pro + S_pro + R_pro
  Per_coeff <- ifelse(denom > 0, 100 / denom, NA_real_)

  # Final CSR scores (sum to 100% for each species)
  C <- C_pro * Per_coeff
  S <- S_pro * Per_coeff
  R <- R_pro * Per_coeff

  return(data.frame(C = C, S = S, R = R))
}

################################################################################
# Ecosystem Services (Shipley 2025 Parts I & II)
################################################################################

# ========================================================================
# Compute 10 ecosystem service ratings from CSR scores + life form
# ========================================================================
# Based on Shipley (2025) Parts I & II
# Input: df (data.frame with columns: C, S, R, height_m, life_form_simple, nitrogen_fixation_rating)
# Output: df with 20 added columns (10 service ratings + 10 confidence levels)
# Services: NPP, decomposition, 3 nutrient services, 3 carbon services, erosion, N-fixation
compute_ecosystem_services <- function(df) {
  # ========================================================================
  # STEP 1: Initialize and validate input columns
  # ========================================================================

  # Initialize nitrogen fixation if not present (Bill's verification doesn't have TRY N-fix data)
  if (!"nitrogen_fixation_rating" %in% names(df)) {
    cat("  ⚠ nitrogen_fixation_rating not found, using 'No Information' fallback for all species\n")
    df$nitrogen_fixation_rating <- "No Information"
    df$nitrogen_fixation_has_try <- FALSE
  } else {
    # Mark which species have TRY nitrogen fixation data vs fallback
    df$nitrogen_fixation_has_try <- !is.na(df$nitrogen_fixation_rating) &
                                     df$nitrogen_fixation_rating != "No Information"
  }

  # Ensure all required columns are present
  required_cols <- c("C", "S", "R", "height_m", "life_form_simple", "nitrogen_fixation_rating")
  missing <- setdiff(required_cols, names(df))
  if (length(missing) > 0) {
    stop("Missing required columns: ", paste(missing, collapse = ", "))
  }

  # ========================================================================
  # STEP 2: Initialize service rating and confidence columns
  # ========================================================================
  # Each service has a rating (Very Low/Low/Moderate/High/Very High) and confidence level
  # Confidence reflects data quality: Very High (CSR-based), High (CSR+height), Moderate (CSR+assumptions)

  df$npp_rating <- NA_character_
  df$npp_confidence <- "Very High"  # Based on CSR + life form stratification
  df$decomposition_rating <- NA_character_
  df$decomposition_confidence <- "Very High"  # Based on CSR
  df$nutrient_cycling_rating <- NA_character_
  df$nutrient_cycling_confidence <- "Very High"  # Based on CSR
  df$nutrient_retention_rating <- NA_character_
  df$nutrient_retention_confidence <- "Very High"  # Based on CSR
  df$nutrient_loss_rating <- NA_character_
  df$nutrient_loss_confidence <- "Very High"  # Based on CSR
  df$carbon_biomass_rating <- NA_character_
  df$carbon_biomass_confidence <- "High"  # Requires height estimate
  df$carbon_recalcitrant_rating <- NA_character_
  df$carbon_recalcitrant_confidence <- "High"  # Requires recalcitrance data
  df$carbon_total_rating <- NA_character_
  df$carbon_total_confidence <- "High"  # Combined estimate
  df$erosion_protection_rating <- NA_character_
  df$erosion_protection_confidence <- "Moderate"  # Requires root system assumptions
  df$nitrogen_fixation_confidence <- NA_character_

  # ========================================================================
  # STEP 3: Compute services for species with valid CSR
  # ========================================================================
  # Only process species with complete CSR scores (C, S, R all non-NA)
  valid_idx <- !is.na(df$C) & !is.na(df$S) & !is.na(df$R)

  # ========================================================================
  # SERVICE 1: NPP (Net Primary Productivity) with life form stratification
  # ========================================================================
  # Shipley Part II: NPP calculation differs by life form
  # - Woody plants: NPP ∝ height × C (taller competitive trees have highest NPP)
  # - Herbaceous plants: NPP ∝ C only (height less relevant for herbs)

  for (i in which(valid_idx)) {
    C_val <- df$C[i]
    S_val <- df$S[i]
    R_val <- df$R[i]
    height <- df$height_m[i]
    life_form <- df$life_form_simple[i]

    # NPP rating depends on life form
    if (!is.na(life_form) && life_form %in% c("woody", "semi-woody")) {
      # Woody plants: NPP score = height (m) × C-score (0-1)
      # Taller competitive trees -> higher NPP
      npp_score <- height * (C_val / 100)
      # Thresholds calibrated from Shipley Part II results
      if (npp_score >= 4.0) {
        df$npp_rating[i] <- "Very High"  # e.g., 20m tall tree with C=20%
      } else if (npp_score >= 2.0) {
        df$npp_rating[i] <- "High"       # e.g., 10m tree with C=20%
      } else if (npp_score >= 0.5) {
        df$npp_rating[i] <- "Moderate"
      } else if (npp_score >= 0.1) {
        df$npp_rating[i] <- "Low"
      } else {
        df$npp_rating[i] <- "Very Low"
      }
    } else {
      # Herbaceous or unknown: NPP driven by C only
      # High C = competitive fast growers
      if (C_val >= 60) {
        df$npp_rating[i] <- "Very High"
      } else if (C_val >= 50) {
        df$npp_rating[i] <- "High"
      } else if (S_val >= 60) {
        df$npp_rating[i] <- "Low"  # Stress-tolerators have low NPP
      } else {
        df$npp_rating[i] <- "Moderate"
      }
    }

    # ========================================================================
    # SERVICE 2: Litter Decomposition (R ≈ C > S)
    # ========================================================================
    # Ruderals (R) and Competitors (C) have fast-decomposing litter (high SLA, low LDMC)
    # Stress-tolerators (S) have slow-decomposing litter (low SLA, high LDMC)
    if (R_val >= 60 || C_val >= 60) {
      df$decomposition_rating[i] <- "Very High"
    } else if (R_val >= 45 || C_val >= 45) {
      df$decomposition_rating[i] <- "High"
    } else if (S_val >= 60) {
      df$decomposition_rating[i] <- "Low"  # S-strategists slow decomposition
    } else {
      df$decomposition_rating[i] <- "Moderate"
    }

    # ========================================================================
    # SERVICE 3: Nutrient Cycling (R ≈ C > S)
    # ========================================================================
    # Similar pattern to decomposition: fast cycles with R/C, slow with S
    if (R_val >= 60 || C_val >= 60) {
      df$nutrient_cycling_rating[i] <- "Very High"
    } else if (R_val >= 45 || C_val >= 45) {
      df$nutrient_cycling_rating[i] <- "High"
    } else if (S_val >= 60) {
      df$nutrient_cycling_rating[i] <- "Low"
    } else {
      df$nutrient_cycling_rating[i] <- "Moderate"
    }

    # ========================================================================
    # SERVICE 4: Nutrient Retention (C > S > R)
    # ========================================================================
    # Competitors retain nutrients in biomass
    # Ruderals lose nutrients quickly (high turnover)
    if (C_val >= 60) {
      df$nutrient_retention_rating[i] <- "Very High"
    } else if (C_val >= 45) {
      df$nutrient_retention_rating[i] <- "High"
    } else if (R_val >= 60) {
      df$nutrient_retention_rating[i] <- "Low"  # R-strategists don't retain
    } else {
      df$nutrient_retention_rating[i] <- "Moderate"
    }

    # ========================================================================
    # SERVICE 5: Nutrient Loss (R > S ≈ C)
    # ========================================================================
    # Inverse of retention: Ruderals have high nutrient loss
    if (R_val >= 60) {
      df$nutrient_loss_rating[i] <- "Very High"
    } else if (R_val >= 45) {
      df$nutrient_loss_rating[i] <- "High"
    } else if (C_val >= 60) {
      df$nutrient_loss_rating[i] <- "Low"  # C-strategists retain well
    } else {
      df$nutrient_loss_rating[i] <- "Moderate"
    }

    # ========================================================================
    # SERVICE 6: Carbon Storage - Biomass (C > S > R)
    # ========================================================================
    # Competitors store carbon in biomass (high leaf area, dense canopy)
    # Ruderals have low biomass (fast turnover)
    if (C_val >= 60) {
      df$carbon_biomass_rating[i] <- "Very High"
    } else if (C_val >= 45) {
      df$carbon_biomass_rating[i] <- "High"
    } else if (R_val >= 60) {
      df$carbon_biomass_rating[i] <- "Low"
    } else {
      df$carbon_biomass_rating[i] <- "Moderate"
    }

    # ========================================================================
    # SERVICE 7: Carbon Storage - Recalcitrant (S dominant)
    # ========================================================================
    # Stress-tolerators produce recalcitrant litter (high LDMC, slow decomposition)
    # This carbon stays in soil longer
    if (S_val >= 60) {
      df$carbon_recalcitrant_rating[i] <- "Very High"
    } else if (S_val >= 45) {
      df$carbon_recalcitrant_rating[i] <- "High"
    } else if (R_val >= 60) {
      df$carbon_recalcitrant_rating[i] <- "Low"  # R litter decomposes fast
    } else {
      df$carbon_recalcitrant_rating[i] <- "Moderate"
    }

    # ========================================================================
    # SERVICE 8: Carbon Storage - Total (C ≈ S > R)
    # ========================================================================
    # Combined biomass + recalcitrant storage
    # Both C (biomass) and S (recalcitrant) contribute to total storage
    if (C_val >= 50 || S_val >= 50) {
      df$carbon_total_rating[i] <- "Very High"
    } else if (C_val >= 40 || S_val >= 40) {
      df$carbon_total_rating[i] <- "High"
    } else if (R_val >= 60) {
      df$carbon_total_rating[i] <- "Low"  # R-strategists store least carbon
    } else {
      df$carbon_total_rating[i] <- "Moderate"
    }

    # ========================================================================
    # SERVICE 9: Soil Erosion Protection (C > S > R)
    # ========================================================================
    # Competitors have extensive root systems and dense cover
    # Ruderals have sparse, shallow roots
    if (C_val >= 60) {
      df$erosion_protection_rating[i] <- "Very High"
    } else if (C_val >= 45) {
      df$erosion_protection_rating[i] <- "High"
    } else if (R_val >= 60) {
      df$erosion_protection_rating[i] <- "Low"
    } else {
      df$erosion_protection_rating[i] <- "Moderate"
    }
  }

  # ========================================================================
  # SERVICE 10: Nitrogen Fixation (fallback for Bill's verification)
  # ========================================================================
  # Bill's verification doesn't have TRY nitrogen fixation data
  # Confidence is "High" for species with TRY data, "No Information" otherwise
  df$nitrogen_fixation_confidence <- ifelse(
    df$nitrogen_fixation_has_try,
    "High",
    "No Information"
  )

  # ========================================================================
  # STEP 4: Mark species without valid CSR as "Unable to Classify"
  # ========================================================================
  # Species with missing CSR scores cannot have ecosystem services computed
  invalid_idx <- !valid_idx
  if (any(invalid_idx)) {
    # Set all service ratings to "Unable to Classify"
    service_cols <- c("npp_rating", "decomposition_rating", "nutrient_cycling_rating",
                     "nutrient_retention_rating", "nutrient_loss_rating",
                     "carbon_biomass_rating", "carbon_recalcitrant_rating",
                     "carbon_total_rating", "erosion_protection_rating")
    for (col in service_cols) {
      df[[col]][invalid_idx] <- "Unable to Classify"
    }

    # Set all confidence levels to "Not Applicable"
    confidence_cols <- c("npp_confidence", "decomposition_confidence",
                        "nutrient_cycling_confidence", "nutrient_retention_confidence",
                        "nutrient_loss_confidence", "carbon_biomass_confidence",
                        "carbon_recalcitrant_confidence", "carbon_total_confidence",
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
  opt <- parse_args(opt_parser)

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
  cat("  Services computed: 10\n")
  cat("    1. NPP (life form-stratified)\n")
  cat("    2. Litter Decomposition\n")
  cat("    3. Nutrient Cycling\n")
  cat("    4. Nutrient Retention\n")
  cat("    5. Nutrient Loss\n")
  cat("    6. Carbon Storage - Biomass\n")
  cat("    7. Carbon Storage - Recalcitrant\n")
  cat("    8. Carbon Storage - Total\n")
  cat("    9. Soil Erosion Protection\n")
  cat("   10. Nitrogen Fixation (fallback: all Low)\n")

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
