#!/usr/bin/env Rscript
#
# 2-Stage Köppen-Stratified Calibration Script (R Implementation)
#
# Stage 1: 2-Plant Pairs (20K per tier × 6 tiers = 120K pairs)
# Stage 2: 7-Plant Guilds (20K per tier × 6 tiers = 120K guilds)
#
# Based on Document 4.2c: 7-Metric Framework (2025-11-05)
# - N1 (Pathogen Fungi) and N2 (Herbivore Overlap) REMOVED
# - P4 (Phylogenetic Diversity) → M1 (Pathogen & Pest Independence)
# - M1 applies exponential transformation: exp(-3.0 × distance)
#
# Dual verification against Python baseline implementation.
#

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(jsonlite)
  library(R6)
})

# Source Faith's PD calculator
source("shipley_checks/src/Stage_4/faiths_pd_calculator.R")

# Köppen tier structure
TIERS <- list(
  tier_1_tropical = c('Af', 'Am', 'As', 'Aw'),
  tier_2_mediterranean = c('Csa', 'Csb', 'Csc'),
  tier_3_humid_temperate = c('Cfa', 'Cfb', 'Cfc', 'Cwa', 'Cwb', 'Cwc'),
  tier_4_continental = c('Dfa', 'Dfb', 'Dfc', 'Dfd', 'Dwa', 'Dwb', 'Dwc', 'Dwd', 'Dsa', 'Dsb', 'Dsc', 'Dsd'),
  tier_5_boreal_polar = c('ET', 'EF'),
  tier_6_arid = c('BWh', 'BWk', 'BSh', 'BSk')
)

COMPONENTS <- c('m1', 'n4', 'p1', 'p2', 'p3', 'p5', 'p6')
PERCENTILES <- c(1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99)


#' Load all necessary datasets
#'
#' @return List with plants_df, organisms_df, fungi_df
load_all_data <- function() {
  cat("\nLoading datasets...\n")

  # Plants with Köppen tiers (SHIPLEY_CHECKS DATASET - 11,711 plants)
  plants_df <- read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet') %>%
    select(
      wfo_taxon_id, wfo_scientific_name, family, genus,
      height_m, try_growth_form,
      CSR_C = C, CSR_S = S, CSR_R = R,
      light_pref = `EIVEres-L`,
      tier_1_tropical, tier_2_mediterranean, tier_3_humid_temperate,
      tier_4_continental, tier_5_boreal_polar, tier_6_arid,
      starts_with("phylo_ev")
    ) %>%
    filter(!is.na(phylo_ev1))

  # Organisms (SHIPLEY_CHECKS DATASET)
  organisms_path <- 'shipley_checks/stage4/plant_organism_profiles_11711.parquet'
  if (file.exists(organisms_path)) {
    organisms_df <- read_parquet(organisms_path) %>%
      select(plant_wfo_id, herbivores, flower_visitors, pollinators)
  } else {
    organisms_df <- tibble()
  }

  # Fungi (SHIPLEY_CHECKS DATASET)
  fungi_path <- 'shipley_checks/stage4/plant_fungal_guilds_hybrid_11711.parquet'
  if (file.exists(fungi_path)) {
    fungi_df <- read_parquet(fungi_path) %>%
      select(plant_wfo_id, pathogenic_fungi, pathogenic_fungi_host_specific,
             amf_fungi, emf_fungi, endophytic_fungi, saprotrophic_fungi)
  } else {
    fungi_df <- tibble()
  }

  cat(sprintf("  Plants: %s\n", format(nrow(plants_df), big.mark = ",")))
  cat(sprintf("  Organisms: %s\n", format(nrow(organisms_df), big.mark = ",")))
  cat(sprintf("  Fungi: %s\n", format(nrow(fungi_df), big.mark = ",")))

  list(plants_df = plants_df, organisms_df = organisms_df, fungi_df = fungi_df)
}


#' Organize plant IDs by Köppen tier
#'
#' @param plants_df Plant dataset
#' @return Named list of plant IDs per tier
organize_by_tier <- function(plants_df) {
  tier_plants <- list()

  for (tier_name in names(TIERS)) {
    tier_mask <- plants_df[[tier_name]] == TRUE
    tier_ids <- plants_df$wfo_taxon_id[tier_mask]
    tier_plants[[tier_name]] <- tier_ids
    cat(sprintf("  %-30s: %5s plants\n", tier_name, format(length(tier_ids), big.mark = ",")))
  }

  tier_plants
}


