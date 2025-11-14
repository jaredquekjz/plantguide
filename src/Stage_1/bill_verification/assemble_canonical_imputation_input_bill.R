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
  library(arrow)
  library(dplyr)
  library(readr)
})

cat("========================================================================\n")
cat("Bill's Verification: Assemble Canonical Imputation Input (736 columns)\n")
cat("========================================================================\n\n")

# ========================================================================
# OUTPUT DIRECTORY SETUP
# ========================================================================
# Create modelling output directory for canonical imputation input dataset
# Use auto-detected OUTPUT_DIR for cross-platform compatibility
output_dir <- file.path(OUTPUT_DIR, "modelling")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# ==============================================================================
# STEP 1: LOAD BASE SHORTLIST (2 columns)
# ==============================================================================
# Load the 11,711 species base list with IDs and scientific names
# This serves as the skeleton for all subsequent joins (left joins preserve all base species)
# Base list criteria: species with GBIF occurrence count >= 30
cat("[1/10] Loading base shortlist...\n")
# Use auto-detected OUTPUT_DIR for cross-platform compatibility
shortlist <- read_parquet(file.path(OUTPUT_DIR, "shipley_checks", "stage1_shortlist_with_gbif_ge30_R.parquet"))

# Extract just the ID and scientific name columns (2 columns)
# wfo_taxon_id: unique WFO identifier for each taxon
# canonical_name: scientific name without authorship
base <- shortlist %>%
  select(wfo_taxon_id, wfo_scientific_name = canonical_name)

cat("  ✓ Base: ", nrow(base), " species × ", ncol(base), " columns\n", sep="")

# ==============================================================================
# STEP 2: EXTRACT ENVIRONMENTAL QUANTILES (624 columns)
# ==============================================================================
# Load species-level climate, soil, and agroclimate quantiles
# Each variable has 4 quantiles: q05, q50 (median), q95, iqr (interquartile range)
# Quantiles summarize the environmental niche of each species based on GBIF occurrences
# These serve as predictors in imputation models (environmental signal)
cat("\n[2/10] Extracting environmental quantiles (q05/q50/q95/iqr)...\n")

# WorldClim climate variables: 63 vars × 4 quantiles = 252 columns
# Variables include: temperature, precipitation, solar radiation, wind, vapor pressure
# Use auto-detected OUTPUT_DIR for cross-platform compatibility
wc_all <- read_parquet(file.path(OUTPUT_DIR, "shipley_checks", "worldclim_species_quantiles_R.parquet")) %>%
  select(wfo_taxon_id, ends_with("_q05"), ends_with("_q50"),
         ends_with("_q95"), ends_with("_iqr"))
cat("  ✓ WorldClim: ", ncol(wc_all) - 1, " quantile columns (63 vars × 4)\n", sep="")

# SoilGrids soil variables: 42 vars × 4 quantiles = 168 columns
# Variables include: pH, nitrogen, organic carbon, texture (clay/sand/silt), bulk density
sg_all <- read_parquet(file.path(OUTPUT_DIR, "shipley_checks", "soilgrids_species_quantiles_R.parquet")) %>%
  select(wfo_taxon_id, ends_with("_q05"), ends_with("_q50"),
         ends_with("_q95"), ends_with("_iqr"))
cat("  ✓ SoilGrids: ", ncol(sg_all) - 1, " quantile columns (42 vars × 4)\n", sep="")

# Agroclim agroclimatic variables: 51 vars × 4 quantiles = 204 columns
# Variables include: growing degree days, frost days, aridity indices
ac_all <- read_parquet(file.path(OUTPUT_DIR, "shipley_checks", "agroclime_species_quantiles_R.parquet")) %>%
  select(wfo_taxon_id, ends_with("_q05"), ends_with("_q50"),
         ends_with("_q95"), ends_with("_iqr"))
cat("  ✓ Agroclim: ", ncol(ac_all) - 1, " quantile columns (51 vars × 4)\n", sep="")

# Merge all environmental quantiles using left joins
# 252 (WorldClim) + 168 (SoilGrids) + 204 (Agroclim) = 624 columns
env_quantiles <- wc_all %>%
  left_join(sg_all, by = "wfo_taxon_id") %>%
  left_join(ac_all, by = "wfo_taxon_id")

