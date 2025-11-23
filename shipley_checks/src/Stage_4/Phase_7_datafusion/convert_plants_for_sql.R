#!/usr/bin/env Rscript
#
# Convert Phase 4 plant data to DataFusion SQL-optimized parquet
#
# Purpose:
# - Take Phase 4 output (vernaculars + Köppen + CSR + ecosystem services)
# - Create flattened, SQL-friendly schema for DataFusion query engine
# - Rename columns (remove hyphens), normalize scales, add computed columns
#
# Input:
#   - shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet
#
# Output:
#   - shipley_checks/stage4/phase7_output/plants_searchable_11711.parquet
#

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

# Paths
project_root <- "/home/olier/ellenberg"
input_file <- file.path(project_root, "shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet")
output_file <- file.path(project_root, "shipley_checks/stage4/phase7_output/plants_searchable_11711.parquet")

cat("================================================================================\n")
cat("PHASE 7: CONVERT PLANTS TO SQL-OPTIMIZED PARQUET\n")
cat("================================================================================\n\n")

# Check input exists
if (!file.exists(input_file)) {
  stop("Input file not found: ", input_file, "\n  Run Phase 4 first.")
}

cat("Loading plant data...\n")
cat("  Input: ", input_file, "\n")

plants <- read_parquet(input_file)
cat("  →", nrow(plants), "plants loaded\n")
cat("  →", ncol(plants), "columns\n\n")

cat("================================================================================\n")
cat("TRANSFORMATIONS\n")
cat("================================================================================\n\n")

# Step 1: Rename EIVE columns (remove hyphens for SQL compatibility)
cat("1. Renaming EIVE columns (remove hyphens)...\n")
plants_sql <- plants %>%
  rename(
    # Main EIVE values
    EIVE_L = `EIVEres-L`,
    EIVE_M = `EIVEres-M`,
    EIVE_T = `EIVEres-T`,
    EIVE_N = `EIVEres-N`,
    EIVE_R = `EIVEres-R`,
    # Complete values
    EIVE_L_complete = `EIVEres-L_complete`,
    EIVE_M_complete = `EIVEres-M_complete`,
    EIVE_T_complete = `EIVEres-T_complete`,
    EIVE_N_complete = `EIVEres-N_complete`,
    EIVE_R_complete = `EIVEres-R_complete`,
    # Imputed flags
    EIVE_L_imputed = `EIVEres-L_imputed`,
    EIVE_M_imputed = `EIVEres-M_imputed`,
    EIVE_T_imputed = `EIVEres-T_imputed`,
    EIVE_N_imputed = `EIVEres-N_imputed`,
    EIVE_R_imputed = `EIVEres-R_imputed`,
    # Source
    EIVE_L_source = `EIVEres-L_source`,
    EIVE_M_source = `EIVEres-M_source`,
    EIVE_T_source = `EIVEres-T_source`,
    EIVE_N_source = `EIVEres-N_source`,
    EIVE_R_source = `EIVEres-R_source`
  )

# Step 2: Convert EIVE to numeric (they may be stored as VARCHAR)
cat("2. Converting EIVE columns to numeric...\n")
plants_sql <- plants_sql %>%
  mutate(
    EIVE_L = as.numeric(EIVE_L),
    EIVE_M = as.numeric(EIVE_M),
    EIVE_T = as.numeric(EIVE_T),
    EIVE_N = as.numeric(EIVE_N),
    EIVE_R = as.numeric(EIVE_R),
    EIVE_L_imputed = as.character(EIVE_L_imputed),
    EIVE_M_imputed = as.character(EIVE_M_imputed),
    EIVE_T_imputed = as.character(EIVE_T_imputed),
    EIVE_N_imputed = as.character(EIVE_N_imputed),
    EIVE_R_imputed = as.character(EIVE_R_imputed)
  )

# Step 3: Normalize CSR scores (0-100 → 0-1 for consistency)
cat("3. Normalizing CSR scores (0-100 → 0-1)...\n")
plants_sql <- plants_sql %>%
  mutate(
    C_norm = C / 100.0,
    S_norm = S / 100.0,
    R_norm = R / 100.0
  )

# Step 4: Add computed columns for common queries
cat("4. Adding computed columns...\n")
plants_sql <- plants_sql %>%
  mutate(
    # Maintenance level based on CSR strategy
    maintenance_level = case_when(
      S > 50 ~ "low",      # Stress-tolerators: low maintenance
      C > 50 ~ "high",     # Competitors: high maintenance
      TRUE ~ "medium"      # Ruderals or mixed: medium
    ),

    # Boolean flags for common filters
    drought_tolerant = S > 60,
    fast_growing = R > 60,
    shade_tolerant = EIVE_L < 4,
    full_sun = EIVE_L > 7,
    nitrogen_lover = EIVE_N > 7,
    low_nitrogen = EIVE_N < 4,
    acid_soil = EIVE_R < 4,
    alkaline_soil = EIVE_R > 7,
    wet_soil = EIVE_M > 7,
    dry_soil = EIVE_M < 4
  )

