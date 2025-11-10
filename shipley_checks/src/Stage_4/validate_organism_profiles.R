#!/usr/bin/env Rscript
#
# Validation: Organism Profiles (Python vs R)
#

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

cat("================================================================================\n")
cat("VALIDATION: Organism Profiles (Python vs R)\n")
cat("================================================================================\n\n")

# Load both CSVs
python_csv <- "shipley_checks/validation/organism_profiles_python_VERIFIED.csv"
r_csv <- "shipley_checks/validation/organism_profiles_pure_r.csv"

cat("Loading Python baseline...\n")
python <- read_csv(python_csv, show_col_types = FALSE)
cat("  ✓ Loaded", nrow(python), "rows,", ncol(python), "columns\n\n")

cat("Loading R output...\n")
r_data <- read_csv(r_csv, show_col_types = FALSE)
cat("  ✓ Loaded", nrow(r_data), "rows,", ncol(r_data), "columns\n\n")

# Compare column names
cat("Comparing column structure...\n")
if (identical(names(python), names(r_data))) {
  cat("  ✓ Column names match\n\n")
} else {
  cat("  ✗ Column names differ\n")
  cat("    Python:", paste(names(python), collapse = ", "), "\n")
  cat("    R:     ", paste(names(r_data), collapse = ", "), "\n\n")
}

# Compare counts for numeric columns
cat("Comparing count columns...\n")
count_cols <- c(
  'pollinator_count', 'herbivore_count', 'pathogen_count', 'visitor_count',
  'predators_hasHost_count', 'predators_interactsWith_count', 'predators_adjacentTo_count'
)

for (col in count_cols) {
  if (col %in% names(python) && col %in% names(r_data)) {
    python_total <- sum(python[[col]], na.rm = TRUE)
    r_total <- sum(r_data[[col]], na.rm = TRUE)
    diff <- r_total - python_total

    if (diff == 0) {
      cat(sprintf("  ✓ %s: %d (match)\n", col, python_total))
    } else {
      cat(sprintf("  ✗ %s: Python=%d, R=%d (diff: %+d)\n", col, python_total, r_total, diff))
    }
  }
}
cat("\n")

# Find sample plant with differences
cat("Finding sample plants with differences...\n")
merged <- python %>%
  select(plant_wfo_id, all_of(count_cols)) %>%
  inner_join(
    r_data %>% select(plant_wfo_id, all_of(count_cols)),
    by = "plant_wfo_id",
    suffix = c("_python", "_r")
  )

# Check for any differences
diff_plants <- merged %>%
  filter(
    pollinator_count_python != pollinator_count_r |
    herbivore_count_python != herbivore_count_r |
    pathogen_count_python != pathogen_count_r |
    visitor_count_python != visitor_count_r |
    predators_hasHost_count_python != predators_hasHost_count_r |
    predators_interactsWith_count_python != predators_interactsWith_count_r |
    predators_adjacentTo_count_python != predators_adjacentTo_count_r
  )

if (nrow(diff_plants) > 0) {
  cat(sprintf("  Found %d plants with differences\n", nrow(diff_plants)))
  cat("\nFirst 10 differing plants:\n")
  print(head(diff_plants, 10))
} else {
  cat("  ✓ All plants match!\n")
}

cat("\n================================================================================\n")
cat("VALIDATION COMPLETE\n")
cat("================================================================================\n")