cat("  ✓ Total env quantiles: ", ncol(env_quantiles) - 1, " columns\n", sep="")

# ==============================================================================
# STEP 3: EXTRACT RAW TRAITS FROM TRY ENHANCED (6 raw traits)
# ==============================================================================
# Load TRY database traits: leaf area, Nmass, LDMC, LMA, height, seed mass
# These will be aggregated to species level and used to compute canonical log traits
# CRITICAL: Raw traits will be DROPPED before output (anti-leakage protection)
# Only log-transformed versions will remain in final dataset
cat("\n[3/10] Extracting TRY Enhanced traits...\n")
# Use auto-detected OUTPUT_DIR for cross-platform compatibility
try_enhanced <- read_parquet(file.path(OUTPUT_DIR, "wfo_verification", "tryenhanced_worldflora_enriched.parquet")) %>%
  filter(!is.na(wfo_taxon_id))

# Aggregate to species level using median (robust to outliers and multiple measurements)
# Median preferred over mean for trait data with skewed distributions
# Convert to numeric first to handle any string/factor values from parquet
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
  # Convert NaN (from empty groups with all NA) to NA for consistency
  mutate(across(where(is.numeric), ~ifelse(is.nan(.), NA, .)))

cat("  ✓ TRY traits: ", nrow(try_traits), " species\n", sep="")

# ==============================================================================
# STEP 4: EXTRACT AUSTRAITS FOR SLA FALLBACK
# ==============================================================================
# AusTraits provides supplementary trait data, especially for Australian species
# Used as fallback when TRY data is missing (waterfall approach: TRY → AusTraits)
# Particularly important for SLA which has better coverage with AusTraits supplement
# Key traits: leaf_mass_per_area (LMA), LDMC, plant height, seed mass
cat("\n[4/10] Extracting AusTraits for SLA fallback...\n")
# Use auto-detected OUTPUT_DIR for cross-platform compatibility
austraits <- read_parquet(file.path(OUTPUT_DIR, "wfo_verification", "austraits_traits_worldflora_enriched.parquet")) %>%
  filter(!is.na(wfo_taxon_id))

# Extract leaf_mass_per_area (LMA) for computing SLA
# SLA = 1000 / LMA (conversion from g/m² to mm²/mg)
# Filter for positive values only (negative LMA is physically impossible)
aust_sla <- austraits %>%
  filter(trait_name == "leaf_mass_per_area") %>%
  mutate(value_numeric = as.numeric(value)) %>%
  filter(!is.na(value_numeric), value_numeric > 0) %>%
  group_by(wfo_taxon_id) %>%
  summarise(aust_lma_g_m2 = median(value_numeric, na.rm = TRUE), .groups = "drop")

# Extract other traits for fallback (same pattern as LMA)
# LDMC (leaf dry matter content): ratio of dry to fresh leaf mass
aust_ldmc <- austraits %>%
  filter(trait_name == "leaf_dry_matter_content") %>%
  mutate(value_numeric = as.numeric(value)) %>%
  filter(!is.na(value_numeric), value_numeric > 0) %>%
  group_by(wfo_taxon_id) %>%
  summarise(aust_ldmc_g_g = median(value_numeric, na.rm = TRUE), .groups = "drop")

# Plant height: maximum vegetative height (meters)
aust_height <- austraits %>%
  filter(trait_name == "plant_height") %>%
  mutate(value_numeric = as.numeric(value)) %>%
  filter(!is.na(value_numeric), value_numeric > 0) %>%
  group_by(wfo_taxon_id) %>%
  summarise(aust_plant_height_m = median(value_numeric, na.rm = TRUE), .groups = "drop")

# Seed dry mass: mass of single seed or diaspore (milligrams)
aust_seed <- austraits %>%
  filter(trait_name == "seed_dry_mass") %>%
  mutate(value_numeric = as.numeric(value)) %>%
  filter(!is.na(value_numeric), value_numeric > 0) %>%
  group_by(wfo_taxon_id) %>%
  summarise(aust_seed_mass_mg = median(value_numeric, na.rm = TRUE), .groups = "drop")

