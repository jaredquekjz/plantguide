#!/usr/bin/env Rscript
# Convert TRY Enhanced Species Means Excel to Parquet
# Source: data/Tryenhanced/Dataset/Species_mean_traits.xlsx
# Output: data/stage1/tryenhanced_species_original.parquet
# Method: R readxl + arrow (consistent with Bill's verification pipeline)

library(readxl)
library(arrow)

# Paths
WORKDIR <- "/home/olier/ellenberg"
INPUT_XLSX <- file.path(WORKDIR, "data/Tryenhanced/Dataset/Species_mean_traits.xlsx")
OUTPUT_PARQUET <- file.path(WORKDIR, "data/stage1/tryenhanced_species_original.parquet")

cat("Converting TRY Enhanced Excel to Parquet...\n")

# Read Excel file (all columns as character to preserve data)
df <- read_excel(INPUT_XLSX, col_types = "text")

cat(sprintf("Loaded %d rows × %d columns\n", nrow(df), ncol(df)))

# Write to parquet with snappy compression
write_parquet(df, OUTPUT_PARQUET, compression = "snappy")

cat(sprintf("Wrote: %s\n", OUTPUT_PARQUET))
cat("✓ Conversion complete\n")
