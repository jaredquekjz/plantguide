#!/usr/bin/env Rscript
#
# assemble_canonical_imputation_input_bill.R
#
# Purpose: Transform Bill's Phase 1/2/3 outputs to canonical imputation input (268 columns)
#
# Inputs (Bill's independent outputs):
#   - data/shipley_checks/stage1_shortlist_with_gbif_ge30_R.parquet (11,711 species base)
#   - data/shipley_checks/wfo_verification/tryenhanced_worldflora_enriched.parquet (traits + categorical)
#   - data/shipley_checks/wfo_verification/try_selected_traits_worldflora_enriched.parquet (categorical 3/7)
#   - data/shipley_checks/wfo_verification/austraits_traits_worldflora_enriched.parquet (SLA fallback)
#   - data/shipley_checks/wfo_verification/eive_worldflora_enriched.parquet (EIVE indicators)
#   - data/shipley_checks/worldclim_species_quantiles_R.parquet (ALL quantiles)
#   - data/shipley_checks/soilgrids_species_quantiles_R.parquet (ALL quantiles)
#   - data/shipley_checks/agroclime_species_quantiles_R.parquet (ALL quantiles)
#   - data/shipley_checks/modelling/phylo_eigenvectors_11711_bill.csv (92 phylo eigenvectors)
#
# Output:
#   - data/shipley_checks/modelling/canonical_imputation_input_11711_bill.csv (11,711 × 736)
#
# Run:
#   env R_LIBS_USER=/home/olier/ellenberg/.Rlib \
#     /usr/bin/Rscript src/Stage_1/bill_verification/assemble_canonical_imputation_input_bill.R

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
    # Scripts are in shipley_checks/src/Stage_X/bill_verification/
    repo_root <- normalizePath(file.path(dirname(script_path), "..", "..", ".."))
  } else {
    # Fallback: assume current directory is repo root
    repo_root <- normalizePath(getwd())
  }
  return(repo_root)
}

repo_root <- get_repo_root()
INPUT_DIR <- file.path(repo_root, "shipley_checks/input")
INTERMEDIATE_DIR <- file.path(repo_root, "shipley_checks/intermediate")
OUTPUT_DIR <- file.path(repo_root, "shipley_checks/output")

# Create output directories
dir.create(file.path(OUTPUT_DIR, "wfo_verification"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "stage3"), recursive = TRUE, showWarnings = FALSE)



suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(readr)
})

cat("========================================================================\n")
cat("Bill's Verification: Assemble Canonical Imputation Input (736 columns)\n")
cat("========================================================================\n\n")

# Output directory
output_dir <- "data/shipley_checks/modelling"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# ==============================================================================
# Step 1: Load Base Shortlist (2 columns)
# ==============================================================================

cat("[1/10] Loading base shortlist...\n")
shortlist <- read_parquet("data/shipley_checks/stage1_shortlist_with_gbif_ge30_R.parquet")
base <- shortlist %>%
  select(wfo_taxon_id, wfo_scientific_name = canonical_name)

cat("  ✓ Base: ", nrow(base), " species × ", ncol(base), " columns\n", sep="")

# ==============================================================================
# Step 2: Extract Environmental Quantiles (624 columns: q05/q50/q95/iqr)
# ==============================================================================

cat("\n[2/10] Extracting environmental quantiles (q05/q50/q95/iqr)...\n")

# WorldClim ALL quantiles
wc_all <- read_parquet("data/shipley_checks/worldclim_species_quantiles_R.parquet") %>%
  select(wfo_taxon_id, ends_with("_q05"), ends_with("_q50"),
         ends_with("_q95"), ends_with("_iqr"))
cat("  ✓ WorldClim: ", ncol(wc_all) - 1, " quantile columns (63 vars × 4)\n", sep="")

# SoilGrids ALL quantiles
sg_all <- read_parquet("data/shipley_checks/soilgrids_species_quantiles_R.parquet") %>%
  select(wfo_taxon_id, ends_with("_q05"), ends_with("_q50"),
         ends_with("_q95"), ends_with("_iqr"))
cat("  ✓ SoilGrids: ", ncol(sg_all) - 1, " quantile columns (42 vars × 4)\n", sep="")

