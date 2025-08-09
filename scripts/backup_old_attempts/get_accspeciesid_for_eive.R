#!/usr/bin/env Rscript
# Get AccSpeciesIDs for EIVE taxa from TRY data

library(data.table)

cat('Finding AccSpeciesIDs for EIVE taxa...\n\n')

# Load EIVE taxa
eive <- fread('data/EIVE/EIVE_TaxonConcept_WFO.csv')
cat(sprintf('EIVE taxa: %d\n', nrow(eive)))

# Normalize function
normalize_name <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub('[^a-z0-9 ]', ' ', x)
  x <- gsub('\\s+', ' ', x)
  trimws(x)
}

# Get normalized EIVE names
eive_names <- unique(c(
  normalize_name(eive$TaxonConcept),
  normalize_name(eive$wfo_accepted_name)
))
eive_names <- eive_names[!is.na(eive_names) & nzchar(eive_names)]
cat(sprintf('Unique normalized names: %d\n\n', length(eive_names)))

# Sample a TRY file to get species-ID mappings
cat('Extracting species-ID mappings from TRY...\n')
try_sample <- fread('data/TRY/43244_extract/43244.txt', 
                   nrows = 500000, encoding = 'Latin-1')

# Get unique species-ID pairs
species_map <- unique(try_sample[!is.na(AccSpeciesID) & !is.na(AccSpeciesName), 
                                 .(AccSpeciesID, AccSpeciesName)])
cat(sprintf('Found %d species-ID mappings\n', nrow(species_map)))

# Normalize and match
species_map[, norm_name := normalize_name(AccSpeciesName)]
matches <- species_map[norm_name %in% eive_names]

cat(sprintf('\nMatched %d EIVE taxa to AccSpeciesIDs\n', nrow(matches)))

if (nrow(matches) > 0) {
  # Save mapping
  fwrite(matches, 'data/output/eive_accspeciesid_mapping.csv')
  
  cat('\nSample matches:\n')
  print(head(matches, 10))
  
  cat(sprintf('\nMapping saved to: data/output/eive_accspeciesid_mapping.csv\n'))
  cat(sprintf('Coverage: %.1f%% of EIVE taxa\n', 100 * nrow(matches) / length(eive_names)))
}