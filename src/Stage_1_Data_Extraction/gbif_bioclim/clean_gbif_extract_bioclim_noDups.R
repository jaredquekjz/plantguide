#!/usr/bin/env Rscript

# =============================================================================
# GBIF Cleaning Pipeline - No Duplicates Version
# =============================================================================
# Skips sea test (hangs) and duplicates test (keeps multiple obs per location)
# Uses standard CoordinateCleaner approach but without duplicate removal

# Set up local R library
.libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))

suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
  library(CoordinateCleaner)
  library(terra)
  library(cli)
  library(parallel)
})

cli_h1("GBIF Cleaning Pipeline (No Duplicates)")
cli_alert_info("Skips sea test (hangs) and duplicates (preserves all observations)")

# Configuration with relaxed parameters
config <- list(
  worldclim_dir = "/home/olier/ellenberg/data/worldclim/bio",
  gbif_dir = "/home/olier/ellenberg/data/gbif_occurrences_model_species",
  output_dir = "/home/olier/ellenberg/data/bioclim_extractions_cleaned",
  cores = min(8, parallel::detectCores() - 1),
  min_year = 1950,
  max_coord_uncertainty = 10000,
  capitals_radius = 20000,      # Relaxed from 10km to 20km
  institutions_radius = 2000,    # Relaxed from 1km to 2km
  outlier_quantile = 0.001,
  min_occurrences = 3
)

# Create output directories
for (subdir in c("", "species_bioclim", "summary_stats", "quality_reports")) {
  dir.create(file.path(config$output_dir, subdir), recursive = TRUE, showWarnings = FALSE)
}

# =============================================================================
# Step 1: Load GBIF Data
# =============================================================================

cli_h2("Loading GBIF data")
gbif_files <- list.files(config$gbif_dir, pattern = "\\.csv\\.gz$", full.names = TRUE)
cli_alert_info("Found {length(gbif_files)} species files")

read_gbif <- function(file) {
  species_name <- gsub("\\.csv\\.gz$", "", basename(file))
  species_name <- gsub("-", " ", species_name)
  
  # Use zcat to read gzipped files (R.utils not available)
  dt <- fread(cmd = sprintf("zcat '%s'", file), showProgress = FALSE, sep = "\t")
  dt[, species_clean := species_name]
  
  # Keep essential columns if they exist
  essential <- c("gbifID", "decimalLatitude", "decimalLongitude", "year", 
                "coordinateUncertaintyInMeters", "countryCode", "species_clean",
                "basisOfRecord", "establishmentMeans")
  available <- intersect(essential, names(dt))
  
  if (length(available) == 0) {
    # Return minimal dataset with species name
    return(data.table(species_clean = species_name))
  }
  
  return(dt[, ..available])
}

# Load all files - try parallel first, fall back to sequential if it fails
cli_alert_info("Reading files...")

# Try parallel processing
data_list <- tryCatch({
  mclapply(gbif_files, read_gbif, mc.cores = config$cores)
}, error = function(e) {
  cli_alert_warning("Parallel processing failed, using sequential reading...")
  lapply(gbif_files, function(f) {
    tryCatch(read_gbif(f), error = function(e) {
      cli_alert_warning("Failed to read {basename(f)}: {e$message}")
      return(NULL)
    })
  })
})

# Remove NULLs and combine
data_list <- data_list[!sapply(data_list, is.null)]
all_data <- rbindlist(data_list, fill = TRUE)

n_raw <- nrow(all_data)
n_species <- uniqueN(all_data$species_clean)
cli_alert_success("Loaded {format(n_raw, big.mark=',')} occurrences from {n_species} species")

# =============================================================================
# Step 2: Basic Cleaning
# =============================================================================

cli_h2("Basic cleaning")

# Remove invalid coordinates
n_before <- nrow(all_data)
all_data <- all_data[!is.na(decimalLatitude) & !is.na(decimalLongitude)]
all_data <- all_data[decimalLatitude >= -90 & decimalLatitude <= 90]
all_data <- all_data[decimalLongitude >= -180 & decimalLongitude <= 180]
cli_alert_info("Removed {n_before - nrow(all_data)} invalid coordinates")

