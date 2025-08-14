# Specify the library path where rtry and its dependencies are installed
.libPaths("/home/olier/ellenberg/.Rlib")

# Load dplyr for n_distinct function
library(dplyr)

# Define the path to the .rds file
rds_file <- "/home/olier/ellenberg/artifacts/stage1_data_extraction/trait_7_myco_type.rds"

# Read the .rds file into a data frame
message("Reading data from: ", rds_file)
trait_data <- readRDS(rds_file)

# --- Analysis ---

# 1. Display the structure of the data frame
message("\n--- Data Structure (str) ---")
str(trait_data)

# 2. Show the first few rows to inspect the content
message("\n--- First 6 Rows (head) ---")
print(head(trait_data))

# 3. Summarize the key columns
message("\n--- Key Column Analysis ---")

# Count unique species to see if data is aggregated by species
unique_species_count <- n_distinct(trait_data$AccSpeciesName)
total_rows <- nrow(trait_data)
message(paste("Total records:", total_rows))
message(paste("Unique species names (AccSpeciesName):", unique_species_count))
message(paste("Average records per species:", round(total_rows / unique_species_count, 2)))

# Display the different mycorrhiza types and their frequencies
message("\n--- Mycorrhiza Type Frequencies (OrigValueStr) ---")
print(table(trait_data$OrigValueStr))

message("\nAnalysis complete.")
