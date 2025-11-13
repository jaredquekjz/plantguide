# ==============================================================================
# TEST: Lookup Tables Module
# ==============================================================================

library(dplyr)

# Source the module
source("shipley_checks/src/encyclopedia/utils/lookup_tables.R")

cat("\n=== TEST 1: Module Initialization ===\n")
cat("EIVE bins should auto-load if in project directory\n")
if (exists("L_bins", envir = .lookup_env)) {
  cat("✓ Bins loaded successfully\n")
} else {
  cat("✗ Bins not loaded, trying manual load...\n")
  load_eive_bins()
}

cat("\n=== TEST 2: Light (L) Axis ===\n")
test_cases_L <- data.frame(
  value = c(1.0, 2.8, 4.9, 7.4, 8.8, 10.0, NA),
  expected_pattern = c("deep shade", "shade plant", "semi-shade", "half-light", "full-light", "full-light", NA)
)

for (i in 1:nrow(test_cases_L)) {
  val <- test_cases_L$value[i]
  label <- get_light_label(val)

  if (is.na(val)) {
    if (is.na(label)) {
      cat(sprintf("✓ L=NA → NA (correct)\n"))
    } else {
      cat(sprintf("✗ L=NA → '%s' (expected NA)\n", label))
    }
  } else {
    pattern_match <- grepl(test_cases_L$expected_pattern[i], label, ignore.case = TRUE)
    status <- if (pattern_match) "✓" else "✗"
    cat(sprintf("%s L=%.1f → '%s'\n", status, val, label))
  }
}

cat("\n=== TEST 3: Moisture (M) Axis ===\n")
test_cases_M <- data.frame(
  value = c(1.0, 3.5, 5.5, 7.5, 9.0),
  expected_pattern = c("extreme dryness", "moderately dry|dry", "moist", "wet", "water")
)

for (i in 1:nrow(test_cases_M)) {
  val <- test_cases_M$value[i]
  label <- get_moisture_label(val)
  pattern_match <- grepl(test_cases_M$expected_pattern[i], label, ignore.case = TRUE)
  status <- if (pattern_match) "✓" else "✗"
  cat(sprintf("%s M=%.1f → '%s'\n", status, val, label))
}

cat("\n=== TEST 4: Temperature (T) Axis ===\n")
test_cases_T <- data.frame(
  value = c(0.5, 3.2, 5.5, 8.1, 9.8),
  expected_pattern = c("cold|alpine|arctic", "cool|montane", "warm|colline", "hot|mediterranean", "hot|subtropical")
)

for (i in 1:nrow(test_cases_T)) {
  val <- test_cases_T$value[i]
  label <- get_temperature_label(val)
  pattern_match <- grepl(test_cases_T$expected_pattern[i], label, ignore.case = TRUE)
  status <- if (pattern_match) "✓" else "✗"
  cat(sprintf("%s T=%.1f → '%s'\n", status, val, label))
}

cat("\n=== TEST 5: Reaction/pH (R) Axis ===\n")
test_cases_R <- data.frame(
  value = c(1.0, 4.0, 5.5, 7.0, 9.0),
  expected_pattern = c("acid", "acid", "weakly acid|neutral", "neutral|weakly", "alkaline|basic")
)

for (i in 1:nrow(test_cases_R)) {
  val <- test_cases_R$value[i]
  label <- get_ph_label(val)
  pattern_match <- grepl(test_cases_R$expected_pattern[i], label, ignore.case = TRUE)
  status <- if (pattern_match) "✓" else "✗"
  cat(sprintf("%s R=%.1f → '%s'\n", status, val, label))
}

cat("\n=== TEST 6: Nitrogen/Fertility (N) Axis ===\n")
test_cases_N <- data.frame(
  value = c(1.0, 3.0, 5.0, 7.0, 9.0),
  expected_pattern = c("infertile|oligotrophic", "poor", "moderate|mesotrophic", "rich|eutrophic", "very rich|eutrophic")
)

for (i in 1:nrow(test_cases_N)) {
  val <- test_cases_N$value[i]
  label <- get_fertility_label(val)
  pattern_match <- grepl(test_cases_N$expected_pattern[i], label, ignore.case = TRUE)
  status <- if (pattern_match) "✓" else "✗"
  cat(sprintf("%s N=%.1f → '%s'\n", status, val, label))
}

cat("\n=== TEST 7: Vectorized Mapping ===\n")
light_values <- c(2.0, 5.0, 8.0)
labels <- map_eive_labels(light_values, "L")
cat(sprintf("Input: L = %s\n", paste(light_values, collapse = ", ")))
cat(sprintf("Output: %d labels returned\n", length(labels)))
if (length(labels) == 3 && all(!is.na(labels))) {
  cat("✓ Vectorized mapping works\n")
} else {
  cat("✗ Vectorized mapping failed\n")
}

cat("\n=== TEST 8: Edge Cases ===\n")
# Test exact boundary values
edge_L <- c(0.0, 1.6, 2.44, 10.0)
for (val in edge_L) {
  label <- get_light_label(val)
  cat(sprintf("L=%.2f → '%s'\n", val, substr(label, 1, 40)))
}

cat("\n=== TEST COMPLETE ===\n")
