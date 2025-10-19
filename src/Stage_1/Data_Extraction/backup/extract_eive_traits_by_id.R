#!/usr/bin/env Rscript
# EIVE Trait Extraction using RTRY Standard Functions with Aggregation
# This version uses rtry library functions for proper duplicate handling and aggregation

library(rtry)      # Primary - use rtry functions whenever possible!
library(data.table) # Secondary - only for final processing

cat("=== 🚀 EIVE Trait Extraction Using RTRY Standard Functions ===\n\n")

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

# STEP 1: Import all datasets using rtry_import
cat("STEP 1: Importing all TRY datasets with rtry_import...\n")
all_data <- list()

for(i in seq_along(datasets)) {
  dataset <- datasets[[i]]
  
  cat(sprintf("\n🌟 Processing %s\n", dataset$name))
  cat(sprintf("  File: %s\n", dataset$path))
  
  file_size_mb <- file.info(dataset$path)$size / (1024^2)
  cat(sprintf("  File size: %.1f MB\n", file_size_mb))
  
  # Import using rtry_import - THE STANDARD WAY
  cat("  Importing with rtry_import (handles encoding properly)...\n")
  try_data <- rtry_import(dataset$path, showOverview = FALSE)
  
  # Use rtry_select_row for filtering - PROPER RTRY WAY!
  cat("  Filtering for EIVE species using rtry_select_row...\n")
  
  # Debug: Check if AccSpeciesIDs are matching (keep for diagnostics)
  unique_try_ids <- unique(try_data$AccSpeciesID)
  matching_ids <- intersect(unique_try_ids, species_ids)
  cat(sprintf("    Species ID matching: %d of %d EIVE IDs found in this dataset\n", 
              length(matching_ids), length(species_ids)))
  
  # CRITICAL: Use rtry_select_row with getAncillary=TRUE and rmDuplicates=FALSE (we'll do it later)
  species_data <- rtry_select_row(
    try_data,
    AccSpeciesID %in% species_ids,
    getAncillary = TRUE,     # Get all ancillary data
    rmDuplicates = FALSE,     # Keep duplicates for now - combine first!
    showOverview = FALSE
  )
  
  # Clean up immediately to free memory
  rm(try_data)
  gc()
  
  # Get summary statistics
  n_species <- length(unique(species_data$AccSpeciesID))
  n_traits <- length(unique(species_data$TraitID[!is.na(species_data$TraitID) & species_data$TraitID != ""]))
  n_records <- nrow(species_data)
  
  cat(sprintf("  Found: %d species, %d unique traits, %s records\n", 
              n_species, n_traits, format(n_records, big.mark = ',')))
  
  # Store this dataset's data
  all_data[[dataset$name]] <- species_data
  
  # Show trait frequency using rtry_explore
  if (nrow(species_data) > 0) {
    cat("\n  📊 Top 10 traits in this dataset:\n")
    trait_freq <- rtry_explore(species_data, TraitID, TraitName, 
                              sortBy = "Count", showOverview = FALSE)
    # Filter for actual traits (not ancillary)
    trait_freq <- trait_freq[!is.na(trait_freq$TraitID) & trait_freq$TraitID != "",]
    top_traits <- head(trait_freq[order(-trait_freq$Count),], 10)
    for(j in 1:nrow(top_traits)) {
      cat(sprintf("    %2d. ID %5s: %s (n=%s)\n", 
                  j, 
                  top_traits$TraitID[j], 
                  substr(top_traits$TraitName[j], 1, 45),
                  format(top_traits$Count[j], big.mark = ',')))
    }
  }
}

# STEP 2: Combine all datasets - handle type mismatches
cat("\n🔄 STEP 2: Combining all datasets...\n")

# Fix type mismatches comprehensively (filtering creates all-NA columns)
cat("  Harmonizing column types across datasets...\n")

# Get all column names from all datasets
all_columns <- unique(unlist(lapply(all_data, names)))

# For each dataset, ensure all character columns are character type
for(i in seq_along(all_data)) {
  df <- all_data[[i]]
  
  # Check EVERY column for type mismatches
  for(col in names(df)) {
    # If this column is logical (all NA) but should be character
    if(is.logical(df[[col]])) {
      # Check if this column is character in ANY other dataset
      is_char_elsewhere <- FALSE
      for(j in seq_along(all_data)) {
        if(j != i && col %in% names(all_data[[j]])) {
          if(is.character(all_data[[j]][[col]])) {
            is_char_elsewhere <- TRUE
            break
          }
        }
      }
      
      # If it's character elsewhere, convert it here too
      if(is_char_elsewhere) {
        cat(sprintf("    Dataset %d: Converting %s from logical to character\n", i, col))
        all_data[[i]][[col]] <- as.character(df[[col]])
      }
    }
  }
}

