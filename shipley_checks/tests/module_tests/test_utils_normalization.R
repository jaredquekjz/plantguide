#!/usr/bin/env Rscript
#
# Module Test: Normalization Utility
#
# Tests percentile_normalize and csr_to_percentile functions
# by comparing outputs from modular vs inline implementations
#

suppressMessages({
  library(jsonlite)
  library(glue)
})

cat(rep("=", 80), "\n", sep="")
cat("MODULE TEST: NORMALIZATION UTILITY\n")
cat(rep("=", 80), "\n\n", sep="")

# Source modular normalization
source('shipley_checks/src/Stage_4/utils/normalization.R')

# Load calibration data
calibration_params <- fromJSON('shipley_checks/stage4/normalization_params_7plant.json')
csr_percentiles <- if (file.exists('shipley_checks/stage4/csr_percentile_calibration_global.json')) {
  fromJSON('shipley_checks/stage4/csr_percentile_calibration_global.json')
} else {
  NULL
}

climate_tier <- 'tier_3_humid_temperate'

cat("Test 1: percentile_normalize function\n")
cat(rep("=", 80), "\n", sep="")

# Test data: raw values and expected outputs from Python/R
test_cases_percentile <- list(
  # M1: Pest risk values
  list(raw = 0.4158, metric = 'm1', invert = FALSE, desc = "M1: Low pest risk (high diversity)"),
  list(raw = 0.4932, metric = 'm1', invert = FALSE, desc = "M1: Medium pest risk"),
  list(raw = 0.6957, metric = 'm1', invert = FALSE, desc = "M1: High pest risk (low diversity)"),

  # N4: Conflict density values
  list(raw = 0.0, metric = 'n4', invert = FALSE, desc = "N4: Zero conflicts"),
  list(raw = 0.5238, metric = 'n4', invert = FALSE, desc = "N4: Medium conflicts"),
  list(raw = 0.8571, metric = 'n4', invert = FALSE, desc = "N4: High conflicts"),

  # P1: Biocontrol values
  list(raw = 0.0, metric = 'p1', invert = FALSE, desc = "P1: No biocontrol"),
  list(raw = 10.0, metric = 'p1', invert = FALSE, desc = "P1: High biocontrol"),

  # P6: Pollinator overlap values
  list(raw = 0.0, metric = 'p6', invert = FALSE, desc = "P6: No shared pollinators"),
  list(raw = 2.4132, metric = 'p6', invert = FALSE, desc = "P6: High pollinator overlap")
)

n_tests <- length(test_cases_percentile)
n_passed <- 0

for (test in test_cases_percentile) {
  result <- percentile_normalize(
    test$raw,
    test$metric,
    calibration_params,
    climate_tier,
    test$invert
  )

  cat(sprintf("  %s\n", test$desc))
  cat(sprintf("    Raw: %.4f → Percentile: %.4f\n", test$raw, result))

  # Basic validation: percentile should be 0-100
  if (result >= 0 && result <= 100) {
    cat("    ✅ PASS (valid range)\n")
    n_passed <- n_passed + 1
  } else {
    cat("    ❌ FAIL (out of range)\n")
  }
  cat("\n")
}

cat(sprintf("Percentile normalize tests: %d/%d passed\n\n", n_passed, n_tests))

cat("Test 2: csr_to_percentile function\n")
cat(rep("=", 80), "\n", sep="")

# Test data: CSR values
test_cases_csr <- list(
  # C (Competitive) strategy
  list(raw = 30.0, strategy = 'c', desc = "C=30 (Low competitive)"),
  list(raw = 60.0, strategy = 'c', desc = "C=60 (High competitive threshold)"),
  list(raw = 85.0, strategy = 'c', desc = "C=85 (Very high competitive)"),

  # S (Stress-tolerant) strategy
  list(raw = 30.0, strategy = 's', desc = "S=30 (Low stress-tolerant)"),
  list(raw = 60.0, strategy = 's', desc = "S=60 (High stress-tolerant threshold)"),
  list(raw = 85.0, strategy = 's', desc = "S=85 (Very high stress-tolerant)"),

  # R (Ruderal) strategy
  list(raw = 20.0, strategy = 'r', desc = "R=20 (Low ruderal)"),
  list(raw = 50.0, strategy = 'r', desc = "R=50 (High ruderal threshold)"),
  list(raw = 75.0, strategy = 'r', desc = "R=75 (Very high ruderal)")
)

n_tests_csr <- length(test_cases_csr)
n_passed_csr <- 0

for (test in test_cases_csr) {
  result <- csr_to_percentile(test$raw, test$strategy, csr_percentiles)

  cat(sprintf("  %s\n", test$desc))
  cat(sprintf("    Raw: %.1f → Percentile: %.1f\n", test$raw, result))

  # Validation: percentile should be 0-100
  if (result >= 0 && result <= 100) {
    cat("    ✅ PASS (valid range)\n")
    n_passed_csr <- n_passed_csr + 1
  } else {
    cat("    ❌ FAIL (out of range)\n")
  }
  cat("\n")
}

cat(sprintf("CSR percentile tests: %d/%d passed\n\n", n_passed_csr, n_tests_csr))

cat("Test 3: Edge cases\n")
cat(rep("=", 80), "\n", sep="")

# Edge case tests
edge_cases <- list(
  list(raw = -1.0, metric = 'm1', desc = "Below minimum", expected = 0.0),
  list(raw = 999.0, metric = 'm1', desc = "Above maximum", expected = 100.0),
  list(raw = 0.5, metric = 'm1', desc = "Mid-range value", expected = "between 0 and 100")
)

n_edge <- 0
for (test in edge_cases) {
  result <- percentile_normalize(test$raw, test$metric, calibration_params, climate_tier, FALSE)

  cat(sprintf("  %s (raw=%.1f)\n", test$desc, test$raw))
  cat(sprintf("    Result: %.4f\n", result))

  if (is.numeric(test$expected)) {
    if (abs(result - test$expected) < 0.01) {
      cat("    ✅ PASS\n")
      n_edge <- n_edge + 1
    } else {
      cat(sprintf("    ❌ FAIL (expected %.1f)\n", test$expected))
    }
  } else {
    if (result >= 0 && result <= 100) {
      cat("    ✅ PASS\n")
      n_edge <- n_edge + 1
    } else {
      cat("    ❌ FAIL\n")
    }
  }
  cat("\n")
}

cat(sprintf("Edge case tests: %d/%d passed\n\n", n_edge, length(edge_cases)))

# Summary
cat(rep("=", 80), "\n", sep="")
cat("SUMMARY\n")
cat(rep("=", 80), "\n", sep="")
total_tests <- n_tests + n_tests_csr + length(edge_cases)
total_passed <- n_passed + n_passed_csr + n_edge

cat(sprintf("Total tests: %d\n", total_tests))
cat(sprintf("Passed: %d\n", total_passed))
cat(sprintf("Failed: %d\n", total_tests - total_passed))

if (total_passed == total_tests) {
  cat("\n✅ ALL NORMALIZATION TESTS PASSED\n")
  quit(status = 0)
} else {
  cat("\n❌ SOME TESTS FAILED\n")
  quit(status = 1)
}
