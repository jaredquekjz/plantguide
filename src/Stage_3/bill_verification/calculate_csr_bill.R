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
################################################################################

compute_ecosystem_services <- function(df) {
  # Initialize nitrogen fixation if not present
  if (!"nitrogen_fixation_rating" %in% names(df)) {
    cat("  ⚠ nitrogen_fixation_rating not found, using 'Low' fallback for all species\n")
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

  # Nitrogen Fixation - simplified for Bill's verification (no TRY data)
  # All species get "Low" confidence since we're using fallback
  df$nitrogen_fixation_confidence <- "Low"

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
  cat("   10. Nitrogen Fixation (fallback: all Low)\n")

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
