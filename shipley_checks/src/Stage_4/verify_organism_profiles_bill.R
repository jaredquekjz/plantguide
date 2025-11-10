#!/usr/bin/env Rscript
# Stage 4 Verification: Plant Organism Profiles
#
# Verifies structure, coverage, and data quality of organism profiles
# extracted from GloBI interactions database.
#
# Expected output: shipley_checks/stage4/plant_organism_profiles_11711.parquet
#
# Usage: Rscript shipley_checks/src/Stage_4/verify_organism_profiles_bill.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

cat("================================================================================\n")
cat("STAGE 4 VERIFICATION: Plant Organism Profiles\n")
cat("================================================================================\n")
cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# File paths
PROFILES_FILE <- "shipley_checks/stage4/plant_organism_profiles_11711.parquet"
MAIN_DATASET <- "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet"
REPORT_FILE <- "shipley_checks/reports/verify_organism_profiles_bill.txt"

# Ensure report directory exists
dir.create("shipley_checks/reports", showWarnings = FALSE, recursive = TRUE)

# Redirect output to both console and file
sink(REPORT_FILE, split = TRUE)

cat("================================================================================\n")
cat("STAGE 4 VERIFICATION: Plant Organism Profiles\n")
cat("================================================================================\n")
cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Initialize results
all_checks_pass <- TRUE
failed_checks <- c()

# Test 1: File exists
cat("Test 1: File Existence\n")
cat("  Checking:", PROFILES_FILE, "\n")
if (!file.exists(PROFILES_FILE)) {
  cat("  ❌ FAIL: File does not exist\n\n")
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "File existence")
  sink()
  quit(status = 1)
} else {
  file_size <- file.size(PROFILES_FILE) / 1024 / 1024
  cat(sprintf("  ✓ PASS: File exists (%.2f MB)\n\n", file_size))
}

# Load data
cat("Loading organism profiles...\n")
profiles <- read_parquet(PROFILES_FILE)
cat(sprintf("  - Loaded %s rows\n\n", format(nrow(profiles), big.mark = ",")))

# Test 2: Row count
cat("Test 2: Row Count\n")
cat("  Expected: 11,711 plants\n")
cat(sprintf("  Actual: %s plants\n", format(nrow(profiles), big.mark = ",")))
if (nrow(profiles) != 11711) {
  cat(sprintf("  ❌ FAIL: Expected 11,711 rows, got %d\n\n", nrow(profiles)))
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "Row count")
} else {
  cat("  ✓ PASS\n\n")
}

# Test 3: Column structure
cat("Test 3: Column Structure\n")
expected_cols <- c(
  "plant_wfo_id", "wfo_taxon_id", "wfo_scientific_name",
  "pollinators", "pollinator_count",
  "herbivores", "herbivore_count",
  "pathogens", "pathogen_count",
  "flower_visitors", "visitor_count",
  "predators_hasHost", "predators_hasHost_count",
  "predators_interactsWith", "predators_interactsWith_count",
  "predators_adjacentTo", "predators_adjacentTo_count"
)

actual_cols <- colnames(profiles)
missing_cols <- setdiff(expected_cols, actual_cols)
extra_cols <- setdiff(actual_cols, expected_cols)

if (length(missing_cols) > 0) {
  cat("  ❌ FAIL: Missing columns:", paste(missing_cols, collapse = ", "), "\n")
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "Missing columns")
} else {
  cat("  ✓ PASS: All expected columns present\n")
}

if (length(extra_cols) > 0) {
  cat("  ⚠️  WARNING: Extra columns found:", paste(extra_cols, collapse = ", "), "\n")
}
cat("\n")

# Test 4: Count columns match list lengths
cat("Test 4: Count Columns Match List Lengths\n")

check_list_count <- function(df, list_col, count_col) {
  mismatches <- df %>%
    mutate(
      list_len = sapply(.data[[list_col]], length),
      matches = (.data[[count_col]] == list_len)
    ) %>%
    filter(!matches) %>%
    nrow()

  return(mismatches)
}

list_count_checks <- list(
  pollinators = check_list_count(profiles, "pollinators", "pollinator_count"),
  herbivores = check_list_count(profiles, "herbivores", "herbivore_count"),
  pathogens = check_list_count(profiles, "pathogens", "pathogen_count"),
  flower_visitors = check_list_count(profiles, "flower_visitors", "visitor_count"),
  predators_hasHost = check_list_count(profiles, "predators_hasHost", "predators_hasHost_count"),
  predators_interactsWith = check_list_count(profiles, "predators_interactsWith", "predators_interactsWith_count"),
  predators_adjacentTo = check_list_count(profiles, "predators_adjacentTo", "predators_adjacentTo_count")
)

all_match <- TRUE
for (field in names(list_count_checks)) {
  mismatches <- list_count_checks[[field]]
  if (mismatches > 0) {
    cat(sprintf("  ❌ FAIL: %s has %d mismatches\n", field, mismatches))
    all_checks_pass <- FALSE
    all_match <- FALSE
  }
}

