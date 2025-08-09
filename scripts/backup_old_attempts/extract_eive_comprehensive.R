#!/usr/bin/env Rscript
# Adapted from the SUCCESSFUL extract_all_ellenberg_traits_comprehensive.R
# But for EIVE taxa using name matching

library(data.table)
library(rtry)  # Use official rtry package like the successful script!

cat("=== 🔮 COMPREHENSIVE TRAIT EXTRACTION FOR EIVE TAXA 🔮 ===\n")
cat("Extracting ALL traits for 14,835 EIVE taxa from all TRY datasets\n\n")

# Load EIVE taxa with WFO normalization
cat("📚 Loading EIVE taxa list...\n")
eive <- fread('data/EIVE/EIVE_TaxonConcept_WFO.csv', encoding = 'UTF-8')
cat(sprintf("  EIVE taxa count: %d\n", nrow(eive)))

# Normalize function
normalize_name <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub('[^a-z0-9 ]', ' ', x)
  x <- gsub('\\s+', ' ', x)
  trimws(x)
}

# Create normalized name set for matching
# Match on BOTH original EIVE names AND WFO accepted names
eive_norm <- unique(normalize_name(eive$TaxonConcept))
wfo_norm <- normalize_name(eive$wfo_accepted_name)
wfo_norm <- wfo_norm[!is.na(wfo_norm) & nzchar(wfo_norm)]
wfo_norm <- unique(wfo_norm)

# Combine both for maximum matching potential
target_names_set <- unique(c(eive_norm, wfo_norm))
target_names_set <- target_names_set[nzchar(target_names_set)]

cat(sprintf("  Target normalized names: %d\n", length(target_names_set)))
cat(sprintf("    - From EIVE TaxonConcept: %d\n", length(eive_norm)))
cat(sprintf("    - From WFO accepted names: %d\n", length(wfo_norm)))

# Define all 4 TRY datasets (same as your successful script)
datasets <- list(
  list(path = "data/TRY/43240_extract/43240.txt", name = "Dataset 1 (43240)"),
  list(path = "data/TRY/43244_extract/43244.txt", name = "Dataset 2 (43244)"),
  list(path = "data/TRY/43286_extract/43286.txt", name = "Dataset 3 (43286)"),
  list(path = "data/TRY/43289_extract/43289.txt", name = "Dataset 4 (43289)")
)

# Initialize collection for all data
all_traits_combined <- list()

