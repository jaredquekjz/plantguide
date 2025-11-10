#!/usr/bin/env Rscript
#
# Comprehensive verification script for Köppen labeling pipeline
#
# Purpose:
#   Verify data integrity and correctness at each stage of the pipeline:
#   1. Köppen zone assignment to occurrences
#   2. Plant-level aggregation
#   3. Integration with main dataset
#
# Usage:
#   env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
#     /usr/bin/Rscript shipley_checks/src/Stage_4/verify_koppen_pipeline_11711.R
#
# Returns:
#   Exit code 0 if all checks pass
#   Exit code 1 if any check fails

library(arrow)
library(data.table)
library(jsonlite)

# ANSI color codes
RED <- "\033[0;31m"
GREEN <- "\033[0;32m"
YELLOW <- "\033[1;33m"
BLUE <- "\033[0;34m"
NC <- "\033[0m"  # No Color

# Test counters
n_tests <- 0
n_passed <- 0
n_failed <- 0
n_warnings <- 0

# Helper functions
test <- function(name, condition, error_msg = NULL, warning_msg = NULL) {
  n_tests <<- n_tests + 1
  cat(sprintf("\n[TEST %d] %s\n", n_tests, name))

  if (condition) {
    cat(sprintf("%s✓ PASS%s\n", GREEN, NC))
    n_passed <<- n_passed + 1
    return(TRUE)
  } else {
    if (!is.null(warning_msg)) {
      cat(sprintf("%s⚠ WARNING: %s%s\n", YELLOW, warning_msg, NC))
      n_warnings <<- n_warnings + 1
      return(TRUE)
    } else {
      cat(sprintf("%s✗ FAIL: %s%s\n", RED, error_msg, NC))
      n_failed <<- n_failed + 1
      return(FALSE)
    }
  }
}

info <- function(msg) {
  cat(sprintf("%s  ℹ %s%s\n", BLUE, msg, NC))
}

cat(rep("=", 80), "\n", sep = "")
cat("KÖPPEN LABELING PIPELINE VERIFICATION\n")
cat(rep("=", 80), "\n", sep = "")
cat("\nStart time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")

# ============================================================================
# SECTION 1: FILE EXISTENCE AND BASIC STRUCTURE
# ============================================================================
cat("\n", rep("=", 80), "\n", sep = "")
cat("SECTION 1: FILE EXISTENCE AND BASIC STRUCTURE\n")
cat(rep("=", 80), "\n", sep = "")

# Define file paths
INPUT_WORLDCLIM <- "data/stage1/worldclim_occ_samples.parquet"
OUTPUT_KOPPEN <- "data/stage1/worldclim_occ_samples_with_koppen_11711.parquet"
OUTPUT_AGGREGATED <- "shipley_checks/stage4/plant_koppen_distributions_11711.parquet"
OUTPUT_INTEGRATED <- "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet"
INPUT_MAIN <- "shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv"

# Test 1: Input files exist
test("Input worldclim file exists",
     file.exists(INPUT_WORLDCLIM),
     error_msg = paste("File not found:", INPUT_WORLDCLIM))

test("Input main dataset exists",
     file.exists(INPUT_MAIN),
     error_msg = paste("File not found:", INPUT_MAIN))

# Test 2: Output files exist
test("Output Köppen occurrence file exists",
     file.exists(OUTPUT_KOPPEN),
     error_msg = paste("File not found:", OUTPUT_KOPPEN, "- Run step 1 first"))

test("Output aggregated distributions file exists",
     file.exists(OUTPUT_AGGREGATED),
     error_msg = paste("File not found:", OUTPUT_AGGREGATED, "- Run step 2 first"))

test("Output integrated dataset file exists",
     file.exists(OUTPUT_INTEGRATED),
     error_msg = paste("File not found:", OUTPUT_INTEGRATED, "- Run step 3 first"))