#' Count organisms shared across plants
#'
#' @param df DataFrame (organisms or fungi)
#' @param plant_ids Vector of plant WFO IDs
#' @param ... Column names to check
#' @return Named vector of organism counts
count_shared_organisms <- function(df, plant_ids, ...) {
  columns <- c(...)
  organism_counts <- list()

  guild_df <- df %>% filter(plant_wfo_id %in% plant_ids)

  if (nrow(guild_df) == 0) {
    return(organism_counts)
  }

  for (i in seq_len(nrow(guild_df))) {
    row <- guild_df[i, ]
    plant_organisms <- c()

    for (col in columns) {
      col_val <- row[[col]]
      # Check if column value is list and not NULL/NA
      if (is.list(col_val)) {
        col_val <- col_val[[1]]  # Extract from list wrapper
      }
      if (!is.null(col_val) && length(col_val) > 0 && !all(is.na(col_val))) {
        plant_organisms <- c(plant_organisms, col_val)
      }
    }

    # Remove NA and ensure unique
    plant_organisms <- unique(plant_organisms[!is.na(plant_organisms)])

    if (length(plant_organisms) > 0) {
      for (org in plant_organisms) {
        # Ensure org is valid (not NULL, not NA, not empty string)
        if (!is.null(org) && !is.na(org) && nzchar(as.character(org))) {
          org_key <- as.character(org)
          if (is.null(organism_counts[[org_key]])) {
            organism_counts[[org_key]] <- 0
          }
          organism_counts[[org_key]] <- organism_counts[[org_key]] + 1
        }
      }
    }
  }

  organism_counts
}


