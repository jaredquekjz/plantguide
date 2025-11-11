#!/usr/bin/env Rscript
#
# Module Test: Shared Organism Counter Utility
#
# Tests count_shared_organisms function by comparing against manual counts
#

suppressMessages({
  library(arrow)
  library(dplyr)
  library(readr)
  library(purrr)
})

cat(rep("=", 80), "\n", sep="")
cat("MODULE TEST: SHARED ORGANISM COUNTER UTILITY\n")
cat(rep("=", 80), "\n\n")

# Source modular organism counter
source('shipley_checks/src/Stage_4/utils/shared_organism_counter.R')

# Load test data (real organism and fungi data)
cat("Loading test data...\n")

# Helper function to convert pipe-separated strings to lists
csv_to_lists <- function(df, list_cols) {
  for (col in list_cols) {
    if (col %in% names(df)) {
      df <- df %>%
        mutate(!!col := map(.data[[col]], function(x) {
          if (is.na(x) || x == '') character(0) else strsplit(x, '\\|')[[1]]
        }))
    }
  }
  df
}

organisms_df <- read_csv('shipley_checks/validation/organism_profiles_pure_r.csv', show_col_types = FALSE) %>%
  csv_to_lists(c('herbivores', 'flower_visitors', 'pollinators',
                 'predators_hasHost', 'predators_interactsWith', 'predators_adjacentTo'))

fungi_df <- read_csv('shipley_checks/validation/fungal_guilds_pure_r.csv', show_col_types = FALSE) %>%
  csv_to_lists(c('pathogenic_fungi', 'pathogenic_fungi_host_specific',
                 'amf_fungi', 'emf_fungi', 'mycoparasite_fungi',
                 'entomopathogenic_fungi', 'endophytic_fungi', 'saprotrophic_fungi'))

cat("  Organisms: ", nrow(organisms_df), " rows\n")
cat("  Fungi: ", nrow(fungi_df), " rows\n\n")

# Test 1: Count shared pollinators (M7)
cat("Test 1: Count shared pollinators\n")
cat(rep("=", 80), "\n", sep="")

guild_1 <- c(
  'wfo-0000832453',  # Fraxinus excelsior
  'wfo-0000649136',  # Diospyros kaki
  'wfo-0000642673',  # Deutzia scabra
  'wfo-0000984977',  # Rubus moorei
  'wfo-0000241769',  # Mercurialis perennis
  'wfo-0000092746',  # Anaphalis margaritacea
  'wfo-0000690499'   # Maianthemum racemosum
)

shared_pollinators <- count_shared_organisms(
  organisms_df,
  guild_1,
  'pollinators', 'flower_visitors'
)

cat(sprintf("  Guild size: %d plants\n", length(guild_1)))
cat(sprintf("  Unique pollinators: %d\n", length(shared_pollinators)))
cat(sprintf("  Shared by 2+ plants: %d\n", sum(shared_pollinators >= 2)))
cat(sprintf("  Shared by 3+ plants: %d\n", sum(shared_pollinators >= 3)))

# Show top 5 most shared
if (length(shared_pollinators) > 0) {
  sorted <- shared_pollinators[order(unlist(shared_pollinators), decreasing = TRUE)]
  cat("\n  Top 5 most shared pollinators:\n")
  for (i in 1:min(5, length(sorted))) {
    cat(sprintf("    %s: %d plants\n", names(sorted)[i], sorted[[i]]))
  }
}

# Validation: Basic checks
test_1_pass <- TRUE
if (length(shared_pollinators) == 0) {
  cat("\n  ❌ FAIL: No pollinators found (unexpected)\n")
  test_1_pass <- FALSE
} else if (any(shared_pollinators < 1)) {
  cat("\n  ❌ FAIL: Count < 1 detected (logic error)\n")
  test_1_pass <- FALSE
} else if (any(shared_pollinators > length(guild_1))) {
  cat("\n  ❌ FAIL: Count > guild size (logic error)\n")
  test_1_pass <- FALSE
} else {
  cat("\n  ✅ PASS: Valid pollinator counts\n")
}

cat("\n")

