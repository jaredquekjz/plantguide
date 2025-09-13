#!/usr/bin/env Rscript

# Simpler approach: Use existing clean_gbif_extract_bioclim_noDups.R 
# but with the correct list of 1,051 matched species

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

cat("=== Preparing Species List for Bioclim Re-extraction ===\n\n")

# Load matched species
matches_file <- "/home/olier/ellenberg/artifacts/gbif_complete_trait_matches_wfo.json"
matches <- fromJSON(matches_file)
matched_species <- matches$matched_species

cat(sprintf("Found %d matched species\n", nrow(matched_species)))

# Create species list file for extraction
species_df <- data.frame(
  species = matched_species$trait_name,
  gbif_file = matched_species$gbif_file,
  stringsAsFactors = FALSE
)

# Save to file that extraction script can use
output_file <- "/home/olier/ellenberg/data/matched_species_for_extraction.csv"
write.csv(species_df, output_file, row.names = FALSE)

cat(sprintf("\nSpecies list saved to: %s\n", output_file))

# Show instructions for running extraction
cat("\n=== Next Steps ===\n")
cat("1. Modify clean_gbif_extract_bioclim_noDups.R to use this species list\n")
cat("2. Run the extraction with:\n")
cat("   export R_LIBS_USER=/home/olier/ellenberg/.Rlib\n")
cat("   Rscript src/Stage_1_Data_Extraction/gbif_bioclim/clean_gbif_extract_bioclim_matched.R\n")

# Or we can directly call the existing script with modified config
cat("\nAlternatively, checking if we can reuse existing extractions...\n")

# Check what's already extracted
existing_dir <- "/home/olier/ellenberg/data/bioclim_extractions_cleaned"
if (dir.exists(existing_dir)) {
  existing_files <- list.files(file.path(existing_dir, "species_data"), pattern = "\\.csv$")
  cat(sprintf("Found %d existing species extractions\n", length(existing_files)))
  
  # Extract species names from filenames
  existing_species <- gsub("_bioclim\\.csv$", "", existing_files)
  existing_species <- gsub("_", " ", existing_species)
  
  # Check overlap
  overlap <- sum(tolower(species_df$species) %in% tolower(existing_species))
  cat(sprintf("Overlap: %d species already extracted (%.1f%%)\n", 
              overlap, 100 * overlap / nrow(species_df)))
  
  # Find missing species
  missing <- species_df$species[!tolower(species_df$species) %in% tolower(existing_species)]
  cat(sprintf("Missing: %d species need extraction\n", length(missing)))
  
  if (length(missing) > 0) {
    cat("\nSample missing species:\n")
    print(head(missing, 10))
    
    # Save missing species list
    missing_df <- species_df[species_df$species %in% missing, ]
    missing_file <- "/home/olier/ellenberg/data/missing_species_for_extraction.csv"
    write.csv(missing_df, missing_file, row.names = FALSE)
    cat(sprintf("\nMissing species list saved to: %s\n", missing_file))
  }
}