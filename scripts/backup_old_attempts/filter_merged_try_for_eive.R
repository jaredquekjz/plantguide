#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(data.table)
})

cat('======================================================================\n')
cat('EXTRACT EIVE TAXA FROM PRE-MERGED TRY DATA\n')
cat('======================================================================\n\n')

# Input and output paths
merged_file <- '/home/olier/plantsdatabase/data/sources/TRY/merged_try_data.txt'
wfo_file <- 'data/EIVE/EIVE_TaxonConcept_WFO.csv'
output_all <- 'data/output/eive_taxa_all_try_data.tsv'
output_traits <- 'data/output/eive_taxa_traits_only.tsv'

# Check file exists
if (!file.exists(merged_file)) {
  stop('Merged TRY file not found at: ', merged_file)
}

file_gb <- file.info(merged_file)$size / (1024^3)
cat(sprintf('Input file: %s (%.1f GB)\n\n', basename(merged_file), file_gb))

# Load WFO mapping
cat('Loading EIVE taxa with WFO normalization...\n')
wfo_map <- fread(wfo_file, encoding = 'UTF-8')
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

# Process in chunks to handle 19GB file
cat('Processing merged TRY file in chunks...\n')
cat('----------------------------------------------------------------------\n')

chunk_size <- 500000  # Process 500k rows at a time
total_rows <- 0
total_matches <- 0
total_traits <- 0
unique_traits <- c()
unique_species <- c()

# Read header first
con <- file(merged_file, 'r', encoding = 'latin1')
header_line <- readLines(con, n = 1, warn = FALSE)
close(con)

header <- strsplit(header_line, '\t', fixed = TRUE)[[1]]
cat(sprintf('Columns: %d\n', length(header)))

# Check for key columns
if (!all(c('SpeciesName', 'AccSpeciesName', 'TraitID') %in% header)) {
  cat('WARNING: Some expected columns missing!\n')
  cat('Available columns:', paste(head(header, 20), collapse = ', '), '...\n')
}

# Initialize output files with headers
write_header <- TRUE

# Process file in chunks
con <- file(merged_file, 'r', encoding = 'latin1')
readLines(con, n = 1, warn = FALSE)  # Skip header

chunk_num <- 0
repeat {
  # Read chunk
  chunk_num <- chunk_num + 1
  
  if (chunk_num %% 10 == 1) {
    cat(sprintf('\nChunk %d (row %s):\n', chunk_num, format(total_rows + 1, big.mark = ',')))
  }
  
  dt <- tryCatch({
    fread(cmd = sprintf("head -n %d", chunk_size), 
          file = con, sep = '\t', header = FALSE,
          col.names = header, fill = TRUE, 
          encoding = 'Latin-1', showProgress = FALSE)
  }, error = function(e) NULL)
  
  if (is.null(dt) || nrow(dt) == 0) break
  
  total_rows <- total_rows + nrow(dt)
  
  # Normalize species names
  dt[, norm_species := normalize_name(SpeciesName)]
  dt[, norm_acc := normalize_name(AccSpeciesName)]
  
  # Find EIVE taxa
  dt[, is_eive := norm_species %in% taxa_set | norm_acc %in% taxa_set]
  eive_subset <- dt[is_eive == TRUE]
  
  if (nrow(eive_subset) > 0) {
    n_matches <- nrow(eive_subset)
    total_matches <- total_matches + n_matches
    
    # Count traits
    eive_subset[, has_trait := !is.na(TraitID) & TraitID != ""]
    n_traits <- sum(eive_subset$has_trait)
    total_traits <- total_traits + n_traits
    
    # Track unique values
    unique_traits <- unique(c(unique_traits, unique(eive_subset[has_trait == TRUE, TraitID])))
    unique_species <- unique(c(unique_species, unique(eive_subset$AccSpeciesName)))
    
    # Save all EIVE data
    if (write_header) {
      fwrite(eive_subset, file = output_all, sep = '\t', quote = TRUE)
      write_header <- FALSE
    } else {
      fwrite(eive_subset, file = output_all, sep = '\t', quote = TRUE, 
             append = TRUE, col.names = FALSE)
    }
    
    # Save traits only
    traits_subset <- eive_subset[has_trait == TRUE]
    if (nrow(traits_subset) > 0) {
      fwrite(traits_subset, file = output_traits, sep = '\t', quote = TRUE,
             append = !write_header, col.names = write_header)
    }
    
    if (chunk_num %% 10 == 1) {
      cat(sprintf('  Found %s EIVE rows (%s traits)\n', 
                  format(n_matches, big.mark = ','),
                  format(n_traits, big.mark = ',')))
      cat(sprintf('  Running total: %s matches, %d unique traits\n',
                  format(total_matches, big.mark = ','),
                  length(unique_traits)))
    }
  }
  
  # Progress report every 5M rows
  if (total_rows %% 5000000 == 0) {
    cat(sprintf('\n=== Progress: %s rows processed ===\n', 
                format(total_rows, big.mark = ',')))
    cat(sprintf('  EIVE matches so far: %s\n', format(total_matches, big.mark = ',')))
    cat(sprintf('  Unique traits found: %d\n', length(unique_traits)))
    cat(sprintf('  Unique species found: %d\n', length(unique_species)))
    
    # Show top traits so far
    if (length(unique_traits) > 0 && exists('eive_subset')) {
      cat('  Sample traits:', paste(head(unique_traits, 10), collapse = ', '), '...\n')
    }
  }
}

close(con)

# Final summary
cat('\n======================================================================\n')
cat('EXTRACTION COMPLETE!\n')
cat('======================================================================\n')
cat(sprintf('Total rows processed: %s\n', format(total_rows, big.mark = ',')))
cat(sprintf('EIVE taxa rows found: %s (%.2f%%)\n', 
            format(total_matches, big.mark = ','),
            100 * total_matches / total_rows))
cat(sprintf('  - Trait records: %s\n', format(total_traits, big.mark = ',')))
cat(sprintf('  - Metadata records: %s\n', format(total_matches - total_traits, big.mark = ',')))
cat(sprintf('Unique traits: %d\n', length(unique_traits)))
cat(sprintf('Unique species: %d\n', length(unique_species)))

# Clean up species list
unique_species <- unique_species[!is.na(unique_species) & nzchar(unique_species)]
cat(sprintf('Clean unique species: %d\n', length(unique_species)))

cat('\nOutput files:\n')
cat(sprintf('  - All data: %s\n', output_all))
cat(sprintf('  - Traits only: %s\n', output_traits))

if (file.exists(output_all)) {
  out_gb <- file.info(output_all)$size / (1024^3)
  cat(sprintf('  - Output size: %.2f GB\n', out_gb))
}

# Show trait list
if (length(unique_traits) > 0) {
  cat(sprintf('\nFound %d unique trait IDs:\n', length(unique_traits)))
  cat(paste(sort(as.numeric(unique_traits)), collapse = ', '), '\n')
}