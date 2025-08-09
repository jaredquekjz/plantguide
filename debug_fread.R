#!/usr/bin/env Rscript
library(data.table)

path <- 'data/43244_extract/43244.txt'

cat("=== Testing different fread approaches ===\n\n")

# Test 1: Basic fread with encoding
cat("Test 1: fread with Latin-1 encoding\n")
hdr1 <- tryCatch({
  result <- fread(path, sep = '\t', nrows = 0, header = TRUE, fill = TRUE, encoding = 'Latin-1')
  cat("Success! Found", length(names(result)), "columns\n")
  cat("Column names include SpeciesName?", 'SpeciesName' %in% names(result), "\n")
  cat("Column names include AccSpeciesName?", 'AccSpeciesName' %in% names(result), "\n")
  result
}, error = function(e) {
  cat("Error:", e$message, "\n")
  NULL
})

# Test 2: fread with UTF-8 encoding
cat("\nTest 2: fread with UTF-8 encoding\n")
hdr2 <- tryCatch({
  result <- fread(path, sep = '\t', nrows = 0, header = TRUE, fill = TRUE, encoding = 'UTF-8')
  cat("Success! Found", length(names(result)), "columns\n")
  cat("Column names include SpeciesName?", 'SpeciesName' %in% names(result), "\n")
  cat("Column names include AccSpeciesName?", 'AccSpeciesName' %in% names(result), "\n")
  result
}, error = function(e) {
  cat("Error:", e$message, "\n")
  NULL
})

# Test 3: Check if file path is being split incorrectly
cat("\nTest 3: File path handling\n")
cat("Original path:", path, "\n")
cat("File exists?", file.exists(path), "\n")

# Try with full absolute path
full_path <- normalizePath(path, mustWork = FALSE)
cat("Full path:", full_path, "\n")
cat("Full path file exists?", file.exists(full_path), "\n")

# Test 4: Read raw header line
cat("\nTest 4: Raw header analysis\n")
first_line <- readLines(path, n = 1, warn = FALSE)
cols <- strsplit(first_line, '\t')[[1]]
cat("Number of columns from raw read:", length(cols), "\n")
cat("Column 5:", cols[5], "\n")
cat("Column 7:", cols[7], "\n")

# Test 5: Check match() function behavior
cat("\nTest 5: Testing match() function\n")
if (!is.null(hdr1)) {
  header <- names(hdr1)
  cat("Header length:", length(header), "\n")
  idx_species <- match('SpeciesName', header)
  idx_acc <- match('AccSpeciesName', header)
  cat("SpeciesName index:", idx_species, "\n")
  cat("AccSpeciesName index:", idx_acc, "\n")
  cat("Both NA?", is.na(idx_species) && is.na(idx_acc), "\n")
}