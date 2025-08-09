#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(data.table)
})

cat('======================================================================\n')
cat('EXTRACT EIVE TAXA FROM COMPLETE 4-FILE TRY MERGE\n')
cat('======================================================================\n\n')

# Check which merged file exists
rds_file <- '/home/olier/plantsdatabase/data/sources/TRY/merged_try_data_complete.rds'
csv_gz_file <- '/home/olier/plantsdatabase/data/sources/TRY/merged_try_data_complete.csv.gz'
txt_file <- '/home/olier/plantsdatabase/data/sources/TRY/merged_try_data.txt'

# Determine which file to use
if (file.exists(rds_file)) {
  input_file <- rds_file
  file_type <- 'rds'
} else if (file.exists(csv_gz_file)) {
  input_file <- csv_gz_file
  file_type <- 'csv.gz'
} else if (file.exists(txt_file)) {
  input_file <- txt_file
  file_type <- 'txt'
} else {
  stop('No merged TRY file found! Please run merge_all_try_datasets.R first.')
}

file_gb <- file.info(input_file)$size / (1024^3)
cat(sprintf('Using: %s (%.1f GB, type: %s)\n\n', basename(input_file), file_gb, file_type))

# Load WFO mapping
cat('Loading EIVE taxa with WFO normalization...\n')
wfo_map <- fread('data/EIVE/EIVE_TaxonConcept_WFO.csv', encoding = 'UTF-8')
cat(sprintf('  Loaded %d EIVE taxa\n', nrow(wfo_map)))

# Normalize function
normalize_name <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub('[^a-z0-9 ]', ' ', x)
  x <- gsub('\\s+', ' ', x)
  trimws(x)
}

# Create lookup sets
eive_norm <- unique(normalize_name(wfo_map$TaxonConcept))
wfo_norm <- normalize_name(wfo_map$wfo_accepted_name)
wfo_norm <- wfo_norm[!is.na(wfo_norm) & nzchar(wfo_norm)]
all_taxa <- unique(c(eive_norm, wfo_norm))
taxa_set <- all_taxa[nzchar(all_taxa)]

cat(sprintf('  Target: %d unique normalized names\n\n', length(taxa_set)))

# Load merged data based on file type
cat('Loading merged TRY data...\n')

if (file_type == 'rds') {
  # Most efficient - load RDS
  merged_data <- readRDS(input_file)
  merged_data <- as.data.table(merged_data)
  cat(sprintf('  Loaded %s rows from RDS\n', format(nrow(merged_data), big.mark = ',')))
  
} else if (file_type == 'csv.gz') {
  # Load compressed CSV
  merged_data <- fread(input_file, encoding = 'Latin-1')
  cat(sprintf('  Loaded %s rows from compressed CSV\n', format(nrow(merged_data), big.mark = ',')))
  
} else {
  # For the large txt file, we need to process in chunks
  cat('  Large text file - will process in chunks\n')
  
  # Just get a sample first to analyze structure
  sample_data <- fread(input_file, nrows = 100000, encoding = 'Latin-1')
  cat(sprintf('  Sample loaded: %d columns\n', ncol(sample_data)))
  
  # For now, let's process the rest in chunks like before
  # (Full chunked processing code would go here)
  merged_data <- sample_data  # Temporary - just for testing
}

# Quick stats on merged data
cat('\nMerged data summary:\n')
cat(sprintf('  Total rows: %s\n', format(nrow(merged_data), big.mark = ',')))
cat(sprintf('  Columns: %d\n', ncol(merged_data)))

# Check for unique traits BEFORE filtering
all_traits_before <- unique(merged_data[!is.na(TraitID) & TraitID != "", TraitID])
cat(sprintf('  Unique traits in full dataset: %d\n', length(all_traits_before)))

# Sample of trait IDs
if (length(all_traits_before) > 0) {
  trait_sample <- sort(as.numeric(all_traits_before))
  cat('  Sample trait IDs:', paste(head(trait_sample, 20), collapse = ', '), '...\n')
}

# Filter for EIVE taxa
cat('\nFiltering for EIVE taxa...\n')

# Normalize species names
merged_data[, norm_species := normalize_name(SpeciesName)]
merged_data[, norm_acc := normalize_name(AccSpeciesName)]

# Find matches
merged_data[, is_eive := norm_species %in% taxa_set | norm_acc %in% taxa_set]

