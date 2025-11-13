#!/usr/bin/env Rscript
# Bill Shipley Verification: Extract GloBI plant names for WorldFlora matching
# Reads from canonical GloBI interactions parquet, outputs to shipley_checks

# ========================================================================
# AUTO-DETECTING PATHS (works on Windows/Linux/Mac, any location)
# ========================================================================
get_repo_root <- function() {
  # First check if environment variable is set (from run_all_bill.R)
  env_root <- Sys.getenv("BILL_REPO_ROOT", unset = NA)
  if (!is.na(env_root) && env_root != "") {
    return(normalizePath(env_root))
  }

  # Otherwise detect from script path
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    # Navigate up from script to repo root
    # Scripts are in src/Stage_X/bill_verification/
    repo_root <- normalizePath(file.path(dirname(script_path), "..", "..", ".."))
  } else {
    # Fallback: assume current directory is repo root
    repo_root <- normalizePath(getwd())
  }
  return(repo_root)
}

repo_root <- get_repo_root()
INPUT_DIR <- file.path(repo_root, "input")
INTERMEDIATE_DIR <- file.path(repo_root, "intermediate")
OUTPUT_DIR <- file.path(repo_root, "output")

# Create output directories
dir.create(file.path(OUTPUT_DIR, "wfo_verification"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "stage3"), recursive = TRUE, showWarnings = FALSE)



library(arrow)

cat("Bill verification: Extracting GloBI plant names\n")
cat("Reading from canonical:", file.path(INPUT_DIR, "globi_interactions_plants.parquet"), "\n")

# Read GloBI plant interactions parquet
globi <- read_parquet(file.path(INPUT_DIR, "globi_interactions_plants.parquet"))
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
output_dir <- file.path(OUTPUT_DIR, "wfo_verification")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
output_path <- file.path(output_dir, "globi_interactions_names_for_r.tsv")

write.table(all_names, output_path, sep = "\t", row.names = FALSE, quote = FALSE)
cat("Wrote name list to:", output_path, "\n")
cat("Done.\n")
