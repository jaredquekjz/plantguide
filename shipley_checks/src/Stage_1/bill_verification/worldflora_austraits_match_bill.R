#!/usr/bin/env Rscript

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



cat("Starting WorldFlora matching for AusTraits dataset\n")
flush.console()

suppressPackageStartupMessages({
  library(data.table)
  library(WorldFlora)
})

log_msg <- function(...) {
  cat(..., "\n", sep = "")
  flush.console()
}


input_path <- file.path(OUTPUT_DIR, "data/shipley_checks/wfo_verification/austraits_names_for_r.csv")
output_dir <- file.path(OUTPUT_DIR, "wfo_verification")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
output_path <- file.path(output_dir, "austraits_wfo_worldflora.csv")
wfo_path <- file.path(OUTPUT_DIR, file.path(INPUT_DIR, "classification.csv"))

log_msg("Reading AusTraits names from: ", input_path)
names_dt <- fread(input_path, encoding = "UTF-8", data.table = FALSE)
log_msg("Loaded ", nrow(names_dt), " name rows")

names_dt$name_raw <- trimws(names_dt$taxon_name)
names_dt <- names_dt[!is.na(names_dt$name_raw) & nchar(names_dt$name_raw) > 0, ]
log_msg("Retained ", nrow(names_dt), " rows with non-empty raw names")

log_msg("Preparing names with WFO.prepare()")
prep <- WFO.prepare(
  spec.data = names_dt,
  spec.full = "name_raw",
  squish = TRUE,
  spec.name.nonumber = TRUE,
  spec.name.sub = TRUE,
  verbose = FALSE
)
log_msg("Prepared names; resulting rows: ", nrow(prep))

log_msg("Loading WFO backbone from: ", wfo_path)
wfo <- fread(
  wfo_path,
  sep = "\t",
  encoding = "Latin-1",
  data.table = FALSE,
  showProgress = TRUE
)
log_msg("WFO backbone rows: ", nrow(wfo))

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

log_msg("Writing results to: ", output_path)
fwrite(matches, output_path)
log_msg("Completed WorldFlora matching for AusTraits dataset")