# Merge all AusTraits data using full joins (preserves all species with any trait)
# Some species may have only one trait, others may have multiple
aust_traits <- aust_sla %>%
  full_join(aust_ldmc, by = "wfo_taxon_id") %>%
  full_join(aust_height, by = "wfo_taxon_id") %>%
  full_join(aust_seed, by = "wfo_taxon_id")

cat("  ✓ AusTraits SLA fallback: ", nrow(aust_sla), " species\n", sep="")

# ==============================================================================
# STEP 5: CANONICAL SLA WATERFALL + LOG TRANSFORMS (6 log columns)
# ==============================================================================
# Compute canonical trait values using waterfall logic (TRY → AusTraits)
# Then apply log transformation (required for imputation model normality)
# Waterfall approach: prioritize TRY (larger database), fallback to AusTraits
# CRITICAL: ALL raw trait columns will be dropped (anti-leakage protection)
cat("\n[5/10] Computing canonical SLA waterfall and log transforms...\n")

# Merge TRY + AusTraits raw traits using full join
# Full join ensures no species are lost (some may have only TRY or only AusTraits)
traits_combined <- try_traits %>%
  full_join(aust_traits, by = "wfo_taxon_id")

# Canonical SLA calculation + log transforms for all 6 traits
# Process: raw trait → waterfall logic → canonical value → log transform
traits_combined <- traits_combined %>%
  mutate(
    # Priority 1: TRY SLA (derived from LMA)
    # SLA (specific leaf area) = 1000 / LMA (leaf mass per area)
    # Unit conversion: g/m² → mm²/mg (multiply by 1000)
    try_sla_mm2_mg = ifelse(!is.na(try_lma_g_m2) & try_lma_g_m2 > 0, 1000.0 / try_lma_g_m2, NA),

    # Priority 2: AusTraits SLA (derived from LMA)
    # Same calculation as TRY, but from AusTraits LMA values
    aust_sla_mm2_mg = ifelse(!is.na(aust_lma_g_m2) & aust_lma_g_m2 > 0, 1000.0 / aust_lma_g_m2, NA),

    # Canonical SLA (waterfall: try_sla → aust_sla)
    # Use TRY if available, otherwise fallback to AusTraits
    # This maximizes coverage while prioritizing larger database
    sla_mm2_mg = case_when(
      !is.na(try_sla_mm2_mg) ~ try_sla_mm2_mg,
      !is.na(aust_sla_mm2_mg) ~ aust_sla_mm2_mg,
      TRUE ~ NA_real_
    ),

    # Canonical for other traits (TRY priority, AusTraits fallback)
    # coalesce() returns first non-NA value
    leaf_area_mm2 = coalesce(try_leaf_area_mm2, NA_real_),  # No AusTraits fallback available
    nmass_mg_g = coalesce(try_nmass_mg_g, NA_real_),        # No AusTraits fallback available
    ldmc_g_g = coalesce(try_ldmc_g_g, aust_ldmc_g_g),       # Has AusTraits fallback
    plant_height_m = coalesce(try_plant_height_m, aust_plant_height_m),  # Has fallback
    seed_mass_mg = coalesce(try_seed_mass_mg, aust_seed_mass_mg),        # Has fallback

    # Compute log transforms (natural log) for all 6 traits
    # Log transformation normalizes right-skewed distributions typical of trait data
    # This improves imputation model performance and meets normality assumptions
    # Check for positive values before log (log of negative/zero is undefined)
    logLA = ifelse(!is.na(leaf_area_mm2) & leaf_area_mm2 > 0, log(leaf_area_mm2), NA),
    logNmass = ifelse(!is.na(nmass_mg_g) & nmass_mg_g > 0, log(nmass_mg_g), NA),
    logLDMC = ifelse(!is.na(ldmc_g_g) & ldmc_g_g > 0, log(ldmc_g_g), NA),
    logSLA = ifelse(!is.na(sla_mm2_mg) & sla_mm2_mg > 0, log(sla_mm2_mg), NA),
    logH = ifelse(!is.na(plant_height_m) & plant_height_m > 0, log(plant_height_m), NA),
    logSM = ifelse(!is.na(seed_mass_mg) & seed_mass_mg > 0, log(seed_mass_mg), NA)
  )