# Alternative: Use data.table's rbindlist which is more forgiving
cat("  Combining datasets (using rbindlist for robustness)...\n")
combined_data <- rbindlist(all_data, fill = TRUE, use.names = TRUE)
cat(sprintf("  Combined data: %d rows, %d columns\n", nrow(combined_data), ncol(combined_data)))

# Track data before deduplication
cat(sprintf("  Records before deduplication: %s\n", format(nrow(combined_data), big.mark = ",")))

# Count Plant growth form before dedup for comparison
trait_42_before <- sum(combined_data$TraitID == 42, na.rm = TRUE)
cat(sprintf("  Plant growth form (ID 42) before dedup: %d records\n", trait_42_before))

# STEP 3: Remove duplicates using rtry_remove_dup - THE PROPER WAY!
cat("\n🔧 STEP 3: Removing duplicates with rtry_remove_dup...\n")
combined_unique <- rtry_remove_dup(combined_data, showOverview = TRUE)

# STEP 4: Exclude outliers using rtry_exclude (if any exist)
cat("\n🔧 STEP 4: Checking for outliers (ErrorRisk > 4)...\n")

# First check if ErrorRisk column exists and has values > 4
n_outliers <- sum(combined_unique$ErrorRisk > 4, na.rm = TRUE)
cat(sprintf("  Found %d records with ErrorRisk > 4\n", n_outliers))

if (n_outliers > 0) {
  cat("  Excluding outliers with rtry_exclude...\n")
  combined_clean <- rtry_exclude(
    combined_unique,
    ErrorRisk > 4,
    baseOn = ObsDataID,  # No quotes! It's a symbol, not a string
    showOverview = TRUE
  )
} else {
  cat("  No outliers to exclude (all ErrorRisk <= 4 or NA)\n")
  combined_clean <- combined_unique
}

# STEP 5: Separate numeric and categorical traits for processing
cat("\n📊 STEP 5: Processing numeric and categorical traits separately...\n")

# Extract numeric traits (those with StdValue)
numeric_traits <- rtry_select_row(
  combined_clean,
  !is.na(TraitID) & !is.na(StdValue),
  showOverview = FALSE
)
cat(sprintf("  Numeric trait records: %s\n", format(nrow(numeric_traits), big.mark = ',')))

# Extract categorical traits (those with OrigValueStr but no StdValue)
categorical_traits <- rtry_select_row(
  combined_clean,
  !is.na(TraitID) & is.na(StdValue) & !is.na(OrigValueStr),
  showOverview = FALSE
)
cat(sprintf("  Categorical trait records: %s\n", format(nrow(categorical_traits), big.mark = ',')))

# Get metadata records
metadata_only <- rtry_select_row(
  combined_clean,
  is.na(TraitID) | TraitID == "",
  showOverview = FALSE
)
cat(sprintf("  Metadata records: %s\n", format(nrow(metadata_only), big.mark = ',')))

# Get final statistics
cat("\n📈 FINAL COMBINED STATISTICS:\n")
cat(sprintf("  Total records: %s\n", format(nrow(combined_clean), big.mark = ',')))
cat(sprintf("    - Numeric trait records: %s\n", format(nrow(numeric_traits), big.mark = ',')))
cat(sprintf("    - Categorical trait records: %s\n", format(nrow(categorical_traits), big.mark = ',')))
cat(sprintf("    - Metadata records: %s\n", format(nrow(metadata_only), big.mark = ',')))
cat(sprintf("  Unique species: %d\n", length(unique(combined_clean$AccSpeciesID))))
cat(sprintf("  Unique traits: %d\n", length(unique(c(numeric_traits$TraitID, categorical_traits$TraitID)))))

# STEP 6: Create aggregated species-trait matrices
cat("\n📋 STEP 6: Creating aggregated species-trait matrices...\n")

# 6A. NUMERIC TRAITS - Use rtry_trans_wider for automatic aggregation!
cat("  Creating numeric trait matrix with rtry_trans_wider (automatic aggregation)...\n")

# CRITICAL: Select ONLY the columns needed for species-level aggregation
# Do NOT include ObservationID - that would create observation-level rows!
cat("    Selecting only species, trait, and value columns...\n")
numeric_for_wide <- rtry_select_col(
  numeric_traits,
  AccSpeciesID, AccSpeciesName, TraitID, StdValue,
  showOverview = FALSE
)

