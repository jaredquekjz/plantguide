# SCRIPT PURPOSE:
# Re-organize the raw Mycorrhiza type data (Trait 7) into a clean,
# one-to-one mapping of species to a standardized, evidence-based mycorrhizal group.
# This script implements a sophisticated, rule-based approach informed by best
# practices for handling facultative associations in trait databases.
# This is the data preparation step for Action 1 in sem_improvement_checklist.md.

# 0. Setup
# Specify the library path and load necessary libraries
.libPaths("/home/olier/ellenberg/.Rlib")
library(data.table)
library(dplyr)

# Define file paths
input_file <- "/home/olier/ellenberg/artifacts/stage1_data_extraction/trait_7_myco_type.rds"
output_dir <- "/home/olier/ellenberg/artifacts/stage1_myco_cleaning"
output_file <- file.path(output_dir, "species_myco_groups_classified.rds")
csv_output_file <- file.path(output_dir, "species_myco_groups_classified_summary.csv")

# Create output directory if it doesn't exist
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# 1. Load the extracted data
message("Loading raw data from: ", input_file)
trait_data <- readRDS(input_file)
setDT(trait_data)

# 2. Standardize Mycorrhizal Categories
message("Standardizing raw mycorrhizal categories...")
trait_data[, Myco_Standard := fcase(
  OrigValueStr %in% c("AM", "arbuscular", "VAM", "vesicular-arbuscular mycorrhiza", "Ph.th.end."), "AM",
  OrigValueStr %in% c("EM", "Ecto", "ECTO", "ectomycorrhiza", "Ectomycorrhiza", "ecto"), "EM",
  OrigValueStr %in% c("Ericoid", "ericoid", "ERM", "ErM", "ericoid mycorrhiza"), "ERM",
  OrigValueStr %in% c("NM", "No", "no", "absent", "Non", "0"), "NM",
  OrigValueStr %in% c("NM/AM", "AMNM"), "AM_NM_Reported", # Temporarily code reported facultative
  OrigValueStr %in% c("AM + EM"), "AM_EM_Reported",
  OrigValueStr %in% c("Orchid", "orchid", "OrM", "orchid mycorrhiza", "monotropoid", "arbutoid"), "Other_Myco",
  default = NA_character_
)]

original_rows <- nrow(trait_data)
trait_data <- na.omit(trait_data, cols = "Myco_Standard")
cleaned_rows <- nrow(trait_data)
message(paste("Removed", original_rows - cleaned_rows, "records with unclear/junk categories."))

# 3. Apply Classification Rules Based on Consensus and Confidence
message("Applying rule-based classification for each species...")

# Calculate total valid records and proportions for each standardized type per species
species_summary <- trait_data[, .(
  total_records = .N,
  prop_AM = sum(Myco_Standard == "AM") / .N,
  prop_EM = sum(Myco_Standard == "EM") / .N,
  prop_NM = sum(Myco_Standard == "NM") / .N,
  prop_ERM = sum(Myco_Standard == "ERM") / .N,
  prop_Other = sum(Myco_Standard == "Other_Myco") / .N,
  prop_AM_NM_R = sum(Myco_Standard == "AM_NM_Reported") / .N,
  prop_AM_EM_R = sum(Myco_Standard == "AM_EM_Reported") / .N
), by = AccSpeciesName]

# Apply the classification logic
species_summary[, Myco_Group_Final := fcase(
  # Rule 1: Data Scarcity
  total_records < 5, "Low_Confidence",
  # Rule 2: High-Confidence Consensus
  prop_AM > 0.8, "Pure_AM",
  prop_EM > 0.8, "Pure_EM",
  prop_NM > 0.8, "Pure_NM",
  prop_ERM > 0.8, "Pure_ERM",
  # Rule 3: Biologically Meaningful Facultative/Mixed Groups
  (prop_AM > 0.1 & prop_NM > 0.1) | prop_AM_NM_R > 0.1, "Facultative_AM_NM",
  (prop_AM > 0.1 & prop_EM > 0.1) | prop_AM_EM_R > 0.1, "Mixed_AM_EM",
  # Rule 4: Default to Uncertain for other mixed cases
  default = "Mixed_Uncertain"
)]

# 4. Prepare and Save Final Output
final_data <- species_summary[, .(AccSpeciesName, Myco_Group_Final, total_records)]

message(paste("Saving", nrow(final_data), "classified species-myco mappings to:", output_file))
saveRDS(final_data, file = output_file)

# Also save a summary CSV for easy inspection
summary_table <- final_data[, .N, by = Myco_Group_Final]
message("Saving summary table to: ", csv_output_file)
fwrite(summary_table, file = csv_output_file)


# --- Final Summary ---
message("\n--- Reorganization Complete ---")
message("Final unique species classified: ", nrow(final_data))
message("Final Myco Group distribution:")
print(summary_table)
message("---------------------------------")
