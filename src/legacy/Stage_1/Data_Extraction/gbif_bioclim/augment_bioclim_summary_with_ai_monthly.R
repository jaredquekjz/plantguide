#!/usr/bin/env Rscript

# Augment species_bioclim_summary.csv with Monthly AI (P/PET) dryness features
# Features per species (computed from unique (species, lon, lat) coords):
#  - ai_month_min: min monthly AI
#  - ai_month_p10: 10th percentile monthly AI (robust low-end)
#  - ai_roll3_min: min 3-month rolling mean AI (circular months)
#  - ai_dry_frac_t020, ai_dry_run_max_t020: fraction and longest run of months with AI < 0.20
#  - ai_dry_frac_t050, ai_dry_run_max_t050: fraction and longest run of months with AI < 0.50
#  - ai_amp: p90 - p10 (amplitude)
#  - ai_cv_month: sd/mean across 12 months (variability)
#  - n_ai_m: number of unique coords contributing non-NA monthly vectors

.libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))

suppressPackageStartupMessages({
  library(optparse)
  library(data.table)
  library(dplyr)
  library(terra)
  library(cli)
})

option_list <- list(
  make_option(c("--ai_month_dir"), type="character",
              default="data/PET/Global_AI__monthly_v3_1/Global_AI__monthly_v3_1",
              help="Directory containing 12 monthly AI GeoTIFFs (ai_v31_01.tif..ai_v31_12.tif)"),
  make_option(c("--input_summary"), type="character",
              default="data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv",
              help="Input species bioclim summary CSV"),
  make_option(c("--output_summary"), type="character",
              default="data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv",
              help="Output augmented summary CSV"),
  make_option(c("--occurrences_csv"), type="character",
              default="/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654.csv",
              help="Combined occurrences CSV with species and coordinates"),
  make_option(c("--species_dir"), type="character",
              default="/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/species_data",
              help="Optional per-species directory (fallback if combined CSV unavailable)"),
  make_option(c("--species_col"), type="character", default="species_clean",
              help="Species column in occurrences"),
  make_option(c("--summary_species_col"), type="character", default="species",
              help="Species column in summary"),
  make_option(c("--lon_col"), type="character", default="decimalLongitude",
              help="Longitude column in occurrences"),
  make_option(c("--lat_col"), type="character", default="decimalLatitude",
              help="Latitude column in occurrences"),
  make_option(c("--scale_divisor"), type="double", default=10000,
              help="Divisor to scale UInt16 AI into dimensionless (default 10000)"),
  make_option(c("--thr1"), type="double", default=0.20,
              help="Dry threshold 1 (default 0.20)"),
  make_option(c("--thr2"), type="double", default=0.50,
              help="Dry threshold 2 (default 0.50)"),
  make_option(c("--roll_len"), type="integer", default=3,
              help="Rolling window length for seasonal min (default 3 months)"),
  make_option(c("--chunk_size"), type="integer", default=100000,
              help="Chunk size for batched extraction (default 200k points)")
  ,
  make_option(c("--workers"), type="integer", default=1,
              help="Number of parallel workers (forked processes). Use 1 to disable parallel.")
)

opt <- parse_args(OptionParser(option_list = option_list))

normalize_species <- function(x) {
  tolower(gsub("[[:space:]]+|_+", "_", trimws(as.character(x))))
}
stop_with <- function(msg) { cli::cli_alert_danger(msg); quit(status = 1) }

# Load species summary
file.exists(opt$input_summary) || stop_with(paste("Input summary not found:", opt$input_summary))
bio <- fread(opt$input_summary)
if (!(opt$summary_species_col %in% names(bio))) stop_with("Summary species column not found")

# Monthly AI files
if (!dir.exists(opt$ai_month_dir)) stop_with(paste("Monthly AI directory not found:", opt$ai_month_dir))
files <- list.files(opt$ai_month_dir, pattern = "^ai_v31_([0-9]{2})\\.tif$", full.names = TRUE)
if (length(files) != 12) stop_with(sprintf("Expected 12 monthly AI tifs, found %d", length(files)))

# Order by month number
month_num <- as.integer(sub("^.*ai_v31_([0-9]{2})\\.tif$", "\\1", basename(files)))
ord <- order(month_num)
files <- files[ord]

cli::cli_h1("Augment summary with Monthly AI dryness features")
cli::cli_alert_info("AI monthly dir: {opt$ai_month_dir}")
cli::cli_alert_info("Summary in: {opt$input_summary}")

