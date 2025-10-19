#!/usr/bin/env Rscript
# EXACT MATCH ONLY version of GROOT to WFO normalization
# No fuzzy matching - only uses direct WFO backbone matches
# This avoids duplicate mappings and ensures precise species identification

suppressPackageStartupMessages({
  library(data.table)
})

cat("=== GROOT to WFO Normalization (EXACT MATCH ONLY) ===\n\n")

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
groot_csv <- trimws(gsub('[\r\n`]+','', get_arg('--groot_csv', 'GRooT-Data/DataFiles/GRooTAggregateSpeciesVersion.csv')))
out_csv  <- trimws(gsub('[\r\n`]+','', get_arg('--out', 'data/GROOT/GROOT_species_WFO_EXACT.csv')))
wfo_csv  <- trimws(gsub('[\r\n`]+','', get_arg('--wfo_csv', 'data/WFO_taxonomy/classification.csv')))

if (!file.exists(groot_csv)) stop(sprintf('Missing GROOT CSV: %s', groot_csv))
if (!file.exists(wfo_csv)) stop(sprintf('Missing WFO backbone CSV: %s', wfo_csv))
dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)

# Load GROOT data
cat("Loading GROOT data...\n")
groot <- fread(groot_csv, encoding = 'Latin-1')  # GROOT uses Latin-1 encoding

# Extract unique species from GROOT and create scientific names
if (!'genusTNRS' %in% names(groot) || !'speciesTNRS' %in% names(groot)) {
  stop('GROOT CSV must have genusTNRS and speciesTNRS columns')
}
groot_species <- unique(groot[!is.na(speciesTNRS), .(genusTNRS, speciesTNRS)])
groot_species[, scientific_name := paste(genusTNRS, speciesTNRS)]
names_in <- unique(groot_species$scientific_name)
cat(sprintf("  Found %d unique species in GROOT\n", length(names_in)))

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
res <- data.table(scientific_name = names_in)
res[, norm := normalize_name(scientific_name)]

# Direct exact join on normalized names
res <- merge(res, wfo_best[, .(norm, wfo_id, wfo_accepted_name)], 
             by = 'norm', all.x = TRUE, sort = FALSE)

# Count matches
exact_matched <- sum(!is.na(res$wfo_id))
exact_unmatched <- sum(is.na(res$wfo_id))

cat(sprintf("\nResults:\n"))
cat(sprintf("  Exact matches: %d (%.1f%%)\n", exact_matched, 100*exact_matched/length(names_in)))
cat(sprintf("  Unmatched: %d (%.1f%%)\n", exact_unmatched, 100*exact_unmatched/length(names_in)))

# Check for duplicates (multiple GROOT → same WFO)
wfo_counts <- res[!is.na(wfo_id), .N, by = wfo_id][N > 1]
if (nrow(wfo_counts) > 0) {
  cat(sprintf("\nWARNING: %d WFO IDs have multiple GROOT taxa mapping to them\n", nrow(wfo_counts)))
  setorder(wfo_counts, -N)
  cat("Top duplicate mappings:\n")
  for (i in 1:min(5, nrow(wfo_counts))) {
    wfo <- wfo_counts$wfo_id[i]
    n <- wfo_counts$N[i]
    taxa <- res[wfo_id == wfo, scientific_name]
    cat(sprintf("  %s: %d GROOT taxa (%s...)\n", wfo, n, paste(head(taxa, 3), collapse=", ")))
  }
}

# For unmatched, keep the original name as a fallback
res[is.na(wfo_accepted_name), wfo_accepted_name := scientific_name]

# Save results
cat("\nSaving results...\n")
output_data <- res[, .(scientific_name, wfo_id, wfo_accepted_name)]
setorder(output_data, scientific_name)
fwrite(output_data, out_csv)
cat(sprintf("  Saved to: %s\n", out_csv))

# Show some examples
cat("\nSample mappings:\n")
cat("Matched examples:\n")
print(head(output_data[!is.na(wfo_id) & wfo_id != ""], 5))

