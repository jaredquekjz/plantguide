#!/usr/bin/env Rscript
# FAST extraction using AccSpeciesIDs - exactly like the successful Ellenberg script!

library(data.table)
library(rtry)

cat("=== 🚀 FAST EIVE Trait Extraction Using AccSpeciesIDs ===\n\n")

# Load the EIVE species IDs
id_file <- "data/output/eive_accspecies_ids.txt"
if (!file.exists(id_file)) {
  stop("Run extract_eive_species_ids.R first to generate AccSpeciesIDs!")
}

cat("Loading EIVE AccSpeciesIDs...\n")
species_ids <- as.numeric(readLines(id_file))
species_ids <- species_ids[!is.na(species_ids)]
cat(sprintf("  Loaded %d AccSpeciesIDs\n\n", length(species_ids)))

# Define all 4 TRY datasets
datasets <- list(
  list(path = "data/TRY/43240_extract/43240.txt", name = "Dataset 1 (43240)"),
  list(path = "data/TRY/43244_extract/43244.txt", name = "Dataset 2 (43244)"),
  list(path = "data/TRY/43286_extract/43286.txt", name = "Dataset 3 (43286)"),
  list(path = "data/TRY/43289_extract/43289.txt", name = "Dataset 4 (43289)")
)

# Initialize collection
all_traits_combined <- list()

# Process each dataset (EXACTLY like the successful script!)
for(i in seq_along(datasets)) {
  dataset <- datasets[[i]]
  
  cat(sprintf("\n🌟 Processing %s\n", dataset$name))
  cat(sprintf("  File: %s\n", dataset$path))
  
  file_size_mb <- file.info(dataset$path)$size / (1024^2)
  cat(sprintf("  File size: %.1f MB\n", file_size_mb))
  
  # Import using rtry_import (handles encoding properly)
  cat("  Importing data with rtry_import...\n")
  try_data <- rtry_import(dataset$path, showOverview = FALSE)
  
  # Ensure it's a data.table
  if(!is.data.table(try_data)) {
    try_data <- as.data.table(try_data)
  }
  
  # FAST INTEGER FILTERING!
  cat("  Filtering for EIVE species (by AccSpeciesID)...\n")
  species_data <- try_data[AccSpeciesID %in% species_ids]
  
  # Clean up immediately to free memory
  rm(try_data)
  gc()
  
  # Get summary statistics
  n_species <- length(unique(species_data$AccSpeciesID))
  n_traits <- length(unique(species_data[!is.na(TraitID) & TraitID != "", TraitID]))
  n_records <- nrow(species_data)
  
  cat(sprintf("  Found: %d species, %d unique traits, %s records\n", 
              n_species, n_traits, format(n_records, big.mark = ',')))
  
  # Store this dataset's data - use copy() like the successful script!
  all_traits_combined[[dataset$name]] <- copy(species_data)
  
  # Show trait frequency
  if (nrow(species_data) > 0) {
    cat("\n  📊 Top 10 traits in this dataset:\n")
    trait_freq <- species_data[!is.na(TraitID) & TraitID != "", 
                               .N, by = .(TraitID, TraitName)][order(-N)][1:min(10, .N)]
    for(j in 1:nrow(trait_freq)) {
      cat(sprintf("    %2d. ID %5s: %s (n=%s)\n", 
                  j, 
                  trait_freq$TraitID[j], 
                  substr(trait_freq$TraitName[j], 1, 45),
                  format(trait_freq$N[j], big.mark = ',')))
    }
  }
}

# Combine all datasets
cat("\n🔄 Combining all datasets...\n")
combined_data <- rbindlist(all_traits_combined, idcol = "Dataset", fill = TRUE)

# Remove duplicates - use AccSpeciesID like the successful script!
cat("  Removing duplicates...\n")
combined_data[, unique_id := paste(AccSpeciesID, TraitID, StdValue, sep = "_")]
combined_unique <- combined_data[!duplicated(unique_id)]
combined_unique[, unique_id := NULL]

# Separate traits from metadata
combined_unique[, has_trait := !is.na(TraitID) & TraitID != ""]
traits_only <- combined_unique[has_trait == TRUE]
metadata_only <- combined_unique[has_trait == FALSE]

