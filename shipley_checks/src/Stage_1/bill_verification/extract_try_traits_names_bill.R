#!/usr/bin/env Rscript
# Bill Shipley Verification: Extract TRY trait species names for WorldFlora matching
# Reads from canonical TRY traits parquet, outputs to shipley_checks

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

cat("Bill verification: Extracting TRY trait species names\n")
cat("Reading from canonical:", file.path(repo_root, "data/stage1/try_selected_traits.parquet"), "\n")

# Read TRY traits parquet
try_traits <- read_parquet("data/stage1/try_selected_traits.parquet")
cat("Loaded", nrow(try_traits), "TRY trait rows\n")

# Extract distinct AccSpeciesID, AccSpeciesName, SpeciesName
names_df <- unique(try_traits[!is.na(try_traits$AccSpeciesID),
                               c("AccSpeciesID", "AccSpeciesName", "SpeciesName")])

cat("Extracted", nrow(names_df), "unique species records\n")

# Output to Bill's verification folder
output_dir <- file.path(repo_root, "data/shipley_checks/wfo_verification")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
output_path <- file.path(output_dir, "try_selected_traits_names_for_r.csv")

write.csv(names_df, output_path, row.names = FALSE)
cat("Wrote name list to:", output_path, "\n")
cat("Done.\n")