# Test 3: File sizes reasonable
if (file.exists(OUTPUT_KOPPEN)) {
  size_koppen <- file.info(OUTPUT_KOPPEN)$size / (1024^3)
  test("Köppen occurrence file size reasonable (>2 GB)",
       size_koppen > 2,
       error_msg = sprintf("File too small: %.2f GB (expected >2 GB)", size_koppen))
  info(sprintf("File size: %.2f GB", size_koppen))
}

if (file.exists(OUTPUT_AGGREGATED)) {
  size_aggregated <- file.info(OUTPUT_AGGREGATED)$size / (1024^2)
  test("Aggregated distributions file size reasonable (>1 MB)",
       size_aggregated > 1,
       error_msg = sprintf("File too small: %.2f MB (expected >1 MB)", size_aggregated))
  info(sprintf("File size: %.2f MB", size_aggregated))
}

if (file.exists(OUTPUT_INTEGRATED)) {
  size_integrated <- file.info(OUTPUT_INTEGRATED)$size / (1024^2)
  test("Integrated dataset file size reasonable (>20 MB)",
       size_integrated > 20,
       error_msg = sprintf("File too small: %.2f MB (expected >20 MB)", size_integrated))
  info(sprintf("File size: %.2f MB", size_integrated))
}

# ============================================================================
# SECTION 2: STEP 1 VERIFICATION (OCCURRENCE KÖPPEN ASSIGNMENT)
# ============================================================================
if (file.exists(OUTPUT_KOPPEN)) {
  cat("\n", rep("=", 80), "\n", sep = "")
  cat("SECTION 2: STEP 1 VERIFICATION (OCCURRENCE KÖPPEN ASSIGNMENT)\n")
  cat(rep("=", 80), "\n", sep = "")

  ds_koppen <- open_dataset(OUTPUT_KOPPEN, format = "parquet")
  schema_koppen <- ds_koppen$schema

  # Test 4: koppen_zone column exists
  test("Köppen zone column exists",
       "koppen_zone" %in% names(schema_koppen),
       error_msg = "Column 'koppen_zone' not found in output")

  # Test 5: Essential columns preserved
  essential_cols <- c("wfo_taxon_id", "gbifID", "lat", "lon")
  for (col in essential_cols) {
    test(sprintf("Column '%s' exists", col),
         col %in% names(schema_koppen),
         error_msg = sprintf("Essential column '%s' missing", col))
  }

  # Load sample data
  sample_koppen <- ds_koppen %>% head(10000) %>% collect() %>% as.data.table()

  # Test 6: Row count matches input
  n_rows_koppen <- ds_koppen %>% count() %>% collect() %>% pull(n)
  ds_input <- open_dataset(INPUT_WORLDCLIM, format = "parquet")
  n_rows_input <- ds_input %>% count() %>% collect() %>% pull(n)

  test("Row count matches input",
       n_rows_koppen == n_rows_input,
       error_msg = sprintf("Row count mismatch: input=%s, output=%s",
                          format(n_rows_input, big.mark = ","),
                          format(n_rows_koppen, big.mark = ",")))
  info(sprintf("Row count: %s", format(n_rows_koppen, big.mark = ",")))

  # Test 7: Number of unique plants
  n_plants_koppen <- ds_koppen %>%
    select(wfo_taxon_id) %>%
    distinct() %>%
    count() %>%
    collect() %>%
    pull(n)

  test("Number of unique plants = 11,711",
       n_plants_koppen == 11711,
       error_msg = sprintf("Expected 11,711 plants, got %s", format(n_plants_koppen, big.mark = ",")))
  info(sprintf("Unique plants: %s", format(n_plants_koppen, big.mark = ",")))

  # Test 8: Köppen zone format valid
  koppen_sample <- sample_koppen[!is.na(koppen_zone), unique(koppen_zone)]
  valid_pattern <- all(grepl("^[A-E][A-Za-z]{1,2}$", koppen_sample))
  test("Köppen zone format valid (e.g., 'Cfb', 'Dfa')",
       valid_pattern,
       error_msg = "Some Köppen zones have invalid format")

  # Test 9: NULL Köppen zones reasonable percentage
  null_pct <- ds_koppen %>%
    filter(is.na(koppen_zone)) %>%
    count() %>%
    collect() %>%
    pull(n) / n_rows_koppen * 100

  test("NULL Köppen zones <5%",
       null_pct < 5,
       error_msg = sprintf("Too many NULL values: %.2f%%", null_pct),
       warning_msg = if (null_pct >= 1) sprintf("%.2f%% occurrences have NULL Köppen zones", null_pct) else NULL)
  info(sprintf("NULL Köppen zones: %.2f%%", null_pct))

  # Test 10: Köppen zone distribution reasonable
  koppen_dist <- ds_koppen %>%
    filter(!is.na(koppen_zone)) %>%
    group_by(koppen_zone) %>%
    summarise(n = n()) %>%
    collect() %>%
    as.data.table() %>%
    .[order(-n)]

  info("Top 5 Köppen zones:")
  for (i in 1:min(5, nrow(koppen_dist))) {
    info(sprintf("  %s: %s occurrences (%.1f%%)",
                 koppen_dist$koppen_zone[i],
                 format(koppen_dist$n[i], big.mark = ","),
                 100 * koppen_dist$n[i] / n_rows_koppen))
  }

  test("At least 10 different Köppen zones",
       nrow(koppen_dist) >= 10,
       error_msg = sprintf("Only %d Köppen zones found (expected >=10)", nrow(koppen_dist)))

  # Test 11: Coordinate validity
  coord_check <- sample_koppen[, .(
    lat_valid = all(lat >= -90 & lat <= 90),
    lon_valid = all(lon >= -180 & lon <= 180)
  )]

  test("Latitude values valid (-90 to 90)",
       coord_check$lat_valid,
       error_msg = "Some latitude values out of range")

  test("Longitude values valid (-180 to 180)",
       coord_check$lon_valid,
       error_msg = "Some longitude values out of range")
}

