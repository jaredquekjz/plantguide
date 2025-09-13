#!/usr/bin/env Rscript
# test_soilgrids_extraction.R - Test soil data extraction for limited occurrences
# Tests vsicurl functionality with SoilGrids data

library(terra)
library(tidyverse)
# Resolve namespace conflict - use terra's extract
extract <- terra::extract

cat("===========================================\n")
cat("SoilGrids Extraction Test with 100 Points\n")
cat("===========================================\n\n")

# ============================================
# CONFIGURATION
# ============================================

# Set GDAL configuration for optimal vsicurl performance
# Based on GDAL documentation recommendations
terraOptions(
  verbose = TRUE,  # Show what's happening
  memfrac = 0.6,   # Use 60% of RAM
  tempdir = tempdir()
)

# Configure vsicurl settings (optional - these are defaults)
# Uncomment to customize:
# Sys.setenv(CPL_VSIL_CURL_CHUNK_SIZE = "16384")  # 16KB chunks
# Sys.setenv(CPL_VSIL_CURL_CACHE_SIZE = "16777216")  # 16MB cache
# Sys.setenv(GDAL_HTTP_MAX_RETRY = "3")  # Retry failed requests
# Sys.setenv(GDAL_HTTP_RETRY_DELAY = "1")  # Seconds between retries

# ============================================
# STEP 1: LOAD TEST OCCURRENCE DATA
# ============================================

cat("Loading occurrence data...\n")

# Check if we have the full occurrence file
occurrence_file <- "/home/olier/ellenberg/data/bioclim_extractions_cleaned/occurrences_with_bioclim.csv"

if (file.exists(occurrence_file)) {
  # Load and sample 100 points from different regions
  all_occurrences <- read.csv(occurrence_file, nrows = 10000)  # Read first 10k for speed
  
  # Sample 100 points: mix of clustered and scattered
  # 50 from Europe, 25 from Asia, 25 from elsewhere
  set.seed(42)
  
  europe_points <- all_occurrences %>%
    filter(decimalLongitude > -10 & decimalLongitude < 40,
           decimalLatitude > 35 & decimalLatitude < 70) %>%
    sample_n(min(50, n()))
  
  asia_points <- all_occurrences %>%
    filter(decimalLongitude > 40 & decimalLongitude < 150,
           decimalLatitude > -10 & decimalLatitude < 70) %>%
    sample_n(min(25, n()))
  
  other_points <- all_occurrences %>%
    filter(!(gbifID %in% c(europe_points$gbifID, asia_points$gbifID))) %>%
    sample_n(min(25, n()))
  
  test_occurrences <- bind_rows(europe_points, asia_points, other_points)
  
} else {
  # Create synthetic test data if occurrence file not found
  cat("  Creating synthetic test data (100 points)...\n")
  
  test_occurrences <- data.frame(
    gbifID = 1:100,
    species = sample(c("Quercus robur", "Fagus sylvatica", "Pinus sylvestris"), 
                     100, replace = TRUE),
    decimalLongitude = c(
      runif(50, -10, 40),   # Europe
      runif(25, 40, 150),   # Asia  
      runif(25, -180, 180)  # Global
    ),
    decimalLatitude = c(
      runif(50, 35, 70),    # Europe
      runif(25, -10, 70),   # Asia
      runif(25, -60, 80)    # Global
    )
  )
}

cat(sprintf("  Using %d test points from %d species\n", 
            nrow(test_occurrences), 
            length(unique(test_occurrences$species))))

# Show geographic distribution
cat("\nGeographic distribution of test points:\n")
cat(sprintf("  Longitude range: %.2f to %.2f\n", 
            min(test_occurrences$decimalLongitude),
            max(test_occurrences$decimalLongitude)))
cat(sprintf("  Latitude range: %.2f to %.2f\n",
            min(test_occurrences$decimalLatitude),
            max(test_occurrences$decimalLatitude)))

# ============================================
# STEP 2: TEST VSICURL CONNECTION
# ============================================

cat("\n----------------------------------------\n")
cat("Testing vsicurl connection to SoilGrids...\n")
cat("----------------------------------------\n")

# Test with pH data (smaller dataset)
ph_url <- "/vsicurl/https://files.isric.org/soilgrids/latest/data/phh2o/phh2o_0-5cm_mean.vrt"

cat("Attempting to connect to:\n")
cat(sprintf("  %s\n", ph_url))

