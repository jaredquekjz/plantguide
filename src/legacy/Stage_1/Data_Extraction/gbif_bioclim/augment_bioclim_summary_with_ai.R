#!/usr/bin/env Rscript

# Augment species_bioclim_summary.csv with Aridity Index (AI) per-species stats
# Why: Provide a compact, dimensionless moisture diagnostic (AI = P/PET)
# How: Extract AI raster values at species occurrence coordinates and compute mean/sd
# Inputs (prefer): a combined cleaned occurrences CSV; fallback: a directory with per-species CSVs

.libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))

suppressPackageStartupMessages({
  library(optparse)
  library(data.table)
  library(dplyr)
  library(terra)
  library(cli)
})

option_list <- list(
  make_option(c("--ai_raster"), type="character", default="data/PET/Global-AI_ET0__annual_v3_1/ai_v31_yr.tif",
              help="Path to annual AI raster (UInt16; scale=1/10000)"),
  make_option(c("--input_summary"), type="character", default="data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv",
              help="Path to input species bioclim summary CSV"),
  make_option(c("--output_summary"), type="character", default="data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_ai.csv",
              help="Path to output augmented summary CSV"),
  make_option(c("--occurrences_csv"), type="character", default="data/bioclim_extractions_cleaned/all_occurrences_cleaned_noDups.csv",
              help="Optional combined occurrences CSV with species and coordinates"),
  make_option(c("--species_dir"), type="character", default="data/bioclim_extractions_cleaned/species_bioclim",
              help="Optional directory containing per-species occurrences CSVs"),
  make_option(c("--species_col"), type="character", default="species_clean",
              help="Species column name in occurrences"),
  make_option(c("--summary_species_col"), type="character", default="species",
              help="Species column name in input summary"),
  make_option(c("--lon_col"), type="character", default="decimalLongitude",
              help="Longitude column in occurrences"),
  make_option(c("--lat_col"), type="character", default="decimalLatitude",
              help="Latitude column in occurrences"),
  make_option(c("--scale_divisor"), type="double", default=10000,
              help="Divisor to scale UInt16 AI into dimensionless value (default: 10000)")
)

opt <- parse_args(OptionParser(option_list = option_list))

normalize_species <- function(x) {
  tolower(gsub("[[:space:]]+|_+", "_", trimws(as.character(x))))
}

stop_with <- function(msg) { cli::cli_alert_danger(msg); quit(status = 1) }

# Load inputs
file.exists(opt$ai_raster) || stop_with(paste("AI raster not found:", opt$ai_raster))
file.exists(opt$input_summary) || stop_with(paste("Input summary not found:", opt$input_summary))

cli::cli_h1("Augment species bioclim summary with Aridity Index (AI)")
cli::cli_alert_info("AI raster: {opt$ai_raster}")
cli::cli_alert_info("Summary in: {opt$input_summary}")

bio <- fread(opt$input_summary)
if (!(opt$summary_species_col %in% names(bio))) {
  stop_with(paste("Summary species column not found:", opt$summary_species_col))
}

# Collect occurrences
occ <- NULL
if (file.exists(opt$occurrences_csv)) {
  cli::cli_alert_success("Using occurrences CSV: {opt$occurrences_csv}")
  occ <- tryCatch(fread(opt$occurrences_csv), error = function(e) NULL)
}

if (is.null(occ) && dir.exists(opt$species_dir)) {
  cli::cli_alert_warning("Combined CSV not found; scanning per-species directory: {opt$species_dir}")
  files <- list.files(opt$species_dir, pattern = "\\.csv$", full.names = TRUE)
  if (length(files) == 0) stop_with("No per-species CSVs found.")
  read_sp <- function(f) {
    dt <- tryCatch(fread(f, select = c(opt$lon_col, opt$lat_col, opt$species_col)), error = function(e) NULL)
    if (is.null(dt)) return(NULL)
    # If species_col missing, derive from file name
    if (!(opt$species_col %in% names(dt))) {
      sp <- gsub("_bioclim\\.csv$", "", basename(f))
      sp <- gsub("_", " ", sp)
      dt[[opt$species_col]] <- sp
    }
    dt
  }
  lst <- lapply(files, read_sp)
  lst <- lst[!sapply(lst, is.null)]
  if (length(lst) == 0) stop_with("Failed to read any per-species CSVs.")
  occ <- rbindlist(lst, fill = TRUE)
}

is_valid <- function(x) is.finite(x) & !is.na(x)
if (is.null(occ)) stop_with("No occurrences source available. Provide --occurrences_csv or --species_dir.")
if (!all(c(opt$lon_col, opt$lat_col, opt$species_col) %in% names(occ))) {
  stop_with("Occurrences are missing required columns (lon/lat/species).")
}

# Clean coordinates
occ <- occ %>% filter(is_valid(.data[[opt$lon_col]]), is_valid(.data[[opt$lat_col]]))
if (nrow(occ) == 0) stop_with("No valid coordinates in occurrences.")

# Reduce duplicates per species to speed up extraction
occ_small <- occ %>%
  transmute(
    species_occ = .data[[opt$species_col]],
    lon = as.numeric(.data[[opt$lon_col]]),
    lat = as.numeric(.data[[opt$lat_col]])
  ) %>%
  distinct(species_occ, lon, lat)

cli::cli_alert_info("Unique coords: {format(nrow(occ_small), big.mark=',')}")

# Extract AI values
r <- rast(opt$ai_raster)
ex <- extract(r, as.matrix(occ_small[, c("lon", "lat")] ))
# terra versions may include an ID column; drop it if present
if ("ID" %in% names(ex)) ex <- ex[, -1, drop = FALSE]
occ_small$ai_raw <- as.numeric(ex[[1]])  # UInt16 (0..65535) or NA

# Aggregate per species (scale to dimensionless)
ai_ag <- occ_small %>%
  filter(!is.na(ai_raw)) %>%
  group_by(species_occ) %>%
  summarise(
    ai_mean = mean(ai_raw) / opt$scale_divisor,
    ai_sd   = sd(ai_raw) / opt$scale_divisor,
    n_ai    = n(),
    .groups = "drop"
  )

cli::cli_alert_success("Computed AI for {nrow(ai_ag)} species")

# Join to summary by normalized species names
bio <- as.data.frame(bio)
bio$.__join <- normalize_species(bio[[opt$summary_species_col]])
ai_ag$.__join <- normalize_species(ai_ag$species_occ)

out <- bio %>%
  left_join(ai_ag %>% select(.__join, ai_mean, ai_sd, n_ai), by = ".__join") %>%
  select(-.__join)

fwrite(out, opt$output_summary)
cli::cli_alert_success("Wrote augmented summary: {opt$output_summary}")
cli::cli_alert_info("Rows: {nrow(out)}, Cols: {ncol(out)}")