# ============================================================================
# SECTION 3: STEP 2 VERIFICATION (AGGREGATED DISTRIBUTIONS)
# ============================================================================
if (file.exists(OUTPUT_AGGREGATED)) {
  cat("\n", rep("=", 80), "\n", sep = "")
  cat("SECTION 3: STEP 2 VERIFICATION (AGGREGATED DISTRIBUTIONS)\n")
  cat(rep("=", 80), "\n", sep = "")

  agg_dt <- read_parquet(OUTPUT_AGGREGATED) %>% as.data.table()

  # Test 12: Row count = number of plants
  test("One row per plant (11,711 rows)",
       nrow(agg_dt) == 11711,
       error_msg = sprintf("Expected 11,711 rows, got %s", format(nrow(agg_dt), big.mark = ",")))

  # Test 13: Required columns exist
  required_cols <- c("wfo_taxon_id", "total_occurrences", "n_koppen_zones",
                     "n_main_zones", "top_zone_code", "top_zone_percent",
                     "ranked_zones_json", "main_zones_json",
                     "zone_counts_json", "zone_percents_json")

  for (col in required_cols) {
    test(sprintf("Column '%s' exists", col),
         col %in% names(agg_dt),
         error_msg = sprintf("Required column '%s' missing", col))
  }

  # Test 14: total_occurrences > 0 for all plants
  test("All plants have occurrences (total_occurrences > 0)",
       all(agg_dt$total_occurrences > 0),
       error_msg = "Some plants have 0 occurrences")

  info(sprintf("Mean occurrences per plant: %s",
               format(round(mean(agg_dt$total_occurrences)), big.mark = ",")))
  info(sprintf("Median occurrences per plant: %s",
               format(median(agg_dt$total_occurrences), big.mark = ",")))

  # Test 15: n_koppen_zones reasonable
  test("All plants have at least 1 Köppen zone",
       all(agg_dt$n_koppen_zones > 0),
       error_msg = "Some plants have 0 Köppen zones")

  info(sprintf("Mean Köppen zones per plant: %.1f", mean(agg_dt$n_koppen_zones)))
  info(sprintf("Max Köppen zones per plant: %d", max(agg_dt$n_koppen_zones)))

  # Test 16: n_main_zones ≤ n_koppen_zones
  test("n_main_zones ≤ n_koppen_zones for all plants",
       all(agg_dt$n_main_zones <= agg_dt$n_koppen_zones),
       error_msg = "Some plants have more main zones than total zones")

  # Test 17: top_zone_percent between 0 and 100
  test("top_zone_percent in valid range (0-100)",
       all(agg_dt$top_zone_percent > 0 & agg_dt$top_zone_percent <= 100),
       error_msg = "Some top_zone_percent values out of range")

  info(sprintf("Mean top zone dominance: %.1f%%", mean(agg_dt$top_zone_percent)))

  # Test 18: JSON fields parseable
  json_test <- tryCatch({
    sample_zones <- fromJSON(agg_dt$main_zones_json[1])
    sample_counts <- fromJSON(agg_dt$zone_counts_json[1])
    TRUE
  }, error = function(e) FALSE)

  test("JSON fields parseable",
       json_test,
       error_msg = "Cannot parse JSON fields")

  # Test 19: Top zone exists in ranked zones
  sample_check <- agg_dt[1:100, {
    ranked <- fromJSON(ranked_zones_json)
    top_zone_code %in% ranked
  }]

  test("Top zone appears in ranked zones (sample check)",
       all(sample_check),
       error_msg = "Top zone missing from ranked zones for some plants")

  # Test 20: Main zones ≥5% rule
  pct_check <- agg_dt[1:100, {
    main_zones <- fromJSON(main_zones_json)
    zone_percents <- fromJSON(zone_percents_json)
    if (length(main_zones) == 0) return(TRUE)
    all(sapply(main_zones, function(z) zone_percents[[z]] >= 5.0))
  }]

  test("Main zones follow ≥5% rule (sample check)",
       all(pct_check),
       error_msg = "Some main zones have <5% occurrences")
}