if (all_match) {
  cat("  ✓ PASS: All count columns match their list lengths\n")
} else {
  failed_checks <- c(failed_checks, "List/count mismatches")
}
cat("\n")

# Test 5: No NA in count columns
cat("Test 5: No NA Values in Count Columns\n")
count_cols <- c("pollinator_count", "herbivore_count", "pathogen_count", "visitor_count",
                "predators_hasHost_count", "predators_interactsWith_count", "predators_adjacentTo_count")

na_counts <- sapply(count_cols, function(col) sum(is.na(profiles[[col]])))
if (any(na_counts > 0)) {
  cat("  ❌ FAIL: NA values found in count columns:\n")
  for (col in names(na_counts[na_counts > 0])) {
    cat(sprintf("    - %s: %d NAs\n", col, na_counts[col]))
  }
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "NA in count columns")
} else {
  cat("  ✓ PASS: No NA values in count columns\n")
}
cat("\n")

# Test 6: Coverage statistics
cat("Test 6: Coverage Statistics\n")
stats <- profiles %>%
  summarize(
    total = n(),
    with_pollinators = sum(pollinator_count > 0),
    with_herbivores = sum(herbivore_count > 0),
    with_pathogens = sum(pathogen_count > 0),
    with_visitors = sum(visitor_count > 0),
    pct_pollinators = 100 * with_pollinators / total,
    pct_herbivores = 100 * with_herbivores / total,
    pct_pathogens = 100 * with_pathogens / total,
    pct_visitors = 100 * with_visitors / total
  )

cat(sprintf("  Plants with pollinators: %s (%.1f%%)\n",
            format(stats$with_pollinators, big.mark = ","), stats$pct_pollinators))
cat(sprintf("  Plants with herbivores: %s (%.1f%%)\n",
            format(stats$with_herbivores, big.mark = ","), stats$pct_herbivores))
cat(sprintf("  Plants with pathogens: %s (%.1f%%)\n",
            format(stats$with_pathogens, big.mark = ","), stats$pct_pathogens))
cat(sprintf("  Plants with flower visitors: %s (%.1f%%)\n",
            format(stats$with_visitors, big.mark = ","), stats$pct_visitors))

# Expected ranges (from Python output, allowing ±2%)
expected_ranges <- list(
  pollinators = c(11.4, 15.4),
  herbivores = c(25.6, 29.6),
  pathogens = c(61.1, 65.1),
  visitors = c(24.2, 28.2)
)

coverage_ok <- TRUE
if (stats$pct_pollinators < expected_ranges$pollinators[1] ||
    stats$pct_pollinators > expected_ranges$pollinators[2]) {
  cat(sprintf("  ⚠️  WARNING: Pollinator coverage (%.1f%%) outside expected range (%.1f%%-%.1f%%)\n",
              stats$pct_pollinators, expected_ranges$pollinators[1], expected_ranges$pollinators[2]))
  coverage_ok <- FALSE
}

if (stats$pct_herbivores < expected_ranges$herbivores[1] ||
    stats$pct_herbivores > expected_ranges$herbivores[2]) {
  cat(sprintf("  ⚠️  WARNING: Herbivore coverage (%.1f%%) outside expected range (%.1f%%-%.1f%%)\n",
              stats$pct_herbivores, expected_ranges$herbivores[1], expected_ranges$herbivores[2]))
  coverage_ok <- FALSE
}

if (stats$pct_pathogens < expected_ranges$pathogens[1] ||
    stats$pct_pathogens > expected_ranges$pathogens[2]) {
  cat(sprintf("  ⚠️  WARNING: Pathogen coverage (%.1f%%) outside expected range (%.1f%%-%.1f%%)\n",
              stats$pct_pathogens, expected_ranges$pathogens[1], expected_ranges$pathogens[2]))
  coverage_ok <- FALSE
}

if (coverage_ok) {
  cat("  ✓ PASS: Coverage statistics within expected ranges\n")
} else {
  cat("  ⚠️  Some coverage values outside expected ranges (not critical)\n")
}
cat("\n")

# Test 7: Data quality - no generic names
cat("Test 7: Data Quality - No Generic Names\n")
generic_names <- c("no name", "Fungi", "Bacteria", "Insecta", "Plantae", "Animalia", "Viruses")

check_generic_names <- function(df, col_name) {
  all_values <- unlist(df[[col_name]])
  if (length(all_values) == 0) return(0)
  sum(all_values %in% generic_names)
}

generic_counts <- list(
  pollinators = check_generic_names(profiles, "pollinators"),
  herbivores = check_generic_names(profiles, "herbivores"),
  pathogens = check_generic_names(profiles, "pathogens"),
  flower_visitors = check_generic_names(profiles, "flower_visitors")
)

