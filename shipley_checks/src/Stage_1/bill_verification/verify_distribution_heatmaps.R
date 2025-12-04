#!/usr/bin/env Rscript
# verify_distribution_heatmaps.R
#
# Verifies integrity and quality of generated distribution heatmaps
#
# Usage:
#   env R_LIBS_USER="/home/olier/ellenberg/.Rlib" /usr/bin/Rscript verify_distribution_heatmaps.R

suppressPackageStartupMessages({
  library(duckdb)
  library(DBI)
  library(dplyr)
})

# Configuration
BASE_DIR <- "/home/olier/ellenberg"
GBIF_PARQUET <- file.path(BASE_DIR, "data/gbif/occurrence_plantae_wfo.parquet")
ENCYCLOPEDIA_PARQUET <- file.path(BASE_DIR, "shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet")
OUTPUT_DIR <- file.path(BASE_DIR, "shipley_checks/stage4/distribution_maps")
MIN_POINTS <- 5

cat("=== Distribution Heatmap Verification ===\n\n")

# Check output directory exists
if (!dir.exists(OUTPUT_DIR)) {
  cat("ERROR: Output directory does not exist:", OUTPUT_DIR, "\n")
  quit(save = "no", status = 1)
}

# Count PNG and WebP files
png_files <- list.files(OUTPUT_DIR, pattern = "\\.png$", full.names = TRUE)
webp_files <- list.files(OUTPUT_DIR, pattern = "\\.webp$", full.names = TRUE)

cat("Generated files:\n")
cat("  PNG files:", length(png_files), "\n")
cat("  WebP files:", length(webp_files), "\n\n")

# Connect to DuckDB
con <- dbConnect(duckdb())