# Remove old records
if ("year" %in% names(all_data)) {
  n_before <- nrow(all_data)
  all_data <- all_data[is.na(year) | year >= config$min_year]
  cli_alert_info("Removed {n_before - nrow(all_data)} old records (pre-{config$min_year})")
}

# Remove high uncertainty
if ("coordinateUncertaintyInMeters" %in% names(all_data)) {
  n_before <- nrow(all_data)
  all_data <- all_data[is.na(coordinateUncertaintyInMeters) | 
                      coordinateUncertaintyInMeters <= config$max_coord_uncertainty]
  cli_alert_info("Removed {n_before - nrow(all_data)} high uncertainty records")
}

# Remove fossils and living specimens
if ("basisOfRecord" %in% names(all_data)) {
  n_before <- nrow(all_data)
  all_data <- all_data[!toupper(basisOfRecord) %in% c("FOSSIL_SPECIMEN", "LIVING_SPECIMEN")]
  cli_alert_info("Removed {n_before - nrow(all_data)} fossil/living specimens")
}

cli_alert_success("After basic cleaning: {format(nrow(all_data), big.mark=',')} records")

# =============================================================================
# Step 3: CoordinateCleaner Tests (WITHOUT SEA TEST)
# =============================================================================

cli_h2("Coordinate cleaning tests")
cli_alert_warning("Sea test skipped to avoid hanging")

# Prepare data for CoordinateCleaner
cc_data <- as.data.frame(all_data)
cc_data$decimallongitude <- cc_data$decimalLongitude
cc_data$decimallatitude <- cc_data$decimalLatitude

# Define tests to run (excluding seas and duplicates)
# Based on CoordinateCleaner documentation
# Not using duplicates test - multiple observations at same location are valid
# Not using seas test - causes hanging with large datasets
tests_to_run <- c(
  "capitals",      # Near capitals (default radius 10km, we use 20km)
  "centroids",     # Country/province centroids
  "equal",         # Equal lat/lon
  "gbif",          # GBIF headquarters
  "institutions",  # Museums, herbaria (default 1km, we use 2km)
  "zeros"          # 0,0 coordinates
  # "duplicates" excluded - preserves multiple observations per location
  # "seas" excluded - causes hanging
)

cli_alert_info("Running {length(tests_to_run)} coordinate tests...")

# Run CoordinateCleaner
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

# Get flagging summary
flags_summary <- cc_cleaned %>%
  dplyr::select(starts_with(".")) %>%
  dplyr::summarise(across(everything(), ~sum(!., na.rm = TRUE)))

cli_alert_info("Flagging summary:")
for (col in names(flags_summary)) {
  test_name <- gsub("^\\.", "", col)
  n_flagged <- flags_summary[[col]]
  if (n_flagged > 0) {
    pct <- round(100 * n_flagged / nrow(cc_cleaned), 1)
    cli_alert_warning("  {test_name}: {n_flagged} records ({pct}%)")
  }
}

# Standard practice: use .summary column (records passing ALL tests)
# This is the conservative approach recommended by CoordinateCleaner docs
cc_cleaned <- cc_cleaned[cc_cleaned$.summary, ]
all_data <- as.data.table(cc_cleaned)

cli_alert_success("Retained {format(nrow(all_data), big.mark=',')} clean records")
cli_alert_info("Removed {format(nrow(cc_data) - nrow(all_data), big.mark=',')} flagged records")
cli_alert_info("Using standard conservative cleaning (removed all flagged records)")
cli_alert_warning("Note: Duplicates NOT removed - preserving all observations")

# =============================================================================
# Step 4: Simple Statistical Outlier Removal
# =============================================================================

cli_h2("Statistical outlier removal")

remove_outliers <- function(dt) {
  if (nrow(dt) < 10) return(dt)  # Too few points
  
  # Use IQR method for outlier detection
  lat_q <- quantile(dt$decimalLatitude, c(config$outlier_quantile, 1 - config$outlier_quantile))
  lon_q <- quantile(dt$decimalLongitude, c(config$outlier_quantile, 1 - config$outlier_quantile))
  
  dt[decimalLatitude >= lat_q[1] & decimalLatitude <= lat_q[2] &
     decimalLongitude >= lon_q[1] & decimalLongitude <= lon_q[2]]
}

