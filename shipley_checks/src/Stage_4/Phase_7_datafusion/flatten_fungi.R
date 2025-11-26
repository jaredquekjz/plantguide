#!/usr/bin/env Rscript
#
# Flatten fungal guilds for SQL queries
#
# Purpose:
# - Explode list columns from fungal_guilds into relational rows
# - Faithful transformation: no derived labels or categories
# - Output: one row per plant-fungus interaction
#
# Input:
#   - shipley_checks/stage4/phase0_output/fungal_guilds_hybrid_11711.parquet
#
# Output:
#   - shipley_checks/stage4/phase7_output/fungi_flat.parquet
#
# Schema (3 columns only):
#   - plant_wfo_id: Plant identifier
#   - fungus_taxon: Fungus name (from exploded list)
#   - source_column: Name of source column (e.g., "amf_fungi", "emf_fungi")
#

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
})

# Paths
project_root <- "/home/olier/ellenberg"
input_file <- file.path(project_root, "shipley_checks/stage4/phase0_output/fungal_guilds_hybrid_11711.parquet")
output_file <- file.path(project_root, "shipley_checks/stage4/phase7_output/fungi_flat.parquet")

cat("================================================================================\n")
cat("PHASE 7: FLATTEN FUNGI FOR SQL\n")
cat("================================================================================\n\n")

# Check input exists
if (!file.exists(input_file)) {
  stop("Input file not found: ", input_file, "\n  Run Phase 0 first.")
}

cat("Loading fungal guild profiles...\n")
cat("  Input: ", input_file, "\n")

fungi <- read_parquet(input_file)
cat("  Rows:", nrow(fungi), "\n")
cat("  Columns:", ncol(fungi), "\n\n")

# List columns to flatten (all fungal list columns)
list_columns <- c(
  "pathogenic_fungi",
  "pathogenic_fungi_host_specific",
  "amf_fungi",
  "emf_fungi",
  "mycoparasite_fungi",
  "entomopathogenic_fungi",
  "endophytic_fungi",
  "saprotrophic_fungi"
)

cat("Flattening list columns...\n")

# Initialize empty list
flattened_dfs <- list()

for (col_name in list_columns) {
  if (!col_name %in% names(fungi)) {
    cat("  Skipping", col_name, "(not found)\n")
    next
  }

  cat("  Processing:", col_name, "...")

  # Flatten: explode list column into rows
  flat_df <- fungi %>%
    select(plant_wfo_id, fungus_list = all_of(col_name)) %>%
    filter(!is.na(fungus_list), lengths(fungus_list) > 0) %>%
    unnest_longer(fungus_list) %>%
    transmute(
      plant_wfo_id = plant_wfo_id,
      fungus_taxon = as.character(fungus_list),
      source_column = col_name
    )

  cat(" ", nrow(flat_df), "rows\n")
  flattened_dfs[[col_name]] <- flat_df
}

# Combine all
cat("\nCombining all interactions...\n")
fungi_flat <- bind_rows(flattened_dfs)

cat("  Total rows:", nrow(fungi_flat), "\n")
cat("  Unique fungi:", length(unique(fungi_flat$fungus_taxon)), "\n")
cat("  Plants with data:", length(unique(fungi_flat$plant_wfo_id)), "\n")

# Summary by source column
cat("\nBreakdown by source_column:\n")
summary_df <- fungi_flat %>%
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
  fungi_flat,
  output_file,
  compression = "zstd",
  compression_level = 9
)

output_size_mb <- file.size(output_file) / 1024 / 1024
cat("Output:", output_file, "\n")
cat("  Rows:", nrow(fungi_flat), "\n")
cat("  Columns:", ncol(fungi_flat), "\n")
cat("  Size:", round(output_size_mb, 2), "MB\n\n")

cat("Schema (faithful, no derived columns):\n")
cat("  - plant_wfo_id: Plant identifier\n")
cat("  - fungus_taxon: Fungus name\n")
cat("  - source_column: Original column name from Phase 0\n\n")

cat("Done.\n")
