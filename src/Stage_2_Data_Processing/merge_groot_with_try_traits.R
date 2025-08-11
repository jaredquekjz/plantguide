#!/usr/bin/env Rscript
# Merge GROOT aggregated root traits with TRY numeric trait matrix
# Strategy: Exact species name matching, LEFT JOIN to retain all TRY data
# GROOT provides AGGREGATED data (species-level means, medians, quartiles)

suppressPackageStartupMessages({
  library(data.table)
})

cat("=== Merging GROOT Aggregated Root Traits with TRY Data ===\n")
cat("GROOT provides species-level aggregated values (mean, median, quartiles)\n\n")

# File paths
try_numeric <- "data/output/eive_numeric_trait_matrix.csv"
groot_raw <- "/home/olier/ellenberg/GRooT-Data/DataFiles/GRooTAggregateSpeciesVersion.csv"
out_dir <- "data/output/merged_traits"

# Create output directory
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Load TRY numeric traits matrix
cat("Loading TRY numeric trait matrix...\n")
try_dt <- fread(try_numeric)
initial_try_rows <- nrow(try_dt)
initial_try_cols <- ncol(try_dt)
cat(sprintf("  Loaded %d species × %d columns\n", initial_try_rows, initial_try_cols))
cat(sprintf("  Species ID range: %d-%d\n", min(try_dt$AccSpeciesID), max(try_dt$AccSpeciesID)))

# Verify TRY data integrity before merge
try_species_checksum <- sum(try_dt$AccSpeciesID)
cat(sprintf("  Checksum of species IDs: %d\n", try_species_checksum))

# Load GROOT aggregated data
cat("\nLoading GROOT aggregated species data...\n")
groot_dt <- fread(groot_raw)
cat(sprintf("  Loaded %d rows (species-trait combinations)\n", nrow(groot_dt)))

# Create species names in GROOT
groot_dt[, species_name := paste(genusTNRS, speciesTNRS)]
unique_groot_species <- length(unique(groot_dt$species_name))
unique_groot_traits <- length(unique(groot_dt$traitName))
cat(sprintf("  Unique species: %d\n", unique_groot_species))
cat(sprintf("  Unique traits: %d\n", unique_groot_traits))

# Show aggregation indicators
cat("\n=== GROOT AGGREGATION LEVEL ===\n")
cat("  GROOT provides AGGREGATED data with:\n")
cat("    - meanSpecies: species-level mean value\n")
cat("    - medianSpecies: species-level median\n")
cat("    - firstQuantile, thirdQuantile: distribution info\n")
cat(sprintf("    - entriesStudySite: number of data sources (range %d-%d, mean %.2f)\n",
            min(groot_dt$entriesStudySite), 
            max(groot_dt$entriesStudySite),
            mean(groot_dt$entriesStudySite)))

# We'll use meanSpecies as the primary aggregated value
cat("\n  → Using 'meanSpecies' column for trait values\n")

# Pivot GROOT to wide format (one column per trait)
cat("\nPivoting GROOT to wide format...\n")
# Using dcast from data.table for efficiency
groot_wide <- dcast(groot_dt, 
                    species_name ~ traitName, 
                    value.var = "meanSpecies",
                    fun.aggregate = mean)  # If duplicate entries, take mean

groot_cols_before <- names(groot_wide)[-1]  # Exclude species_name
cat(sprintf("  Created matrix: %d species × %d traits\n", 
            nrow(groot_wide), length(groot_cols_before)))

# Add GROOT_ prefix to all trait columns
setnames(groot_wide, 
         old = groot_cols_before,
         new = paste0("GROOT_", groot_cols_before))

cat("  Added 'GROOT_' prefix to distinguish from TRY traits\n")

# Check exact matches
cat("\n=== EXACT SPECIES MATCHING ===\n")
matches <- try_dt$AccSpeciesName %in% groot_wide$species_name
n_matches <- sum(matches)
cat(sprintf("  Found %d exact matches out of %d TRY species (%.1f%%)\n", 
            n_matches, nrow(try_dt), 100 * n_matches / nrow(try_dt)))

