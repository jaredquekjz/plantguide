#!/usr/bin/env Rscript
#
# Flatten organism profiles for SQL queries
#
# Purpose:
# - Explode list columns from organism_profiles into relational rows
# - Faithful transformation: no derived labels or categories
# - Output: one row per plant-organism interaction
#
# Input:
#   - shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet
#
# Output:
#   - shipley_checks/stage4/phase7_output/organisms_flat.parquet
#
# Schema (3 columns only):
#   - plant_wfo_id: Plant identifier
#   - organism_taxon: Organism name (from exploded list)
#   - source_column: Name of source column (e.g., "pollinators", "herbivores")
#

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
})

# Paths
project_root <- "/home/olier/ellenberg"
input_file <- file.path(project_root, "shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet")
output_file <- file.path(project_root, "shipley_checks/stage4/phase7_output/organisms_flat.parquet")

cat("================================================================================\n")
cat("PHASE 7: FLATTEN ORGANISMS FOR SQL\n")
cat("================================================================================\n\n")

# Check input exists
if (!file.exists(input_file)) {
  stop("Input file not found: ", input_file, "\n  Run Phase 0 first.")
}

cat("Loading organism profiles...\n")
cat("  Input: ", input_file, "\n")

organisms <- read_parquet(input_file)
cat("  Rows:", nrow(organisms), "\n")
cat("  Columns:", ncol(organisms), "\n\n")

# List columns to flatten (all organism list columns)
list_columns <- c(
  "pollinators",
  "herbivores",
  "pathogens",
  "flower_visitors",
  "fauna_hasHost",        # Animals using plant as host (renamed from predators_hasHost)
  "fauna_interactsWith",  # Animals interacting with plant (renamed from predators_interactsWith)
  "fauna_adjacentTo",     # Animals found near plant (renamed from predators_adjacentTo)
  "fungivores_eats"
)

cat("Flattening list columns...\n")

# Initialize empty list
flattened_dfs <- list()

for (col_name in list_columns) {
  if (!col_name %in% names(organisms)) {
    cat("  Skipping", col_name, "(not found)\n")
    next
  }

  cat("  Processing:", col_name, "...")

  # Flatten: explode list column into rows
  flat_df <- organisms %>%
    select(plant_wfo_id, organism_list = all_of(col_name)) %>%
    filter(!is.na(organism_list), lengths(organism_list) > 0) %>%
    unnest_longer(organism_list) %>%
    transmute(
      plant_wfo_id = plant_wfo_id,
      organism_taxon = as.character(organism_list),
      source_column = col_name
    )

  cat(" ", nrow(flat_df), "rows\n")
  flattened_dfs[[col_name]] <- flat_df
}

# Combine all
cat("\nCombining all interactions...\n")
organisms_flat <- bind_rows(flattened_dfs)

cat("  Total rows:", nrow(organisms_flat), "\n")
cat("  Unique organisms:", length(unique(organisms_flat$organism_taxon)), "\n")
cat("  Plants with data:", length(unique(organisms_flat$plant_wfo_id)), "\n")

# Summary by source column
cat("\nBreakdown by source_column:\n")
summary_df <- organisms_flat %>%
  group_by(source_column) %>%
  summarise(n = n(), .groups = "drop") %>%
  arrange(desc(n))
print(as.data.frame(summary_df))

# Write output
cat("\n================================================================================\n")
cat("EXPORT TO PARQUET\n")
cat("================================================================================\n\n")

dir.create(dirname(output_file), showWarnings = FALSE, recursive = TRUE)

write_parquet(
  organisms_flat,
  output_file,
  compression = "zstd",
  compression_level = 9
)

output_size_mb <- file.size(output_file) / 1024 / 1024
cat("Output:", output_file, "\n")
cat("  Rows:", nrow(organisms_flat), "\n")
cat("  Columns:", ncol(organisms_flat), "\n
")
cat("  Size:", round(output_size_mb, 2), "MB\n\n")

cat("Schema (faithful, no derived columns):\n")
cat("  - plant_wfo_id: Plant identifier\n")
cat("  - organism_taxon: Organism name\n")
cat("  - source_column: Original column name from Phase 0\n\n")

cat("Done.\n")
