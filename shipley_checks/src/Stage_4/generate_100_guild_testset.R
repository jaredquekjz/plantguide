#!/usr/bin/env Rscript
#
# Generate 100-guild test dataset for frontend verification
#
# Purpose: Create comprehensive test set covering edge cases and systematic
#          size × climate combinations for Python/R/Rust scorer verification
#
# Output: shipley_checks/stage4/100_guild_testset.json
#

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(jsonlite)
})

set.seed(42)  # Reproducible guild selection

generate_100_guild_testset <- function() {
  cat("Loading plant dataset...\n")

  # Load full dataset
  plants <- read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet')

  cat(sprintf("Loaded %d plants\n", nrow(plants)))

  guilds <- list()
  guild_idx <- 1

  # ========================================================================
  # PART 1: Edge Case Guilds (10 guilds)
  # ========================================================================

  cat("\n=== Generating Edge Case Guilds ===\n")

  # Edge Case 1: Same genus (low Faith's PD)
  cat("1. Same genus guild (low M1)...\n")
  quercus_plants <- plants %>%
    filter(genus == "Quercus", !is.na(height_m)) %>%
    slice_sample(n = 2)

  guilds[[guild_idx]] <- list(
    guild_id = sprintf("guild_%03d", guild_idx),
    name = "edge_same_genus_quercus_2plant",
    size = 2,
    climate_tier = "tier_3_humid_temperate",
    plant_ids = quercus_plants$wfo_taxon_id,
    expected_behavior = "Low Faith's PD - same genus",
    tags = list("edge_case", "m1_low_pd")
  )
  guild_idx <- guild_idx + 1

  # Edge Case 2: Different families (high Faith's PD)
  cat("2. Max diversity guild (high M1)...\n")
  diverse_plants <- plants %>%
    filter(!is.na(height_m)) %>%
    group_by(family) %>%
    slice_sample(n = 1) %>%
    ungroup() %>%
    slice_sample(n = 7)

  guilds[[guild_idx]] <- list(
    guild_id = sprintf("guild_%03d", guild_idx),
    name = "edge_max_diversity_7plant",
    size = 7,
    climate_tier = "tier_3_humid_temperate",
    plant_ids = diverse_plants$wfo_taxon_id,
    expected_behavior = "High Faith's PD - different families",
    tags = list("edge_case", "m1_high_pd")
  )
  guild_idx <- guild_idx + 1

  # Edge Case 3: All High-S (zero CSR conflicts)
  cat("3. All stress-tolerant guild (zero M2 conflicts)...\n")
  high_s_plants <- plants %>%
    filter(S >= 0.6, !is.na(height_m)) %>%
    slice_sample(n = 5)

  guilds[[guild_idx]] <- list(
    guild_id = sprintf("guild_%03d", guild_idx),
    name = "edge_all_stress_tolerant_5plant",
    size = 5,
    climate_tier = "tier_3_humid_temperate",
    plant_ids = high_s_plants$wfo_taxon_id,
    expected_behavior = "Zero CSR conflicts - all High-S",
    tags = list("edge_case", "m2_zero_conflict")
  )
  guild_idx <- guild_idx + 1

  # Edge Case 4: All High-C (maximum CSR conflicts)
  cat("4. All competitive guild (max M2 conflicts)...\n")
  high_c_plants <- plants %>%
    filter(C >= 0.6, !is.na(height_m)) %>%
    slice_sample(n = 5)

  guilds[[guild_idx]] <- list(
    guild_id = sprintf("guild_%03d", guild_idx),
    name = "edge_all_competitive_5plant",
    size = 5,
    climate_tier = "tier_3_humid_temperate",
    plant_ids = high_c_plants$wfo_taxon_id,
    expected_behavior = "Maximum CSR conflicts - all High-C",
    tags = list("edge_case", "m2_max_conflict")
  )
  guild_idx <- guild_idx + 1

  # Edge Case 5: Monoform - all herbs (low M6)
  cat("5. Monoform guild (low M6)...\n")
  herb_plants <- plants %>%
    filter(try_growth_form == "herbaceous", !is.na(height_m)) %>%
    slice_sample(n = 5)

  guilds[[guild_idx]] <- list(
    guild_id = sprintf("guild_%03d", guild_idx),
    name = "edge_monoform_herbaceous_5plant",
    size = 5,
    climate_tier = "tier_3_humid_temperate",
    plant_ids = herb_plants$wfo_taxon_id,
    expected_behavior = "Low structural diversity - all herbs",
    tags = list("edge_case", "m6_low_diversity")
  )
  guild_idx <- guild_idx + 1

  # Edge Case 6: Maximum structure (high M6)
  cat("6. Max structure guild (high M6)...\n")
  # Get one from each growth form
  structured_plants <- plants %>%
    filter(!is.na(height_m), !is.na(try_growth_form)) %>%
    group_by(try_growth_form) %>%
    slice_sample(n = 1) %>%
    ungroup() %>%
    slice_head(n = 7)

  guilds[[guild_idx]] <- list(
    guild_id = sprintf("guild_%03d", guild_idx),
    name = "edge_max_structure_7plant",
    size = 7,
    climate_tier = "tier_3_humid_temperate",
    plant_ids = structured_plants$wfo_taxon_id,
    expected_behavior = "High structural diversity - mixed forms",
    tags = list("edge_case", "m6_high_diversity")
  )
  guild_idx <- guild_idx + 1

  # Edge Case 7: Small guild (2 plants)
  cat("7. Minimal guild size (2 plants)...\n")
  small_guild <- plants %>%
    filter(!is.na(height_m)) %>%
    slice_sample(n = 2)

  guilds[[guild_idx]] <- list(
    guild_id = sprintf("guild_%03d", guild_idx),
    name = "edge_minimal_size_2plant",
    size = 2,
    climate_tier = "tier_3_humid_temperate",
    plant_ids = small_guild$wfo_taxon_id,
    expected_behavior = "Edge case - minimum guild size",
    tags = list("edge_case", "size_minimum")
  )
  guild_idx <- guild_idx + 1

  # Edge Case 8: Large guild (10 plants)
  cat("8. Large guild size (10 plants)...\n")
  large_guild <- plants %>%
    filter(!is.na(height_m)) %>%
    slice_sample(n = 10)

  guilds[[guild_idx]] <- list(
    guild_id = sprintf("guild_%03d", guild_idx),
    name = "edge_large_size_10plant",
    size = 10,
    climate_tier = "tier_3_humid_temperate",
    plant_ids = large_guild$wfo_taxon_id,
    expected_behavior = "Large guild for network effects",
    tags = list("edge_case", "size_large")
  )
  guild_idx <- guild_idx + 1

  # Edge Case 9: Mixed CSR (balanced strategies)
  cat("9. Mixed CSR strategies...\n")
  mixed_csr <- plants %>%
    filter(!is.na(height_m)) %>%
    mutate(
      dominant = case_when(
        C >= 0.5 ~ "C",
        S >= 0.5 ~ "S",
        R >= 0.5 ~ "R",
        TRUE ~ "balanced"
      )
    ) %>%
    group_by(dominant) %>%
    slice_sample(n = 1) %>%
    ungroup() %>%
    slice_head(n = 5)

  guilds[[guild_idx]] <- list(
    guild_id = sprintf("guild_%03d", guild_idx),
    name = "edge_mixed_csr_5plant",
    size = 5,
    climate_tier = "tier_3_humid_temperate",
    plant_ids = mixed_csr$wfo_taxon_id,
    expected_behavior = "Mixed CSR strategies",
    tags = list("edge_case", "m2_mixed")
  )
  guild_idx <- guild_idx + 1

  # Edge Case 10: Tropical extreme
  cat("10. Tropical climate extreme...\n")
  tropical_plants <- plants %>%
    filter(tier_1_tropical == 1, !is.na(height_m)) %>%
    slice_sample(n = 7)

  guilds[[guild_idx]] <- list(
    guild_id = sprintf("guild_%03d", guild_idx),
    name = "edge_tropical_7plant",
    size = 7,
    climate_tier = "tier_1_tropical",
    plant_ids = tropical_plants$wfo_taxon_id,
    expected_behavior = "Tropical climate specialization",
    tags = list("edge_case", "climate_tropical")
  )
  guild_idx <- guild_idx + 1

  # ========================================================================
  # PART 2: Systematic Size × Climate Grid (90 guilds)
  # ========================================================================

  cat("\n=== Generating Systematic Size × Climate Grid ===\n")

  sizes <- c(2, 3, 5, 7, 10)
  tiers <- c('tier_1_tropical', 'tier_2_mediterranean', 'tier_3_humid_temperate',
             'tier_4_continental', 'tier_5_boreal_polar', 'tier_6_arid')

  tier_columns <- c('tier_1_tropical', 'tier_2_mediterranean', 'tier_3_humid_temperate',
                    'tier_4_continental', 'tier_5_boreal_polar', 'tier_6_arid')

  for (size in sizes) {
    for (tier_idx in seq_along(tiers)) {
      tier_name <- tiers[tier_idx]
      tier_col <- tier_columns[tier_idx]

      cat(sprintf("Generating %d-plant guild for %s...\n", size, tier_name))

      # Select plants matching climate tier
      tier_candidates <- plants %>%
        filter(.data[[tier_col]] == 1, !is.na(height_m))

      n_available <- nrow(tier_candidates)
      n_to_sample <- min(size, n_available)

      tier_plants <- tier_candidates %>%
        slice_sample(n = n_to_sample)

      # If not enough plants in tier, fill with general selection
      if (nrow(tier_plants) < size) {
        cat(sprintf("  Warning: Only %d plants available for %s, filling with general pool\n",
                    nrow(tier_plants), tier_name))
        additional <- plants %>%
          filter(!is.na(height_m), !wfo_taxon_id %in% tier_plants$wfo_taxon_id) %>%
          slice_sample(n = size - nrow(tier_plants))
        tier_plants <- bind_rows(tier_plants, additional)
      }

      guilds[[guild_idx]] <- list(
        guild_id = sprintf("guild_%03d", guild_idx),
        name = sprintf("systematic_%dplant_%s", size, tier_name),
        size = size,
        climate_tier = tier_name,
        plant_ids = tier_plants$wfo_taxon_id,
        expected_behavior = sprintf("%d-plant guild in %s", size, tier_name),
        tags = list("systematic", paste0("size_", size), paste0("climate_", tier_name))
      )
      guild_idx <- guild_idx + 1
    }
  }

  # ========================================================================
  # Export to JSON
  # ========================================================================

  cat("\n=== Exporting Test Dataset ===\n")

  output_path <- 'shipley_checks/stage4/100_guild_testset.json'
  write_json(guilds, output_path, auto_unbox = TRUE, pretty = TRUE)

  cat(sprintf("✓ Exported %d guilds to %s\n", length(guilds), output_path))
  cat(sprintf("  File size: %s bytes\n",
              format(file.size(output_path), big.mark = ',')))

  # Summary statistics
  cat("\n=== Test Dataset Summary ===\n")
  cat(sprintf("Total guilds: %d\n", length(guilds)))

  sizes_count <- table(sapply(guilds, function(g) g$size))
  cat("\nSize distribution:\n")
  for (s in names(sizes_count)) {
    cat(sprintf("  %s plants: %d guilds\n", s, sizes_count[s]))
  }

  tiers_count <- table(sapply(guilds, function(g) g$climate_tier))
  cat("\nClimate distribution:\n")
  for (t in names(tiers_count)) {
    cat(sprintf("  %s: %d guilds\n", t, tiers_count[t]))
  }

  cat("\n✓ Test dataset generation complete\n")

  return(guilds)
}

# Run if called directly
if (!interactive()) {
  guilds <- generate_100_guild_testset()
}