#' Compute raw component scores for a guild
#'
#' @param guild_ids Vector of plant WFO IDs
#' @param plants_df Plant dataset
#' @param organisms_df Organism dataset
#' @param fungi_df Fungal dataset
#' @param phylo_calculator Faith's PD calculator instance
#' @return Named list of scores (m1, n4, p1-p6) or NULL if missing data
compute_raw_scores <- function(guild_ids, plants_df, organisms_df, fungi_df, phylo_calculator) {
  n_plants <- length(guild_ids)
  guild_plants <- plants_df %>% filter(wfo_taxon_id %in% guild_ids)

  if (nrow(guild_plants) != n_plants) {
    return(NULL)  # Missing data
  }

  scores <- list()

  # N4: CSR conflicts (conflict_density)
  HIGH_C <- 60
  HIGH_S <- 60
  HIGH_R <- 50
  conflicts <- 0

  high_c <- guild_plants %>% filter(CSR_C > HIGH_C)
  if (nrow(high_c) >= 2) {
    conflicts <- conflicts + choose(nrow(high_c), 2)
  }

  high_s <- guild_plants %>% filter(CSR_S > HIGH_S)
  high_c_plants <- guild_plants %>% filter(CSR_C > HIGH_C)

  for (i in seq_len(nrow(high_c_plants))) {
    for (j in seq_len(nrow(high_s))) {
      if (high_c_plants$wfo_taxon_id[i] != high_s$wfo_taxon_id[j]) {
        s_light <- ifelse(is.na(high_s$light_pref[j]), 5.0, high_s$light_pref[j])
        conflict <- if (s_light < 3.2) 0.0 else if (s_light > 7.47) 0.9 else 0.6
        conflicts <- conflicts + conflict
      }
    }
  }

  high_r <- guild_plants %>% filter(CSR_R > HIGH_R)
  for (i in seq_len(nrow(high_c_plants))) {
    for (j in seq_len(nrow(high_r))) {
      if (high_c_plants$wfo_taxon_id[i] != high_r$wfo_taxon_id[j]) {
        conflicts <- conflicts + 0.8
      }
    }
  }

  if (nrow(high_r) >= 2) {
    conflicts <- conflicts + choose(nrow(high_r), 2) * 0.3
  }

  max_pairs <- if (n_plants > 1) n_plants * (n_plants - 1) else 1
  scores$n4 <- conflicts / max_pairs

  # P3: Beneficial fungi
  beneficial_counts <- count_shared_organisms(
    fungi_df, guild_ids,
    'amf_fungi', 'emf_fungi', 'endophytic_fungi', 'saprotrophic_fungi'
  )

  network_raw <- 0
  for (org_name in names(beneficial_counts)) {
    count <- beneficial_counts[[org_name]]
    if (count >= 2) {
      network_raw <- network_raw + (count / n_plants)
    }
  }

  guild_fungi <- fungi_df %>% filter(plant_wfo_id %in% guild_ids)
  plants_with_beneficial <- 0

  for (i in seq_len(nrow(guild_fungi))) {
    row <- guild_fungi[i, ]
    has_beneficial <- FALSE
    for (col in c('amf_fungi', 'emf_fungi', 'endophytic_fungi', 'saprotrophic_fungi')) {
      col_val <- row[[col]]
      if (!is.null(col_val) && length(col_val) > 0) {
        has_beneficial <- TRUE
        break
      }
    }
    if (has_beneficial) {
      plants_with_beneficial <- plants_with_beneficial + 1
    }
  }

  coverage_ratio <- plants_with_beneficial / n_plants
  scores$p3 <- network_raw * 0.6 + coverage_ratio * 0.4

  # M1: Pathogen & Pest Independence using Faith's PD
  # Literature: Faith 1992, Phylopathogen 2013, Gougherty-Davies 2021, Keesing et al. 2006
  # Faith's PD increases with richness + divergence → captures dilution effect
  plant_ids <- guild_plants$wfo_taxon_id

  if (length(plant_ids) >= 2) {
    # Calculate Faith's PD using C++ binary
    faiths_pd <- phylo_calculator$calculate_pd(plant_ids, use_wfo_ids = TRUE)

    # Apply EXPONENTIAL TRANSFORMATION
    # Decay constant k calibrated for Faith's PD scale (hundreds)
    k <- 0.001  # Much smaller than old k=3.0 (Faith's PD >> eigenvector distances)
    pest_risk_raw <- exp(-k * faiths_pd)
    scores$m1 <- pest_risk_raw  # Store TRANSFORMED value (0-1 scale)
  } else {
    # Single plant = maximum pest risk
    scores$m1 <- 1.0  # No diversity = highest pest risk
  }

  # P5: Structural diversity
  heights <- guild_plants$height_m[!is.na(guild_plants$height_m)]
  forms <- guild_plants$try_growth_form[!is.na(guild_plants$try_growth_form)]

  p5_raw <- 0
  if (length(heights) >= 2) {
    height_range <- max(heights) - min(heights)
    p5_raw <- p5_raw + min(height_range / 20.0, 1.0) * 0.6
  }

  if (length(forms) > 0) {
    unique_forms <- length(unique(forms))
    p5_raw <- p5_raw + (unique_forms / 5.0) * 0.4
  }

  scores$p5 <- min(p5_raw, 1.0)

  # P6: Pollinators
  shared_pollinators <- count_shared_organisms(
    organisms_df, guild_ids,
    'pollinators', 'flower_visitors'
  )

  p6_score <- 0
  for (org_name in names(shared_pollinators)) {
    count <- shared_pollinators[[org_name]]
    if (count >= 2) {
      p6_score <- p6_score + (count / n_plants) ^ 1.5
    }
  }
  scores$p6 <- p6_score

  # P1/P2: Set to 0 (require complex relationship tables)
  scores$p1 <- 0.0
  scores$p2 <- 0.0

  scores
}