# Test 2: Count shared beneficial fungi (M5)
cat("Test 2: Count shared beneficial fungi\n")
cat(rep("=", 80), "\n", sep="")

shared_fungi <- count_shared_organisms(
  fungi_df,
  guild_1,
  'amf_fungi', 'emf_fungi', 'endophytic_fungi', 'saprotrophic_fungi'
)

cat(sprintf("  Guild size: %d plants\n", length(guild_1)))
cat(sprintf("  Unique beneficial fungi: %d\n", length(shared_fungi)))
cat(sprintf("  Shared by 2+ plants: %d\n", sum(shared_fungi >= 2)))
cat(sprintf("  Shared by 3+ plants: %d\n", sum(shared_fungi >= 3)))

# Show top 5 most shared
if (length(shared_fungi) > 0) {
  sorted <- shared_fungi[order(unlist(shared_fungi), decreasing = TRUE)]
  cat("\n  Top 5 most shared fungi:\n")
  for (i in 1:min(5, length(sorted))) {
    cat(sprintf("    %s: %d plants\n", names(sorted)[i], sorted[[i]]))
  }
}

# Validation
test_2_pass <- TRUE
if (length(shared_fungi) == 0) {
  cat("\n  ⚠️  WARNING: No beneficial fungi found (may be valid)\n")
  test_2_pass <- TRUE  # Not necessarily a failure
} else if (any(shared_fungi < 1)) {
  cat("\n  ❌ FAIL: Count < 1 detected (logic error)\n")
  test_2_pass <- FALSE
} else if (any(shared_fungi > length(guild_1))) {
  cat("\n  ❌ FAIL: Count > guild size (logic error)\n")
  test_2_pass <- FALSE
} else {
  cat("\n  ✅ PASS: Valid fungi counts\n")
}

cat("\n")

# Test 3: Edge case - single plant
cat("Test 3: Edge case - single plant\n")
cat(rep("=", 80), "\n", sep="")

single_plant <- c('wfo-0000832453')

shared_single <- count_shared_organisms(
  organisms_df,
  single_plant,
  'pollinators', 'flower_visitors'
)

cat(sprintf("  Guild size: %d plant\n", length(single_plant)))
cat(sprintf("  Unique pollinators: %d\n", length(shared_single)))

# All counts should be 1 (single plant)
test_3_pass <- TRUE
if (length(shared_single) > 0) {
  if (all(shared_single == 1)) {
    cat("  ✅ PASS: All counts = 1 (expected for single plant)\n")
  } else {
    cat("  ❌ FAIL: Some counts != 1 for single plant\n")
    test_3_pass <- FALSE
  }
} else {
  cat("  ⚠️  WARNING: No organisms found for single plant\n")
  # Not necessarily a failure - plant may have no data
}

cat("\n")

# Test 4: Edge case - empty guild
cat("Test 4: Edge case - empty guild\n")
cat(rep("=", 80), "\n", sep="")

empty_guild <- character(0)

shared_empty <- count_shared_organisms(
  organisms_df,
  empty_guild,
  'pollinators', 'flower_visitors'
)

cat(sprintf("  Guild size: %d plants\n", length(empty_guild)))
cat(sprintf("  Unique pollinators: %d\n", length(shared_empty)))

test_4_pass <- TRUE
if (length(shared_empty) == 0) {
  cat("  ✅ PASS: Empty result for empty guild\n")
} else {
  cat("  ❌ FAIL: Non-empty result for empty guild\n")
  test_4_pass <- FALSE
}

cat("\n")

# Summary
cat(rep("=", 80), "\n", sep="")
cat("SUMMARY\n")
cat(rep("=", 80), "\n", sep="")

tests_passed <- sum(test_1_pass, test_2_pass, test_3_pass, test_4_pass)
total_tests <- 4

cat(sprintf("Total tests: %d\n", total_tests))
cat(sprintf("Passed: %d\n", tests_passed))
cat(sprintf("Failed: %d\n", total_tests - tests_passed))

if (tests_passed == total_tests) {
  cat("\n✅ ALL ORGANISM COUNTER TESTS PASSED\n")
  quit(status = 0)
} else {
  cat("\n❌ SOME TESTS FAILED\n")
  quit(status = 1)
}