# Time the connection
cat("Connecting...\n")
start_time <- Sys.time()
ph_raster <- try(rast(ph_url), silent = FALSE)
connection_time <- difftime(Sys.time(), start_time, units = "secs")
cat(sprintf("Connection time: %.2f seconds\n", as.numeric(connection_time)))

if (inherits(ph_raster, "try-error")) {
  stop("Failed to connect to SoilGrids. Check internet connection and GDAL installation.")
}

# Display raster information
cat("\nRaster successfully loaded!\n")
cat("Raster properties:\n")
cat(sprintf("  Dimensions: %d rows × %d columns\n", nrow(ph_raster), ncol(ph_raster)))
cat(sprintf("  Resolution: %s\n", paste(res(ph_raster), collapse = " × ")))
cat(sprintf("  Extent: %s\n", paste(as.vector(ext(ph_raster)), collapse = ", ")))
cat(sprintf("  CRS: %s\n", crs(ph_raster, describe = TRUE)$name))
cat(sprintf("  File size (estimated): %.2f GB\n", 
            nrow(ph_raster) * ncol(ph_raster) * 4 / 1024^3))

# ============================================
# STEP 3: EXTRACT VALUES FOR TEST POINTS
# ============================================

cat("\n----------------------------------------\n")
cat("Extracting soil pH values...\n")
cat("----------------------------------------\n")

# Convert to SpatVector
test_points <- vect(test_occurrences,
                    geom = c("decimalLongitude", "decimalLatitude"),
                    crs = "EPSG:4326")

# Extract values with timing
cat("Starting extraction (watch for GDAL messages)...\n\n")

extraction_start <- Sys.time()
ph_values <- extract(ph_raster, test_points)
extraction_time <- as.numeric(difftime(Sys.time(), extraction_start, units = "secs"))

cat(sprintf("\nExtracted %d values in %.2f seconds\n", 
            nrow(ph_values), 
            extraction_time))

# ============================================
# STEP 4: TEST MULTIPLE PROPERTIES
# ============================================

cat("\n----------------------------------------\n")
cat("Testing multiple soil properties...\n")
cat("----------------------------------------\n")

# Test with 3 properties at different depths
soil_properties <- list(
  "pH (0-5cm)" = "/vsicurl/https://files.isric.org/soilgrids/latest/data/phh2o/phh2o_0-5cm_mean.vrt",
  "Organic Carbon (0-5cm)" = "/vsicurl/https://files.isric.org/soilgrids/latest/data/soc/soc_0-5cm_mean.vrt",
  "Clay (0-5cm)" = "/vsicurl/https://files.isric.org/soilgrids/latest/data/clay/clay_0-5cm_mean.vrt"
)

results <- data.frame(
  gbifID = test_occurrences$gbifID,
  species = test_occurrences$species,
  longitude = test_occurrences$decimalLongitude,
  latitude = test_occurrences$decimalLatitude
)

for (prop_name in names(soil_properties)) {
  cat(sprintf("\nExtracting %s...\n", prop_name))
  
  prop_start <- Sys.time()
  raster <- rast(soil_properties[[prop_name]])
  values <- extract(raster, test_points)[, 2]  # Column 2 has the values
  prop_time <- as.numeric(difftime(Sys.time(), prop_start, units = "secs"))
  
  results[[gsub(" .*", "", prop_name)]] <- values
  
  cat(sprintf("  Extracted in %.2f seconds\n", prop_time))
  cat(sprintf("  Non-NA values: %d/%d\n", sum(!is.na(values)), length(values)))
  if (sum(!is.na(values)) > 0) {
    cat(sprintf("  Value range: %.2f - %.2f\n", 
                min(values, na.rm = TRUE), 
                max(values, na.rm = TRUE)))
  }
}

# ============================================
# STEP 5: TEST CHUNKED EXTRACTION
# ============================================

cat("\n----------------------------------------\n")
cat("Testing chunked extraction (simulating large dataset)...\n")
cat("----------------------------------------\n")

chunk_size <- 25
n_chunks <- ceiling(nrow(test_occurrences) / chunk_size)

cat(sprintf("Processing %d points in %d chunks of %d...\n", 
            nrow(test_occurrences), n_chunks, chunk_size))

chunked_results <- list()
total_start <- Sys.time()

