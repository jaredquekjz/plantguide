#!/usr/bin/env Rscript
################################################################################
# Bill Shipley Verification: Extract Plant Names from All 8 Datasets
################################################################################
# PURPOSE:
#   Extracts unique plant names from 8 source datasets (Duke, EIVE, Mabberly,
#   TRY Enhanced, AusTraits, GBIF, GloBI, TRY traits) for WorldFlora matching.
#   This is Phase 0 Step 1 of the verification pipeline.
#
# INPUTS:
#   - Duke ethnobotany parquet (input/duke_original.parquet)
#   - EIVE indicators parquet (input/eive_original.parquet)
#   - Mabberly genera parquet (input/mabberly_original.parquet)
#   - TRY Enhanced species parquet (input/tryenhanced_species_original.parquet)
#   - AusTraits taxa parquet (input/austraits_taxa.parquet)
#   - GBIF occurrences parquet (input/gbif_occurrence_plantae.parquet) - 5.4GB, streamed
#   - GloBI interactions parquet (input/globi_interactions_plants.parquet) - streamed
#   - TRY selected traits parquet (input/try_selected_traits.parquet)
#
# OUTPUTS:
#   - output/wfo_verification/duke_names_for_r.csv
#   - output/wfo_verification/eive_names_for_r.csv
#   - output/wfo_verification/mabberly_names_for_r.csv
#   - output/wfo_verification/tryenhanced_names_for_r.csv
#   - output/wfo_verification/austraits_names_for_r.csv
#   - output/wfo_verification/gbif_occurrence_names_for_r.tsv
#   - output/wfo_verification/globi_interactions_names_for_r.tsv
#   - output/wfo_verification/try_selected_traits_names_for_r.csv
#
# KEY OPERATIONS:
#   1. Extract distinct name columns from each dataset
#   2. Handle dataset-specific column structures (e.g., scientific_name vs TaxonConcept)
#   3. Stream large files (GBIF 5.4GB, GloBI) using Arrow to avoid memory issues
#   4. Deduplicate names within each dataset
#   5. Write CSV/TSV files for downstream WorldFlora matching
#
# MEMORY OPTIMIZATION:
#   - Uses Arrow streaming for GBIF (5.4GB) and GloBI datasets
#   - Filters and deduplicates before collecting to R memory
################################################################################

# ========================================================================
# AUTO-DETECTING PATHS (works on Windows/Linux/Mac, any location)
# ========================================================================
# This function automatically detects the repository root directory
# regardless of where the script is run from or which platform is used.
# Priority: env var > script location > current directory
get_repo_root <- function() {
  # First check if environment variable is set (from run_all_bill.R)
  # The master script sets BILL_REPO_ROOT for all child processes
  env_root <- Sys.getenv("BILL_REPO_ROOT", unset = NA)
  if (!is.na(env_root) && env_root != "") {
    return(normalizePath(env_root))
  }

  # Otherwise detect from script path using R's command-line arguments
  # This works when script is run via Rscript or source()
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    # Navigate up from script to repo root
    # Scripts are in src/Stage_X/bill_verification/
    # So we go up 3 levels: bill_verification -> Stage_X -> src -> repo_root
    repo_root <- normalizePath(file.path(dirname(script_path), "..", "..", ".."))
  } else {
    # Fallback: assume current directory is repo root
    # This is used when running interactively or in RStudio
    repo_root <- normalizePath(getwd())
  }
  return(repo_root)
}

repo_root <- get_repo_root()
# Construct all directory paths using file.path for cross-platform compatibility
# file.path() automatically uses correct separators (/ on Unix, \ on Windows)
INPUT_DIR <- file.path(repo_root, "input")
INTERMEDIATE_DIR <- file.path(repo_root, "intermediate")
OUTPUT_DIR <- file.path(repo_root, "output")

# Create output directories if they don't exist
# recursive = TRUE creates parent directories as needed
# showWarnings = FALSE suppresses "already exists" messages
dir.create(file.path(OUTPUT_DIR, "wfo_verification"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "stage3"), recursive = TRUE, showWarnings = FALSE)

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(dplyr)
})

output_dir <- file.path(OUTPUT_DIR, "wfo_verification")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cat("Bill Shipley Verification: Extracting names from 8 datasets\n")
cat("Output directory:", output_dir, "\n\n")

# ========================================================================
# DATASET 1: DUKE ETHNOBOTANY
# ========================================================================
# Extract unique plant names from Duke ethnobotany database
# Uses plant_key as primary identifier with scientific names
cat("[1/8] Extracting Duke names...\n")
duke <- read_parquet(file.path(INPUT_DIR, "duke_original.parquet"))

