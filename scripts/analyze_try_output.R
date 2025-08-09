#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(data.table)
})

cat('======================================================================\n')
cat('TRY Output Analysis: Taxa Coverage and Data Structure\n')
cat('======================================================================\n\n')

# Load the WFO mapping to get all EIVE taxa
wfo_map <- fread('data/EIVE/EIVE_TaxonConcept_WFO.csv', encoding = 'UTF-8')
cat(sprintf('Total EIVE taxa: %d\n', nrow(wfo_map)))
cat(sprintf('  - Mapped to WFO: %d\n', sum(!is.na(wfo_map$wfo_id))))
cat(sprintf('  - No WFO mapping: %d\n\n', sum(is.na(wfo_map$wfo_id))))

# Load the TRY output
cat('Loading TRY output file...\n')
try_data <- fread('data/output/traits_for_eive_taxa_rtry.tsv', encoding = 'UTF-8')
cat(sprintf('Total rows in output: %s\n', format(nrow(try_data), big.mark = ',')))

# Analyze unique species
unique_species <- unique(try_data$SpeciesName)
unique_acc_species <- unique(try_data$AccSpeciesName)
all_unique <- unique(c(unique_species, unique_acc_species))
all_unique <- all_unique[!is.na(all_unique) & nzchar(all_unique)]

cat(sprintf('\nUnique taxa in TRY output:\n'))
cat(sprintf('  - Unique SpeciesName: %d\n', length(unique_species[!is.na(unique_species)])))
cat(sprintf('  - Unique AccSpeciesName: %d\n', length(unique_acc_species[!is.na(unique_acc_species)])))
cat(sprintf('  - Combined unique: %d\n', length(all_unique)))

# Normalize function (same as in merge script)
normalize_name <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub('[^a-z0-9 ]', ' ', x)
  x <- gsub('\\s+', ' ', x)
  trimws(x)
}

# Check coverage: which EIVE taxa have data
eive_norm <- unique(normalize_name(wfo_map$TaxonConcept))
wfo_norm <- unique(normalize_name(wfo_map$wfo_accepted_name))
wfo_norm <- wfo_norm[!is.na(wfo_norm) & nzchar(wfo_norm)]
all_target_taxa <- unique(c(eive_norm, wfo_norm))

# Normalize TRY species names
try_norm_species <- unique(normalize_name(try_data$SpeciesName))
try_norm_acc <- unique(normalize_name(try_data$AccSpeciesName))
try_all_norm <- unique(c(try_norm_species, try_norm_acc))
try_all_norm <- try_all_norm[!is.na(try_all_norm) & nzchar(try_all_norm)]

# Find matches
matched_taxa <- all_target_taxa[all_target_taxa %in% try_all_norm]
unmatched_taxa <- all_target_taxa[!all_target_taxa %in% try_all_norm]

cat('\n======================================================================\n')
cat('TAXA COVERAGE ANALYSIS\n')
cat('======================================================================\n')
cat(sprintf('Target EIVE taxa (normalized): %d\n', length(all_target_taxa)))
cat(sprintf('Taxa WITH trait data: %d (%.1f%%)\n', 
            length(matched_taxa), 100 * length(matched_taxa) / length(all_target_taxa)))
cat(sprintf('Taxa WITHOUT trait data: %d (%.1f%%)\n', 
            length(unmatched_taxa), 100 * length(unmatched_taxa) / length(all_target_taxa)))

# Analyze traits
cat('\n======================================================================\n')
cat('TRAIT DATA STRUCTURE\n')
cat('======================================================================\n')

if ('TraitID' %in% names(try_data)) {
  trait_counts <- try_data[, .N, by = TraitID]
  setorder(trait_counts, -N)
  cat(sprintf('Unique traits: %d\n', length(unique(try_data$TraitID))))
  cat('\nTop 10 most common traits:\n')
  
  # Get trait names if available
  if ('TraitName' %in% names(try_data)) {
    trait_summary <- try_data[, .(Count = .N, TraitName = first(TraitName)), by = TraitID]
    setorder(trait_summary, -Count)
    for (i in 1:min(10, nrow(trait_summary))) {
      cat(sprintf('  %d. TraitID %s: %s (%s records)\n', 
                  i, trait_summary$TraitID[i], trait_summary$TraitName[i],
                  format(trait_summary$Count[i], big.mark = ',')))
    }
  } else {
    for (i in 1:min(10, nrow(trait_counts))) {
      cat(sprintf('  %d. TraitID %s: %s records\n', 
                  i, trait_counts$TraitID[i], 
                  format(trait_counts$N[i], big.mark = ',')))
    }
  }
}

# Analyze data sources
if ('Dataset' %in% names(try_data)) {
  cat('\nData sources (datasets):\n')
  dataset_counts <- try_data[, .N, by = Dataset]
  setorder(dataset_counts, -N)
  for (i in 1:min(5, nrow(dataset_counts))) {
    cat(sprintf('  %d. %s: %s records\n', 
                i, dataset_counts$Dataset[i], 
                format(dataset_counts$N[i], big.mark = ',')))
  }
}

# Sample unmatched taxa
if (length(unmatched_taxa) > 0) {
  cat('\n======================================================================\n')
  cat('SAMPLE OF TAXA WITHOUT TRAIT DATA\n')
  cat('======================================================================\n')
  
  # Get original names for unmatched taxa
  unmatched_original <- wfo_map$TaxonConcept[normalize_name(wfo_map$TaxonConcept) %in% unmatched_taxa]
  cat(sprintf('Showing first 20 of %d taxa without data:\n', length(unmatched_original)))
  for (i in 1:min(20, length(unmatched_original))) {
    cat(sprintf('  - %s\n', unmatched_original[i]))
  }
  
  # Save full list
  unmatched_file <- 'data/output/eive_taxa_without_try_data.txt'
  writeLines(sort(unmatched_original), unmatched_file)
  cat(sprintf('\nFull list saved to: %s\n', unmatched_file))
}

# Analyze observations per species
cat('\n======================================================================\n')
cat('OBSERVATIONS PER SPECIES\n')
cat('======================================================================\n')

obs_per_species <- try_data[, .N, by = AccSpeciesName]
setorder(obs_per_species, -N)

cat(sprintf('Species with data: %d\n', nrow(obs_per_species)))
cat(sprintf('Mean observations per species: %.1f\n', mean(obs_per_species$N)))
cat(sprintf('Median observations per species: %.0f\n', median(obs_per_species$N)))
cat(sprintf('Max observations for a species: %s\n', format(max(obs_per_species$N), big.mark = ',')))

cat('\nTop 10 species by number of observations:\n')
for (i in 1:min(10, nrow(obs_per_species))) {
  cat(sprintf('  %d. %s: %s observations\n', 
              i, obs_per_species$AccSpeciesName[i], 
              format(obs_per_species$N[i], big.mark = ',')))
}

cat('\n======================================================================\n')
cat('ANALYSIS COMPLETE!\n')
cat('======================================================================\n')