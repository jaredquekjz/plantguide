#!/usr/bin/env Rscript

# Ensure local R library is available (user-installed pkgs)
.libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))

# =============================================================================
# Bioclim-First Extraction Pipeline
# =============================================================================
# Extract bioclim BEFORE coordinate cleaning to understand data loss
# This helps identify if species are lost due to:
# 1. Ocean/no-data areas (bioclim extraction fails)
# 2. Coordinate cleaning (capitals, institutions, etc.)

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(terra)
  library(CoordinateCleaner)
  library(parallel)
})

cat("=== BIOCLIM-FIRST EXTRACTION PIPELINE ===\n")
cat("Processing all 1,051 matched species\n")
cat("Extracting bioclim BEFORE coordinate cleaning\n\n")

# Configuration
config <- list(
  matches_file = "/home/olier/ellenberg/artifacts/gbif_complete_trait_matches_wfo.json",
  worldclim_dir = "/home/olier/ellenberg/data/worldclim/bio",
  output_dir = "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first",
  n_cores = 8,
  capitals_radius = 20000,      # 20km
  institutions_radius = 2000,    # 2km
  min_occurrences = 3,
  trait_csv = "/home/olier/ellenberg/artifacts/model_data_complete_case_with_myco.csv",
  filtered_traits_out = "/home/olier/ellenberg/artifacts/model_data_bioclim_subset.csv"
)

# Create output directories
dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(config$output_dir, "species_data"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(config$output_dir, "diagnostics"), recursive = TRUE, showWarnings = FALSE)

# =============================================================================
# Step 1: Load matched species and GBIF data
# =============================================================================

cat("Step 1: Loading data...\n")

# Load matches
matches <- fromJSON(config$matches_file)
matched_species <- matches$matched_species
cat(sprintf("  Loaded %d matched species from JSON\n", nrow(matched_species)))

# Function to read GBIF file
read_gbif <- function(file, species_name) {
  tryCatch({
    dt <- fread(cmd = sprintf("zcat '%s'", file), showProgress = FALSE, sep = "\t")
    dt[, species_clean := species_name]
    
    # Keep essential columns
    essential <- c("gbifID", "decimalLatitude", "decimalLongitude", "year", 
                  "coordinateUncertaintyInMeters", "countryCode", "species_clean",
                  "basisOfRecord", "establishmentMeans")
    available <- intersect(essential, names(dt))
    
    if (length(available) == 0 || nrow(dt) == 0) {
      return(data.table(species_clean = species_name))
    }
    
    return(dt[, ..available])
  }, error = function(e) {
    cat(sprintf("  Error reading %s: %s\n", basename(file), e$message))
    return(NULL)
  })
}

# Read all files
cat("  Reading GBIF files...\n")
all_data_list <- mclapply(1:nrow(matched_species), function(i) {
  read_gbif(matched_species$gbif_file[i], matched_species$trait_name[i])
}, mc.cores = config$n_cores)

# Remove NULLs and combine
all_data_list <- all_data_list[!sapply(all_data_list, is.null)]
all_data <- rbindlist(all_data_list, fill = TRUE)

n_species_loaded <- uniqueN(all_data$species_clean)
cat(sprintf("  Loaded %s occurrences from %d species\n", 
            format(nrow(all_data), big.mark=","), n_species_loaded))

# Track species counts at each step
species_tracking <- data.table(
  species = unique(all_data$species_clean),
  n_raw = as.numeric(NA),
  n_with_coords = as.numeric(NA),
  n_with_bioclim = as.numeric(NA),
  n_after_cleaning = as.numeric(NA),
  reason_lost = as.character(NA)
)

# Count raw occurrences per species
raw_counts <- all_data[, .N, by = species_clean]
species_tracking[raw_counts, n_raw := i.N, on = .(species = species_clean)]

# =============================================================================
# Step 2: Basic coordinate validation (just remove invalid)
# =============================================================================

cat("\nStep 2: Basic coordinate validation...\n")

# Remove only invalid coordinates (keep everything else for now)
all_data <- all_data[!is.na(decimalLatitude) & !is.na(decimalLongitude)]
all_data <- all_data[decimalLatitude >= -90 & decimalLatitude <= 90]
all_data <- all_data[decimalLongitude >= -180 & decimalLongitude <= 180]
all_data <- all_data[!(decimalLatitude == 0 & decimalLongitude == 0)]  # Remove 0,0