n_before <- nrow(all_data)
all_data <- rbindlist(lapply(split(all_data, by = "species_clean"), remove_outliers))
cli_alert_info("Removed {n_before - nrow(all_data)} statistical outliers")

# =============================================================================
# Step 5: Extract Bioclim Values
# =============================================================================

cli_h2("Bioclim extraction")

# Check if WorldClim data is available
bio_files <- list.files(config$worldclim_dir, pattern = "wc2.1_30s_bio_.*\\.tif$", 
                        full.names = TRUE)

if (length(bio_files) >= 19) {
  cli_alert_info("Loading WorldClim rasters...")
  
  # Load rasters in correct order
  bio_files <- bio_files[order(as.numeric(gsub(".*bio_(\\d+)\\.tif", "\\1", bio_files)))]
  bio_stack <- rast(bio_files)
  names(bio_stack) <- paste0("bio", 1:19)
  
  # Get unique coordinates
  unique_coords <- unique(all_data[, .(decimalLongitude, decimalLatitude)])
  cli_alert_info("Extracting for {format(nrow(unique_coords), big.mark=',')} unique coordinates")
  cli_alert_info("Coordinate reduction: {round(100 * (1 - nrow(unique_coords)/nrow(all_data)), 1)}%")
  
  # Extract bioclim values
  cli_alert_info("This will take 5-10 minutes...")
  coords_mat <- as.matrix(unique_coords)
  bio_values <- extract(bio_stack, coords_mat)
  
  # Combine with coordinates
  # Note: extract() with matrix doesn't return ID column in terra >= 1.7
  if ("ID" %in% names(bio_values)) {
    unique_coords_bio <- cbind(unique_coords, bio_values[, -1])  # Remove ID column if present
  } else {
    unique_coords_bio <- cbind(unique_coords, bio_values)  # No ID column to remove
  }
  
  # Remove NA values
  n_before <- nrow(unique_coords_bio)
  complete_rows <- complete.cases(unique_coords_bio)
  unique_coords_bio <- unique_coords_bio[complete_rows, ]
  
  if (n_before > nrow(unique_coords_bio)) {
    cli_alert_warning("Removed {n_before - nrow(unique_coords_bio)} coordinates outside WorldClim extent")
  }
  
  # Merge back to all occurrences
  all_data <- merge(all_data, unique_coords_bio, 
                   by = c("decimalLongitude", "decimalLatitude"), 
                   all.x = TRUE)
  
  cli_alert_success("Bioclim extraction complete")
  
} else {
  cli_alert_error("WorldClim data not found in {config$worldclim_dir}")
  cli_alert_info("Run: make predownload")
  
  # Add empty bioclim columns
  for (i in 1:19) {
    all_data[, paste0("bio", i) := NA_real_]
  }
}

# =============================================================================
# Step 6: Save Results
# =============================================================================

cli_h2("Saving results")

# Save complete dataset
output_file <- file.path(config$output_dir, "all_occurrences_cleaned_noDups.csv")
fwrite(all_data, output_file)
cli_alert_success("Saved complete dataset: {output_file}")

# Save per-species files
species_list <- unique(all_data$species_clean)
n_saved <- 0
n_too_few <- 0
species_occurrence_counts <- list()

cli_progress_bar("Saving species files", total = length(species_list))

for (sp in species_list) {
  cli_progress_update()
  sp_data <- all_data[species_clean == sp]
  n_occ <- nrow(sp_data)
  species_occurrence_counts[[sp]] <- n_occ
  
  # Save ALL species files, regardless of occurrence count
  sp_file <- gsub(" ", "_", tolower(sp))
  fwrite(sp_data, 
         file.path(config$output_dir, "species_bioclim", 
                  paste0(sp_file, "_bioclim.csv")))
  n_saved <- n_saved + 1
  
  # Track species with few occurrences for reporting
  if (n_occ < config$min_occurrences) {
    n_too_few <- n_too_few + 1
  }
}

