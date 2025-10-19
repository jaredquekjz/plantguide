#!/usr/bin/env Rscript
# Merge species-level soil summary columns (e.g., phh2o_*) into a bioclim species summary

suppressPackageStartupMessages({
  .libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))
  library(data.table)
  library(optparse)
})

option_list <- list(
  make_option(c("--bioclim_summary"), type = "character",
              default = "data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv",
              help = "Input bioclim summary CSV (has 'species' column)", metavar = "path"),
  make_option(c("--soil_summary"), type = "character",
              default = "data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary.csv",
              help = "Input soil summary CSV (has 'species' column)", metavar = "path"),
  make_option(c("--output"), type = "character",
              default = "data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_soil.csv",
              help = "Output merged CSV", metavar = "path")
)

opt <- parse_args(OptionParser(option_list = option_list,
                              description = "Augment a bioclim species summary with soil columns"))

normalize <- function(x) {
  x <- ifelse(is.na(x), '', trimws(x))
  x <- gsub('^×[[:space:]]*', '', x, perl = TRUE)
  x <- gsub('[[:space:]]*×[[:space:]]*', ' ', x, perl = TRUE)
  x <- gsub('(^|[[:space:]])x([[:space:]]+)', ' ', x, perl = TRUE)
  x <- iconv(x, to = 'ASCII//TRANSLIT')
  x <- tolower(gsub('[\r\n]+', ' ', x))
  x <- gsub('[[:space:]]+', ' ', x)
  trimws(x)
}

cat("===============================================\n")
cat("Augment bioclim summary with soil columns\n")
cat("===============================================\n\n")
cat(sprintf("Bioclim: %s\n", opt$bioclim_summary))
cat(sprintf("Soil:    %s\n", opt$soil_summary))
cat(sprintf("Output:  %s\n\n", opt$output))

bioclim <- fread(opt$bioclim_summary)
if (!'species' %in% names(bioclim)) stop("Bioclim summary must contain 'species'")
soil <- fread(opt$soil_summary)
if (!'species' %in% names(soil)) stop("Soil summary must contain 'species'")

# Normalize names for robust join
bioclim[, norm := normalize(species)]
soil[, norm := normalize(species)]

# Columns to add (soil properties only)
soil_cols <- grep('^(phh2o|soc|clay|sand|cec|nitrogen|bdod)_', names(soil), value = TRUE)
if (!length(soil_cols)) stop("No soil property columns found in soil summary")

# Keep one record per species in each (first occurrence if duplicates)
bioclim <- bioclim[, .SD[1], by = norm]
soil    <- soil[, c('norm', soil_cols), with = FALSE][, .SD[1], by = norm]

# Merge
merged <- merge(bioclim, soil, by = 'norm', all.x = TRUE, sort = FALSE)

# Restore original ordering by species label if present
if ('species' %in% names(bioclim)) {
  setorder(merged, species)
}

# Drop helper
merged[, norm := NULL]

dir.create(dirname(opt$output), recursive = TRUE, showWarnings = FALSE)
fwrite(merged, opt$output)

cat("\n===============================================\n")
cat("Merged summary saved\n")
cat("===============================================\n")
cat(sprintf("Rows:    %d\n", nrow(merged)))
cat(sprintf("Columns: %d\n", ncol(merged)))
cat(sprintf("Output:  %s\n", opt$output))