# Get final statistics
cat("\n📈 FINAL COMBINED STATISTICS:\n")
cat(sprintf("  Total records: %s\n", format(nrow(combined_unique), big.mark = ',')))
cat(sprintf("    - Trait records: %s\n", format(nrow(traits_only), big.mark = ',')))
cat(sprintf("    - Metadata records: %s\n", format(nrow(metadata_only), big.mark = ',')))
cat(sprintf("  Unique species: %d\n", length(unique(combined_unique$AccSpeciesID))))
cat(sprintf("  Unique traits: %d\n", length(unique(traits_only$TraitID))))

# Create trait summary
cat("\n📋 Creating trait availability summary...\n")
trait_summary <- traits_only[!is.na(StdValue), .(
  N_species = length(unique(AccSpeciesID)),
  N_records = .N,
  Example_values = paste(head(unique(StdValue), 3), collapse = ", "),
  Units = paste(unique(UnitName), collapse = " | "),
  Datasets = paste(unique(Dataset), collapse = ", ")
), by = .(TraitID, TraitName)]

setorder(trait_summary, -N_species)

# Show top traits
cat("\n🏆 Top 30 traits by species coverage:\n")
for(i in 1:min(30, nrow(trait_summary))) {
  cat(sprintf("  %2d. ID %5s: %s\n      %d species, %s records\n", 
              i,
              trait_summary$TraitID[i],
              substr(trait_summary$TraitName[i], 1, 60),
              trait_summary$N_species[i],
              format(trait_summary$N_records[i], big.mark = ',')))
}

# Check for key trait categories
cat("\n🎯 KEY TRAIT CATEGORIES:\n")
key_categories <- list(
  "Leaf economics" = c(3116, 3117, 47, 14, 15, 146, 147),
  "Wood traits" = c(4, 282, 287, 163, 159),
  "Root traits" = c(1080, 82, 80, 83, 1781, 896),
  "Height/Size" = c(18, 3106, 3107),
  "Seeds" = c(26, 27, 28)
)

for(cat_name in names(key_categories)) {
  trait_ids <- key_categories[[cat_name]]
  found <- intersect(trait_ids, as.numeric(trait_summary$TraitID))
  cat(sprintf("  %s: %d of %d found", cat_name, length(found), length(trait_ids)))
  if (length(found) > 0) {
    cat(sprintf(" (IDs: %s)", paste(found, collapse = ", ")))
  }
  cat("\n")
}

# Save outputs
cat("\n💾 Saving EIVE trait data...\n")

# Save all data
output_all <- "data/output/eive_all_traits_by_id.rds"
saveRDS(combined_unique, output_all)
cat(sprintf("  All data: %s (%.1f GB)\n", output_all, 
            file.info(output_all)$size / (1024^3)))

# Save traits only
output_traits <- "data/output/eive_traits_only_by_id.tsv"
fwrite(traits_only, output_traits, sep = '\t', quote = TRUE)
cat(sprintf("  Traits only: %s (%.1f GB)\n", output_traits,
            file.info(output_traits)$size / (1024^3)))

# Save trait summary
output_summary <- "data/output/eive_trait_summary_by_id.csv"
write.csv(trait_summary, output_summary, row.names = FALSE)
cat(sprintf("  Trait summary: %s\n", output_summary))

# Create species-trait matrix
cat("\n🎨 Creating species-trait matrix...\n")
species_trait_matrix <- dcast(traits_only[!is.na(StdValue)], 
                             AccSpeciesID + AccSpeciesName ~ TraitID, 
                             value.var = "StdValue", 
                             fun.aggregate = mean)

# Count traits per species
trait_cols <- setdiff(names(species_trait_matrix), c("AccSpeciesID", "AccSpeciesName"))
species_trait_matrix[, N_traits := rowSums(!is.na(.SD)), .SDcols = trait_cols]
setorder(species_trait_matrix, -N_traits)

# Save matrix
write.csv(species_trait_matrix[, .(AccSpeciesID, AccSpeciesName, N_traits)], 
          "data/output/eive_species_trait_counts_by_id.csv",
          row.names = FALSE)

# List all trait IDs
cat("\n📝 All trait IDs found:\n")
all_trait_ids <- sort(as.numeric(unique(traits_only$TraitID)))
cat(paste(all_trait_ids, collapse = ", "), "\n")

cat("\n✨ EIVE trait extraction complete! ✨\n")
cat("\nThis extraction used fast INTEGER matching on AccSpeciesID!\n")