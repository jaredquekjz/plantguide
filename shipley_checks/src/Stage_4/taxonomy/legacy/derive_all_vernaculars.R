#!/usr/bin/env Rscript
#' Unified Vernacular Category Derivation
#'
#' @description
#' Command-line interface for deriving vernacular categories from species-level
#' vernacular names using word frequency analysis. Replaces separate Python
#' scripts with a single unified R implementation.
#'
#' @details
#' ## Purpose
#'
#' This script derives vernacular category names (e.g., "oaks", "bees", "moths")
#' for taxonomic groups (genera or families) by analyzing word frequencies in
#' their species' vernacular names.
#'
#' ## Algorithm
#'
#' 1. Load all species with iNaturalist vernacular names
#' 2. Group by taxonomic level (genus or family)
#' 3. Aggregate all vernacular strings per group
#' 4. Tokenize into words, remove stopwords
#' 5. Count word frequencies
#' 6. Match against category keywords (oak, bee, moth, etc.)
#' 7. Assign dominant category if ≥10% of total word frequency
#' 8. Pluralize and save to parquet
#'
#' ## Usage
#'
#' ```bash
#' # Derive plant family categories
#' Rscript derive_all_vernaculars.R --organism-type plant --level family
#'
#' # Derive plant genus categories
#' Rscript derive_all_vernaculars.R --organism-type plant --level genus
#'
#' # Derive animal family categories
#' Rscript derive_all_vernaculars.R --organism-type animal --level family
#'
#' # Derive animal genus categories
#' Rscript derive_all_vernaculars.R --organism-type animal --level genus
#' ```
#'
#' ## Arguments
#'
#' - `--organism-type`: Either "plant" or "animal" (required)
#' - `--level`: Either "family" or "genus" (required)
#' - `--threshold`: Minimum percentage for assignment (default: 0.10)
#' - `--data-dir`: Path to taxonomy data directory (default: /home/olier/ellenberg/data/taxonomy)
#'
#' ## Input Files
#'
#' **Plants:**
#' - `data/taxonomy/plants_vernacular_final.parquet`
#'   - From: assign_vernacular_names.R pipeline
#'   - Contains: All plants with iNaturalist vernacular names
#'
#' **Animals:**
#' - `data/taxonomy/organisms_vernacular_final.parquet`
#'   - From: assign_vernacular_names.R pipeline
#'   - Contains: All beneficial organisms with iNaturalist vernaculars
#'
#' ## Output Files
#'
#' Pattern: `{organism_type}_{level}_vernaculars_derived.parquet`
#'
#' Examples:
#' - `plant_family_vernaculars_derived.parquet`
#' - `plant_genus_vernaculars_derived.parquet`
#' - `animal_family_vernaculars_derived.parquet` (legacy: family_vernaculars_derived_from_species.parquet)
#' - `animal_genus_vernaculars_derived.parquet` (legacy: genus_vernaculars_derived_from_species.parquet)
#'
#' Output columns:
#' - [family/genus]: Taxonomic group name
#' - n_species_with_vernaculars: Species count
#' - dominant_category: Highest-scoring category
#' - dominant_score: Raw keyword frequency
#' - total_word_count: Total words analyzed
#' - category_percentage: (score / total) * 100
#' - top_10_words: Most frequent words
#' - derived_vernacular: Assigned category (pluralized)
#'
#' ## Performance
#'
#' - Plant genus (11,000 species): ~15 seconds
#' - Plant family (11,000 species): ~10 seconds
#' - Animal genus (29,000 organisms): ~30 seconds
#' - Animal family (29,000 organisms): ~20 seconds
#'
#' @author Claude Code
#' @date 2025-11-15
#' @version 1.0

suppressPackageStartupMessages({
  library(optparse)
  library(duckdb)
  library(arrow)
  library(dplyr)
})

# ==============================================================================
# Parse Command Line Arguments
# ==============================================================================

option_list <- list(
  make_option(
    c("-t", "--organism-type"),
    type = "character",
    default = NULL,
    help = "Organism type: 'plant' or 'animal' [required]",
    metavar = "TYPE"
  ),
  make_option(
    c("-l", "--level"),
    type = "character",
    default = NULL,
    help = "Taxonomic level: 'family' or 'genus' [required]",
    metavar = "LEVEL"
  ),
  make_option(
    c("--threshold"),
    type = "double",
    default = 0.10,
    help = "Minimum percentage for category assignment [default: %default]",
    metavar = "PCT"
  ),
  make_option(
    c("-d", "--data-dir"),
    type = "character",
    default = "/home/olier/ellenberg/data/taxonomy",
    help = "Path to taxonomy data directory [default: %default]",
    metavar = "DIR"
  ),
  make_option(
    c("-v", "--verbose"),
    action = "store_true",
    default = TRUE,
    help = "Print progress messages [default: %default]"
  )
)

opt_parser <- OptionParser(
  option_list = option_list,
  description = "\nDerive vernacular categories for genera or families using word frequency analysis.",
  epilogue = paste0(
    "\nExamples:\n",
    "  Rscript derive_all_vernaculars.R --organism-type plant --level genus\n",
    "  Rscript derive_all_vernaculars.R -t animal -l family --threshold 0.15\n"
  )
)

opt <- parse_args(opt_parser)

# ==============================================================================
# Validate Arguments
# ==============================================================================

