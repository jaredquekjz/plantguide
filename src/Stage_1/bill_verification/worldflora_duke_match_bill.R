#!/usr/bin/env Rscript
################################################################################
# Bill Shipley Verification: WorldFlora Matching for Duke Dataset
################################################################################
# PURPOSE:
#   Matches Duke ethnobotany plant names against World Flora Online (WFO)
#   taxonomic backbone using the WorldFlora R package. This normalizes
#   scientific names to accepted WFO taxonomy.
#
# INPUTS:
#   - output/wfo_verification/duke_names_for_r.csv (from extract_all_names_bill.R)
#   - input/classification.csv (WFO taxonomic backbone)
#
# OUTPUTS:
#   - output/wfo_verification/duke_wfo_worldflora.csv
#
# MATCHING STRATEGY:
#   - Uses exact matching (Fuzzy = 0) to prevent false positives
#   - WFO.prepare() standardizes name formats (removes numbers, subspecies markers)
#   - WFO.match() attempts matching against WFO backbone with multiple strategies
#   - Returns matched names with WFO taxonID and taxonomic hierarchy
#
# EXPECTED OUTPUT:
#   ~14,027 matched records (±10)
################################################################################

# ========================================================================
# AUTO-DETECTING PATHS (works on Windows/Linux/Mac, any location)
# ========================================================================
# This function automatically detects the repository root directory
# regardless of where the script is run from or which platform is used.
# Priority: env var > script location > current directory
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
# Construct all directory paths using file.path for cross-platform compatibility
# file.path() automatically uses correct separators (/ on Unix, \ on Windows)
INPUT_DIR <- file.path(repo_root, "input")
INTERMEDIATE_DIR <- file.path(repo_root, "intermediate")
OUTPUT_DIR <- file.path(repo_root, "output")

# Create output directories if they don't exist
# recursive = TRUE creates parent directories as needed
# showWarnings = FALSE suppresses "already exists" messages
dir.create(file.path(OUTPUT_DIR, "wfo_verification"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "stage3"), recursive = TRUE, showWarnings = FALSE)

cat("Starting WorldFlora matching for Duke dataset\n")
flush.console()

suppressPackageStartupMessages({
  library(data.table)   # Fast CSV I/O with fread/fwrite
  library(WorldFlora)   # WFO.prepare() and WFO.match() functions
})

# Helper function for logging with console flush (ensures output appears immediately)
log_msg <- function(...) {
  cat(..., "\n", sep = "")
  flush.console()
}

# ========================================================================
# DEFINE INPUT/OUTPUT PATHS
# ========================================================================
output_dir <- file.path(OUTPUT_DIR, "wfo_verification")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

input_path <- file.path(output_dir, "duke_names_for_r.csv")
output_path <- file.path(output_dir, "duke_wfo_worldflora.csv")
wfo_path <- file.path(INPUT_DIR, "classification.csv")

# ========================================================================
# STEP 1: LOAD AND PREPARE DUKE NAMES
# ========================================================================
log_msg("Reading Duke names from: ", input_path)
duke <- fread(input_path, encoding = "UTF-8", data.table = FALSE)
log_msg("Loaded ", nrow(duke), " name rows")

# Build unified name_raw column from Duke's two name fields
# Priority: scientific_name (primary) > taxonomy_taxon (fallback)
# This ensures we use the best available name for each record
# Duke database has two name fields; scientific_name is preferred when available
duke$name_raw <- duke$scientific_name
# Identify rows where scientific_name is missing or empty (including whitespace-only)
empty_idx <- which(is.na(duke$name_raw) | trimws(duke$name_raw) == "")
if (length(empty_idx) > 0) {
  # Fill empty scientific_name slots with taxonomy_taxon values
  # This preserves records that only have taxonomy_taxon populated
  duke$name_raw[empty_idx] <- duke$taxonomy_taxon[empty_idx]
}

# Clean whitespace and filter out records with no usable name
# trimws() removes leading/trailing whitespace
duke$name_raw <- trimws(duke$name_raw)
# Final filter: remove any rows where both name fields were empty
duke <- duke[!is.na(duke$name_raw) & nchar(duke$name_raw) > 0, ]
log_msg("Retained ", nrow(duke), " rows with non-empty raw names")

# ========================================================================
# STEP 2: PREPARE NAMES FOR WFO MATCHING
# ========================================================================
# WFO.prepare() standardizes plant names for matching:
# - squish: removes extra whitespace
# - spec.name.nonumber: removes numbers from names
# - spec.name.sub: removes subspecies/variety markers (subsp., var., etc.)
# This increases matching success by normalizing name formats
log_msg("Preparing names with WFO.prepare()")
prep <- WFO.prepare(
  spec.data = duke,
  spec.full = "name_raw",              # Column containing full scientific names
  squish = TRUE,                       # Collapse multiple spaces to single space
  spec.name.nonumber = TRUE,           # Remove numbers from names
  spec.name.sub = TRUE,                # Remove subspecies/variety designations
  verbose = FALSE
)
log_msg("Prepared names; resulting rows: ", nrow(prep))

# ========================================================================
# STEP 3: LOAD WFO TAXONOMIC BACKBONE
# ========================================================================
# The WFO classification.csv contains the complete World Flora Online taxonomy
# This is a large reference file (~1.5M rows) with all accepted plant names and synonyms
# Each row represents one taxonomic concept with its full hierarchy
log_msg("Loading WFO backbone from: ", wfo_path)
wfo <- fread(
  wfo_path,
  sep = "\t",                          # Tab-separated values (TSV format)
  encoding = "Latin-1",                # Latin-1 encoding handles special characters in botanical names
  data.table = FALSE,                  # Return as data.frame for compatibility with WorldFlora
  showProgress = TRUE                  # Show progress bar for large file loading
)
wfo_rows <- nrow(wfo)
log_msg("WFO backbone rows: ", wfo_rows)

# ========================================================================
# STEP 4: MATCH DUKE NAMES AGAINST WFO BACKBONE
# ========================================================================
# WFO.match() performs taxonomic name matching with multiple strategies:
# 1. Exact match on scientific name
# 2. Match on accepted name (follows synonymy)
# 3. Fuzzy matching (disabled here with Fuzzy = 0 for strict matching)
#
# Parameters explained:
# - acceptedNameUsageID.match: If a name is a synonym, follow to accepted name
#   Example: "Quercus robur" (synonym) -> "Quercus petraea" (accepted)
# - Fuzzy = 0: Disable fuzzy matching (only exact matches allowed)
#   Prevents false matches like "Rosa alba" matching to "Rosa rubra"
# - Fuzzy.two/one: Allow fuzzy on genus/species separately (not active with Fuzzy=0)
# - counter: Print progress message every N records (helps monitor long-running matches)
# - verbose: Print detailed matching diagnostics to console
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
# Output contains original Duke columns plus WFO matching results:
# - taxonID: WFO identifier for matched taxon
# - scientificName: WFO accepted scientific name
# - taxonomicStatus: accepted, synonym, etc.
# - family, genus: taxonomic hierarchy from WFO
log_msg("Writing results to: ", output_path)
fwrite(matches, output_path)
log_msg("Completed WorldFlora matching for Duke dataset")