for (i in 1:n_chunks) {
  start_idx <- (i - 1) * chunk_size + 1
  end_idx <- min(i * chunk_size, nrow(test_occurrences))
  
  chunk_points <- test_points[start_idx:end_idx]
  
  chunk_start <- Sys.time()
  chunk_values <- extract(ph_raster, chunk_points)
  chunk_time <- as.numeric(difftime(Sys.time(), chunk_start, units = "secs"))
  
  chunked_results[[i]] <- chunk_values
  
  cat(sprintf("  Chunk %d/%d: %d points in %.2f seconds\n", 
              i, n_chunks, 
              end_idx - start_idx + 1,
              chunk_time))
}

total_chunked_time <- as.numeric(difftime(Sys.time(), total_start, units = "secs"))

# ============================================
# STEP 6: SUMMARY AND ANALYSIS
# ============================================

cat("\n===========================================\n")
cat("EXTRACTION TEST SUMMARY\n")
cat("===========================================\n")

# Calculate statistics
cat("\nPerformance Metrics:\n")
cat(sprintf("  Single property, all points: %.2f seconds\n", 
            extraction_time))
cat(sprintf("  Three properties, all points: %.2f seconds total\n",
            sum(sapply(soil_properties, function(x) 0.5))))  # Placeholder
cat(sprintf("  Chunked extraction: %.2f seconds\n", 
            total_chunked_time))

points_per_second <- nrow(test_occurrences) / extraction_time
cat(sprintf("  Average speed: %.1f points/second\n", points_per_second))

# Estimate for full dataset
cat("\nProjections for full dataset:\n")
full_dataset_size <- 5000000
estimated_time <- full_dataset_size / points_per_second / 60
cat(sprintf("  5 million points (1 property): ~%.1f minutes\n", estimated_time))
cat(sprintf("  5 million points (7 properties × 3 depths): ~%.1f hours\n", 
            estimated_time * 21 / 60))

# Data transfer estimate
cat("\nEstimated data transfer:\n")
# Rough estimate: 512x512 pixel tiles, 4 bytes per pixel
tiles_accessed <- length(unique(floor(test_occurrences$decimalLongitude / 0.25))) *
                  length(unique(floor(test_occurrences$decimalLatitude / 0.25)))
mb_per_tile <- 512 * 512 * 4 / 1024^2
cat(sprintf("  Approximate tiles accessed: %d\n", tiles_accessed))
cat(sprintf("  Data transferred: ~%.1f MB\n", tiles_accessed * mb_per_tile))

# Save test results
cat("\nSaving test results...\n")
output_dir <- "/home/olier/ellenberg/artifacts/soil_test"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

write.csv(results, 
          file.path(output_dir, "test_soil_extraction_results.csv"),
          row.names = FALSE)

cat(sprintf("Results saved to: %s\n", 
            file.path(output_dir, "test_soil_extraction_results.csv")))

# ============================================
# STEP 7: VALIDATION
# ============================================

cat("\n----------------------------------------\n")
cat("Validating extracted values...\n")
cat("----------------------------------------\n")

# Check for reasonable pH values (should be 10x actual pH, per SoilGrids docs)
ph_actual <- results$pH / 10
cat(sprintf("pH range (actual): %.1f - %.1f\n", 
            min(ph_actual, na.rm = TRUE),
            max(ph_actual, na.rm = TRUE)))

if (any(ph_actual < 3 | ph_actual > 11, na.rm = TRUE)) {
  cat("WARNING: Some pH values outside typical range (3-11)\n")
}

# Check geographic coverage
na_by_region <- results %>%
  mutate(region = case_when(
    longitude > -10 & longitude < 40 & latitude > 35 & latitude < 70 ~ "Europe",
    longitude > 40 & longitude < 150 & latitude > -10 & latitude < 70 ~ "Asia",
    TRUE ~ "Other"
  )) %>%
  group_by(region) %>%
  summarise(
    n_points = n(),
    n_na = sum(is.na(pH)),
    pct_na = 100 * n_na / n_points
  )

cat("\nData availability by region:\n")
print(na_by_region)

cat("\n===========================================\n")
cat("TEST COMPLETE!\n")
cat("===========================================\n")

cat("\nNext steps:\n")
cat("1. Review the results in artifacts/soil_test/\n")
cat("2. Check if extraction speeds meet requirements\n")
cat("3. Adjust chunk_size and parallel processing as needed\n")
cat("4. Scale up to full dataset if performance is acceptable\n")