# Get encyclopedia species
encyclopedia_query <- sprintf("
  SELECT DISTINCT wfo_taxon_id
  FROM read_parquet('%s')
", ENCYCLOPEDIA_PARQUET)
encyclopedia_species <- dbGetQuery(con, encyclopedia_query)$wfo_taxon_id
cat("Encyclopedia species:", length(encyclopedia_species), "\n")

# Get species with sufficient occurrences
occurrence_query <- sprintf("
  SELECT
    wfo_taxon_id,
    COUNT(*) as n
  FROM read_parquet('%s')
  WHERE wfo_taxon_id IN (SELECT DISTINCT wfo_taxon_id FROM read_parquet('%s'))
    AND decimalLatitude IS NOT NULL
    AND decimalLongitude IS NOT NULL
    AND decimalLatitude BETWEEN -90 AND 90
    AND decimalLongitude BETWEEN -180 AND 180
  GROUP BY wfo_taxon_id
  HAVING COUNT(*) >= %d
", GBIF_PARQUET, ENCYCLOPEDIA_PARQUET, MIN_POINTS)

valid_species <- dbGetQuery(con, occurrence_query)
cat("Species with >=", MIN_POINTS, "occurrences:", nrow(valid_species), "\n\n")

dbDisconnect(con, shutdown = TRUE)

# Get generated species IDs
generated_png <- sub("\\.png$", "", basename(png_files))
generated_webp <- sub("\\.webp$", "", basename(webp_files))

# Coverage analysis
cat("=== Coverage Analysis ===\n")

# PNG coverage
png_coverage <- sum(valid_species$wfo_taxon_id %in% generated_png)
png_pct <- round(100 * png_coverage / nrow(valid_species), 1)
cat("PNG coverage:", png_coverage, "/", nrow(valid_species), "(", png_pct, "%)\n")

# WebP coverage
webp_coverage <- sum(valid_species$wfo_taxon_id %in% generated_webp)
webp_pct <- round(100 * webp_coverage / nrow(valid_species), 1)
cat("WebP coverage:", webp_coverage, "/", nrow(valid_species), "(", webp_pct, "%)\n")

# Missing species
missing_png <- setdiff(valid_species$wfo_taxon_id, generated_png)
if (length(missing_png) > 0) {
  cat("\nMissing PNG files:", length(missing_png), "\n")
  if (length(missing_png) <= 20) {
    cat("  ", paste(missing_png, collapse = ", "), "\n")
  } else {
    cat("  First 20:", paste(head(missing_png, 20), collapse = ", "), "...\n")
  }
}

# File size analysis
cat("\n=== File Size Analysis ===\n")

if (length(png_files) > 0) {
  png_sizes <- file.info(png_files)$size / 1024  # KB
  cat("PNG files:\n")
  cat("  Min:", round(min(png_sizes), 1), "KB\n")
  cat("  Max:", round(max(png_sizes), 1), "KB\n")
  cat("  Mean:", round(mean(png_sizes), 1), "KB\n")
  cat("  Median:", round(median(png_sizes), 1), "KB\n")
  cat("  Total:", round(sum(png_sizes) / 1024, 1), "MB\n")

  # Check for suspiciously small/large files
  small_png <- png_files[png_sizes < 5]
  large_png <- png_files[png_sizes > 200]

  if (length(small_png) > 0) {
    cat("\n  WARNING:", length(small_png), "files < 5KB (may be corrupted)\n")
    if (length(small_png) <= 5) {
      cat("    ", paste(basename(small_png), collapse = ", "), "\n")
    }
  }

  if (length(large_png) > 0) {
    cat("\n  NOTE:", length(large_png), "files > 200KB (complex distributions)\n")
  }
}

if (length(webp_files) > 0) {
  webp_sizes <- file.info(webp_files)$size / 1024  # KB
  cat("\nWebP files:\n")
  cat("  Min:", round(min(webp_sizes), 1), "KB\n")
  cat("  Max:", round(max(webp_sizes), 1), "KB\n")
  cat("  Mean:", round(mean(webp_sizes), 1), "KB\n")
  cat("  Median:", round(median(webp_sizes), 1), "KB\n")
  cat("  Total:", round(sum(webp_sizes) / 1024, 1), "MB\n")

  if (length(png_files) > 0 && length(webp_files) > 0) {
    compression <- (1 - sum(webp_sizes) / sum(png_sizes)) * 100
    cat("  Compression ratio:", round(compression, 1), "% reduction from PNG\n")
  }
}

# Image dimension check (sample 10 random files)
cat("\n=== Image Dimension Check (sample) ===\n")

check_image_dims <- function(files, n_sample = 10) {
  if (length(files) == 0) return(NULL)

  sample_files <- sample(files, min(n_sample, length(files)))
  results <- list()

  for (f in sample_files) {
    # Use identify command if available
    dims <- tryCatch({
      output <- system2("identify", args = c("-format", "%wx%h", f), stdout = TRUE, stderr = FALSE)
      output
    }, error = function(e) NA)

    results[[basename(f)]] <- dims
  }

  return(results)
}

# Check if ImageMagick is available
if (system("which identify", ignore.stdout = TRUE) == 0) {
  if (length(png_files) > 0) {
    png_dims <- check_image_dims(png_files)
    cat("Sample PNG dimensions:\n")
    for (name in names(png_dims)) {
      cat("  ", name, ":", png_dims[[name]], "\n")
    }

    # Verify expected dimensions
    expected <- "960x480"
    correct <- sum(unlist(png_dims) == expected, na.rm = TRUE)
    cat("  Expected (960x480):", correct, "/", length(png_dims), "\n")
  }
} else {
  cat("ImageMagick not available - skipping dimension check\n")
}

# Check generation results if available
results_file <- file.path(OUTPUT_DIR, "generation_results.csv")
if (file.exists(results_file)) {
  cat("\n=== Generation Results Summary ===\n")
  results <- read.csv(results_file)

  cat("Status breakdown:\n")
  print(table(results$status))

  if ("reason" %in% names(results)) {
    errors <- results %>% filter(status == "error")
    if (nrow(errors) > 0) {
      cat("\nError reasons:\n")
      print(table(errors$reason))
    }
  }
}

# Final summary
cat("\n=== VERIFICATION SUMMARY ===\n")

all_ok <- TRUE

if (png_pct < 100) {
  cat("WARNING: PNG coverage incomplete (", png_pct, "%)\n")
  all_ok <- FALSE
}

if (length(webp_files) == 0 && length(png_files) > 0) {
  cat("NOTE: WebP conversion not yet done\n")
}

if (length(webp_files) > 0 && webp_pct < 100) {
  cat("WARNING: WebP coverage incomplete (", webp_pct, "%)\n")
  all_ok <- FALSE
}

if (all_ok && png_pct == 100) {
  cat("OK: All expected maps generated successfully\n")
}

cat("\nNext steps:\n")
if (length(webp_files) == 0 && length(png_files) > 0) {
  cat("  1. Run convert_to_webp.sh to convert PNGs\n")
  cat("  2. Upload to R2: rclone sync distribution_maps/ r2:plantphotos/maps/\n")
}
