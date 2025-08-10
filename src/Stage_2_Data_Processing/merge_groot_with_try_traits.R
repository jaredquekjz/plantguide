#!/usr/bin/env Rscript
# Merge GROOT root traits with TRY trait data for EIVE species
# Creates comprehensive multi-organ trait dataset

suppressPackageStartupMessages({
  library(data.table)
})

cat("=== Merging GROOT Root Traits with TRY Data for EIVE Species ===\n\n")

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(key, default = NULL) {
  hit <- grep(paste0('^', key, '='), args, value = TRUE)
  if (length(hit) == 0) return(default)
  sub(paste0('^', key, '='), '', hit[1])
}

# File paths
try_rds <- get_arg('--try_rds', 'data/output/eive_all_traits_by_id.rds')
groot_wide <- get_arg('--groot_wide', 'data/GROOT_extracted/GROOT_EIVE_traits_wide.csv')
out_dir <- get_arg('--out_dir', 'data/output/merged_traits')

# Create output directory
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Load TRY data
cat("Loading TRY trait data...\n")
try_data <- readRDS(try_rds)
cat(sprintf("  Loaded %s records for %d unique species\n", 
            format(nrow(try_data), big.mark = ','),
            length(unique(try_data$AccSpeciesID))))

# Get unique TRY species
try_species <- unique(try_data[!is.na(AccSpeciesID), .(AccSpeciesID, AccSpeciesName)])
cat(sprintf("  TRY species: %d\n", nrow(try_species)))

# Check for existing root traits in TRY
cat("\nChecking for existing root traits in TRY...\n")
root_trait_ids <- c(
  1080,  # Specific root length
  82,    # Root tissue density  
  80,    # Root nitrogen concentration
  83,    # Root diameter
  1781,  # Fine root density
  896,   # Fine root diameter
  1401   # Root branching
)

existing_root_traits <- try_data[TraitID %in% root_trait_ids]
if (nrow(existing_root_traits) > 0) {
  cat("  WARNING: Found existing root traits in TRY:\n")
  root_summary <- existing_root_traits[, .(N = .N), by = .(TraitID, TraitName)]
  print(root_summary)
  cat("  These will be preserved alongside GROOT data\n")
} else {
  cat("  No root traits found in TRY data (as expected)\n")
}

# Load GROOT data
cat("\nLoading GROOT root trait data...\n")
groot <- fread(groot_wide)
cat(sprintf("  Loaded root traits for %d species\n", nrow(groot)))

# Get GROOT trait columns (exclude identifiers)
id_cols <- c('TaxonConcept', 'wfo_accepted_name', 'genusTNRS', 'speciesTNRS')
groot_trait_cols <- setdiff(names(groot), id_cols)
cat(sprintf("  Available root traits: %d\n", length(groot_trait_cols)))

# Match species between TRY and GROOT
cat("\nMatching species between datasets...\n")
# Direct match: TRY AccSpeciesName = GROOT TaxonConcept
matched_species <- merge(try_species, 
                        groot[, c("TaxonConcept", ..groot_trait_cols), with = FALSE],
                        by.x = "AccSpeciesName",
                        by.y = "TaxonConcept",
                        all.x = FALSE,  # Inner join to get only matches
                        all.y = FALSE)

cat(sprintf("  Matched %d species (out of %d TRY, %d GROOT)\n", 
            nrow(matched_species), nrow(try_species), nrow(groot)))

if (nrow(matched_species) == 0) {
  stop("No species matched between TRY and GROOT! Check species name formats.")
}