if(n_matches > 0) {
  matched_species <- try_dt$AccSpeciesName[matches]
  cat("\n  Example matched species:\n")
  for(i in 1:min(10, length(matched_species))) {
    # Show the trait coverage for this species in GROOT
    groot_row <- groot_wide[species_name == matched_species[i]]
    if(nrow(groot_row) > 0) {
      n_traits <- sum(!is.na(groot_row[, -1]))  # Exclude species_name column
      cat(sprintf("    %s (%d GROOT traits)\n", matched_species[i], n_traits))
    }
  }
}

# Store unmatched species for reporting
unmatched_try <- try_dt$AccSpeciesName[!matches]
cat(sprintf("\n  TRY species without GROOT match: %d\n", length(unmatched_try)))

# Perform LEFT JOIN - keeping ALL TRY species
cat("\n🔮 Performing LEFT JOIN (preserving ALL TRY data)...\n")
merged_dt <- merge(try_dt, 
                   groot_wide,
                   by.x = "AccSpeciesName",
                   by.y = "species_name",
                   all.x = TRUE,   # Keep ALL TRY species
                   all.y = FALSE)  # Don't add GROOT species not in TRY

# Verify no TRY data loss
cat("\n=== DATA INTEGRITY CHECK ===\n")
cat(sprintf("  TRY species before merge: %d\n", initial_try_rows))
cat(sprintf("  Species after merge: %d\n", nrow(merged_dt)))
cat(sprintf("  Checksum verification: %s\n", 
            ifelse(sum(merged_dt$AccSpeciesID) == try_species_checksum, "✓ PASSED", "✗ FAILED")))

if(nrow(merged_dt) != initial_try_rows) {
  stop("ERROR: Row count mismatch! Data loss detected!")
}

# Reorder columns: TRY first, then GROOT
groot_cols <- grep("^GROOT_", names(merged_dt), value = TRUE)
try_cols <- setdiff(names(merged_dt), groot_cols)
setcolorder(merged_dt, c(try_cols, groot_cols))

# Calculate coverage statistics
cat("\n=== COVERAGE STATISTICS ===\n")
try_trait_cols <- setdiff(names(try_dt), c("V1", "AccSpeciesID", "AccSpeciesName"))

# Count non-NA values per species
coverage_stats <- merged_dt[, .(
  AccSpeciesID = AccSpeciesID,
  species = AccSpeciesName,
  n_try_traits = rowSums(!is.na(.SD[, ..try_trait_cols])),
  n_groot_traits = rowSums(!is.na(.SD[, ..groot_cols]))
)]

cat(sprintf("Total species: %d\n", nrow(coverage_stats)))
cat(sprintf("  With TRY traits only (no GROOT): %d (%.1f%%)\n", 
            sum(coverage_stats$n_groot_traits == 0),
            100 * sum(coverage_stats$n_groot_traits == 0) / nrow(coverage_stats)))
cat(sprintf("  With GROOT traits added: %d (%.1f%%)\n", 
            sum(coverage_stats$n_groot_traits > 0),
            100 * sum(coverage_stats$n_groot_traits > 0) / nrow(coverage_stats)))
cat(sprintf("  Average TRY traits per species: %.1f\n", 
            mean(coverage_stats$n_try_traits)))
cat(sprintf("  Average GROOT traits (when present): %.1f\n", 
            mean(coverage_stats$n_groot_traits[coverage_stats$n_groot_traits > 0])))

# Check key root traits
key_root_traits <- c("GROOT_Mean_Root_diameter", 
                     "GROOT_Specific_root_length", 
                     "GROOT_Root_tissue_density", 
                     "GROOT_Root_N_concentration",
                     "GROOT_Root_C_concentration",
                     "GROOT_Root_dry_matter_content")

