#!/usr/bin/env Rscript
#
# Pure R Extraction: Insect-Fungal Parasite Network (NO DuckDB)
#
# Purpose:
#   Extract entomopathogenic fungus → insect/mite relationships
#   to enable specific biological control matching
#
# Learnings applied:
#   - Use %in% TRUE for boolean subsetting (excludes NA)
#   - Use n_distinct() for counting unique values
#   - Set locale to C for ASCII sorting (matches Python)
#   - Handle NA explicitly with !is.na()
#
# Usage:
#   Rscript shipley_checks/src/Stage_4/EXPERIMENT_extract_insect_fungal_parasites_pure_r.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(readr)
  library(purrr)
  library(tidyr)
})

# Set locale to C for ASCII sorting (matches Python's default sorted())
Sys.setlocale("LC_COLLATE", "C")

cat("================================================================================\n")
cat("PURE R EXTRACTION: Insect-Fungal Parasite Network (NO DuckDB)\n")
cat("================================================================================\n")
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Paths
GLOBI_FULL_PATH <- "data/stage1/globi_interactions_original.parquet"

# ==============================================================================
# Extract Fungus → Insect/Mite Parasitic Relationships
# ==============================================================================

cat("Extracting fungus → insect/mite parasitic relationships from GloBI...\n")
cat("  (Scanning 20M+ rows - may take 2-3 minutes)\n\n")

# Load full GloBI interactions
globi_full <- read_parquet(GLOBI_FULL_PATH)

# Filter to entomopathogenic relationships
result <- globi_full %>%
  filter(
    sourceTaxonKingdomName == 'Fungi',
    targetTaxonKingdomName == 'Animalia',
    targetTaxonClassName %in% c('Insecta', 'Arachnida'),
    interactionTypeName %in% c('pathogenOf', 'parasiteOf', 'parasitoidOf', 'hasHost', 'kills')
  ) %>%
  group_by(
    herbivore = targetTaxonName,
    herbivore_family = targetTaxonFamilyName,
    herbivore_order = targetTaxonOrderName,
    herbivore_class = targetTaxonClassName
  ) %>%
  summarize(
    entomopathogenic_fungi = list(unique(sourceTaxonName)),
    fungal_parasite_count = n_distinct(sourceTaxonName),
    .groups = 'drop'
  ) %>%
  filter(fungal_parasite_count > 0) %>%
  arrange(desc(fungal_parasite_count))

cat("  ✓ Extracted", nrow(result), "herbivores with fungal parasites\n\n")

# ==============================================================================
# Convert to CSV Format
# ==============================================================================

cat("Preparing CSV output with sorted rows and sorted list columns...\n")

# Sort by herbivore, then by taxonomic hierarchy for deterministic output
# (Some herbivore names appear across different taxonomic groups)
result_csv <- result %>%
  arrange(herbivore, herbivore_family, herbivore_order, herbivore_class)

# Convert list column to sorted pipe-separated strings
result_csv$entomopathogenic_fungi <- map_chr(result_csv$entomopathogenic_fungi, function(x) {
  if (length(x) == 0) {
    return('')
  } else {
    return(paste(sort(x), collapse = '|'))
  }
})

# Replace NA with empty string in taxonomic columns to match Python
result_csv <- result_csv %>%
  mutate(
    herbivore_family = ifelse(is.na(herbivore_family), '', herbivore_family),
    herbivore_order = ifelse(is.na(herbivore_order), '', herbivore_order)
  )

cat("  ✓ Lists converted to sorted pipe-separated strings\n\n")

# ==============================================================================
# Save CSV
# ==============================================================================

output_file <- "shipley_checks/validation/insect_fungal_parasites_pure_r.csv"

cat("Saving to", output_file, "...\n")
write_csv(result_csv, output_file)
cat("  ✓ Saved\n\n")

# ==============================================================================
# Generate Checksums
# ==============================================================================

cat("Generating checksums...\n")

md5_result <- system2("md5sum", args = output_file, stdout = TRUE)
md5_hash <- trimws(strsplit(md5_result, "\\s+")[[1]][1])

sha256_result <- system2("sha256sum", args = output_file, stdout = TRUE)
sha256_hash <- trimws(strsplit(sha256_result, "\\s+")[[1]][1])

cat("  MD5:   ", md5_hash, "\n")
cat("  SHA256:", sha256_hash, "\n\n")

# Save checksums
checksum_file <- "shipley_checks/validation/insect_fungal_parasites_pure_r.checksums.txt"
writeLines(
  c(
    paste0("MD5:    ", md5_hash),
    paste0("SHA256: ", sha256_hash),
    "",
    paste0("File: ", output_file),
    paste0("Size: ", format(file.size(output_file), big.mark = ","), " bytes"),
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  ),
  checksum_file
)

cat("  ✓ Checksums saved to", checksum_file, "\n\n")

# ==============================================================================
# Summary Statistics
# ==============================================================================

cat("================================================================================\n")
cat("SUMMARY STATISTICS\n")
cat("================================================================================\n")

total_herbivores <- nrow(result_csv)
total_relationships <- sum(result_csv$fungal_parasite_count)

# Count unique fungi
unique_fungi <- result %>%
  select(entomopathogenic_fungi) %>%
  unnest(entomopathogenic_fungi) %>%
  distinct(entomopathogenic_fungi) %>%
  nrow()

avg_fungi <- mean(result_csv$fungal_parasite_count)
max_fungi <- max(result_csv$fungal_parasite_count)

cat("Total herbivores:", format(total_herbivores, big.mark = ","), "\n")
cat("Total fungus-herbivore relationships:", format(total_relationships, big.mark = ","), "\n")
cat("Unique entomopathogenic fungi:", format(unique_fungi, big.mark = ","), "\n")
cat(sprintf("Average fungi per herbivore: %.1f\n", avg_fungi))
cat("Max fungi per herbivore:", max_fungi, "\n\n")

cat("================================================================================\n")
cat("Completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("================================================================================\n")
