#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(data.table)
})

cat('======================================================================\n')
cat('TRY-EIVE EXTRACTION: Merge All Files First, Then Filter\n')
cat('======================================================================\n\n')

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

# Get all TRY files
files <- Sys.glob('data/TRY/*_extract/*.txt')
cat(sprintf('Found %d TRY files to process\n\n', length(files)))

# STEP 1: MERGE ALL FILES FIRST
cat('STEP 1: MERGING ALL TRY FILES\n')
cat('----------------------------------------------------------------------\n')

merged_data <- NULL
total_rows <- 0

for (i in seq_along(files)) {
  f <- files[i]
  cat(sprintf('[%d/%d] Processing %s\n', i, length(files), basename(f)))
  
  # Get file size
  file_mb <- file.info(f)$size / (1024^2)
  cat(sprintf('  File size: %.1f MB\n', file_mb))
  
  if (file_mb > 1000) {
    # Large file - process in chunks
    cat('  Large file - processing in chunks...\n')
    
    con <- file(f, 'r', encoding = 'latin1')
    header_line <- readLines(con, n = 1, warn = FALSE)
    header <- strsplit(header_line, '\t', fixed = TRUE)[[1]]
    header <- trimws(header)
    
    chunk_size <- 100000
    chunk_num <- 0
    file_data <- list()
    
    repeat {
      lines <- readLines(con, n = chunk_size, warn = FALSE)
      if (length(lines) == 0) break
      
      chunk_num <- chunk_num + 1
      if (chunk_num %% 10 == 0) {
        cat(sprintf('    Chunk %d...\n', chunk_num))
      }
      
      # Parse lines
      split_lines <- strsplit(lines, '\t', fixed = TRUE)
      expected_cols <- length(header)
      valid_lines <- sapply(split_lines, length) == expected_cols
      
      if (any(valid_lines)) {
        mat <- do.call(rbind, split_lines[valid_lines])
        dt <- as.data.table(mat)
        if (ncol(dt) == length(header)) {
          setnames(dt, header)
          file_data[[length(file_data) + 1]] <- dt
        }
      }
    }
    close(con)
    
    if (length(file_data) > 0) {
      file_dt <- rbindlist(file_data, fill = TRUE)
      cat(sprintf('  Loaded %d rows\n', nrow(file_dt)))
    } else {
      cat('  ERROR: Could not parse file\n')
      next
    }
    
  } else {
    # Small file - read at once
    file_dt <- fread(f, sep = '\t', header = TRUE, fill = TRUE, 
                     encoding = 'Latin-1', quote = '"', showProgress = FALSE)
    cat(sprintf('  Loaded %d rows\n', nrow(file_dt)))
  }
  
  # Add source info
  file_dt[, SourceFile := basename(dirname(f))]
  
  total_rows <- total_rows + nrow(file_dt)
  
  # Merge with previous data
  if (is.null(merged_data)) {
    merged_data <- file_dt
  } else {
    merged_data <- rbindlist(list(merged_data, file_dt), fill = TRUE)
  }
  
  # Report memory usage
  mem_gb <- object.size(merged_data) / (1024^3)
  cat(sprintf('  Cumulative: %s rows, %.1f GB in memory\n\n', 
              format(total_rows, big.mark = ','), mem_gb))
}

cat('----------------------------------------------------------------------\n')
cat(sprintf('MERGE COMPLETE: %s total rows\n\n', format(nrow(merged_data), big.mark = ',')))

# STEP 2: FILTER FOR EIVE TAXA
cat('STEP 2: FILTERING FOR EIVE TAXA\n')
cat('----------------------------------------------------------------------\n')

# Normalize species names
cat('Normalizing species names...\n')
merged_data[, norm_species := normalize_name(SpeciesName)]
merged_data[, norm_acc := normalize_name(AccSpeciesName)]

# Find matches
cat('Finding EIVE taxa matches...\n')
merged_data[, is_eive := norm_species %in% taxa_set | norm_acc %in% taxa_set]