# Create TRY TraitID mapping for GROOT traits
# Using standard TRY IDs where they exist, high numbers for others
groot_to_try_traits <- data.table(
  groot_name = c(
    "Specific_root_length", "Root_tissue_density", "Root_N_concentration",
    "Mean_Root_diameter", "Root_dry_matter_content", "Root_C_concentration",
    "Root_P_concentration", "Root_C_N_ratio", "Root_N_P_ratio",
    "Root_mycorrhizal colonization", "Rooting_depth", "Lateral_spread",
    "Root_mass_fraction", "Root_branching_density", "Root_branching_ratio",
    "Root_stele_diameter", "Root_stele_fraction", "Root_cortex_thickness",
    "Root_vessel_diameter", "Root_xylem_vessel_number", "Root_lignin_concentration",
    "Root_Ca_concentration", "Root_K_concentration", "Root_Mg_concentration",
    "Root_Mn_concentration", "Specific_root_area", "Specific_root_respiration",
    "Fine_root_mass_leaf_mass_ratio", "Coarse_root_fine_root_mass_ratio",
    "Root_length_density_volume", "Root_mass_density", "Root_production",
    "Root_turnover_rate", "Root_lifespan_mean", "Root_lifespan_median",
    "Root_litter_mass_loss_rate", "Root_total_structural_carbohydrate_concentration",
    "Net_nitrogen_uptake_rate"
  ),
  TraitID = c(
    1080, 82, 80,  # Use standard TRY IDs for SRL, RTD, Root N
    83, 90001, 90002,  # Root diameter has TRY ID, others get high IDs
    90003, 90004, 90005,
    90006, 90007, 90008,
    90009, 90010, 90011,
    90012, 90013, 90014,
    90015, 90016, 90017,
    90018, 90019, 90020,
    90021, 90022, 90023,
    90024, 90025,
    90026, 90027, 90028,
    90029, 90030, 90031,
    90032, 90033, 90034
  ),
  TraitName = c(
    "Root - specific root length (SRL)", "Root - tissue density", "Root - nitrogen content per root dry mass",
    "Root - diameter (mean)", "Root - dry matter content (RDMC)", "Root - carbon content per root dry mass",
    "Root - phosphorus content per root dry mass", "Root - carbon:nitrogen ratio", "Root - nitrogen:phosphorus ratio",
    "Root - mycorrhizal colonization intensity", "Root - rooting depth", "Root - lateral spread",
    "Root - mass fraction", "Root - branching density", "Root - branching ratio",
    "Root - stele diameter", "Root - stele fraction", "Root - cortex thickness",
    "Root - vessel diameter", "Root - xylem vessel number", "Root - lignin concentration",
    "Root - calcium concentration", "Root - potassium concentration", "Root - magnesium concentration",
    "Root - manganese concentration", "Root - specific root area", "Root - specific respiration rate",
    "Root - fine root to leaf mass ratio", "Root - coarse to fine root mass ratio",
    "Root - length density per soil volume", "Root - mass density", "Root - production rate",
    "Root - turnover rate", "Root - lifespan (mean)", "Root - lifespan (median)",
    "Root - litter mass loss rate", "Root - structural carbohydrate concentration",
    "Root - net nitrogen uptake rate"
  ),
  UnitName = c(
    "m g-1", "g cm-3", "mg g-1",
    "mm", "g g-1", "mg g-1",
    "mg g-1", "dimensionless", "dimensionless",
    "%", "m", "m",
    "g g-1", "n cm-1", "dimensionless",
    "µm", "dimensionless", "µm",
    "µm", "dimensionless", "mg g-1",
    "mg g-1", "mg g-1", "mg g-1",
    "mg g-1", "cm2 g-1", "nmol g-1 s-1",
    "g g-1", "g g-1",
    "cm cm-3", "g cm-3", "g m-2 yr-1",
    "yr-1", "d", "d",
    "k", "mg g-1", "µg g-1 hr-1"
  )
)

# Convert GROOT wide format to TRY long format using melt
cat("\nConverting GROOT data to TRY format...\n")

# Melt the matched species data
groot_long <- melt(matched_species, 
                   id.vars = c("AccSpeciesID", "AccSpeciesName"),
                   measure.vars = groot_trait_cols,
                   variable.name = "groot_name",
                   value.name = "StdValue",
                   na.rm = TRUE)  # Remove NA values

# Add trait metadata
groot_long <- merge(groot_long, groot_to_try_traits, by = "groot_name", all.x = TRUE)

# Add TRY-compatible columns
groot_long[, `:=`(
  Dataset = "GROOT Database",
  DatasetID = 90000,
  DataID = 90000,
  DataName = "Species mean value",
  OrigValueStr = as.character(StdValue),
  OrigUnitStr = UnitName,
  ObservationID = NA_integer_,
  ObsDataID = NA_integer_,
  ErrorRisk = NA_real_,
  Comment = "GROOT aggregated species-level data",
  FirstName = NA_character_,
  LastName = NA_character_,
  SpeciesName = AccSpeciesName,
  ValueKindName = "Mean",
  Reference = "Guerrero-Ramirez et al. 2020 GEB"
)]

# Remove the temporary groot_name column
groot_long[, groot_name := NULL]

cat(sprintf("  Created %d GROOT trait records in TRY format\n", nrow(groot_long)))

# Combine TRY and GROOT data
cat("\nMerging datasets...\n")

# Ensure column compatibility
common_cols <- intersect(names(try_data), names(groot_long))
try_subset <- try_data[, ..common_cols]
groot_subset <- groot_long[, ..common_cols]

# Combine the datasets
combined_data <- rbindlist(list(try_subset, groot_subset), use.names = TRUE, fill = TRUE)

# Add source identifier
combined_data[, Source := ifelse(DatasetID == 90000, "GROOT", "TRY")]

cat(sprintf("  Combined dataset: %s records\n", format(nrow(combined_data), big.mark = ',')))

# Summary statistics
cat("\n=== MERGE SUMMARY ===\n")

