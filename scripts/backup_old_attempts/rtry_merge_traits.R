#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(data.table)
})

args <- commandArgs(trailingOnly = TRUE)

# Simple CLI parsing
get_arg <- function(key, default = NULL) {
  hit <- grep(paste0('^', key, '='), args, value = TRUE)
  if (length(hit) == 0) return(default)
  sub(paste0('^', key, '='), '', hit[1])
}

wfo_csv <- get_arg('--wfo_csv', 'data/EIVE/EIVE_TaxonConcept_WFO.csv')
sources_pattern <- get_arg('--pattern', 'data/TRY/*_extract/*.txt')
out_path <- get_arg('--out', 'data/output/traits_for_eive_taxa_rtry.tsv')
chunk_sz <- as.integer(get_arg('--chunk_lines', '50000'))  # Smaller for safety

# Find source files
sources <- Sys.glob(sources_pattern)
if (length(sources) == 0) {
  stop(sprintf('No files found matching pattern: %s', sources_pattern))
}

cat('======================================================================\n')
cat('TRY Data Extraction with WFO Normalized Names\n')
cat('======================================================================\n\n')

# Load WFO normalized names
if (!file.exists(wfo_csv)) {
  stop(sprintf('WFO file not found: %s', wfo_csv))
}

cat(sprintf('Loading WFO normalized names from: %s\n', wfo_csv))
wfo_map <- fread(wfo_csv, encoding = 'UTF-8')
cat(sprintf('  Loaded %d EIVE taxa with WFO mappings\n', nrow(wfo_map)))

# Normalize function - simpler version
normalize_name <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub('[^a-z0-9 ]', ' ', x)  # Remove all special chars
  x <- gsub('\\s+', ' ', x)        # Collapse spaces
  trimws(x)
}

# Create lookup sets
eive_norm <- unique(normalize_name(wfo_map$TaxonConcept))
wfo_norm <- normalize_name(wfo_map$wfo_accepted_name)
wfo_norm <- wfo_norm[!is.na(wfo_norm) & nzchar(wfo_norm)]
wfo_norm <- unique(wfo_norm)

all_taxa <- unique(c(eive_norm, wfo_norm))
taxa_set <- all_taxa[nzchar(all_taxa)]

cat(sprintf('\nTarget taxa: %d unique normalized names\n', length(taxa_set)))
cat(sprintf('Processing %d files...\n', length(sources)))

# Initialize
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
write_header <- TRUE
total_matches <- 0L
total_rows <- 0L

for (file_path in sources) {
  cat(sprintf('\n--- Processing %s ---\n', basename(file_path)))
  
  # Get file info
  file_mb <- file.info(file_path)$size / (1024^2)
  cat(sprintf('  File size: %.1f MB\n', file_mb))
  
  # Read header line manually (safer than fread for problematic files)
  con <- file(file_path, 'r', encoding = 'latin1')
  header_line <- readLines(con, n = 1, warn = FALSE)
  close(con)
  
  # Parse header
  header <- strsplit(header_line, '\t', fixed = TRUE)[[1]]
  header <- trimws(header)
  
  # Find species columns
  idx_species <- which(header == 'SpeciesName')
  idx_acc <- which(header == 'AccSpeciesName')
  
  if (length(idx_species) == 0 && length(idx_acc) == 0) {
    cat('  ERROR: No species columns found!\n')
    next
  }
  
  cat(sprintf('  Found columns: SpeciesName=%s, AccSpeciesName=%s\n',
              ifelse(length(idx_species) > 0, idx_species[1], 'NA'),
              ifelse(length(idx_acc) > 0, idx_acc[1], 'NA')))
  
  # Process file in chunks using readLines (more robust than fread)
  con <- file(file_path, 'r', encoding = 'latin1')
  readLines(con, n = 1, warn = FALSE)  # Skip header
  
  chunk_num <- 0L
  file_matches <- 0L
  file_rows <- 0L
  
  repeat {
    # Read chunk
    lines <- readLines(con, n = chunk_sz, warn = FALSE)
    if (length(lines) == 0) break
    
    chunk_num <- chunk_num + 1
    if (chunk_num %% 20 == 0) {
      cat(sprintf('  Chunk %d: %d rows processed, %d matches found...\n', 
                  chunk_num, file_rows, file_matches))
    }
    
    # Parse lines into data.table
    # Split each line and create a matrix, then convert to data.table
    split_lines <- strsplit(lines, '\t', fixed = TRUE)
    
    # Filter out malformed lines
    expected_cols <- length(header)
    valid_lines <- sapply(split_lines, length) == expected_cols
    
    if (!any(valid_lines)) {
      file_rows <- file_rows + length(lines)
      next
    }
    
    # Create data.table from valid lines
    mat <- do.call(rbind, split_lines[valid_lines])
    dt <- as.data.table(mat)
    
    # Set column names
    if (ncol(dt) == length(header)) {
      setnames(dt, header)
    } else {
      cat(sprintf('  WARNING: Column mismatch in chunk %d\n', chunk_num))
      file_rows <- file_rows + length(lines)
      next
    }
    
    # Get species names
    species_names <- character(0)
    acc_names <- character(0)
    
    if (length(idx_species) > 0 && 'SpeciesName' %in% names(dt)) {
      species_names <- dt$SpeciesName
    }
    if (length(idx_acc) > 0 && 'AccSpeciesName' %in% names(dt)) {
      acc_names <- dt$AccSpeciesName
    }
    
    # Normalize and check for matches
    norm_species <- normalize_name(species_names)
    norm_acc <- normalize_name(acc_names)
    
    # Find matches - ONLY keep rows with actual trait data (non-empty TraitID)
    has_trait <- !is.na(dt$TraitID) & dt$TraitID != ""
    match_species <- norm_species %in% taxa_set
    match_acc <- norm_acc %in% taxa_set
    keep <- has_trait & (match_species | match_acc)
    
    n_matches <- sum(keep)
    
    if (n_matches > 0) {
      sub <- dt[keep]
      sub[, Source := basename(dirname(file_path))]
      
      # Write to output
      if (write_header) {
        fwrite(sub, file = out_path, sep = '\t', quote = TRUE)
        write_header <- FALSE
      } else {
        fwrite(sub, file = out_path, sep = '\t', append = TRUE, 
               quote = TRUE, col.names = FALSE)
      }
      
      file_matches <- file_matches + n_matches
      
      if (n_matches >= 10) {
        cat(sprintf('    -> Found %d trait records for EIVE taxa in chunk %d!\n', n_matches, chunk_num))
      }
    }
    
    file_rows <- file_rows + nrow(dt)
  }
  
  close(con)
  
  cat(sprintf('  COMPLETE: %d rows, %d matches (%.3f%%)\n', 
              file_rows, file_matches, 
              100 * file_matches / max(file_rows, 1)))
  
  total_matches <- total_matches + file_matches
  total_rows <- total_rows + file_rows
}

cat('\n======================================================================\n')
cat('EXTRACTION COMPLETE!\n')
cat('======================================================================\n')
cat(sprintf('Total rows processed: %s\n', format(total_rows, big.mark = ',')))
cat(sprintf('Trait records extracted: %s (only rows with TraitID)\n', format(total_matches, big.mark = ',')))
cat(sprintf('Extraction rate: %.4f%%\n', 100 * total_matches / max(total_rows, 1)))
cat(sprintf('Output file: %s\n', out_path))
cat('\nNote: Ancillary data rows (metadata without TraitID) were excluded.\n')

if (total_matches == 0) {
  cat('\nWARNING: No matches found!\n')
}