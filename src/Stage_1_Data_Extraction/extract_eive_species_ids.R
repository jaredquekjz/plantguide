#!/usr/bin/env Rscript
# Extract AccSpeciesIDs for EIVE taxa from TRY data
# This creates a mapping we can use for FAST extraction

library(data.table)

cat("=== Extracting TRY AccSpeciesIDs for EIVE Taxa ===\n\n")

# Load EIVE taxa
cat("Loading EIVE taxa list...\n")
eive <- fread('data/EIVE/EIVE_TaxonConcept_WFO.csv', encoding = 'UTF-8')
cat(sprintf("  EIVE taxa count: %d\n", nrow(eive)))

# Normalize function with better encoding handling
normalize_name <- function(x) {
  # Handle NAs and empty strings
  x[is.na(x)] <- ""
  x <- as.character(x)
  
  # Clean encoding issues first
  x <- iconv(x, from = "", to = "UTF-8", sub = " ")
  
  # Then normalize
  x <- tolower(x)
  x <- gsub('[^a-z0-9 ]', ' ', x)
  x <- gsub('\\s+', ' ', x)
  trimws(x)
}

# Create normalized name sets
eive_norm <- unique(normalize_name(eive$TaxonConcept))
wfo_norm <- normalize_name(eive$wfo_accepted_name)
wfo_norm <- wfo_norm[!is.na(wfo_norm) & nzchar(wfo_norm)]
wfo_norm <- unique(wfo_norm)

target_names_set <- unique(c(eive_norm, wfo_norm))
target_names_set <- target_names_set[nzchar(target_names_set)]

cat(sprintf("  Target normalized names: %d\n\n", length(target_names_set)))

# Process each TRY file to extract unique species-ID mappings
datasets <- list(
  "data/TRY/43240_extract/43240.txt",
  "data/TRY/43244_extract/43244.txt", 
  "data/TRY/43286_extract/43286.txt",
  "data/TRY/43289_extract/43289.txt"
)

all_species_mappings <- list()

for(i in seq_along(datasets)) {
  file_path <- datasets[[i]]
  cat(sprintf("Processing %s...\n", basename(file_path)))
  
  file_size_mb <- file.info(file_path)$size / (1024^2)
  cat(sprintf("  File size: %.1f MB\n", file_size_mb))
  
  # Just read the file - no chunking needed!
  # We only need the species columns for matching
  cat("  Reading species columns...\n")
  
  # Use tryCatch to handle encoding issues
  dt <- tryCatch({
    fread(file_path, sep = '\t', encoding = 'Latin-1', 
          select = c("SpeciesName", "AccSpeciesName", "AccSpeciesID"),
          quote = "")  # Avoid quoting issues
  }, error = function(e) {
    cat("  Latin-1 failed, trying UTF-8...\n")
    fread(file_path, sep = '\t', encoding = 'UTF-8',
          select = c("SpeciesName", "AccSpeciesName", "AccSpeciesID"),
          quote = "")
  })
  
  # Clean any encoding issues in the data
  dt[, SpeciesName := iconv(SpeciesName, from = "UTF-8", to = "UTF-8", sub = "")]
  dt[, AccSpeciesName := iconv(AccSpeciesName, from = "UTF-8", to = "UTF-8", sub = "")]
  
  # Get unique species entries (reduces from millions to thousands)
  unique_species <- unique(dt)
  rm(dt)  # Free memory immediately
  gc()
  
  cat(sprintf("  Found %d unique species entries\n", nrow(unique_species)))
  
  # Normalize and match
  unique_species[, norm_species := normalize_name(SpeciesName)]
  unique_species[, norm_acc := normalize_name(AccSpeciesName)]
  
  # Find EIVE taxa
  matched <- unique_species[norm_species %in% target_names_set | 
                            norm_acc %in% target_names_set]
  
  if (nrow(matched) > 0) {
    cat(sprintf("  Matched %d EIVE taxa\n", nrow(matched)))
    all_species_mappings[[basename(file_path)]] <- matched
  }
}

# Combine all mappings
cat("\nCombining species mappings...\n")
combined_mappings <- rbindlist(all_species_mappings, fill = TRUE)

# Remove duplicates and clean
combined_mappings <- unique(combined_mappings[!is.na(AccSpeciesID) & AccSpeciesID != ""])
combined_mappings[, AccSpeciesID := as.numeric(AccSpeciesID)]
combined_mappings <- combined_mappings[!is.na(AccSpeciesID)]

# Sort by AccSpeciesID
setorder(combined_mappings, AccSpeciesID)

cat(sprintf("\nFinal mappings: %d unique species\n", nrow(combined_mappings)))
cat(sprintf("Unique AccSpeciesIDs: %d\n", length(unique(combined_mappings$AccSpeciesID))))

# Create reverse mapping to EIVE names
cat("\nCreating EIVE name mappings...\n")
combined_mappings[, matched_eive_name := NA_character_]

for(i in 1:nrow(combined_mappings)) {
  norm_sp <- combined_mappings$norm_species[i]
  norm_acc <- combined_mappings$norm_acc[i]
  
  # Find which EIVE name matched
  if (norm_sp %in% eive_norm) {
    idx <- which(eive_norm == norm_sp)[1]
    combined_mappings[i, matched_eive_name := eive$TaxonConcept[idx]]
  } else if (norm_acc %in% eive_norm) {
    idx <- which(eive_norm == norm_acc)[1]
    combined_mappings[i, matched_eive_name := eive$TaxonConcept[idx]]
  } else if (norm_sp %in% wfo_norm) {
    idx <- which(wfo_norm == norm_sp)[1]
    combined_mappings[i, matched_eive_name := eive$wfo_accepted_name[idx]]
  } else if (norm_acc %in% wfo_norm) {
    idx <- which(wfo_norm == norm_acc)[1]
    combined_mappings[i, matched_eive_name := eive$wfo_accepted_name[idx]]
  }
}

# Save results
cat("\nSaving results...\n")

# Save full mapping
output_mapping <- "data/output/eive_try_species_mapping.csv"
fwrite(combined_mappings[, .(AccSpeciesID, AccSpeciesName, SpeciesName, matched_eive_name)], 
       output_mapping)
cat(sprintf("  Full mapping saved to: %s\n", output_mapping))

# Save just the IDs for fast filtering
species_ids <- unique(combined_mappings$AccSpeciesID)
output_ids <- "data/output/eive_accspecies_ids.txt"
writeLines(as.character(species_ids), output_ids)
cat(sprintf("  AccSpeciesIDs saved to: %s (%d IDs)\n", output_ids, length(species_ids)))

# Save as comma-delimited for TRY requests
csv_string <- paste(species_ids, collapse = ",")
output_csv <- "data/output/eive_accspecies_ids_comma.txt"
writeLines(csv_string, output_csv)
cat(sprintf("  Comma-delimited IDs saved to: %s\n", output_csv))

# Show sample
cat("\nSample mappings:\n")
print(head(combined_mappings[, .(AccSpeciesID, AccSpeciesName, matched_eive_name)], 10))

cat(sprintf("\n✨ Complete! Found %d AccSpeciesIDs for EIVE taxa\n", length(species_ids)))
cat(sprintf("Coverage: ~%.1f%% of EIVE taxa\n", 
            100 * length(unique(combined_mappings$matched_eive_name)) / nrow(eive)))