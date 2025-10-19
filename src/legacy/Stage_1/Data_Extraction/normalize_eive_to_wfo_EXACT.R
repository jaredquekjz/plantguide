#!/usr/bin/env Rscript
# EXACT MATCH ONLY version of EIVE to WFO normalization
# No fuzzy matching - only uses direct WFO backbone matches
# This avoids duplicate mappings and ensures precise species identification

suppressPackageStartupMessages({
  library(data.table)
})

cat("=== EIVE to WFO Normalization (EXACT MATCH ONLY) ===\n\n")

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(key, default = NULL) {
  hit <- grep(paste0('^', key, '='), args, value = TRUE)
  if (length(hit) == 0) return(default)
  sub(paste0('^', key, '='), '', hit[1])
}

normalize_name <- function(x) {
  x <- ifelse(is.na(x), '', trimws(x))
  # Remove botanical hybrid sign (×) and ASCII 'x' marker between tokens
  x <- gsub('^×[[:space:]]*', '', x, perl = TRUE)
  x <- gsub('[[:space:]]*×[[:space:]]*', ' ', x, perl = TRUE)
  x <- gsub('(^|[[:space:]])x([[:space:]]+)', ' ', x, perl = TRUE)
  x <- iconv(x, to = 'ASCII//TRANSLIT')
  x <- tolower(gsub('[\r\n]+', ' ', x))
  x <- gsub('[[:space:]]+', ' ', x)
  trimws(x)
}

# File paths
eive_csv <- trimws(gsub('[\r\n`]+','', get_arg('--eive_csv', 'data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv')))
out_csv  <- trimws(gsub('[\r\n`]+','', get_arg('--out', 'data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv')))
# Bake in default WFO backbone location updated to data/classification.csv
wfo_csv  <- trimws(gsub('[\r\n`]+','', get_arg('--wfo_csv', 'data/classification.csv')))

if (!file.exists(eive_csv)) stop(sprintf('Missing EIVE CSV: %s', eive_csv))
if (!file.exists(wfo_csv)) stop(sprintf('Missing WFO backbone CSV: %s', wfo_csv))
dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)

# Load EIVE data
cat("Loading EIVE data...\n")
eive <- fread(eive_csv, encoding = 'UTF-8')
if (!'TaxonConcept' %in% names(eive)) stop('EIVE CSV must have a TaxonConcept column')
names_in <- unique(eive$TaxonConcept)
cat(sprintf("  Found %d unique EIVE taxa\n", length(names_in)))

# Load WFO backbone
cat("\nLoading WFO backbone...\n")
# Read header first to detect column names robustly
hdr <- names(fread(wfo_csv, nrows = 0, encoding = 'UTF-8'))
has <- function(x) any(tolower(hdr) == tolower(x))
col_of <- function(x) hdr[tolower(hdr) == tolower(x)][1]
need <- c('taxonID','scientificName','acceptedNameUsageID','taxonomicStatus')
sel <- vapply(need, function(x) if (has(x)) col_of(x) else NA_character_, character(1))
if (any(is.na(sel))) {
  stop(sprintf('WFO CSV missing required columns: %s', paste(need[is.na(sel)], collapse = ', ')))
}
WFO.data <- fread(wfo_csv, select = sel, encoding = 'UTF-8')
setnames(WFO.data, sel, need)
cat(sprintf("  Loaded %d WFO records\n", nrow(WFO.data)))

# Normalize WFO names for matching
cat("\nPreparing WFO data for matching...\n")
WFO.data[, norm := normalize_name(scientificName)]

# Create accepted name mapping
acc_map <- WFO.data[taxonomicStatus == 'Accepted', .(accepted_id = taxonID, accepted_scientificName = scientificName)]
WFO.data[, accepted_id2 := ifelse(taxonomicStatus == 'Accepted' | is.na(taxonomicStatus), taxonID, acceptedNameUsageID)]
WFO.data <- merge(WFO.data, acc_map, by.x = 'accepted_id2', by.y = 'accepted_id', all.x = TRUE)
WFO.data[, wfo_accepted_name := fifelse(!is.na(accepted_scientificName), accepted_scientificName, scientificName)]
WFO.data[, wfo_id := accepted_id2]

