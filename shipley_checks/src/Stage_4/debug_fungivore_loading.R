#!/usr/bin/env Rscript
#
# Debug fungivore data loading for Entomopathogen guild
#

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(glue)
})

source('shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R')

cat("==================================================================\n")
cat("DEBUG: Fungivore Data Loading (Entomopathogen Guild)\n")
cat("==================================================================\n\n")

# Initialize scorer
scorer <- GuildScorerV3Shipley$new('7plant', 'tier_3_humid_temperate')

# Entomopathogen guild
plant_ids <- c(
  "wfo-0000910097",  # Coffea arabica
  "wfo-0000421791",  # Vitis vinifera
  "wfo-0000861498",  # Dactylis glomerata
  "wfo-0001007437",  # Prunus spinosa
  "wfo-0000292858",  # Quercus robur
  "wfo-0001005999",  # Rosa canina
  "wfo-0000993770"   # Fragaria vesca
)

# Extract guild organisms
guild_organisms <- scorer$organisms_df %>% filter(plant_wfo_id %in% plant_ids)

cat("Guild organisms dataframe:\n")
cat(sprintf("  Rows: %d\n", nrow(guild_organisms)))
cat(sprintf("  Columns: %s\n", paste(names(guild_organisms), collapse=", ")))
cat("\n")

# Check fungivores_eats column
cat("Fungivores_eats column check:\n")
for (plant_id in plant_ids) {
  plant_name <- scorer$plants_df %>%
    filter(wfo_taxon_id == plant_id) %>%
    pull(wfo_scientific_name)

  org_row <- guild_organisms %>% filter(plant_wfo_id == plant_id)

  if (nrow(org_row) > 0) {
    fungivores <- org_row$fungivores_eats[[1]]
    cat(sprintf("\n%s (%s):\n", plant_id, plant_name))

    if (is.null(fungivores)) {
      cat("  fungivores_eats: NULL\n")
    } else if (length(fungivores) == 0) {
      cat("  fungivores_eats: empty list\n")
    } else {
      cat(sprintf("  fungivores_eats: %d species\n", length(fungivores)))
      if (length(fungivores) <= 5) {
        for (f in fungivores) {
          cat(sprintf("    - %s\n", f))
        }
      } else {
        for (f in head(fungivores, 3)) {
          cat(sprintf("    - %s\n", f))
        }
        cat(sprintf("    ... and %d more\n", length(fungivores) - 3))
      }
    }
  } else {
    cat(sprintf("\n%s: NO ORGANISM DATA\n", plant_id))
  }
}

# Check pathogen antagonists lookup
cat("\n\n", strrep("=", 70), "\n")
cat("Pathogen Antagonists Lookup:\n")
cat(strrep("=", 70), "\n")
cat(sprintf("Total entries: %d\n", length(scorer$pathogen_antagonists)))

# Show first 5 entries
cat("\nFirst 5 entries:\n")
for (i in 1:min(5, length(scorer$pathogen_antagonists))) {
  pathogen <- names(scorer$pathogen_antagonists)[i]
  antagonists <- scorer$pathogen_antagonists[[pathogen]]
  cat(sprintf("  %s: %d antagonists\n", pathogen, length(antagonists)))
  if (length(antagonists) <= 3) {
    for (ant in antagonists) {
      cat(sprintf("    - %s\n", ant))
    }
  } else {
    for (ant in head(antagonists, 2)) {
      cat(sprintf("    - %s\n", ant))
    }
    cat(sprintf("    ... and %d more\n", length(antagonists) - 2))
  }
}

# Check if any fungivores match any antagonists
cat("\n\n", strrep("=", 70), "\n")
cat("Cross-Check: Do guild fungivores match ANY antagonists?\n")
cat(strrep("=", 70), "\n")

# Collect all guild fungivores
all_guild_fungivores <- c()
for (plant_id in plant_ids) {
  org_row <- guild_organisms %>% filter(plant_wfo_id == plant_id)
  if (nrow(org_row) > 0) {
    fungivores <- org_row$fungivores_eats[[1]]
    if (!is.null(fungivores) && length(fungivores) > 0) {
      all_guild_fungivores <- c(all_guild_fungivores, fungivores)
    }
  }
}
all_guild_fungivores <- unique(all_guild_fungivores)

cat(sprintf("Total unique guild fungivores: %d\n", length(all_guild_fungivores)))

# Collect all antagonists
all_antagonists <- unique(unlist(scorer$pathogen_antagonists))
cat(sprintf("Total unique antagonists in lookup: %d\n", length(all_antagonists)))

# Find intersection
common <- intersect(all_guild_fungivores, all_antagonists)
cat(sprintf("\nFungivores that ARE antagonists: %d\n", length(common)))

if (length(common) > 0) {
  cat("\nMatches:\n")
  for (fungivore in head(common, 10)) {
    cat(sprintf("  - %s\n", fungivore))
  }
  if (length(common) > 10) {
    cat(sprintf("  ... and %d more\n", length(common) - 10))
  }
}

# Now check guild pathogens
cat("\n\n", strrep("=", 70), "\n")
cat("Guild Pathogen Check:\n")
cat(strrep("=", 70), "\n")

guild_fungi <- scorer$fungi_df %>% filter(plant_wfo_id %in% plant_ids)

for (plant_id in plant_ids) {
  fungi_row <- guild_fungi %>% filter(plant_wfo_id == plant_id)

  if (nrow(fungi_row) > 0) {
    pathogens <- fungi_row$pathogenic_fungi[[1]]

    if (!is.null(pathogens) && length(pathogens) > 0) {
      cat(sprintf("\n%s: %d pathogens\n", plant_id, length(pathogens)))

      # Check if any pathogen has known antagonists
      pathogens_with_antagonists <- 0
      for (pathogen in pathogens) {
        if (pathogen %in% names(scorer$pathogen_antagonists)) {
          pathogens_with_antagonists <- pathogens_with_antagonists + 1
        }
      }
      cat(sprintf("  Pathogens with known antagonists: %d\n", pathogens_with_antagonists))
    }
  }
}

cat("\n", strrep("=", 70), "\n")
cat("Debug complete.\n")
cat(strrep("=", 70), "\n")
