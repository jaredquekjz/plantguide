#!/usr/bin/env Rscript
# Diagnose species matching for file 43289

library(data.table)

cat("=====================================================\n")
cat("DIAGNOSING SPECIES MATCHING FOR 43289 (WOOD DENSITY)\n")
cat("=====================================================\n\n")

# Load EIVE species IDs that we identified
eive_ids <- as.numeric(readLines("data/output/eive_accspecies_ids.txt"))
cat(sprintf("Total EIVE AccSpeciesIDs we're looking for: %d\n\n", length(eive_ids)))

# Check what's actually in 43289
cat("Reading 43289.txt to check species coverage...\n")
dt <- fread("data/TRY/43289_extract/43289.txt",
            select = c("AccSpeciesID", "AccSpeciesName", "TraitID"),
            sep = '\t',
            encoding = 'Latin-1',
            quote = "")

# Get unique species in this file
all_species_in_file <- unique(dt$AccSpeciesID)
all_species_in_file <- all_species_in_file[!is.na(all_species_in_file)]
cat(sprintf("Total unique species in 43289.txt: %d\n", length(all_species_in_file)))

# Check overlap with EIVE
eive_species_in_file <- all_species_in_file[all_species_in_file %in% eive_ids]
cat(sprintf("EIVE species found in 43289.txt: %d (%.1f%%)\n\n", 
            length(eive_species_in_file),
            100 * length(eive_species_in_file) / length(eive_ids)))

# Now check wood density specifically
cat("Checking wood density (TraitID 4) coverage...\n")
wood_data <- dt[TraitID == 4]
wood_species <- unique(wood_data$AccSpeciesID)
wood_species <- wood_species[!is.na(wood_species)]
cat(sprintf("Total species with wood density in file: %d\n", length(wood_species)))

# EIVE species with wood density
eive_wood <- wood_species[wood_species %in% eive_ids]
cat(sprintf("EIVE species with wood density: %d\n\n", length(eive_wood)))

# The key question: What % of EIVE species in this file have wood density?
if(length(eive_species_in_file) > 0) {
  cat("KEY FINDING:\n")
  cat(sprintf("  %d EIVE species are in this file\n", length(eive_species_in_file)))
  cat(sprintf("  %d of them have wood density data\n", length(eive_wood)))
  cat(sprintf("  That's %.1f%% coverage for EIVE species IN THIS FILE\n\n", 
              100 * length(eive_wood) / length(eive_species_in_file)))
}

# Sample some EIVE species WITHOUT wood density
eive_no_wood <- setdiff(eive_species_in_file, eive_wood)
if(length(eive_no_wood) > 0) {
  cat(sprintf("EIVE species in file WITHOUT wood density: %d\n", length(eive_no_wood)))
  
  # Get their names
  sample_ids <- head(eive_no_wood, 10)
  sample_names <- unique(dt[AccSpeciesID %in% sample_ids, .(AccSpeciesID, AccSpeciesName)])
  cat("Sample EIVE species WITHOUT wood density:\n")
  for(i in 1:nrow(sample_names)) {
    cat(sprintf("  ID %d: %s\n", sample_names$AccSpeciesID[i], sample_names$AccSpeciesName[i]))
  }
}

cat("\n=====================================================\n")
cat("HYPOTHESIS CHECK\n")
cat("=====================================================\n")

# Check what traits these EIVE species DO have
cat("What traits do EIVE species have in this file?\n")
eive_subset <- dt[AccSpeciesID %in% eive_species_in_file]
trait_counts <- eive_subset[!is.na(TraitID), .N, by = TraitID][order(-N)][1:20]

cat("Top 20 traits for EIVE species in 43289:\n")
for(i in 1:nrow(trait_counts)) {
  cat(sprintf("  TraitID %s: %d records\n", trait_counts$TraitID[i], trait_counts$N[i]))
}

# The real question: Why wasn't wood density requested for more species?
cat("\n=====================================================\n")
cat("CONCLUSION\n")
cat("=====================================================\n")
cat("File 43289 was requested based on specific traits.\n")
cat("It contains wood density for 11,257 species globally,\n")
cat(sprintf("but only %d EIVE species are in this file,\n", length(eive_species_in_file)))
cat(sprintf("and only %d of those have wood density.\n", length(eive_wood)))
cat("\nThis suggests the file was NOT requested for wood density\n")
cat("but for other traits, and wood density came along as\n")
cat("ancillary data for SOME species.\n")