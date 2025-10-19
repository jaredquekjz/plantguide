#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  .libPaths(c('/home/olier/ellenberg/.Rlib', .libPaths()))

  library(optparse)
  library(DBI)
  library(duckdb)
  library(data.table)
  library(arrow)
  library(terra)
})

option_list <- list(
  make_option("--dataset", type = "character", help = "Dataset to sample: worldclim, soilgrids, agroclim"),
  make_option("--chunk-size", type = "integer", default = 500000,
              help = "Number of occurrence rows per chunk [default %default]")
)

opt <- parse_args(OptionParser(option_list = option_list))

valid_datasets <- c("worldclim", "soilgrids", "agroclim")
if (is.null(opt$dataset) || !(opt$dataset %in% valid_datasets)) {
  stop("--dataset must be one of: ", paste(valid_datasets, collapse = ", "))
}

if (is.na(opt$`chunk-size`) || opt$`chunk-size` <= 0) {
  stop("--chunk-size must be a positive integer")
}

dataset <- opt$dataset
chunk_size <- opt$`chunk-size`

WORKDIR <- "/home/olier/ellenberg"
shortlist_path <- file.path(WORKDIR, "data/stage1/stage1_shortlist_with_gbif.parquet")
occurrence_path <- file.path(WORKDIR, "data/gbif/occurrence_plantae_wfo.parquet")

paths <- list(
  worldclim = list(
    raster_dir = file.path(WORKDIR, "data/worldclim_uncompressed"),
    output_occ = file.path(WORKDIR, "data/stage1/worldclim_occ_samples.parquet"),
    output_sum = file.path(WORKDIR, "data/stage1/worldclim_species_summary.parquet"),
    log_path    = file.path(WORKDIR, "dump/worldclim_samples.log")
  ),
  soilgrids = list(
    raster_dir = file.path(WORKDIR, "data/soilgrids_250m_global"),
    output_occ = file.path(WORKDIR, "data/stage1/soilgrids_occ_samples.parquet"),
    output_sum = file.path(WORKDIR, "data/stage1/soilgrids_species_summary.parquet"),
    log_path    = file.path(WORKDIR, "dump/soilgrids_samples.log")
  ),
  agroclim = list(
    raster_dir = file.path(WORKDIR, "data/agroclime_mean"),
    output_occ = file.path(WORKDIR, "data/stage1/agroclime_occ_samples.parquet"),
    output_sum = file.path(WORKDIR, "data/stage1/agroclime_species_summary.parquet"),
    log_path    = file.path(WORKDIR, "dump/agroclime_samples.log")
  )
)

cfg <- paths[[dataset]]

log_message <- function(text) {
  cat(text, "\n")
  write(text, file = cfg$log_path, append = TRUE)
}

# initialise log
dir.create(dirname(cfg$log_path), recursive = TRUE, showWarnings = FALSE)
write("", file = cfg$log_path)

log_message(sprintf("=== Sampling %s rasters (terra) ===", dataset))
log_message(sprintf("Chunk size: %s", format(chunk_size, big.mark = ",")))

# remove previous outputs
if (file.exists(cfg$output_occ)) file.remove(cfg$output_occ)
if (file.exists(cfg$output_sum)) file.remove(cfg$output_sum)

# helper to discover rasters
discover_rasters <- function(root_dir, pattern = "\\.tif$") {
  files <- list.files(root_dir, pattern = pattern, full.names = TRUE, recursive = TRUE)
  if (length(files) == 0) {
    stop("No raster files found in ", root_dir)
  }
  files
}

raster_files <- discover_rasters(cfg$raster_dir)

if (dataset %in% c('worldclim', 'agroclim')) {
  raster_stack <- rast(raster_files)
  names(raster_stack) <- make.names(names(raster_stack), unique = TRUE)
  raster_cols <- names(raster_stack)
  log_message(sprintf("Loaded %d rasters from %s", length(raster_files), cfg$raster_dir))
} else if (dataset == 'soilgrids') {
  props <- c('phh2o','soc','clay','sand','cec','nitrogen','bdod')
  depths <- c('0-5cm','5-15cm','15-30cm','30-60cm','60-100cm','100-200cm')
  scaling <- list(phh2o = 10, soc = 10, clay = 10, sand = 10, cec = 10, nitrogen = 100, bdod = 100)
  soil_layers <- list()
  for (prop in props) {
    for (depth in depths) {
      pattern <- sprintf('%s_%s_global_250m.tif$', prop, depth)
      match <- raster_files[grepl(pattern, basename(raster_files))]
      if (length(match) == 1) {
        layer_name <- paste0(prop, '_', gsub('-', '_', depth))
        soil_layers[[layer_name]] <- list(rast = rast(match), scale = scaling[[prop]])
      }
    }
  }
  if (length(soil_layers) == 0) {
    stop('No SoilGrids rasters found with expected naming convention in ', cfg$raster_dir)
  }
  raster_cols <- names(soil_layers)
  log_message(sprintf('Prepared %d SoilGrids layers from %s', length(soil_layers), cfg$raster_dir))
} else {
  stop('Unsupported dataset: ', dataset)
}

# connect to DuckDB
con <- dbConnect(duckdb())

