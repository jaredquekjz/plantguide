#!/usr/bin/env Rscript
# Extract SoilGrids properties for 654-species GBIF occurrences
# Uses local tiles with VRT files for fast extraction

library(terra)
library(data.table)
library(parallel)

cat("========================================\n")
cat("SOILGRIDS EXTRACTION FOR GBIF OCCURRENCES\n")
cat("========================================\n\n")

# Configuration
SOILGRIDS_DIR <- "/home/olier/ellenberg/data/soilgrids_250m"
INPUT_FILE <- "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654.csv"
OUTPUT_FILE <- "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654_with_soil.csv"

# Properties and depths
PROPERTIES <- c("phh2o", "soc", "clay", "sand", "cec", "nitrogen", "bdod")
DEPTHS <- c("0-5cm", "5-15cm", "15-30cm", "30-60cm", "60-100cm", "100-200cm")

# Scaling factors for each property
SCALING <- list(
  phh2o = 10,      # pH in water
  soc = 10,        # Soil organic carbon (g/kg)
  clay = 10,       # Clay content (%)
  sand = 10,       # Sand content (%)
  cec = 10,        # Cation exchange capacity (cmol/kg)
  nitrogen = 100,  # Total nitrogen (g/kg)
  bdod = 100       # Bulk density (kg/dm³)
)

# Step 1: Load occurrences
cat("Loading occurrence data...\n")
start_time <- Sys.time()

# Read with fread for speed
occurrences <- fread(INPUT_FILE, showProgress = TRUE)
n_occ <- nrow(occurrences)
cat(sprintf("Loaded %s occurrences\n\n", format(n_occ, big.mark = ",")))

# Step 2: Create spatial points
cat("Creating spatial points...\n")
pts <- vect(occurrences, 
            geom = c("decimalLongitude", "decimalLatitude"), 
            crs = "EPSG:4326")

# Step 3: Copy VRT files to soilgrids directory (needed for relative paths)
cat("Setting up VRT files...\n")
for (prop in PROPERTIES) {
  for (depth in DEPTHS) {
    vrt_source <- sprintf("/home/olier/ellenberg/data/soilgrids_250m_test/%s_%s_mean.vrt", prop, depth)
    vrt_dest <- sprintf("%s/%s_%s_mean.vrt", SOILGRIDS_DIR, prop, depth)
    
    if (file.exists(vrt_source) && !file.exists(vrt_dest)) {
      file.copy(vrt_source, vrt_dest, overwrite = FALSE)
    }
  }
}

# Step 4: Extract soil properties
cat("\nExtracting soil properties...\n")
cat("This will take approximately 3-4 hours for 5.2M points\n")
cat("Processing 42 layers (7 properties × 6 depths)\n\n")

# Initialize results matrix
soil_data <- matrix(NA, nrow = n_occ, ncol = length(PROPERTIES) * length(DEPTHS))
col_names <- character(0)

# Progress counter
layer_count <- 0
total_layers <- length(PROPERTIES) * length(DEPTHS)

# Process each property and depth
for (prop in PROPERTIES) {
  cat(sprintf("\nProcessing %s:\n", toupper(prop)))
  
  for (depth in DEPTHS) {
    layer_count <- layer_count + 1
    col_name <- paste0(prop, "_", gsub("-", "_", depth))
    col_names <- c(col_names, col_name)
    
    # Progress indicator
    cat(sprintf("  [%d/%d] %s... ", layer_count, total_layers, depth))
    
    # Load VRT
    vrt_file <- sprintf("%s/%s_%s_mean.vrt", SOILGRIDS_DIR, prop, depth)
    
    if (!file.exists(vrt_file)) {
      cat("VRT not found, skipping\n")
      next
    }
    
    tryCatch({
      # Load raster
      r <- rast(vrt_file)
      
      # Extract values
      extract_start <- Sys.time()
      values <- extract(r, pts, ID = FALSE)[, 1]
      extract_time <- as.numeric(Sys.time() - extract_start, units = "secs")
      
      # Apply scaling
      scaled_values <- values / SCALING[[prop]]
      
      # Store in matrix
      col_idx <- (layer_count - 1) + 1
      soil_data[, col_idx] <- scaled_values
      
      # Count successful extractions
      n_valid <- sum(!is.na(scaled_values))
      pct_valid <- n_valid / n_occ * 100
      
      cat(sprintf("✓ %.1fs (%d%% valid)\n", extract_time, round(pct_valid)))
      
    }, error = function(e) {
      cat(sprintf("✗ Error: %s\n", e$message))
    })
  }
}

# Step 5: Combine with original data
cat("\nCombining with original occurrence data...\n")

# Convert matrix to data.table
soil_dt <- as.data.table(soil_data)
names(soil_dt) <- col_names

# Add soil data to occurrences
result <- cbind(occurrences, soil_dt)

# Step 6: Calculate summary statistics
cat("\n========================================\n")
cat("EXTRACTION SUMMARY\n")
cat("========================================\n\n")

# Count valid values per property
for (prop in PROPERTIES) {
  prop_cols <- grep(paste0("^", prop, "_"), names(result), value = TRUE)
  if (length(prop_cols) > 0) {
    valid_counts <- sapply(result[, ..prop_cols], function(x) sum(!is.na(x)))
    avg_valid <- mean(valid_counts)
    cat(sprintf("%s: %.0f average valid values (%.1f%%)\n", 
                toupper(prop), avg_valid, avg_valid/n_occ*100))
  }
}

# Step 7: Save results
cat("\nSaving results...\n")
fwrite(result, OUTPUT_FILE, showProgress = TRUE)

# Calculate file size
file_size <- file.info(OUTPUT_FILE)$size / 1024^3
cat(sprintf("\nOutput saved: %s (%.1f GB)\n", OUTPUT_FILE, file_size))

# Total time
total_time <- as.numeric(Sys.time() - start_time, units = "mins")
cat(sprintf("\nTotal processing time: %.1f minutes\n", total_time))

# Final statistics
cat("\n========================================\n")
cat("FINAL STATISTICS\n")
cat("========================================\n")
cat(sprintf("Input occurrences: %s\n", format(n_occ, big.mark = ",")))
cat(sprintf("Soil properties extracted: %d\n", length(PROPERTIES)))
cat(sprintf("Depths processed: %d\n", length(DEPTHS)))
cat(sprintf("Total columns added: %d\n", ncol(soil_dt)))
cat(sprintf("Output file columns: %d\n", ncol(result)))
cat("\nExtraction complete!\n")