n_matches <- sum(merged_data$is_eive)
cat(sprintf('  Found %s rows for EIVE taxa (%.1f%%)\n', 
            format(n_matches, big.mark = ','),
            100 * n_matches / nrow(merged_data)))

# Filter for EIVE taxa
eive_data <- merged_data[is_eive == TRUE]

# STEP 3: SEPARATE TRAITS FROM METADATA
cat('\nSTEP 3: ANALYZING TRAIT VS METADATA ROWS\n')
cat('----------------------------------------------------------------------\n')

# Identify trait rows (have TraitID) vs metadata rows
eive_data[, has_trait := !is.na(TraitID) & TraitID != ""]

n_trait_rows <- sum(eive_data$has_trait)
n_metadata_rows <- sum(!eive_data$has_trait)

cat(sprintf('  Trait rows (with TraitID): %s (%.1f%%)\n', 
            format(n_trait_rows, big.mark = ','),
            100 * n_trait_rows / nrow(eive_data)))
cat(sprintf('  Metadata rows (no TraitID): %s (%.1f%%)\n',
            format(n_metadata_rows, big.mark = ','),
            100 * n_metadata_rows / nrow(eive_data)))

# Count unique traits
unique_traits <- unique(eive_data[has_trait == TRUE, TraitID])
cat(sprintf('  Unique trait IDs: %d\n', length(unique_traits)))

# Show trait distribution
cat('\nTop 20 traits by frequency:\n')
trait_counts <- eive_data[has_trait == TRUE, .N, by = .(TraitID, TraitName)]
setorder(trait_counts, -N)

for (i in 1:min(20, nrow(trait_counts))) {
  cat(sprintf('  %5s: %s (n=%s)\n',
              trait_counts$TraitID[i],
              substr(trait_counts$TraitName[i], 1, 40),
              format(trait_counts$N[i], big.mark = ',')))
}

# Count species coverage
unique_species <- unique(eive_data$AccSpeciesName)
unique_species <- unique_species[!is.na(unique_species) & nzchar(unique_species)]
cat(sprintf('\nUnique species with data: %d\n', length(unique_species)))

# STEP 4: SAVE OUTPUT
cat('\nSTEP 4: SAVING OUTPUT FILES\n')
cat('----------------------------------------------------------------------\n')

# Save all EIVE data (traits + metadata)
output_all <- 'data/output/eive_taxa_all_try_data.tsv'
cat(sprintf('Saving all data to %s...\n', output_all))
fwrite(eive_data, file = output_all, sep = '\t', quote = TRUE)
cat(sprintf('  Saved %s rows\n', format(nrow(eive_data), big.mark = ',')))

# Save traits only
output_traits <- 'data/output/eive_taxa_traits_only.tsv'
cat(sprintf('Saving trait rows only to %s...\n', output_traits))
traits_only <- eive_data[has_trait == TRUE]
fwrite(traits_only, file = output_traits, sep = '\t', quote = TRUE)
cat(sprintf('  Saved %s trait records\n', format(nrow(traits_only), big.mark = ',')))

# Summary
cat('\n======================================================================\n')
cat('EXTRACTION COMPLETE!\n')
cat('======================================================================\n')
cat(sprintf('Processed: %s total rows\n', format(nrow(merged_data), big.mark = ',')))
cat(sprintf('Extracted: %s rows for EIVE taxa\n', format(nrow(eive_data), big.mark = ',')))
cat(sprintf('  - Trait records: %s\n', format(n_trait_rows, big.mark = ',')))
cat(sprintf('  - Metadata records: %s\n', format(n_metadata_rows, big.mark = ',')))
cat(sprintf('Unique traits: %d\n', length(unique_traits)))
cat(sprintf('Unique species: %d\n', length(unique_species)))
cat('\nOutput files:\n')
cat(sprintf('  - All data: %s\n', output_all))
cat(sprintf('  - Traits only: %s\n', output_traits))