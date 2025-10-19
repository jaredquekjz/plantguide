#!/usr/bin/env Rscript

# Extract monthly Aridity Index (AI = P/PET) at unique (species, lon, lat) coordinates
# and write plain CSV part files for later aggregation.

.libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))

suppressPackageStartupMessages({
  library(optparse)
  library(data.table)
  library(terra)
  library(cli)
})

option_list <- list(
  make_option(c("--ai_month_dir"), type = "character",
              default = "/home/olier/ellenberg/data/PET/Global_AI__monthly_v3_1/Global_AI__monthly_v3_1",
              help = "Directory with ai_v31_01.tif..ai_v31_12.tif"),
  make_option(c("--occurrences_csv"), type = "character",
              default = "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654.csv",
              help = "Occurrences CSV (will be deduped by species+lon+lat)"),
  make_option(c("--species_col"), type = "character", default = "species_clean",
              help = "Species column name in occurrences"),
  make_option(c("--lon_col"), type = "character", default = "decimalLongitude",
              help = "Longitude column name in occurrences"),
  make_option(c("--lat_col"), type = "character", default = "decimalLatitude",
              help = "Latitude column name in occurrences"),
  make_option(c("--out_prefix"), type = "character",
              default = "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/ai_monthly_coords_part",
              help = "Output CSV prefix; part files will be suffixed with _<id>of<k>.csv"),
  make_option(c("--scale_divisor"), type = "double", default = 10000,
              help = "Divisor to scale UInt16 to dimensionless AI (default 10000)"),
  make_option(c("--chunk_size"), type = "integer", default = 80000,
              help = "Per-process extraction chunk size (default 80k)"),
  make_option(c("--num_shards"), type = "integer", default = 8,
              help = "Total number of shards (parallel processes)"),
  make_option(c("--shard_id"), type = "integer", default = 1,
              help = "This shard id (1..num_shards)")
)

opt <- parse_args(OptionParser(option_list = option_list))

stop_with <- function(msg) { cli::cli_alert_danger(msg); quit(status = 1) }

if (!dir.exists(opt$ai_month_dir)) stop_with(paste("Missing ai_month_dir", opt$ai_month_dir))
if (!file.exists(opt$occurrences_csv)) stop_with(paste("Missing occurrences_csv", opt$occurrences_csv))
if (opt$shard_id < 1 || opt$num_shards < 1 || opt$shard_id > opt$num_shards) {
  stop_with("Invalid shard settings: shard_id must be in 1..num_shards")
}

files <- list.files(opt$ai_month_dir, pattern = "^ai_v31_([0-9]{2})\\.tif$", full.names = TRUE)
if (length(files) != 12) stop_with(sprintf("Expected 12 monthly AI tifs, found %d", length(files)))
ord <- order(as.integer(sub("^.*ai_v31_([0-9]{2})\\.tif$", "\\1", basename(files))))
files <- files[ord]

cli::cli_h1("Monthly AI extraction — coords to CSV (sharded)")
cli::cli_alert_info("ai_month_dir: {opt$ai_month_dir}")
cli::cli_alert_info("occurrences:  {opt$occurrences_csv}")
cli::cli_alert_info("shard {opt$shard_id} of {opt$num_shards}; chunk_size={opt$chunk_size}")

# Load and deduplicate coords
dt <- fread(opt$occurrences_csv, select = c(opt$species_col, opt$lon_col, opt$lat_col))
setnames(dt, c("species", "lon", "lat"))
dt <- unique(dt, by = c("species", "lon", "lat"))
n_all <- nrow(dt)
cli::cli_alert_info("Unique coords total: {format(n_all, big.mark=',')}")

# Select shard rows
dt[, rid := .I]
dt_shard <- dt[(rid - 1L) %% opt$num_shards + 1L == opt$shard_id]
dt_shard[, rid := NULL]
n <- nrow(dt_shard)
if (n == 0) stop_with("No rows in this shard (check num_shards/shard_id)")
cli::cli_alert_info("Shard rows: {format(n, big.mark=',')}")

# Build raster stack
terraOptions(progress = 1, memfrac = 0.6)
r <- rast(files)
names(r) <- sprintf("ai_m%02d", 1:12)

# Prepare output
out_file <- sprintf("%s_%02dof%02d.csv", opt$out_prefix, opt$shard_id, opt$num_shards)
header_written <- file.exists(out_file) && file.info(out_file)$size > 0

# Extraction loop
chunk <- max(10000, min(opt$chunk_size, n))
idx <- 1L
start_time <- Sys.time()
while (idx <= n) {
  j <- min(n, idx + chunk - 1L)
  cli::cli_alert_info("Extracting rows {idx}-{j} / {n}")
  ex <- tryCatch({
    extract(r, as.matrix(dt_shard[idx:j, .(lon, lat)]))
  }, error = function(e) {
    cli::cli_alert_warning("Extract failed on {idx}-{j}: {e$message}; retry half chunk")
    j2 <- idx + floor((j - idx + 1L)/2) - 1L
    extract(r, as.matrix(dt_shard[idx:j2, .(lon, lat)]))
  })
  if ("ID" %in% names(ex)) ex <- ex[, -1, drop = FALSE]
  ex <- as.data.table(ex) / opt$scale_divisor
  out_dt <- cbind(dt_shard[idx:(idx + nrow(ex) - 1L), .(species, lon, lat)], ex)
  fwrite(out_dt, out_file, append = header_written, col.names = !header_written)
  header_written <- TRUE
  idx <- idx + nrow(ex)
}

elapsed <- as.numeric(Sys.time() - start_time, units = "mins")
cli::cli_alert_success("Shard {opt$shard_id}/{opt$num_shards} complete: {out_file} in {round(elapsed,1)} min")