# Load occurrences (combined preferred)
occ <- NULL
if (file.exists(opt$occurrences_csv)) {
  cli::cli_alert_success("Using occurrences CSV: {opt$occurrences_csv}")
  occ <- tryCatch(fread(opt$occurrences_csv), error = function(e) NULL)
}
if (is.null(occ) && dir.exists(opt$species_dir)) {
  cli::cli_alert_warning("Combined CSV not found; scanning per-species directory: {opt$species_dir}")
  fns <- list.files(opt$species_dir, pattern = "\\.csv$", full.names = TRUE)
  read_sp <- function(f) {
    dt <- tryCatch(fread(f, select = c(opt$lon_col, opt$lat_col)), error = function(e) NULL)
    if (is.null(dt)) return(NULL)
    sp <- gsub("_bioclim\\.csv$", "", basename(f))
    sp <- gsub("_", " ", sp)
    dt[[opt$species_col]] <- sp
    dt
  }
  lst <- lapply(fns, read_sp)
  lst <- lst[!sapply(lst, is.null)]
  if (length(lst) > 0) occ <- rbindlist(lst, fill = TRUE)
}
if (is.null(occ)) stop_with("No occurrences source available.")

# Deduplicate to unique coords per species
is_valid <- function(x) is.finite(x) & !is.na(x)
occ <- occ %>% filter(is_valid(.data[[opt$lon_col]]), is_valid(.data[[opt$lat_col]]))
occ_small <- occ %>%
  transmute(
    species_occ = .data[[opt$species_col]],
    lon = as.numeric(.data[[opt$lon_col]]),
    lat = as.numeric(.data[[opt$lat_col]])
  ) %>%
  distinct(species_occ, lon, lat)

cli::cli_alert_info("Unique (species, lon, lat): {format(nrow(occ_small), big.mark=',')}")

# Helper: per-range processor (builds its own raster stack to avoid cross-process issues)
process_range <- function(ridx) {
  terraOptions(progress = 0, memfrac = 0.6)
  rloc <- rast(files)
  names(rloc) <- sprintf("m%02d", 1:12)
  nloc <- length(ridx)
  start <- ridx[1]; end <- ridx[nloc]
  chunk <- max(10000, min(opt$chunk_size, nloc))
  feats <- data.table(
    species_occ = occ_small$species_occ[ridx],
    lon = occ_small$lon[ridx],
    lat = occ_small$lat[ridx],
    ai_month_min = NA_real_, ai_month_p10 = NA_real_, ai_roll3_min = NA_real_,
    ai_dry_frac_t020 = NA_real_, ai_dry_run_max_t020 = NA_real_,
    ai_dry_frac_t050 = NA_real_, ai_dry_run_max_t050 = NA_real_,
    ai_amp = NA_real_, ai_cv_month = NA_real_
  )
  idx <- 1
  while (idx <= nloc) {
    j <- min(nloc, idx + chunk - 1)
    chunk_start <- start + idx - 1
    chunk_end <- start + j - 1
    cli::cli_alert_info("Processing chunk {chunk_start}-{chunk_end}")
    ex <- tryCatch({
      extract(rloc, as.matrix(cbind(feats$lon[idx:j], feats$lat[idx:j])))
    }, error = function(e) {
      # back off once
      j2 <- idx + floor((j-idx+1)/2) - 1
      extract(rloc, as.matrix(cbind(feats$lon[idx:j2], feats$lat[idx:j2])))
    })
    if ("ID" %in% names(ex)) ex <- ex[, -1, drop = FALSE]
    ex <- as.matrix(ex) / opt$scale_divisor
    nr <- nrow(ex)
    for (row in 1:nr) {
      v <- ex[row,]
      if (all(!is.finite(v))) next
      v_clean <- v[is.finite(v)]
      if (!length(v_clean)) next
      mmin <- suppressWarnings(min(v_clean, na.rm = TRUE))
      p10 <- suppressWarnings(as.numeric(quantile(v_clean, 0.10, na.rm = TRUE, type = 7)))
      r3 <- suppressWarnings(roll_min(v, k = opt$roll_len))
      mask20 <- v < opt$thr1; mask50 <- v < opt$thr2
      frac20 <- mean(mask20, na.rm = TRUE); frac50 <- mean(mask50, na.rm = TRUE)
      run20 <- longest_run_circ(mask20); run50 <- longest_run_circ(mask50)
      p90 <- suppressWarnings(as.numeric(quantile(v_clean, 0.90, na.rm = TRUE, type = 7)))
      amp <- p90 - p10
      mu <- mean(v_clean); sdv <- sd(v_clean)
      cv <- ifelse(is.finite(mu) && mu != 0, sdv/mu, NA_real_)
      ii <- idx + row - 1
      feats$ai_month_min[ii] <- mmin
      feats$ai_month_p10[ii] <- p10
      feats$ai_roll3_min[ii] <- r3
      feats$ai_dry_frac_t020[ii] <- frac20
      feats$ai_dry_run_max_t020[ii] <- run20
      feats$ai_dry_frac_t050[ii] <- frac50
      feats$ai_dry_run_max_t050[ii] <- run50
      feats$ai_amp[ii] <- amp
      feats$ai_cv_month[ii] <- cv
    }
    cli::cli_alert_success("Completed chunk {chunk_start}-{chunk_end}")
    idx <- idx + nr
  }
  feats
}