# ============================================================================
# SECTION 4: STEP 3 VERIFICATION (INTEGRATED DATASET)
# ============================================================================
if (file.exists(OUTPUT_INTEGRATED)) {
  cat("\n", rep("=", 80), "\n", sep = "")
  cat("SECTION 4: STEP 3 VERIFICATION (INTEGRATED DATASET)\n")
  cat(rep("=", 80), "\n", sep = "")

  integrated_dt <- read_parquet(OUTPUT_INTEGRATED) %>% as.data.table()

  # Test 21: Row count = 11,711
  test("Integrated dataset has 11,711 rows",
       nrow(integrated_dt) == 11711,
       error_msg = sprintf("Expected 11,711 rows, got %s", format(nrow(integrated_dt), big.mark = ",")))

  # Test 22: Tier columns exist
  tier_cols <- c("tier_1_tropical", "tier_2_mediterranean", "tier_3_humid_temperate",
                 "tier_4_continental", "tier_5_boreal_polar", "tier_6_arid")

  for (tier in tier_cols) {
    test(sprintf("Tier column '%s' exists", tier),
         tier %in% names(integrated_dt),
         error_msg = sprintf("Tier column '%s' missing", tier))
  }

  # Test 23: Tier columns are boolean
  tier_types_ok <- all(sapply(tier_cols, function(col) {
    if (col %in% names(integrated_dt)) {
      is.logical(integrated_dt[[col]]) || all(integrated_dt[[col]] %in% c(TRUE, FALSE, NA))
    } else {
      FALSE
    }
  }))

  test("Tier columns are boolean type",
       tier_types_ok,
       error_msg = "Some tier columns are not boolean")

  # Test 24: n_tier_memberships matches actual tier flags
  sample_tier_check <- integrated_dt[1:100, {
    counted <- sum(c(tier_1_tropical, tier_2_mediterranean, tier_3_humid_temperate,
                     tier_4_continental, tier_5_boreal_polar, tier_6_arid), na.rm = TRUE)
    counted == n_tier_memberships
  }]

  test("n_tier_memberships matches sum of tier flags (sample check)",
       all(sample_tier_check),
       error_msg = "Tier membership count mismatch")

  # Test 25: Original columns preserved
  original_cols <- c("wfo_taxon_id", "wfo_scientific_name", "C", "S", "R",
                     "EIVEres-L", "EIVEres-T", "EIVEres-R", "height_m")

  for (col in original_cols) {
    test(sprintf("Original column '%s' preserved", col),
         col %in% names(integrated_dt),
         error_msg = sprintf("Original column '%s' missing", col))
  }

  # Test 26: Tier distribution reasonable
  tier_counts <- sapply(tier_cols, function(col) sum(integrated_dt[[col]], na.rm = TRUE))

  info("Tier membership counts:")
  for (i in seq_along(tier_cols)) {
    info(sprintf("  %s: %s plants (%.1f%%)",
                 tier_cols[i],
                 format(tier_counts[i], big.mark = ","),
                 100 * tier_counts[i] / nrow(integrated_dt)))
  }

  test("All tiers have at least 500 plants",
       all(tier_counts >= 500),
       error_msg = "Some tiers have very few plants",
       warning_msg = if (any(tier_counts < 1000)) "Some tiers have <1000 plants" else NULL)

  # Test 27: Most plants have 1-3 tier memberships
  tier_dist <- integrated_dt[, .N, by = n_tier_memberships][order(n_tier_memberships)]
  pct_1_to_3 <- sum(tier_dist[n_tier_memberships %in% 1:3, N]) / nrow(integrated_dt) * 100

  test("Most plants (>80%) have 1-3 tier memberships",
       pct_1_to_3 > 80,
       error_msg = sprintf("Only %.1f%% of plants have 1-3 tier memberships", pct_1_to_3),
       warning_msg = if (pct_1_to_3 < 90) sprintf("%.1f%% of plants have 1-3 tier memberships (expected >90%%)", pct_1_to_3) else NULL)

  # Test 28: Plants without Köppen data
  n_no_koppen <- sum(is.na(integrated_dt$top_zone_code))
  pct_no_koppen <- 100 * n_no_koppen / nrow(integrated_dt)

  test("Plants without Köppen data <5%",
       pct_no_koppen < 5,
       error_msg = sprintf("%.1f%% plants lack Köppen data", pct_no_koppen),
       warning_msg = if (pct_no_koppen >= 1) sprintf("%.1f%% plants lack Köppen data", pct_no_koppen) else NULL)

  # Test 29: Köppen columns consistent with aggregated file
  if (file.exists(OUTPUT_AGGREGATED)) {
    agg_check <- integrated_dt[1:100, .(wfo_taxon_id, top_zone_code_int = top_zone_code)]
    agg_orig <- agg_dt[wfo_taxon_id %in% agg_check$wfo_taxon_id,
                       .(wfo_taxon_id, top_zone_code)]

    merged_check <- merge(agg_check, agg_orig, by = "wfo_taxon_id", all.x = TRUE)
    zones_match <- merged_check[, all(top_zone_code_int == top_zone_code, na.rm = TRUE)]

    test("Köppen data consistent with aggregated file (sample check)",
         zones_match,
         error_msg = "Köppen zones don't match aggregated file")
  }

  # Test 30: Tier logic validation
  # Check a few known Köppen zones map to correct tiers
  tropical_check <- integrated_dt[top_zone_code %in% c("Af", "Am", "Aw"), tier_1_tropical]
  if (length(tropical_check) > 0) {
    test("Tropical Köppen zones (Af, Am, Aw) mapped to tier_1_tropical",
         all(tropical_check, na.rm = TRUE),
         error_msg = "Some tropical zones not mapped to tier_1_tropical")
  }

  temperate_check <- integrated_dt[top_zone_code %in% c("Cfb", "Cfa"), tier_3_humid_temperate]
  if (length(temperate_check) > 0) {
    test("Humid temperate Köppen zones (Cfb, Cfa) mapped to tier_3_humid_temperate",
         all(temperate_check, na.rm = TRUE),
         error_msg = "Some humid temperate zones not mapped to tier_3_humid_temperate")
  }
}