# Now transform to wide format with SPECIES-LEVEL aggregation
cat("    Transforming to wide format with mean aggregation per species-trait...\n")
numeric_matrix <- rtry_trans_wider(
  numeric_for_wide,
  names_from = "TraitID",  # Column names from TraitID
  values_from = "StdValue",  # Values from StdValue
  values_fn = list(StdValue = mean),  # MEAN aggregation per species!
  showOverview = TRUE
)

# 6B. CATEGORICAL TRAITS - Need custom processing for mode
cat("\n  Processing categorical traits (computing mode per species-trait)...\n")
if (nrow(categorical_traits) > 0) {
  # Convert to data.table for efficient mode calculation
  cat_dt <- as.data.table(categorical_traits)
  
  # Calculate mode (most frequent value) per species-trait combination
  categorical_summary <- cat_dt[, .(
    Value = names(sort(table(OrigValueStr), decreasing=TRUE))[1],
    N_observations = .N
  ), by = .(AccSpeciesID, AccSpeciesName, TraitID, TraitName)]
  
  # Show sample of categorical aggregation
  cat("\n  Sample categorical trait aggregation (first 5):\n")
  print(head(categorical_summary))
  
  # Create wide format for categorical traits
  cat_matrix <- dcast(categorical_summary,
                      AccSpeciesID + AccSpeciesName ~ paste0("Cat_", TraitID),
                      value.var = "Value")
  
  cat(sprintf("  Categorical matrix: %d species × %d traits\n", 
              nrow(cat_matrix), ncol(cat_matrix) - 2))
} else {
  cat_matrix <- NULL
}

# 6C. Create trait summaries using rtry_explore
cat("\n  Creating trait frequency summaries with rtry_explore...\n")
trait_summary <- rtry_explore(combined_clean, TraitID, TraitName, 
                              sortBy = "Count", showOverview = FALSE)
# Filter for actual traits
trait_summary <- trait_summary[!is.na(trait_summary$TraitID) & trait_summary$TraitID != "",]

# Sort by count (frequency)
trait_summary <- trait_summary[order(-trait_summary$Count),]