cat("\nUnmatched examples (kept original names):\n")
print(head(output_data[is.na(wfo_id) | wfo_id == ""], 5))

# Now analyze coverage with EIVE if EIVE WFO file exists
eive_wfo_csv <- get_arg('--eive_wfo', 'data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv')
if (file.exists(eive_wfo_csv)) {
  cat("\n=== Analyzing GROOT coverage for EIVE species ===\n")
  
  # Load EIVE WFO normalized names
  eive_wfo <- fread(eive_wfo_csv)
  
  # Get EIVE accepted names
  if ("wfo_accepted_name" %in% names(eive_wfo)) {
    eive_accepted <- unique(eive_wfo[!is.na(wfo_accepted_name), wfo_accepted_name])
  } else if ("WFO_Accepted" %in% names(eive_wfo)) {
    eive_accepted <- unique(eive_wfo[!is.na(WFO_Accepted), WFO_Accepted])
  } else {
    eive_accepted <- unique(eive_wfo$TaxonConcept)
  }
  
  # Count GROOT species that match EIVE
  groot_in_eive <- sum(res$wfo_accepted_name %in% eive_accepted, na.rm = TRUE)
  
  cat(sprintf("\nGROOT species total: %d\n", nrow(res)))
  cat(sprintf("GROOT species with WFO match: %d\n", sum(!is.na(res$wfo_id))))
  cat(sprintf("GROOT species in EIVE: %d (%.1f%%)\n", 
              groot_in_eive, 100 * groot_in_eive / nrow(res)))
  
  # Analyze key root traits coverage
  cat("\n=== Root Trait Coverage for EIVE Species ===\n")
  
  # Get GROOT species that are in EIVE
  eive_groot_species <- res[wfo_accepted_name %in% eive_accepted, scientific_name]
  
  # Map back to original GROOT genus/species format
  eive_groot_matches <- groot_species[scientific_name %in% eive_groot_species]
  
  key_traits <- c("Specific_root_length", "Root_tissue_density", 
                  "Root_N_concentration", "Mean_Root_diameter",
                  "Root_mycorrhizal colonization")
  
  for (trait in key_traits) {
    trait_data <- groot[traitName == trait]
    if (nrow(trait_data) > 0) {
      trait_species <- unique(trait_data[!is.na(speciesTNRS), 
                                         paste(genusTNRS, speciesTNRS)])
      n_trait_total <- length(trait_species)
      n_trait_eive <- sum(trait_species %in% eive_groot_species)
      cat(sprintf("%-30s: %4d species (%d in EIVE)\n", 
                  trait, n_trait_total, n_trait_eive))
    }
  }
  
  # Save EIVE-matched GROOT data
  out_eive_matched <- gsub('\\.csv$', '_EIVE_matched.csv', out_csv)
  groot_eive_subset <- groot[paste(genusTNRS, speciesTNRS) %in% eive_groot_species]
  fwrite(groot_eive_subset, out_eive_matched)
  cat(sprintf("\nEIVE-matched GROOT data saved to: %s\n", out_eive_matched))
  cat(sprintf("Total trait records for EIVE species: %d\n", nrow(groot_eive_subset)))
}

# Summary statistics
cat("\n=== FINAL SUMMARY ===\n")
cat(sprintf("Total GROOT species: %d\n", nrow(output_data)))
cat(sprintf("Successfully mapped to WFO: %d (%.1f%%)\n", 
            sum(!is.na(output_data$wfo_id) & output_data$wfo_id != ""),
            100*sum(!is.na(output_data$wfo_id) & output_data$wfo_id != "")/nrow(output_data)))
cat(sprintf("Unique WFO IDs: %d\n", length(unique(output_data$wfo_id[!is.na(output_data$wfo_id)]))))
cat(sprintf("Unique WFO accepted names: %d\n", 
            length(unique(output_data$wfo_accepted_name[output_data$wfo_accepted_name != output_data$scientific_name]))))

cat("\n✅ EXACT matching complete - no fuzzy matching was used!\n")