# Agroclim ALL quantiles
ac_all <- read_parquet("data/shipley_checks/agroclime_species_quantiles_R.parquet") %>%
  select(wfo_taxon_id, ends_with("_q05"), ends_with("_q50"),
         ends_with("_q95"), ends_with("_iqr"))
cat("  ✓ Agroclim: ", ncol(ac_all) - 1, " quantile columns (51 vars × 4)\n", sep="")

# Merge environmental quantiles
env_quantiles <- wc_all %>%
  left_join(sg_all, by = "wfo_taxon_id") %>%
  left_join(ac_all, by = "wfo_taxon_id")

cat("  ✓ Total env quantiles: ", ncol(env_quantiles) - 1, " columns\n", sep="")

# ==============================================================================
# Step 3: Extract Raw Traits from TRY Enhanced (6 raw traits)
# ==============================================================================

cat("\n[3/10] Extracting TRY Enhanced traits...\n")
try_enhanced <- read_parquet("data/shipley_checks/wfo_verification/tryenhanced_worldflora_enriched.parquet") %>%
  filter(!is.na(wfo_taxon_id))

# Aggregate to species level (median) - convert to numeric first
try_traits <- try_enhanced %>%
  mutate(across(c(`Leaf area (mm2)`, `Nmass (mg/g)`, `LDMC (g/g)`,
                   `LMA (g/m2)`, `Plant height (m)`, `Diaspore mass (mg)`),
                as.numeric, .names = "{.col}")) %>%
  group_by(wfo_taxon_id) %>%
  summarise(
    try_leaf_area_mm2 = median(`Leaf area (mm2)`, na.rm = TRUE),
    try_nmass_mg_g = median(`Nmass (mg/g)`, na.rm = TRUE),
    try_ldmc_g_g = median(`LDMC (g/g)`, na.rm = TRUE),
    try_lma_g_m2 = median(`LMA (g/m2)`, na.rm = TRUE),
    try_plant_height_m = median(`Plant height (m)`, na.rm = TRUE),
    try_seed_mass_mg = median(`Diaspore mass (mg)`, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(across(where(is.numeric), ~ifelse(is.nan(.), NA, .)))

cat("  ✓ TRY traits: ", nrow(try_traits), " species\n", sep="")

# ==============================================================================
# Step 4: Extract AusTraits for SLA Fallback
# ==============================================================================

cat("\n[4/10] Extracting AusTraits for SLA fallback...\n")
austraits <- read_parquet("data/shipley_checks/wfo_verification/austraits_traits_worldflora_enriched.parquet") %>%
  filter(!is.na(wfo_taxon_id))

# leaf_mass_per_area for SLA
aust_sla <- austraits %>%
  filter(trait_name == "leaf_mass_per_area") %>%
  mutate(value_numeric = as.numeric(value)) %>%
  filter(!is.na(value_numeric), value_numeric > 0) %>%
  group_by(wfo_taxon_id) %>%
  summarise(aust_lma_g_m2 = median(value_numeric, na.rm = TRUE), .groups = "drop")

# Other AusTraits for fallback
aust_ldmc <- austraits %>%
  filter(trait_name == "leaf_dry_matter_content") %>%
  mutate(value_numeric = as.numeric(value)) %>%
  filter(!is.na(value_numeric), value_numeric > 0) %>%
  group_by(wfo_taxon_id) %>%
  summarise(aust_ldmc_g_g = median(value_numeric, na.rm = TRUE), .groups = "drop")

aust_height <- austraits %>%
  filter(trait_name == "plant_height") %>%
  mutate(value_numeric = as.numeric(value)) %>%
  filter(!is.na(value_numeric), value_numeric > 0) %>%
  group_by(wfo_taxon_id) %>%
  summarise(aust_plant_height_m = median(value_numeric, na.rm = TRUE), .groups = "drop")

aust_seed <- austraits %>%
  filter(trait_name == "seed_dry_mass") %>%
  mutate(value_numeric = as.numeric(value)) %>%
  filter(!is.na(value_numeric), value_numeric > 0) %>%
  group_by(wfo_taxon_id) %>%
  summarise(aust_seed_mass_mg = median(value_numeric, na.rm = TRUE), .groups = "drop")

# Merge AusTraits
aust_traits <- aust_sla %>%
  full_join(aust_ldmc, by = "wfo_taxon_id") %>%
  full_join(aust_height, by = "wfo_taxon_id") %>%
  full_join(aust_seed, by = "wfo_taxon_id")

cat("  ✓ AusTraits SLA fallback: ", nrow(aust_sla), " species\n", sep="")

# ==============================================================================
# Step 5: Canonical SLA Waterfall + Log Transforms (6 log columns)
# ==============================================================================

cat("\n[5/10] Computing canonical SLA waterfall and log transforms...\n")

# Merge TRY + AusTraits raw traits
traits_combined <- try_traits %>%
  full_join(aust_traits, by = "wfo_taxon_id")

# Canonical SLA calculation + log transforms
traits_combined <- traits_combined %>%
  mutate(
    # Priority 1: TRY SLA (derived from LMA)
    try_sla_mm2_mg = ifelse(!is.na(try_lma_g_m2) & try_lma_g_m2 > 0, 1000.0 / try_lma_g_m2, NA),

    # Priority 2: AusTraits SLA (derived from LMA)
    aust_sla_mm2_mg = ifelse(!is.na(aust_lma_g_m2) & aust_lma_g_m2 > 0, 1000.0 / aust_lma_g_m2, NA),

    # Canonical SLA (waterfall: try_sla → aust_sla)
    sla_mm2_mg = case_when(
      !is.na(try_sla_mm2_mg) ~ try_sla_mm2_mg,
      !is.na(aust_sla_mm2_mg) ~ aust_sla_mm2_mg,
      TRUE ~ NA_real_
    ),

    # Canonical for other traits (TRY priority, AusTraits fallback)
    leaf_area_mm2 = coalesce(try_leaf_area_mm2, NA_real_),
    nmass_mg_g = coalesce(try_nmass_mg_g, NA_real_),
    ldmc_g_g = coalesce(try_ldmc_g_g, aust_ldmc_g_g),
    plant_height_m = coalesce(try_plant_height_m, aust_plant_height_m),
    seed_mass_mg = coalesce(try_seed_mass_mg, aust_seed_mass_mg),

    # Compute log transforms
    logLA = ifelse(!is.na(leaf_area_mm2) & leaf_area_mm2 > 0, log(leaf_area_mm2), NA),
    logNmass = ifelse(!is.na(nmass_mg_g) & nmass_mg_g > 0, log(nmass_mg_g), NA),
    logLDMC = ifelse(!is.na(ldmc_g_g) & ldmc_g_g > 0, log(ldmc_g_g), NA),
    logSLA = ifelse(!is.na(sla_mm2_mg) & sla_mm2_mg > 0, log(sla_mm2_mg), NA),
    logH = ifelse(!is.na(plant_height_m) & plant_height_m > 0, log(plant_height_m), NA),
    logSM = ifelse(!is.na(seed_mass_mg) & seed_mass_mg > 0, log(seed_mass_mg), NA)
  )

# ANTI-LEAKAGE: Keep only log transforms, drop ALL raw traits
log_transforms <- traits_combined %>%
  select(wfo_taxon_id, logLA, logNmass, logLDMC, logSLA, logH, logSM)

# Report coverage
logSLA_coverage <- sum(!is.na(log_transforms$logSLA))
cat("  ✓ logSLA coverage: ", logSLA_coverage, " / ", nrow(log_transforms),
    " (", sprintf("%.1f%%", 100 * logSLA_coverage / nrow(log_transforms)), ")\n", sep="")

# ==============================================================================
# Step 6: Extract Categorical Traits (7 columns)
# ==============================================================================

cat("\n[6/10] Extracting categorical traits...\n")

# From TRY Enhanced (4 categorical)
try_cat <- try_enhanced %>%
  group_by(wfo_taxon_id) %>%
  summarise(
    try_woodiness = first(Woodiness[!is.na(Woodiness)]),
    try_growth_form = first(`Growth Form`[!is.na(`Growth Form`)]),
    try_habitat_adaptation = first(`Adaptation to terrestrial or aquatic habitats`[!is.na(`Adaptation to terrestrial or aquatic habitats`)]),
    try_leaf_type = first(`Leaf type`[!is.na(`Leaf type`)]),
    .groups = "drop"
  )

cat("  ✓ TRY Enhanced categorical: 4 traits\n")

# From TRY Selected Traits (3 categorical)
try_selected <- read_parquet("data/shipley_checks/wfo_verification/try_selected_traits_worldflora_enriched.parquet") %>%
  filter(!is.na(wfo_taxon_id))

# TraitID 37: Leaf phenology
phenology <- try_selected %>%
  filter(TraitID == 37) %>%
  mutate(StdValue_std = tolower(trimws(OrigValueStr))) %>%
  mutate(phenology_std = case_when(
    grepl("evergreen", StdValue_std) ~ "evergreen",
    grepl("deciduous", StdValue_std) ~ "deciduous",
    grepl("semi", StdValue_std) ~ "semi_deciduous",
    TRUE ~ NA_character_
  )) %>%
  filter(!is.na(phenology_std)) %>%
  group_by(wfo_taxon_id) %>%
  summarise(try_leaf_phenology = first(phenology_std), .groups = "drop")

# TraitID 22: Photosynthesis pathway
photosynthesis <- try_selected %>%
  filter(TraitID == 22) %>%
  mutate(StdValue_std = toupper(trimws(OrigValueStr))) %>%
  mutate(photo_std = case_when(
    StdValue_std %in% c("C3", "3", "C3?") ~ "C3",
    StdValue_std %in% c("C4", "4", "C4?") ~ "C4",
    StdValue_std == "CAM" ~ "CAM",
    StdValue_std %in% c("C3/C4", "C3-C4") ~ "C3_C4",
    StdValue_std %in% c("C3/CAM", "C3-CAM") ~ "C3_CAM",
    TRUE ~ NA_character_
  )) %>%
  filter(!is.na(photo_std)) %>%
  group_by(wfo_taxon_id) %>%
  summarise(try_photosynthesis_pathway = first(photo_std), .groups = "drop")

# TraitID 7: Mycorrhiza type
mycorrhiza <- try_selected %>%
  filter(TraitID == 7) %>%
  mutate(StdValue_std = toupper(trimws(OrigValueStr))) %>%
  mutate(myc_std = case_when(
    grepl("AM|ARBUSCULAR", StdValue_std) & !grepl("EM|ECTO", StdValue_std) ~ "AM",
    grepl("EM|ECTO", StdValue_std) & !grepl("AM|ARBUSCULAR", StdValue_std) ~ "EM",
    grepl("NM|NON", StdValue_std) & !grepl("AM", StdValue_std) ~ "NM",
    grepl("ERIC", StdValue_std) ~ "ericoid",
    grepl("ORCH", StdValue_std) ~ "orchid",
    grepl("AM", StdValue_std) & grepl("EM", StdValue_std) ~ "mixed",
    TRUE ~ NA_character_
  )) %>%
  filter(!is.na(myc_std)) %>%
  group_by(wfo_taxon_id) %>%
  summarise(try_mycorrhiza_type = first(myc_std), .groups = "drop")

cat("  ✓ TRY Selected categorical: 3 traits\n")

# Merge all categorical (7 total)
categorical_7 <- try_cat %>%
  full_join(phenology, by = "wfo_taxon_id") %>%
  full_join(photosynthesis, by = "wfo_taxon_id") %>%
  full_join(mycorrhiza, by = "wfo_taxon_id")

cat("  ✓ Total categorical: ", ncol(categorical_7) - 1, " traits\n", sep="")

# ==============================================================================
# Step 7: Extract EIVE Indicators (5 columns)
# ==============================================================================

cat("\n[7/10] Extracting EIVE indicators...\n")
eive <- read_parquet("data/shipley_checks/wfo_verification/eive_worldflora_enriched.parquet") %>%
  filter(!is.na(wfo_taxon_id)) %>%
  group_by(wfo_taxon_id) %>%
  summarise(
    `EIVEres-L` = first(`EIVEres-L`[!is.na(`EIVEres-L`)]),
    `EIVEres-T` = first(`EIVEres-T`[!is.na(`EIVEres-T`)]),
    `EIVEres-M` = first(`EIVEres-M`[!is.na(`EIVEres-M`)]),
    `EIVEres-N` = first(`EIVEres-N`[!is.na(`EIVEres-N`)]),
    `EIVEres-R` = first(`EIVEres-R`[!is.na(`EIVEres-R`)]),
    .groups = "drop"
  )

eive_coverage <- nrow(eive)
cat("  ✓ EIVE coverage: ", eive_coverage, " species with at least one indicator\n", sep="")

# ==============================================================================
# Step 8: Load Phylogenetic Eigenvectors (92 columns)
# ==============================================================================

cat("\n[8/10] Loading phylogenetic eigenvectors...\n")
phylo <- read_csv("data/shipley_checks/modelling/phylo_eigenvectors_11711_bill.csv",
                  show_col_types = FALSE) %>%
  select(wfo_taxon_id, starts_with("phylo_ev"))

phylo_coverage <- sum(complete.cases(phylo[, -1]))
cat("  ✓ Phylo eigenvectors: ", ncol(phylo) - 1, " eigenvectors\n", sep="")
cat("  ✓ Phylo coverage: ", phylo_coverage, " / ", nrow(phylo),
    " (", sprintf("%.1f%%", 100 * phylo_coverage / nrow(phylo)), ")\n", sep="")

# ==============================================================================
# Step 9: Merge All Components
# ==============================================================================

cat("\n[9/10] Merging all components...\n")
result <- base %>%
  left_join(categorical_7, by = "wfo_taxon_id") %>%
  left_join(log_transforms, by = "wfo_taxon_id") %>%
  left_join(env_quantiles, by = "wfo_taxon_id") %>%
  left_join(eive, by = "wfo_taxon_id") %>%
  left_join(phylo, by = "wfo_taxon_id")

cat("  ✓ Merged dataset: ", nrow(result), " species × ", ncol(result), " columns\n", sep="")

# ==============================================================================
# Step 10: Verify and Write Output
# ==============================================================================

cat("\n[10/10] Verifying structure and writing output...\n")

# Verify dimensions
if (nrow(result) != 11711) {
  stop("ERROR: Expected 11,711 rows, got ", nrow(result))
}

if (ncol(result) != 736) {
  stop("ERROR: Expected 736 columns, got ", ncol(result))
}

# Verify no raw trait leakage
raw_traits <- c("leaf_area_mm2", "nmass_mg_g", "ldmc_g_g", "sla_mm2_mg",
                "plant_height_m", "seed_mass_mg", "try_lma_g_m2", "aust_lma_g_m2")
leakage <- intersect(raw_traits, names(result))
if (length(leakage) > 0) {
  stop("ERROR: Data leakage detected - raw traits found: ", paste(leakage, collapse=", "))
}

cat("  ✓ CRITICAL: No data leakage (all raw traits removed)\n")

# Write output
output_path <- file.path(output_dir, "canonical_imputation_input_11711_bill.csv")
write_csv(result, output_path)

cat("  ✓ Written: ", output_path, "\n", sep="")
cat("  ✓ File size: ", sprintf("%.2f MB", file.size(output_path) / 1024^2), "\n", sep="")

# Summary
cat("\n", rep("=", 72), "\n", sep="")
cat("SUCCESS: Canonical imputation input assembled\n")
cat(rep("=", 72), "\n\n", sep="")

cat("Output:\n")
cat("  File: ", output_path, "\n", sep="")
cat("  Shape: ", nrow(result), " species × ", ncol(result), " columns\n\n", sep="")

cat("Column breakdown:\n")
cat("  IDs: 2\n")
cat("  Categorical traits: 7\n")
cat("  Log transforms: 6\n")
cat("  Environmental quantiles: 624 (156 vars × 4 quantiles)\n")
cat("    - q05: 156\n")
cat("    - q50: 156\n")
cat("    - q95: 156\n")
cat("    - iqr: 156\n")
cat("  EIVE indicators: 5\n")
cat("  Phylo eigenvectors: 92\n")
cat("  Total: 736\n\n")

cat("Key coverage:\n")
cat("  logSLA: ", logSLA_coverage, " / 11,711 (", sprintf("%.1f%%", 100 * logSLA_coverage / 11711), ")\n", sep="")
cat("  EIVE: ", eive_coverage, " / 11,711 (", sprintf("%.1f%%", 100 * eive_coverage / 11711), ")\n", sep="")
cat("  Phylo: ", phylo_coverage, " / 11,711 (", sprintf("%.1f%%", 100 * phylo_coverage / 11711), ")\n\n", sep="")

cat("Next steps:\n")
cat("  1. Run mixgb imputation on 6 log traits\n")
cat("  2. Merge imputed traits back to create final Stage 2 dataset\n")
cat("  3. Verify final dataset ready for EIVE prediction (11,711 species, 736 columns)\n")