# Show top traits
cat("\n🏆 Top 30 traits by frequency:\n")
for(i in 1:min(30, nrow(trait_summary))) {
  cat(sprintf("  %2d. ID %5s: %s (n=%s)\n", 
              i,
              trait_summary$TraitID[i],
              substr(trait_summary$TraitName[i], 1, 50),
              format(trait_summary$Count[i], big.mark = ',')))
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

# STEP 7: Save outputs
cat("\n💾 STEP 7: Saving EIVE trait data...\n")

# Save all cleaned data
output_all <- "data/output/eive_all_traits_by_id.rds"
saveRDS(combined_clean, output_all)
cat(sprintf("  All cleaned data: %s (%.1f GB)\n", output_all, 
            file.info(output_all)$size / (1024^3)))

# Save numeric matrix using rtry_export
output_numeric <- "data/output/eive_numeric_trait_matrix.csv"
rtry_export(numeric_matrix, output_numeric, encoding = "UTF-8")
cat(sprintf("  Numeric trait matrix: %s (%.1f MB)\n", output_numeric,
            file.info(output_numeric)$size / (1024^2)))

# Save categorical matrix if it exists
if (!is.null(cat_matrix)) {
  output_categorical <- "data/output/eive_categorical_trait_matrix.csv"
  rtry_export(cat_matrix, output_categorical, encoding = "UTF-8")
  cat(sprintf("  Categorical trait matrix: %s (%.1f MB)\n", output_categorical,
              file.info(output_categorical)$size / (1024^2)))
}

# Save trait summary
output_summary <- "data/output/eive_trait_summary_by_id.csv"
rtry_export(trait_summary, output_summary, encoding = "UTF-8")
cat(sprintf("  Trait summary: %s\n", output_summary))

# STEP 8: Create coverage report
cat("\n📊 STEP 8: Coverage Analysis...\n")

# Count traits per species in numeric matrix
trait_cols <- setdiff(names(numeric_matrix), c("AccSpeciesID", "AccSpeciesName"))
n_traits_per_species <- rowSums(!is.na(numeric_matrix[,trait_cols]))

cat(sprintf("  Numeric matrix: %d species × %d traits\n", 
            nrow(numeric_matrix), length(trait_cols)))
cat(sprintf("  Mean traits per species: %.1f\n", mean(n_traits_per_species)))
cat(sprintf("  Max traits per species: %d\n", max(n_traits_per_species)))

# Check for traits that have BOTH numeric and categorical values
if (!is.null(cat_matrix)) {
  numeric_trait_ids <- as.numeric(gsub("^X", "", trait_cols))
  categorical_trait_ids <- as.numeric(gsub("^Cat_", "", 
                          setdiff(names(cat_matrix), c("AccSpeciesID", "AccSpeciesName"))))
  
  overlapping_traits <- intersect(numeric_trait_ids, categorical_trait_ids)
  if(length(overlapping_traits) > 0) {
    cat(sprintf("  ⚠️ WARNING: %d traits have BOTH numeric AND categorical values!\n", 
                length(overlapping_traits)))
    cat(sprintf("     Mixed traits: %s\n", paste(head(overlapping_traits, 10), collapse=", ")))
  }
}

# STEP 9: DATA INTEGRITY CHECKS (KEEPING ORIGINAL LOGIC)
cat("\n🔍 STEP 9: DATA INTEGRITY VERIFICATION:\n")

# Check 1: Verify Plant growth form (ID 42) records
trait_42_after <- sum(categorical_traits$TraitID == 42, na.rm = TRUE)
cat(sprintf("  Plant growth form (ID 42) check:\n"))
cat(sprintf("    - Records before dedup: %d\n", trait_42_before))
cat(sprintf("    - Records after processing: %d\n", trait_42_after))
cat(sprintf("    - Data retention rate: %.1f%%\n", 100 * trait_42_after / trait_42_before))

# Check 2: Verify aggregation worked
if (nrow(numeric_matrix) > 0) {
  cat("\n  Aggregation check (numeric traits):\n")
  cat(sprintf("    - Original records: %s\n", format(nrow(numeric_traits), big.mark=",")))
  cat(sprintf("    - Aggregated to: %d species × %d traits\n", 
              nrow(numeric_matrix), length(trait_cols)))
  # Calculate actual cells with data
  n_cells_with_data <- sum(!is.na(numeric_matrix[,trait_cols]))
  cat(sprintf("    - Cells with data: %s (%.1f%% fill rate)\n",
              format(n_cells_with_data, big.mark=","),
              100 * n_cells_with_data / (nrow(numeric_matrix) * length(trait_cols))))
  cat(sprintf("    - Average observations per species-trait: %.1f\n", 
              nrow(numeric_traits) / n_cells_with_data))
}

# Check 3: Sample some high-frequency traits
cat("\n  High-frequency trait verification:\n")
for(tid in c(42, 28, 26, 3106)) {
  n_numeric <- sum(numeric_traits$TraitID == tid, na.rm = TRUE)
  n_categorical <- sum(categorical_traits$TraitID == tid, na.rm = TRUE)
  if (n_numeric > 0 || n_categorical > 0) {
    cat(sprintf("    - Trait %d: %d numeric, %d categorical\n", 
                tid, n_numeric, n_categorical))
  }
}

# Check 4: Species with most traits
if (nrow(numeric_matrix) > 0 && length(n_traits_per_species) > 0) {
  # Get indices of species with most traits
  top_indices <- head(order(n_traits_per_species, decreasing = TRUE), 5)
  cat("\n  Species with most traits:\n")
  for(i in seq_along(top_indices)) {
    idx <- top_indices[i]
    cat(sprintf("    %d. %s: %d traits\n", 
                i, numeric_matrix$AccSpeciesName[idx], n_traits_per_species[idx]))
  }
}

cat("\n=== FINAL SUMMARY ===\n")
cat("✨ EIVE trait extraction complete using RTRY standard functions! ✨\n\n")

cat("KEY IMPROVEMENTS in this version:\n")
cat("  1. rtry_import() for proper encoding handling\n")
cat("  2. rtry_select_row() for filtering with getAncillary=TRUE\n")
cat("  3. rtry_remove_dup() using OrigObsDataID (official duplicate removal)\n")
cat("  4. rtry_exclude() for outlier removal (ErrorRisk > 4)\n")
cat("  5. rtry_trans_wider() for AUTOMATIC aggregation (mean)\n")
cat("  6. rtry_explore() for trait frequency analysis\n")
cat("  7. rtry_export() for standardized output\n")

cat("\nOUTPUTS CREATED:\n")
cat(sprintf("  - Numeric trait matrix: %d species × %d traits (aggregated means)\n", 
            nrow(numeric_matrix), length(trait_cols)))
if (!is.null(cat_matrix)) {
  cat(sprintf("  - Categorical trait matrix: %d species × %d traits (modes)\n",
              nrow(cat_matrix), ncol(cat_matrix) - 2))
}
cat("  - Trait summary: Frequency and coverage statistics\n")
cat("  - All data preserved in RDS format\n")

cat("\nThis approach follows TRY best practices and ensures data integrity!\n")