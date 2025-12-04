#!/usr/bin/env Rscript
# generate_distribution_heatmaps.R
#
# Generates Apple Maps-style distribution heatmaps for encyclopedia species
# Uses kernel density estimation for fuzzy/organic boundaries
#
# Usage:
#   env R_LIBS_USER="/home/olier/ellenberg/.Rlib" /usr/bin/Rscript generate_distribution_heatmaps.R
#
# Output: PNG files in shipley_checks/stage4/distribution_maps/
# Post-process: Convert to WebP with cwebp

suppressPackageStartupMessages({
  library(duckdb)
  library(DBI)
  library(ggplot2)
  library(sf)
  library(rnaturalearth)
  library(dplyr)
  library(parallel)
  library(pbapply)
})

# Configuration
BASE_DIR <- "/home/olier/ellenberg"
GBIF_PARQUET <- file.path(BASE_DIR, "data/gbif/occurrence_plantae_wfo.parquet")
ENCYCLOPEDIA_PARQUET <- file.path(BASE_DIR, "shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet")
OUTPUT_DIR <- file.path(BASE_DIR, "shipley_checks/stage4/distribution_maps")
LOG_FILE <- file.path(OUTPUT_DIR, "generation_log.txt")

# Number of parallel workers (adjust based on RAM - each worker needs ~2GB)
N_WORKERS <- 6

# Minimum points required for heatmap generation
MIN_POINTS <- 5

# Apple-inspired color palette
OCEAN_COLOR <- "#1a1a2e"
LAND_COLOR <- "#2d2d3a"
HEAT_LOW <- "#064e3b"    # Dark emerald (sparse)
HEAT_HIGH <- "#34d399"   # Bright emerald (dense)

# Create output directory
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

log_msg <- function(msg) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  line <- paste0("[", timestamp, "] ", msg)
  cat(line, "\n")
  cat(line, "\n", file = LOG_FILE, append = TRUE)
}

log_msg("Starting distribution heatmap generation")
log_msg(paste("Output directory:", OUTPUT_DIR))

# Load world map for base layer
log_msg("Loading world map...")
world <- ne_countries(scale = "medium", returnclass = "sf")

# Connect to DuckDB and load data
log_msg("Connecting to DuckDB and loading occurrence data...")
con <- dbConnect(duckdb())

