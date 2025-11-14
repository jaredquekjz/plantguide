#!/usr/bin/env Rscript
################################################################################
# Bill Shipley Verification: WorldFlora Matching for TRY Traits Dataset
################################################################################
# PURPOSE:
#   Matches TRY selected traits plant names against WFO backbone.
#   TRY contains functional trait measurements for plant species.
#
# INPUTS:
#   - output/wfo_verification/try_selected_traits_names_for_r.csv
#   - input/classification.csv (WFO taxonomic backbone)
#
# OUTPUTS:
#   - output/wfo_verification/try_selected_traits_wfo_worldflora.csv
#
# DATASET SPECIFICS:
#   - Uses AccSpeciesName (preferred) or SpeciesName (fallback)
#   - Expected output: ~80,788 matched records (±10)
#   - Includes fallback logic for missing AccSpeciesName values
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



cat("Starting WorldFlora matching for TRY selected traits dataset\n")
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
input_path <- file.path(OUTPUT_DIR, "wfo_verification/try_selected_traits_names_for_r.csv")
output_dir <- file.path(OUTPUT_DIR, "wfo_verification")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
output_path <- file.path(output_dir, "try_selected_traits_wfo_worldflora.csv")
wfo_path <- file.path(INPUT_DIR, "classification.csv")

# ========================================================================
# STEP 1: LOAD AND PREPARE TRY TRAIT NAMES
# ========================================================================
log_msg("Reading TRY trait names from: ", input_path)
try_names <- fread(input_path, encoding = "UTF-8", data.table = FALSE)
log_msg("Loaded ", nrow(try_names), " name rows")

# Handle column name variation with preference order:
# 1. AccSpeciesName (accepted species name - preferred)
# 2. SpeciesName (original species name - fallback)
# TRY database distinguishes between accepted names (AccSpeciesName) and
# original submitted names (SpeciesName) which may contain synonyms
if ("AccSpeciesName" %in% names(try_names)) {
  log_msg("Using AccSpeciesName as primary raw name")
  try_names$name_raw <- trimws(try_names$AccSpeciesName)
} else if ("SpeciesName" %in% names(try_names)) {
  log_msg("AccSpeciesName missing, defaulting to SpeciesName")
  try_names$name_raw <- trimws(try_names$SpeciesName)
} else {
  # Stop with error if neither expected column is found
  stop("Input file must contain AccSpeciesName or SpeciesName column.")
}

# Fallback logic: use SpeciesName to fill any empty AccSpeciesName slots
# Some records may have SpeciesName but not AccSpeciesName populated
if ("SpeciesName" %in% names(try_names)) {
  fallback <- trimws(try_names$SpeciesName)
  # Identify rows where AccSpeciesName is missing or empty
  need_fallback <- is.na(try_names$name_raw) | nchar(try_names$name_raw) == 0
  # Fill those rows with SpeciesName values
  try_names$name_raw[need_fallback] <- fallback[need_fallback]
}

# Filter to non-empty names (final cleanup after all fallback logic)
try_names <- try_names[!is.na(try_names$name_raw) & nchar(try_names$name_raw) > 0, ]
log_msg("Retained ", nrow(try_names), " rows with non-empty raw names")

# ========================================================================
# STEP 2: PREPARE NAMES FOR WFO MATCHING
# ========================================================================
log_msg("Preparing names with WFO.prepare()")
prep <- WFO.prepare(
  spec.data = try_names,
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
# STEP 4: MATCH TRY TRAIT NAMES AGAINST WFO BACKBONE
# ========================================================================
log_msg("Running WFO.match() with exact matching (Fuzzy = 0)")
matches <- WFO.match(
  spec.data = prep,
  WFO.data = wfo,
  acceptedNameUsageID.match = TRUE,
  Fuzzy = 0,
  Fuzzy.force = FALSE,
  Fuzzy.two = TRUE,
  Fuzzy.one = TRUE,
  verbose = TRUE,
  counter = 1000
)
log_msg("Matched rows: ", nrow(matches))

# ========================================================================
# STEP 5: WRITE MATCHED RESULTS
# ========================================================================
log_msg("Writing results to: ", output_path)
fwrite(matches, output_path)
log_msg("Completed WorldFlora matching for TRY selected traits dataset")
