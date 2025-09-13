#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  .libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))
  library(data.table)
  library(optparse)
})

option_list <- list(
  make_option(c("--input"), type = "character", help = "Path to CSV", metavar = "path"),
  make_option(c("--type"), type = "character", default = "generic",
              help = "Summary type: occ_soil | soil_summary | merged | generic", metavar = "type")
)
opt <- parse_args(OptionParser(option_list = option_list))
if (is.null(opt$input) || !file.exists(opt$input)) stop("Input CSV not found.")

dt <- fread(opt$input, nThread = 1, showProgress = FALSE)

title <- switch(opt$type,
  occ_soil = "Occurrence+Soil summary",
  soil_summary = "Species Soil summary",
  merged = "Merged Trait+Bioclim+Soil summary",
  "CSV summary")
cat("===============================================\n")
cat(title, "\n")
cat("===============================================\n")
cat(sprintf("Rows: %s\n", format(nrow(dt), big.mark=",")))
cat(sprintf("Cols: %s\n", ncol(dt)))

soil_pattern <- "^(phh2o|soc|clay|sand|cec|nitrogen|bdod)_"
soil_cols <- grep(soil_pattern, names(dt), value = TRUE)
bioclim_cols <- grep("^bio[0-9]+", names(dt), value = TRUE)

if (opt$type == "occ_soil") {
  sp_col <- if ("species_clean" %in% names(dt)) "species_clean" else if ("species" %in% names(dt)) "species" else NA
  if (!is.na(sp_col)) cat(sprintf("Species (unique): %s\n", format(length(unique(dt[[sp_col]])), big.mark=",")))
  cat(sprintf("Soil columns: %d\n", length(soil_cols)))
  # Quick NA rates on common layers
  for (cnd in c("phh2o_0_5cm","soc_0_5cm","clay_0_5cm","bdod_0_5cm")) {
    if (cnd %in% names(dt)) {
      na_rate <- mean(is.na(dt[[cnd]]))
      cat(sprintf("  NA %% %s: %.1f%%\n", cnd, 100*na_rate))
    }
  }
} else if (opt$type == "soil_summary") {
  if ("has_sufficient_data" %in% names(dt)) {
    ok <- sum(dt$has_sufficient_data, na.rm = TRUE)
    cat(sprintf("Species with sufficient data (>=3): %d\n", ok))
  }
  cat(sprintf("Soil columns: %d\n", length(soil_cols)))
} else if (opt$type == "merged") {
  cat(sprintf("Bioclim variables: %d\n", length(bioclim_cols)))
  # Soil mean/sd counts
  soil_mean <- grep(paste0(soil_pattern, ".*_mean$"), names(dt), value = TRUE)
  soil_sd   <- grep(paste0(soil_pattern, ".*_sd$"), names(dt), value = TRUE)
  cat(sprintf("Soil means: %d | Soil sds: %d\n", length(soil_mean), length(soil_sd)))
  # Occurrence counters if present
  for (c in c("n_occurrences_bioclim","n_occurrences_soil")) if (c %in% names(dt)) cat(sprintf("Has %s\n", c))
}

# Print first few columns for sanity
cat("\nColumns (head):\n")
print(utils::head(names(dt), 10))