# Process each dataset separately (LIKE YOUR SUCCESSFUL SCRIPT!)
for(i in seq_along(datasets)) {
  dataset <- datasets[[i]]
  
  cat(sprintf("\n🌟 Processing %s\n", dataset$name))
  cat(sprintf("  File: %s\n", dataset$path))
  
  file_size_mb <- file.info(dataset$path)$size / (1024^2)
  cat(sprintf("  File size: %.1f MB\n", file_size_mb))
  
  # Try to use rtry_import first (like the successful script)
  # If it fails due to memory, fall back to chunking
  
  tryCatch({
    # EXACTLY like the successful script!
    cat("  Importing data with rtry_import...\n")
    try_data <- rtry_import(dataset$path, showOverview = FALSE)
    
    # Ensure it's a data.table
    if(!is.data.table(try_data)) {
      try_data <- as.data.table(try_data)
    }
    
    # Normalize and filter for EIVE taxa
    cat("  Filtering for EIVE species...\n")
    try_data[, norm_species := normalize_name(SpeciesName)]
    try_data[, norm_acc := normalize_name(AccSpeciesName)]
    
    species_data <- try_data[norm_species %in% target_names_set | 
                            norm_acc %in% target_names_set]
    
    # Clean up to free memory
    rm(try_data)
    gc()
    
  }, error = function(e) {
    # If rtry_import fails (memory), use chunking
    cat("  rtry_import failed, using chunked processing...\n")
    
    con <- file(dataset$path, 'r', encoding = 'latin1')
    header_line <- readLines(con, n = 1, warn = FALSE)
    header <- strsplit(header_line, '\t', fixed = TRUE)[[1]]
    
    chunk_size <- 100000
    chunk_num <- 0
    dataset_data <- list()
    
    repeat {
      lines <- readLines(con, n = chunk_size, warn = FALSE)
      if (length(lines) == 0) break
      
      chunk_num <- chunk_num + 1
      if (chunk_num %% 10 == 0) {
        cat(sprintf("    Chunk %d...\n", chunk_num))
      }
      
      # Parse chunk
      split_lines <- strsplit(lines, '\t', fixed = TRUE)
      valid_lines <- sapply(split_lines, length) == length(header)
      
      if (any(valid_lines)) {
        mat <- do.call(rbind, split_lines[valid_lines])
        dt <- as.data.table(mat)
        setnames(dt, header)
        
        # Normalize and filter for EIVE taxa
        dt[, norm_species := normalize_name(SpeciesName)]
        dt[, norm_acc := normalize_name(AccSpeciesName)]
        
        # Keep only EIVE taxa
        eive_subset <- dt[norm_species %in% target_names_set | 
                         norm_acc %in% target_names_set]
        
        if (nrow(eive_subset) > 0) {
          dataset_data[[length(dataset_data) + 1]] <- eive_subset
        }
      }
    }
    close(con)
    
    # Combine chunks for this dataset
    if (length(dataset_data) > 0) {
      species_data <- rbindlist(dataset_data, fill = TRUE)
    } else {
      species_data <- data.table()
    }
  })
  
  # Get summary statistics
  n_species <- length(unique(species_data$AccSpeciesName))
  n_traits <- length(unique(species_data[!is.na(TraitID) & TraitID != "", TraitID]))
  n_records <- nrow(species_data)
  
  cat(sprintf("  Found: %d species, %d unique traits, %s records\n", 
              n_species, n_traits, format(n_records, big.mark = ',')))
  
  # Store this dataset's data
  species_data[, Dataset := dataset$name]
  all_traits_combined[[dataset$name]] <- species_data
  
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
combined_data <- rbindlist(all_traits_combined, fill = TRUE)

# Remove duplicates
cat("  Removing duplicates...\n")
combined_data[, unique_id := paste(AccSpeciesName, TraitID, StdValue, sep = "_")]
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
cat(sprintf("  Unique species: %d\n", length(unique(combined_unique$AccSpeciesName))))
cat(sprintf("  Unique traits: %d\n", length(unique(traits_only$TraitID))))

# Create trait summary
cat("\n📋 Creating trait availability summary...\n")
trait_summary <- traits_only[!is.na(StdValue), .(
  N_species = length(unique(AccSpeciesName)),
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
cat("\n💾 Saving comprehensive EIVE trait data...\n")

# Save all data
output_all <- "data/output/eive_all_traits_comprehensive.rds"
saveRDS(combined_unique, output_all)
cat(sprintf("  All data: %s (%.1f GB)\n", output_all, 
            file.info(output_all)$size / (1024^3)))

# Save traits only
output_traits <- "data/output/eive_traits_only.tsv"
fwrite(traits_only, output_traits, sep = '\t', quote = TRUE)
cat(sprintf("  Traits only: %s (%.1f GB)\n", output_traits,
            file.info(output_traits)$size / (1024^3)))

# Save trait summary
output_summary <- "data/output/eive_trait_summary.csv"
write.csv(trait_summary, output_summary, row.names = FALSE)
cat(sprintf("  Trait summary: %s\n", output_summary))

# List all trait IDs
cat("\n📝 All trait IDs found:\n")
all_trait_ids <- sort(as.numeric(unique(traits_only$TraitID)))
cat(paste(all_trait_ids, collapse = ", "), "\n")

cat("\n✨ EIVE trait extraction complete! ✨\n")