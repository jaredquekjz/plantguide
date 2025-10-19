#!/usr/bin/env Rscript

# Improved merge of trait and bioclim data using WFO normalization
# This script uses proper WFO backbone matching to maximize species overlap

suppressPackageStartupMessages({
  library(tidyverse)
  library(data.table)
})

cat("=== Improved Trait-Bioclim Merge with WFO Normalization ===\n\n")

# Configuration
config <- list(
  trait_data = "/home/olier/ellenberg/artifacts/model_data_complete_case_with_myco.csv",
  bioclim_data = "/home/olier/ellenberg/data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv",
  wfo_backbone = "/home/olier/ellenberg/data/classification.csv",
  output_file = "/home/olier/ellenberg/artifacts/model_data_trait_bioclim_merged_wfo.csv"
)

# Normalization function (from normalize_eive_to_wfo_EXACT.R)
normalize_name <- function(x) {
  x <- ifelse(is.na(x), '', trimws(x))
  # Remove botanical hybrid sign (×) and ASCII 'x' marker between tokens
  x <- gsub('^×[[:space:]]*', '', x, perl = TRUE)
  x <- gsub('[[:space:]]*×[[:space:]]*', ' ', x, perl = TRUE)
  x <- gsub('(^|[[:space:]])x([[:space:]]+)', ' ', x, perl = TRUE)
  x <- iconv(x, to = 'ASCII//TRANSLIT')
  x <- tolower(gsub('[\r\n]+', ' ', x))
  x <- gsub('[[:space:]]+', ' ', x)
  trimws(x)
}

# =============================================================================
# Step 1: Load and prepare WFO backbone
# =============================================================================

cat("Loading WFO backbone...\n")
wfo <- fread(config$wfo_backbone, encoding = 'UTF-8')

# Select relevant columns
wfo_cols <- c('taxonID', 'scientificName', 'acceptedNameUsageID', 'taxonomicStatus')
wfo <- wfo[, ..wfo_cols]

# Normalize WFO names
wfo[, norm := normalize_name(scientificName)]

# Create accepted name mapping
acc_map <- wfo[taxonomicStatus == 'Accepted', .(accepted_id = taxonID, accepted_scientificName = scientificName)]
wfo[, accepted_id := ifelse(taxonomicStatus == 'Accepted' | is.na(taxonomicStatus), taxonID, acceptedNameUsageID)]
wfo <- merge(wfo, acc_map, by.x = 'accepted_id', by.y = 'accepted_id', all.x = TRUE)
wfo[, wfo_accepted_name := fifelse(!is.na(accepted_scientificName), accepted_scientificName, scientificName)]

# Prioritize accepted names over synonyms
wfo[, rank := ifelse(taxonomicStatus == 'Accepted', 1L, 2L)]
setorderv(wfo, c('norm', 'rank'))

# Get best match per normalized name
wfo_best <- wfo[nzchar(norm), .SD[1], by = norm, 
                .SDcols = c('wfo_accepted_name', 'scientificName', 'taxonomicStatus')]

cat(sprintf("  Loaded %d WFO records (%d unique normalized names)\n", 
            nrow(wfo), nrow(wfo_best)))

# =============================================================================
# Step 2: Load trait data and match to WFO
# =============================================================================

cat("\nLoading trait data...\n")
trait_data <- read.csv(config$trait_data, stringsAsFactors = FALSE)
cat(sprintf("  Loaded %d species with traits\n", nrow(trait_data)))

# Normalize trait species names
trait_data$norm <- normalize_name(trait_data$wfo_accepted_name)

# Match to WFO backbone
trait_matched <- merge(
  trait_data,
  wfo_best[, .(norm, wfo_resolved = wfo_accepted_name)],
  by = "norm",
  all.x = TRUE
)

# Use resolved name if available, otherwise keep original
trait_matched$wfo_final <- ifelse(
  !is.na(trait_matched$wfo_resolved),
  trait_matched$wfo_resolved,
  trait_matched$wfo_accepted_name
)