dbExecute(con, sprintf("
  CREATE OR REPLACE TEMP TABLE species_target AS
  SELECT DISTINCT wfo_taxon_id
  FROM read_parquet('%s')
  WHERE gbif_occurrence_count >= 30
", shortlist_path))

species_count <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM species_target")$n
if (species_count == 0) {
  log_message("No species meet the >=30 GBIF occurrence threshold. Exiting.")
  dbDisconnect(con, shutdown = TRUE)
  quit(status = 0)
}
log_message(sprintf("Target species: %d", species_count))

dbExecute(con, sprintf("
  CREATE OR REPLACE TEMP TABLE target_occ AS
  SELECT
    o.wfo_taxon_id,
    o.gbifID,
    o.decimalLongitude AS lon,
    o.decimalLatitude AS lat
  FROM read_parquet('%s') o
  JOIN species_target s USING (wfo_taxon_id)
  WHERE o.decimalLongitude IS NOT NULL
    AND o.decimalLatitude IS NOT NULL
", occurrence_path))

total_occ <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM target_occ")$n
if (total_occ == 0) {
  log_message("No valid occurrences found after filtering. Exiting.")
  dbDisconnect(con, shutdown = TRUE)
  quit(status = 0)
}
log_message(sprintf("Filtered occurrence rows: %s", format(total_occ, big.mark = ",")))

n_chunks <- ceiling(total_occ / chunk_size)
log_message(sprintf("Sampling in %d chunks...", n_chunks))

terraOptions(progress = 0)
output_table <- paste0('occ_output_', dataset)

for (idx in seq_len(n_chunks)) {
  offset <- (idx - 1) * chunk_size
  query <- sprintf("
    SELECT wfo_taxon_id, gbifID, lon, lat
    FROM target_occ
    ORDER BY wfo_taxon_id, gbifID
    LIMIT %d OFFSET %d
  ", chunk_size, offset)
  chunk <- dbGetQuery(con, query)

  if (!nrow(chunk)) {
    break
  }

  dt_chunk <- as.data.table(chunk)
  dt_chunk[, row_id := .I]

  unique_coords <- unique(dt_chunk[, .(lon, lat)])
  coord_matrix <- as.matrix(unique_coords[, .(lon, lat)])

  if (dataset %in% c('worldclim', 'agroclim')) {
    extract_vals <- terra::extract(raster_stack, coord_matrix)
    if (is.data.frame(extract_vals) && 'ID' %in% names(extract_vals)) {
      extract_vals[['ID']] <- NULL
    }
    extract_dt <- as.data.table(extract_vals)
    unique_coords <- cbind(unique_coords, extract_dt)
  } else if (dataset == 'soilgrids') {
    values_dt <- copy(unique_coords)
    for (layer_name in raster_cols) {
      layer <- soil_layers[[layer_name]]
      vals <- terra::extract(layer$rast, coord_matrix)
      if (is.data.frame(vals)) {
        vals <- vals[[1]]
      }
      values_dt[[layer_name]] <- vals / layer$scale
    }
    unique_coords <- values_dt
  }

  dt_chunk <- merge(dt_chunk, unique_coords, by = c('lon', 'lat'), all.x = TRUE, sort = FALSE)
  setorder(dt_chunk, row_id)
  dt_chunk[, row_id := NULL]

  if (idx == 1) {
    dbWriteTable(con, output_table, as.data.frame(dt_chunk), overwrite = TRUE)
  } else {
    dbWriteTable(con, output_table, as.data.frame(dt_chunk), append = TRUE)
  }

  processed <- min(idx * chunk_size, total_occ)
  pct <- processed / total_occ * 100
  log_message(sprintf('Chunk %d/%d processed (%s/%s, %.2f%%)',
                      idx, n_chunks,
                      format(processed, big.mark = ','),
                      format(total_occ, big.mark = ','),
                      pct))
}
dbExecute(con, sprintf("COPY %s TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)", output_table, cfg$output_occ))
dbExecute(con, sprintf('DROP TABLE %s', output_table))
dbDisconnect(con, shutdown = TRUE)

# Aggregate per species using DuckDB
con <- dbConnect(duckdb())

select_parts <- c("wfo_taxon_id")
quote_ident <- function(x) sprintf('"%s"', gsub('"', '""', x))

for (col in raster_cols) {
  col_q <- quote_ident(col)
  select_parts <- c(select_parts,
                    sprintf("AVG(%s) AS %s", col_q, quote_ident(paste0(col, "_avg"))),
                    sprintf("STDDEV_SAMP(%s) AS %s", col_q, quote_ident(paste0(col, "_stddev"))),
                    sprintf("MIN(%s) AS %s", col_q, quote_ident(paste0(col, "_min"))),
                    sprintf("MAX(%s) AS %s", col_q, quote_ident(paste0(col, "_max"))))
}
agg_sql <- sprintf("
  SELECT %s
  FROM read_parquet('%s')
  GROUP BY wfo_taxon_id
  ORDER BY wfo_taxon_id
", paste(select_parts, collapse = ",\n"), cfg$output_occ)

agg_result <- dbGetQuery(con, agg_sql)
arrow::write_parquet(arrow::arrow_table(as.data.table(agg_result)), cfg$output_sum)

dbDisconnect(con, shutdown = TRUE)

log_message("Aggregation complete.")
log_message(sprintf("Occurrence samples: %s", cfg$output_occ))
log_message(sprintf("Species summaries: %s", cfg$output_sum))
log_message("=== Sampling complete ===")
