#!/usr/bin/env Rscript
#' Vernacular Category Derivation Library
#'
#' @description
#' Core functions for deriving vernacular categories from species-level
#' vernacular names using word frequency analysis. This library provides
#' organism-agnostic functions that work for both plants and animals at
#' both genus and family taxonomic levels.
#'
#' @details
#' ## Algorithm Overview
#'
#' The derivation algorithm follows these steps:
#' 1. **Aggregate**: Combine all species vernacular names within each taxon (genus/family)
#' 2. **Tokenize**: Extract individual words (3+ letters, lowercase)
#' 3. **Filter**: Remove common stopwords ("the", "and", "of", etc.)
#' 4. **Count**: Calculate word frequencies
#' 5. **Score**: Match words against category keywords (oak, bee, moth, etc.)
#' 6. **Assign**: If dominant category ≥10% of total words, assign that category
#'
#' ## Example
#'
#' For genus Quercus with species vernaculars:
#' - "white oak", "red oak", "live oak", "oak tree", "English oak"
#' - Tokenized: white, oak, red, oak, live, oak, oak, tree, english, oak
#' - Word freq: oak(5), white(1), red(1), live(1), tree(1), english(1)
#' - Category scores: oak=5 (keyword match)
#' - Total words: 10
#' - Percentage: 5/10 = 50% > 10% threshold
#' - **Result**: Quercus → "oaks"
#'
#' @section Functions:
#' - `tokenize_vernaculars()`: Extract and clean words from text
#' - `calculate_category_scores()`: Score categories by keyword frequency
#' - `derive_vernacular_categories()`: Main derivation pipeline
#' - `calculate_coverage_impact()`: Assess potential coverage improvement
#'
#' @author Claude Code
#' @date 2025-11-15

library(dplyr)
library(stringr)
library(duckdb)

# Source keyword definitions
script_dir <- dirname(sys.frame(1)$ofile)
source(file.path(script_dir, "category_keywords.R"))

# ==============================================================================
# TEXT PROCESSING FUNCTIONS
# ==============================================================================

#' Tokenize vernacular names into individual words
#'
#' @description
#' Extracts individual words from vernacular name text, applying lowercase
#' conversion, word boundary detection, and stopword filtering.
#'
#' @param text Character vector of vernacular names (can be concatenated strings)
#' @param stopwords Character vector of words to exclude (default: common English stopwords)
#' @param min_length Minimum word length to keep (default: 3)
#'
#' @return Character vector of cleaned, filtered words
#'
#' @details
#' Processing steps:
#' 1. Convert to lowercase
#' 2. Extract words using regex `\b[a-z]{min_length,}\b`
#' 3. Remove words in stopwords list
#' 4. Return flattened character vector
#'
#' Word boundaries (`\b`) ensure we match whole words only, avoiding
#' partial matches like "the" in "gather".
#'
#' @examples
#' tokenize_vernaculars("White Oak and Red Oak trees")
#' # Returns: c("white", "oak", "red", "oak", "trees")
#'
#' tokenize_vernaculars("The big oak", stopwords = c("the", "big"))
#' # Returns: c("oak")
#'
#' @export
tokenize_vernaculars <- function(text,
                                  stopwords = default_stopwords(),
                                  min_length = 3) {

  # Convert to lowercase and extract words (3+ letters by default)
  pattern <- sprintf("\\b[a-z]{%d,}\\b", min_length)
  words <- str_extract_all(tolower(text), pattern) %>%
    unlist()

  # Remove stopwords
  words[!words %in% stopwords]
}

#' Calculate category scores from word frequencies
#'
#' @description
#' Scores each category by summing the frequencies of its associated keywords.
#' Returns categories ranked by score, along with percentage of total words.
#'
#' @param words Character vector of tokenized words
#' @param category_keywords Named list mapping categories to keyword vectors
#'
#' @return Data frame with columns:
#'   - category: Category name
#'   - score: Sum of keyword frequencies
#'   - percentage: (score / total_words) * 100
#'   - n_keyword_matches: Number of distinct keywords matched
#'
#' Sorted by score descending (highest scoring category first).
#'
#' @details
#' ## Scoring Algorithm
#'
#' For each category:
#' 1. Get its keyword list (e.g., oak: c("oak", "oaks"))
#' 2. Sum frequencies of matching keywords in word_freq table
#' 3. Calculate percentage: (category_score / total_words) * 100
#' 4. Only include categories with score > 0
#'
#' ## Example
#'
#' ```r
#' words <- c("oak", "oak", "tree", "white", "oak")
#' keywords <- list(oak = c("oak", "oaks"), tree = c("tree", "trees"))
#' calculate_category_scores(words, keywords)
#'
#' # Returns:
#' #   category score percentage n_keyword_matches
#' # 1      oak     3       60.0                 1
#' # 2     tree     1       20.0                 1
#' ```
#'
#' @export
calculate_category_scores <- function(words, category_keywords) {

  # Count word frequencies
  word_freq <- table(words)
  total_words <- sum(word_freq)

  # Score each category
  scores <- lapply(names(category_keywords), function(cat) {
    keywords <- category_keywords[[cat]]

    # Sum frequencies for all keywords in this category
    keyword_freqs <- word_freq[keywords]
    keyword_freqs <- keyword_freqs[!is.na(keyword_freqs)]  # Remove unmatched

    score <- sum(keyword_freqs)
    n_matches <- length(keyword_freqs)

    data.frame(
      category = cat,
      score = as.numeric(score),
      percentage = 100 * as.numeric(score) / total_words,
      n_keyword_matches = n_matches,
      stringsAsFactors = FALSE
    )
  })

  # Combine and filter
  bind_rows(scores) %>%
    filter(score > 0) %>%
    arrange(desc(score))
}

