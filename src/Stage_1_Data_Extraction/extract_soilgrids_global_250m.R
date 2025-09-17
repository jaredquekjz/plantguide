#!/usr/bin/env Rscript
# Extract SoilGrids values from local global 250m GeoTIFFs
# - Uses unique (lon,lat) coordinates to speed up
# - Preserves per-depth columns (42 layers) with correct scaling
# - Joins back to the full occurrences table

suppressPackageStartupMessages({
  library(terra)
  library(data.table)
  library(optparse)
})

option_list <- list(
  make_option(c("-i", "--input"), type = "character",
              default = "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv",
              help = "Path to occurrences CSV (bioclim-first cleaned). Columns required: decimalLongitude, decimalLatitude [default %default]"),
  make_option(c("-o", "--output"), type = "character",
              default = NULL,
              help = "Output CSV path. If not set, appends _with_soilglobal.csv to input."),
  make_option(c("-p", "--properties"), type = "character",
              default = "phh2o,soc,clay,sand,cec,nitrogen,bdod",
              help = "Comma-separated list of properties to extract [default %default]"),
  make_option(c("-d", "--dir"), type = "character",
              default = "/home/olier/ellenberg/data/soilgrids_250m_global",
              help = "Directory containing <prop>_<depth>_global_250m.tif files [default %default]"),
  make_option(c("-c", "--chunk"), type = "integer",
              default = 500000,
              help = "Extraction chunk size for unique points (0 = no chunking) [default %default]")
)

opt <- parse_args(OptionParser(option_list = option_list,
                              description = "Extract SoilGrids (global 250m) for occurrence points"))

ALL_PROPERTIES <- c("phh2o", "soc", "clay", "sand", "cec", "nitrogen", "bdod")
DEPTHS <- c("0-5cm", "5-15cm", "15-30cm", "30-60cm", "60-100cm", "100-200cm")

# Unit scaling to convert to standard units
# phh2o, soc, clay, sand, cec are scaled by 10; nitrogen and bdod by 100 in SoilGrids 250m tiles
SCALING <- list(phh2o = 10, soc = 10, clay = 10, sand = 10, cec = 10, nitrogen = 100, bdod = 100)

# Resolve properties
req_props <- unique(trimws(strsplit(opt$properties, ",", fixed = TRUE)[[1]]))
invalid <- setdiff(req_props, ALL_PROPERTIES)
if (length(invalid) > 0) {
  stop(sprintf("Invalid properties requested: %s\nValid: %s",
               paste(invalid, collapse = ", "), paste(ALL_PROPERTIES, collapse = ", ")))
}

input_file <- opt$input
if (!file.exists(input_file)) {
  # Fallback to 654 variant if present
  input_654 <- sub("all_occurrences_cleaned\\.csv$", "all_occurrences_cleaned_654.csv", input_file)
  if (file.exists(input_654)) {
    input_file <- input_654
  } else {
    stop(sprintf("Input occurrences file not found: %s", opt$input))
  }
}

output_file <- if (is.null(opt$output)) {
  sub("\\.csv$", "_with_soilglobal.csv", input_file)
} else opt$output

sg_dir <- opt$dir
if (!dir.exists(sg_dir)) stop(sprintf("SoilGrids dir not found: %s", sg_dir))

cat("========================================\n")
cat("GLOBAL 250m SOILGRIDS EXTRACTION\n")
cat("========================================\n\n")
cat(sprintf("Input:      %s\n", input_file))
cat(sprintf("Soil dir:   %s\n", sg_dir))
cat(sprintf("Properties: %s\n", paste(req_props, collapse = ", ")))
cat(sprintf("Depths:     %s\n", paste(DEPTHS, collapse = ", ")))
cat(sprintf("Output:     %s\n", output_file))
cat(sprintf("Chunk:      %s\n\n", ifelse(opt$chunk > 0, opt$chunk, "no chunk")))

