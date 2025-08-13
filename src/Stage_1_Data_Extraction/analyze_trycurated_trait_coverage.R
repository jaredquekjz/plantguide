#!/usr/bin/env Rscript
# Analyze trait coverage from curated TRY means and emit Markdown summary

suppressPackageStartupMessages({
  library(data.table)
})

cat("=== TRY Curated Trait Coverage Analysis ===\n\n")

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(key, default = NULL) {
  hit <- grep(paste0('^', key, '='), args, value = TRUE)
  if (length(hit) == 0) return(default)
  sub(paste0('^', key, '='), '', hit[1])
}

traits_rds <- get_arg('--traits_rds', 'artifacts/traits_matched.rds')
out_md     <- get_arg('--out_md', 'artifacts/trait_coverage.md')

if (!file.exists(traits_rds)) {
  stop(sprintf("Traits RDS not found: %s (run match_trycurated_species_to_eive_wfo.R first)", traits_rds))
}
dir.create(dirname(out_md), showWarnings = FALSE, recursive = TRUE)

cat("Loading curated traits RDS...\n")
dt <- as.data.table(readRDS(traits_rds))
cat(sprintf("  Rows: %d, Cols: %d\n", nrow(dt), ncol(dt)))

# Helper to match column by case-insensitive name
find_col <- function(names_vec, pattern) {
  hits <- which(tolower(names_vec) == tolower(pattern))
  if (length(hits) > 0) return(names_vec[hits[1]])
  # relax: partial match
  hits <- grep(pattern = paste0('^', gsub('([()])', '\\$\1', tolower(pattern)), '$'), 
               x = tolower(names_vec))
  if (length(hits) > 0) return(names_vec[hits[1]])
  hits <- grep(pattern = tolower(pattern), x = tolower(names_vec), fixed = TRUE)
  if (length(hits) > 0) return(names_vec[hits[1]])
  NA_character_
}

# Define the six core numeric traits used in the curated summary
want <- c(
  'Leaf area (mm2)',
  'Nmass (mg/g)',
  'LMA (g/m2)',
  'Plant height (m)',
  'Diaspore mass (mg)',
  'SSD combined (mg/mm3)'
)

cols <- vapply(want, function(w) find_col(names(dt), w), character(1))
missing <- is.na(cols)
if (any(missing)) {
  stop(sprintf("Missing expected trait columns: %s", paste(want[missing], collapse = ", ")))
}

cat("Using trait columns:\n")
for (i in seq_along(want)) {
  cat(sprintf("  - %s (col: '%s')\n", want[i], cols[i]))
}

# Count number of non-NA across selected columns per species
vals <- dt[, ..cols]
for (j in seq_along(cols)) set(vals, j = j, value = suppressWarnings(as.numeric(vals[[j]])))
trait_counts <- vals[, rowSums(!is.na(.SD)), .SDcols = cols]
dt[, traits_available_count := trait_counts]
dt[, has_all_traits := traits_available_count == length(cols)]

# Distribution summary
tab <- dt[, .N, by = traits_available_count][order(-traits_available_count)]
setnames(tab, 'N', 'species_count')
total_species <- nrow(dt)
max_traits <- length(cols)

cat("\nSummary distribution (top 10 rows):\n")
print(head(tab, 10))

# Generate Markdown table
md <- c(
  "# TRY Curated Trait Coverage",
  "",
  sprintf("Total species: %d", total_species),
  sprintf("Traits counted: %d (%s)", max_traits, paste(want, collapse = "; ")),
  "",
  "| traits_available | species_count | percent |",
  "|------------------:|--------------:|--------:|"
)

for (k in seq(from = max_traits, to = 0, by = -1)) {
  n <- tab[traits_available_count == k, species_count]
  if (length(n) == 0) n <- 0L
  pct <- if (total_species > 0) sprintf("%.1f%%", 100 * n / total_species) else "0.0%"
  md <- c(md, sprintf("| %d | %d | %s |", k, n, pct))
}

# Also add a one-liner for "all traits"
all_n <- tab[traits_available_count == max_traits, species_count]
if (length(all_n) == 0) all_n <- 0L
md <- c(md, "", sprintf("All traits (%d): %d species", max_traits, all_n))

writeLines(md, out_md)
cat(sprintf("\nSaved Markdown summary to: %s\n", out_md))

invisible(NULL)

