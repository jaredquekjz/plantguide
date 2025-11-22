#!/usr/bin/env Rscript
#
# Debug M1 (Pest Independence) R vs Rust Parity
# Compare step-by-step calculation for Forest Garden guild
#

suppressPackageStartupMessages({
  library(glue)
  library(dplyr)
  library(arrow)
  library(jsonlite)
})

source('shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R')

cat("\n", strrep("=", 70), "\n", sep = "")
cat("M1 PARITY DEBUG: Forest Garden Guild\n")
cat(strrep("=", 70), "\n\n")

# Initialize scorer
scorer <- GuildScorerV3Shipley$new('7plant', 'tier_3_humid_temperate')

# Forest Garden plants
plant_ids <- c(
  "wfo-0000832453",
  "wfo-0000649136",
  "wfo-0000642673",
  "wfo-0000984977",
  "wfo-0000241769",
  "wfo-0000092746",
  "wfo-0000690499"
)

cat("Plants in guild:", length(plant_ids), "\n\n")

# Get plant data
plants_data <- scorer$plants_lf %>%
  filter(wfo_taxon_id %in% plant_ids) %>%
  collect()

cat("Plant CSR values:\n")
for (i in 1:nrow(plants_data)) {
  cat(glue("  {plants_data$wfo_taxon_id[i]}: C={plants_data$c[i]:.1f}, S={plants_data$s[i]:.1f}, R={plants_data$r[i]:.1f}"), "\n")
}
cat("\n")

# Calculate M1 with detailed output
cat(strrep("=", 70), "\n")
cat("M1 CALCULATION BREAKDOWN\n")
cat(strrep("=", 70), "\n\n")

# Load CSR calibration
csr_cal_file <- "shipley_checks/stage4/csr_percentile_calibration_global.json"
if (file.exists(csr_cal_file)) {
  csr_cal <- fromJSON(csr_cal_file)
  cat("CSR Percentile Calibration (global):\n")
  cat(glue("  C p50: {csr_cal$c$p50}, p95: {csr_cal$c$p95}"), "\n")
  cat(glue("  S p50: {csr_cal$s$p50}, p95: {csr_cal$s$p95}"), "\n")
  cat(glue("  R p50: {csr_cal$r$p50}, p95: {csr_cal$r$p95}"), "\n\n")
} else {
  cat("⚠ CSR calibration file not found!\n\n")
}

# Calculate M1 manually with step-by-step logging
cat("Step-by-step M1 calculation:\n\n")

# Get herbivore data
cat("1. Loading herbivore/fungivore data...\n")
herbivores_lf <- open_dataset("shipley_checks/validation/organism_profiles_pure_rust.parquet") %>%
  filter(taxon_category %in% c("herbivore", "fungivore"))

total_herbivores <- herbivores_lf %>% count() %>% collect() %>% pull(n)
cat(glue("   Total herbivores/fungivores in dataset: {total_herbivores}"), "\n\n")

# For each plant, count pests
pest_counts <- data.frame(
  plant_id = character(),
  n_pests = integer(),
  pest_load = numeric(),
  stringsAsFactors = FALSE
)

for (plant_id in plant_ids) {
  # Get pests for this plant (exactly as in the scorer)
  pests <- herbivores_lf %>%
    filter(
      grepl(plant_id, host_plants_list) |
      grepl(plant_id, interactions_list) |
      grepl(plant_id, adjacency_list)
    ) %>%
    select(taxon_id) %>%
    distinct() %>%
    collect()

  n_pests <- nrow(pests)
  pest_load <- (n_pests / max(total_herbivores, 1)) * 100.0

  pest_counts <- rbind(pest_counts, data.frame(
    plant_id = plant_id,
    n_pests = n_pests,
    pest_load = pest_load,
    stringsAsFactors = FALSE
  ))

  cat(glue("   {plant_id}: {n_pests} pests → {sprintf('%.4f', pest_load)}% load"), "\n")
}

cat("\n2. Guild-level pest load:\n")
avg_pest_load <- mean(pest_counts$pest_load)
cat(glue("   Average: {sprintf('%.6f', avg_pest_load)}%"), "\n")
cat(glue("   Range: {sprintf('%.4f', min(pest_counts$pest_load))}% - {sprintf('%.4f', max(pest_counts$pest_load))}%"), "\n\n")

cat("3. Normalization (tier-specific):\n")
cal_params <- scorer$calibration_params
tier_params <- cal_params[[scorer$climate_tier]]
m1_params <- tier_params$m1_pest_independence

cat(glue("   Tier: {scorer$climate_tier}"), "\n")
cat(glue("   M1 min: {m1_params$min}"), "\n")
cat(glue("   M1 max: {m1_params$max}"), "\n")
cat(glue("   M1 mean: {m1_params$mean}"), "\n")
cat(glue("   M1 std: {m1_params$std}"), "\n\n")

# Calculate normalized score
raw_independence <- 100.0 - avg_pest_load
cat(glue("   Raw independence: {sprintf('%.6f', raw_independence)}"), "\n")

z_score <- (raw_independence - m1_params$mean) / m1_params$std
cat(glue("   Z-score: {sprintf('%.6f', z_score)}"), "\n")

normalized_score <- 50.0 + (z_score * 10.0)
cat(glue("   Normalized (50 + z*10): {sprintf('%.6f', normalized_score)}"), "\n")

m1_final <- max(0.0, min(100.0, normalized_score))
cat(glue("   Clamped [0,100]: {sprintf('%.6f', m1_final)}"), "\n\n")

cat(strrep("=", 70), "\n")
cat("COMPARISON\n")
cat(strrep("=", 70), "\n\n")

# Run full scorer
result <- scorer$score_guild(plant_ids)

cat(glue("R Implementation:"), "\n")
cat(glue("  M1 from scorer: {sprintf('%.2f', result$metrics[1])}"), "\n")
cat(glue("  M1 manual calc: {sprintf('%.2f', m1_final)}"), "\n\n")

cat(glue("Expected from Rust: 58.33"), "\n\n")

cat(glue("Difference (R - Rust): {sprintf('%.2f', result$metrics[1] - 58.33)}"), "\n\n")
