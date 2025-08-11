#!/usr/bin/env Rscript
# FAST extraction using AccSpeciesIDs - exactly like the successful Ellenberg script!

library(data.table)
library(rtry)

cat("=== 🚀 FAST EIVE Trait Extraction Using AccSpeciesIDs ===\n\n")

# Load the EIVE species IDs (EXACT match version)
id_file <- "data/output/eive_accspecies_ids_EXACT.txt"
if (!file.exists(id_file)) {
  stop("Run extract_eive_species_ids_EXACT.R first to generate AccSpeciesIDs!")
}

cat("Loading EIVE AccSpeciesIDs...\n")
species_ids <- as.numeric(readLines(id_file))
species_ids <- species_ids[!is.na(species_ids)]
cat(sprintf("  Loaded %d AccSpeciesIDs\n\n", length(species_ids)))

# Define all 5 TRY datasets
datasets <- list(
  list(path = "data/TRY/43240_extract/43240.txt", name = "Dataset 1 (43240)"),
  list(path = "data/TRY/43244_extract/43244.txt", name = "Dataset 2 (43244)"),
  list(path = "data/TRY/43286_extract/43286.txt", name = "Dataset 3 (43286)"),
  list(path = "data/TRY/43289_extract/43289.txt", name = "Dataset 4 (43289)"),
  list(path = "data/TRY/43374.txt", name = "Dataset 5 (43374)")
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
  
  # Debug: Check if AccSpeciesIDs are matching
  unique_try_ids <- unique(try_data$AccSpeciesID)
  matching_ids <- intersect(unique_try_ids, species_ids)
  cat(sprintf("    Species ID matching: %d of %d EIVE IDs found in this dataset\n", 
              length(matching_ids), length(species_ids)))
  
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

# Track data before deduplication
cat(sprintf("  Records before deduplication: %s\n", format(nrow(combined_data), big.mark = ",")))
trait_42_before <- combined_data[TraitID == 42]
cat(sprintf("  Plant growth form (ID 42) before dedup: %d records\n", nrow(trait_42_before)))

# FIXED: Better duplicate removal that preserves categorical traits
cat("  Removing duplicates (improved logic)...\n")
# For numeric traits: use StdValue
# For categorical traits: use OrigValueStr
# Include ObservationID to distinguish multiple observations
combined_data[, trait_value := ifelse(!is.na(StdValue), 
                                      as.character(StdValue), 
                                      OrigValueStr)]
combined_data[, unique_id := paste(AccSpeciesID, TraitID, trait_value, ObservationID, sep = "_")]

# Show sample unique_ids for debugging
cat("\n  Sample unique_ids (first 5):\n")
sample_ids <- head(combined_data[TraitID == 42, .(AccSpeciesID, TraitID, trait_value, ObservationID, unique_id)], 5)
print(sample_ids)

# Count duplicates
n_total <- nrow(combined_data)
n_unique <- length(unique(combined_data$unique_id))
cat(sprintf("\n  Duplicate check: %d total records, %d unique IDs, %d duplicates (%.1f%%)\n", 
            n_total, n_unique, n_total - n_unique, 100*(n_total - n_unique)/n_total))

combined_unique <- combined_data[!duplicated(unique_id)]
cat(sprintf("  After deduplication: %s records (removed %d duplicates)\n", 
            format(nrow(combined_unique), big.mark = ","),
            nrow(combined_data) - nrow(combined_unique)))
combined_unique[, c("unique_id", "trait_value") := NULL]

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

# FIXED: Create trait summary for ALL traits (numeric AND categorical)
cat("\n📋 Creating trait availability summary (including categorical)...\n")

# Separate numeric and categorical traits
numeric_traits <- traits_only[!is.na(StdValue)]
categorical_traits <- traits_only[is.na(StdValue) & !is.na(OrigValueStr)]

# Summary for numeric traits
numeric_summary <- numeric_traits[, .(
  Type = "Numeric",
  N_species = length(unique(AccSpeciesID)),
  N_records = .N,
  Example_values = paste(head(unique(StdValue), 3), collapse = ", "),
  Units = paste(unique(UnitName), collapse = " | "),
  Datasets = paste(unique(Dataset), collapse = ", ")
), by = .(TraitID, TraitName)]

# Summary for categorical traits
categorical_summary <- categorical_traits[, .(
  Type = "Categorical",
  N_species = length(unique(AccSpeciesID)),
  N_records = .N,
  Example_values = paste(head(unique(OrigValueStr), 3), collapse = ", "),
  Units = "categorical",
  Datasets = paste(unique(Dataset), collapse = ", ")
), by = .(TraitID, TraitName)]

# Combine summaries
trait_summary <- rbind(numeric_summary, categorical_summary, fill = TRUE)

setorder(trait_summary, -N_species)

# Show top traits
cat("\n🏆 Top 30 traits by species coverage (ALL types):\n")
for(i in 1:min(30, nrow(trait_summary))) {
  cat(sprintf("  %2d. ID %5s (%s): %s\n      %d species, %s records\n", 
              i,
              trait_summary$TraitID[i],
              trait_summary$Type[i],
              substr(trait_summary$TraitName[i], 1, 50),
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
  "Seeds" = c(26, 27, 28),
  "Growth form" = c(42, 343)  # Added growth form
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

# Create species-trait matrix (for numeric traits)
cat("\n🎨 Creating species-trait matrix (numeric traits)...\n")
species_trait_matrix <- dcast(numeric_traits, 
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

# Report on categorical vs numeric
cat("\n📊 TRAIT TYPE BREAKDOWN:\n")
n_numeric <- nrow(numeric_summary)
n_categorical <- nrow(categorical_summary)
cat(sprintf("  Traits with numeric values: %d\n", n_numeric))
cat(sprintf("  Traits with categorical values: %d\n", n_categorical))

# Check for traits that have BOTH types of values
overlapping_traits <- intersect(numeric_summary$TraitID, categorical_summary$TraitID)
if(length(overlapping_traits) > 0) {
  cat(sprintf("  ⚠️ WARNING: %d traits have BOTH numeric AND categorical values!\n", length(overlapping_traits)))
  cat(sprintf("     These mixed traits: %s\n", paste(head(overlapping_traits, 10), collapse=", ")))
}

cat(sprintf("  Total unique traits: %d\n", length(unique(c(numeric_summary$TraitID, categorical_summary$TraitID)))))

# DATA INTEGRITY CHECKS
cat("\n🔍 DATA INTEGRITY VERIFICATION:\n")

# Check 1: Verify Plant growth form (ID 42) records
trait_42 <- traits_only[TraitID == 42]
cat(sprintf("  Plant growth form (ID 42) check:\n"))
cat(sprintf("    - Total records after dedup: %d\n", nrow(trait_42)))
cat(sprintf("    - Expected from datasets: ~704,750 (352,375 × 2)\n"))
cat(sprintf("    - Data retention rate: %.1f%%\n", 100 * nrow(trait_42) / 704750))

# Check 2: Verify total records per dataset
dataset_counts <- combined_unique[, .N, by = Dataset]
cat("\n  Records per dataset after dedup:\n")
for(i in 1:nrow(dataset_counts)) {
  cat(sprintf("    - %s: %s records\n", dataset_counts$Dataset[i], format(dataset_counts$N[i], big.mark=",")))
}

# Check 3: Sample some high-frequency traits
cat("\n  High-frequency trait verification:\n")
for(tid in c(42, 28, 26, 3106)) {
  trait_data <- traits_only[TraitID == tid]
  n_numeric <- sum(!is.na(trait_data$StdValue))
  n_categorical <- sum(!is.na(trait_data$OrigValueStr) & is.na(trait_data$StdValue))
  cat(sprintf("    - Trait %d: %d total (%d numeric, %d categorical)\n", 
              tid, nrow(trait_data), n_numeric, n_categorical))
}

# Check 4: Unique combinations before/after dedup
cat("\n  Deduplication effectiveness:\n")
cat(sprintf("    - Unique species-trait combinations: %d\n", 
            length(unique(paste(traits_only$AccSpeciesID, traits_only$TraitID)))))
cat(sprintf("    - Total trait records: %d\n", nrow(traits_only)))
cat(sprintf("    - Average records per species-trait: %.1f\n", 
            nrow(traits_only) / length(unique(paste(traits_only$AccSpeciesID, traits_only$TraitID)))))

# List traits with both types
cat("\n📝 Mixed-type trait IDs (have both numeric AND categorical):\n")
if(length(overlapping_traits) > 0) {
  cat(paste(sort(as.numeric(overlapping_traits)), collapse = ", "), "\n")
}

cat("\n📝 Numeric-only trait IDs:\n")
numeric_only <- setdiff(numeric_summary$TraitID, categorical_summary$TraitID)
cat(paste(sort(as.numeric(numeric_only)), collapse = ", "), "\n")

cat("\n📝 Categorical-only trait IDs:\n")
categorical_only <- setdiff(categorical_summary$TraitID, numeric_summary$TraitID)
cat(paste(sort(as.numeric(categorical_only)), collapse = ", "), "\n")

cat("\n✨ EIVE trait extraction complete (with integrity checks)! ✨\n")
cat("\nThis version correctly handles both numeric and categorical traits!\n")