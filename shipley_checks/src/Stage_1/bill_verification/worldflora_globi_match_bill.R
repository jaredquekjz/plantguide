#!/usr/bin/env Rscript
################################################################################
# Bill Shipley Verification: WorldFlora Matching for GloBI Dataset
################################################################################
# PURPOSE:
#   Matches GloBI (Global Biotic Interactions) plant names against WFO backbone.
#   GloBI contains species interaction data (pollination, herbivory, etc.).
#
# INPUTS:
#   - output/wfo_verification/globi_interactions_names_for_r.tsv
#   - input/classification.csv (WFO taxonomic backbone)
#
# OUTPUTS:
#   - output/wfo_verification/globi_interactions_wfo_worldflora.csv
#
# DATASET SPECIFICS:
#   - Uses SpeciesName (combined from source and target taxa)
#   - Expected output: ~74,002 matched records (±10)
#   - Progress counter set to 2000 due to large dataset size
################################################################################

# ========================================================================
# AUTO-DETECTING PATHS (works on Windows/Linux/Mac, any location)
# ========================================================================
get_repo_root <- function() {
  # First check if environment variable is set (from run_all_bill.R)
  # The master script sets BILL_REPO_ROOT for all child processes
  env_root <- Sys.getenv("BILL_REPO_ROOT", unset = NA)
  if (!is.na(env_root) && env_root != "") {
    return(normalizePath(env_root))
  }

  # Otherwise detect from script path using R's command-line arguments
  # This works when script is run via Rscript or source()
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    # Navigate up from script to repo root
    # Scripts are in src/Stage_X/bill_verification/
    # So we go up 3 levels: bill_verification -> Stage_X -> src -> repo_root
    repo_root <- normalizePath(file.path(dirname(script_path), "..", "..", ".."))
  } else {
    # Fallback: assume current directory is repo root
    # This is used when running interactively or in RStudio
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



cat("Starting WorldFlora matching for GloBI interactions dataset\n")
flush.console()

suppressPackageStartupMessages({
  library(data.table)
  library(WorldFlora)
})

log_msg <- function(...) {
  cat(..., "\n", sep = "")
  flush.console()
}

# ========================================================================
# DEFINE INPUT/OUTPUT PATHS
# ========================================================================
input_path <- file.path(OUTPUT_DIR, "wfo_verification/globi_interactions_names_for_r.tsv")
output_dir <- file.path(OUTPUT_DIR, "wfo_verification")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
output_path <- file.path(output_dir, "globi_interactions_wfo_worldflora.csv")
wfo_path <- file.path(INPUT_DIR, "classification.csv")

# ========================================================================
# STEP 1: LOAD AND PREPARE GLOBI NAMES
# ========================================================================
log_msg("Reading GloBI names from: ", input_path)
globi <- fread(input_path, encoding = "UTF-8", data.table = FALSE, sep = "\t")
log_msg("Loaded ", nrow(globi), " name rows")

# Extract SpeciesName (unified column from source/target taxa in extraction)
# GloBI names were combined from both interaction source and target organisms
# This column was created during the extraction phase (extract_all_names_bill.R)
globi$name_raw <- trimws(globi$SpeciesName)
# Filter out empty or NA names
globi <- globi[!is.na(globi$name_raw) & nchar(globi$name_raw) > 0, ]
log_msg("Retained ", nrow(globi), " rows with non-empty raw names")

# ========================================================================
# STEP 2: PREPARE NAMES FOR WFO MATCHING
# ========================================================================
log_msg("Preparing names with WFO.prepare()")
prep <- WFO.prepare(
  spec.data = globi,
  spec.full = "name_raw",
  squish = TRUE,
  spec.name.nonumber = TRUE,
  spec.name.sub = TRUE,
  verbose = FALSE
)
log_msg("Prepared names; resulting rows: ", nrow(prep))

# ========================================================================
# STEP 3: LOAD WFO TAXONOMIC BACKBONE
# ========================================================================
log_msg("Loading WFO backbone from: ", wfo_path)
wfo <- fread(
  wfo_path,
  sep = "\t",
  encoding = "Latin-1",
  data.table = FALSE,
  showProgress = TRUE
)
log_msg("WFO backbone rows: ", nrow(wfo))

# ========================================================================
# STEP 4: MATCH GLOBI NAMES AGAINST WFO BACKBONE
# ========================================================================
# Note: Counter set to 2000 (higher than default 1000) due to large dataset
# GloBI has ~74K unique names, so progress updates every 2000 records
log_msg("Running WFO.match() with exact matching (Fuzzy = 0)")
matches <- WFO.match(
  spec.data = prep,                    # Prepared names from WFO.prepare()
  WFO.data = wfo,                      # WFO taxonomic backbone
  acceptedNameUsageID.match = TRUE,    # Follow synonyms to accepted names
  Fuzzy = 0,                           # STRICT: no fuzzy matching (exact only)
  Fuzzy.force = FALSE,                 # Don't force fuzzy matching
  Fuzzy.two = TRUE,                    # Allow fuzzy on genus (not used with Fuzzy=0)
  Fuzzy.one = TRUE,                    # Allow fuzzy on species (not used with Fuzzy=0)
  verbose = TRUE,                      # Print matching progress
  counter = 2000                       # Progress update every 2000 records (larger dataset)
)
log_msg("Matched rows: ", nrow(matches))

# ========================================================================
# STEP 5: WRITE MATCHED RESULTS
# ========================================================================
log_msg("Writing results to: ", output_path)
fwrite(matches, output_path)
log_msg("Completed WorldFlora matching for GloBI dataset")
