#!/usr/bin/env Rscript
# EXACT match version - matches EIVE WFO accepted names directly to TRY AccSpeciesName
# Since TRY v6.0 uses WFO taxonomy, we can do direct exact matching

suppressPackageStartupMessages({
  library(data.table)
})

cat("=== Extracting TRY AccSpeciesIDs for EIVE Taxa (EXACT MATCH) ===\n\n")

# Load EIVE WFO mapping (EXACT version)
cat("Loading EIVE WFO exact mappings...\n")
eive <- fread("data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv", encoding = 'UTF-8')

# Get unique WFO accepted names that have valid WFO IDs
# These are the names we'll match against TRY's AccSpeciesName
eive_wfo_names <- unique(eive[!is.na(wfo_id) & nzchar(wfo_id), wfo_accepted_name])
cat(sprintf("  EIVE taxa with WFO mapping: %d\n", length(eive_wfo_names)))

# Also keep a mapping from WFO name back to original EIVE names
wfo_to_eive <- eive[!is.na(wfo_id) & nzchar(wfo_id), 
                     .(wfo_accepted_name, TaxonConcept)]

# Process each TRY file
datasets <- list(
  "data/TRY/43240_extract/43240.txt",
  "data/TRY/43244_extract/43244.txt", 
  "data/TRY/43286_extract/43286.txt",
  "data/TRY/43289_extract/43289.txt",
  "data/TRY/43374.txt"
)

all_matches <- list()

cat("\nProcessing TRY datasets...\n")
for(i in seq_along(datasets)) {
  file_path <- datasets[[i]]
  cat(sprintf("\n%d. %s\n", i, basename(file_path)))
  
  file_size_mb <- file.info(file_path)$size / (1024^2)
  cat(sprintf("   File size: %.1f MB\n", file_size_mb))
  
  # Read only the species columns we need
  cat("   Reading species columns...\n")
  
  dt <- tryCatch({
    fread(file_path, sep = '\t', encoding = 'Latin-1', 
          select = c("AccSpeciesName", "AccSpeciesID"),
          quote = "")
  }, error = function(e) {
    cat("   Latin-1 failed, trying UTF-8...\n")
    fread(file_path, sep = '\t', encoding = 'UTF-8',
          select = c("AccSpeciesName", "AccSpeciesID"),
          quote = "")
  })
  
  # Get unique AccSpeciesName-ID pairs
  unique_species <- unique(dt[!is.na(AccSpeciesName) & !is.na(AccSpeciesID)])
  rm(dt)
  gc()
  
  cat(sprintf("   Unique AccSpecies entries: %d\n", nrow(unique_species)))
  
  # EXACT match: AccSpeciesName should exactly match our EIVE WFO accepted names
  # TRY uses WFO, so AccSpeciesName ARE WFO accepted names
  matched <- unique_species[AccSpeciesName %in% eive_wfo_names]
  
  if (nrow(matched) > 0) {
    cat(sprintf("   Matched species: %d\n", nrow(matched)))
    cat(sprintf("   Unique AccSpeciesIDs: %d\n", length(unique(matched$AccSpeciesID))))
    all_matches[[basename(file_path)]] <- matched
  } else {
    cat("   No matches found\n")
  }
}

# Combine all matches
cat("\n=== Combining Results ===\n")
combined <- rbindlist(all_matches, use.names = TRUE)

# Get unique AccSpeciesID-Name pairs across all datasets
unique_mappings <- unique(combined)
cat(sprintf("Total unique AccSpecies mappings: %d\n", nrow(unique_mappings)))

# Get unique AccSpeciesIDs
unique_ids <- unique(unique_mappings$AccSpeciesID)
cat(sprintf("Unique AccSpeciesIDs: %d\n", length(unique_ids)))

# Add back EIVE taxon names for reporting
unique_mappings <- merge(unique_mappings, wfo_to_eive, 
                         by.x = "AccSpeciesName", 
                         by.y = "wfo_accepted_name",
                         allow.cartesian = TRUE)

# Check coverage
matched_eive_names <- unique(unique_mappings$TaxonConcept)
cat(sprintf("\nEIVE taxa found in TRY: %d of %d (%.1f%%)\n", 
            length(matched_eive_names), 
            nrow(eive),
            100 * length(matched_eive_names) / nrow(eive)))

# Also report coverage of successfully WFO-mapped EIVE taxa
eive_with_wfo <- eive[!is.na(wfo_id) & nzchar(wfo_id)]
matched_wfo_names <- unique(unique_mappings$AccSpeciesName)
cat(sprintf("WFO-mapped EIVE taxa found in TRY: %d of %d (%.1f%%)\n",
            length(matched_wfo_names),
            nrow(eive_with_wfo),
            100 * length(matched_wfo_names) / nrow(eive_with_wfo)))

# Save results
cat("\n=== Saving Results ===\n")

# Full mapping with EIVE names
output_full <- unique_mappings[order(AccSpeciesID, TaxonConcept)]
fwrite(output_full, "data/output/eive_try_species_mapping_EXACT.csv")
cat(sprintf("Full mapping saved to: data/output/eive_try_species_mapping_EXACT.csv\n"))

# Just the AccSpeciesIDs - ONE PER LINE!
writeLines(as.character(unique_ids), "data/output/eive_accspecies_ids_EXACT.txt")
cat(sprintf("AccSpeciesIDs saved to: data/output/eive_accspecies_ids_EXACT.txt (%d IDs)\n", 
            length(unique_ids)))

# Comma-delimited for SQL queries
write(paste(unique_ids, collapse = ","), "data/output/eive_accspecies_ids_comma_EXACT.txt")
cat(sprintf("Comma-delimited IDs saved to: data/output/eive_accspecies_ids_comma_EXACT.txt\n"))

# Show sample mappings
cat("\n=== Sample Mappings ===\n")
print(head(output_full, 10))

# Summary statistics
cat("\n=== Summary Statistics ===\n")
cat(sprintf("✅ EXACT matching complete!\n"))
cat(sprintf("   Total AccSpeciesIDs found: %d\n", length(unique_ids)))
cat(sprintf("   EIVE taxa coverage: %.1f%%\n", 100 * length(matched_eive_names) / nrow(eive)))
cat(sprintf("   WFO-mapped coverage: %.1f%%\n", 100 * length(matched_wfo_names) / nrow(eive_with_wfo)))

# List some common species found
cat("\nMost common matched species:\n")
species_counts <- unique_mappings[, .N, by = AccSpeciesName][order(-N)]
print(head(species_counts, 10))