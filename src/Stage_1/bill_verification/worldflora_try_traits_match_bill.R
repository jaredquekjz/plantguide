#!/usr/bin/env Rscript

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


input_path <- file.path(OUTPUT_DIR, "wfo_verification/try_selected_traits_names_for_r.csv")
output_dir <- file.path(OUTPUT_DIR, "wfo_verification")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
output_path <- file.path(output_dir, "try_selected_traits_wfo_worldflora.csv")
wfo_path <- file.path(INPUT_DIR, "classification.csv")

log_msg("Reading TRY trait names from: ", input_path)
try_names <- fread(input_path, encoding = "UTF-8", data.table = FALSE)
log_msg("Loaded ", nrow(try_names), " name rows")

if ("AccSpeciesName" %in% names(try_names)) {
  log_msg("Using AccSpeciesName as primary raw name")
  try_names$name_raw <- trimws(try_names$AccSpeciesName)
} else if ("SpeciesName" %in% names(try_names)) {
  log_msg("AccSpeciesName missing, defaulting to SpeciesName")
  try_names$name_raw <- trimws(try_names$SpeciesName)
} else {
  stop("Input file must contain AccSpeciesName or SpeciesName column.")
}

if ("SpeciesName" %in% names(try_names)) {
  fallback <- trimws(try_names$SpeciesName)
  need_fallback <- is.na(try_names$name_raw) | nchar(try_names$name_raw) == 0
  try_names$name_raw[need_fallback] <- fallback[need_fallback]
}

try_names <- try_names[!is.na(try_names$name_raw) & nchar(try_names$name_raw) > 0, ]
log_msg("Retained ", nrow(try_names), " rows with non-empty raw names")

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
log_msg("Completed WorldFlora matching for TRY selected traits dataset")