# Prioritize accepted names over synonyms
WFO.data[, rank := ifelse(taxonomicStatus == 'Accepted', 1L, 2L)]
setorderv(WFO.data, c('norm','rank'))

# Get best match per normalized name (prefer accepted status)
wfo_best <- WFO.data[nzchar(norm), .SD[1], by = norm, .SDcols = c('wfo_id','wfo_accepted_name','scientificName','taxonomicStatus')]

cat(sprintf("  Prepared %d unique normalized names for matching\n", nrow(wfo_best)))

# EXACT MATCHING ONLY - NO FUZZY!
cat("\n=== EXACT MATCHING (NO FUZZY) ===\n")

# Build result with exact matches
res <- data.table(TaxonConcept = names_in)
res[, norm := normalize_name(TaxonConcept)]

# Direct exact join on normalized names
res <- merge(res, wfo_best[, .(norm, wfo_id, wfo_accepted_name)], 
             by = 'norm', all.x = TRUE, sort = FALSE)

# Count matches
exact_matched <- sum(!is.na(res$wfo_id))
exact_unmatched <- sum(is.na(res$wfo_id))

cat(sprintf("\nResults:\n"))
cat(sprintf("  Exact matches: %d (%.1f%%)\n", exact_matched, 100*exact_matched/length(names_in)))
cat(sprintf("  Unmatched: %d (%.1f%%)\n", exact_unmatched, 100*exact_unmatched/length(names_in)))

# Check for duplicates (multiple EIVE → same WFO)
wfo_counts <- res[!is.na(wfo_id) & nzchar(wfo_id), .N, by = wfo_id][N > 1]
if (nrow(wfo_counts) > 0) {
  cat(sprintf("\nNOTE: %d WFO IDs have multiple EIVE taxa mapping to them\n", nrow(wfo_counts)))
  cat("(This is expected for subspecies/varieties mapping to species level)\n")
  setorder(wfo_counts, -N)
  cat("Top duplicate mappings:\n")
  for (i in 1:min(5, nrow(wfo_counts))) {
    wfo <- wfo_counts$wfo_id[i]
    n <- wfo_counts$N[i]
    taxa <- res[wfo_id == wfo, TaxonConcept]
    cat(sprintf("  %s: %d EIVE taxa (%s...)\n", wfo, n, paste(head(taxa, 3), collapse=", ")))
  }
}

# For unmatched, keep the original name as a fallback
res[is.na(wfo_accepted_name), wfo_accepted_name := TaxonConcept]

# Save results
cat("\nSaving results...\n")
output_data <- res[, .(TaxonConcept, wfo_id, wfo_accepted_name)]
setorder(output_data, TaxonConcept)
fwrite(output_data, out_csv)
cat(sprintf("  Saved to: %s\n", out_csv))

# Show some examples
cat("\nSample mappings:\n")
cat("Matched examples:\n")
print(head(output_data[!is.na(wfo_id) & wfo_id != ""], 5))

cat("\nUnmatched examples (kept original names):\n")
print(head(output_data[is.na(wfo_id) | wfo_id == ""], 5))

# Summary statistics
cat("\n=== FINAL SUMMARY ===\n")
cat(sprintf("Total EIVE taxa: %d\n", nrow(output_data)))
cat(sprintf("Successfully mapped to WFO: %d (%.1f%%)\n", 
            sum(!is.na(output_data$wfo_id)),
            100*sum(!is.na(output_data$wfo_id))/nrow(output_data)))
cat(sprintf("Unique WFO IDs: %d\n", length(unique(output_data$wfo_id[!is.na(output_data$wfo_id)]))))
cat(sprintf("Unique WFO accepted names: %d\n", 
            length(unique(output_data$wfo_accepted_name))))

cat("\n✅ EXACT matching complete - no fuzzy matching was used!\n")