# ==============================================================================
# MAIN DERIVATION PIPELINE
# ==============================================================================

#' Derive vernacular categories for taxonomic groups
#'
#' @description
#' Main pipeline function that derives vernacular categories for genera or
#' families using word frequency analysis of their species' vernacular names.
#'
#' @param con DuckDB connection object
#' @param input_file Path to parquet file containing organism data
#' @param group_col Column name to group by: "family" or "genus"
#' @param category_keywords Named list of category keywords (from category_keywords.R)
#' @param threshold Minimum percentage for category assignment (default: 0.10 = 10%)
#' @param verbose Print progress messages (default: TRUE)
#'
#' @return Data frame with derived categories, containing columns:
#'   - [group_col]: Taxonomic group name (family or genus)
#'   - n_species_with_vernaculars: Number of species with vernacular names
#'   - dominant_category: The highest-scoring category
#'   - dominant_score: Raw word count for dominant category
#'   - total_word_count: Total words analyzed for this group
#'   - category_percentage: (dominant_score / total_word_count) * 100
#'   - top_10_words: Most frequent words with counts "word(count), ..."
#'   - derived_vernacular: Pluralized category name for assignment
#'
#' Sorted by n_species_with_vernaculars descending.
#'
#' @details
#' ## Input File Requirements
#'
#' The input parquet must contain:
#' - [group_col]: Taxonomic group (genus or family)
#' - scientific_name: Species scientific name
#' - inat_all_vernaculars: Vernacular names (semicolon-separated)
#'
#' ## Processing Steps
#'
#' For each unique value in [group_col]:
#' 1. Filter to species in that group with vernaculars
#' 2. Concatenate all vernacular strings
#' 3. Tokenize and count word frequencies
#' 4. Calculate category scores using keywords
#' 5. If dominant category ≥ threshold%, assign derived vernacular
#' 6. Pluralize category name (oak → oaks, unless already plural)
#'
#' ## Threshold Rationale
#'
#' Default 10% threshold ensures the category is meaningfully represented.
#' Lower thresholds risk spurious matches; higher thresholds reduce coverage.
#'
#' ## Performance
#'
#' For 11,000 species grouped into 1,000 genera: ~10-30 seconds
#'
#' @examples
#' \dontrun{
#' con <- dbConnect(duckdb::duckdb())
#' keywords <- plant_keywords()
#'
#' result <- derive_vernacular_categories(
#'   con = con,
#'   input_file = "data/taxonomy/plants_vernacular_final.parquet",
#'   group_col = "genus",
#'   category_keywords = keywords,
#'   threshold = 0.10
#' )
#'
#' head(result)
#' # genus n_species dominant_category dominant_score category_percentage derived_vernacular
#' # Quercus      70               oak            120                60.0               oaks
#' # Salix        53            willow             85                45.2            willows
#' }
#'
#' @export
derive_vernacular_categories <- function(con,
                                         input_file,
                                         group_col,
                                         category_keywords,
                                         threshold = 0.10,
                                         verbose = TRUE) {

  # Validate inputs
  stopifnot(group_col %in% c("family", "genus"))
  stopifnot(threshold > 0 && threshold <= 1.0)

  # Load data via DuckDB (fast parquet reading)
  if (verbose) {
    cat(sprintf("Loading data from: %s\n", basename(input_file)))
  }

  data <- dbGetQuery(con, sprintf("
    SELECT
      %s as taxon_group,
      scientific_name,
      inat_all_vernaculars as vernacular_names
    FROM read_parquet('%s')
    WHERE %s IS NOT NULL
      AND inat_all_vernaculars IS NOT NULL
  ", group_col, input_file, group_col))

  if (verbose) {
    cat(sprintf("Species with %s + vernacular names: %s\n\n",
                group_col, format(nrow(data), big.mark = ",")))
  }

  # Process each taxonomic group
  results <- list()
  unique_groups <- unique(data$taxon_group)

  if (verbose) {
    cat(sprintf("Processing %s unique %ss...\n",
                format(length(unique_groups), big.mark = ","), group_col))
  }

  for (i in seq_along(unique_groups)) {
    taxon <- unique_groups[i]

    # Progress indicator
    if (verbose && i %% 100 == 0) {
      cat(sprintf("  Processed %s/%s %ss...\r",
                  format(i, big.mark = ","),
                  format(length(unique_groups), big.mark = ","),
                  group_col))
      flush.console()
    }

    # Skip NA or invalid taxa
    if (is.na(taxon) || taxon == "" || taxon == "NA") next

    # Get all vernaculars for this taxon
    taxon_data <- filter(data, taxon_group == taxon)
    n_species <- nrow(taxon_data)

    # Combine all vernacular names into single string
    all_vernaculars <- paste(taxon_data$vernacular_names, collapse = " ")

    # Tokenize and count words
    words <- tokenize_vernaculars(all_vernaculars)

    if (length(words) == 0) next

    # Calculate word frequencies for top words display
    word_freq <- table(words)
    top_words <- head(sort(word_freq, decreasing = TRUE), 10)
    top_words_str <- paste(
      sprintf("%s(%d)", names(top_words), as.numeric(top_words)),
      collapse = ", "
    )

    # Calculate category scores
    cat_scores <- calculate_category_scores(words, category_keywords)

    if (nrow(cat_scores) == 0) next

    # Get dominant category
    dominant <- cat_scores[1, ]

    # Only keep if dominant category meets threshold
    if (dominant$percentage >= threshold * 100) {

      # Pluralize category name if needed
      # Check if category already ends with 's'
      derived_name <- if (!endsWith(dominant$category, "s")) {
        paste0(dominant$category, "s")
      } else {
        dominant$category
      }

      # Store result
      results[[taxon]] <- data.frame(
        taxon = taxon,
        n_species_with_vernaculars = n_species,
        dominant_category = dominant$category,
        dominant_score = dominant$score,
        total_word_count = length(words),
        category_percentage = dominant$percentage,
        top_10_words = top_words_str,
        derived_vernacular = derived_name,
        stringsAsFactors = FALSE
      )
    }
  }

  if (verbose) cat("\n")

  # Combine all results
  if (length(results) == 0) {
    warning("No categories derived. Check threshold or keyword coverage.")
    return(data.frame())
  }

  result_df <- bind_rows(results)

  # Rename taxon column to match group_col
  names(result_df)[names(result_df) == "taxon"] <- group_col

  # Sort by species count (most coverage first)
  result_df %>%
    arrange(desc(n_species_with_vernaculars))
}

# ==============================================================================
# COVERAGE ANALYSIS FUNCTIONS
# ==============================================================================

#' Calculate coverage impact of derived categories
#'
#' @description
#' Analyzes how many currently uncategorized organisms would gain a category
#' if derived vernaculars are applied.
#'
#' @param con DuckDB connection
#' @param input_file Path to organism parquet file
#' @param derived_file Path to derived categories parquet file
#' @param group_col Column name: "family" or "genus"
#' @param verbose Print detailed results (default: TRUE)
#'
#' @return List with elements:
#'   - total_uncategorized: Count of organisms without vernaculars
#'   - would_be_covered: Count that would gain derived category
#'   - coverage_improvement_pct: Percentage point improvement
#'   - coverage_improvement_abs: Absolute improvement percentage
#'
#' @details
#' Queries the input file for organisms where `vernacular_source = 'uncategorized'`,
#' then counts how many have a matching entry in the derived categories file.
#'
#' This represents the **potential** coverage improvement before actually
#' applying the derived categories.
#'
#' @examples
#' \dontrun{
#' impact <- calculate_coverage_impact(
#'   con = con,
#'   input_file = "data/taxonomy/plants_vernacular_final.parquet",
#'   derived_file = "data/taxonomy/plant_genus_vernaculars_derived.parquet",
#'   group_col = "genus"
#' )
#'
#' # Potential coverage impact:
#' # Currently uncategorized: 1,438
#' # Would be covered: 123 (8.6%)
#' }
#'
#' @export
calculate_coverage_impact <- function(con,
                                      input_file,
                                      derived_file,
                                      group_col,
                                      verbose = TRUE) {

  # Count total uncategorized
  uncategorized <- dbGetQuery(con, sprintf("
    SELECT COUNT(*) as n
    FROM read_parquet('%s')
    WHERE vernacular_source = 'uncategorized'
  ", input_file))$n

  # Count how many would be covered by derived categories
  would_be_covered <- dbGetQuery(con, sprintf("
    SELECT COUNT(*) as n
    FROM read_parquet('%s') p
    WHERE p.vernacular_source = 'uncategorized'
      AND p.%s IN (SELECT %s FROM read_parquet('%s'))
  ", input_file, group_col, group_col, derived_file))$n

  # Calculate impact metrics
  improvement_pct <- if (uncategorized > 0) {
    100 * would_be_covered / uncategorized
  } else {
    0
  }

  # Print results if verbose
  if (verbose) {
    cat("\n=== Potential Coverage Impact ===\n")
    cat(sprintf("Currently uncategorized: %s\n",
                format(uncategorized, big.mark = ",")))
    cat(sprintf("Would be covered by derived %ss: %s (%.1f%%)\n",
                group_col,
                format(would_be_covered, big.mark = ","),
                improvement_pct))
  }

  # Return metrics
  list(
    total_uncategorized = uncategorized,
    would_be_covered = would_be_covered,
    coverage_improvement_pct = improvement_pct,
    coverage_improvement_abs = would_be_covered
  )
}