# Step 5: Ensure integer types for counts
cat("5. Converting count columns to integers...\n")
# Find columns that are likely counts (end with _count or _rating)
count_cols <- grep("_count$", names(plants_sql), value = TRUE)
rating_cols <- grep("_rating$", names(plants_sql), value = TRUE)

for (col in count_cols) {
  if (col %in% names(plants_sql)) {
    plants_sql[[col]] <- as.integer(plants_sql[[col]])
  }
}

# Step 6: Select and order key columns for DataFusion
cat("6. Selecting final column set...\n")

# Core identifiers
id_cols <- c("wfo_taxon_id", "wfo_scientific_name", "family", "genus")

# EIVE indicators
eive_cols <- c("EIVE_L", "EIVE_M", "EIVE_T", "EIVE_N", "EIVE_R",
               "EIVE_L_complete", "EIVE_M_complete", "EIVE_T_complete",
               "EIVE_N_complete", "EIVE_R_complete")

# CSR strategy
csr_cols <- c("C", "S", "R", "C_norm", "S_norm", "R_norm")

# Computed flags
computed_cols <- c("maintenance_level", "drought_tolerant", "fast_growing",
                   "shade_tolerant", "full_sun", "nitrogen_lover", "low_nitrogen",
                   "acid_soil", "alkaline_soil", "wet_soil", "dry_soil")

# Ecosystem services
ecosystem_cols <- grep("^(npp|decomposition|nutrient|carbon|erosion)_(rating|confidence)$",
                       names(plants_sql), value = TRUE)

# Nitrogen fixation
nitrogen_cols <- c("nitrogen_fixation_rating", "nitrogen_fixation_confidence",
                   "nitrogen_fixation_has_try")

# Köppen climate
koppen_cols <- grep("koppen", names(plants_sql), value = TRUE, ignore.case = TRUE)

# Vernacular names (select major languages only for searchability)
major_languages <- c("en", "es", "fr", "de", "it", "pt", "nl", "zh", "ja", "ar")
vernacular_cols <- paste0("vernacular_name_", major_languages)
vernacular_cols <- c(vernacular_cols[vernacular_cols %in% names(plants_sql)], "vernacular_source")

# Traits (log-transformed and original)
trait_cols <- c("logLA", "logNmass", "logLDMC", "logSLA", "logH", "logSM",
                "LA", "LDMC", "SLA", "height_m")

# TRY categorical traits
try_cols <- grep("^try_", names(plants_sql), value = TRUE)

# Life form
life_form_cols <- c("life_form_simple")

# Combine all
selected_cols <- c(id_cols, eive_cols, csr_cols, computed_cols,
                   ecosystem_cols, nitrogen_cols, koppen_cols,
                   vernacular_cols, trait_cols, try_cols, life_form_cols)

# Keep only columns that exist
selected_cols <- selected_cols[selected_cols %in% names(plants_sql)]

plants_final <- plants_sql %>%
  select(all_of(selected_cols))

cat("  → Final schema:", ncol(plants_final), "columns\n\n")

# Step 7: Write parquet with optimal compression
cat("================================================================================\n")
cat("EXPORT TO PARQUET\n")
cat("================================================================================\n\n")

cat("Writing to:", output_file, "\n")

# Ensure output directory exists
dir.create(dirname(output_file), showWarnings = FALSE, recursive = TRUE)

write_parquet(
  plants_final,
  output_file,
  compression = "zstd",
  compression_level = 9,
  use_dictionary = TRUE  # Enable dictionary encoding for categorical columns
)

# Verify output
output_size_mb <- file.size(output_file) / 1024 / 1024
cat("✓ Export complete\n")
cat("  →", nrow(plants_final), "plants\n")
cat("  →", ncol(plants_final), "columns\n")
cat("  → File size:", round(output_size_mb, 2), "MB\n\n")

cat("SQL-friendly features:\n")
cat("  - Column names: No hyphens (EIVE_L instead of EIVEres-L)\n")
cat("  - CSR normalized: 0-1 scale (C_norm, S_norm, R_norm)\n")
cat("  - Computed columns: maintenance_level, drought_tolerant, etc.\n")
cat("  - Type-safe: Integers for counts, doubles for scores\n")
cat("  - Compressed: ZSTD level 9 + dictionary encoding\n\n")

cat("================================================================================\n")
cat("READY FOR DATAFUSION QUERY ENGINE\n")
cat("================================================================================\n")
