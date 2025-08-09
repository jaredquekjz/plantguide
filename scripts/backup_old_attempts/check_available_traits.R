#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(data.table)
})

cat('Loading TRY data to check available traits...\n')
try_data <- fread('data/output/traits_for_eive_taxa_rtry.tsv', encoding = 'UTF-8', nrows = 100000)

# Get unique traits with names
trait_summary <- try_data[!is.na(TraitID), .(
  N_Records = .N,
  TraitName = first(TraitName),
  Example_Species = first(AccSpeciesName)
), by = TraitID]

setorder(trait_summary, -N_Records)

cat('\n======================================================================\n')
cat('TOP 50 MOST COMMON TRAITS IN DATASET\n')
cat('======================================================================\n\n')

for (i in 1:min(50, nrow(trait_summary))) {
  cat(sprintf('%3d. ID %5s: %s (%d records)\n',
              i,
              trait_summary$TraitID[i],
              substr(trait_summary$TraitName[i], 1, 60),
              trait_summary$N_Records[i]))
}

# Check for any root/SLA related traits
cat('\n======================================================================\n')
cat('SEARCHING FOR KEY MISSING TRAITS (alternative IDs)\n')
cat('======================================================================\n\n')

# Search for SLA variants
sla_keywords <- c('SLA', 'specific leaf area', 'leaf area per', 'area per mass')
cat('SLA-related traits:\n')
for (kw in sla_keywords) {
  matches <- trait_summary[grepl(kw, TraitName, ignore.case = TRUE)]
  if (nrow(matches) > 0) {
    for (j in 1:nrow(matches)) {
      cat(sprintf('  ID %s: %s\n', matches$TraitID[j], matches$TraitName[j]))
    }
  }
}

# Search for root traits
cat('\nRoot-related traits:\n')
root_keywords <- c('root', 'Root', 'ROOT')
for (kw in root_keywords) {
  matches <- trait_summary[grepl(kw, TraitName, ignore.case = FALSE)]
  if (nrow(matches) > 0) {
    for (j in 1:min(10, nrow(matches))) {
      cat(sprintf('  ID %s: %s\n', matches$TraitID[j], matches$TraitName[j]))
    }
    if (nrow(matches) > 10) cat(sprintf('  ... and %d more\n', nrow(matches) - 10))
    break
  }
}

# Search for wood/stem traits
cat('\nWood/Stem-related traits:\n')
wood_keywords <- c('wood', 'vessel', 'xylem', 'stem')
for (kw in wood_keywords) {
  matches <- trait_summary[grepl(kw, TraitName, ignore.case = TRUE)]
  if (nrow(matches) > 0) {
    for (j in 1:min(5, nrow(matches))) {
      cat(sprintf('  ID %s: %s\n', matches$TraitID[j], matches$TraitName[j]))
    }
    break
  }
}

# List all unique trait IDs
all_ids <- sort(unique(trait_summary$TraitID))
cat('\n======================================================================\n')
cat(sprintf('TOTAL UNIQUE TRAIT IDS: %d\n', length(all_ids)))
cat('======================================================================\n')
cat('All IDs:', paste(all_ids, collapse = ', '), '\n')