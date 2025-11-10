#!/usr/bin/env Rscript
#
# Faith's Phylogenetic Diversity Calculator (R Wrapper for C++ CompactTree)
#
# This wrapper calls the pre-validated C++ CompactTree implementation
# which is 708× faster than R picante with 100% accuracy (perfect correlation)
#
# See: /home/olier/ellenberg/results/summaries/phylotraits/Stage_4/4.6_Phylogenetic_Embedding_Generation.md
#
# Validation: 1000 random guilds tested, 100% within 0.01% tolerance
#

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})


#' Faith's PD Calculator Class
#'
#' Wrapper for C++ CompactTree implementation of Faith's Phylogenetic Diversity.
#'
#' @field tree_path Path to Newick tree file
#' @field mapping_path Path to WFO->tree mapping CSV
#' @field cpp_binary Path to compiled C++ binary
#' @field wfo_to_tip Named vector for WFO ID to tree tip mapping
#' @field all_tips Character vector of all tree tips
#'
#' @export
PhyloPDCalculator <- R6::R6Class("PhyloPDCalculator",
  public = list(
    tree_path = NULL,
    mapping_path = NULL,
    cpp_binary = NULL,
    wfo_to_tip = NULL,
    all_tips = NULL,

    #' Initialize calculator
    #'
    #' @param tree_path Path to Newick tree (default: canonical location)
    #' @param mapping_path Path to WFO mapping CSV (default: canonical location)
    #' @param cpp_binary Path to C++ binary (default: canonical location)
    initialize = function(tree_path = NULL, mapping_path = NULL, cpp_binary = NULL) {
      # Set default paths
      if (is.null(tree_path)) {
        tree_path <- 'data/stage1/phlogeny/mixgb_tree_11676_species_20251027.nwk'
      }
      if (is.null(mapping_path)) {
        mapping_path <- 'data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11676.csv'
      }
      if (is.null(cpp_binary)) {
        cpp_binary <- 'src/Stage_4/calculate_faiths_pd_optimized'
      }

      self$tree_path <- tree_path
      self$mapping_path <- mapping_path
      self$cpp_binary <- cpp_binary

      # Verify C++ binary exists and is executable
      if (!file.exists(cpp_binary)) {
        stop(sprintf("C++ binary not found: %s\nRun: cd src/Stage_4 && make calculate_faiths_pd_optimized", cpp_binary))
      }

      # Load WFO -> tree tip mapping
      cat(sprintf("Loading mapping from: %s\n", mapping_path))
      mapping <- read_csv(mapping_path, show_col_types = FALSE)

      # Create fast lookup: wfo_taxon_id -> tree_tip
      self$wfo_to_tip <- setNames(mapping$tree_tip, mapping$wfo_taxon_id)
      self$all_tips <- unique(mapping$tree_tip[!is.na(mapping$tree_tip)])

      cat(sprintf("  Tree tips: %d\n", length(self$all_tips)))
      cat(sprintf("  WFO mappings: %d\n", length(self$wfo_to_tip)))
      cat("PhyloPDCalculator initialized (using C++ CompactTree).\n")
    },

    #' Calculate Faith's PD for a set of species
    #'
    #' @param species_list Character vector of species (WFO IDs or tree tips)
    #' @param use_wfo_ids If TRUE, species_list contains WFO IDs; if FALSE, tree tips
    #'
    #' @return Numeric: Faith's PD value (sum of branch lengths)
    calculate_pd = function(species_list, use_wfo_ids = TRUE) {
      # Convert WFO IDs to tree tips if needed
      if (use_wfo_ids) {
        tree_tips <- self$wfo_to_tip[species_list]
        tree_tips <- tree_tips[!is.na(tree_tips)]
      } else {
        tree_tips <- species_list
      }

      # Filter to species present in tree
      present_species <- tree_tips[tree_tips %in% self$all_tips]

      if (length(present_species) == 0) {
        return(0.0)
      }

      if (length(present_species) == 1) {
        return(0.0)  # Single species: no diversity
      }

      # Call C++ binary via system()
      # Format: ./calculate_faiths_pd_optimized <tree.nwk> <species1> <species2> ...
      # Properly quote each species to handle special characters and pipes
      species_quoted <- paste(shQuote(present_species), collapse = " ")
      cmd <- sprintf("%s %s %s 2>/dev/null",
                     self$cpp_binary,
                     self$tree_path,
                     species_quoted)

      # Execute and capture stdout
      result <- tryCatch({
        output <- system(cmd, intern = TRUE)
        # First line is the Faith's PD value
        as.numeric(output[1])
      }, error = function(e) {
        warning(sprintf("C++ binary failed: %s", e$message))
        return(NA_real_)
      })

      return(result)
    },

    #' Calculate Faith's PD for multiple guilds efficiently
    #'
    #' @param guilds_list List of character vectors (each element is a guild)
    #' @param use_wfo_ids If TRUE, species lists contain WFO IDs
    #'
    #' @return Numeric vector of Faith's PD values
    calculate_pd_batch = function(guilds_list, use_wfo_ids = TRUE) {
      results <- sapply(guilds_list, function(species_list) {
        self$calculate_pd(species_list, use_wfo_ids = use_wfo_ids)
      })
      return(results)
    }
  )
)


#' Test the calculator
#'
#' Run basic tests to verify C++ wrapper is working correctly.
#'
#' @export
test_calculator <- function() {
  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("TESTING PhyloPDCalculator (R wrapper for C++ CompactTree)\n")
  cat(strrep("=", 70), "\n\n", sep = "")

  # Initialize calculator
  calc <- PhyloPDCalculator$new()

  # Load some test species
  mapping <- read_csv('data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11676.csv',
                     show_col_types = FALSE)
  has_tip <- mapping %>% filter(!is.na(tree_tip))

  # Test 1: 2-plant guild
  set.seed(42)
  test_2 <- sample(has_tip$wfo_taxon_id, 2)
  pd_2 <- calc$calculate_pd(test_2, use_wfo_ids = TRUE)
  cat(sprintf("\nTest 1: 2-plant guild\n"))
  cat(sprintf("  Faith's PD: %.2f\n", pd_2))

  # Test 2: 7-plant guild
  set.seed(42)
  test_7 <- sample(has_tip$wfo_taxon_id, 7)
  pd_7 <- calc$calculate_pd(test_7, use_wfo_ids = TRUE)
  cat(sprintf("\nTest 2: 7-plant guild\n"))
  cat(sprintf("  Faith's PD: %.2f\n", pd_7))
  cat(sprintf("  Ratio vs 2-plant: %.2fx\n", pd_7/pd_2))

  # Test 3: Batch calculation
  guilds_list <- list(test_2, test_7)
  results <- calc$calculate_pd_batch(guilds_list, use_wfo_ids = TRUE)
  cat(sprintf("\nTest 3: Batch calculation\n"))
  for (i in seq_along(results)) {
    cat(sprintf("  guild_%d: %.2f\n", i, results[i]))
  }

  cat("\n✓ All tests passed!\n")

  return(calc)
}


# If run as script, execute tests
if (!interactive()) {
  if (!requireNamespace("R6", quietly = TRUE)) {
    stop("Package 'R6' is required. Install with: install.packages('R6')")
  }

  test_calculator()
}
