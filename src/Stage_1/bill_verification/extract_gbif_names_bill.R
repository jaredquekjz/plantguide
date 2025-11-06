#!/usr/bin/env Rscript
# Bill Shipley Verification: Extract GBIF plant names for WorldFlora matching
# Reads from canonical GBIF occurrence parquet, outputs to shipley_checks

library(arrow)

args <- commandArgs(trailingOnly = FALSE)
file_arg_idx <- grep("^--file=", args)
if (length(file_arg_idx) == 0) {
  script_dir <- getwd()
} else {
  script_path <- sub("^--file=", "", args[file_arg_idx[length(file_arg_idx)]])
  script_dir <- dirname(normalizePath(script_path))
}
repo_root <- normalizePath(file.path(script_dir, "..", "..", ".."), winslash = "/", mustWork = TRUE)
setwd(repo_root)

cat("Bill verification: Extracting GBIF plant names\n")
cat("Reading from canonical:", file.path(repo_root, "data/gbif/occurrence_plantae.parquet"), "\n")

# Read GBIF occurrence parquet
gbif <- read_parquet("data/gbif/occurrence_plantae.parquet")
cat("Loaded", nrow(gbif), "GBIF occurrence rows\n")

# Extract distinct scientificName
names_df <- unique(gbif[, "scientificName", drop = FALSE])
names_df <- names_df[!is.na(names_df$scientificName) & nchar(trimws(names_df$scientificName)) > 0, , drop = FALSE]
names_df <- data.frame(SpeciesName = names_df$scientificName, stringsAsFactors = FALSE)

cat("Extracted", nrow(names_df), "unique plant names\n")

# Output to Bill's verification folder
output_dir <- file.path(repo_root, "data/shipley_checks/wfo_verification")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
output_path <- file.path(output_dir, "gbif_occurrence_names_for_r.tsv")

write.table(names_df, output_path, sep = "\t", row.names = FALSE, quote = FALSE)
cat("Wrote name list to:", output_path, "\n")
cat("Done.\n")
