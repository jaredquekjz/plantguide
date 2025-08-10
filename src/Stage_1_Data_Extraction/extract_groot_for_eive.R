#!/usr/bin/env Rscript
# Extract all GROOT root traits for EIVE-matched species
# Creates comprehensive root trait dataset for multi-organ modeling

suppressPackageStartupMessages({
  library(data.table)
  library(tidyr)
})

cat("=== GROOT Root Trait Extraction for EIVE Species ===\n")

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(key, default = NULL) {
  hit <- grep(paste0('^', key, '='), args, value = TRUE)
  if (length(hit) == 0) return(default)
  sub(paste0('^', key, '='), '', hit[1])
}

# File paths
groot_csv <- get_arg('--groot_csv', 'GRooT-Data/DataFiles/GRooTAggregateSpeciesVersion.csv')
groot_wfo_csv <- get_arg('--groot_wfo', 'data/GROOT/GROOT_species_WFO.csv')
eive_wfo_csv <- get_arg('--eive_wfo', 'data/EIVE/EIVE_TaxonConcept_WFO.csv')
out_dir <- get_arg('--out_dir', 'data/GROOT_extracted')

# Create output directory
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Load GROOT data
cat("Loading GROOT aggregated species data...\n")
groot <- fread(groot_csv, encoding = 'Latin-1')
cat(sprintf("  Loaded %d trait records for %d unique species\n", 
            nrow(groot), 
            length(unique(paste(groot$genusTNRS, groot$speciesTNRS)))))

# Get all unique traits
all_traits <- unique(groot$traitName)
cat(sprintf("  Found %d unique root traits\n", length(all_traits)))

# Load GROOT WFO mapping
cat("\nLoading GROOT-WFO mapping...\n")
groot_wfo <- fread(groot_wfo_csv)
groot_wfo[, genus_species := scientific_name]  # Keep original name for matching

# Load EIVE WFO normalized names
cat("Loading EIVE-WFO mapping...\n")
eive_wfo <- fread(eive_wfo_csv)

# Get EIVE accepted names (handle different column names)
if ("wfo_accepted_name" %in% names(eive_wfo)) {
  eive_accepted <- unique(eive_wfo[!is.na(wfo_accepted_name), .(TaxonConcept, wfo_accepted_name)])
} else if ("WFO_Accepted" %in% names(eive_wfo)) {
  eive_accepted <- unique(eive_wfo[!is.na(WFO_Accepted), .(TaxonConcept, wfo_accepted_name = WFO_Accepted)])
} else {
  eive_accepted <- unique(eive_wfo[, .(TaxonConcept, wfo_accepted_name = TaxonConcept)])
}

# Find GROOT species that match EIVE
cat("\nMatching GROOT species to EIVE...\n")
groot_in_eive <- groot_wfo[wfo_accepted_name %in% eive_accepted$wfo_accepted_name]
cat(sprintf("  Found %d GROOT species in EIVE (%.1f%%)\n", 
            nrow(groot_in_eive), 
            100 * nrow(groot_in_eive) / nrow(groot_wfo)))

# Add EIVE taxon concept to matched species
groot_in_eive <- merge(groot_in_eive, 
                       eive_accepted, 
                       by = 'wfo_accepted_name', 
                       all.x = TRUE)

# Extract all root traits for EIVE species
cat("\nExtracting root traits for EIVE species...\n")

# Add scientific name to GROOT data for matching
groot[, scientific_name := paste(genusTNRS, speciesTNRS)]

# Filter GROOT data for EIVE species
groot_eive <- groot[scientific_name %in% groot_in_eive$genus_species]

# Add WFO accepted name and EIVE taxon concept
groot_eive <- merge(groot_eive, 
                    groot_in_eive[, .(scientific_name = genus_species, 
                                     wfo_accepted_name, 
                                     TaxonConcept)],
                    by = 'scientific_name',
                    all.x = TRUE)

