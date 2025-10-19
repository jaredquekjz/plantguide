#!/usr/bin/env Rscript
# Efficient SoilGrids extraction - processes unique coordinates only
# Then joins back to full occurrence dataset
# Now supports selective property extraction via --properties flag

library(terra)
library(data.table)
library(optparse)

# Parse command-line arguments
option_list <- list(
  make_option(c("-p", "--properties"), type="character", default="all",
              help="Comma-separated list of properties to extract (phh2o,soc,clay,sand,cec,nitrogen,bdod) or 'all' [default %default]"),
  make_option(c("-i", "--input"), type="character", 
              default="/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654.csv",
              help="Input CSV file with occurrences [default %default]"),
  make_option(c("-o", "--output"), type="character", default=NULL,
              help="Output CSV file (auto-generated if not specified)")
)

parser <- OptionParser(option_list=option_list,
                       description="Extract SoilGrids data for occurrence points")
args <- parse_args(parser)

# Parse properties
ALL_PROPERTIES <- c("phh2o", "soc", "clay", "sand", "cec", "nitrogen", "bdod")
if (args$properties == "all") {
  PROPERTIES <- ALL_PROPERTIES
} else {
  requested <- trimws(strsplit(args$properties, ",")[[1]])
  invalid <- setdiff(requested, ALL_PROPERTIES)
  if (length(invalid) > 0) {
    stop(sprintf("Invalid properties: %s. Valid options: %s",
                 paste(invalid, collapse=", "),
                 paste(ALL_PROPERTIES, collapse=", ")))
  }
  PROPERTIES <- requested
}

# Set output filename
if (is.null(args$output)) {
  if (args$properties == "all") {
    OUTPUT_FILE <- sub("\\.csv$", "_with_soil.csv", args$input)
  } else {
    props_suffix <- paste(PROPERTIES, collapse="_")
    OUTPUT_FILE <- sub("\\.csv$", sprintf("_with_%s.csv", props_suffix), args$input)
  }
} else {
  OUTPUT_FILE <- args$output
}

cat("========================================\n")
cat("EFFICIENT SOILGRIDS EXTRACTION\n")
cat("========================================\n\n")

# Configuration
SOILGRIDS_DIR <- "/home/olier/ellenberg/data/soilgrids_250m"
INPUT_FILE <- args$input

# Report configuration
cat(sprintf("Properties to extract: %s\n", paste(PROPERTIES, collapse=", ")))
cat(sprintf("Input file: %s\n", INPUT_FILE))
cat(sprintf("Output file: %s\n\n", OUTPUT_FILE))

# Depths (always the same)
DEPTHS <- c("0-5cm", "5-15cm", "15-30cm", "30-60cm", "60-100cm", "100-200cm")

# Scaling factors
SCALING <- list(
  phh2o = 10, soc = 10, clay = 10, sand = 10, 
  cec = 10, nitrogen = 100, bdod = 100
)

# Step 1: Load occurrences and find unique coordinates
cat("Loading occurrences and finding unique coordinates...\n")
start_time <- Sys.time()

occurrences <- fread(INPUT_FILE, showProgress = FALSE)
cat(sprintf("  Total occurrences: %s\n", format(nrow(occurrences), big.mark = ",")))

# Extract unique coordinates
unique_coords <- unique(occurrences[, .(decimalLongitude, decimalLatitude)])
cat(sprintf("  Unique coordinates: %s\n", format(nrow(unique_coords), big.mark = ",")))
cat(sprintf("  Reduction: %.1fx fewer points to process!\n\n", 
            nrow(occurrences) / nrow(unique_coords)))

# Step 2: Create spatial points from unique coordinates
cat("Creating spatial points...\n")
pts <- vect(unique_coords, 
            geom = c("decimalLongitude", "decimalLatitude"), 
            crs = "EPSG:4326")

# Step 3: Copy VRT files to soilgrids directory
cat("Setting up VRT files...\n")
vrt_count <- 0
for (prop in PROPERTIES) {
  for (depth in DEPTHS) {
    vrt_source <- sprintf("/home/olier/ellenberg/data/soilgrids_250m_test/%s_%s_mean.vrt", prop, depth)
    vrt_dest <- sprintf("%s/%s_%s_mean.vrt", SOILGRIDS_DIR, prop, depth)
    
    if (file.exists(vrt_source) && !file.exists(vrt_dest)) {
      file.copy(vrt_source, vrt_dest, overwrite = FALSE)
      vrt_count <- vrt_count + 1
    }
  }
}
if (vrt_count > 0) {
  cat(sprintf("  Copied %d VRT files\n", vrt_count))
}

