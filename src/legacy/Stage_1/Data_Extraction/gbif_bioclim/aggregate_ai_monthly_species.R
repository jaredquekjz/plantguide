#!/usr/bin/env Rscript

# Aggregate monthly AI per-coordinate values into species-level dryness features.

.libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))

suppressPackageStartupMessages({
  library(optparse)
  library(data.table)
  library(dplyr)
  library(cli)
})

option_list <- list(
  make_option(c("--parts_dir"), type="character",
              default = "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first",
              help = "Directory containing ai_monthly_coords_part_*.csv files"),
  make_option(c("--input_summary"), type="character",
              default = "/home/olier/ellenberg/data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv",
              help = "Base species bioclim summary CSV"),
  make_option(c("--output_summary"), type="character",
              default = "/home/olier/ellenberg/data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv",
              help = "Output augmented summary CSV")
)

opt <- parse_args(OptionParser(option_list = option_list))

stop_with <- function(msg) { cli::cli_alert_danger(msg); quit(status = 1) }

if (!dir.exists(opt$parts_dir)) stop_with(paste("Missing parts_dir", opt$parts_dir))
if (!file.exists(opt$input_summary)) stop_with(paste("Missing input_summary", opt$input_summary))

files <- list.files(opt$parts_dir, pattern = "^ai_monthly_coords_part_.*of[0-9]+\\.csv$", full.names = TRUE)
if (length(files) == 0) stop_with("No part files found; run extraction first")

cli::cli_h1("Aggregate monthly AI to species features")
cli::cli_alert_info("Parts: {length(files)} files from {opt$parts_dir}")

# Helper functions
roll_min <- function(x, k = 3) {
  n <- length(x)
  if (n < 1) return(NA_real_)
  x2 <- c(x, x[1:(k-1)])
  m <- sapply(1:n, function(i) mean(x2[i:(i+k-1)], na.rm = TRUE))
  min(m, na.rm = TRUE)
}
longest_run_circ <- function(mask) {
  if (all(is.na(mask))) return(NA_integer_)
  mask[is.na(mask)] <- FALSE
  x <- c(mask, mask)
  max_run <- 0; cur <- 0
  for (i in seq_along(x)) { if (x[i]) { cur <- cur + 1; max_run <- max(max_run, cur) } else { cur <- 0 } }
  min(max_run, 12)
}

calc_row_feats <- function(row) {
  v <- as.numeric(row)
  if (all(!is.finite(v))) return(c(rep(NA_real_, 8)))
  v_clean <- v[is.finite(v)]
  if (!length(v_clean)) return(c(rep(NA_real_, 8)))
  mmin <- suppressWarnings(min(v_clean))
  p10  <- suppressWarnings(as.numeric(quantile(v_clean, 0.10, type = 7)))
  r3   <- suppressWarnings(roll_min(v, 3))
  mask20 <- v < 0.20; mask50 <- v < 0.50
  frac20 <- mean(mask20, na.rm = TRUE); frac50 <- mean(mask50, na.rm = TRUE)
  run20  <- longest_run_circ(mask20); run50  <- longest_run_circ(mask50)
  p90  <- suppressWarnings(as.numeric(quantile(v_clean, 0.90, type = 7)))
  amp  <- p90 - p10
  mu <- mean(v_clean); sdv <- sd(v_clean)
  cv <- ifelse(is.finite(mu) && mu != 0, sdv/mu, NA_real_)
  c(mmin, p10, r3, frac20, run20, frac50, run50, amp, cv)
}

feat_names <- c("ai_month_min","ai_month_p10","ai_roll3_min",
                "ai_dry_frac_t020","ai_dry_run_max_t020",
                "ai_dry_frac_t050","ai_dry_run_max_t050",
                "ai_amp","ai_cv_month")

species_rows <- list()
total_rows <- 0L
for (f in files) {
  cli::cli_alert_info("Reading {basename(f)} ...")
  dt <- fread(f)
  # Expect columns: species, lon, lat, ai_m01..ai_m12
  mcols <- grep("^ai_m[0-9]{2}$", names(dt), value = TRUE)
  if (length(mcols) != 12) stop_with(paste("Expected 12 ai_mXX columns in", f))
  # Compute per-row features
  mat <- as.matrix(dt[, ..mcols])
  feats <- t(apply(mat, 1, calc_row_feats))
  feats_dt <- as.data.table(feats)
  setnames(feats_dt, feat_names)
  part <- cbind(dt[, .(species)], feats_dt)
  species_rows[[length(species_rows) + 1L]] <- part
  total_rows <- total_rows + nrow(part)
  cli::cli_alert_success("Processed {nrow(part)} rows from {basename(f)} (total {format(total_rows,big.mark=',')})")
}

all_rows <- rbindlist(species_rows, use.names = TRUE, fill = TRUE)

cli::cli_alert_info("Aggregating to species medians...")
ag <- all_rows %>% group_by(species) %>% summarise(
  ai_month_min = median(ai_month_min, na.rm = TRUE),
  ai_month_p10 = median(ai_month_p10, na.rm = TRUE),
  ai_roll3_min = median(ai_roll3_min, na.rm = TRUE),
  ai_dry_frac_t020 = median(ai_dry_frac_t020, na.rm = TRUE),
  ai_dry_run_max_t020 = median(ai_dry_run_max_t020, na.rm = TRUE),
  ai_dry_frac_t050 = median(ai_dry_frac_t050, na.rm = TRUE),
  ai_dry_run_max_t050 = median(ai_dry_run_max_t050, na.rm = TRUE),
  ai_amp = median(ai_amp, na.rm = TRUE),
  ai_cv_month = median(ai_cv_month, na.rm = TRUE),
  n_ai_m = sum(!is.na(ai_month_min)),
  .groups = "drop"
)


# Prepare for merge (avoid tibble/data.table bracket gotchas)
bio <- as.data.table(fread(opt$input_summary))
bio[, species_norm := tolower(gsub("[[:space:]]+|_+", "_", species))]
ag_dt <- as.data.table(ag)
ag_dt[, species_norm := tolower(gsub("[[:space:]]+|_+", "_", species))]
ag_dt[, species := NULL]

out <- merge(bio, ag_dt, by = "species_norm", all.x = TRUE)
out[, species_norm := NULL]

dir.create(dirname(opt$output_summary), recursive = TRUE, showWarnings = FALSE)
fwrite(out, opt$output_summary)
cli::cli_alert_success("Wrote augmented summary: {opt$output_summary}")
cli::cli_alert_info("Rows: {nrow(out)}, Cols: {ncol(out)}")