all_clean <- TRUE
for (field in names(generic_counts)) {
  if (generic_counts[[field]] > 0) {
    cat(sprintf("  ❌ FAIL: %s contains %d generic names\n", field, generic_counts[[field]]))
    all_checks_pass <- FALSE
    all_clean <- FALSE
  }
}

if (all_clean) {
  cat("  ✓ PASS: No generic names found in organism lists\n")
} else {
  failed_checks <- c(failed_checks, "Generic names present")
}
cat("\n")

# Test 8: Cross-reference with main dataset
cat("Test 8: Cross-Reference with Main Dataset\n")
cat("  Loading main dataset...\n")
main_dataset <- read_parquet(MAIN_DATASET)
cat(sprintf("  - Main dataset has %s plants\n", format(nrow(main_dataset), big.mark = ",")))

# Check all profile plant IDs exist in main dataset
profile_ids <- unique(profiles$plant_wfo_id)
main_ids <- unique(main_dataset$wfo_taxon_id)

missing_in_main <- setdiff(profile_ids, main_ids)
if (length(missing_in_main) > 0) {
  cat(sprintf("  ❌ FAIL: %d plant IDs in profiles not found in main dataset\n", length(missing_in_main)))
  cat("  First 5 missing:", paste(head(missing_in_main, 5), collapse = ", "), "\n")
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "Plant IDs not in main dataset")
} else {
  cat("  ✓ PASS: All plant IDs exist in main dataset\n")
}

# Check coverage
coverage <- length(profile_ids) / length(main_ids) * 100
cat(sprintf("  Coverage: %s / %s plants (%.1f%%)\n",
            format(length(profile_ids), big.mark = ","),
            format(length(main_ids), big.mark = ","),
            coverage))

if (coverage < 99.9) {
  cat(sprintf("  ⚠️  WARNING: Coverage is %.1f%%, expected ~100%%\n", coverage))
}
cat("\n")

# Test 9: Sample data inspection
cat("Test 9: Sample Data Inspection\n")
cat("  Top 5 plants by total interactions:\n")
sample_plants <- profiles %>%
  mutate(total_interactions = pollinator_count + herbivore_count + pathogen_count + visitor_count) %>%
  arrange(desc(total_interactions)) %>%
  head(5) %>%
  select(wfo_scientific_name, pollinator_count, herbivore_count, pathogen_count, visitor_count, total_interactions)

print(sample_plants, row.names = FALSE)
cat("\n")

# Test 10: Herbivores exclude pollinators
cat("Test 10: Herbivores Exclude Pollinators (Spot Check)\n")
cat("  Checking first 100 plants for pollinator/herbivore overlap...\n")
overlap_counts <- profiles %>%
  head(100) %>%
  rowwise() %>%
  mutate(
    overlap = length(intersect(pollinators, herbivores))
  ) %>%
  ungroup() %>%
  summarize(total_overlap = sum(overlap))

if (overlap_counts$total_overlap > 0) {
  cat(sprintf("  ⚠️  WARNING: Found %d pollinator-herbivore overlaps in first 100 plants\n",
              overlap_counts$total_overlap))
  cat("  (Some overlap may be expected due to data quality in GloBI)\n")
} else {
  cat("  ✓ PASS: No pollinator-herbivore overlap detected in sample\n")
}
cat("\n")

# Final summary
cat("================================================================================\n")
cat("VERIFICATION SUMMARY\n")
cat("================================================================================\n\n")

if (all_checks_pass) {
  cat("✓ ALL TESTS PASSED\n\n")
  cat("Summary:\n")
  cat(sprintf("  - Total plants: %s\n", format(nrow(profiles), big.mark = ",")))
  cat(sprintf("  - With pollinators: %s (%.1f%%)\n",
              format(stats$with_pollinators, big.mark = ","), stats$pct_pollinators))
  cat(sprintf("  - With herbivores: %s (%.1f%%)\n",
              format(stats$with_herbivores, big.mark = ","), stats$pct_herbivores))
  cat(sprintf("  - With pathogens: %s (%.1f%%)\n",
              format(stats$with_pathogens, big.mark = ","), stats$pct_pathogens))
  cat(sprintf("  - With flower visitors: %s (%.1f%%)\n",
              format(stats$with_visitors, big.mark = ","), stats$pct_visitors))
  cat("\n✓ Dataset is ready for guild calibration\n\n")
} else {
  cat("❌ SOME TESTS FAILED\n\n")
  cat("Failed checks:\n")
  for (check in failed_checks) {
    cat(sprintf("  - %s\n", check))
  }
  cat("\n⚠️  Please review failures before proceeding\n\n")
}

cat("================================================================================\n")
cat("Completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Report saved to:", REPORT_FILE, "\n")
cat("================================================================================\n")

sink()

# Exit with appropriate status code
if (all_checks_pass) {
  quit(status = 0)
} else {
  quit(status = 1)
}
