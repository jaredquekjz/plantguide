#!/usr/bin/env Rscript
# Debug script for nitrogen extraction failures

library(terra)
library(data.table)

cat("========================================\n")
cat("DEBUGGING NITROGEN EXTRACTION\n")
cat("========================================\n\n")

# Load a subset of occurrences
INPUT_FILE <- "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654.csv"
cat("Loading first 10,000 occurrences for testing...\n")
occurrences <- fread(INPUT_FILE, nrows = 10000)

# Get unique coordinates
unique_coords <- unique(occurrences[, .(decimalLongitude, decimalLatitude)])
cat(sprintf("Unique coordinates: %d\n\n", nrow(unique_coords)))

# Create spatial points
pts <- vect(unique_coords, 
            geom = c("decimalLongitude", "decimalLatitude"), 
            crs = "EPSG:4326")

# Test each nitrogen depth
DEPTHS <- c("0-5cm", "5-15cm", "15-30cm", "30-60cm", "60-100cm", "100-200cm")
SOILGRIDS_DIR <- "/home/olier/ellenberg/data/soilgrids_250m"

for (depth in DEPTHS) {
  cat(sprintf("\nTesting nitrogen_%s:\n", depth))
  vrt_file <- sprintf("%s/nitrogen_%s_mean.vrt", SOILGRIDS_DIR, depth)
  
  if (!file.exists(vrt_file)) {
    cat("  VRT file missing!\n")
    next
  }
  
  tryCatch({
    # Load raster with verbose messages
    cat("  Loading VRT...\n")
    r <- rast(vrt_file)
    cat(sprintf("    Dimensions: %d x %d\n", nrow(r), ncol(r)))
    cat(sprintf("    CRS: %s\n", crs(r, describe=TRUE)$code))
    
    # Try extraction with progress
    cat("  Extracting values...\n")
    start_time <- Sys.time()
    
    # Extract with error handling
    withCallingHandlers({
      values <- extract(r, pts, ID = FALSE)[, 1]
      extract_time <- as.numeric(Sys.time() - start_time, units = "secs")
      
      # Check results
      n_valid <- sum(!is.na(values))
      cat(sprintf("    SUCCESS! Time: %.1f sec, Valid values: %d/%d (%.1f%%)\n", 
                  extract_time, n_valid, length(values), 
                  n_valid/length(values)*100))
      
      # Apply scaling (nitrogen uses 100)
      scaled_values <- values / 100
      cat(sprintf("    Sample values (scaled): %.2f, %.2f, %.2f\n", 
                  scaled_values[1], scaled_values[2], scaled_values[3]))
      
    }, warning = function(w) {
      cat(sprintf("    WARNING: %s\n", w$message))
      invokeRestart("muffleWarning")
    })
    
  }, error = function(e) {
    cat(sprintf("    ERROR: %s\n", e$message))
    
    # Try to get more details
    if (grepl("memory", tolower(e$message))) {
      cat("    Possible memory issue - too many tiles to load\n")
    }
    if (grepl("cannot open", tolower(e$message))) {
      cat("    Possible missing or corrupted tile files\n")
    }
  })
}

# Check memory usage
cat("\n========================================\n")
cat("MEMORY INFORMATION\n")
cat("========================================\n")
mem_info <- gc()
cat(sprintf("Memory used: %.1f MB\n", sum(mem_info[,2])))
cat(sprintf("Memory max: %.1f MB\n", sum(mem_info[,6])))

# Test with even smaller subset for problematic depths
cat("\n========================================\n")
cat("FOCUSED TEST ON FAILED DEPTHS\n")
cat("========================================\n")

problem_depths <- c("15-30cm", "30-60cm")
tiny_coords <- unique_coords[1:100, ]
tiny_pts <- vect(tiny_coords, 
                  geom = c("decimalLongitude", "decimalLatitude"), 
                  crs = "EPSG:4326")

for (depth in problem_depths) {
  cat(sprintf("\nTesting nitrogen_%s with 100 points:\n", depth))
  vrt_file <- sprintf("%s/nitrogen_%s_mean.vrt", SOILGRIDS_DIR, depth)
  
  tryCatch({
    r <- rast(vrt_file)
    
    # Try different extraction methods
    cat("  Method 1: Standard extract()...\n")
    v1 <- extract(r, tiny_pts, ID = FALSE)[, 1]
    cat(sprintf("    Success! Valid: %d/%d\n", sum(!is.na(v1)), length(v1)))
    
    cat("  Method 2: Extract with xy=TRUE...\n")
    v2 <- extract(r, tiny_pts, xy = TRUE)
    cat(sprintf("    Success! Columns: %s\n", paste(names(v2), collapse=", ")))
    
  }, error = function(e) {
    cat(sprintf("    ERROR: %s\n", e$message))
  })
}

cat("\nDebug script complete!\n")