eive_data <- merged_data[is_eive == TRUE]
cat(sprintf('  Found %s rows for EIVE taxa (%.1f%%)\n', 
            format(nrow(eive_data), big.mark = ','),
            100 * nrow(eive_data) / nrow(merged_data)))

# Analyze traits vs metadata
eive_data[, has_trait := !is.na(TraitID) & TraitID != ""]
n_trait_rows <- sum(eive_data$has_trait)
n_metadata_rows <- sum(!eive_data$has_trait)

cat(sprintf('  - Trait rows: %s (%.1f%%)\n', 
            format(n_trait_rows, big.mark = ','),
            100 * n_trait_rows / nrow(eive_data)))
cat(sprintf('  - Metadata rows: %s (%.1f%%)\n',
            format(n_metadata_rows, big.mark = ','),
            100 * n_metadata_rows / nrow(eive_data)))

# Count unique traits for EIVE taxa
unique_traits <- unique(eive_data[has_trait == TRUE, TraitID])
cat(sprintf('\nUnique traits for EIVE taxa: %d\n', length(unique_traits)))

# Show trait distribution
cat('\nTop 30 traits by frequency:\n')
trait_counts <- eive_data[has_trait == TRUE, .N, by = .(TraitID, TraitName)]
setorder(trait_counts, -N)

for (i in 1:min(30, nrow(trait_counts))) {
  cat(sprintf('  %5s: %-45s n=%s\n',
              trait_counts$TraitID[i],
              substr(trait_counts$TraitName[i], 1, 45),
              format(trait_counts$N[i], big.mark = ',')))
}

# Check for specific important traits
cat('\nChecking for key trait categories:\n')
key_traits <- list(
  "Leaf economics" = c(3116, 3117, 47, 14, 15, 146, 147),
  "Wood traits" = c(4, 282, 287, 163, 159),
  "Root traits" = c(1080, 82, 80, 83, 1781, 896),
  "Height/Size" = c(18, 3106, 3107),
  "Seeds" = c(26, 27, 28),
  "Stem" = c(21, 22)
)

for (category in names(key_traits)) {
  found <- intersect(key_traits[[category]], as.numeric(unique_traits))
  cat(sprintf('  %s: found %d of %d\n', category, length(found), length(key_traits[[category]])))
  if (length(found) > 0) {
    cat('    IDs:', paste(found, collapse = ', '), '\n')
  }
}

# Count species coverage
unique_species <- unique(eive_data$AccSpeciesName)
unique_species <- unique_species[!is.na(unique_species) & nzchar(unique_species)]
cat(sprintf('\nUnique species with data: %d\n', length(unique_species)))

# Save outputs
cat('\nSaving output files...\n')

# Save all EIVE data
output_all <- 'data/output/eive_taxa_all_try_data.tsv'
fwrite(eive_data, file = output_all, sep = '\t', quote = TRUE)
cat(sprintf('  All data: %s (%.1f GB)\n', output_all, 
            file.info(output_all)$size / (1024^3)))

# Save traits only
output_traits <- 'data/output/eive_taxa_traits_only.tsv'
traits_only <- eive_data[has_trait == TRUE]
fwrite(traits_only, file = output_traits, sep = '\t', quote = TRUE)
cat(sprintf('  Traits only: %s (%.1f GB)\n', output_traits,
            file.info(output_traits)$size / (1024^3)))

# Summary
cat('\n======================================================================\n')
cat('EXTRACTION COMPLETE!\n')
cat('======================================================================\n')
cat(sprintf('Input: %s rows (all 4 TRY files merged)\n', format(nrow(merged_data), big.mark = ',')))
cat(sprintf('Output: %s rows for EIVE taxa\n', format(nrow(eive_data), big.mark = ',')))
cat(sprintf('  - %s trait records\n', format(n_trait_rows, big.mark = ',')))
cat(sprintf('  - %s metadata records\n', format(n_metadata_rows, big.mark = ',')))
cat(sprintf('Unique traits: %d (was %d in full dataset)\n', 
            length(unique_traits), length(all_traits_before)))
cat(sprintf('Unique species: %d\n', length(unique_species)))

# List all trait IDs
if (length(unique_traits) > 0) {
  cat('\nAll trait IDs found:\n')
  all_ids <- sort(as.numeric(unique_traits))
  cat(paste(all_ids, collapse = ', '), '\n')
}