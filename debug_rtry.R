#!/usr/bin/env Rscript
library(data.table)

# Test reading the problematic file
path <- 'data/43244_extract/43244.txt'

# Try to read just the header
cat("Attempting to read header from:", path, "\n")

# Method 1: Using fread with nrows=0
cat("\n=== Method 1: fread with nrows=0 ===\n")
hdr <- tryCatch({
  result <- fread(path, sep = '\t', nThread = 1, nrows = 0, header = TRUE, fill = TRUE)
  cat("Success! Columns found:\n")
  print(names(result))
  result
}, error = function(e) {
  cat("Error:", e$message, "\n")
  NULL
})

# Method 2: Read first line manually
cat("\n=== Method 2: Reading first line manually ===\n")
first_line <- readLines(path, n = 1, warn = FALSE)
cols <- strsplit(first_line, '\t')[[1]]
cat("Number of columns:", length(cols), "\n")
cat("Column 5 (SpeciesName):", cols[5], "\n")
cat("Column 7 (AccSpeciesName):", cols[7], "\n")

# Method 3: Using read.table with nrows=1
cat("\n=== Method 3: read.table ===\n")
hdr2 <- tryCatch({
  result <- read.table(path, sep = '\t', header = TRUE, nrows = 1, 
                      quote = '"', fill = TRUE, stringsAsFactors = FALSE)
  cat("Success! Columns found:\n")
  print(names(result))
  result
}, error = function(e) {
  cat("Error:", e$message, "\n")
  NULL
})

# Check for BOM or encoding issues
cat("\n=== Checking for BOM/encoding issues ===\n")
con <- file(path, "rb")
bytes <- readBin(con, "raw", n = 10)
close(con)
cat("First 10 bytes (hex):", paste(sprintf("%02X", as.integer(bytes)), collapse = " "), "\n")

# Check if there's a trailing empty column
cat("\n=== Checking for trailing tabs ===\n")
if (length(cols) > 0) {
  last_col <- cols[length(cols)]
  cat("Last column: [", last_col, "] (length:", nchar(last_col), ")\n", sep = "")
  if (nchar(last_col) == 0) {
    cat("WARNING: File has trailing tab creating empty column!\n")
  }
}