n_trait_resolved <- sum(!is.na(trait_matched$wfo_resolved))
cat(sprintf("  Resolved %d/%d trait species through WFO backbone (%.1f%%)\n",
            n_trait_resolved, nrow(trait_matched),
            100 * n_trait_resolved / nrow(trait_matched)))

# =============================================================================
# Step 3: Load bioclim data and match to WFO
# =============================================================================

cat("\nLoading bioclim data...\n")
bioclim_data <- read.csv(config$bioclim_data, stringsAsFactors = FALSE)

# Filter to sufficient data only
bioclim_sufficient <- bioclim_data %>%
  filter(has_sufficient_data == TRUE)

cat(sprintf("  Loaded %d species with sufficient bioclim data\n", nrow(bioclim_sufficient)))

# Normalize GBIF species names
bioclim_sufficient$norm <- normalize_name(bioclim_sufficient$species)

# Match to WFO backbone
bioclim_matched <- merge(
  bioclim_sufficient,
  wfo_best[, .(norm, wfo_resolved = wfo_accepted_name)],
  by = "norm",
  all.x = TRUE
)

# Use resolved name if available, otherwise keep original
bioclim_matched$wfo_final <- ifelse(
  !is.na(bioclim_matched$wfo_resolved),
  bioclim_matched$wfo_resolved,
  bioclim_matched$species
)

n_bio_resolved <- sum(!is.na(bioclim_matched$wfo_resolved))
cat(sprintf("  Resolved %d/%d bioclim species through WFO backbone (%.1f%%)\n",
            n_bio_resolved, nrow(bioclim_matched),
            100 * n_bio_resolved / nrow(bioclim_matched)))

# =============================================================================
# Step 4: Merge datasets using normalized WFO names
# =============================================================================

cat("\n=== Merging Datasets ===\n")

# First try: match on WFO-resolved names
trait_matched$norm_final <- normalize_name(trait_matched$wfo_final)
bioclim_matched$norm_final <- normalize_name(bioclim_matched$wfo_final)

# Select bioclim columns
bio_cols <- c("norm_final", "n_occurrences", grep("^bio[0-9]+", names(bioclim_matched), value = TRUE))
bioclim_for_merge <- bioclim_matched[, bio_cols]

# Remove _mean suffix from bioclim columns
names(bioclim_for_merge) <- gsub("_mean$", "", names(bioclim_for_merge))

# Merge datasets
merged_data <- merge(
  trait_matched,
  bioclim_for_merge,
  by = "norm_final",
  all.x = FALSE,  # Inner join - only keep matches
  all.y = FALSE
)

cat(sprintf("\nMerge Results:\n"))
cat(sprintf("  Trait species: %d\n", nrow(trait_matched)))
cat(sprintf("  Bioclim species: %d\n", nrow(bioclim_matched)))
cat(sprintf("  Merged species: %d (%.1f%% of trait species)\n", 
            nrow(merged_data),
            100 * nrow(merged_data) / nrow(trait_matched)))

# =============================================================================
# Step 5: Compare with original simple matching
# =============================================================================

cat("\n=== Comparison with Simple Matching ===\n")

# Simple normalization (original approach)
simple_normalize <- function(x) {
  tolower(gsub("[[:space:]_-]+", "_", x))
}

trait_simple <- trait_data
trait_simple$simple_norm <- simple_normalize(trait_simple$wfo_accepted_name)

bioclim_simple <- bioclim_sufficient
bioclim_simple$simple_norm <- simple_normalize(bioclim_simple$species)

# Count simple matches
simple_matches <- intersect(trait_simple$simple_norm, bioclim_simple$simple_norm)
cat(sprintf("  Simple matching: %d matches\n", length(simple_matches)))
cat(sprintf("  WFO matching: %d matches\n", nrow(merged_data)))
cat(sprintf("  Improvement: +%d species (%.1f%% increase)\n",
            nrow(merged_data) - length(simple_matches),
            100 * (nrow(merged_data) - length(simple_matches)) / length(simple_matches)))

# =============================================================================
# Step 6: Find unmatched species for diagnostics
# =============================================================================

cat("\n=== Unmatched Species Analysis ===\n")

