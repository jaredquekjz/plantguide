#!/usr/bin/env Rscript
#
# Convert Phase 0 organism profiles to DataFusion SQL-optimized parquet
#
# Purpose:
# - Take Phase 0 organism profiles (plant-organism relationships from GloBI)
# - Flatten array columns to relational format for SQL queries
# - Create searchable organism-plant interaction table
#
# Input:
#   - shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet
#
# Output:
#   - shipley_checks/stage4/phase7_output/organisms_searchable.parquet
#

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
})

# Paths
project_root <- "/home/olier/ellenberg"
input_file <- file.path(project_root, "shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet")
output_file <- file.path(project_root, "shipley_checks/stage4/phase7_output/organisms_searchable.parquet")

cat("================================================================================\n")
cat("PHASE 7: CONVERT ORGANISMS TO SQL-OPTIMIZED PARQUET\n")
cat("================================================================================\n\n")

# Check input exists
if (!file.exists(input_file)) {
  stop("Input file not found: ", input_file, "\n  Run Phase 0 first.")
}

cat("Loading organism profiles...\n")
cat("  Input: ", input_file, "\n")

organisms <- read_parquet(input_file)
cat("  →", nrow(organisms), "plant profiles loaded\n")
cat("  →", ncol(organisms), "columns\n\n")

cat("================================================================================\n")
cat("TRANSFORMATIONS\n")
cat("================================================================================\n\n")

# The organism profiles have array columns that need to be flattened
# For SQL queries, we want one row per plant-organism interaction

# Define interaction types and their columns
interaction_types <- list(
  pollinators = "pollinators",
  herbivores = "herbivores",
  pathogens = "pathogens",
  flower_visitors = "flower_visitors",
  predators_hasHost = "predators_hasHost",
  predators_interactsWith = "predators_interactsWith",
  predators_adjacentTo = "predators_adjacentTo",
  fungivores_eats = "fungivores_eats"
)

cat("1. Flattening organism arrays to relational format...\n")

# Initialize empty list to store flattened data frames
flattened_dfs <- list()

for (interaction_name in names(interaction_types)) {
  col_name <- interaction_types[[interaction_name]]

  # Check if column exists
  if (!col_name %in% names(organisms)) {
    cat("  Skipping", interaction_name, "(column not found)\n")
    next
  }

  cat("  Processing:", interaction_name, "\n")

  # Flatten this interaction type
  # Convert array to individual rows
  flat_df <- organisms %>%
    select(plant_wfo_id, organism_list = all_of(col_name)) %>%
    filter(!is.na(organism_list), lengths(organism_list) > 0) %>%
    unnest_longer(organism_list) %>%
    mutate(
      interaction_type = interaction_name,
      organism_taxon = as.character(organism_list)
    ) %>%
    select(plant_wfo_id, organism_taxon, interaction_type)

  flattened_dfs[[interaction_name]] <- flat_df
}

# Combine all interaction types
cat("\n2. Combining all interaction types...\n")
organisms_flat <- bind_rows(flattened_dfs)

cat("  →", nrow(organisms_flat), "plant-organism interactions\n")
cat("  →", length(unique(organisms_flat$organism_taxon)), "unique organisms\n")
cat("  →", length(unique(organisms_flat$plant_wfo_id)), "plants with organism data\n\n")

# Add computed columns for common queries
cat("3. Adding computed columns...\n")
organisms_final <- organisms_flat %>%
  mutate(
    # Categorize interaction types
    interaction_category = case_when(
      interaction_type %in% c("pollinators", "flower_visitors") ~ "beneficial",
      interaction_type %in% c("herbivores", "pathogens") ~ "pest",
      interaction_type %in% c("predators_hasHost", "predators_interactsWith",
                              "predators_adjacentTo") ~ "biocontrol",
      interaction_type == "fungivores_eats" ~ "fungivore",
      TRUE ~ "other"
    ),

    # Boolean flags for quick filtering
    is_pollinator = interaction_type %in% c("pollinators", "flower_visitors"),
    is_pest = interaction_type %in% c("herbivores", "pathogens"),
    is_biocontrol = interaction_type %in% c("predators_hasHost", "predators_interactsWith",
                                             "predators_adjacentTo"),
    is_pathogen = interaction_type == "pathogens",
    is_herbivore = interaction_type == "herbivores"
  )

cat("  → Interaction categories:",
    paste(unique(organisms_final$interaction_category), collapse = ", "), "\n\n")

# Step 4: Write parquet with optimal compression
cat("================================================================================\n")
cat("EXPORT TO PARQUET\n")
cat("================================================================================\n\n")

cat("Writing to:", output_file, "\n")

# Ensure output directory exists
dir.create(dirname(output_file), showWarnings = FALSE, recursive = TRUE)

write_parquet(
  organisms_final,
  output_file,
  compression = "zstd",
  compression_level = 9,
  use_dictionary = TRUE  # Excellent for categorical columns
)

# Verify output
output_size_mb <- file.size(output_file) / 1024 / 1024
cat("✓ Export complete\n")
cat("  →", nrow(organisms_final), "interactions\n")
cat("  →", ncol(organisms_final), "columns\n")
cat("  → File size:", round(output_size_mb, 2), "MB\n\n")

cat("SQL-friendly features:\n")
cat("  - Relational format: One row per plant-organism interaction\n")
cat("  - Categorical indexing: interaction_type, interaction_category\n")
cat("  - Boolean filters: is_pollinator, is_pest, is_biocontrol\n")
cat("  - Joinable: plant_wfo_id links to plants_searchable\n")
cat("  - Compressed: ZSTD level 9 + dictionary encoding\n\n")

cat("Example SQL queries:\n")
cat("  SELECT * FROM organisms WHERE is_pollinator = true\n")
cat("  SELECT * FROM organisms WHERE interaction_category = 'pest'\n")
cat("  SELECT plant_wfo_id, COUNT(*) FROM organisms GROUP BY plant_wfo_id\n\n")

cat("================================================================================\n")
cat("READY FOR DATAFUSION QUERY ENGINE\n")
cat("================================================================================\n")
