#!/usr/bin/env Rscript
# extract_soilgrids_vrt_global.R - Extract soil data for 5M points WITHOUT downloading
# Uses VRT virtual rasters for efficient global access

library(terra)
library(tidyverse)
library(data.table)
library(parallel)
library(future)
library(furrr)  # For parallel processing

cat("===========================================\n")
cat("SoilGrids Global Extraction via VRT\n")
cat("NO DOWNLOAD REQUIRED!\n")
cat("===========================================\n\n")

# ============================================
# CONFIGURATION
# ============================================

# Configure terra for optimal performance
terraOptions(
  memfrac = 0.8,     # Use 80% of RAM
  tempdir = "/tmp",  # Fast temp directory
  verbose = FALSE
)

# Set GDAL options for better vsicurl performance
Sys.setenv(
  CPL_VSIL_CURL_CHUNK_SIZE = "524288",     # 512KB chunks (larger than default)
  CPL_VSIL_CURL_CACHE_SIZE = "268435456",  # 256MB cache (much larger)
  GDAL_HTTP_MAX_RETRY = "5",               # More retries for stability
  GDAL_HTTP_RETRY_DELAY = "2"              # Wait between retries
)

# SoilGrids WebDAV base URL
SG_URL <- "/vsicurl?max_retry=3&retry_delay=1&list_dir=no&url=https://files.isric.org/soilgrids/latest/data/"

# Soil properties to extract (choose based on EIVE needs)
SOIL_PROPERTIES <- list(
  phh2o = list(name = "pH in H2O", factor = 0.1),        # Divide by 10
  soc = list(name = "Soil organic carbon", factor = 0.1), # g/kg, divide by 10
  clay = list(name = "Clay content", factor = 0.1),      # %, divide by 10
  sand = list(name = "Sand content", factor = 0.1),      # %, divide by 10
  cec = list(name = "CEC", factor = 0.1),                # cmol/kg, divide by 10
  nitrogen = list(name = "Total nitrogen", factor = 0.01), # g/kg, divide by 100
  bdod = list(name = "Bulk density", factor = 0.01)      # kg/dm3, divide by 100
)

# Depths to extract
DEPTHS <- c("0-5cm", "5-15cm", "15-30cm")

# ============================================
# STEP 1: CREATE VRT CONNECTIONS (NO DOWNLOAD!)
# ============================================

cat("Creating VRT connections to global data...\n")

# Build list of VRT URLs
vrt_list <- list()
for(prop in names(SOIL_PROPERTIES)) {
  for(depth in DEPTHS) {
    vrt_name <- paste0(prop, "_", gsub("-", "_", depth))
    vrt_url <- paste0(SG_URL, prop, "/", prop, "_", depth, "_mean.vrt")
    vrt_list[[vrt_name]] <- list(
      url = vrt_url,
      factor = SOIL_PROPERTIES[[prop]]$factor
    )
    cat(sprintf("  Connected: %s\n", vrt_name))
  }
}

cat(sprintf("\nTotal VRT connections: %d (NO data downloaded yet!)\n", length(vrt_list)))

# ============================================
# STEP 2: LOAD AND PREPARE OCCURRENCE DATA
# ============================================

cat("\nLoading occurrence data...\n")

# Load your occurrences
occurrence_file <- "/home/olier/ellenberg/data/bioclim_extractions_cleaned/occurrences_with_bioclim.csv"

if (file.exists(occurrence_file)) {
  # For testing, use subset; for production, remove nrows limit
  occurrences <- fread(occurrence_file, nrows = 10000)  # TEST WITH 10K FIRST!
  
  cat(sprintf("  Loaded %d occurrences for %d species\n", 
              nrow(occurrences), 
              length(unique(occurrences$species))))
} else {
  stop("Occurrence file not found!")
}

# ============================================
# STEP 3: SMART EXTRACTION STRATEGY
# ============================================

cat("\n--- Extraction Strategy ---\n")

# Group occurrences by spatial proximity for efficient tile access
# This minimizes tile switching and HTTP requests

# Create spatial bins (1-degree grid cells)
occurrences <- occurrences %>%
  mutate(
    lon_bin = floor(decimalLongitude),
    lat_bin = floor(decimalLatitude),
    spatial_group = paste(lon_bin, lat_bin, sep = "_")
  )

spatial_groups <- occurrences %>%
  group_by(spatial_group) %>%
  summarise(
    n_points = n(),
    min_lon = min(decimalLongitude),
    max_lon = max(decimalLongitude),
    min_lat = min(decimalLatitude),
    max_lat = max(decimalLatitude)
  ) %>%
  arrange(desc(n_points))  # Process densest areas first

cat(sprintf("  Spatial groups: %d\n", nrow(spatial_groups)))
cat(sprintf("  Points per group: min=%d, max=%d, mean=%.1f\n",
            min(spatial_groups$n_points),
            max(spatial_groups$n_points),
            mean(spatial_groups$n_points)))

# ============================================
# STEP 4: EXTRACT BY SPATIAL GROUP
# ============================================

cat("\nExtracting soil values by spatial group...\n")
cat("(This approach minimizes tile fetching)\n\n")

# Function to extract for one spatial group
extract_spatial_group <- function(group_id, vrt_info, occurrences_subset) {
  
  # Convert to SpatVector
  points <- vect(occurrences_subset,
                 geom = c("decimalLongitude", "decimalLatitude"),
                 crs = "EPSG:4326")
  
  # Extract from VRT (only fetches necessary tiles!)
  raster <- rast(vrt_info$url)
  
  # OPTION 1: Direct extraction (let GDAL handle projection)
  values <- extract(raster, points, ID = FALSE)[, 2]  # Column 2 has values
  
  # OPTION 2: If projection issues, transform points first
  # points_transformed <- project(points, crs(raster))
  # values <- extract(raster, points_transformed, ID = FALSE)[, 2]
  
  # Apply scaling factor
  values <- values * vrt_info$factor
  
  return(values)
}

