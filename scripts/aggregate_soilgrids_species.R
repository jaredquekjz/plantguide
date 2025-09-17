#!/usr/bin/env Rscript
# Aggregate occurrence-level SoilGrids values to species-level summaries

# Usage example:
#   R_LIBS_USER=/home/olier/ellenberg/.Rlib \
#   Rscript scripts/aggregate_soilgrids_species.R \
#     --input /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654_with_soil.csv \
#     --species_col species_clean \
#     --min_occ 3 \
#     --output /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary.csv

suppressPackageStartupMessages({
  .libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))
  library(data.table)
  library(optparse)
})

option_list <- list(
  make_option(c("--input"), type = "character",
              default = "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654_with_soil.csv",
              help = "Path to occurrences CSV with appended SoilGrids columns",
              metavar = "path"),
  make_option(c("--species_col"), type = "character",
              default = "species_clean",
              help = "Column name holding species (default: species_clean)",
              metavar = "name"),
  make_option(c("--min_occ"), type = "integer",
              default = 3,
              help = "Minimum occurrences per species to flag sufficient data (default: 3)",
              metavar = "integer"),
  make_option(c("--output"), type = "character",
              default = "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary.csv",
              help = "Output CSV path for species-level soil summary",
              metavar = "path")
)

opt <- parse_args(OptionParser(option_list = option_list))

cat("===============================================\n")
cat("Aggregating SoilGrids to species level\n")
cat("===============================================\n\n")

cat(sprintf("Input:   %s\n", opt$input))
cat(sprintf("Species: %s\n", opt$species_col))
cat(sprintf("Min occ: %d\n", opt$min_occ))
cat(sprintf("Output:  %s\n\n", opt$output))

dt <- fread(opt$input, showProgress = TRUE)

if (!opt$species_col %in% names(dt)) {
  stop(sprintf("Species column '%s' not found in input.", opt$species_col))
}

# Identify soil columns (42 layers expected)
soil_cols <- grep("^(phh2o|soc|clay|sand|cec|nitrogen|bdod)_", names(dt), value = TRUE)
if (length(soil_cols) == 0) {
  stop("No soil columns found. Did the extraction step complete?")
}

# Ensure species column named 'species' in output
dt[, species := get(opt$species_col)]

# Collapse to unique coordinates per species to avoid overweighting duplicates
if (!all(c("decimalLongitude","decimalLatitude") %in% names(dt))) {
  stop("Input missing decimalLongitude/decimalLatitude columns for deduplication.")
}
dt_unique <- unique(dt, by = c("species", "decimalLongitude", "decimalLatitude"))

cat(sprintf("Found %d soil layers: %s\n\n", length(soil_cols), paste(head(soil_cols, 6), collapse = ", "))) 

cat("Computing per-species counts...\n")
species_counts <- dt[, .(n_occurrences = .N), by = .(species)]
species_unique_counts <- dt_unique[, .(n_unique_coords = .N), by = .(species)]

compute_agg <- function(fun, suffix) {
  tmp <- dt[, lapply(.SD, function(x) suppressWarnings(fun(x, na.rm = TRUE))),
            .SDcols = soil_cols, by = .(species)]
  setnames(tmp, old = soil_cols, new = paste0(soil_cols, suffix))
  tmp
}

cat("Computing per-species means...\n")
means_dt <- dt_unique[, lapply(.SD, function(x) suppressWarnings(mean(x, na.rm = TRUE))),
                      .SDcols = soil_cols, by = .(species)]
setnames(means_dt, old = soil_cols, new = paste0(soil_cols, "_mean"))

cat("Computing per-species standard deviations...\n")
sds_dt <- dt_unique[, lapply(.SD, function(x) suppressWarnings(sd(x, na.rm = TRUE))),
                    .SDcols = soil_cols, by = .(species)]
setnames(sds_dt, old = soil_cols, new = paste0(soil_cols, "_sd"))

cat("Computing per-species valid counts per layer...\n")
nvalid_dt <- dt_unique[, lapply(.SD, function(x) sum(!is.na(x))), .SDcols = soil_cols, by = .(species)]
setnames(nvalid_dt, old = soil_cols, new = paste0(soil_cols, "_n_valid"))

cat("Computing per-species quantiles (p10, p50, p90)...\n")
qfun <- function(x, p) suppressWarnings(as.numeric(stats::quantile(x, probs = p, na.rm = TRUE, type = 7)))
q10_dt <- dt_unique[, lapply(.SD, function(x) qfun(x, 0.10)), .SDcols = soil_cols, by = .(species)]
setnames(q10_dt, old = soil_cols, new = paste0(soil_cols, "_p10"))
q50_dt <- dt_unique[, lapply(.SD, function(x) qfun(x, 0.50)), .SDcols = soil_cols, by = .(species)]
setnames(q50_dt, old = soil_cols, new = paste0(soil_cols, "_p50"))
q90_dt <- dt_unique[, lapply(.SD, function(x) qfun(x, 0.90)), .SDcols = soil_cols, by = .(species)]
setnames(q90_dt, old = soil_cols, new = paste0(soil_cols, "_p90"))

cat("Merging summaries...\n")
out <- Reduce(function(x, y) merge(x, y, by = "species", all = TRUE),
              list(species_counts, species_unique_counts, means_dt, sds_dt, q10_dt, q50_dt, q90_dt, nvalid_dt))

out[, has_sufficient_data := n_occurrences >= opt$min_occ]

# Ensure output directory exists
if (!dir.exists(dirname(opt$output))) {
  dir.create(dirname(opt$output), recursive = TRUE, showWarnings = FALSE)
}

fwrite(out, opt$output)

cat("\n===============================================\n")
cat("Species-level soil summary saved\n")
cat("===============================================\n")
cat(sprintf("Species: %d\n", nrow(out)))
cat(sprintf("Columns: %d\n", ncol(out)))
cat(sprintf("Output:  %s\n", opt$output))
