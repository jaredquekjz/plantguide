#!/usr/bin/env Rscript

# Merge trait data with bioclim data to create complete dataset

library(tidyverse)

cat("=== Merging Trait and Bioclim Data ===\n")

# Load trait data
trait_data <- read.csv("/home/olier/ellenberg/artifacts/model_data_complete_case_with_myco.csv", 
                       stringsAsFactors = FALSE)

# Load bioclim summary
bioclim_data <- read.csv("/home/olier/ellenberg/data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv",
                         stringsAsFactors = FALSE)

cat(sprintf("Trait data: %d species\n", nrow(trait_data)))
cat(sprintf("Bioclim data: %d species\n", nrow(bioclim_data)))

# Filter bioclim to sufficient data only
bioclim_sufficient <- bioclim_data %>%
  filter(has_sufficient_data == TRUE) %>%
  select(species, starts_with("bio") & ends_with("_mean"))

# Rename bioclim columns (remove _mean suffix)
names(bioclim_sufficient) <- gsub("_mean$", "", names(bioclim_sufficient))

cat(sprintf("Bioclim with sufficient data: %d species\n", nrow(bioclim_sufficient)))

# Normalize species names for matching
normalize_species <- function(x) {
  tolower(gsub("[[:space:]_-]+", "_", x))
}

trait_data$species_norm <- normalize_species(trait_data$wfo_accepted_name)
bioclim_sufficient$species_norm <- normalize_species(bioclim_sufficient$species)

# Merge datasets
merged_data <- inner_join(trait_data, bioclim_sufficient, by = "species_norm")

cat(sprintf("\nMerged data: %d species with both traits and bioclim\n", nrow(merged_data)))

# Select relevant columns (drop duplicate/norm columns)
merged_data <- merged_data %>%
  select(-species_norm, -species)

# Check current column names
cat("\nColumn names in merged data:\n")
print(names(merged_data)[1:20])

# Clean up column names
names(merged_data) <- gsub("\\.", "_", names(merged_data))

# Create cleaner names for EIVE axes
if ("EIVEres_L" %in% names(merged_data)) {
  merged_data <- merged_data %>%
    rename(
      L = EIVEres_L,
      T = EIVEres_T,
      M = EIVEres_M,
      R = EIVEres_R,
      N = EIVEres_N
    )
}

# Create cleaner names for traits
if ("Leaf_area__mm2_" %in% names(merged_data)) {
  merged_data <- merged_data %>%
    rename(
      LA = Leaf_area__mm2_,
      LMA = LMA__g_m2_,
      H = Plant_height__m_,
      SM = Diaspore_mass__mg_,
      SSD = SSD_used__mg_mm3_
    )
}

# Save merged dataset
output_path <- "/home/olier/ellenberg/artifacts/model_data_trait_bioclim_merged.csv"
write.csv(merged_data, output_path, row.names = FALSE)

cat(sprintf("\nSaved merged dataset to: %s\n", output_path))

# Summary of data completeness by axis
for (axis in c("L", "T", "M", "R", "N")) {
  n_complete <- sum(!is.na(merged_data[[axis]]))
  cat(sprintf("  %s: %d species with data\n", axis, n_complete))
}

# Check bioclim variables
bio_cols <- grep("^bio[0-9]+$", names(merged_data), value = TRUE)
cat(sprintf("\nBioclim variables included: %s\n", paste(bio_cols, collapse = ", ")))