n_species_with_coords <- uniqueN(all_data$species_clean)
cat(sprintf("  %s occurrences with valid coordinates\n", format(nrow(all_data), big.mark=",")))
cat(sprintf("  %d species with valid coordinates\n", n_species_with_coords))

# Update tracking
coord_counts <- all_data[, .N, by = species_clean]
species_tracking[coord_counts, n_with_coords := i.N, on = .(species = species_clean)]
species_tracking[is.na(n_with_coords), n_with_coords := 0]

# =============================================================================
# Step 3: Extract bioclim for ALL valid coordinates (before cleaning)
# =============================================================================

cat("\nStep 3: Extracting bioclim (this will take 5-10 minutes)...\n")

# Load WorldClim rasters
bio_files <- list.files(
  config$worldclim_dir,
  pattern = "wc2\\.1_30s_bio_.*\\.tif$",
  full.names = TRUE
)
if (length(bio_files) == 0) {
  stop("No WorldClim BIO rasters found in directory: ", config$worldclim_dir)
}
# Ensure rasters are ordered numerically (bio_1.tif ... bio_19.tif)
bio_indices <- as.integer(sub("^.*_bio_(\\d+)\\.tif$", "\\1", basename(bio_files)))
order_idx <- order(bio_indices)
bio_files <- bio_files[order_idx]
bio_stack <- rast(bio_files)
names(bio_stack) <- paste0("bio", 1:19)

# Get unique coordinates for efficiency
unique_coords <- unique(all_data[, .(decimalLongitude, decimalLatitude)])
cat(sprintf("  Extracting for %s unique coordinates\n", 
            format(nrow(unique_coords), big.mark=",")))

# Extract bioclim
coords_mat <- as.matrix(unique_coords)
bio_values <- extract(bio_stack, coords_mat)

# Combine with coordinates (remove ID column if present)
if ("ID" %in% names(bio_values)) {
  bio_values <- bio_values[, -1]
}
unique_coords_bio <- cbind(unique_coords, bio_values)

# Check how many have valid bioclim data
n_valid_bio <- sum(complete.cases(unique_coords_bio[, 3:ncol(unique_coords_bio)]))
n_invalid_bio <- nrow(unique_coords_bio) - n_valid_bio

cat(sprintf("  %s coordinates with valid bioclim data\n", format(n_valid_bio, big.mark=",")))
cat(sprintf("  %s coordinates with NO bioclim data (ocean/mask)\n", 
            format(n_invalid_bio, big.mark=",")))

# Merge back to all occurrences
all_data <- merge(all_data, unique_coords_bio, 
                 by = c("decimalLongitude", "decimalLatitude"), 
                 all.x = TRUE)

# Check which species have bioclim data
bio_cols <- paste0("bio", 1:19)
all_data[, has_bioclim := complete.cases(.SD), .SDcols = bio_cols]

n_with_bio <- sum(all_data$has_bioclim)
cat(sprintf("  %s total occurrences with bioclim data\n", format(n_with_bio, big.mark=",")))

# Count by species
bio_counts <- all_data[has_bioclim == TRUE, .N, by = species_clean]
species_tracking[bio_counts, n_with_bioclim := i.N, on = .(species = species_clean)]
species_tracking[is.na(n_with_bioclim), n_with_bioclim := 0]

n_species_with_bio <- sum(species_tracking$n_with_bioclim > 0)
cat(sprintf("  %d species with at least 1 bioclim occurrence\n", n_species_with_bio))

# Find species lost due to no bioclim
lost_to_ocean <- species_tracking[n_with_coords > 0 & n_with_bioclim == 0, species]
if (length(lost_to_ocean) > 0) {
  cat(sprintf("\n  WARNING: %d species lost due to ocean/no-data:\n", length(lost_to_ocean)))
  for (sp in head(lost_to_ocean, 10)) {
    sp_data <- all_data[species_clean == sp]
    cat(sprintf("    - %s (%d coords, all ocean/no-data)\n", sp, nrow(sp_data)))
  }
  species_tracking[species %in% lost_to_ocean, reason_lost := "ocean/no_bioclim"]
}

# =============================================================================
# Step 4: Coordinate cleaning (only on occurrences with bioclim)
# =============================================================================