cat(sprintf("  Extracted %d trait records for %d EIVE species\n", 
            nrow(groot_eive), 
            length(unique(groot_eive$TaxonConcept))))

# Create wide format dataset (species × traits)
cat("\nCreating wide-format trait matrix...\n")

# Use mean values and pivot to wide format
groot_wide <- dcast(groot_eive, 
                    TaxonConcept + wfo_accepted_name + genusTNRS + speciesTNRS ~ traitName, 
                    value.var = 'meanSpecies',
                    fun.aggregate = mean,
                    na.rm = TRUE)

# Replace NaN with NA (from aggregation of missing values)
trait_cols <- setdiff(names(groot_wide), c('TaxonConcept', 'wfo_accepted_name', 'genusTNRS', 'speciesTNRS'))
for (col in trait_cols) {
  groot_wide[is.nan(get(col)), (col) := NA]
}

cat(sprintf("  Created matrix: %d species × %d traits\n", 
            nrow(groot_wide), 
            length(trait_cols)))

# Calculate trait coverage statistics
cat("\nCalculating trait coverage statistics...\n")
coverage_stats <- data.table(
  trait = trait_cols,
  n_species = sapply(trait_cols, function(x) sum(!is.na(groot_wide[[x]]))),
  pct_coverage = sapply(trait_cols, function(x) 100 * sum(!is.na(groot_wide[[x]])) / nrow(groot_wide)),
  mean_value = sapply(trait_cols, function(x) mean(groot_wide[[x]], na.rm = TRUE)),
  median_value = sapply(trait_cols, function(x) median(groot_wide[[x]], na.rm = TRUE)),
  sd_value = sapply(trait_cols, function(x) sd(groot_wide[[x]], na.rm = TRUE))
)
setorder(coverage_stats, -n_species)

# Print top traits by coverage
cat("\nTop 10 traits by EIVE species coverage:\n")
print(coverage_stats[1:min(10, nrow(coverage_stats))])

# Save outputs
cat("\nSaving outputs...\n")

# 1. Wide format trait matrix
out_wide <- file.path(out_dir, 'GROOT_EIVE_traits_wide.csv')
fwrite(groot_wide, out_wide)
cat(sprintf("  Trait matrix saved to: %s\n", out_wide))

# 2. Long format with all information
out_long <- file.path(out_dir, 'GROOT_EIVE_traits_long.csv')
fwrite(groot_eive, out_long)
cat(sprintf("  Long format saved to: %s\n", out_long))

# 3. Coverage statistics
out_stats <- file.path(out_dir, 'GROOT_EIVE_coverage_stats.csv')
fwrite(coverage_stats, out_stats)
cat(sprintf("  Coverage stats saved to: %s\n", out_stats))

# 4. Species list with counts
species_counts <- groot_eive[, .(
  n_traits = length(unique(traitName)),
  traits_available = paste(sort(unique(traitName)), collapse = "; ")
), by = .(TaxonConcept, wfo_accepted_name, genusTNRS, speciesTNRS)]
setorder(species_counts, -n_traits)

out_species <- file.path(out_dir, 'GROOT_EIVE_species_summary.csv')
fwrite(species_counts, out_species)
cat(sprintf("  Species summary saved to: %s\n", out_species))

# Create trait correlation matrix for traits with sufficient data
cat("\nAnalyzing trait correlations...\n")
min_species <- 100  # Minimum species required for correlation
good_traits <- coverage_stats[n_species >= min_species, trait]

