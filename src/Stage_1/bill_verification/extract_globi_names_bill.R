#!/usr/bin/env Rscript
# Bill Shipley Verification: Extract GloBI plant names for WorldFlora matching
# Reads from canonical GloBI interactions parquet, outputs to shipley_checks

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

cat("Bill verification: Extracting GloBI plant names\n")
cat("Reading from canonical:", file.path(repo_root, "data/stage1/globi_interactions_plants.parquet"), "\n")

# Read GloBI plant interactions parquet
globi <- read_parquet("data/stage1/globi_interactions_plants.parquet")
cat("Loaded", nrow(globi), "GloBI plant interaction rows\n")

# Extract distinct plant names from both source and target
source_names <- unique(globi[globi$sourceTaxonKingdomName == "Plantae" &
                               !is.na(globi$sourceTaxonName) &
                               nchar(trimws(globi$sourceTaxonName)) > 0, "sourceTaxonName", drop = FALSE])
colnames(source_names) <- "SpeciesName"

target_names <- unique(globi[globi$targetTaxonKingdomName == "Plantae" &
                               !is.na(globi$targetTaxonName) &
                               nchar(trimws(globi$targetTaxonName)) > 0, "targetTaxonName", drop = FALSE])
colnames(target_names) <- "SpeciesName"

# Combine and deduplicate
all_names <- unique(rbind(source_names, target_names))

cat("Extracted", nrow(all_names), "unique plant names (source + target)\n")

# Output to Bill's verification folder
output_dir <- file.path(repo_root, "data/shipley_checks/wfo_verification")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
output_path <- file.path(output_dir, "globi_interactions_names_for_r.tsv")

write.table(all_names, output_path, sep = "\t", row.names = FALSE, quote = FALSE)
cat("Wrote name list to:", output_path, "\n")
cat("Done.\n")
