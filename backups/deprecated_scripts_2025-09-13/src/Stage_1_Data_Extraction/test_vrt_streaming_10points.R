#!/usr/bin/env Rscript
# Simple test: VRT streaming for 10 global points

library(terra)

cat("Testing VRT Streaming (10 points)\n")
cat("==================================\n\n")

# 10 test points from different continents
test_points <- data.frame(
  id = 1:10,
  location = c("Germany", "Brazil", "Kenya", "India", "Australia", 
               "Canada", "Spain", "Japan", "Mexico", "Norway"),
  lon = c(10.5, -47.9, 36.8, 78.0, 133.8, 
          -106.3, -3.7, 138.2, -99.1, 10.7),
  lat = c(51.2, -15.8, -1.3, 20.6, -25.3, 
          56.1, 40.4, 36.2, 19.4, 59.9)
)

print(test_points)

# Convert to SpatVector
points <- vect(test_points, geom = c("lon", "lat"), crs = "EPSG:4326")

# Test pH extraction via VRT
cat("\nConnecting to SoilGrids pH VRT...\n")
ph_url <- "/vsicurl/https://files.isric.org/soilgrids/latest/data/phh2o/phh2o_0-5cm_mean.vrt"

start_time <- Sys.time()

tryCatch({
  # Load VRT (no download, just metadata)
  ph_raster <- rast(ph_url)
  connect_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  cat(sprintf("Connected in %.2f seconds\n", connect_time))
  
  # Extract values
  cat("\nExtracting values for 10 global points...\n")
  extract_start <- Sys.time()
  
  values <- extract(ph_raster, points)
  
  extract_time <- as.numeric(difftime(Sys.time(), extract_start, units = "secs"))
  
  # Show results
  results <- cbind(test_points, pH_raw = values[,2], pH = values[,2] / 10)
  cat(sprintf("\nExtraction completed in %.2f seconds\n", extract_time))
  cat(sprintf("Speed: %.2f seconds per point\n\n", extract_time / 10))
  
  print(results)
  
  # Performance projection
  cat("\n--- Performance Projections ---\n")
  points_per_hour <- 3600 / (extract_time / 10)
  cat(sprintf("Rate: %.0f points/hour\n", points_per_hour))
  cat(sprintf("5M points would take: %.1f hours\n", 5000000 / points_per_hour))
  
  if (extract_time / 10 > 1) {
    cat("\n⚠️  WARNING: Too slow for 5M points (>1 sec/point)\n")
    cat("Recommendation: Use download approach instead\n")
  } else {
    cat("\n✓ Acceptable speed for large-scale extraction\n")
  }
  
}, error = function(e) {
  cat("\n❌ VRT STREAMING FAILED\n")
  cat(sprintf("Error: %s\n", e$message))
  cat("\nRecommendation: Use download approach\n")
})

cat("\n==================================\n")
cat("Test complete. See results above.\n")