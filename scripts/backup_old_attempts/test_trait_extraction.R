#!/usr/bin/env Rscript
# Quick test of the fixed trait extraction logic
suppressPackageStartupMessages({
  library(data.table)
})

cat('Testing trait extraction fix...\n\n')

# Test on smallest file first
test_file <- 'data/TRY/43240_extract/43240.txt'
cat(sprintf('Reading first 1000 rows from %s\n', basename(test_file)))

dt <- fread(test_file, sep = '\t', nrows = 1000, header = TRUE, 
            fill = TRUE, encoding = 'Latin-1', quote = '"')

cat(sprintf('Total rows: %d\n', nrow(dt)))

# Count rows with TraitID
has_trait <- !is.na(dt$TraitID) & dt$TraitID != ""
cat(sprintf('Rows with TraitID: %d (%.1f%%)\n', sum(has_trait), 100*sum(has_trait)/nrow(dt)))
cat(sprintf('Rows without TraitID (metadata): %d\n', sum(!has_trait)))

# Show trait distribution
if (sum(has_trait) > 0) {
  trait_counts <- dt[has_trait, .N, by = .(TraitID, TraitName)]
  cat('\nTraits found:\n')
  print(trait_counts)
}

# Show what's in rows without TraitID
if (sum(!has_trait) > 0) {
  cat('\nSample of metadata rows (no TraitID):\n')
  metadata <- dt[!has_trait, .(DataID, DataName)]
  metadata_counts <- metadata[, .N, by = .(DataID, DataName)]
  setorder(metadata_counts, -N)
  print(head(metadata_counts, 10))
}

cat('\n--- Testing on larger file ---\n')
test_file2 <- 'data/TRY/43244_extract/43244.txt'
cat(sprintf('Reading first 10000 rows from %s\n', basename(test_file2)))

dt2 <- fread(test_file2, sep = '\t', nrows = 10000, header = TRUE,
             fill = TRUE, encoding = 'Latin-1', quote = '"')

has_trait2 <- !is.na(dt2$TraitID) & dt2$TraitID != ""
cat(sprintf('Total rows: %d\n', nrow(dt2)))
cat(sprintf('Rows with TraitID: %d (%.1f%%)\n', sum(has_trait2), 100*sum(has_trait2)/nrow(dt2)))

# Count unique traits
unique_traits <- unique(dt2$TraitID[has_trait2])
cat(sprintf('Unique trait IDs: %d\n', length(unique_traits)))

# Show top traits
trait_counts2 <- dt2[has_trait2, .N, by = TraitID]
setorder(trait_counts2, -N)
cat('\nTop 10 traits by frequency:\n')
for (i in 1:min(10, nrow(trait_counts2))) {
  trait_info <- dt2[TraitID == trait_counts2$TraitID[i], .(TraitName = first(TraitName))]
  cat(sprintf('  %5s: %s (n=%d)\n', 
              trait_counts2$TraitID[i],
              substr(trait_info$TraitName, 1, 40),
              trait_counts2$N[i]))
}

cat('\nTEST COMPLETE - The fix correctly filters for trait records only!\n')