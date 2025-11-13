#!/usr/bin/env Rscript
# Bill Shipley Verification: Extract TRY trait species names for WorldFlora matching
# Reads from canonical TRY traits parquet, outputs to shipley_checks

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

cat("Bill verification: Extracting TRY trait species names\n")
cat("Reading from canonical:", file.path(OUTPUT_DIR, file.path(INPUT_DIR, "try_selected_traits.parquet")), "\n")

# Read TRY traits parquet
try_traits <- read_parquet(file.path(INPUT_DIR, "try_selected_traits.parquet"))
cat("Loaded", nrow(try_traits), "TRY trait rows\n")

# Extract distinct AccSpeciesID, AccSpeciesName, SpeciesName
names_df <- unique(try_traits[!is.na(try_traits$AccSpeciesID),
                               c("AccSpeciesID", "AccSpeciesName", "SpeciesName")])

cat("Extracted", nrow(names_df), "unique species records\n")

# Output to Bill's verification folder
output_dir <- file.path(OUTPUT_DIR, "wfo_verification")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
output_path <- file.path(output_dir, "try_selected_traits_names_for_r.csv")

write.csv(names_df, output_path, row.names = FALSE)
cat("Wrote name list to:", output_path, "\n")
cat("Done.\n")
