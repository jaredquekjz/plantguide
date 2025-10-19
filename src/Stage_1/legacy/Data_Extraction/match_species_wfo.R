# SCRIPT PURPOSE:
# To taxonomically standardize the cleaned mycorrhizal species list against the
# World Flora Online (WFO) accepted names list. This script matches the species
# from our classified myco data with the WFO reference, keeping only the matched
# species and adopting the WFO accepted name.

# 0. Setup
# Specify the library path and load necessary libraries
.libPaths("/home/olier/ellenberg/.Rlib")
library(rtry)
library(data.table)

# Define file paths
myco_input_file <- "/home/olier/ellenberg/artifacts/stage1_myco_cleaning/species_myco_groups_classified.rds"
wfo_input_file <- "/home/olier/ellenberg/data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv"
output_dir <- "/home/olier/ellenberg/data" # As requested, save to data folder
output_file <- file.path(output_dir, "species_myco_wfo_matched.rds")

# 1. Load the classified mycorrhizal data
message("Loading classified mycorrhizal data from: ", myco_input_file)
myco_data <- readRDS(myco_input_file)
setDT(myco_data)

# 2. Load the WFO taxonomic reference data using rtry_import
message("Loading WFO taxonomic reference data from: ", wfo_input_file)
# Use rtry_import, specifying comma as separator and UTF-8 encoding
wfo_data <- rtry_import(wfo_input_file, separator = ",", encoding = "UTF-8")
setDT(wfo_data)

# Examine the structure of the WFO data
message("WFO Data Head:")
print(head(wfo_data))
message("Column names in WFO data: ", paste(names(wfo_data), collapse = ", "))


# 3. Perform the taxonomic match (Left Join)
message("Performing left join to match myco data with WFO accepted names...")
# We match `AccSpeciesName` from TRY with `TaxonConcept` from the EIVE file.
# `all.x = FALSE` makes this an inner join, keeping only matched species.
matched_data <- merge(myco_data, wfo_data,
                      by.x = "AccSpeciesName",
                      by.y = "TaxonConcept",
                      all.x = FALSE)

message(paste("Successfully matched", nrow(matched_data), "out of", nrow(myco_data), "species."))

# 4. Clean up and select final columns
# The key columns are the accepted WFO name and our final Myco Group.
final_matched_data <- matched_data[, .(
  wfo_accepted_name,
  Myco_Group_Final,
  original_name = AccSpeciesName,
  total_records
)]

# Remove any rows where the accepted name is blank
final_matched_data <- final_matched_data[wfo_accepted_name != ""]


# 5. Save the final, matched data
message(paste("Saving", nrow(final_matched_data), "taxonomically standardized species to:", output_file))
saveRDS(final_matched_data, file = output_file)

# --- Final Summary ---
message("\n--- Taxonomic Standardization Complete ---")
message("Final matched and cleaned species count: ", nrow(final_matched_data))
message("Data saved to: ", output_file)
message("------------------------------------------")
