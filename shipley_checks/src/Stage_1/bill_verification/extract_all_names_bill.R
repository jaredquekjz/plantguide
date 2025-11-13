#!/usr/bin/env Rscript
# Bill Shipley Verification: Extract names from all 8 datasets for WorldFlora matching
# Reads from canonical parquets, writes name CSVs to shipley_checks

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
  library(data.table)
  library(dplyr)
})

output_dir <- file.path(OUTPUT_DIR, "wfo_verification")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cat("Bill Shipley Verification: Extracting names from 8 datasets\n")
cat("Output directory:", output_dir, "\n\n")

# 1. Duke
cat("[1/8] Extracting Duke names...\n")
duke <- read_parquet(file.path(INPUT_DIR, "duke_original.parquet"))
duke_names <- unique(duke[!is.na(duke$plant_key),
                          c("plant_key", "scientific_name", "taxonomy.taxon", "genus", "species")])
# Rename to match DuckDB: "taxonomy.taxon" AS taxonomy_taxon
setnames(duke_names, "taxonomy.taxon", "taxonomy_taxon")
fwrite(duke_names, file.path(output_dir, "duke_names_for_r.csv"))
cat("      Wrote", nrow(duke_names), "Duke name records\n\n")

# 2. EIVE
cat("[2/8] Extracting EIVE names...\n")
eive <- read_parquet(file.path(INPUT_DIR, "eive_original.parquet"))
eive_names <- unique(eive[!is.na(eive$TaxonConcept) & nchar(trimws(eive$TaxonConcept)) > 0,
                           c("TaxonConcept", "TaxonRank", "AccordingTo", "UUID")])
fwrite(eive_names, file.path(output_dir, "eive_names_for_r.csv"))
cat("      Wrote", nrow(eive_names), "EIVE name records\n\n")

# 3. Mabberly
cat("[3/8] Extracting Mabberly names...\n")
mab <- read_parquet(file.path(INPUT_DIR, "mabberly_original.parquet"))
mab_names <- unique(mab[!is.na(mab$Genus) & nchar(trimws(mab$Genus)) > 0,
                        c("Genus", "Family")])
fwrite(mab_names, file.path(output_dir, "mabberly_names_for_r.csv"))
cat("      Wrote", nrow(mab_names), "Mabberly name records\n\n")

# 4. TRY Enhanced
cat("[4/8] Extracting TRY Enhanced names...\n")
try_enh <- read_parquet(file.path(INPUT_DIR, "tryenhanced_species_original.parquet"))
try_enh_names <- unique(try_enh[!is.na(try_enh$`Species name standardized against TPL`) &
                                  nchar(trimws(try_enh$`Species name standardized against TPL`)) > 0,
                                c("Species name standardized against TPL", "Genus", "Family")])
# Rename column to match canonical
setnames(try_enh_names, "Species name standardized against TPL", "SpeciesName")
fwrite(try_enh_names, file.path(output_dir, "tryenhanced_names_for_r.csv"))
cat("      Wrote", nrow(try_enh_names), "TRY Enhanced name records\n\n")

# 5. AusTraits
cat("[5/8] Extracting AusTraits names...\n")
aus_taxa <- read_parquet(file.path(INPUT_DIR, "austraits_taxa.parquet"))
aus_names <- unique(aus_taxa[, c("taxon_name", "taxon_rank", "genus", "family",
                                  "taxonomic_status", "taxonomic_dataset")])
aus_names <- aus_names[order(aus_names$taxon_name), ]
fwrite(aus_names, file.path(output_dir, "austraits_names_for_r.csv"))
cat("      Wrote", nrow(aus_names), "AusTraits name records\n\n")

# 6. GBIF occurrences (stream to avoid memory issues with 5.4GB file)
cat("[6/8] Extracting GBIF plant names...\n")
gbif_ds <- open_dataset(file.path(INPUT_DIR, "gbif_occurrence_plantae.parquet"))
gbif_names <- gbif_ds %>%
  select(scientificName) %>%
  filter(!is.na(scientificName)) %>%
  distinct() %>%
  collect()
gbif_names <- as.data.frame(gbif_names)
setnames(gbif_names, "scientificName", "SpeciesName")
fwrite(gbif_names, file.path(output_dir, "gbif_occurrence_names_for_r.tsv"), sep = "\t")
cat("      Wrote", nrow(gbif_names), "GBIF name records\n\n")

# 7. GloBI interactions (stream for efficiency)
cat("[7/8] Extracting GloBI plant names...\n")
globi_ds <- open_dataset(file.path(INPUT_DIR, "globi_interactions_plants.parquet"))
# Extract source plant names
source_names <- globi_ds %>%
  filter(sourceTaxonKingdomName == "Plantae", !is.na(sourceTaxonName)) %>%
  select(sourceTaxonName) %>%
  distinct() %>%
  collect()
source_names <- as.data.frame(source_names)
setnames(source_names, "sourceTaxonName", "SpeciesName")
# Extract target plant names
target_names <- globi_ds %>%
  filter(targetTaxonKingdomName == "Plantae", !is.na(targetTaxonName)) %>%
  select(targetTaxonName) %>%
  distinct() %>%
  collect()
target_names <- as.data.frame(target_names)
setnames(target_names, "targetTaxonName", "SpeciesName")
# Combine and deduplicate
globi_names <- unique(rbind(source_names, target_names))
fwrite(globi_names, file.path(output_dir, "globi_interactions_names_for_r.tsv"), sep = "\t")
cat("      Wrote", nrow(globi_names), "GloBI plant name records\n\n")

# 8. TRY traits
cat("[8/8] Extracting TRY trait names...\n")
try_traits <- read_parquet(file.path(INPUT_DIR, "try_selected_traits.parquet"))
try_trait_names <- unique(try_traits[!is.na(try_traits$AccSpeciesID),
                                      c("AccSpeciesID", "AccSpeciesName", "SpeciesName")])
fwrite(try_trait_names, file.path(output_dir, "try_selected_traits_names_for_r.csv"))
cat("      Wrote", nrow(try_trait_names), "TRY trait name records\n\n")

cat("Extraction complete. All name files written to:\n")
cat(" ", output_dir, "\n")
