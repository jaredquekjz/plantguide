# Extract multiple traits from TRY data
# Traits: 7 (Mycorrhiza type), 46 (Leaf thickness), 37 (Leaf phenology type),
#         22 (Photosynthesis pathway), 31 (Species tolerance to frost)

# Specify the library path
.libPaths("/home/olier/ellenberg/.Rlib")

# Load necessary libraries
# Ensure rtry is installed. If not, run: install.packages("rtry")
library(rtry)
library(dplyr)

# Define traits to extract
target_traits <- list(
  list(id = 7, name = "mycorrhiza_type", desc = "Mycorrhiza type"),
  list(id = 46, name = "leaf_thickness", desc = "Leaf thickness"),
  list(id = 37, name = "leaf_phenology_type", desc = "Leaf phenology type"),
  list(id = 22, name = "photosynthesis_pathway", desc = "Photosynthesis pathway"),
  list(id = 31, name = "species_tolerance_to_frost", desc = "Species tolerance to frost")
)

# Define file paths
input_files <- list(
  "/home/olier/ellenberg/data/TRY/43244.txt",  # Main file with most traits
  "/home/olier/ellenberg/data/TRY/43289.txt"   # Has additional phenology data
)

output_dir <- "/home/olier/ellenberg/artifacts/stage1_data_extraction"

# Create output directory if it doesn't exist
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Process each file
for (input_file in input_files) {
  if (!file.exists(input_file)) {
    message("File not found, skipping: ", input_file)
    next
  }
  
  message("\n===================================")
  message("Processing file: ", basename(input_file))
  message("===================================")
  
  # 1. Import the TRY data file
  # The rtry_import function is designed for TRY text files, using tab as a separator
  # and Latin-1 encoding by default.
  message("Importing data from: ", input_file)
  try_data <- rtry_import(input_file)
  
  # Process each trait
  for (trait in target_traits) {
    message("\n-----------------------------------")
    message("Extracting Trait ", trait$id, " (", trait$desc, ")...")
    
    # 2. Select rows with the specific TraitID
    trait_data <- dplyr::filter(try_data, TraitID == trait$id)
    
    if (nrow(trait_data) > 0) {
      # 3. Select relevant columns
      # We are interested in the species name and the trait value.
      trait_data_selected <- rtry_select_col(trait_data,
                                            AccSpeciesID,
                                            AccSpeciesName,
                                            SpeciesName,
                                            TraitID,
                                            TraitName,
                                            DataID,
                                            DataName,
                                            OrigValueStr,
                                            StdValue,
                                            ValueKindName,
                                            OrigUnitStr,
                                            UnitName)
      
      # 4. Create output file name based on input file
      file_suffix <- gsub(".txt", "", basename(input_file))
      output_file <- file.path(output_dir, 
                              paste0("trait_", trait$id, "_", trait$name, "_", file_suffix, ".rds"))
      
      # 5. Save the resulting data frame to an .rds file
      message("Saving extracted data to: ", output_file)
      saveRDS(trait_data_selected, file = output_file)
      
      # Report summary
      n_records <- nrow(trait_data_selected)
      n_species <- length(unique(trait_data_selected$AccSpeciesName))
      message(paste("Extracted", n_records, "records for", n_species, "unique species"))
      
      # Show sample values for categorical traits
      if (trait$id %in% c(7, 37, 22)) {
        unique_vals <- unique(trait_data_selected$OrigValueStr[!is.na(trait_data_selected$OrigValueStr)])
        message("Sample values: ", paste(head(unique_vals, 10), collapse = ", "))
      }
    } else {
      message("No data found for Trait ", trait$id, " in this file")
    }
  }
  
  # Clean up memory after processing each file
  rm(try_data)
  gc(verbose = FALSE)
}

# Combine results from multiple files for each trait
message("\n===================================")
message("Combining results from multiple files...")
message("===================================")

for (trait in target_traits) {
  # Find all files for this trait
  pattern <- paste0("trait_", trait$id, "_", trait$name, "_.*\\.rds$")
  trait_files <- list.files(output_dir, pattern = pattern, full.names = TRUE)
  
  if (length(trait_files) > 0) {
    message("\nCombining Trait ", trait$id, " (", trait$desc, ")...")
    
    # Read and combine all files
    combined_data <- NULL
    for (file in trait_files) {
      data <- readRDS(file)
      if (is.null(combined_data)) {
        combined_data <- data
      } else {
        combined_data <- rbind(combined_data, data)
      }
    }
    
    # Remove duplicates
    combined_data <- unique(combined_data)
    
    # Save combined file
    output_file <- file.path(output_dir, paste0("trait_", trait$id, "_", trait$name, "_combined.rds"))
    saveRDS(combined_data, file = output_file)
    
    # Report summary
    n_records <- nrow(combined_data)
    n_species <- length(unique(combined_data$AccSpeciesName))
    message(paste("  Combined:", n_records, "total records,", n_species, "unique species"))
    message("  Saved to:", output_file)
    
    # Clean up individual files (optional - comment out if you want to keep them)
    # for (file in trait_files) {
    #   file.remove(file)
    # }
  }
}

# Create summary CSV
message("\n===================================")
message("Creating summary report...")
message("===================================")

summary_data <- data.frame(
  TraitID = integer(),
  TraitName = character(),
  Description = character(),
  TotalRecords = integer(),
  UniqueSpecies = integer(),
  stringsAsFactors = FALSE
)

for (trait in target_traits) {
  combined_file <- file.path(output_dir, paste0("trait_", trait$id, "_", trait$name, "_combined.rds"))
  if (file.exists(combined_file)) {
    data <- readRDS(combined_file)
    summary_data <- rbind(summary_data, data.frame(
      TraitID = trait$id,
      TraitName = trait$name,
      Description = trait$desc,
      TotalRecords = nrow(data),
      UniqueSpecies = length(unique(data$AccSpeciesName)),
      stringsAsFactors = FALSE
    ))
  }
}

summary_file <- file.path(output_dir, "extracted_traits_summary.csv")
write.csv(summary_data, summary_file, row.names = FALSE)
message("Summary saved to: ", summary_file)

message("\n===================================")
message("Script finished successfully!")
message("===================================")
message("All extracted trait data saved to: ", output_dir)