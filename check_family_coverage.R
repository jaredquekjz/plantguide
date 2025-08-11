#!/usr/bin/env Rscript
library(data.table)

cat('=== CHECKING FAMILY COVERAGE FOR WOOD DENSITY APPROXIMATION ===\n\n')

# Load WFO taxonomy with family information
cat('Loading WFO taxonomy data...\n')
wfo <- fread('data/WFO_taxonomy/classification.csv', select=c('scientificName', 'family'))
cat(sprintf('  WFO entries with family: %d\n', nrow(wfo)))

# Remove duplicates (keep first occurrence)
wfo_unique <- wfo[!duplicated(scientificName)]
cat(sprintf('  Unique species names: %d\n', nrow(wfo_unique)))

# Load our TRY species
cat('\nLoading TRY species list...\n')
try_data <- fread('data/output/eive_numeric_trait_matrix.csv', select=c('AccSpeciesID', 'AccSpeciesName'))
cat(sprintf('  TRY species: %d\n', nrow(try_data)))

# Check if we already have wood density
wood_density_col <- '4'  # TraitID for wood density
if(wood_density_col %in% names(fread('data/output/eive_numeric_trait_matrix.csv', nrows=1))) {
  try_full <- fread('data/output/eive_numeric_trait_matrix.csv', select=c('AccSpeciesID', 'AccSpeciesName', wood_density_col))
  setnames(try_full, wood_density_col, 'wood_density_measured')
  n_with_wd <- sum(!is.na(try_full$wood_density_measured))
  cat(sprintf('  Species with measured wood density: %d (%.1f%%)\n', 
              n_with_wd, 100*n_with_wd/nrow(try_full)))
} else {
  cat('  Wood density column not found in numeric traits\n')
  try_full <- try_data
  try_full$wood_density_measured <- NA
}

# Match with WFO to get families
cat('\nMatching TRY species with WFO families...\n')
matched <- merge(try_full, wfo_unique, by.x='AccSpeciesName', by.y='scientificName', all.x=TRUE)

# Count matches
n_with_family <- sum(!is.na(matched$family))
cat(sprintf('  Species with family match: %d (%.1f%%)\n', 
            n_with_family, 100*n_with_family/nrow(matched)))

# Check coverage by approximation method
cat('\n=== WOOD DENSITY APPROXIMATION COVERAGE ===\n')
matched$has_measured <- !is.na(matched$wood_density_measured)
matched$has_family <- !is.na(matched$family)

cat(sprintf('1. Measured wood density: %d species (%.1f%%)\n', 
            sum(matched$has_measured), 100*sum(matched$has_measured)/nrow(matched)))
cat(sprintf('2. Can use family approximation (no measured, but has family): %d species (%.1f%%)\n',
            sum(!matched$has_measured & matched$has_family), 
            100*sum(!matched$has_measured & matched$has_family)/nrow(matched)))
cat(sprintf('3. Need growth form/default (no measured, no family): %d species (%.1f%%)\n',
            sum(!matched$has_measured & !matched$has_family),
            100*sum(!matched$has_measured & !matched$has_family)/nrow(matched)))
cat(sprintf('\nTotal coverage with measured + family: %d species (%.1f%%)\n',
            sum(matched$has_measured | matched$has_family),
            100*sum(matched$has_measured | matched$has_family)/nrow(matched)))

# Show family distribution
cat('\n=== TOP 20 FAMILIES BY SPECIES COUNT ===\n')
family_counts <- matched[!is.na(family), .N, by=family]
setorder(family_counts, -N)
for(i in 1:min(20, nrow(family_counts))) {
  cat(sprintf('  %2d. %-20s: %4d species\n', i, family_counts$family[i], family_counts$N[i]))
}

# Save the matched data for later use
cat('\nSaving species-family mapping...\n')
output_file <- 'data/output/try_species_families.csv'
fwrite(matched[, .(AccSpeciesID, AccSpeciesName, family, wood_density_measured)], output_file)
cat(sprintf('  Saved to: %s\n', output_file))