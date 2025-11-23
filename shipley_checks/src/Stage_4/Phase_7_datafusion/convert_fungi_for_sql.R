#!/usr/bin/env Rscript
#
# Convert Phase 0 fungal guilds to DataFusion SQL-optimized parquet
#
# Purpose:
# - Take Phase 0 fungal guild profiles (plant-fungi relationships from GloBI)
# - Flatten array columns to relational format for SQL queries
# - Create searchable fungi-plant interaction table
#
# Input:
#   - shipley_checks/stage4/phase0_output/fungal_guilds_hybrid_11711.parquet
#
# Output:
#   - shipley_checks/stage4/phase7_output/fungi_searchable.parquet
#

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
})

# Paths
project_root <- "/home/olier/ellenberg"
input_file <- file.path(project_root, "shipley_checks/stage4/phase0_output/fungal_guilds_hybrid_11711.parquet")
output_file <- file.path(project_root, "shipley_checks/stage4/phase7_output/fungi_searchable.parquet")

cat("================================================================================\n")
cat("PHASE 7: CONVERT FUNGAL GUILDS TO SQL-OPTIMIZED PARQUET\n")
cat("================================================================================\n\n")

# Check input exists
if (!file.exists(input_file)) {
  stop("Input file not found: ", input_file, "\n  Run Phase 0 first.")
}

cat("Loading fungal guild profiles...\n")
cat("  Input: ", input_file, "\n")

fungi <- read_parquet(input_file)
cat("  →", nrow(fungi), "plant profiles loaded\n")
cat("  →", ncol(fungi), "columns\n\n")

cat("================================================================================\n")
cat("TRANSFORMATIONS\n")
cat("================================================================================\n\n")

# Define fungal guild types and their columns
guild_types <- list(
  pathogenic_fungi = "pathogenic_fungi",
  pathogenic_fungi_host_specific = "pathogenic_fungi_host_specific",
  amf_fungi = "amf_fungi",
  emf_fungi = "emf_fungi",
  mycoparasite_fungi = "mycoparasite_fungi",
  entomopathogenic_fungi = "entomopathogenic_fungi",
  endophytic_fungi = "endophytic_fungi",
  saprotrophic_fungi = "saprotrophic_fungi"
)

cat("1. Flattening fungal guild arrays to relational format...\n")

# Initialize empty list to store flattened data frames
flattened_dfs <- list()

for (guild_name in names(guild_types)) {
  col_name <- guild_types[[guild_name]]

  # Check if column exists
  if (!col_name %in% names(fungi)) {
    cat("  Skipping", guild_name, "(column not found)\n")
    next
  }

  cat("  Processing:", guild_name, "\n")

  # Flatten this guild type
  flat_df <- fungi %>%
    select(plant_wfo_id, wfo_scientific_name, family, genus,
           fungus_list = all_of(col_name)) %>%
    filter(!is.na(fungus_list), lengths(fungus_list) > 0) %>%
    unnest_longer(fungus_list) %>%
    mutate(
      guild_type = guild_name,
      fungus_taxon = as.character(fungus_list)
    ) %>%
    select(plant_wfo_id, wfo_scientific_name, family, genus,
           fungus_taxon, guild_type)

  flattened_dfs[[guild_name]] <- flat_df
}

# Combine all guild types
cat("\n2. Combining all fungal guilds...\n")
fungi_flat <- bind_rows(flattened_dfs)

cat("  →", nrow(fungi_flat), "plant-fungi interactions\n")
cat("  →", length(unique(fungi_flat$fungus_taxon)), "unique fungi\n")
cat("  →", length(unique(fungi_flat$plant_wfo_id)), "plants with fungal data\n\n")

# Add computed columns for common queries
cat("3. Adding computed columns...\n")
fungi_final <- fungi_flat %>%
  mutate(
    # Categorize guild types
    guild_category = case_when(
      guild_type %in% c("amf_fungi", "emf_fungi") ~ "mycorrhizal",
      guild_type %in% c("pathogenic_fungi", "pathogenic_fungi_host_specific") ~ "pathogenic",
      guild_type %in% c("mycoparasite_fungi", "entomopathogenic_fungi") ~ "biocontrol",
      guild_type == "endophytic_fungi" ~ "endophytic",
      guild_type == "saprotrophic_fungi" ~ "saprotrophic",
      TRUE ~ "other"
    ),

    # Functional category (broader grouping)
    functional_role = case_when(
      guild_type %in% c("amf_fungi", "emf_fungi") ~ "beneficial",
      guild_type %in% c("pathogenic_fungi", "pathogenic_fungi_host_specific") ~ "harmful",
      guild_type %in% c("mycoparasite_fungi", "entomopathogenic_fungi") ~ "biocontrol",
      TRUE ~ "neutral"
    ),

    # Boolean flags for quick filtering
    is_mycorrhizal = guild_type %in% c("amf_fungi", "emf_fungi"),
    is_amf = guild_type == "amf_fungi",
    is_emf = guild_type == "emf_fungi",
    is_pathogenic = guild_type %in% c("pathogenic_fungi", "pathogenic_fungi_host_specific"),
    is_biocontrol = guild_type %in% c("mycoparasite_fungi", "entomopathogenic_fungi"),
    is_entomopathogen = guild_type == "entomopathogenic_fungi",
    is_mycoparasite = guild_type == "mycoparasite_fungi",
    is_endophytic = guild_type == "endophytic_fungi",
    is_saprotrophic = guild_type == "saprotrophic_fungi"
  )

cat("  → Guild categories:",
    paste(unique(fungi_final$guild_category), collapse = ", "), "\n")
cat("  → Functional roles:",
    paste(unique(fungi_final$functional_role), collapse = ", "), "\n\n")

# Step 4: Write parquet with optimal compression
cat("================================================================================\n")
cat("EXPORT TO PARQUET\n")
cat("================================================================================\n\n")

cat("Writing to:", output_file, "\n")

# Ensure output directory exists
dir.create(dirname(output_file), showWarnings = FALSE, recursive = TRUE)

write_parquet(
  fungi_final,
  output_file,
  compression = "zstd",
  compression_level = 9,
  use_dictionary = TRUE  # Excellent for categorical columns
)

# Verify output
output_size_mb <- file.size(output_file) / 1024 / 1024
cat("✓ Export complete\n")
cat("  →", nrow(fungi_final), "interactions\n")
cat("  →", ncol(fungi_final), "columns\n")
cat("  → File size:", round(output_size_mb, 2), "MB\n\n")

cat("SQL-friendly features:\n")
cat("  - Relational format: One row per plant-fungus interaction\n")
cat("  - Categorical indexing: guild_type, guild_category, functional_role\n")
cat("  - Boolean filters: is_mycorrhizal, is_pathogenic, is_biocontrol\n")
cat("  - Joinable: plant_wfo_id links to plants_searchable\n")
cat("  - Compressed: ZSTD level 9 + dictionary encoding\n\n")

cat("Example SQL queries:\n")
cat("  SELECT * FROM fungi WHERE is_mycorrhizal = true\n")
cat("  SELECT * FROM fungi WHERE guild_category = 'biocontrol'\n")
cat("  SELECT plant_wfo_id, COUNT(*) FROM fungi GROUP BY plant_wfo_id\n")
cat("  SELECT * FROM fungi WHERE is_amf = true AND family = 'Fabaceae'\n\n")

cat("================================================================================\n")
cat("READY FOR DATAFUSION QUERY ENGINE\n")
cat("================================================================================\n")