# Check required arguments
if (is.null(opt$`organism-type`) || is.null(opt$level)) {
  print_help(opt_parser)
  stop("Both --organism-type and --level are required.", call. = FALSE)
}

# Validate organism type
if (!opt$`organism-type` %in% c("plant", "animal")) {
  stop("--organism-type must be 'plant' or 'animal'", call. = FALSE)
}

# Validate taxonomic level
if (!opt$level %in% c("family", "genus")) {
  stop("--level must be 'family' or 'genus'", call. = FALSE)
}

# Validate threshold
if (opt$threshold <= 0 || opt$threshold > 1.0) {
  stop("--threshold must be between 0 and 1.0", call. = FALSE)
}

# Validate data directory
if (!dir.exists(opt$`data-dir`)) {
  stop(sprintf("Data directory does not exist: %s", opt$`data-dir`), call. = FALSE)
}

# ==============================================================================
# Load Library Functions
# ==============================================================================

# Get script directory for sourcing library
script_path <- commandArgs(trailingOnly = FALSE)
script_path <- script_path[grep("^--file=", script_path)]
if (length(script_path) > 0) {
  script_dir <- dirname(sub("^--file=", "", script_path))
} else {
  # Fallback if running interactively
  script_dir <- getwd()
}

lib_dir <- file.path(script_dir, "lib")

if (!dir.exists(lib_dir)) {
  stop(sprintf("Library directory not found: %s\nEnsure lib/ exists in script directory.", lib_dir),
       call. = FALSE)
}

# Source library modules
source(file.path(lib_dir, "category_keywords.R"))
source(file.path(lib_dir, "vernacular_derivation.R"))

# ==============================================================================
# Configuration
# ==============================================================================

organism_type <- opt$`organism-type`
level <- opt$level
threshold <- opt$threshold
data_dir <- opt$`data-dir`
verbose <- opt$verbose

# Determine input file based on organism type
input_file <- if (organism_type == "plant") {
  file.path(data_dir, "plants_vernacular_final.parquet")
} else {
  file.path(data_dir, "organisms_vernacular_final.parquet")
}

# Check input file exists
if (!file.exists(input_file)) {
  stop(sprintf("Input file not found: %s\n\nRun assign_vernacular_names.R pipeline first.",
               input_file),
       call. = FALSE)
}

# Determine output file
output_file <- file.path(
  data_dir,
  sprintf("%s_%s_vernaculars_derived.parquet", organism_type, level)
)

# Get appropriate keyword set
category_keywords <- if (organism_type == "plant") {
  plant_keywords()
} else {
  animal_keywords()
}

# ==============================================================================
# Main Execution
# ==============================================================================

if (verbose) {
  cat(strrep("=", 80), "\n")
  cat(sprintf("DERIVE %s %s VERNACULAR CATEGORIES\n",
              toupper(organism_type), toupper(level)))
  cat(strrep("=", 80), "\n\n")

  cat("Configuration:\n")
  cat(sprintf("  Organism type:  %s\n", organism_type))
  cat(sprintf("  Taxonomic level: %s\n", level))
  cat(sprintf("  Threshold:      %.1f%%\n", threshold * 100))
  cat(sprintf("  Input file:     %s\n", basename(input_file)))
  cat(sprintf("  Output file:    %s\n", basename(output_file)))
  cat(sprintf("  Keywords:       %d categories, %d unique keywords\n",
              length(category_keywords),
              count_keywords(organism_type)))
  cat("\n")
}

# Initialize DuckDB
start_time <- Sys.time()
con <- dbConnect(duckdb::duckdb())

if (verbose) {
  cat("Starting derivation...\n\n")
}

# Run derivation pipeline
result <- derive_vernacular_categories(
  con = con,
  input_file = input_file,
  group_col = level,
  category_keywords = category_keywords,
  threshold = threshold,
  verbose = verbose
)

# Check if any categories were derived
if (nrow(result) == 0) {
  warning("No categories derived. Try lowering --threshold or check keyword coverage.")
  dbDisconnect(con, shutdown = TRUE)
  quit(status = 1)
}

# Display summary
if (verbose) {
  cat(sprintf("\n=== Results Summary ===\n"))
  cat(sprintf("%ss with derived vernaculars: %s\n",
              tools::toTitleCase(level),
              format(nrow(result), big.mark = ",")))
  cat("\n")

  # Show top 20 by species coverage
  cat(sprintf("=== Top 20 %ss by Species Coverage ===\n", tools::toTitleCase(level)))
  top_display <- result %>%
    head(20) %>%
    select(all_of(c(level, "n_species_with_vernaculars", "dominant_category", "category_percentage")))

  print(top_display, row.names = FALSE)
  cat("\n")
}

# Save results
write_parquet(result, output_file)

if (verbose) {
  cat(sprintf("✓ Saved to: %s\n", output_file))
}

# Calculate coverage impact
coverage_impact <- calculate_coverage_impact(
  con = con,
  input_file = input_file,
  derived_file = output_file,
  group_col = level,
  verbose = verbose
)

# Cleanup
dbDisconnect(con, shutdown = TRUE)

# Final timing
elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

if (verbose) {
  cat(sprintf("\n✓ Completed in %.1f seconds\n", elapsed))
}

# Exit successfully
quit(status = 0)