cat("\nStep 4: Coordinate cleaning...\n")

# Filter to only occurrences with bioclim data
data_with_bio <- all_data[has_bioclim == TRUE]
cat(sprintf("  Starting with %s occurrences with bioclim\n", 
            format(nrow(data_with_bio), big.mark=",")))

# Prepare for CoordinateCleaner
cc_data <- data.frame(
  decimallongitude = data_with_bio$decimalLongitude,
  decimallatitude = data_with_bio$decimalLatitude,
  species_clean = data_with_bio$species_clean,
  countryCode = data_with_bio$countryCode
)

# Run coordinate tests
tests_to_run <- c("capitals", "centroids", "equal", "gbif", "institutions")

cc_cleaned <- clean_coordinates(
  x = cc_data,
  lon = "decimallongitude",
  lat = "decimallatitude",
  species = "species_clean",
  countries = "countryCode",
  tests = tests_to_run,
  capitals_rad = config$capitals_radius,
  inst_rad = config$institutions_radius,
  value = "spatialvalid"
)

# Count failures by test
cat("  Coordinate test results:\n")
for (test in tests_to_run) {
  col <- paste0(".", test)
  if (col %in% names(cc_cleaned)) {
    n_failed <- sum(!cc_cleaned[[col]], na.rm = TRUE)
    if (n_failed > 0) {
      cat(sprintf("    %s: %d failed\n", test, n_failed))
    }
  }
}

# Keep only records passing all tests
cc_cleaned <- cc_cleaned[cc_cleaned$.summary, ]
cat(sprintf("  %s occurrences passed all coordinate tests\n", 
            format(nrow(cc_cleaned), big.mark=",")))

# Convert back to data.table and update species tracking
cc_cleaned_dt <- as.data.table(cc_cleaned)
clean_counts <- cc_cleaned_dt[, .N, by = species_clean]
species_tracking[clean_counts, n_after_cleaning := i.N, on = .(species = species_clean)]
species_tracking[is.na(n_after_cleaning), n_after_cleaning := 0]

# Find species lost due to coordinate cleaning
lost_to_cleaning <- species_tracking[n_with_bioclim > 0 & n_after_cleaning == 0, species]
if (length(lost_to_cleaning) > 0) {
  cat(sprintf("\n  WARNING: %d species lost due to coordinate cleaning:\n", 
              length(lost_to_cleaning)))
  for (sp in head(lost_to_cleaning, 10)) {
    n_before <- species_tracking[species == sp, n_with_bioclim]
    cat(sprintf("    - %s (had %d with bioclim, all failed tests)\n", sp, n_before))
  }
  species_tracking[species %in% lost_to_cleaning, reason_lost := "coord_cleaning"]
}

# =============================================================================
# Step 5: Final summary and save results
# =============================================================================

cat("\n=== FINAL SUMMARY ===\n")

# Overall statistics
cat(sprintf("Started with: %d species\n", nrow(matched_species)))
cat(sprintf("Had GBIF data: %d species\n", n_species_loaded))
cat(sprintf("Had valid coordinates: %d species\n", n_species_with_coords))
cat(sprintf("Had bioclim data: %d species\n", n_species_with_bio))
cat(sprintf("Passed coordinate cleaning: %d species\n", 
            sum(species_tracking$n_after_cleaning > 0)))

# Species with sufficient data
sufficient <- species_tracking[n_after_cleaning >= config$min_occurrences]
cat(sprintf("Have ≥%d occurrences: %d species\n", 
            config$min_occurrences, nrow(sufficient)))

# Loss breakdown
cat("\n=== SPECIES LOSS BREAKDOWN ===\n")
loss_summary <- species_tracking[, .N, by = reason_lost]
loss_summary <- loss_summary[!is.na(reason_lost)]
if (nrow(loss_summary) > 0) {
  for (i in 1:nrow(loss_summary)) {
    cat(sprintf("  %s: %d species\n", loss_summary$reason_lost[i], loss_summary$N[i]))
  }
}

# Save diagnostic file
diagnostic_file <- file.path(config$output_dir, "diagnostics", "species_tracking.csv")
fwrite(species_tracking, diagnostic_file)
cat(sprintf("\nSpecies tracking saved to: %s\n", diagnostic_file))

