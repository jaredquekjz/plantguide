# ==============================================================================
# TEST: Complete Encyclopedia Page Generation
# ==============================================================================

# Source the coordinator
source("shipley_checks/src/encyclopedia/encyclopedia_generator.R")

cat("\n=== TEST: Complete Encyclopedia Page Generation ===\n\n")

# ==============================================================================
# Initialize generator
# ==============================================================================

generator <- EncyclopediaGenerator$new(
  plant_data_path = "/tmp/test_plants_sample.csv"
)

# ==============================================================================
# Generate pages for test samples
# ==============================================================================

test_ids <- c("wfo-0000614323", "wfo-0000447854", "wfo-0000631143")

for (wfo_id in test_ids) {
  cat(sprintf("\n--- Generating page for %s ---\n", wfo_id))

  page <- generator$generate_page(wfo_id)

  cat("\nGenerated Page:\n")
  cat(strrep("=", 70))
  cat("\n")
  cat(page)
  cat("\n")
  cat(strrep("=", 70))
  cat("\n\n")
}

# ==============================================================================
# Test batch generation (3 plants to output directory)
# ==============================================================================

cat("\n--- Testing Batch Generation ---\n")
generator$batch_generate(
  wfo_ids = test_ids,
  output_dir = "output/encyclopedia_test"
)

cat("\n=== TEST COMPLETE ===\n")
cat("Check output/encyclopedia_test/ for generated markdown files\n")
