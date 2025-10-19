#!/usr/bin/env Rscript

# Build the "cleaned" species_bioclim_summary.csv from the bioclim-first
# occurrence table, computing per-species means/SDs from unique coordinates.

.libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))

suppressPackageStartupMessages({
  library(data.table)
  library(cli)
  library(optparse)
})

option_list <- list(
  make_option(c("--occurrences_csv"), type="character",
              default = "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv",
              help = "Bioclim-first all_occurrences_cleaned.csv"),
  make_option(c("--output_summary"), type="character",
              default = "/home/olier/ellenberg/data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv",
              help = "Output cleaned species summary path"),
  make_option(c("--min_occ"), type="integer", default = 3,
              help = "Sufficiency threshold for has_sufficient_data (default 3)")
)

opt <- parse_args(OptionParser(option_list = option_list))

stop_with <- function(msg) { cli_alert_danger(msg); quit(status = 1) }
file.exists(opt$occurrences_csv) || stop_with(paste("Missing:", opt$occurrences_csv))

cli_h1("Rebuilding CLEANED species_bioclim_summary from bioclim-first")
cli_alert_info("Input: {opt$occurrences_csv}")
cli_alert_info("Output: {opt$output_summary}")

cols_needed <- c("species_clean","decimalLongitude","decimalLatitude",
                 paste0("bio", 1:19))
dt <- fread(opt$occurrences_csv, select = cols_needed, showProgress = TRUE)
setnames(dt, c("species","lon","lat", paste0("bio", 1:19)))

cli_alert_info("Rows loaded: {format(nrow(dt), big.mark=',')}")

# n_occurrences per species (all cleaned observations)
sp_counts <- dt[, .(n_occurrences = .N), by = species]

# Unique coords per species for environmental summaries
dt_u <- unique(dt, by = c("species","lon","lat"))
sp_unique_counts <- dt_u[, .(n_unique_coords = .N), by = species]

bio_cols <- grep("^bio[0-9]+$", names(dt_u), value = TRUE)

means_dt <- dt_u[, lapply(.SD, function(x) suppressWarnings(mean(x, na.rm = TRUE))),
                 .SDcols = bio_cols, by = species]
setnames(means_dt, old = bio_cols, new = paste0(bio_cols, "_mean"))

sds_dt   <- dt_u[, lapply(.SD, function(x) suppressWarnings(sd(x, na.rm = TRUE))),
                 .SDcols = bio_cols, by = species]
setnames(sds_dt,   old = bio_cols, new = paste0(bio_cols, "_sd"))

n_with_dt <- dt_u[, .(n_with_bioclim = sum(complete.cases(.SD))), .SDcols = bio_cols, by = species]

out <- Reduce(function(x,y) merge(x,y,by="species", all=TRUE),
              list(sp_counts, sp_unique_counts, means_dt, sds_dt, n_with_dt))

out[, has_sufficient_data := n_occurrences >= opt$min_occ]

dir.create(dirname(opt$output_summary), recursive = TRUE, showWarnings = FALSE)
fwrite(out, opt$output_summary)

cli_alert_success("Wrote cleaned summary: {opt$output_summary}")
cli_alert_info("Rows: {nrow(out)}  Cols: {ncol(out)}")

