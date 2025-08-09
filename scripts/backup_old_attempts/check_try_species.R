#!/usr/bin/env Rscript
# Quick diagnostic to check species overlap between TRY and EIVE

library(data.table)

# Load WFO mapping
wfo_map <- fread('data/EIVE/EIVE_TaxonConcept_WFO.csv', encoding = 'UTF-8')

normalize_name <- function(x) {
  x <- ifelse(is.na(x), '', trimws(x))
  x <- gsub('×', 'x', x, fixed = TRUE)
  x <- iconv(x, to = 'ASCII//TRANSLIT')
  x <- tolower(gsub('[\r\n]+', ' ', x))
  x <- gsub('[[:space:]]+', ' ', x)
  trimws(x)
}

# Get all normalized EIVE/WFO names
eive_norm <- unique(normalize_name(wfo_map$TaxonConcept))
wfo_norm <- unique(normalize_name(wfo_map$wfo_accepted_name))
all_taxa <- unique(c(eive_norm, wfo_norm))
taxa_set <- all_taxa[nzchar(all_taxa)]

message(sprintf('EIVE/WFO taxa to search for: %d unique normalized names', length(taxa_set)))
message('\nSampling first 10000 rows from each TRY file to check for matches...\n')

# Check each TRY file
files <- Sys.glob('data/TRY/*_extract/*.txt')

for (f in files) {
  message(sprintf('Checking %s...', basename(f)))
  
  # Read first 10000 rows
  dt <- tryCatch(
    fread(f, sep = '\t', nrows = 10000, header = TRUE, 
          fill = TRUE, encoding = 'Latin-1'),
    error = function(e) NULL
  )
  
  if (is.null(dt)) {
    message('  ERROR reading file!')
    next
  }
  
  # Get unique species names
  species_col <- if ('SpeciesName' %in% names(dt)) dt$SpeciesName else character(0)
  acc_col <- if ('AccSpeciesName' %in% names(dt)) dt$AccSpeciesName else character(0)
  
  all_species <- unique(c(species_col, acc_col))
  all_species <- all_species[!is.na(all_species) & nzchar(all_species)]
  
  message(sprintf('  Found %d unique species names in first 10k rows', length(all_species)))
  
  # Normalize and check for matches
  norm_species <- unique(normalize_name(all_species))
  matches <- norm_species[norm_species %in% taxa_set]
  
  if (length(matches) > 0) {
    message(sprintf('  ✓ Found %d MATCHES!', length(matches)))
    message('    Examples:')
    for (i in 1:min(5, length(matches))) {
      # Find original name
      orig_idx <- which(normalize_name(all_species) == matches[i])[1]
      message(sprintf('      - %s', all_species[orig_idx]))
    }
  } else {
    message('  ✗ No matches found in sample')
  }
  
  # Show some example species for debugging
  if (length(all_species) > 0) {
    message('  Sample of TRY species names:')
    for (i in 1:min(3, length(all_species))) {
      message(sprintf('    - %s -> %s', all_species[i], normalize_name(all_species[i])))
    }
  }
  
  message('')
}