# Get encyclopedia species list
encyclopedia_query <- sprintf("
  SELECT DISTINCT wfo_taxon_id
  FROM read_parquet('%s')
", ENCYCLOPEDIA_PARQUET)
encyclopedia_species <- dbGetQuery(con, encyclopedia_query)$wfo_taxon_id
log_msg(paste("Encyclopedia species:", length(encyclopedia_species)))

# Load all occurrences for encyclopedia species (with coordinates)
occurrence_query <- sprintf("
  SELECT
    wfo_taxon_id,
    decimalLatitude as lat,
    decimalLongitude as lon
  FROM read_parquet('%s')
  WHERE wfo_taxon_id IN (SELECT DISTINCT wfo_taxon_id FROM read_parquet('%s'))
    AND decimalLatitude IS NOT NULL
    AND decimalLongitude IS NOT NULL
    AND decimalLatitude BETWEEN -90 AND 90
    AND decimalLongitude BETWEEN -180 AND 180
", GBIF_PARQUET, ENCYCLOPEDIA_PARQUET)

log_msg("Loading occurrence data (this may take a few minutes)...")
occurrences <- dbGetQuery(con, occurrence_query)
log_msg(paste("Total occurrences loaded:", format(nrow(occurrences), big.mark = ",")))

# Get count per species
species_counts <- occurrences %>%
  group_by(wfo_taxon_id) %>%
  summarise(n = n(), .groups = "drop") %>%
  arrange(desc(n))

log_msg(paste("Species with occurrences:", nrow(species_counts)))
log_msg(paste("Species with <", MIN_POINTS, "points (will skip):",
              sum(species_counts$n < MIN_POINTS)))

dbDisconnect(con, shutdown = TRUE)

# Filter to species with enough points
valid_species <- species_counts %>%
  filter(n >= MIN_POINTS) %>%
  pull(wfo_taxon_id)

log_msg(paste("Species to process:", length(valid_species)))

# Check for already generated maps
existing_maps <- list.files(OUTPUT_DIR, pattern = "\\.png$", full.names = FALSE)
existing_ids <- sub("\\.png$", "", existing_maps)
remaining_species <- setdiff(valid_species, existing_ids)

log_msg(paste("Already generated:", length(existing_ids)))
log_msg(paste("Remaining to generate:", length(remaining_species)))

if (length(remaining_species) == 0) {
  log_msg("All maps already generated. Exiting.")
  quit(save = "no", status = 0)
}

# Function to generate single heatmap
generate_heatmap <- function(species_id, all_occurrences, world_map, output_dir) {

  tryCatch({
    # Get points for this species
    species_points <- all_occurrences %>%
      filter(wfo_taxon_id == species_id)

    n_points <- nrow(species_points)

    if (n_points < MIN_POINTS) {
      return(list(species_id = species_id, status = "skipped", reason = "too_few_points", n = n_points))
    }

    # Determine density bandwidth based on point count
    # More points = tighter bandwidth for sharper detail
    # Fewer points = wider bandwidth for smoother appearance
    h_adjust <- if (n_points > 10000) 0.3 else if (n_points > 1000) 0.5 else if (n_points > 100) 0.8 else 1.2

    # Create the plot
    p <- ggplot() +
      # Ocean background
      theme_void() +
      theme(
        plot.background = element_rect(fill = OCEAN_COLOR, color = NA),
        panel.background = element_rect(fill = OCEAN_COLOR, color = NA),
        plot.margin = margin(0, 0, 0, 0)
      ) +
      # Land silhouette
      geom_sf(data = world_map, fill = LAND_COLOR, color = NA) +
      # Density heatmap layer
      stat_density_2d(
        data = species_points,
        aes(x = lon, y = lat, fill = after_stat(level)),
        geom = "polygon",
        alpha = 0.7,
        bins = 12,
        h = c(h_adjust * 10, h_adjust * 10)  # Bandwidth in degrees
      ) +
      scale_fill_gradient(low = HEAT_LOW, high = HEAT_HIGH, guide = "none") +
      # Map bounds (exclude Antarctica)
      coord_sf(
        xlim = c(-180, 180),
        ylim = c(-60, 85),
        expand = FALSE
      )

    # Save as PNG (will convert to WebP later)
    output_path <- file.path(output_dir, paste0(species_id, ".png"))

    ggsave(
      output_path,
      plot = p,
      width = 9.6,
      height = 4.8,
      dpi = 100,
      bg = OCEAN_COLOR
    )

    return(list(species_id = species_id, status = "success", n = n_points))

  }, error = function(e) {
    return(list(species_id = species_id, status = "error", reason = as.character(e)))
  })
}

# Process in batches with progress
log_msg(paste("Starting parallel generation with", N_WORKERS, "workers"))
log_msg(paste("Estimated time: ~", round(length(remaining_species) / 60 / N_WORKERS, 1), "hours"))

# Set up cluster
cl <- makeCluster(N_WORKERS)

# Export required objects to workers
clusterExport(cl, c("occurrences", "world", "generate_heatmap", "OUTPUT_DIR",
                    "OCEAN_COLOR", "LAND_COLOR", "HEAT_LOW", "HEAT_HIGH", "MIN_POINTS"))

# Load required packages on workers
clusterEvalQ(cl, {
  suppressPackageStartupMessages({
    library(ggplot2)
    library(sf)
    library(dplyr)
  })
})

# Process with progress bar
results <- pblapply(remaining_species, function(sp) {
  generate_heatmap(sp, occurrences, world, OUTPUT_DIR)
}, cl = cl)

stopCluster(cl)

# Summarize results
results_df <- bind_rows(lapply(results, as.data.frame))

success_count <- sum(results_df$status == "success")
error_count <- sum(results_df$status == "error")
skipped_count <- sum(results_df$status == "skipped")

log_msg("=== Generation Complete ===")
log_msg(paste("Success:", success_count))
log_msg(paste("Errors:", error_count))
log_msg(paste("Skipped:", skipped_count))

# Save results summary
results_path <- file.path(OUTPUT_DIR, "generation_results.csv")
write.csv(results_df, results_path, row.names = FALSE)
log_msg(paste("Results saved to:", results_path))

# List any errors
if (error_count > 0) {
  log_msg("Errors encountered:")
  errors <- results_df %>% filter(status == "error")
  for (i in 1:nrow(errors)) {
    log_msg(paste(" -", errors$species_id[i], ":", errors$reason[i]))
  }
}

# Count total PNGs
final_count <- length(list.files(OUTPUT_DIR, pattern = "\\.png$"))
log_msg(paste("Total PNG files:", final_count))
log_msg("Next step: Convert to WebP with convert_to_webp.sh")