# Filter to rows with valid plant_key and extract relevant name columns
# plant_key: unique identifier for each plant
# scientific_name: primary scientific name
# taxonomy.taxon: alternative taxonomic name
# genus, species: taxonomic rank information
# Using !is.na() to exclude rows where plant_key is missing
duke_names <- unique(duke[!is.na(duke$plant_key),
                          c("plant_key", "scientific_name", "taxonomy.taxon", "genus", "species")])

# Rename column to match canonical naming convention (replace dot with underscore)
# This ensures consistency with DuckDB output format which doesn't allow dots in column names
# data.table::setnames modifies in-place (no copy made, more memory efficient)
setnames(duke_names, "taxonomy.taxon", "taxonomy_taxon")

# Write extracted names to CSV for WorldFlora matching
fwrite(duke_names, file.path(output_dir, "duke_names_for_r.csv"))
cat("      Wrote", nrow(duke_names), "Duke name records\n\n")

# ========================================================================
# DATASET 2: EIVE (ELLENBERG INDICATOR VALUES)
# ========================================================================
# Extract unique plant names from EIVE ecological indicator values database
# EIVE uses TaxonConcept as the primary taxonomic identifier
cat("[2/8] Extracting EIVE names...\n")
eive <- read_parquet(file.path(INPUT_DIR, "eive_original.parquet"))

# Filter to rows with valid, non-empty TaxonConcept
# TaxonConcept: full taxonomic name/concept
# TaxonRank: taxonomic rank (species, genus, etc.)
# AccordingTo: authority for the taxonomic concept
# UUID: unique identifier for the record
# Two-part filter: !is.na() checks for NULL/NA, nchar(trimws()) > 0 removes whitespace-only values
eive_names <- unique(eive[!is.na(eive$TaxonConcept) & nchar(trimws(eive$TaxonConcept)) > 0,
                           c("TaxonConcept", "TaxonRank", "AccordingTo", "UUID")])

# Write extracted names to CSV for WorldFlora matching
fwrite(eive_names, file.path(output_dir, "eive_names_for_r.csv"))
cat("      Wrote", nrow(eive_names), "EIVE name records\n\n")

# ========================================================================
# DATASET 3: MABBERLY'S PLANT-BOOK
# ========================================================================
# Extract unique genera from Mabberly's Plant-Book
# Mabberly is genus-level only (not species-level)
cat("[3/8] Extracting Mabberly names...\n")
mab <- read_parquet(file.path(INPUT_DIR, "mabberly_original.parquet"))

# Filter to rows with valid, non-empty Genus names
# Genus: genus name (this dataset is genus-level taxonomy)
# Family: family classification for the genus
mab_names <- unique(mab[!is.na(mab$Genus) & nchar(trimws(mab$Genus)) > 0,
                        c("Genus", "Family")])

# Write extracted names to CSV for WorldFlora matching
fwrite(mab_names, file.path(output_dir, "mabberly_names_for_r.csv"))
cat("      Wrote", nrow(mab_names), "Mabberly name records\n\n")

# ========================================================================
# DATASET 4: TRY ENHANCED (TRAIT DATABASE)
# ========================================================================
# Extract unique species from TRY Enhanced trait database
# Names are standardized against TPL (The Plant List)
cat("[4/8] Extracting TRY Enhanced names...\n")
try_enh <- read_parquet(file.path(INPUT_DIR, "tryenhanced_species_original.parquet"))

# Filter to rows with valid TPL-standardized species names
# "Species name standardized against TPL": species name validated against The Plant List
# Genus: genus classification
# Family: family classification
try_enh_names <- unique(try_enh[!is.na(try_enh$`Species name standardized against TPL`) &
                                  nchar(trimws(try_enh$`Species name standardized against TPL`)) > 0,
                                c("Species name standardized against TPL", "Genus", "Family")])

# Rename column to canonical format for consistency across datasets
setnames(try_enh_names, "Species name standardized against TPL", "SpeciesName")

# Write extracted names to CSV for WorldFlora matching
fwrite(try_enh_names, file.path(output_dir, "tryenhanced_names_for_r.csv"))
cat("      Wrote", nrow(try_enh_names), "TRY Enhanced name records\n\n")

# ========================================================================
# DATASET 5: AUSTRAITS (AUSTRALIAN PLANT TRAITS)
# ========================================================================
# Extract unique taxa from AusTraits plant trait database
# Focuses on Australian flora with comprehensive taxonomic metadata
cat("[5/8] Extracting AusTraits names...\n")
aus_taxa <- read_parquet(file.path(INPUT_DIR, "austraits_taxa.parquet"))

# Extract all taxonomic columns without filtering
# taxon_name: full scientific name
# taxon_rank: taxonomic rank (species, subspecies, variety, etc.)
# genus, family: higher taxonomic classifications
# taxonomic_status: accepted, synonym, etc.
# taxonomic_dataset: source of the taxonomic information
aus_names <- unique(aus_taxa[, c("taxon_name", "taxon_rank", "genus", "family",
                                  "taxonomic_status", "taxonomic_dataset")])

