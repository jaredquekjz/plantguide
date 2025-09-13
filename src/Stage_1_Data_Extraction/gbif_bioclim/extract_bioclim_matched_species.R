#!/usr/bin/env Rscript

# Extract bioclim data for all 1,051 matched trait-GBIF species
# This script replaces the outdated extraction that only covered 830 species

suppressPackageStartupMessages({
  library(data.table)
  library(tidyverse)
  library(jsonlite)
  library(terra)
  library(CoordinateCleaner)
  library(parallel)
})

cat("=== Bioclim Extraction for Matched Species ===\n\n")

# Configuration
config <- list(
  matches_file = "/home/olier/ellenberg/artifacts/gbif_complete_trait_matches_wfo.json",
  gbif_dir = "/home/olier/plantsdatabase/data/Stage_4/gbif_occurrences_complete",
  worldclim_dir = "/home/olier/ellenberg/data/worldclim/bio",
  output_dir = "/home/olier/ellenberg/data/bioclim_extractions_matched",
  n_cores = 8,
  min_occurrences = 3,  # Keep consistent with previous threshold
  batch_size = 100
)

# Create output directories
dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(config$output_dir, "species_data"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(config$output_dir, "summary_stats"), recursive = TRUE, showWarnings = FALSE)

# Load matched species
cat("Loading matched species list...\n")
matches <- fromJSON(config$matches_file)
matched_species <- matches$matched_species

cat(sprintf("  Found %d matched species\n", nrow(matched_species)))

# Load WorldClim layers (bio1-bio19)
cat("\nLoading WorldClim layers...\n")
bioclim_files <- list.files(config$worldclim_dir, 
                            pattern = "wc2\\.1_30s_bio_[0-9]+\\.tif$",
                            full.names = TRUE)
bioclim_raster <- rast(bioclim_files)
names(bioclim_raster) <- paste0("bio", 1:19)

# Function to clean GBIF occurrences
clean_gbif_data <- function(df, species_name) {
  # Basic cleaning
  df_clean <- df %>%
    filter(!is.na(decimalLatitude), !is.na(decimalLongitude)) %>%
    filter(decimalLatitude != 0 | decimalLongitude != 0) %>%
    filter(abs(decimalLatitude) <= 90, abs(decimalLongitude) <= 180)
  
  if (nrow(df_clean) == 0) return(NULL)
  
  # CoordinateCleaner checks
  df_clean <- df_clean %>%
    cc_val(lat = "decimalLatitude", lon = "decimalLongitude", verbose = FALSE) %>%
    cc_equ(lat = "decimalLatitude", lon = "decimalLongitude", verbose = FALSE) %>%
    cc_cap(lat = "decimalLatitude", lon = "decimalLongitude", verbose = FALSE) %>%
    cc_cen(lat = "decimalLatitude", lon = "decimalLongitude", verbose = FALSE) %>%
    cc_gbif(lat = "decimalLatitude", lon = "decimalLongitude", verbose = FALSE) %>%
    cc_inst(lat = "decimalLatitude", lon = "decimalLongitude", verbose = FALSE) %>%
    cc_zero(lat = "decimalLatitude", lon = "decimalLongitude", verbose = FALSE)
  
  # Remove duplicates
  df_clean <- df_clean %>%
    distinct(decimalLatitude, decimalLongitude, .keep_all = TRUE)
  
  return(df_clean)
}

# Function to extract bioclim for one species
process_species <- function(species_row, config, bioclim_raster) {
  tryCatch({
    species_name <- species_row$trait_name
    gbif_file <- species_row$gbif_file
    
    # Read GBIF data
    if (!file.exists(gbif_file)) {
      return(list(
        species = species_name,
        status = "file_not_found",
        n_occurrences = 0
      ))
    }
    
    # Read compressed GBIF file
    df <- fread(cmd = paste("zcat", gbif_file), 
                select = c("decimalLatitude", "decimalLongitude"),
                showProgress = FALSE)
    
    if (nrow(df) == 0) {
      return(list(
        species = species_name,
        status = "no_data",
        n_occurrences = 0
      ))
    }
    
    # Clean data
    df_clean <- clean_gbif_data(df, species_name)
    
    if (is.null(df_clean) || nrow(df_clean) < config$min_occurrences) {
      return(list(
        species = species_name,
        status = "insufficient_data",
        n_occurrences = ifelse(is.null(df_clean), 0, nrow(df_clean))
      ))
    }
    
    # Extract bioclim values
    coords <- df_clean[, c("decimalLongitude", "decimalLatitude")]
    bio_values <- terra::extract(bioclim_raster, coords, ID = FALSE)
    
    # Remove rows with NA values
    bio_values <- na.omit(bio_values)
    
    if (nrow(bio_values) < config$min_occurrences) {
      return(list(
        species = species_name,
        status = "insufficient_extracted",
        n_occurrences = nrow(df_clean),
        n_extracted = nrow(bio_values)
      ))
    }
    
    # Calculate summary statistics
    bio_summary <- data.frame(
      species = species_name,
      n_occurrences = nrow(bio_values),
      n_original = nrow(df),
      n_cleaned = nrow(df_clean),
      has_sufficient_data = TRUE
    )
    
    # Add mean values for each bioclim variable
    for (var in names(bio_values)) {
      bio_summary[[paste0(var, "_mean")]] <- mean(bio_values[[var]], na.rm = TRUE)
      bio_summary[[paste0(var, "_sd")]] <- sd(bio_values[[var]], na.rm = TRUE)
      bio_summary[[paste0(var, "_min")]] <- min(bio_values[[var]], na.rm = TRUE)
      bio_summary[[paste0(var, "_max")]] <- max(bio_values[[var]], na.rm = TRUE)
    }
    
    # Save species-level data
    species_file <- file.path(config$output_dir, "species_data", 
                             paste0(gsub(" ", "_", species_name), "_bioclim.csv"))
    fwrite(bio_values, species_file)
    
    return(bio_summary)
    
  }, error = function(e) {
    return(list(
      species = species_row$trait_name,
      status = "error",
      error_message = as.character(e),
      n_occurrences = 0
    ))
  })
}