# ANTI-LEAKAGE: Keep only log transforms, drop ALL raw traits
# Raw traits (leaf_area_mm2, sla_mm2_mg, etc.) must NOT be in final dataset
# If present, imputation model could "cheat" by using raw values instead of learning
# Only log-transformed versions allowed (these will be imputed, then back-transformed)
log_transforms <- traits_combined %>%
  select(wfo_taxon_id, logLA, logNmass, logLDMC, logSLA, logH, logSM)

# Report coverage for key trait (logSLA)
# SLA is one of the most important traits, so track its coverage
logSLA_coverage <- sum(!is.na(log_transforms$logSLA))
cat("  ✓ logSLA coverage: ", logSLA_coverage, " / ", nrow(log_transforms),
    " (", sprintf("%.1f%%", 100 * logSLA_coverage / nrow(log_transforms)), ")\n", sep="")

# ==============================================================================
# STEP 6: EXTRACT CATEGORICAL TRAITS (7 columns)
# ==============================================================================
# Load categorical plant traits from TRY database
# These capture qualitative plant characteristics (not continuous values)
# Used as predictors in imputation models (taxonomic/functional signal)
# Total: 7 categorical traits (4 from Enhanced + 3 from Selected)
cat("\n[6/10] Extracting categorical traits...\n")

# From TRY Enhanced (4 categorical traits)
# Extract first non-NA value for each species (simple aggregation)
# first() returns first occurrence, which is sufficient for categorical data
try_cat <- try_enhanced %>%
  group_by(wfo_taxon_id) %>%
  summarise(
    try_woodiness = first(Woodiness[!is.na(Woodiness)]),                    # woody vs herbaceous
    try_growth_form = first(`Growth Form`[!is.na(`Growth Form`)]),          # tree, shrub, herb, etc.
    try_habitat_adaptation = first(`Adaptation to terrestrial or aquatic habitats`[!is.na(`Adaptation to terrestrial or aquatic habitats`)]),  # terrestrial vs aquatic
    try_leaf_type = first(`Leaf type`[!is.na(`Leaf type`)]),                # simple vs compound
    .groups = "drop"
  )

cat("  ✓ TRY Enhanced categorical: 4 traits\n")

# From TRY Selected Traits (3 categorical)
# These require standardization from free-text values in OrigValueStr
# Use auto-detected OUTPUT_DIR for cross-platform compatibility
try_selected <- read_parquet(file.path(OUTPUT_DIR, "wfo_verification", "try_selected_traits_worldflora_enriched.parquet")) %>%
  filter(!is.na(wfo_taxon_id))

# TraitID 37: Leaf phenology (evergreen, deciduous, semi-deciduous)
# Standardize from various text representations using pattern matching
# tolower() and trimws() normalize string format before matching
phenology <- try_selected %>%
  filter(TraitID == 37) %>%
  mutate(StdValue_std = tolower(trimws(OrigValueStr))) %>%
  mutate(phenology_std = case_when(
    grepl("evergreen", StdValue_std) ~ "evergreen",        # matches "Evergreen", "evergreen", etc.
    grepl("deciduous", StdValue_std) ~ "deciduous",        # matches "Deciduous", "deciduous", etc.
    grepl("semi", StdValue_std) ~ "semi_deciduous",        # matches "Semi-deciduous", "semi deciduous", etc.
    TRUE ~ NA_character_
  )) %>%
  filter(!is.na(phenology_std)) %>%
  group_by(wfo_taxon_id) %>%
  summarise(try_leaf_phenology = first(phenology_std), .groups = "drop")