# Save final cleaned data
# Keep ALL occurrences that passed cleaning (no unique()!)
cc_keep <- cc_cleaned_dt[, .(decimallongitude, decimallatitude, species_clean)]

# Filter original data to only cleaned coordinates
final_data <- data_with_bio[paste(decimalLongitude, decimalLatitude, species_clean) %in% 
                            paste(cc_keep$decimallongitude, cc_keep$decimallatitude, cc_keep$species_clean)]
final_file <- file.path(config$output_dir, "all_occurrences_cleaned.csv")
fwrite(final_data, final_file)
cat(sprintf("Final data saved to: %s\n", final_file))

## ---------------------------------------------------------------------------
## Step 6b: Species-level climate summary (means/sd) and sufficiency flag
## ---------------------------------------------------------------------------

cat("\nStep 6b: Creating species-level bioclim summary...\n")

summary_dir <- file.path(config$output_dir, "summary_stats")
dir.create(summary_dir, recursive = TRUE, showWarnings = FALSE)

bio_cols <- paste0("bio", 1:19)

# Initialize summary with counts per species
sp_summary <- final_data[, .(n_occurrences = .N), by = .(species = species_clean)]

# Also compute number of unique coordinates per species
final_unique <- unique(final_data, by = c("species_clean", "decimalLongitude", "decimalLatitude"))
unique_counts <- final_unique[, .(n_unique_coords = .N), by = .(species = species_clean)]
sp_summary <- merge(sp_summary, unique_counts, by = "species", all.x = TRUE)

# Add mean and sd for each bioclim variable
for (v in bio_cols) {
  if (v %in% names(final_data)) {
    # Compute environmental summaries from unique coordinates to avoid overweighting
    stats_dt <- final_unique[!is.na(get(v)), .(
      mean_val = mean(get(v), na.rm = TRUE),
      sd_val   = sd(get(v),   na.rm = TRUE)
    ), by = species_clean]
    setnames(stats_dt, c("species_clean", "mean_val", "sd_val"),
             c("species", paste0(v, "_mean"), paste0(v, "_sd")))
    sp_summary <- merge(sp_summary, stats_dt, by = "species", all.x = TRUE)
  }
}

# Mark species with sufficient data (≥3 occurrences as requested)
sp_summary[, has_sufficient_data := n_occurrences >= 3]

summary_file <- file.path(summary_dir, "species_bioclim_summary.csv")
fwrite(sp_summary, summary_file)
cat(sprintf("Species summary saved to: %s\n", summary_file))

## ---------------------------------------------------------------------------
## Step 6c: Merge with trait table and write bioclim‑subset trait CSV (>=3)
## ---------------------------------------------------------------------------

cat("\nStep 6c: Merging species summary with trait table and filtering (>=3) ...\n")

# Safe helpers
normalize_species <- function(x) {
  tolower(gsub("[[:space:]_-]+", "_", x))
}

trait_csv_path <- config$trait_csv
if (!file.exists(trait_csv_path)) {
  cat(sprintf("  WARNING: Trait CSV not found at %s; skipping merge/filter step.\n", trait_csv_path))
} else {
  # Read traits
  traits <- tryCatch({
    fread(trait_csv_path)
  }, error = function(e) {
    cat(sprintf("  ERROR reading traits: %s\n", e$message)); NULL
  })

  if (!is.null(traits) && ("wfo_accepted_name" %in% names(traits))) {
    # Normalize species
    traits[, species_norm := normalize_species(wfo_accepted_name)]
    sp_summary[, species_norm := normalize_species(species)]

    # Keep species with >= min_occurrences
    keep_norm <- sp_summary[n_occurrences >= config$min_occurrences, species_norm]
    filtered_traits <- traits[species_norm %in% keep_norm]
    filtered_traits[, species_norm := NULL]

    # Write filtered CSV for SEM/hybrid stage
    out_path <- config$filtered_traits_out
    fwrite(filtered_traits, out_path)
    cat(sprintf("  Filtered trait CSV (>=%d) saved to: %s\n", config$min_occurrences, out_path))
    cat(sprintf("  Species retained: %d\n", nrow(filtered_traits)))
  } else {
    cat("  WARNING: Trait table missing or lacks 'wfo_accepted_name'; skipping merge/filter.\n")
  }
}

cat("\n✓ Pipeline complete!\n")
