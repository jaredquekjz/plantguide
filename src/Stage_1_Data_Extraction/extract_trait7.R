# Specify the library path
.libPaths("/home/olier/ellenberg/.Rlib")

# Load necessary libraries
# Ensure rtry is installed. If not, run: install.packages("rtry")
library(rtry)
library(dplyr)

# Define file paths
input_file <- "/home/olier/ellenberg/data/TRY/43244.txt"
output_dir <- "/home/olier/ellenberg/artifacts/stage1_data_extraction"
output_file <- file.path(output_dir, "trait_7_myco_type.rds")

# Create output directory if it doesn't exist
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# 1. Import the TRY data file
# The rtry_import function is designed for TRY text files, using tab as a separator
# and Latin-1 encoding by default.
message("Importing data from: ", input_file)
try_data <- rtry_import(input_file)

# 2. Select rows with TraitID 7 (Mycorrhiza type)
message("Selecting rows for TraitID 7...")
# Using dplyr::filter for clarity, as it's a very common pattern.
trait7_data <- dplyr::filter(try_data, TraitID == 7)

# 3. Select relevant columns
# We are interested in the species name and the trait value.
message("Selecting relevant columns...")
trait7_data_selected <- rtry_select_col(trait7_data,
                                        AccSpeciesName,
                                        SpeciesName,
                                        TraitID,
                                        TraitName,
                                        OrigValueStr,
                                        StdValue,
                                        ValueKindName)


# 4. Save the resulting data frame to an .rds file
message("Saving extracted data to: ", output_file)
saveRDS(trait7_data_selected, file = output_file)

message("Script finished successfully.")
message(paste("Extracted data for", nrow(trait7_data_selected), "records and saved to", output_file))