# Process all species
cat("\n=== Processing Species ===\n")

# Process in batches for better progress tracking
n_batches <- ceiling(nrow(matched_species) / config$batch_size)
all_summaries <- list()

for (batch_idx in 1:n_batches) {
  start_idx <- (batch_idx - 1) * config$batch_size + 1
  end_idx <- min(batch_idx * config$batch_size, nrow(matched_species))
  
  batch_species <- matched_species[start_idx:end_idx, ]
  
  cat(sprintf("\nBatch %d/%d (species %d-%d)...\n", 
              batch_idx, n_batches, start_idx, end_idx))
  
  # Process batch in parallel
  batch_results <- mclapply(
    1:nrow(batch_species),
    function(i) process_species(batch_species[i, ], config, bioclim_raster),
    mc.cores = config$n_cores
  )
  
  all_summaries <- c(all_summaries, batch_results)
  
  # Show progress
  successful <- sum(sapply(batch_results, function(x) 
    !is.null(x$has_sufficient_data) && x$has_sufficient_data))
  cat(sprintf("  Batch complete: %d species with sufficient data\n", successful))
}

# Combine all summaries
cat("\n=== Combining Results ===\n")

# Filter out NULL results and combine
valid_summaries <- all_summaries[!sapply(all_summaries, is.null)]
summary_df <- rbindlist(valid_summaries, fill = TRUE)

# Add has_sufficient_data flag for entries that don't have it
if (!"has_sufficient_data" %in% names(summary_df)) {
  summary_df$has_sufficient_data <- FALSE
}
summary_df[is.na(has_sufficient_data), has_sufficient_data := FALSE]

# Save summary statistics
output_file <- file.path(config$output_dir, "summary_stats", "species_bioclim_summary.csv")
fwrite(summary_df, output_file)

# Generate report
cat("\n=== Extraction Summary ===\n")
cat(sprintf("Total species processed: %d\n", nrow(summary_df)))
cat(sprintf("Species with sufficient data: %d (%.1f%%)\n", 
            sum(summary_df$has_sufficient_data),
            100 * sum(summary_df$has_sufficient_data) / nrow(summary_df)))

# Status breakdown
if ("status" %in% names(summary_df)) {
  cat("\nStatus breakdown:\n")
  status_counts <- table(summary_df$status, useNA = "ifany")
  for (status in names(status_counts)) {
    cat(sprintf("  %s: %d\n", 
                ifelse(is.na(status), "successful", status), 
                status_counts[status]))
  }
}

# Occurrence statistics for successful extractions
successful_df <- summary_df[has_sufficient_data == TRUE]
if (nrow(successful_df) > 0) {
  cat("\nOccurrence statistics (successful extractions):\n")
  cat(sprintf("  Min: %d\n", min(successful_df$n_occurrences)))
  cat(sprintf("  Median: %d\n", median(successful_df$n_occurrences)))
  cat(sprintf("  Mean: %.1f\n", mean(successful_df$n_occurrences)))
  cat(sprintf("  Max: %d\n", max(successful_df$n_occurrences)))
  
  cat("\nOccurrence thresholds:\n")
  for (threshold in c(10, 30, 100, 500, 1000)) {
    n_above <- sum(successful_df$n_occurrences >= threshold)
    cat(sprintf("  ≥%d occurrences: %d species (%.1f%%)\n",
                threshold, n_above,
                100 * n_above / nrow(successful_df)))
  }
}

# Save extraction report
report <- list(
  timestamp = Sys.time(),
  config = config,
  summary = list(
    total_matched = nrow(matched_species),
    total_processed = nrow(summary_df),
    successful = sum(summary_df$has_sufficient_data),
    coverage_pct = 100 * sum(summary_df$has_sufficient_data) / nrow(matched_species)
  ),
  occurrence_stats = if(nrow(successful_df) > 0) {
    list(
      min = min(successful_df$n_occurrences),
      median = median(successful_df$n_occurrences),
      mean = mean(successful_df$n_occurrences),
      max = max(successful_df$n_occurrences)
    )
  } else NULL
)

report_file <- file.path(config$output_dir, "extraction_report.json")
write_json(report, report_file, pretty = TRUE, auto_unbox = TRUE)

cat(sprintf("\n✅ Extraction complete!\n"))
cat(sprintf("Results saved to: %s\n", config$output_dir))
cat(sprintf("Summary file: %s\n", output_file))