# Helpers for features
roll_min <- function(x, k = 3) {
  # circular rolling mean then min
  n <- length(x)
  if (n < 1) return(NA_real_)
  x2 <- c(x, x[1:(k-1)])
  m <- sapply(1:n, function(i) mean(x2[i:(i+k-1)], na.rm = TRUE))
  min(m, na.rm = TRUE)
}
longest_run_circ <- function(mask) {
  # mask: logical length 12, TRUE when condition holds
  if (all(is.na(mask))) return(NA_integer_)
  mask[is.na(mask)] <- FALSE
  x <- c(mask, mask)  # double for circular
  max_run <- 0; cur <- 0
  for (i in seq_along(x)) {
    if (x[i]) { cur <- cur + 1; max_run <- max(max_run, cur) } else { cur <- 0 }
  }
  min(max_run, 12)
}

# Chunked extraction
coords <- as.matrix(occ_small[, c("lon","lat")])
n <- nrow(coords)
workers <- max(1, as.integer(opt$workers))
cli::cli_alert_info("Workers: {workers}; chunk_size: {opt$chunk_size}")

if (workers == 1) {
  features <- process_range(seq_len(n))
} else {
  # Split indices into roughly equal contiguous ranges
  bounds <- floor(seq(1, n+1, length.out = workers + 1))
  ranges <- lapply(seq_len(workers), function(i) seq(bounds[i], bounds[i+1]-1))
  cli::cli_alert_info("Parallel ranges prepared: {length(ranges)}")
  suppressWarnings({
    library(parallel)
    parts <- mclapply(ranges, process_range, mc.cores = workers)
  })
  features <- data.table::rbindlist(parts, use.names = TRUE, fill = TRUE)
}

# Aggregate to species level (median across unique coords)
ag <- features %>%
  group_by(species_occ) %>%
  summarise(
    ai_month_min = median(ai_month_min, na.rm = TRUE),
    ai_month_p10 = median(ai_month_p10, na.rm = TRUE),
    ai_roll3_min = median(ai_roll3_min, na.rm = TRUE),
    ai_dry_frac_t020 = median(ai_dry_frac_t020, na.rm = TRUE),
    ai_dry_run_max_t020 = median(ai_dry_run_max_t020, na.rm = TRUE),
    ai_dry_frac_t050 = median(ai_dry_frac_t050, na.rm = TRUE),
    ai_dry_run_max_t050 = median(ai_dry_run_max_t050, na.rm = TRUE),
    ai_amp = median(ai_amp, na.rm = TRUE),
    ai_cv_month = median(ai_cv_month, na.rm = TRUE),
    n_ai_m = sum(is.finite(ai_month_min)),
    .groups = "drop"
  )

# Merge into summary by normalized species name
bio$.__join <- normalize_species(bio[[opt$summary_species_col]])
ag$.__join <- normalize_species(ag$species_occ)

out <- bio %>% left_join(ag %>% select(-species_occ), by = ".__join") %>% select(-.__join)

# Write output
dir.create(dirname(opt$output_summary), recursive = TRUE, showWarnings = FALSE)
fwrite(out, opt$output_summary)
cli::cli_alert_success("Wrote augmented summary: {opt$output_summary}")
cli::cli_alert_info("Rows: {nrow(out)}, Cols: {ncol(out)}")
