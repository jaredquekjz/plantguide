#!/usr/bin/env Rscript
# Minimal test of SoilGrids vsicurl connection

library(terra)

cat("Testing SoilGrids vsicurl connection...\n\n")

# Test with just 10 European points
test_points <- data.frame(
  id = 1:10,
  lon = c(10.5, 11.2, 9.8, 8.5, 12.0, 13.5, 7.2, 14.8, 6.5, 15.3),  # Germany/Central Europe
  lat = c(51.2, 50.8, 52.1, 49.5, 51.8, 52.5, 50.2, 51.0, 51.5, 50.5)
)

cat("Test points (Central Europe):\n")
print(test_points)

# Convert to SpatVector
points_vect <- vect(test_points, geom = c("lon", "lat"), crs = "EPSG:4326")

# Test 1: Try to connect to pH raster
cat("\n1. Attempting to connect to pH data...\n")
ph_url <- "/vsicurl/https://files.isric.org/soilgrids/latest/data/phh2o/phh2o_0-5cm_mean.vrt"

tryCatch({
  start <- Sys.time()
  ph_raster <- rast(ph_url)
  cat(sprintf("   SUCCESS: Connected in %.2f seconds\n", 
              as.numeric(difftime(Sys.time(), start, units = "secs"))))
  
  # Show raster info
  cat("\n   Raster properties:\n")
  cat(sprintf("   - Dimensions: %d x %d pixels\n", nrow(ph_raster), ncol(ph_raster)))
  cat(sprintf("   - Resolution: %.6f degrees\n", res(ph_raster)[1]))
  cat(sprintf("   - Data type: %s\n", datatype(ph_raster)))
  
  # Test 2: Extract values
  cat("\n2. Extracting values for 10 points...\n")
  start <- Sys.time()
  values <- extract(ph_raster, points_vect)
  extract_time <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  
  cat(sprintf("   SUCCESS: Extracted in %.2f seconds\n", extract_time))
  cat("\n   Extracted values:\n")
  result <- cbind(test_points, pH = values[, 2] / 10)  # Convert to actual pH
  print(result)
  
  # Test 3: Try a different property
  cat("\n3. Testing organic carbon data...\n")
  soc_url <- "/vsicurl/https://files.isric.org/soilgrids/latest/data/soc/soc_0-5cm_mean.vrt"
  
  start <- Sys.time()
  soc_raster <- rast(soc_url)
  soc_values <- extract(soc_raster, points_vect)
  soc_time <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  
  cat(sprintf("   SUCCESS: Extracted SOC in %.2f seconds\n", soc_time))
  
  # Summary
  cat("\n" + paste(rep("=", 50), collapse = "") + "\n")
  cat("TEST SUCCESSFUL!\n")
  cat(paste(rep("=", 50), collapse = "") + "\n")
  cat(sprintf("Total time: %.2f seconds\n", extract_time + soc_time))
  cat(sprintf("Speed: %.1f points/second\n", 10 / extract_time))
  cat("\nProjections:\n")
  cat(sprintf("- 1,000 points: ~%.1f seconds\n", 1000 / (10 / extract_time)))
  cat(sprintf("- 100,000 points: ~%.1f minutes\n", 100000 / (10 / extract_time) / 60))
  cat(sprintf("- 5M points: ~%.1f hours\n", 5000000 / (10 / extract_time) / 3600))
  
}, error = function(e) {
  cat("\n   ERROR: Failed to connect or extract\n")
  cat(sprintf("   Error message: %s\n", e$message))
  
  # Debugging info
  cat("\n   Debugging information:\n")
  cat(sprintf("   - GDAL version: %s\n", gdal()))
  cat(sprintf("   - Terra version: %s\n", packageVersion("terra")))
  cat("   - Testing alternative URL format...\n")
  
  # Try without vsicurl prefix (terra might add it automatically)
  alt_url <- "https://files.isric.org/soilgrids/latest/data/phh2o/phh2o_0-5cm_mean.vrt"
  try({
    alt_raster <- rast(alt_url, vsi = TRUE)
    cat("   Alternative URL format worked!\n")
  })
})