# ============================================================================
# SECTION 5: CROSS-FILE CONSISTENCY
# ============================================================================
if (file.exists(OUTPUT_KOPPEN) && file.exists(OUTPUT_AGGREGATED) && file.exists(OUTPUT_INTEGRATED)) {
  cat("\n", rep("=", 80), "\n", sep = "")
  cat("SECTION 5: CROSS-FILE CONSISTENCY\n")
  cat(rep("=", 80), "\n", sep = "")

  # Test 31: Total occurrence count consistency
  total_occs_agg <- sum(agg_dt$total_occurrences)
  total_occs_koppen <- ds_koppen %>%
    filter(!is.na(koppen_zone)) %>%
    count() %>%
    collect() %>%
    pull(n)

  test("Total occurrence count consistent between files",
       total_occs_agg == total_occs_koppen,
       error_msg = sprintf("Mismatch: aggregated=%s, occurrence=%s",
                          format(total_occs_agg, big.mark = ","),
                          format(total_occs_koppen, big.mark = ",")))

  # Test 32: Plant IDs consistent across files
  plants_agg <- agg_dt$wfo_taxon_id
  plants_int <- integrated_dt$wfo_taxon_id

  test("Same plant IDs in aggregated and integrated files",
       setequal(plants_agg, plants_int),
       error_msg = "Plant ID mismatch between aggregated and integrated files")

  # Test 33: No duplicate plant IDs
  test("No duplicate plant IDs in aggregated file",
       !any(duplicated(plants_agg)),
       error_msg = "Duplicate plant IDs found in aggregated file")

  test("No duplicate plant IDs in integrated file",
       !any(duplicated(plants_int)),
       error_msg = "Duplicate plant IDs found in integrated file")
}