# TraitID 22: Photosynthesis pathway (C3, C4, CAM, mixed)
# Standardize pathway classifications from free-text values
# toupper() normalizes to uppercase for consistent matching
photosynthesis <- try_selected %>%
  filter(TraitID == 22) %>%
  mutate(StdValue_std = toupper(trimws(OrigValueStr))) %>%
  mutate(photo_std = case_when(
    StdValue_std %in% c("C3", "3", "C3?") ~ "C3",              # C3 photosynthesis (most common)
    StdValue_std %in% c("C4", "4", "C4?") ~ "C4",              # C4 photosynthesis (grasses, tropical)
    StdValue_std == "CAM" ~ "CAM",                              # CAM photosynthesis (succulents)
    StdValue_std %in% c("C3/C4", "C3-C4") ~ "C3_C4",           # Mixed C3-C4 (rare)
    StdValue_std %in% c("C3/CAM", "C3-CAM") ~ "C3_CAM",        # Mixed C3-CAM (rare)
    TRUE ~ NA_character_
  )) %>%
  filter(!is.na(photo_std)) %>%
  group_by(wfo_taxon_id) %>%
  summarise(try_photosynthesis_pathway = first(photo_std), .groups = "drop")

# TraitID 7: Mycorrhiza type (AM, EM, NM, ericoid, orchid, mixed)
# Standardize mycorrhizal association types from free-text values
# Complex logic handles mixed associations and exclusions
mycorrhiza <- try_selected %>%
  filter(TraitID == 7) %>%
  mutate(StdValue_std = toupper(trimws(OrigValueStr))) %>%
  mutate(myc_std = case_when(
    grepl("AM|ARBUSCULAR", StdValue_std) & !grepl("EM|ECTO", StdValue_std) ~ "AM",   # Arbuscular mycorrhiza only
    grepl("EM|ECTO", StdValue_std) & !grepl("AM|ARBUSCULAR", StdValue_std) ~ "EM",   # Ectomycorrhiza only
    grepl("NM|NON", StdValue_std) & !grepl("AM", StdValue_std) ~ "NM",               # Non-mycorrhizal
    grepl("ERIC", StdValue_std) ~ "ericoid",                                          # Ericoid mycorrhiza
    grepl("ORCH", StdValue_std) ~ "orchid",                                           # Orchid mycorrhiza
    grepl("AM", StdValue_std) & grepl("EM", StdValue_std) ~ "mixed",                 # Mixed AM+EM
    TRUE ~ NA_character_
  )) %>%
  filter(!is.na(myc_std)) %>%
  group_by(wfo_taxon_id) %>%
  summarise(try_mycorrhiza_type = first(myc_std), .groups = "drop")

cat("  ✓ TRY Selected categorical: 3 traits\n")

# Merge all categorical traits using full joins
# Total: 7 categorical traits (4 from Enhanced + 3 from Selected)
# Full joins preserve species that have only some categorical traits
categorical_7 <- try_cat %>%
  full_join(phenology, by = "wfo_taxon_id") %>%
  full_join(photosynthesis, by = "wfo_taxon_id") %>%
  full_join(mycorrhiza, by = "wfo_taxon_id")

cat("  ✓ Total categorical: ", ncol(categorical_7) - 1, " traits\n", sep="")

# ==============================================================================
# STEP 7: EXTRACT EIVE INDICATORS (5 columns)
# ==============================================================================
# EIVE = Extended Indicator Values for Europe
# Ecological indicator values representing environmental preferences
# 5 indicators: Light, Temperature, Moisture, Nitrogen, Reaction (pH)
# These will be used as response variables in later analysis (what we're trying to predict)
# Based on Ellenberg indicator values extended across European flora
cat("\n[7/10] Extracting EIVE indicators...\n")
# Use auto-detected OUTPUT_DIR for cross-platform compatibility
eive <- read_parquet(file.path(OUTPUT_DIR, "wfo_verification", "eive_worldflora_enriched.parquet")) %>%
  filter(!is.na(wfo_taxon_id)) %>%
  group_by(wfo_taxon_id) %>%
  summarise(
    `EIVEres-L` = first(`EIVEres-L`[!is.na(`EIVEres-L`)]),  # Light: shade tolerance (1=deep shade, 9=full sun)
    `EIVEres-T` = first(`EIVEres-T`[!is.na(`EIVEres-T`)]),  # Temperature: thermal preference (1=cold, 9=warm)
    `EIVEres-M` = first(`EIVEres-M`[!is.na(`EIVEres-M`)]),  # Moisture: water availability (1=dry, 9=wet/aquatic)
    `EIVEres-N` = first(`EIVEres-N`[!is.na(`EIVEres-N`)]),  # Nitrogen: soil fertility (1=infertile, 9=eutrophic)
    `EIVEres-R` = first(`EIVEres-R`[!is.na(`EIVEres-R`)]),  # Reaction: soil pH (1=acidic, 9=basic/calcareous)
    .groups = "drop"
  )