#' Run calibration for one stage
#'
#' @param tier_plants Named list of plant IDs per tier
#' @param plants_df Plant dataset
#' @param organisms_df Organism dataset
#' @param fungi_df Fungal dataset
#' @param phylo_calculator Faith's PD calculator
#' @param guild_size Number of plants per guild
#' @param n_guilds_per_tier Number of guilds to sample per tier
#' @param stage_name Stage description
#' @return Named list of calibration results
calibrate_stage <- function(tier_plants, plants_df, organisms_df, fungi_df,
                            phylo_calculator, guild_size, n_guilds_per_tier, stage_name) {
  cat("\n================================================================================\n")
  cat(sprintf("STAGE: %s\n", stage_name))
  cat("================================================================================\n")
  cat(sprintf("Guild size: %d plants\n", guild_size))
  cat(sprintf("Guilds per tier: %s\n", format(n_guilds_per_tier, big.mark = ",")))

  calibration_results <- list()

  for (tier_name in names(tier_plants)) {
    plant_ids <- tier_plants[[tier_name]]
    cat(sprintf("\n%s:\n", tier_name))
    cat(sprintf("  Plant pool: %s\n", format(length(plant_ids), big.mark = ",")))

    # Initialize storage for raw scores
    tier_raw_scores <- list()
    for (comp in COMPONENTS) {
      tier_raw_scores[[comp]] <- numeric(0)
    }

    successful <- 0
    attempts <- 0
    max_attempts <- n_guilds_per_tier * 100  # Safety limit

    while (successful < n_guilds_per_tier && attempts < max_attempts) {
      attempts <- attempts + 1

      # Sample guild
      guild_ids <- sample(plant_ids, size = guild_size, replace = FALSE)
      raw_scores <- compute_raw_scores(guild_ids, plants_df, organisms_df, fungi_df, phylo_calculator)

      if (!is.null(raw_scores)) {
        for (comp in COMPONENTS) {
          tier_raw_scores[[comp]] <- c(tier_raw_scores[[comp]], raw_scores[[comp]])
        }
        successful <- successful + 1
      }

      # Progress indicator
      if (successful %% 10 == 0) {
        cat(sprintf("\r  Sampling: %d/%d", successful, n_guilds_per_tier))
      }
    }
    cat(sprintf("\r  Sampling: %d/%d - Complete\n", successful, n_guilds_per_tier))

    # Compute percentiles
    tier_percentiles <- list()
    for (comp in COMPONENTS) {
      values <- tier_raw_scores[[comp]]
      percentiles <- setNames(
        quantile(values, probs = PERCENTILES / 100, names = FALSE),
        sprintf("p%02d", PERCENTILES)
      )
      tier_percentiles[[comp]] <- as.list(percentiles)

      cat(sprintf("  %s: p01=%.4f, p50=%.4f, p99=%.4f\n",
                  comp, percentiles["p01"], percentiles["p50"], percentiles["p99"]))
    }

    calibration_results[[tier_name]] <- tier_percentiles
  }

  calibration_results
}


#' Main calibration function
#'
#' @param stage Which stage to run: '1', '2', or 'both'
#' @param n_guilds Number of guilds per tier (default 20000)
main <- function(stage = 'both', n_guilds = 20000) {
  # Load data
  data <- load_all_data()
  tier_plants <- organize_by_tier(data$plants_df)

  # Initialize Faith's PD calculator (once for all calibrations)
  cat("\nInitializing Faith's PD calculator...\n")
  phylo_calculator <- PhyloPDCalculator$new()
  cat("✓ Faith's PD calculator loaded\n")

  # Stage 1: 2-plant
  if (stage %in% c('1', 'both')) {
    results <- calibrate_stage(
      tier_plants, data$plants_df, data$organisms_df, data$fungi_df,
      phylo_calculator, 2, n_guilds, 'Stage 1: 2-Plant'
    )

    output_file <- 'shipley_checks/stage4/normalization_params_2plant_R.json'
    dir.create(dirname(output_file), showWarnings = FALSE, recursive = TRUE)
    write_json(results, output_file, pretty = TRUE, auto_unbox = TRUE)
    cat(sprintf("\n✓ Saved: %s\n", output_file))
  }

  # Stage 2: 7-plant
  if (stage %in% c('2', 'both')) {
    results <- calibrate_stage(
      tier_plants, data$plants_df, data$organisms_df, data$fungi_df,
      phylo_calculator, 7, n_guilds, 'Stage 2: 7-Plant'
    )

    output_file <- 'shipley_checks/stage4/normalization_params_7plant_R.json'
    dir.create(dirname(output_file), showWarnings = FALSE, recursive = TRUE)
    write_json(results, output_file, pretty = TRUE, auto_unbox = TRUE)
    cat(sprintf("\n✓ Saved: %s\n", output_file))
  }

  cat("\n================================================================================\n")
  cat("CALIBRATION COMPLETE\n")
  cat("================================================================================\n")
}


# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
stage <- if (length(args) >= 1) args[1] else 'both'
n_guilds <- if (length(args) >= 2) as.integer(args[2]) else 20000

# Run calibration
main(stage = stage, n_guilds = n_guilds)