# Process first VRT as example
test_vrt <- vrt_list[[1]]
results <- occurrences

# Extract for each property-depth combination
for(vrt_name in names(vrt_list)) {
  cat(sprintf("\nExtracting %s...\n", vrt_name))
  
  vrt_info <- vrt_list[[vrt_name]]
  all_values <- numeric(nrow(occurrences))
  
  start_time <- Sys.time()
  
  # Process by spatial group
  for(i in 1:nrow(spatial_groups)) {
    group <- spatial_groups[i, ]
    group_indices <- which(occurrences$spatial_group == group$spatial_group)
    group_occurrences <- occurrences[group_indices, ]
    
    # Extract for this group
    group_values <- extract_spatial_group(
      group$spatial_group,
      vrt_info,
      group_occurrences
    )
    
    all_values[group_indices] <- group_values
    
    # Progress
    if(i %% 10 == 0) {
      elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
      rate <- i / elapsed
      eta <- (nrow(spatial_groups) - i) / rate
      
      cat(sprintf("  Group %d/%d (%.1f%%), ETA: %.1f min\n",
                  i, nrow(spatial_groups),
                  100 * i / nrow(spatial_groups),
                  eta / 60))
    }
  }
  
  # Store results
  results[[vrt_name]] <- all_values
  
  total_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  cat(sprintf("  Completed in %.1f seconds (%.1f points/sec)\n",
              total_time, nrow(occurrences) / total_time))
  
  # IMPORTANT: For production with 5M points, process only what you need
  # break  # Uncomment to test with just one property
}

# ============================================
# STEP 5: PARALLEL EXTRACTION (ADVANCED)
# ============================================

cat("\n--- Parallel Extraction Option ---\n")
cat("For production with 5M points, use parallel processing:\n\n")

# Set up parallel backend
plan(multisession, workers = 4)  # Adjust based on your CPU

# Function for parallel extraction
extract_parallel <- function(vrt_url, points_df) {
  raster <- rast(vrt_url)
  points <- vect(points_df, 
                 geom = c("decimalLongitude", "decimalLatitude"),
                 crs = "EPSG:4326")
  values <- extract(raster, points, ID = FALSE)[, 2]
  return(values)
}

# Example: Extract multiple properties in parallel
if (FALSE) {  # Set to TRUE to test parallel extraction
  
  cat("Testing parallel extraction...\n")
  
  # Select subset of VRTs for parallel test
  test_vrts <- head(vrt_list, 3)
  
  # Use furrr for parallel map
  parallel_results <- future_map(test_vrts, function(vrt_info) {
    extract_parallel(vrt_info$url, head(occurrences, 1000))
  })
  
  cat("Parallel extraction complete!\n")
}

# ============================================
# STEP 6: AGGREGATE TO SPECIES LEVEL
# ============================================

cat("\n--- Aggregating to Species Level ---\n")

# Calculate species-level summaries
species_soil <- results %>%
  group_by(species) %>%
  summarise(
    n_occurrences = n(),
    across(starts_with("phh2o") | starts_with("soc") | 
           starts_with("clay") | starts_with("sand"),
           list(
             mean = ~mean(.x, na.rm = TRUE),
             sd = ~sd(.x, na.rm = TRUE),
             q25 = ~quantile(.x, 0.25, na.rm = TRUE),
             q75 = ~quantile(.x, 0.75, na.rm = TRUE)
           ),
           .names = "{.col}_{.fn}")
  ) %>%
  filter(n_occurrences >= 30)

cat(sprintf("  Species with ≥30 occurrences: %d\n", nrow(species_soil)))

# ============================================
# STEP 7: SAVE RESULTS
# ============================================

cat("\nSaving results...\n")

output_dir <- "/home/olier/ellenberg/data/soil_extractions"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# Save occurrence-level data
fwrite(results, 
       file.path(output_dir, "occurrences_with_soil_vrt.csv"))

# Save species summaries
write.csv(species_soil,
          file.path(output_dir, "species_soil_summary_vrt.csv"),
          row.names = FALSE)

cat(sprintf("  Saved to: %s\n", output_dir))

# ============================================
# PERFORMANCE SUMMARY
# ============================================

cat("\n===========================================\n")
cat("EXTRACTION COMPLETE!\n")
cat("===========================================\n")

cat("\nKey Advantages of VRT Approach:\n")
cat("  ✓ NO download required (0 GB storage)\n")
cat("  ✓ Access entire global dataset\n")
cat("  ✓ Only fetches tiles you need\n")
cat("  ✓ Automatic caching of recent tiles\n")
cat("  ✓ Works with any global point distribution\n")

cat("\nPerformance Tips for 5M Points:\n")
cat("  1. Process by spatial groups (implemented above)\n")
cat("  2. Use parallel extraction for different properties\n")
cat("  3. Increase GDAL cache size for better performance\n")
cat("  4. Consider 1km resolution VRTs for faster access\n")
cat("  5. Process species separately if spatially clustered\n")

# Estimate for full dataset
points_per_sec <- nrow(occurrences) / 60  # Rough estimate
cat(sprintf("\nProjected time for 5M points:\n"))
cat(sprintf("  Single property: %.1f hours\n", 5000000 / points_per_sec / 3600))
cat(sprintf("  All properties (7×3): %.1f hours\n", 5000000 * 21 / points_per_sec / 3600))
cat(sprintf("  With 4-core parallel: %.1f hours\n", 5000000 * 21 / points_per_sec / 3600 / 4))

cat("\n===========================================\n")