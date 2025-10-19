#!/usr/bin/env Rscript
# Merge trait dataset with bioclim and soil species summaries using WFO normalization

suppressPackageStartupMessages({
  .libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))
  library(data.table)
  library(optparse)
})

option_list <- list(
  make_option(c("--trait_csv"), type = "character",
              default = "artifacts/model_data_bioclim_subset.csv",
              help = "Path to trait dataset CSV (species-level)", metavar = "path"),
  make_option(c("--bioclim_summary"), type = "character",
              default = "data/bioclim_extractions_bioclim_first/summary_stats/species_bioclim_summary.csv",
              help = "Path to species-level bioclim summary CSV", metavar = "path"),
  make_option(c("--soil_summary"), type = "character",
              default = "data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary.csv",
              help = "Path to species-level soil summary CSV", metavar = "path"),
  make_option(c("--wfo_backbone"), type = "character",
              default = "data/classification.csv",
              help = "Path to WFO backbone classification CSV", metavar = "path"),
  make_option(c("--output"), type = "character",
              default = "artifacts/model_data_trait_bioclim_soil_merged_wfo.csv",
              help = "Output CSV path", metavar = "path")
)

opt <- parse_args(OptionParser(option_list = option_list))

cat("===============================================\n")
cat("Merge trait + bioclim + soil with WFO\n")
cat("===============================================\n\n")

normalize_name <- function(x) {
  x <- ifelse(is.na(x), '', trimws(x))
  x <- gsub('^×[[:space:]]*', '', x, perl = TRUE)
  x <- gsub('[[:space:]]*×[[:space:]]*', ' ', x, perl = TRUE)
  x <- gsub('(^|[[:space:]])x([[:space:]]+)', ' ', x, perl = TRUE)
  x <- iconv(x, to = 'ASCII//TRANSLIT')
  x <- tolower(gsub('[\r\n]+', ' ', x))
  x <- gsub('[[:space:]]+', ' ', x)
  trimws(x)
}

cat("Loading WFO backbone...\n")
wfo <- fread(opt$wfo_backbone, encoding = 'UTF-8')
# Build mapping: normalized name -> accepted WFO name
wfo[, norm := normalize_name(scientificName)]
acc_map <- wfo[taxonomicStatus == 'Accepted', .(accepted_id = taxonID, accepted_scientificName = scientificName)]
wfo[, accepted_id := ifelse(taxonomicStatus == 'Accepted' | is.na(taxonomicStatus), taxonID, acceptedNameUsageID)]
wfo <- merge(wfo, acc_map, by = 'accepted_id', all.x = TRUE)
wfo[, wfo_accepted_name := fifelse(!is.na(accepted_scientificName), accepted_scientificName, scientificName)]
wfo[, rank := ifelse(taxonomicStatus == 'Accepted', 1L, 2L)]
setorderv(wfo, c('norm', 'rank'))
wfo_best <- wfo[nzchar(norm), .SD[1], by = norm, .SDcols = c('wfo_accepted_name')]

cat("Loading trait dataset...\n")
trait <- fread(opt$trait_csv)
if (!'wfo_accepted_name' %in% names(trait)) {
  stop("Trait CSV must contain column 'wfo_accepted_name'.")
}
trait[, norm := normalize_name(wfo_accepted_name)]

cat("Loading bioclim summary...\n")
clim <- fread(opt$bioclim_summary)
if (!'species' %in% names(clim)) stop("Bioclim summary must have column 'species'.")
# Keep sufficient data
if ('has_sufficient_data' %in% names(clim)) clim <- clim[has_sufficient_data == TRUE]
clim[, norm := normalize_name(species)]
clim <- merge(clim, wfo_best, by = 'norm', all.x = TRUE)
clim[, wfo_final := fifelse(!is.na(wfo_accepted_name), wfo_accepted_name, species)]
# Deduplicate in case of many-to-one mappings
clim <- clim[, .SD[1], by = wfo_final]
# Rename occurrence count to bioclim-specific to avoid conflicts
if ('n_occurrences' %in% names(clim)) setnames(clim, 'n_occurrences', 'n_occurrences_bioclim')
if ('has_sufficient_data' %in% names(clim)) setnames(clim, 'has_sufficient_data', 'has_sufficient_data_bioclim')

cat("Loading soil summary...\n")
soil <- fread(opt$soil_summary)
if (!'species' %in% names(soil)) stop("Soil summary must have column 'species'.")
soil[, norm := normalize_name(species)]
soil <- merge(soil, wfo_best, by = 'norm', all.x = TRUE)
soil[, wfo_final := fifelse(!is.na(wfo_accepted_name), wfo_accepted_name, species)]
soil <- soil[, .SD[1], by = wfo_final]
if ('n_occurrences' %in% names(soil)) setnames(soil, 'n_occurrences', 'n_occurrences_soil')
if ('has_sufficient_data' %in% names(soil)) setnames(soil, 'has_sufficient_data', 'has_sufficient_data_soil')

# Prepare columns to bring from climate & soil
bio_cols <- grep('^bio[0-9]+', names(clim), value = TRUE)
soil_cols <- grep('^(phh2o|soc|clay|sand|cec|nitrogen|bdod)_', names(soil), value = TRUE)

cat("Merging datasets by WFO accepted names...\n")
# Trait is canonical; merge climate and soil onto it using trait$norm -> exact WFO name
setnames(trait, 'wfo_accepted_name', 'wfo_key')
clim_for_join <- clim[, c('wfo_final', 'n_occurrences_bioclim', 'has_sufficient_data_bioclim', bio_cols), with = FALSE]
soil_for_join <- soil[, c('wfo_final', 'n_occurrences_soil', 'has_sufficient_data_soil', soil_cols), with = FALSE]

merged <- merge(trait, clim_for_join, by.x = 'wfo_key', by.y = 'wfo_final', all.x = FALSE, all.y = FALSE, sort = FALSE)
merged <- merge(merged, soil_for_join, by.x = 'wfo_key', by.y = 'wfo_final', all.x = FALSE, all.y = FALSE, sort = FALSE)

# Restore column name
setnames(merged, 'wfo_key', 'wfo_accepted_name')

# Save
dir.create(dirname(opt$output), recursive = TRUE, showWarnings = FALSE)
fwrite(merged, opt$output)

cat("\n===============================================\n")
cat("Merged dataset saved\n")
cat("===============================================\n")
cat(sprintf("Species: %d\n", nrow(merged)))
cat(sprintf("Columns: %d\n", ncol(merged)))
cat(sprintf("Output:  %s\n", opt$output))

