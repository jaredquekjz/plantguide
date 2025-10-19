# SCRIPT PURPOSE:
# Re-organize the raw Mycorrhiza type data (Trait 7) into a clean,
# one-to-one mapping of species to a standardized mycorrhizal group.
# This script is the data preparation step for Action 1 in the
# sem_improvement_checklist.md.

# 0. Setup
# Specify the library path and load necessary libraries
.libPaths("/home/olier/ellenberg/.Rlib")
library(data.table)
library(dplyr)

# Define file paths
input_file <- "/home/olier/ellenberg/artifacts/stage1_data_extraction/trait_7_myco_type.rds"
output_dir <- "/home/olier/ellenberg/artifacts/stage1_myco_cleaning"
output_file <- file.path(output_dir, "species_myco_groups.rds")

# Create output directory if it doesn't exist
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
  message("Created output directory: ", output_dir)
}

# 1. Load the extracted data
message("Loading data from: ", input_file)
trait_data <- readRDS(input_file)
setDT(trait_data) # Convert to data.table for efficiency

# 2. Standardize Mycorrhizal Categories
message("Standardizing mycorrhizal categories...")
trait_data[, Myco_Group := fcase(
  # Arbuscular Mycorrhiza (AM)
  OrigValueStr %in% c("AM", "arbuscular", "VAM", "vesicular-arbuscular mycorrhiza", "Ph.th.end."), "AM",
  # Ectomycorrhiza (EM)
  OrigValueStr %in% c("EM", "Ecto", "ECTO", "ectomycorrhiza", "Ectomycorrhiza", "ecto"), "EM",
  # Ericoid Mycorrhiza (ERM)
  OrigValueStr %in% c("Ericoid", "ericoid", "ERM", "ErM", "ericoid mycorrhiza"), "ERM",
  # Non-Mycorrhizal (NM)
  OrigValueStr %in% c("NM", "No", "no", "absent", "Non", "0"), "NM",
  # Facultative / Mixed Types
  OrigValueStr %in% c("NM/AM", "AMNM", "AM + EM"), "Facultative_AM_NM",
  # Other specific Mycorrhizal types
  OrigValueStr %in% c("Orchid", "orchid", "OrM", "orchid mycorrhiza", "monotropoid", "arbutoid"), "Other_Myco",
  # Default to NA for anything else (junk, unclear, "Yes")
  default = NA_character_
)]

# Report on standardization
original_rows <- nrow(trait_data)
trait_data <- na.omit(trait_data, cols = "Myco_Group")
cleaned_rows <- nrow(trait_data)
message(paste("Removed", original_rows - cleaned_rows, "records with unclear/junk categories."))

# 3. Aggregate by Species to get the most common Myco_Group
message("Aggregating to find the most common group for each species...")

# Count occurrences of each group for each species
species_group_counts <- trait_data[, .N, by = .(AccSpeciesName, Myco_Group)]

# For each species, find the group with the highest count
# The `order(-N)` and `.[, .SD[1], ...]` combination is a standard data.table way
# to select the top record per group.
species_myco_clean <- species_group_counts[order(-N), .SD[1], by = AccSpeciesName]

# Select final columns
species_myco_final <- species_myco_clean[, .(AccSpeciesName, Myco_Group)]

# 4. Save the Cleaned Data
message(paste("Saving", nrow(species_myco_final), "cleaned species-myco mappings to:", output_file))
saveRDS(species_myco_final, file = output_file)

# Final summary
message("\n--- Reorganization Complete ---")
message("Final unique species with assigned Myco_Group: ", nrow(species_myco_final))
message("Myco Group distribution:")
print(table(species_myco_final$Myco_Group))
message("---------------------------------")
