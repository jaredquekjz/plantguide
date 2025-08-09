#!/usr/bin/env Rscript
# Debug spell to divine WorldFlora column names
suppressPackageStartupMessages({
  library(data.table)
  library(WorldFlora)
})

# Test with a few sample names
test_names <- c("Abies alba", "Acer pseudoplatanus", "Yucca filamentosa")

# Load WFO data
wfo_csv <- "data/WFO/classification.csv"
hdr <- names(fread(wfo_csv, nrows = 0, encoding = 'UTF-8'))
has <- function(x) any(tolower(hdr) == tolower(x))
col_of <- function(x) hdr[tolower(hdr) == tolower(x)][1]
need <- c('taxonID','scientificName','acceptedNameUsageID','taxonomicStatus')
sel <- vapply(need, function(x) if (has(x)) col_of(x) else NA_character_, character(1))
WFO.slim <- as.data.frame(fread(wfo_csv, select = sel, encoding = 'UTF-8'))
setnames(WFO.slim, sel, need)

# Run WorldFlora matching
message("Testing WorldFlora::WFO.match output structure...")
result <- WFO.match(test_names, WFO.data = WFO.slim, Fuzzy = 1)

# Show column names
message("\nColumn names returned by WorldFlora::WFO.match:")
print(names(result))

# Show first few rows
message("\nFirst few rows of result:")
print(head(result, 3))

# Check for ID columns
message("\nChecking for ID-like columns:")
id_candidates <- grep("ID|id|Id", names(result), value = TRUE)
print(id_candidates)