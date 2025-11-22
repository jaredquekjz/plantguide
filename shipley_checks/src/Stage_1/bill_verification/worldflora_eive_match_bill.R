#!/usr/bin/env Rscript
################################################################################
# Bill Shipley Verification: WorldFlora Matching for EIVE Dataset
################################################################################
# PURPOSE:
#   Matches EIVE (Ellenberg Indicator Values) plant names against WFO backbone.
#   EIVE provides ecological indicator values for European plant species.
#
# INPUTS:
#   - output/wfo_verification/eive_names_for_r.csv
#   - input/classification.csv (WFO taxonomic backbone)
#
# OUTPUTS:
#   - output/wfo_verification/eive_wfo_worldflora.csv
#
# DATASET SPECIFICS:
#   - Uses TaxonConcept as primary name field
#   - Expected output: ~14,835 matched records (±10)
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



cat("Starting WorldFlora matching for EIVE dataset\n")
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
input_path <- file.path(OUTPUT_DIR, "wfo_verification/eive_names_for_r.csv")
output_dir <- file.path(OUTPUT_DIR, "wfo_verification")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
output_path <- file.path(output_dir, "eive_wfo_worldflora.csv")
wfo_path <- file.path(INPUT_DIR, "classification.csv")

# ========================================================================
# STEP 1: LOAD AND PREPARE EIVE NAMES
# ========================================================================
log_msg("Reading EIVE names from: ", input_path)
eive <- fread(input_path, encoding = "UTF-8", data.table = FALSE)
log_msg("Loaded ", nrow(eive), " name rows")

# Extract TaxonConcept as the raw name field (EIVE's primary name field)
# EIVE uses TaxonConcept for the full scientific name
# trimws() removes leading/trailing whitespace for clean matching
eive$name_raw <- trimws(eive$TaxonConcept)
# Filter out empty or NA names (ensures all rows have valid input for matching)
eive <- eive[!is.na(eive$name_raw) & nchar(eive$name_raw) > 0, ]
log_msg("Retained ", nrow(eive), " rows with non-empty raw names")

# ========================================================================
# STEP 2: PREPARE NAMES FOR WFO MATCHING
# ========================================================================
log_msg("Preparing names with WFO.prepare()")
prep <- WFO.prepare(
  spec.data = eive,
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
  sep = "\t",                          # Tab-separated values (TSV format)
  encoding = "Latin-1",                # Latin-1 encoding handles special characters in botanical names
  data.table = FALSE,                  # Return as data.frame for compatibility with WorldFlora
  showProgress = TRUE                  # Show progress bar for large file loading
)
log_msg("WFO backbone rows: ", nrow(wfo))

# ========================================================================
# STEP 4: MATCH EIVE NAMES AGAINST WFO BACKBONE
# ========================================================================
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
  counter = 1000                       # Progress update frequency
)
log_msg("Matched rows: ", nrow(matches))

# ========================================================================
# STEP 5: WRITE MATCHED RESULTS
# ========================================================================
log_msg("Writing results to: ", output_path)
fwrite(matches, output_path)
log_msg("Completed WorldFlora matching for EIVE dataset")