cat("\n=== KEY ROOT TRAIT AVAILABILITY ===\n")
for(trait in key_root_traits) {
  if(trait %in% names(merged_dt)) {
    n_species <- sum(!is.na(merged_dt[[trait]]))
    cat(sprintf("  %-35s: %4d species (%5.1f%%)\n", 
                sub("GROOT_", "", trait), n_species, 100 * n_species / nrow(merged_dt)))
  }
}

# Save merged dataset
cat("\n💾 Saving merged dataset...\n")
out_file <- file.path(out_dir, "try_groot_merged_numeric.csv")
fwrite(merged_dt, out_file)
cat(sprintf("  Main file: %s (%.1f MB)\n", out_file, file.size(out_file) / 1024^2))
cat(sprintf("  Dimensions: %d species × %d total columns\n", 
            nrow(merged_dt), ncol(merged_dt)))

# Save coverage summary
coverage_file <- file.path(out_dir, "species_trait_coverage.csv")
fwrite(coverage_stats, coverage_file)
cat(sprintf("  Coverage stats: %s\n", coverage_file))

# Create GROOT trait availability summary
groot_summary <- data.table(
  trait = groot_cols,
  trait_clean = gsub("GROOT_", "", gsub("_", " ", groot_cols)),
  n_species = colSums(!is.na(merged_dt[, ..groot_cols])),
  percent_coverage = round(100 * colSums(!is.na(merged_dt[, ..groot_cols])) / nrow(merged_dt), 1)
)
setorder(groot_summary, -n_species)

cat("\n=== TOP 15 GROOT TRAITS BY AVAILABILITY ===\n")
for(i in 1:min(15, nrow(groot_summary))) {
  cat(sprintf("  %-35s: %4d species (%5.1f%%)\n", 
              groot_summary$trait_clean[i], 
              groot_summary$n_species[i],
              groot_summary$percent_coverage[i]))
}

# Save GROOT trait summary
groot_summary_file <- file.path(out_dir, "groot_trait_availability.csv")
fwrite(groot_summary, groot_summary_file)
cat(sprintf("\nGROOT trait summary: %s\n", groot_summary_file))

# Identify species with rich multi-organ data
complete_species <- coverage_stats[n_try_traits > 20 & n_groot_traits > 5]
setorder(complete_species, -n_groot_traits, -n_try_traits)

if(nrow(complete_species) > 0) {
  cat(sprintf("\n✨ Found %d species with rich multi-organ data (>20 TRY, >5 GROOT traits)!\n", 
              nrow(complete_species)))
  cat("\nTop 10 species by combined trait coverage:\n")
  for(i in 1:min(10, nrow(complete_species))) {
    cat(sprintf("  %-35s: TRY=%2d, GROOT=%2d, Total=%2d\n", 
                complete_species$species[i], 
                complete_species$n_try_traits[i],
                complete_species$n_groot_traits[i],
                complete_species$n_try_traits[i] + complete_species$n_groot_traits[i]))
  }
  
  # Save list of data-rich species
  rich_species_file <- file.path(out_dir, "species_rich_multiorgan_data.csv")
  fwrite(complete_species, rich_species_file)
  cat(sprintf("\nData-rich species list: %s\n", rich_species_file))
}

# Create validation report
cat("\n=== FINAL VALIDATION ===\n")
cat(sprintf("✓ All %d TRY species retained\n", initial_try_rows))
cat(sprintf("✓ Added %d GROOT trait columns\n", length(groot_cols)))
cat(sprintf("✓ %d species enriched with root traits\n", sum(coverage_stats$n_groot_traits > 0)))
cat("✓ No data loss (verified by checksum)\n")
cat("✓ Exact species name matching used\n")

cat("\n✅ MERGE COMPLETE!\n")
cat("All TRY data preserved, GROOT aggregated traits added where available.\n")
cat(sprintf("Output directory: %s\n", out_dir))