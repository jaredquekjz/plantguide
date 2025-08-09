#!/usr/bin/env Rscript
# Direct investigation of wood density (TraitID 4) coverage

library(data.table)

cat("=================================================\n")
cat("WOOD DENSITY (TraitID 4) COVERAGE INVESTIGATION\n")
cat("=================================================\n\n")

# TRY files
files <- c(
  "data/TRY/43240_extract/43240.txt",
  "data/TRY/43244_extract/43244.txt",
  "data/TRY/43286_extract/43286.txt",
  "data/TRY/43289_extract/43289.txt"
)

# Load EIVE species IDs
eive_ids <- as.numeric(readLines("data/output/eive_accspecies_ids.txt"))
cat(sprintf("EIVE species IDs loaded: %d\n\n", length(eive_ids)))

total_wood_species <- c()
total_wood_records <- 0

for(file in files) {
  cat(sprintf("Checking %s...\n", basename(file)))
  cat("  Reading file (this may take a moment)...\n")
  
  # Read just the columns we need
  dt <- fread(file, 
              select = c("TraitID", "AccSpeciesID", "AccSpeciesName"),
              sep = '\t', 
              encoding = 'Latin-1',
              quote = "")
  
  # Filter for TraitID 4
  wood_data <- dt[TraitID == 4]
  
  if(nrow(wood_data) > 0) {
    # Count total occurrences
    n_records <- nrow(wood_data)
    
    # Count unique species with wood density
    unique_species <- unique(wood_data$AccSpeciesID)
    n_unique <- length(unique_species)
    
    # Count EIVE species with wood density
    eive_wood <- unique_species[unique_species %in% eive_ids]
    n_eive <- length(eive_wood)
    
    cat(sprintf("  ✓ TraitID 4 found!\n"))
    cat(sprintf("    Total records: %d\n", n_records))
    cat(sprintf("    Unique species (global): %d\n", n_unique))
    cat(sprintf("    EIVE species with wood density: %d\n", n_eive))
    
    # Show sample species names
    if(n_eive > 0) {
      sample_names <- head(unique(wood_data[AccSpeciesID %in% eive_ids, AccSpeciesName]), 5)
      cat("    Sample EIVE species with wood density:\n")
      for(name in sample_names) {
        cat(sprintf("      - %s\n", name))
      }
    }
    
    # Accumulate
    total_wood_species <- c(total_wood_species, eive_wood)
    total_wood_records <- total_wood_records + n_records
    
  } else {
    cat("  ✗ No TraitID 4 in this file\n")
  }
  
  cat("\n")
  rm(dt, wood_data)
  gc()
}

# Final summary
cat("=================================================\n")
cat("SUMMARY\n")
cat("=================================================\n")
unique_total <- length(unique(total_wood_species))
cat(sprintf("Total EIVE species with wood density: %d\n", unique_total))
cat(sprintf("Total wood density records: %d\n", total_wood_records))
cat(sprintf("Coverage: %.1f%% of %d EIVE species\n", 
            100 * unique_total / length(eive_ids), length(eive_ids)))

# Now let's check what we actually extracted
cat("\n=================================================\n")
cat("COMPARING WITH OUR EXTRACTION\n")
cat("=================================================\n")

if(file.exists("data/output/eive_all_traits_by_id.rds")) {
  extracted <- readRDS("data/output/eive_all_traits_by_id.rds")
  extracted_wood <- extracted[TraitID == 4]
  
  cat(sprintf("Our extraction found: %d species with wood density\n", 
              length(unique(extracted_wood$AccSpeciesID))))
  cat(sprintf("Direct count found: %d species with wood density\n", unique_total))
  
  if(unique_total > length(unique(extracted_wood$AccSpeciesID))) {
    cat("\n⚠️ WE'RE MISSING WOOD DENSITY DATA!\n")
    diff <- unique_total - length(unique(extracted_wood$AccSpeciesID))
    cat(sprintf("   Missing: %d species\n", diff))
  }
}