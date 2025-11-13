#!/usr/bin/env Rscript
# Bill Shipley Verification: Extract GBIF plant names for WorldFlora matching
# Reads from canonical GBIF occurrence parquet, outputs to shipley_checks

# ========================================================================
# AUTO-DETECTING PATHS (works on Windows/Linux/Mac, any location)
# ========================================================================
get_repo_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    # Navigate up from script to repo root
    # Scripts are in shipley_checks/src/Stage_X/bill_verification/
    repo_root <- normalizePath(file.path(dirname(script_path), "..", "..", ".."))
  } else {
    # Fallback: assume current directory is repo root
    repo_root <- normalizePath(getwd())
  }
  return(repo_root)
}

repo_root <- get_repo_root()
INPUT_DIR <- file.path(repo_root, "shipley_checks/input")
INTERMEDIATE_DIR <- file.path(repo_root, "shipley_checks/intermediate")
OUTPUT_DIR <- file.path(repo_root, "shipley_checks/output")

# Create output directories
dir.create(file.path(OUTPUT_DIR, "wfo_verification"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "stage3"), recursive = TRUE, showWarnings = FALSE)



library(arrow)

cat("Bill verification: Extracting GBIF plant names\n")
cat("Reading from canonical:", file.path(OUTPUT_DIR, file.path(INPUT_DIR, "gbif_occurrence_plantae.parquet")), "\n")

# Read GBIF occurrence parquet
gbif <- read_parquet(file.path(INPUT_DIR, "gbif_occurrence_plantae.parquet"))
cat("Loaded", nrow(gbif), "GBIF occurrence rows\n")

# Extract distinct scientificName
names_df <- unique(gbif[, "scientificName", drop = FALSE])
names_df <- names_df[!is.na(names_df$scientificName) & nchar(trimws(names_df$scientificName)) > 0, , drop = FALSE]
names_df <- data.frame(SpeciesName = names_df$scientificName, stringsAsFactors = FALSE)

cat("Extracted", nrow(names_df), "unique plant names\n")

# Output to Bill's verification folder
output_dir <- file.path(OUTPUT_DIR, "wfo_verification")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
output_path <- file.path(output_dir, "gbif_occurrence_names_for_r.tsv")

write.table(names_df, output_path, sep = "\t", row.names = FALSE, quote = FALSE)
cat("Wrote name list to:", output_path, "\n")
cat("Done.\n")
