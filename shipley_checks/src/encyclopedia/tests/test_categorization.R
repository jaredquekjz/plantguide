# ==============================================================================
# TEST: Categorization Module
# ==============================================================================

library(dplyr)

# Source the module
source("shipley_checks/src/encyclopedia/utils/categorization.R")

cat("\n=== TEST 1: CSR Strategy Categorization ===\n")

test_cases_csr <- data.frame(
  C = c(0.8, 0.1, 0.2, 0.5, 0.4, 0.35, 0.35, NA),
  S = c(0.1, 0.8, 0.1, 0.4, 0.1, 0.45, 0.35, 0.3),
  R = c(0.1, 0.1, 0.7, 0.1, 0.5, 0.2, 0.3, 0.4),
  expected = c("C", "S", "R", "CS", "CR", "CS", "CSR", NA)
)

for (i in 1:nrow(test_cases_csr)) {
  result <- get_csr_category(test_cases_csr$C[i],
                             test_cases_csr$S[i],
                             test_cases_csr$R[i])
  expected <- test_cases_csr$expected[i]

  match <- if (is.na(expected)) is.na(result) else (!is.na(result) && result == expected)
  status <- if (match) "✓" else "✗"

  cat(sprintf("%s C=%.2f, S=%.2f, R=%.2f → '%s' (expected '%s')\n",
              status,
              test_cases_csr$C[i],
              test_cases_csr$S[i],
              test_cases_csr$R[i],
              ifelse(is.na(result), "NA", result),
              ifelse(is.na(expected), "NA", expected)))
}

cat("\n=== TEST 2: CSR Strategy Descriptions ===\n")

for (cat_code in c("C", "S", "R", "CS", "CR", "SR", "CSR")) {
  desc <- get_csr_description(cat_code)
  cat(sprintf("%s: %s\n", cat_code, substr(desc, 1, 60)))
}

cat("\n=== TEST 3: Köppen to USDA Zone Mapping ===\n")

test_koppen <- data.frame(
  tier = c(1, 2, 3, 4, 5, 6, NA),
  expected_pattern = c("10|11|12|13", "8|9|10", "6|7|8|9", "4|5|6|7", "1|2|3|4|5", "5|6|7|8|9", NA)
)

for (i in 1:nrow(test_koppen)) {
  tier <- test_koppen$tier[i]
  usda <- map_koppen_to_usda(tier)
  desc <- get_koppen_description(tier)

  if (is.na(tier)) {
    status <- if (is.na(usda)) "✓" else "✗"
    cat(sprintf("%s Tier=NA → USDA=NA\n", status))
  } else {
    # Check if result matches expected pattern
    match <- grepl(test_koppen$expected_pattern[i], usda)
    status <- if (match) "✓" else "✗"
    cat(sprintf("%s Tier=%d (%s) → USDA zones %s\n",
                status, tier, desc, usda))
  }
}

cat("\n=== TEST 4: Ecosystem Service Confidence ===\n")

test_confidence <- data.frame(
  value = c(0.9, 0.7, 0.6, 0.4, 0.2, NA),
  expected = c("High", "High", "Moderate", "Moderate", "Low", NA)
)

for (i in 1:nrow(test_confidence)) {
  val <- test_confidence$value[i]
  result <- categorize_confidence(val)
  expected <- test_confidence$expected[i]

  match <- if (is.na(expected)) is.na(result) else (!is.na(result) && result == expected)
  status <- if (match) "✓" else "✗"

  cat(sprintf("%s Confidence=%.1f → '%s'\n",
              status,
              ifelse(is.na(val), NA, val),
              ifelse(is.na(result), "NA", result)))
}

cat("\n=== TEST 5: Woodiness Categorization ===\n")

test_woodiness <- data.frame(
  value = c(0.0, 0.2, 0.5, 0.8, 1.0, NA),
  expected = c("Herbaceous", "Herbaceous", "Semi-woody", "Woody", "Woody", NA)
)

for (i in 1:nrow(test_woodiness)) {
  val <- test_woodiness$value[i]
  result <- categorize_woodiness(val)
  expected <- test_woodiness$expected[i]

  match <- if (is.na(expected)) is.na(result) else (!is.na(result) && result == expected)
  status <- if (match) "✓" else "✗"

  cat(sprintf("%s Woodiness=%.1f → '%s'\n",
              status,
              ifelse(is.na(val), NA, val),
              ifelse(is.na(result), "NA", result)))
}

cat("\n=== TEST 6: Height Categorization ===\n")

test_height <- data.frame(
  value = c(0.1, 0.5, 1.5, 3.0, 6.0, NA),
  expected = c("Ground cover", "Low", "Medium", "Tall", "Very tall", NA)
)

for (i in 1:nrow(test_height)) {
  val <- test_height$value[i]
  result <- categorize_height(val)
  expected <- test_height$expected[i]

  match <- if (is.na(expected)) is.na(result) else (!is.na(result) && result == expected)
  status <- if (match) "✓" else "✗"

  cat(sprintf("%s Height=%.1fm → '%s'\n",
              status,
              ifelse(is.na(val), NA, val),
              ifelse(is.na(result), "NA", result)))
}

cat("\n=== TEST 7: Leaf Phenology Categorization ===\n")

test_phenology <- data.frame(
  value = c(6, 9, 12, 18, 24, NA),
  expected = c("Deciduous", "Semi-evergreen", "Semi-evergreen", "Evergreen", "Evergreen", NA)
)

for (i in 1:nrow(test_phenology)) {
  val <- test_phenology$value[i]
  result <- categorize_phenology(val)
  expected <- test_phenology$expected[i]

  match <- if (is.na(expected)) is.na(result) else (!is.na(result) && result == expected)
  status <- if (match) "✓" else "✗"

  cat(sprintf("%s Leaf longevity=%d months → '%s'\n",
              status,
              ifelse(is.na(val), NA, val),
              ifelse(is.na(result), "NA", result)))
}

cat("\n=== TEST 8: Edge Cases ===\n")

# Test boundary values
cat(sprintf("  Height 0.3m (boundary) → '%s'\n", categorize_height(0.3)))
cat(sprintf("  Height 1.0m (boundary) → '%s'\n", categorize_height(1.0)))
cat(sprintf("  Confidence 0.7 (boundary) → '%s'\n", categorize_confidence(0.7)))

cat("\n=== TEST COMPLETE ===\n")
