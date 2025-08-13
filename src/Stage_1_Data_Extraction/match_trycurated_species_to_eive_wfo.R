#!/usr/bin/env Rscript

# Match TRY curated species names to EIVE WFO accepted names
# - Reads the TRY curated Excel (Species_mean_traits.xlsx)
# - Extracts species names column (default: "Species name standardized against TPL")
# - Reads EIVE_TaxonConcept_WFO_EXACT.csv and uses column "wfo_accepted_name"
# - Normalizes whitespace/case and computes unique-name matches
# - Prints counts; optionally writes a CSV of matched rows

suppressWarnings({
  suppressMessages({
    # Lazy-load tidy helpers if present
    have_readxl <- requireNamespace("readxl", quietly = TRUE)
    have_readr  <- requireNamespace("readr",  quietly = TRUE)
    have_dplyr  <- requireNamespace("dplyr",  quietly = TRUE)
    have_stringr<- requireNamespace("stringr",quietly = TRUE)
  })
})

args <- commandArgs(trailingOnly = TRUE)

# Simple flag parser: expects --key=value
parse_args <- function(args) {
  out <- list()
  for (a in args) {
    if (!grepl("^--[A-Za-z0-9_]+=", a)) next
    kv <- sub("^--", "", a)
    k <- sub("=.*$", "", kv)
    v <- sub("^[^=]*=", "", kv)
    out[[k]] <- v
  }
  out
}

opts <- parse_args(args)

`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b

# Defaults
try_xlsx  <- opts[["try_xlsx"]]  %||% "data/Tryenhanced/Dataset/Species_mean_traits.xlsx"
if (is.null(opts[["try_sheet"]])) {
  try_sheet <- 1
} else {
  try_sheet <- suppressWarnings(as.integer(opts[["try_sheet"]]))
  if (is.na(try_sheet)) try_sheet <- 1
}
try_species_col <- opts[["try_species_col"]] %||% "Species name standardized against TPL"

eive_csv   <- opts[["eive_csv"]]   %||% "data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv"
eive_name_col <- opts[["eive_name_col"]] %||% "wfo_accepted_name"

out_csv <- opts[["out_csv"]] %||% ""

# Outputs for full trait rows of matched species (optional)
traits_out_csv <- opts[["traits_out_csv"]] %||% ""
traits_out_rds <- opts[["traits_out_rds"]] %||% ""

fail <- function(msg) {
  cat(sprintf("\n[error] %s\n", msg))
  quit(status = 1)
}

# Validate inputs early
if (!file.exists(try_xlsx)) fail(sprintf("TRY workbook not found: '%s'", try_xlsx))
if (!file.exists(eive_csv)) fail(sprintf("EIVE CSV not found: '%s'", eive_csv))
if (!have_readxl) fail("Package 'readxl' is required. Please install with install.packages('readxl').")

# Read TRY species names
try_df <- readxl::read_excel(try_xlsx, sheet = try_sheet, .name_repair = "minimal")

# Find species column (exact, then fuzzy contains)
species_col <- try_species_col
if (!(species_col %in% names(try_df))) {
  alt <- names(try_df)[grepl("species name", tolower(names(try_df)), fixed = TRUE)]
  if (length(alt) == 0) {
    fail(sprintf("Could not find species column. Tried '%s' and any header containing 'species name'.", try_species_col))
  }
  species_col <- alt[[1]]
  cat(sprintf("[warn] Using fallback species column: '%s'\n", species_col))
}

norm_name <- function(x) {
  x <- as.character(x)
  x <- gsub("\\s+", " ", x)
  x <- trimws(x)
  tolower(x)
}

try_species <- norm_name(try_df[[species_col]])
try_species <- try_species[nzchar(try_species)]
try_unique  <- unique(try_species)

# Read EIVE accepted names
if (have_readr) {
  eive_df <- readr::read_csv(eive_csv, show_col_types = FALSE, progress = FALSE)
} else {
  eive_df <- utils::read.csv(eive_csv, stringsAsFactors = FALSE, check.names = FALSE)
}

# Flexible detection of accepted-name column
if (!(eive_name_col %in% names(eive_df))) {
  candidates <- c("wfo_accepted_name", "WFO_Accepted_Name", "wfo_accepted_full_name")
  hit <- candidates[candidates %in% names(eive_df)]
  if (length(hit) == 0) fail(sprintf("Could not find EIVE accepted-name column. Tried: %s", paste(c(eive_name_col, candidates), collapse=", ")))
  eive_name_col <- hit[[1]]
  cat(sprintf("[warn] Using fallback EIVE name column: '%s'\n", eive_name_col))
}

eive_names <- norm_name(eive_df[[eive_name_col]])
eive_names <- eive_names[nzchar(eive_names)]
eive_unique <- unique(eive_names)

# Compute unique-name matches
matches <- intersect(try_unique, eive_unique)

# Optional: write matched pairs (name + any extra columns)
if (nzchar(out_csv)) {
  out_df <- data.frame(
    species = matches,
    stringsAsFactors = FALSE
  )
  if (have_readr) {
    readr::write_csv(out_df, out_csv)
  } else {
    utils::write.csv(out_df, out_csv, row.names = FALSE)
  }
}

# Optional: write full trait rows for matched species
if (nzchar(traits_out_csv) || nzchar(traits_out_rds)) {
  # Attach normalized helper column for matching
  try_df$.__species_norm <- norm_name(try_df[[species_col]])
  matched_rows <- try_df[try_df$.__species_norm %in% eive_unique & nzchar(try_df$.__species_norm), , drop = FALSE]
  # Drop helper column
  matched_rows$.__species_norm <- NULL
  # Ensure output directory exists
  ensure_dir <- function(path) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  }
  if (nzchar(traits_out_csv)) {
    ensure_dir(traits_out_csv)
    if (have_readr) {
      readr::write_csv(matched_rows, traits_out_csv)
    } else {
      utils::write.csv(matched_rows, traits_out_csv, row.names = FALSE)
    }
    cat(sprintf("Wrote matched trait CSV: %s (rows=%d, cols=%d)\n", traits_out_csv, nrow(matched_rows), ncol(matched_rows)))
  }
  if (nzchar(traits_out_rds)) {
    ensure_dir(traits_out_rds)
    saveRDS(matched_rows, traits_out_rds)
    cat(sprintf("Wrote matched trait RDS: %s (rows=%d, cols=%d)\n", traits_out_rds, nrow(matched_rows), ncol(matched_rows)))
  }
}

# Print summary
cat(sprintf("TRY unique species: %d\n", length(try_unique)))
cat(sprintf("EIVE WFO accepted unique: %d\n", length(eive_unique)))
cat(sprintf("Unique name matches: %d\n", length(matches)))

# Exit code 0
invisible(NULL)