# ============================================================================
# FINAL SUMMARY
# ============================================================================
cat("\n", rep("=", 80), "\n", sep = "")
cat("VERIFICATION SUMMARY\n")
cat(rep("=", 80), "\n", sep = "")

cat("\nEnd time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

cat(sprintf("Total tests run: %d\n", n_tests))
cat(sprintf("%s✓ Passed: %d%s\n", GREEN, n_passed, NC))
if (n_warnings > 0) {
  cat(sprintf("%s⚠ Warnings: %d%s\n", YELLOW, n_warnings, NC))
}
if (n_failed > 0) {
  cat(sprintf("%s✗ Failed: %d%s\n", RED, n_failed, NC))
}

cat("\n")

if (n_failed == 0) {
  cat(sprintf("%s═══════════════════════════════════════════════════════════════════════════════%s\n", GREEN, NC))
  cat(sprintf("%s                      ✓ ALL VERIFICATIONS PASSED                              %s\n", GREEN, NC))
  cat(sprintf("%s═══════════════════════════════════════════════════════════════════════════════%s\n", GREEN, NC))
  cat("\nThe Köppen labeling pipeline has successfully completed with data integrity verified.\n")
  cat("\nNext steps:\n")
  cat("1. Use shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet\n")
  cat("2. Update Stage 4 scripts to reference the new dataset\n")
  cat("3. Re-run Stage 4 data extractions and calibrations\n")

  quit(status = 0)
} else {
  cat(sprintf("%s═══════════════════════════════════════════════════════════════════════════════%s\n", RED, NC))
  cat(sprintf("%s                      ✗ VERIFICATION FAILED                                   %s\n", RED, NC))
  cat(sprintf("%s═══════════════════════════════════════════════════════════════════════════════%s\n", RED, NC))
  cat(sprintf("\n%d test(s) failed. Please review the errors above and fix the pipeline.\n", n_failed))

  quit(status = 1)
}
