#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(data.table)
})

cat('======================================================================\n')
cat('TRAIT VERIFICATION: SOURCE FILES vs MERGED OUTPUT\n')
cat('======================================================================\n\n')

# Check source files
cat('CHECKING SOURCE FILES:\n')
cat('----------------------------------------------------------------------\n')

source_files <- Sys.glob('data/TRY/*_extract/*.txt')
total_source_traits <- c()

for (f in source_files) {
  cat(sprintf('\n%s:\n', basename(f)))
  
  # Read first 100k rows to sample traits
  dt <- fread(f, sep = '\t', nrows = 100000, header = TRUE, 
              fill = TRUE, encoding = 'Latin-1', quote = '"')
  
  if ('TraitID' %in% names(dt)) {
    # Get unique traits
    traits <- unique(dt$TraitID[!is.na(dt$TraitID) & dt$TraitID != ""])
    total_source_traits <- c(total_source_traits, traits)
    
    cat(sprintf('  Sample rows: %d\n', nrow(dt)))
    cat(sprintf('  Unique TraitIDs in sample: %d\n', length(traits)))
    
    # Show top 10 traits by frequency
    trait_counts <- dt[!is.na(TraitID) & TraitID != "", .N, by = .(TraitID, TraitName)]
    setorder(trait_counts, -N)
    
    cat('  Top 10 traits:\n')
    for (i in 1:min(10, nrow(trait_counts))) {
      cat(sprintf('    %5s: %s (n=%d)\n', 
                  trait_counts$TraitID[i],
                  substr(trait_counts$TraitName[i], 1, 40),
                  trait_counts$N[i]))
    }
    
    # Check for key traits
    key_traits <- c(3116, 47, 3110, 14, 26, 4, 18, 1080, 82, 80)
    found_key <- intersect(as.character(key_traits), as.character(traits))
    if (length(found_key) > 0) {
      cat(sprintf('  ✓ Found key traits: %s\n', paste(found_key, collapse = ', ')))
    }
  }
}

cat('\n----------------------------------------------------------------------\n')
unique_source_traits <- unique(total_source_traits)
cat(sprintf('TOTAL UNIQUE TRAITS ACROSS ALL SOURCE FILES: %d\n', length(unique_source_traits)))
cat(sprintf('TraitID range: %s to %s\n', min(as.numeric(unique_source_traits)), max(as.numeric(unique_source_traits))))

# Check merged output
cat('\n======================================================================\n')
cat('CHECKING MERGED OUTPUT:\n')
cat('----------------------------------------------------------------------\n')

merged <- fread('data/output/traits_for_eive_taxa_rtry.tsv', 
                nrows = 100000, encoding = 'UTF-8')

cat(sprintf('Sample rows: %d\n', nrow(merged)))

if ('TraitID' %in% names(merged)) {
  merged_traits <- unique(merged$TraitID[!is.na(merged$TraitID) & merged$TraitID != ""])
  cat(sprintf('Unique TraitIDs in sample: %d\n', length(merged_traits)))
  
  # Show trait distribution
  trait_counts_merged <- merged[!is.na(TraitID) & TraitID != "", .N, by = .(TraitID, TraitName)]
  setorder(trait_counts_merged, -N)
  
  cat('\nTop 20 traits in merged output:\n')
  for (i in 1:min(20, nrow(trait_counts_merged))) {
    cat(sprintf('  %5s: %s (n=%d)\n', 
                trait_counts_merged$TraitID[i],
                substr(trait_counts_merged$TraitName[i], 1, 40),
                trait_counts_merged$N[i]))
  }
  
  # Compare with source
  cat('\n----------------------------------------------------------------------\n')
  cat('COMPARISON:\n')
  cat(sprintf('Traits in source files: %d\n', length(unique_source_traits)))
  cat(sprintf('Traits in merged output: %d\n', length(merged_traits)))
  
  missing_in_merge <- setdiff(unique_source_traits, merged_traits)
  cat(sprintf('Traits MISSING from merge: %d\n', length(missing_in_merge)))
  if (length(missing_in_merge) > 0 && length(missing_in_merge) <= 20) {
    cat('  Missing trait IDs:', paste(missing_in_merge, collapse = ', '), '\n')
  }
  
  extra_in_merge <- setdiff(merged_traits, unique_source_traits)
  if (length(extra_in_merge) > 0) {
    cat(sprintf('Extra traits in merge (not in sample): %d\n', length(extra_in_merge)))
  }
}

# Check for rows with empty TraitID
cat('\n----------------------------------------------------------------------\n')
cat('CHECKING EMPTY TRAIT IDs:\n')

empty_trait_rows <- merged[is.na(TraitID) | TraitID == ""]
cat(sprintf('Rows with empty TraitID in merged output: %d (%.1f%%)\n', 
            nrow(empty_trait_rows), 100 * nrow(empty_trait_rows) / nrow(merged)))

if (nrow(empty_trait_rows) > 0) {
  # Check what's in DataName column for empty TraitIDs
  if ('DataName' %in% names(empty_trait_rows)) {
    data_names <- empty_trait_rows[, .N, by = DataName]
    setorder(data_names, -N)
    cat('\nDataName values for empty TraitID rows:\n')
    for (i in 1:min(10, nrow(data_names))) {
      cat(sprintf('  %s: %d rows\n', 
                  substr(data_names$DataName[i], 1, 50), 
                  data_names$N[i]))
    }
  }
}

cat('\n======================================================================\n')
cat('ANALYSIS COMPLETE!\n')
cat('======================================================================\n')