dt <- fread(input_file, showProgress = TRUE)
if (!all(c("decimalLongitude", "decimalLatitude") %in% names(dt))) {
  stop("Input must contain decimalLongitude and decimalLatitude columns")
}

# Unique lon/lat to reduce work
unique_coords <- unique(dt[, .(decimalLongitude, decimalLatitude)])
cat(sprintf("Occurrences: %s\n", format(nrow(dt), big.mark = ",")))
cat(sprintf("Unique pts:  %s (x%.1f speedup)\n\n",
            format(nrow(unique_coords), big.mark = ","),
            nrow(dt)/nrow(unique_coords)))

# Build output matrix for all requested layers
layer_names <- character()
for (prop in req_props) {
  for (depth in DEPTHS) {
    layer_names <- c(layer_names, paste0(prop, "_", gsub("-", "_", depth)))
  }
}
soil_mat <- matrix(NA_real_, nrow = nrow(unique_coords), ncol = length(layer_names))
colnames(soil_mat) <- layer_names

# Helper to extract a single layer, chunked if necessary
extract_layer <- function(r, pts, chunk) {
  if (chunk <= 0 || nrow(pts) <= chunk) {
    vals <- extract(r, pts, ID = FALSE)
    return(vals[, 1])
  }
  out <- numeric(nrow(pts))
  n <- nrow(pts)
  i <- 1L
  while (i <= n) {
    j <- min(i + chunk - 1L, n)
    subpts <- pts[i:j, ]
    vals <- extract(r, subpts, ID = FALSE)
    out[i:j] <- vals[, 1]
    i <- j + 1L
  }
  out
}

# Create SpatVector once (may be large; chunk extraction still benefits IO)
pts <- vect(unique_coords, geom = c("decimalLongitude", "decimalLatitude"), crs = "EPSG:4326")

start_time <- Sys.time()
layer_idx <- 0L
extraction_times <- numeric(0)

for (prop in req_props) {
  cat(sprintf("%s: ", toupper(prop)))
  for (depth in DEPTHS) {
    layer_idx <- layer_idx + 1L
    tif_path <- file.path(sg_dir, sprintf("%s_%s_global_250m.tif", prop, depth))
    col_name <- paste0(prop, "_", gsub("-", "_", depth))

    if (!file.exists(tif_path)) { cat("✗"); next }

    ok <- TRUE
    t0 <- Sys.time()
    tryCatch({
      r <- rast(tif_path)
      vals <- extract_layer(r, pts, opt$chunk)
      # scale
      vals <- vals / SCALING[[prop]]
      soil_mat[, which(colnames(soil_mat) == col_name)] <- vals
    }, error = function(e) { ok <<- FALSE })

    dt_secs <- as.numeric(Sys.time() - t0, units = "secs")
    extraction_times <- c(extraction_times, dt_secs)
    cat(if (ok) "✓" else "✗")
  }
  cat("\n")
}

# Combine lookup and merge back
lookup <- cbind(unique_coords, as.data.table(soil_mat))
res <- merge(dt, lookup, by = c("decimalLongitude", "decimalLatitude"), all.x = TRUE, sort = FALSE)

if ("gbifID" %in% names(res)) setorder(res, gbifID)

# Quick completeness per property (first depth as representative)
cat("\nCompleteness by property (first depth):\n")
for (prop in req_props) {
  first_col <- paste0(prop, "_", gsub("-", "_", DEPTHS[1]))
  if (first_col %in% names(res)) {
    n_valid <- sum(!is.na(res[[first_col]]))
    cat(sprintf("  %6s: %s (%.1f%%)\n", toupper(prop), format(n_valid, big.mark = ","), 100*n_valid/nrow(res)))
  }
}

fwrite(res, output_file, showProgress = TRUE)
size_gb <- file.info(output_file)$size/1024^3
cat(sprintf("\nSaved: %s (%.1f GB)\n", output_file, size_gb))
cat(sprintf("Total time: %.1f min\n", as.numeric(Sys.time() - start_time, units = "mins")))
cat("Done.\n")
