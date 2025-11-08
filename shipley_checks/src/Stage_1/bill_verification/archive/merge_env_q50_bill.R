#!/usr/bin/env Rscript
#
# merge_env_q50_bill.R
#
# Purpose: Extract and merge q50 environmental features from Bill's verified quantile files
#
# Inputs:
#   - data/shipley_checks/worldclim_species_quantiles_R.parquet (63 vars × 4 = 252 + wfo_taxon_id)
#   - data/shipley_checks/soilgrids_species_quantiles_R.parquet (42 vars × 4 = 168 + wfo_taxon_id)
#   - data/shipley_checks/agroclime_species_quantiles_R.parquet (51 vars × 4 = 204 + wfo_taxon_id)
#
# Output:
#   - data/shipley_checks/modelling/env_q50_features_11711_bill.csv (156 q50 + wfo_taxon_id = 157 cols)
#
# Logic matches Python/DuckDB from 1.7a_Imputation_Dataset_Preparation.md lines 86-104:
#   1. Read Bill's verified quantile parquets (already match canonical perfectly)
#   2. Extract only columns ending in "_q50"
#   3. Left join WorldClim → SoilGrids → Agroclim on wfo_taxon_id
#   4. Verify 156 q50 columns (63 + 42 + 51)
#
# Run:
#   env R_LIBS_USER=/home/olier/ellenberg/.Rlib \
#     /usr/bin/Rscript src/Stage_1/bill_verification/merge_env_q50_bill.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(readr)
})

cat("=" , rep("=", 70), "=\n", sep="")
cat("Bill's Verification: Merge Environmental Q50 Features\n")
cat("=" , rep("=", 70), "=\n\n", sep="")

# Output directory
output_dir <- "data/shipley_checks/modelling"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Step 1: Read WorldClim quantiles (Bill's verified)
cat("[1/6] Reading WorldClim quantiles (Bill's verified)...\n")
wc_path <- "data/shipley_checks/worldclim_species_quantiles_R.parquet"
if (!file.exists(wc_path)) {
  stop("ERROR: WorldClim quantiles not found: ", wc_path)
}
wc <- read_parquet(wc_path)
cat("  - Loaded:", nrow(wc), "species ×", ncol(wc), "columns\n")

# Extract q50 columns
wc_q50_cols <- names(wc)[grepl("_q50$", names(wc))]
wc_q50 <- wc %>% select(wfo_taxon_id, all_of(wc_q50_cols))
cat("  - Extracted", length(wc_q50_cols), "q50 columns\n")

# Step 2: Read SoilGrids quantiles (Bill's verified)
cat("\n[2/6] Reading SoilGrids quantiles (Bill's verified)...\n")
sg_path <- "data/shipley_checks/soilgrids_species_quantiles_R.parquet"
if (!file.exists(sg_path)) {
  stop("ERROR: SoilGrids quantiles not found: ", sg_path)
}
sg <- read_parquet(sg_path)
cat("  - Loaded:", nrow(sg), "species ×", ncol(sg), "columns\n")

# Extract q50 columns
sg_q50_cols <- names(sg)[grepl("_q50$", names(sg))]
sg_q50 <- sg %>% select(wfo_taxon_id, all_of(sg_q50_cols))
cat("  - Extracted", length(sg_q50_cols), "q50 columns\n")

# Step 3: Read Agroclim quantiles (Bill's verified)
cat("\n[3/6] Reading Agroclim quantiles (Bill's verified)...\n")
ac_path <- "data/shipley_checks/agroclime_species_quantiles_R.parquet"
if (!file.exists(ac_path)) {
  stop("ERROR: Agroclim quantiles not found: ", ac_path)
}
ac <- read_parquet(ac_path)
cat("  - Loaded:", nrow(ac), "species ×", ncol(ac), "columns\n")

# Extract q50 columns (note: agroclime with 'e', not 'c')
ac_q50_cols <- names(ac)[grepl("_q50$", names(ac))]
ac_q50 <- ac %>% select(wfo_taxon_id, all_of(ac_q50_cols))
cat("  - Extracted", length(ac_q50_cols), "q50 columns\n")

# Step 4: Merge all three datasets (left joins matching DuckDB logic)
cat("\n[4/6] Merging q50 features...\n")
cat("  - WorldClim LEFT JOIN SoilGrids on wfo_taxon_id\n")
env_q50 <- wc_q50 %>%
  left_join(sg_q50, by = "wfo_taxon_id")

cat("  - Result LEFT JOIN Agroclim on wfo_taxon_id\n")
env_q50 <- env_q50 %>%
  left_join(ac_q50, by = "wfo_taxon_id")

cat("  - Final merged dataset:", nrow(env_q50), "species ×", ncol(env_q50), "columns\n")

# Step 5: Verify expected structure
cat("\n[5/6] Verifying structure...\n")
expected_q50_count <- length(wc_q50_cols) + length(sg_q50_cols) + length(ac_q50_cols)
actual_q50_count <- ncol(env_q50) - 1  # Exclude wfo_taxon_id

if (actual_q50_count != expected_q50_count) {
  stop("ERROR: Expected ", expected_q50_count, " q50 columns, got ", actual_q50_count)
}

if (actual_q50_count != 156) {
  stop("ERROR: Expected 156 q50 columns (63 + 42 + 51), got ", actual_q50_count)
}

cat("  ✓ Column count correct: 156 q50 features + 1 ID = 157 total\n")
cat("  ✓ WorldClim q50: ", length(wc_q50_cols), "\n")
cat("  ✓ SoilGrids q50: ", length(sg_q50_cols), "\n")
cat("  ✓ Agroclim q50: ", length(ac_q50_cols), "\n")

# Check for missing values
missing_by_col <- colSums(is.na(env_q50))
if (any(missing_by_col > 0)) {
  cat("\n  WARNING: Some species have missing environmental data:\n")
  missing_species <- which(rowSums(is.na(env_q50[, -1])) > 0)
  cat("    ", length(missing_species), "species with at least one NA value\n")
}

# Step 6: Write output
cat("\n[6/6] Writing output...\n")
output_path <- file.path(output_dir, "env_q50_features_11711_bill.csv")
write_csv(env_q50, output_path)
cat("  ✓ Written:", output_path, "\n")
cat("  ✓ File size:", file.size(output_path) / 1024^2, "MB\n")

# Summary
cat("\n", rep("=", 72), "\n", sep="")
cat("SUCCESS: Environmental q50 merge complete\n")
cat(rep("=", 72), "\n\n", sep="")
cat("Output:\n")
cat("  - File: ", output_path, "\n")
cat("  - Shape: ", nrow(env_q50), " species × ", ncol(env_q50), " columns\n")
cat("  - Features: 156 q50 (WorldClim ", length(wc_q50_cols),
    " + SoilGrids ", length(sg_q50_cols),
    " + Agroclim ", length(ac_q50_cols), ")\n")
cat("\nNext step: Run extract_phylo_eigenvectors_bill.R\n")
