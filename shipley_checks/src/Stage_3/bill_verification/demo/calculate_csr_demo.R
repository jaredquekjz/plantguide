#!/usr/bin/env Rscript
################################################################################
# CSR & Ecosystem Services Calculator - Portable Demo
#
# This is a standalone demonstration version that calculates plant CSR ecological
# strategies (Competitor, Stress-tolerator, Ruderal) and ecosystem services from
# functional traits.
#
# Based on StrateFy method:
#   GitHub: https://github.com/commonreed/StrateFy
#   Pierce et al. (2017). A global method for calculating plant CSR ecological
#   strategies applied across biomes world-wide. Functional Ecology, 31: 444-457.
#   https://doi.org/10.1111/1365-2435.12722
#
# Input requirements (CSV):
#   - wfo_scientific_name: Species identifier
#   - logLA, logLDMC, logSLA: Log-transformed leaf traits
#   - height_m: Plant height in meters
#   - life_form_simple: Life form category (woody, semi-woody, herbaceous)
#   - nitrogen_fixation_rating: (Optional) From TRY database
#     Values: High, Moderate-High, Moderate-Low, Low, or NA
#
# Usage (runs with included sample_data.csv by default):
#   Rscript calculate_csr_demo.R
#
# Or specify custom input/output:
#   Rscript calculate_csr_demo.R --input your_data.csv --output results.csv
################################################################################

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(optparse)
})

################################################################################
# Core StrateFy CSR Calculation (Pierce et al. 2016)
################################################################################

calculate_stratefy_csr <- function(LA, LDMC, SLA) {
  # Improved transformations with safety clipping
  LA_1 <- sqrt(LA / 894205) * 100

  # ENHANCEMENT 1: Clip LDMC to prevent logit explosion
  # Original R implementation: log((LDMC/100)/(1-(LDMC/100)))
  # Problem: LDMC=0 or LDMC=100 cause -Inf or +Inf
  # Solution: Clip to (1e-9, 99.999999) range
  LDMC_safe <- pmax(pmin(LDMC, 99.999999), 1e-9)
  LDMC_1 <- log((LDMC_safe / 100) / (1 - (LDMC_safe / 100)))

  SLA_1 <- log(SLA)

  # Regression against calibration PCA
  PC2_C <- -0.8678 + 1.6464 * LA_1
  PC1_S <- 1.3369 + 0.000010019 * (1 - exp(-0.0000000000022303 * LDMC_1)) +
           4.5835 * (1 - exp(-0.2328 * LDMC_1))
  PC1_R <- -57.5924 + 62.6802 * exp(-0.0288 * SLA_1)

  # CSR classification boundary definition
  C_min <- 0
  S_min <- -0.756451214853076
  R_min <- -11.3467682227961

  # Negative outlier correction
  C_neg <- pmax(PC2_C, C_min)
  S_neg <- pmax(PC1_S, S_min)
  R_neg <- pmax(PC1_R, R_min)

  C_max <- 57.3756711966087
  S_max <- 5.79158377609218
  R_max <- 1.10795515716546

  # Positive outlier correction (clamping)
  C_pos <- pmin(C_neg, C_max)
  S_pos <- pmin(S_neg, S_max)
  R_pos <- pmin(R_neg, R_max)

  # Positive translation
  C_coef <- abs(C_min)
  S_coef <- abs(S_min)
  R_coef <- abs(R_min)

  C_pos_t <- C_pos + C_coef
  S_pos_t <- S_pos + S_coef
  R_pos_t <- R_pos + R_coef

  # Range for PCA positive translation
  PC2_C_range <- C_max + abs(C_min)
  PC1_S_range <- S_max + abs(S_min)
  PC1_R_range <- R_max + abs(R_min)

  # Proportion of total variability
  C_pro <- C_pos_t / PC2_C_range * 100
  S_pro <- S_pos_t / PC1_S_range * 100
  R_pro <- 100 - R_pos_t / PC1_R_range * 100

  # ENHANCEMENT 2: Explicit NaN handling for edge cases
  # When all three proportions are 0 (species hits all boundaries),
  # explicitly assign NA instead of Inf/NaN
  denom <- C_pro + S_pro + R_pro
  Per_coeff <- ifelse(denom > 0, 100 / denom, NA_real_)

  C <- C_pro * Per_coeff
  S <- S_pro * Per_coeff
  R <- R_pro * Per_coeff

  return(data.frame(C = C, S = S, R = R))
}

