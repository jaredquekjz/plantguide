#!/usr/bin/env Rscript
#' Organism Categorization for Explanations
#'
#' Adds animal_category column to organisms based on vernacular keyword matching.
#' Categories used for explanation aggregation in guild scorer.
#'
#' For animals: Categories like "bees", "spiders", "moths" for aggregation
#' For plants: Vernaculars used directly in headers/identifiers (no categorization needed)

suppressPackageStartupMessages({
  library(duckdb)
  library(dplyr)
  library(arrow)
  library(stringr)
})

# Source keyword definitions
# Get script directory
args <- commandArgs(trailingOnly = FALSE)
script_path <- sub("--file=", "", args[grep("--file=", args)])
if (length(script_path) == 0) {
  script_dir <- getwd()
} else {
  script_dir <- dirname(script_path)
}
source(file.path(script_dir, "lib/category_keywords.R"))

cat("=== Organism Categorization Pipeline ===\n\n")

# ============================================================================
# Configuration
# ============================================================================

DATA_DIR <- "/home/olier/ellenberg/data/taxonomy"
ORGANISMS_INPUT <- file.path(DATA_DIR, "organisms_vernacular_final.parquet")
ORGANISMS_OUTPUT <- file.path(DATA_DIR, "organisms_categorized.parquet")

# ============================================================================
# Categorization Logic
# ============================================================================

#' Pluralize category name correctly
#'
#' @param category Singular category name
#' @return Correctly pluralized category
pluralize_category <- function(category) {
  # Special cases (irregular plurals)
  irregular <- list(
    "fly" = "flies",
    "butterfly" = "butterflies",
    "whitefly" = "whiteflies",
    "sawfly" = "sawflies",
    "dragonfly" = "dragonflies",
    "damselfly" = "damselflies",
    "ladybug" = "ladybugs"
  )

  if (category %in% names(irregular)) {
    return(irregular[[category]])
  }

  # Already plural
  if (endsWith(category, "s")) {
    return(category)
  }

  # Default: add 's'
  return(paste0(category, "s"))
}

#' Categorize organism based on vernacular names
#'
#' @param vernacular_en English vernacular names (semicolon-separated)
#' @param vernacular_source Source of vernacular (P1/P2/P3/P4)
#' @return Category string (e.g., "bees", "spiders", "other")
categorize_organism <- function(vernacular_en, vernacular_source) {
  # If no vernacular, return "other"
  if (is.na(vernacular_en) || vernacular_en == "") {
    return("other")
  }

  # For P2/P4 derived categories, the vernacular IS the category
  if (vernacular_source %in% c("P2_derived_genus", "P4_derived_family")) {
    # Already pluralized categories like "bees", "moths", "spiders"
    return(tolower(vernacular_en))
  }

  # For P1/P3, match keywords from vernacular names
  vernacular_lower <- tolower(vernacular_en)

  # Get animal keywords
  keywords <- animal_keywords()

  # Check each category's keywords
  for (category in names(keywords)) {
    category_keywords <- keywords[[category]]

    # Check if any keyword matches
    for (keyword in category_keywords) {
      # Word boundary matching to avoid false positives
      pattern <- sprintf("\\b%s\\b", keyword)
      if (grepl(pattern, vernacular_lower)) {
        # Return correctly pluralized category
        return(pluralize_category(category))
      }
    }
  }

  # Default to "other"
  return("other")
}

# ============================================================================
# Main Pipeline
# ============================================================================

cat("Step 1: Load organisms with vernaculars\n")
organisms <- read_parquet(ORGANISMS_INPUT)
cat(sprintf("  Loaded %s organisms\n", format(nrow(organisms), big.mark = ",")))

cat("\nStep 2: Categorize organisms\n")
cat("  Applying keyword matching to vernacular names...\n")

# Vectorized categorization
organisms <- organisms %>%
  mutate(
    animal_category = mapply(
      categorize_organism,
      vernacular_name_en,
      vernacular_source,
      USE.NAMES = FALSE
    )
  )

# ============================================================================
# Statistics
# ============================================================================

cat("\n=== Categorization Results ===\n")

# Count by category
category_counts <- organisms %>%
  count(animal_category, sort = TRUE)

cat("\nTop 20 categories:\n")
print(category_counts %>% head(20), n = 20)

# Count by source
cat("\n\nCategories by vernacular source:\n")
source_summary <- organisms %>%
  group_by(vernacular_source, animal_category) %>%
  summarise(count = n(), .groups = "drop") %>%
  arrange(vernacular_source, desc(count))
print(source_summary %>% head(30), n = 30)

# Coverage statistics
total_organisms <- nrow(organisms)
categorized <- sum(organisms$animal_category != "other")
pct_categorized <- 100 * categorized / total_organisms

cat(sprintf("\n\nTotal organisms: %s\n", format(total_organisms, big.mark = ",")))
cat(sprintf("Categorized: %s (%.1f%%)\n",
            format(categorized, big.mark = ","), pct_categorized))
cat(sprintf("Other: %s (%.1f%%)\n",
            format(total_organisms - categorized, big.mark = ","),
            100 - pct_categorized))

# ============================================================================
# Save Results
# ============================================================================

cat(sprintf("\n\nStep 3: Save categorized organisms to: %s\n", ORGANISMS_OUTPUT))
write_parquet(organisms, ORGANISMS_OUTPUT)

cat("\n✓ Categorization complete\n")
cat(sprintf("\nOutput columns: %s\n", paste(names(organisms), collapse = ", ")))
cat(sprintf("\nNew column added: animal_category (%s unique values)\n",
            length(unique(organisms$animal_category))))