# Trait species not in merged
trait_unmatched <- trait_matched[!trait_matched$norm_final %in% merged_data$norm_final, ]
cat(sprintf("\nTrait species without bioclim: %d\n", nrow(trait_unmatched)))

# Check if any unmatched trait species have alternate names in GBIF
cat("\nChecking for potential matches with different names...\n")

# Sample of unmatched trait species
if (nrow(trait_unmatched) > 0) {
  cat("Sample unmatched trait species:\n")
  sample_unmatched <- head(trait_unmatched[, c("wfo_accepted_name", "wfo_final")], 10)
  print(sample_unmatched)
}

# Bioclim species not in merged
bioclim_unmatched <- bioclim_matched[!bioclim_matched$norm_final %in% merged_data$norm_final, ]
cat(sprintf("\nBioclim species without traits: %d\n", nrow(bioclim_unmatched)))

if (nrow(bioclim_unmatched) > 0) {
  cat("Sample unmatched bioclim species:\n")
  sample_bio_unmatched <- head(bioclim_unmatched[, c("species", "wfo_final", "n_occurrences")], 10)
  print(sample_bio_unmatched)
}

# =============================================================================
# Step 7: Clean and save merged dataset
# =============================================================================

cat("\n=== Finalizing Dataset ===\n")

# Remove duplicate/temporary columns
cols_to_remove <- c("norm", "norm_final", "wfo_resolved", "wfo_final", "species_norm")
merged_clean <- merged_data[, !names(merged_data) %in% cols_to_remove]

# Clean column names
names(merged_clean) <- gsub("\\.", "_", names(merged_clean))

# Create cleaner names for EIVE axes if present
if ("EIVEres_L" %in% names(merged_clean)) {
  merged_clean <- merged_clean %>%
    rename(
      L = EIVEres_L,
      T = EIVEres_T,
      M = EIVEres_M,
      R = EIVEres_R,
      N = EIVEres_N
    )
}

# Create cleaner names for traits if present
if ("Leaf_area__mm2_" %in% names(merged_clean)) {
  merged_clean <- merged_clean %>%
    rename(
      LA = Leaf_area__mm2_,
      LMA = LMA__g_m2_,
      H = Plant_height__m_,
      SM = Diaspore_mass__mg_,
      SSD = SSD_used__mg_mm3_
    )
}

# Save merged dataset
write.csv(merged_clean, config$output_file, row.names = FALSE)
cat(sprintf("\nSaved improved merged dataset to: %s\n", config$output_file))

# Summary statistics
cat("\n=== Final Summary ===\n")
cat(sprintf("Total species in merged dataset: %d\n", nrow(merged_clean)))

# Data completeness by axis
for (axis in c("L", "T", "M", "R", "N")) {
  if (axis %in% names(merged_clean)) {
    n_complete <- sum(!is.na(merged_clean[[axis]]))
    cat(sprintf("  %s: %d species with data (%.1f%%)\n", 
                axis, n_complete, 100 * n_complete / nrow(merged_clean)))
  }
}

# Bioclim variables included
bio_cols_final <- grep("^bio[0-9]+$", names(merged_clean), value = TRUE)
cat(sprintf("\nBioclim variables: %s\n", paste(bio_cols_final, collapse = ", ")))

# Occurrence statistics
if ("n_occurrences" %in% names(merged_clean)) {
  cat(sprintf("\nOccurrence statistics:\n"))
  cat(sprintf("  Min: %d\n", min(merged_clean$n_occurrences)))
  cat(sprintf("  Median: %d\n", median(merged_clean$n_occurrences)))
  cat(sprintf("  Mean: %.1f\n", mean(merged_clean$n_occurrences)))
  cat(sprintf("  Max: %d\n", max(merged_clean$n_occurrences)))
  cat(sprintf("  Species with ≥30 occurrences: %d (%.1f%%)\n",
              sum(merged_clean$n_occurrences >= 30),
              100 * sum(merged_clean$n_occurrences >= 30) / nrow(merged_clean)))
}

cat("\n✅ Improved merge complete!\n")