# Sort alphabetically by taxon name for easier verification
aus_names <- aus_names[order(aus_names$taxon_name), ]

# Write extracted names to CSV for WorldFlora matching
fwrite(aus_names, file.path(output_dir, "austraits_names_for_r.csv"))
cat("      Wrote", nrow(aus_names), "AusTraits name records\n\n")

# ========================================================================
# DATASET 6: GBIF OCCURRENCE DATA (LARGE FILE - 5.4GB)
# ========================================================================
# Extract unique plant names from GBIF occurrence database
# Uses Arrow streaming to handle large file without loading into memory
cat("[6/8] Extracting GBIF plant names...\n")
gbif_ds <- open_dataset(file.path(INPUT_DIR, "gbif_occurrence_plantae.parquet"))

# Stream processing: select, filter, deduplicate, then collect
# This processes data in chunks to avoid memory overflow
# scientificName: species name from occurrence records
# Arrow's lazy evaluation: operations are queued but not executed until collect()
# This allows Arrow to optimize the query plan and process data in batches
gbif_names <- gbif_ds %>%
  select(scientificName) %>%              # Select only needed column (reduces I/O)
  filter(!is.na(scientificName)) %>%      # Filter in-database (before loading to R)
  distinct() %>%                          # Deduplicate in-database (critical for memory)
  collect()                               # Execute query and pull results into R memory

# Convert to data.frame and rename column to match canonical format
gbif_names <- as.data.frame(gbif_names)
setnames(gbif_names, "scientificName", "SpeciesName")

# Write as TSV (tab-separated) for large dataset efficiency
fwrite(gbif_names, file.path(output_dir, "gbif_occurrence_names_for_r.tsv"), sep = "\t")
cat("      Wrote", nrow(gbif_names), "GBIF name records\n\n")

# ========================================================================
# DATASET 7: GLOBI PLANT INTERACTIONS
# ========================================================================
# Extract unique plant names from GloBI biotic interaction database
# Plants can be either interaction source OR target, so we extract both
# Uses Arrow streaming for efficient processing of large dataset
cat("[7/8] Extracting GloBI plant names...\n")
globi_ds <- open_dataset(file.path(INPUT_DIR, "globi_interactions_plants.parquet"))

# PART A: Extract plant names from SOURCE side of interactions
# Filter to source organisms in Kingdom Plantae
# In GloBI, interactions are directional: source -> interaction_type -> target
# Example: "Bee" -pollinates-> "Rose" (Rose is target)
source_names <- globi_ds %>%
  filter(sourceTaxonKingdomName == "Plantae", !is.na(sourceTaxonName)) %>%
  select(sourceTaxonName) %>%
  distinct() %>%
  collect()
source_names <- as.data.frame(source_names)
setnames(source_names, "sourceTaxonName", "SpeciesName")

# PART B: Extract plant names from TARGET side of interactions
# Filter to target organisms in Kingdom Plantae
# Example: "Caterpillar" -eats-> "Oak leaf" (Oak is target)
target_names <- globi_ds %>%
  filter(targetTaxonKingdomName == "Plantae", !is.na(targetTaxonName)) %>%
  select(targetTaxonName) %>%
  distinct() %>%
  collect()
target_names <- as.data.frame(target_names)
setnames(target_names, "targetTaxonName", "SpeciesName")

# Combine source and target names, then deduplicate
# A plant may appear as both source and target in different interactions
# Example: "Rose" could be pollen source AND herbivory target
globi_names <- unique(rbind(source_names, target_names))

# Write as TSV (tab-separated) for large dataset efficiency
fwrite(globi_names, file.path(output_dir, "globi_interactions_names_for_r.tsv"), sep = "\t")
cat("      Wrote", nrow(globi_names), "GloBI plant name records\n\n")

# ========================================================================
# DATASET 8: TRY SELECTED TRAITS
# ========================================================================
# Extract unique species from TRY trait database (selected traits subset)
# Contains both accepted species names and original submitted names
cat("[8/8] Extracting TRY trait names...\n")
try_traits <- read_parquet(file.path(INPUT_DIR, "try_selected_traits.parquet"))

# Filter to rows with valid AccSpeciesID (accepted species identifier)
# AccSpeciesID: unique identifier for accepted species
# AccSpeciesName: accepted species name (standardized)
# SpeciesName: original species name as submitted (may differ from accepted)
try_trait_names <- unique(try_traits[!is.na(try_traits$AccSpeciesID),
                                      c("AccSpeciesID", "AccSpeciesName", "SpeciesName")])

# Write extracted names to CSV for WorldFlora matching
fwrite(try_trait_names, file.path(output_dir, "try_selected_traits_names_for_r.csv"))
cat("      Wrote", nrow(try_trait_names), "TRY trait name records\n\n")

cat("Extraction complete. All name files written to:\n")
cat(" ", output_dir, "\n")
