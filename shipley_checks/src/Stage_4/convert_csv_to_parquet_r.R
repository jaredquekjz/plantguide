#!/usr/bin/env Rscript
#
# Convert CSV files to Parquet format (R version)
#
# This script converts all CSV files used by the R guild scorer to Parquet format
# using R's arrow package to ensure compatibility with R's data loading.
#
# Usage:
#   Rscript shipley_checks/src/Stage_4/convert_csv_to_parquet_r.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(glue)
})

cat("\n")
cat(strrep("=", 70), "\n")
cat("CSV to Parquet Conversion (R)\n")
cat(strrep("=", 70), "\n\n")

# Define file paths
files <- list(
  list(
    name = "Plants Dataset",
    csv = "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.csv",
    parquet = "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711_r.parquet"
  ),
  list(
    name = "Organism Profiles",
    csv = "shipley_checks/validation/organism_profiles_pure_r.csv",
    parquet = "shipley_checks/validation/organism_profiles_pure_r.parquet"
  ),
  list(
    name = "Fungal Guilds",
    csv = "shipley_checks/validation/fungal_guilds_pure_r.csv",
    parquet = "shipley_checks/validation/fungal_guilds_pure_r.parquet"
  ),
  list(
    name = "Herbivore Predators",
    csv = "shipley_checks/validation/herbivore_predators_pure_r.csv",
    parquet = "shipley_checks/validation/herbivore_predators_pure_r.parquet"
  ),
  list(
    name = "Insect Fungal Parasites",
    csv = "shipley_checks/validation/insect_fungal_parasites_pure_r.csv",
    parquet = "shipley_checks/validation/insect_fungal_parasites_pure_r.parquet"
  ),
  list(
    name = "Pathogen Antagonists",
    csv = "shipley_checks/validation/pathogen_antagonists_pure_r.csv",
    parquet = "shipley_checks/validation/pathogen_antagonists_pure_r.parquet"
  )
)

total_start <- Sys.time()

for (file_info in files) {
  cat(glue("Converting: {file_info$name}"), "\n")
  cat(glue("  CSV:     {file_info$csv}"), "\n")
  cat(glue("  Parquet: {file_info$parquet}"), "\n")

  # Check if CSV exists
  if (!file.exists(file_info$csv)) {
    cat(glue("  ERROR: CSV file not found\n\n"))
    next
  }

  # Load CSV
  load_start <- Sys.time()
  df <- read_csv_arrow(file_info$csv, as_data_frame = TRUE)
  load_time <- as.numeric(difftime(Sys.time(), load_start, units = "secs"))

  cat(glue("  Loaded:  {nrow(df)} rows × {ncol(df)} columns ({sprintf('%.3f', load_time * 1000)} ms)"), "\n")

  # Write Parquet with ZSTD compression
  write_start <- Sys.time()
  write_parquet(df, file_info$parquet, compression = "zstd")
  write_time <- as.numeric(difftime(Sys.time(), write_start, units = "secs"))

  # Get file sizes
  csv_size <- file.size(file_info$csv) / (1024 * 1024)
  parquet_size <- file.size(file_info$parquet) / (1024 * 1024)
  compression_ratio <- csv_size / parquet_size

  cat(glue("  Written: {sprintf('%.2f', parquet_size)} MB ({sprintf('%.3f', write_time * 1000)} ms)"), "\n")
  cat(glue("  CSV size: {sprintf('%.2f', csv_size)} MB"), "\n")
  cat(glue("  Compression: {sprintf('%.1fx', compression_ratio)}"), "\n\n")
}

total_time <- as.numeric(difftime(Sys.time(), total_start, units = "secs"))

cat(strrep("=", 70), "\n")
cat(glue("Total time: {sprintf('%.3f', total_time * 1000)} ms"), "\n")
cat(strrep("=", 70), "\n")
cat("\nParquet files ready for R pipeline.\n")
