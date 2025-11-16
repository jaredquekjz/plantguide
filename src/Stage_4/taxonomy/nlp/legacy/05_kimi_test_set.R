#!/usr/bin/env Rscript
#' Generate Kimi AI Test Set
#'
#' Creates tricky test cases with both English and Chinese vernaculars
#' for testing Kimi V2 AI classification accuracy.
#'
#' Focus on cases where vector classification FAILED.
#'
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(duckdb)
  library(dplyr)
  library(arrow)
})

cat(rep("=", 80), "\n", sep = "")
cat("Kimi AI Test Set Generator\n")
cat(rep("=", 80), "\n\n", sep = "")

# ============================================================================
# Configuration
# ============================================================================

ENGLISH_VERN <- "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations.parquet"
CHINESE_VERN <- "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations_chinese.parquet"
BILINGUAL_RESULTS <- "/home/olier/ellenberg/data/taxonomy/vector_classifications_bilingual.parquet"

OUTPUT_FILE <- "/home/olier/ellenberg/reports/taxonomy/kimi_test_set.txt"

# Tricky cases from our failure analysis
# Include: compound names, host-parasite, phonetic confusion
TRICKY_GENERA <- c(
  # Host/habitat confusion
  "Tanysphyrus",   # duckweed weevil → should be weevils
  "Glycobius",     # sugar maple borer → should be beetles
  "Paragrilus",    # metallic woodborer → should be beetles
  "Heilipus",      # avocado weevil → should be weevils
  "Oxya",          # rice grasshopper → should be grasshoppers

  # Phonetic/word confusion
  "Euschemon",     # regent skipper → should be butterflies
  "Eidolon",       # straw-colored fruit bat → should be bats

  # Generic/ambiguous names
  "Symbrenthia",   # jesters → should be butterflies
  "Rhizophora",    # red mangrove → should be trees
  "Liparis",       # orchids → should be orchids

  # Correct cases for comparison
  "Boloria",       # fritillary → butterflies
  "Arctia",        # tiger moth → moths
  "Apis",          # honey bee → bees
  "Bombus",        # bumblebee → bees
  "Papilio",       # swallowtail → butterflies

  # More challenging insects
  "Agrilus",       # emerald ash borer
  "Sitophilus",    # grain weevil
  "Diabrotica",    # cucumber beetle
  "Meloidogyne",   # root-knot nematode
  "Thrips"         # thrips
)

# ============================================================================
# Load Data
# ============================================================================

cat("Loading data...\n")
english <- read_parquet(ENGLISH_VERN)
chinese <- read_parquet(CHINESE_VERN)
results <- read_parquet(BILINGUAL_RESULTS)
cat(sprintf("  English: %d genera\n", nrow(english)))
cat(sprintf("  Chinese: %d genera\n", nrow(chinese)))
cat("\n")

# ============================================================================
# Extract Vernaculars
# ============================================================================

cat("Extracting vernaculars for test set...\n\n")

test_cases <- list()

for (genus in TRICKY_GENERA) {
  # Get English vernaculars
  eng_row <- english %>% filter(genus == !!genus)
  eng_vern <- if (nrow(eng_row) > 0) eng_row$vernaculars_all[1] else NA_character_

  # Get Chinese vernaculars
  chn_row <- chinese %>% filter(genus == !!genus)
  chn_vern <- if (nrow(chn_row) > 0) chn_row$vernaculars_all[1] else NA_character_

  # Get vector classification
  result_row <- results %>% filter(genus == !!genus)
  vector_cat <- if (nrow(result_row) > 0) result_row$category_en[1] else NA_character_

  # Truncate if too long
  if (!is.na(eng_vern) && nchar(eng_vern) > 150) {
    eng_vern <- paste0(substr(eng_vern, 1, 150), "...")
  }
  if (!is.na(chn_vern) && nchar(chn_vern) > 100) {
    chn_vern <- paste0(substr(chn_vern, 1, 100), "...")
  }

  test_cases[[length(test_cases) + 1]] <- list(
    genus = genus,
    english = eng_vern,
    chinese = chn_vern,
    vector_category = vector_cat
  )
}

# ============================================================================
# Generate Output
# ============================================================================

cat("Generating formatted test set...\n\n")

output_lines <- c()
output_lines <- c(output_lines, "# Kimi AI Test Set - Organism Classification")
output_lines <- c(output_lines, "# Copy-paste format: Genus: English vernaculars | Chinese vernaculars")
output_lines <- c(output_lines, "# Vector classification shown in comments for reference")
output_lines <- c(output_lines, "")
output_lines <- c(output_lines, "Instructions: Classify each genus into ONE functional category:")
output_lines <- c(output_lines, "bees, butterflies, moths, beetles, weevils, grasshoppers, flies, wasps, ants, dragonflies, birds, bats, mammals, trees, shrubs, flowers, orchids, grasses")
output_lines <- c(output_lines, "")
output_lines <- c(output_lines, "IMPORTANT:")
output_lines <- c(output_lines, "- Many insect names follow '[host plant] + [insect type]' pattern")
output_lines <- c(output_lines, "- Example: 'oak gall wasp' IS a wasp, NOT oak")
output_lines <- c(output_lines, "- Focus on what the ORGANISM IS, not what it eats or where it lives")
output_lines <- c(output_lines, "")
output_lines <- c(output_lines, "---")
output_lines <- c(output_lines, "")

for (case in test_cases) {
  genus <- case$genus
  eng <- if (!is.na(case$english)) case$english else "(no English names)"
  chn <- if (!is.na(case$chinese)) case$chinese else "(no Chinese names)"
  vec_cat <- if (!is.na(case$vector_category)) case$vector_category else "uncategorized"

  # Format line
  line <- sprintf("%s: %s | %s", genus, eng, chn)
  output_lines <- c(output_lines, line)
  output_lines <- c(output_lines, sprintf("# Vector said: %s", vec_cat))
  output_lines <- c(output_lines, "")
}

# ============================================================================
# Write Output
# ============================================================================

writeLines(output_lines, OUTPUT_FILE)

cat(sprintf("✓ Wrote test set to: %s\n", OUTPUT_FILE))
cat(sprintf("  Total test cases: %d\n\n", length(test_cases)))

# ============================================================================
# Display Preview
# ============================================================================

cat(rep("=", 80), "\n", sep = "")
cat("Preview (first 5 cases):\n")
cat(rep("=", 80), "\n\n", sep = "")

preview_lines <- head(output_lines[output_lines != ""], 30)
cat(paste(preview_lines, collapse = "\n"))

cat("\n\n")
cat(rep("=", 80), "\n", sep = "")
cat("Complete - Copy from: ", OUTPUT_FILE, "\n", sep = "")
cat(rep("=", 80), "\n\n", sep = "")