cli_progress_done()
cli_alert_success("Saved {n_saved} species files")
if (n_too_few > 0) {
  cli_alert_warning("{n_too_few} species have fewer than {config$min_occurrences} occurrences")
}

# Create summary statistics
cli_alert_info("Creating summary statistics...")

species_summaries <- lapply(species_list, function(sp) {
  sp_data <- all_data[species_clean == sp]
  bio_cols <- paste0("bio", 1:19)
  
  # Check which bio columns actually exist in the data
  existing_bio_cols <- bio_cols[bio_cols %in% names(sp_data)]
  
  # Create summary for ALL species, not just those with min_occurrences
  summary_stats <- data.frame(
    species = sp,
    n_occurrences = nrow(sp_data),
    has_sufficient_data = nrow(sp_data) >= config$min_occurrences,
    stringsAsFactors = FALSE
  )
  
  # Only calculate bioclim stats if columns exist
  if (length(existing_bio_cols) > 0 && nrow(sp_data) > 0) {
    summary_stats$n_with_bioclim <- sum(complete.cases(sp_data[, ..existing_bio_cols]))
    
    # Add mean values for each existing bioclim variable if there's data
    for (bio_var in existing_bio_cols) {
      values <- sp_data[[bio_var]]
      values <- values[!is.na(values)]
      if (length(values) > 0) {
        summary_stats[[paste0(bio_var, "_mean")]] <- mean(values)
        summary_stats[[paste0(bio_var, "_sd")]] <- sd(values)
      }
    }
  } else {
    # No bioclim columns found or no data
    summary_stats$n_with_bioclim <- 0
  }
  return(summary_stats)
})

all_summaries <- rbindlist(species_summaries[!sapply(species_summaries, is.null)], fill = TRUE)
fwrite(all_summaries, file.path(config$output_dir, "summary_stats", "species_bioclim_summary.csv"))

# Save cleaning report
quality_report <- list(
  date = Sys.Date(),
  pipeline_version = "NoSea_v1",
  parameters = config,
  input = list(
    n_raw_occurrences = n_raw,
    n_species = n_species
  ),
  cleaning = list(
    n_after_cleaning = nrow(all_data),
    retention_rate = round(100 * nrow(all_data) / n_raw, 1),
    flags_summary = as.list(flags_summary),
    sea_test = "SKIPPED to avoid hanging"
  ),
  output = list(
    n_final_occurrences = nrow(all_data),
    n_unique_coordinates = nrow(unique_coords_bio),
    n_species_saved = n_saved
  )
)

jsonlite::write_json(quality_report, 
                     file.path(config$output_dir, "quality_reports", "cleaning_report_noSea.json"),
                     pretty = TRUE)

# =============================================================================
# Final Summary
# =============================================================================

cli_rule(left = "Pipeline Complete!")

cli_alert_success("Summary:")
cli_alert_info("  Input: {format(n_raw, big.mark=',')} raw occurrences")
cli_alert_info("  Output: {format(nrow(all_data), big.mark=',')} clean occurrences")
cli_alert_info("  Retention: {round(100 * nrow(all_data) / n_raw, 1)}%")
cli_alert_info("  Species: {n_saved} total ({n_saved - n_too_few} with {config$min_occurrences}+ occurrences)")
cli_alert_info("  Unique coordinates: {format(nrow(unique_coords_bio), big.mark=',')}")

cli_alert_success("Output directory: {config$output_dir}")
cli_alert_warning("Note: Sea coordinate test was skipped")

# Print sample results
if (nrow(all_summaries) > 0) {
  cli_h3("Sample results (first 5 species)")
  # Select columns that actually exist
  display_cols <- c("species", "n_occurrences")
  if ("n_with_bioclim" %in% names(all_summaries)) {
    display_cols <- c(display_cols, "n_with_bioclim")
  }
  if ("bio1_mean" %in% names(all_summaries)) {
    display_cols <- c(display_cols, "bio1_mean")
  }
  if ("bio12_mean" %in% names(all_summaries)) {
    display_cols <- c(display_cols, "bio12_mean")
  }
  print(head(all_summaries[, ..display_cols], 5))
}