# Step 4: Extract soil properties for unique coordinates
total_layers <- length(PROPERTIES) * length(DEPTHS)
cat(sprintf("\nExtracting soil properties (%d layers)...\n", total_layers))
cat("Processing time depends on unique coordinates, not total occurrences\n\n")

# Initialize results
n_unique <- nrow(unique_coords)
soil_data <- matrix(NA, nrow = n_unique, ncol = length(PROPERTIES) * length(DEPTHS))
col_names <- character(0)

# Progress tracking
layer_count <- 0
total_layers <- length(PROPERTIES) * length(DEPTHS)
extraction_times <- numeric(0)

for (prop in PROPERTIES) {
  cat(sprintf("%s: ", toupper(prop)))
  
  for (depth in DEPTHS) {
    layer_count <- layer_count + 1
    col_name <- paste0(prop, "_", gsub("-", "_", depth))
    col_names <- c(col_names, col_name)
    
    # Load VRT
    vrt_file <- sprintf("%s/%s_%s_mean.vrt", SOILGRIDS_DIR, prop, depth)
    
    if (!file.exists(vrt_file)) {
      cat("✗")
      next
    }
    
    tryCatch({
      # Load raster
      r <- rast(vrt_file)
      
      # Extract values
      extract_start <- Sys.time()
      values <- extract(r, pts, ID = FALSE)[, 1]
      extract_time <- as.numeric(Sys.time() - extract_start, units = "secs")
      extraction_times <- c(extraction_times, extract_time)
      
      # Apply scaling
      scaled_values <- values / SCALING[[prop]]
      
      # Store in matrix
      col_idx <- layer_count
      soil_data[, col_idx] <- scaled_values
      
      cat("✓")
      
    }, error = function(e) {
      cat("✗")
    })
  }
  cat("\n")
}

# Step 5: Create lookup table
cat("\nCreating coordinate-soil lookup table...\n")
soil_dt <- as.data.table(soil_data)
names(soil_dt) <- col_names

# Combine with coordinates
lookup_table <- cbind(unique_coords, soil_dt)

# Step 6: Join back to full dataset
cat("Joining soil data to all occurrences...\n")
result <- merge(occurrences, lookup_table, 
                by = c("decimalLongitude", "decimalLatitude"), 
                all.x = TRUE, sort = FALSE)

# Ensure original order is preserved
setorder(result, gbifID)

# Step 7: Summary statistics
cat("\n========================================\n")
cat("EXTRACTION SUMMARY\n")
cat("========================================\n")

# Extraction performance
if (length(extraction_times) > 0) {
  avg_time <- mean(extraction_times)
  total_extract_time <- sum(extraction_times)
  cat(sprintf("Average extraction time per layer: %.1f seconds\n", avg_time))
  cat(sprintf("Total extraction time: %.1f minutes\n", total_extract_time / 60))
  cat(sprintf("Points per second: %.0f\n\n", n_unique / avg_time))
}

# Data completeness
for (prop in PROPERTIES) {
  prop_cols <- grep(paste0("^", prop, "_"), names(result), value = TRUE)
  if (length(prop_cols) > 0) {
    # Check first depth as representative
    first_col <- prop_cols[1]
    n_valid <- sum(!is.na(result[[first_col]]))
    cat(sprintf("%s: %s valid (%.1f%%)\n", 
                toupper(prop), 
                format(n_valid, big.mark = ","),
                n_valid/nrow(result)*100))
  }
}

# Step 8: Save results
cat("\nSaving results...\n")
fwrite(result, OUTPUT_FILE, showProgress = TRUE)

# File info
file_size <- file.info(OUTPUT_FILE)$size / 1024^3
cat(sprintf("Output saved: %.1f GB\n", file_size))

# Total time
total_time <- as.numeric(Sys.time() - start_time, units = "mins")
cat(sprintf("\nTotal processing time: %.1f minutes\n", total_time))

# Final message
cat("\n========================================\n")
cat("EXTRACTION COMPLETE!\n")
cat("========================================\n")
cat(sprintf("Input: %s occurrences\n", format(nrow(occurrences), big.mark = ",")))
cat(sprintf("Unique coordinates processed: %s\n", format(n_unique, big.mark = ",")))
cat(sprintf("Efficiency gain: %.1fx\n", nrow(occurrences) / n_unique))
cat(sprintf("Output: %s\n", OUTPUT_FILE))