if (length(good_traits) > 1) {
  trait_data <- groot_wide[, ..good_traits]
  cor_matrix <- cor(trait_data, use = "pairwise.complete.obs")
  
  # Save correlation matrix
  out_cor <- file.path(out_dir, 'GROOT_EIVE_trait_correlations.csv')
  cor_dt <- as.data.table(cor_matrix, keep.rownames = "trait")
  fwrite(cor_dt, out_cor)
  cat(sprintf("  Correlation matrix saved to: %s\n", out_cor))
  
  # Find highly correlated trait pairs
  cor_long <- melt(cor_dt, id.vars = "trait", variable.name = "trait2", value.name = "correlation")
  cor_long <- cor_long[trait != trait2 & abs(correlation) > 0.7]
  cor_long[, abs_correlation := abs(correlation)]
  setorder(cor_long, -abs_correlation)
  
  if (nrow(cor_long) > 0) {
    cat("\n  Highly correlated trait pairs (|r| > 0.7):\n")
    print(head(unique(cor_long[, .(trait1 = pmin(trait, trait2), 
                                    trait2 = pmax(trait, trait2), 
                                    correlation)]), 10))
  }
}

# Summary report
cat("\n=== EXTRACTION SUMMARY ===\n")
cat(sprintf("Total EIVE species with root traits: %d\n", nrow(groot_wide)))
cat(sprintf("Total trait measurements: %d\n", sum(!is.na(groot_wide[, ..trait_cols]))))
cat(sprintf("Average traits per species: %.1f\n", 
            mean(rowSums(!is.na(groot_wide[, ..trait_cols])))))
cat(sprintf("Traits with >500 species: %d\n", sum(coverage_stats$n_species > 500)))
cat(sprintf("Traits with >1000 species: %d\n", sum(coverage_stats$n_species > 1000)))

# Identify key trait combinations for modeling
cat("\n=== KEY TRAIT COMBINATIONS ===\n")

# Economic spectrum traits
econ_traits <- c("Specific_root_length", "Root_tissue_density", "Root_N_concentration", 
                 "Mean_Root_diameter", "Root_dry_matter_content")
econ_available <- intersect(econ_traits, names(groot_wide))
if (length(econ_available) > 0) {
  econ_complete <- groot_wide[complete.cases(groot_wide[, ..econ_available])]
  cat(sprintf("Root economic spectrum (%d traits): %d complete species\n", 
              length(econ_available), nrow(econ_complete)))
}

# Hydraulic traits
hydraulic_traits <- c("Root_vessel_diameter", "Root_xylem_vessel_number", 
                      "Root_cortex_thickness", "Root_stele_diameter")
hydraulic_available <- intersect(hydraulic_traits, names(groot_wide))
if (length(hydraulic_available) > 0) {
  hydraulic_complete <- groot_wide[complete.cases(groot_wide[, ..hydraulic_available])]
  cat(sprintf("Root hydraulic traits (%d traits): %d complete species\n", 
              length(hydraulic_available), nrow(hydraulic_complete)))
}

# Nutrient traits
nutrient_traits <- c("Root_N_concentration", "Root_P_concentration", "Root_N_P_ratio",
                     "Root_mycorrhizal colonization", "Root_Ca_concentration")
nutrient_available <- intersect(nutrient_traits, names(groot_wide))
if (length(nutrient_available) > 0) {
  nutrient_complete <- groot_wide[complete.cases(groot_wide[, ..nutrient_available])]
  cat(sprintf("Root nutrient traits (%d traits): %d complete species\n", 
              length(nutrient_available), nrow(nutrient_complete)))
}

# Architecture traits
architecture_traits <- c("Rooting_depth", "Lateral_spread", "Root_branching_density",
                        "Root_mass_fraction", "Fine_root_mass_leaf_mass_ratio")
architecture_available <- intersect(architecture_traits, names(groot_wide))
if (length(architecture_available) > 0) {
  architecture_complete <- groot_wide[complete.cases(groot_wide[, ..architecture_available])]
  cat(sprintf("Root architecture traits (%d traits): %d complete species\n", 
              length(architecture_available), nrow(architecture_complete)))
}

cat("\nExtraction complete!\n")
cat(sprintf("All outputs saved to: %s\n", out_dir))