eive_coverage <- nrow(eive)
cat("  ✓ EIVE coverage: ", eive_coverage, " species with at least one indicator\n", sep="")

# ==============================================================================
# STEP 8: LOAD PHYLOGENETIC EIGENVECTORS (92 columns)
# ==============================================================================
# Load eigenvectors from Phase 3 phylogenetic analysis (extract_phylo_eigenvectors_bill.R)
# Eigenvectors capture phylogenetic signal (evolutionary relationships)
# Used as predictors in imputation models to account for trait conservatism
# 92 eigenvectors selected by broken stick rule (explaining ~90% of phylogenetic variance)
cat("\n[8/10] Loading phylogenetic eigenvectors...\n")
# Use auto-detected OUTPUT_DIR for cross-platform compatibility
phylo <- read_csv(file.path(OUTPUT_DIR, "modelling", "phylo_eigenvectors_11711_bill.csv"),
                  show_col_types = FALSE) %>%
  select(wfo_taxon_id, starts_with("phylo_ev"))

# Count species with complete eigenvector data (~11,010 species)
# ~700 species lack eigenvectors (no phylogenetic placement)
phylo_coverage <- sum(complete.cases(phylo[, -1]))
cat("  ✓ Phylo eigenvectors: ", ncol(phylo) - 1, " eigenvectors\n", sep="")
cat("  ✓ Phylo coverage: ", phylo_coverage, " / ", nrow(phylo),
    " (", sprintf("%.1f%%", 100 * phylo_coverage / nrow(phylo)), ")\n", sep="")

# ==============================================================================
# STEP 9: MERGE ALL COMPONENTS
# ==============================================================================
# Combine all data sources into final canonical imputation input dataset
# Uses left joins to preserve all 11,711 base species
# Missing values (NA) will be imputed by mixgb using available predictors
#
# Column structure breakdown:
#   - IDs: 2 (wfo_taxon_id, wfo_scientific_name)
#   - Categorical traits: 7 (woodiness, growth form, phenology, photosynthesis, etc.)
#   - Log traits: 6 (logLA, logNmass, logLDMC, logSLA, logH, logSM)
#   - Environmental quantiles: 624 (156 vars × 4 quantiles)
#   - EIVE indicators: 5 (Light, Temperature, Moisture, Nitrogen, Reaction)
#   - Phylo eigenvectors: 92 (selected by broken stick)
#   - TOTAL: 736 columns
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
# Perform critical checks before writing output
# 1. Verify expected dimensions (11,711 × 736)
# 2. Verify no raw trait leakage (anti-leakage check)
# 3. Write CSV output file

cat("\n[10/10] Verifying structure and writing output...\n")

# Verify dimensions: must have exactly 11,711 rows (all base species)
if (nrow(result) != 11711) {
  stop("ERROR: Expected 11,711 rows, got ", nrow(result))
}

# Verify dimensions: must have exactly 736 columns (see breakdown in Step 9)
if (ncol(result) != 736) {
  stop("ERROR: Expected 736 columns, got ", ncol(result))
}

# CRITICAL: Verify no raw trait leakage (anti-leakage verification)
# These columns must NOT be present in final dataset
# If present, imputation model could "cheat" by using raw values instead of learning
raw_traits <- c("leaf_area_mm2", "nmass_mg_g", "ldmc_g_g", "sla_mm2_mg",
                "plant_height_m", "seed_mass_mg", "try_lma_g_m2", "aust_lma_g_m2")
leakage <- intersect(raw_traits, names(result))
if (length(leakage) > 0) {
  stop("ERROR: Data leakage detected - raw traits found: ", paste(leakage, collapse=", "))
}

cat("  ✓ CRITICAL: No data leakage (all raw traits removed)\n")

# Write output CSV file
# Note: Uses output_dir from line 77 which is hardcoded relative path
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