# Trait summary
trait_summary <- combined_data[!is.na(TraitID), .(
  N_records = .N,
  N_species = length(unique(AccSpeciesID)),
  Source = paste(unique(Source), collapse = "+")
), by = .(TraitID, TraitName)]
setorder(trait_summary, TraitID)

# Show root traits
root_traits_summary <- trait_summary[TraitID %in% c(root_trait_ids, groot_to_try_traits$TraitID)]
cat("\nRoot traits in merged dataset:\n")
print(root_traits_summary[1:min(20, .N)])

# Species coverage
species_coverage <- combined_data[!is.na(TraitID), .(
  N_TRY_traits = sum(Source == "TRY"),
  N_GROOT_traits = sum(Source == "GROOT"),
  Has_leaf = any(TraitID %in% c(3116, 3117, 47, 14)),  # SLA, LDMC, Leaf N
  Has_wood = any(TraitID == 4),  # Wood density
  Has_root = any(TraitID %in% c(1080, 82, 80, 83))  # Core root traits
), by = .(AccSpeciesID, AccSpeciesName)]

cat("\n=== SPECIES COVERAGE ===\n")
cat(sprintf("Total species with traits: %d\n", nrow(species_coverage)))
cat(sprintf("  With TRY traits only: %d\n", sum(species_coverage$N_GROOT_traits == 0)))
cat(sprintf("  With GROOT traits only: %d\n", sum(species_coverage$N_TRY_traits == 0)))
cat(sprintf("  With both TRY and GROOT: %d\n", 
            sum(species_coverage$N_TRY_traits > 0 & species_coverage$N_GROOT_traits > 0)))

# Multi-organ coverage
cat("\n=== MULTI-ORGAN COVERAGE ===\n")
cat(sprintf("Species with leaf traits: %d\n", sum(species_coverage$Has_leaf)))
cat(sprintf("Species with wood traits: %d\n", sum(species_coverage$Has_wood)))
cat(sprintf("Species with root traits: %d\n", sum(species_coverage$Has_root)))
cat(sprintf("Species with leaf + root: %d\n", 
            sum(species_coverage$Has_leaf & species_coverage$Has_root)))
cat(sprintf("Species with all three organs: %d\n", 
            sum(species_coverage$Has_leaf & species_coverage$Has_wood & species_coverage$Has_root)))

# Save outputs
cat("\n💾 Saving merged data...\n")

# Save complete merged dataset
out_rds <- file.path(out_dir, "eive_try_groot_merged.rds")
saveRDS(combined_data, out_rds)
cat(sprintf("  Complete dataset: %s (%.1f MB)\n", out_rds, 
            file.info(out_rds)$size / 1024^2))

# Save species coverage summary
out_coverage <- file.path(out_dir, "species_multi_organ_coverage.csv")
fwrite(species_coverage, out_coverage)
cat(sprintf("  Species coverage: %s\n", out_coverage))

# Create wide-format key traits matrix
cat("\nCreating key trait matrix...\n")
key_traits <- c(
  3117,  # SLA
  47,    # LDMC
  14,    # Leaf N
  4,     # Wood density
  1080,  # SRL
  82,    # Root tissue density
  80,    # Root N
  83     # Root diameter
)

trait_matrix <- dcast(combined_data[TraitID %in% key_traits & !is.na(StdValue)],
                      AccSpeciesID + AccSpeciesName ~ TraitID,
                      value.var = "StdValue",
                      fun.aggregate = mean)

# Rename columns with trait names
trait_names <- c(
  "3117" = "SLA",
  "47" = "LDMC",
  "14" = "LeafN",
  "4" = "WoodDensity",
  "1080" = "SRL",
  "82" = "RTD",
  "80" = "RootN",
  "83" = "RootDiameter"
)

for (old_name in names(trait_names)) {
  if (old_name %in% names(trait_matrix)) {
    setnames(trait_matrix, old_name, trait_names[old_name])
  }
}

# Count available traits
trait_cols <- setdiff(names(trait_matrix), c("AccSpeciesID", "AccSpeciesName"))
trait_matrix[, N_traits := rowSums(!is.na(.SD)), .SDcols = trait_cols]
setorder(trait_matrix, -N_traits)

# Save trait matrix
out_matrix <- file.path(out_dir, "key_trait_matrix.csv")
fwrite(trait_matrix, out_matrix)
cat(sprintf("  Key trait matrix: %s\n", out_matrix))

# Show species with most complete data
cat("\nTop 10 species with most complete trait data:\n")
print(trait_matrix[1:min(10, .N), .(AccSpeciesName, N_traits, SLA, WoodDensity, SRL)])

cat("\n✅ MERGE COMPLETE!\n")
cat(sprintf("Root traits from GROOT successfully integrated with TRY data.\n"))
cat(sprintf("All outputs saved to: %s\n", out_dir))