################################################################################
# Ecosystem Services (Shipley 2025 Parts I & II)
#
# NOTE: Services 1-9 are calculated from CSR scores and plant traits.
#       Service 10 (Nitrogen Fixation) uses empirical data from TRY database
#       (https://www.try-db.org) when available, not calculated from traits.
################################################################################

compute_ecosystem_services <- function(df) {
  # Nitrogen fixation: Use TRY database rating if available, otherwise fallback
  if (!"nitrogen_fixation_rating" %in% names(df)) {
    cat("  ⚠ nitrogen_fixation_rating not found, using 'Low' fallback for all species\n")
    cat("    (Nitrogen fixation data sourced from TRY database when available)\n")
    df$nitrogen_fixation_rating <- "Low"
  }

  # Ensure required columns exist
  required_cols <- c("C", "S", "R", "height_m", "life_form_simple", "nitrogen_fixation_rating")
  missing <- setdiff(required_cols, names(df))
  if (length(missing) > 0) {
    stop("Missing required columns: ", paste(missing, collapse = ", "))
  }

  # Initialize service columns
  df$npp_rating <- NA_character_
  df$npp_confidence <- "Very High"
  df$decomposition_rating <- NA_character_
  df$decomposition_confidence <- "Very High"
  df$nutrient_cycling_rating <- NA_character_
  df$nutrient_cycling_confidence <- "Very High"
  df$nutrient_retention_rating <- NA_character_
  df$nutrient_retention_confidence <- "Very High"
  df$nutrient_loss_rating <- NA_character_
  df$nutrient_loss_confidence <- "Very High"
  df$carbon_biomass_rating <- NA_character_
  df$carbon_biomass_confidence <- "High"
  df$carbon_recalcitrant_rating <- NA_character_
  df$carbon_recalcitrant_confidence <- "High"
  df$carbon_total_rating <- NA_character_
  df$carbon_total_confidence <- "High"
  df$erosion_protection_rating <- NA_character_
  df$erosion_protection_confidence <- "Moderate"
  df$nitrogen_fixation_confidence <- NA_character_

  # For species with valid CSR
  valid_idx <- !is.na(df$C) & !is.na(df$S) & !is.na(df$R)

  # NPP with life form stratification (Shipley Part II)
  for (i in which(valid_idx)) {
    C_val <- df$C[i]
    S_val <- df$S[i]
    R_val <- df$R[i]
    height <- df$height_m[i]
    life_form <- df$life_form_simple[i]

    # NPP (life form-stratified)
    if (!is.na(life_form) && life_form %in% c("woody", "semi-woody")) {
      # Woody: NPP ∝ Height × C
      npp_score <- height * (C_val / 100)
      if (npp_score >= 4.0) {
        df$npp_rating[i] <- "Very High"
      } else if (npp_score >= 2.0) {
        df$npp_rating[i] <- "High"
      } else if (npp_score >= 0.5) {
        df$npp_rating[i] <- "Moderate"
      } else if (npp_score >= 0.1) {
        df$npp_rating[i] <- "Low"
      } else {
        df$npp_rating[i] <- "Very Low"
      }
    } else {
      # Herbaceous or unknown: NPP ∝ C only
      if (C_val >= 60) {
        df$npp_rating[i] <- "Very High"
      } else if (C_val >= 50) {
        df$npp_rating[i] <- "High"
      } else if (S_val >= 60) {
        df$npp_rating[i] <- "Low"
      } else {
        df$npp_rating[i] <- "Moderate"
      }
    }

    # Decomposition (R ≈ C > S)
    if (R_val >= 60 || C_val >= 60) {
      df$decomposition_rating[i] <- "Very High"
    } else if (R_val >= 45 || C_val >= 45) {
      df$decomposition_rating[i] <- "High"
    } else if (S_val >= 60) {
      df$decomposition_rating[i] <- "Low"
    } else {
      df$decomposition_rating[i] <- "Moderate"
    }

    # Nutrient Cycling (R ≈ C > S)
    if (R_val >= 60 || C_val >= 60) {
      df$nutrient_cycling_rating[i] <- "Very High"
    } else if (R_val >= 45 || C_val >= 45) {
      df$nutrient_cycling_rating[i] <- "High"
    } else if (S_val >= 60) {
      df$nutrient_cycling_rating[i] <- "Low"
    } else {
      df$nutrient_cycling_rating[i] <- "Moderate"
    }

    # Nutrient Retention (C > S > R)
    if (C_val >= 60) {
      df$nutrient_retention_rating[i] <- "Very High"
    } else if (C_val >= 45) {
      df$nutrient_retention_rating[i] <- "High"
    } else if (R_val >= 60) {
      df$nutrient_retention_rating[i] <- "Low"
    } else {
      df$nutrient_retention_rating[i] <- "Moderate"
    }

    # Nutrient Loss (R > S ≈ C)
    if (R_val >= 60) {
      df$nutrient_loss_rating[i] <- "Very High"
    } else if (R_val >= 45) {
      df$nutrient_loss_rating[i] <- "High"
    } else if (C_val >= 60) {
      df$nutrient_loss_rating[i] <- "Low"
    } else {
      df$nutrient_loss_rating[i] <- "Moderate"
    }

    # Carbon Storage - Biomass (C > S > R)
    if (C_val >= 60) {
      df$carbon_biomass_rating[i] <- "Very High"
    } else if (C_val >= 45) {
      df$carbon_biomass_rating[i] <- "High"
    } else if (R_val >= 60) {
      df$carbon_biomass_rating[i] <- "Low"
    } else {
      df$carbon_biomass_rating[i] <- "Moderate"
    }

    # Carbon Storage - Recalcitrant (S dominant)
    if (S_val >= 60) {
      df$carbon_recalcitrant_rating[i] <- "Very High"
    } else if (S_val >= 45) {
      df$carbon_recalcitrant_rating[i] <- "High"
    } else if (R_val >= 60) {
      df$carbon_recalcitrant_rating[i] <- "Low"
    } else {
      df$carbon_recalcitrant_rating[i] <- "Moderate"
    }

    # Carbon Storage - Total (C ≈ S > R)
    if (C_val >= 50 || S_val >= 50) {
      df$carbon_total_rating[i] <- "Very High"
    } else if (C_val >= 40 || S_val >= 40) {
      df$carbon_total_rating[i] <- "High"
    } else if (R_val >= 60) {
      df$carbon_total_rating[i] <- "Low"
    } else {
      df$carbon_total_rating[i] <- "Moderate"
    }

    # Erosion Protection (C > S > R)
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

  # Nitrogen Fixation - confidence based on TRY database evidence
  # Logic: High/Moderate-High rating = Very High confidence (strong fixers)
  #        Moderate-Low rating = Moderate confidence
  #        Low rating = High confidence (empirical evidence of non-fixation)
  #        NA (no TRY data) = No Information
  df$nitrogen_fixation_confidence <- ifelse(
    df$nitrogen_fixation_rating %in% c("High", "Moderate-High"),
    "Very High",
    ifelse(
      df$nitrogen_fixation_rating == "Moderate-Low",
      "Moderate",
      ifelse(
        df$nitrogen_fixation_rating == "Low",
        "High",  # Low rating from TRY = high confidence in non-fixation
        "No Information"  # NA rating
      )
    )
  )

  # Mark species without valid CSR as "Unable to Classify"
  invalid_idx <- !valid_idx
  if (any(invalid_idx)) {
    service_cols <- c("npp_rating", "decomposition_rating", "nutrient_cycling_rating",
                     "nutrient_retention_rating", "nutrient_loss_rating",
                     "carbon_biomass_rating", "carbon_recalcitrant_rating",
                     "carbon_total_rating", "erosion_protection_rating")
    for (col in service_cols) {
      df[[col]][invalid_idx] <- "Unable to Classify"
    }

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

main <- function() {
  # Get directory where this script is located (for portable execution)
  script_path <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", script_path, value = TRUE)
  if (length(file_arg) > 0) {
    script_dir <- dirname(sub("^--file=", "", file_arg))
  } else {
    # Fallback to current directory if script path cannot be determined
    script_dir <- "."
  }

  option_list <- list(
    make_option(c("--input"), type = "character",
                default = file.path(script_dir, "sample_data.csv"),
                help = "Input CSV file with trait data (default: sample_data.csv in script directory)"),
    make_option(c("--output"), type = "character",
                default = file.path(script_dir, "output_with_csr.csv"),
                help = "Output CSV file with CSR and ecosystem services")
  )

  opt_parser <- OptionParser(option_list = option_list)
  opt <- parse_args(opt_parser)

  cat("============================================================\n")
  cat("CSR & Ecosystem Services Calculator - Demo\n")
  cat("Based on StrateFy (Pierce et al. 2017)\n")
  cat("============================================================\n\n")

  cat("Loading data...\n")
  df <- read_csv(opt$input, show_col_types = FALSE)
  cat(sprintf("Loaded %d species\n", nrow(df)))

  cat("\nBack-transforming traits...\n")
  df$LA <- exp(df$logLA)
  df$LDMC <- exp(df$logLDMC) * 100  # Convert to %
  df$SLA <- exp(df$logSLA)

  cat(sprintf("  LA: %.2f - %.2f mm²\n", min(df$LA, na.rm = TRUE), max(df$LA, na.rm = TRUE)))
  cat(sprintf("  LDMC: %.2f - %.2f %%\n", min(df$LDMC, na.rm = TRUE), max(df$LDMC, na.rm = TRUE)))
  cat(sprintf("  SLA: %.2f - %.2f mm²/mg\n", min(df$SLA, na.rm = TRUE), max(df$SLA, na.rm = TRUE)))

  cat("\nCalculating CSR scores (StrateFy method)...\n")
  csr_results <- calculate_stratefy_csr(df$LA, df$LDMC, df$SLA)
  df$C <- csr_results$C
  df$S <- csr_results$S
  df$R <- csr_results$R

  # Validation
  valid_csr <- !is.na(df$C) & !is.na(df$S) & !is.na(df$R)
  cat(sprintf("  Valid CSR: %d/%d (%.2f%%)\n",
              sum(valid_csr), nrow(df), 100 * sum(valid_csr) / nrow(df)))
  cat(sprintf("  Failed (NaN): %d species\n", sum(!valid_csr)))

  # Check CSR sum
  if (sum(valid_csr) > 0) {
    csr_sum <- df$C[valid_csr] + df$S[valid_csr] + df$R[valid_csr]
    sum_ok <- abs(csr_sum - 100) < 0.01
    cat(sprintf("  CSR sum to 100: %d/%d (%.2f%%)\n",
                sum(sum_ok), sum(valid_csr), 100 * sum(sum_ok) / sum(valid_csr)))
  }

  cat("\nComputing ecosystem services (Shipley 2025)...\n")
  df <- compute_ecosystem_services(df)

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
  cat("   10. Nitrogen Fixation (from TRY database)\n")

  # Report nitrogen fixation data coverage
  nfix_has_data <- sum(!is.na(df$nitrogen_fixation_rating))
  cat(sprintf("       TRY data coverage: %d/%d species (%.1f%%)\n",
              nfix_has_data, nrow(df), 100 * nfix_has_data / nrow(df)))

  cat("\nWriting output...\n")
  write_csv(df, opt$output)
  cat(sprintf("Saved: %s\n", opt$output))
  cat(sprintf("  %d species × %d columns\n", nrow(df), ncol(df)))

  cat("\n============================================================\n")
  cat("Pipeline Complete\n")
  cat("============================================================\n")
}

if (!interactive()) {
  main()
}
