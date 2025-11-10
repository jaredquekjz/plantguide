#!/usr/bin/env Rscript
#
# Validation: Compare Pure R vs Python Fungal Guilds Extraction
#
# Purpose:
#   Compare the CSV outputs from Python (DuckDB) and pure R (arrow+dplyr)
#   to identify any differences in the extraction logic.
#
# Tests:
#   1. File checksums (MD5/SHA256) - Quick check for byte-for-byte match
#   2. Row counts - Should both be 11,711 plants
#   3. Column structure - Same columns in same order
#   4. Numeric columns - Should match exactly
#   5. List columns - Compare as sets (order within lists might differ)
#   6. Identify differing rows - Where do they differ and why?
#
# Usage:
#   Rscript shipley_checks/src/Stage_4/EXPERIMENT_validate_r_vs_python.R

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(digest)
})

cat("================================================================================\n")
cat("VALIDATION: Pure R vs Python Fungal Guilds Extraction\n")
cat("================================================================================\n")
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Paths
python_csv <- "shipley_checks/validation/fungal_guilds_python_baseline.csv"
r_csv <- "shipley_checks/validation/fungal_guilds_pure_r.csv"

# ===============================================================================
# Test 1: File Checksums
# ===============================================================================

cat("Test 1: File Checksums\n")
cat(paste(rep("=", 80), collapse = ""), "\n")

python_md5 <- digest(file = python_csv, algo = "md5")
r_md5 <- digest(file = r_csv, algo = "md5")

python_sha256 <- digest(file = python_csv, algo = "sha256")
r_sha256 <- digest(file = r_csv, algo = "sha256")

cat("Python MD5:   ", python_md5, "\n")
cat("R MD5:        ", r_md5, "\n")
cat("\n")
cat("Python SHA256:", python_sha256, "\n")
cat("R SHA256:     ", r_sha256, "\n")
cat("\n")

if (python_md5 == r_md5) {
  cat("✓ PASS: Files are byte-for-byte IDENTICAL!\n")
  cat("       No further validation needed.\n\n")
  quit(save = "no", status = 0)
} else {
  cat("⚠️  Files differ - continuing with detailed comparison...\n\n")
}

# ===============================================================================
# Test 2: Load Data and Check Row Counts
# ===============================================================================

cat("Test 2: Row Counts\n")
cat(paste(rep("=", 80), collapse = ""), "\n")

python_df <- read_csv(python_csv, show_col_types = FALSE)
r_df <- read_csv(r_csv, show_col_types = FALSE)

cat("Python rows:", nrow(python_df), "\n")
cat("R rows:     ", nrow(r_df), "\n")

if (nrow(python_df) == nrow(r_df)) {
  cat("✓ PASS: Row counts match\n\n")
} else {
  cat("✗ FAIL: Row counts differ!\n\n")
}

# ===============================================================================
# Test 3: Column Structure
# ===============================================================================

cat("Test 3: Column Structure\n")
cat(paste(rep("=", 80), collapse = ""), "\n")

cat("Python columns:", ncol(python_df), "\n")
cat("R columns:     ", ncol(r_df), "\n")

python_cols <- names(python_df)
r_cols <- names(r_df)

if (identical(python_cols, r_cols)) {
  cat("✓ PASS: Column names and order match\n\n")
} else {
  cat("⚠️  Column names or order differ\n")
  cat("Python-only columns:", setdiff(python_cols, r_cols), "\n")
  cat("R-only columns:", setdiff(r_cols, python_cols), "\n\n")
}

# ===============================================================================
# Test 4: Numeric Column Comparison
# ===============================================================================

cat("Test 4: Numeric Columns (Counts and Totals)\n")
cat(paste(rep("=", 80), collapse = ""), "\n")

numeric_cols <- c(
  'pathogenic_fungi_count',
  'pathogenic_fungi_host_specific_count',
  'amf_fungi_count',
  'emf_fungi_count',
  'mycorrhizae_total_count',
  'mycoparasite_fungi_count',
  'entomopathogenic_fungi_count',
  'biocontrol_total_count',
  'endophytic_fungi_count',
  'saprotrophic_fungi_count',
  'trichoderma_count',
  'beauveria_metarhizium_count',
  'fungaltraits_genera',
  'funguild_genera'
)

numeric_diffs <- tibble(
  column = character(),
  python_total = numeric(),
  r_total = numeric(),
  diff = numeric(),
  rows_differ = integer()
)

for (col in numeric_cols) {
  python_total <- sum(python_df[[col]], na.rm = TRUE)
  r_total <- sum(r_df[[col]], na.rm = TRUE)
  diff <- r_total - python_total
  rows_differ <- sum(python_df[[col]] != r_df[[col]], na.rm = TRUE)

  numeric_diffs <- bind_rows(
    numeric_diffs,
    tibble(
      column = col,
      python_total = python_total,
      r_total = r_total,
      diff = diff,
      rows_differ = rows_differ
    )
  )

  status <- if (diff == 0) "✓" else "⚠️ "
  cat(sprintf("%s %s: Python=%s, R=%s, Diff=%+d (%d rows differ)\n",
              status, col, format(python_total, big.mark = ","),
              format(r_total, big.mark = ","), diff, rows_differ))
}

cat("\n")

if (all(numeric_diffs$diff == 0)) {
  cat("✓ PASS: All numeric columns match exactly\n\n")
} else {
  cat("⚠️  Some numeric columns differ\n\n")
}

# ===============================================================================
# Test 5: List Column Comparison (as Sets)
# ===============================================================================

cat("Test 5: List Columns (Pipe-Separated Genera)\n")
cat(paste(rep("=", 80), collapse = ""), "\n")

list_cols <- c(
  'pathogenic_fungi',
  'pathogenic_fungi_host_specific',
  'amf_fungi',
  'emf_fungi',
  'mycoparasite_fungi',
  'entomopathogenic_fungi',
  'endophytic_fungi',
  'saprotrophic_fungi'
)

# Function to compare lists as sets (ignoring order)
compare_lists <- function(python_str, r_str) {
  # Handle NA values
  if (is.na(python_str) && is.na(r_str)) return(TRUE)
  if (is.na(python_str) || is.na(r_str)) return(FALSE)

  # Handle empty strings
  if (python_str == "" && r_str == "") return(TRUE)
  if (python_str == "" || r_str == "") return(FALSE)

  # Split and sort
  python_set <- sort(strsplit(python_str, "\\|")[[1]])
  r_set <- sort(strsplit(r_str, "\\|")[[1]])

  # Compare
  identical(python_set, r_set)
}

list_diffs <- tibble(
  column = character(),
  rows_differ = integer(),
  pct_differ = numeric()
)

for (col in list_cols) {
  # Count rows where lists differ
  differ_count <- sum(
    mapply(
      function(p, r) !compare_lists(as.character(p), as.character(r)),
      python_df[[col]],
      r_df[[col]]
    ),
    na.rm = TRUE
  )

  pct_differ <- differ_count / nrow(python_df) * 100

  list_diffs <- bind_rows(
    list_diffs,
    tibble(
      column = col,
      rows_differ = differ_count,
      pct_differ = pct_differ
    )
  )

  status <- if (differ_count == 0) "✓" else "⚠️ "
  cat(sprintf("%s %s: %d rows differ (%.2f%%)\n", status, col, differ_count, pct_differ))
}

cat("\n")

if (all(list_diffs$rows_differ == 0)) {
  cat("✓ PASS: All list columns match exactly\n\n")
} else {
  cat("⚠️  Some list columns differ\n\n")
}

# ===============================================================================
# Test 6: Identify Specific Differing Rows
# ===============================================================================

cat("Test 6: Detailed Row-by-Row Comparison\n")
cat(paste(rep("=", 80), collapse = ""), "\n")

# Find rows where ANY numeric column differs
numeric_mismatch_mask <- rep(FALSE, nrow(python_df))
for (col in numeric_cols) {
  numeric_mismatch_mask <- numeric_mismatch_mask | (python_df[[col]] != r_df[[col]])
}

differing_rows <- which(numeric_mismatch_mask)

cat("Rows with numeric differences:", length(differing_rows), "\n")

if (length(differing_rows) > 0) {
  cat("\nFirst 20 differing plants:\n\n")

  for (i in head(differing_rows, 20)) {
    cat("Row", i, ":", python_df$wfo_scientific_name[i], "\n")
    cat("  Python - Pathogenic:", python_df$pathogenic_fungi_count[i],
        ", Mycorrhizae:", python_df$mycorrhizae_total_count[i],
        ", Biocontrol:", python_df$biocontrol_total_count[i], "\n")
    cat("  R      - Pathogenic:", r_df$pathogenic_fungi_count[i],
        ", Mycorrhizae:", r_df$mycorrhizae_total_count[i],
        ", Biocontrol:", r_df$biocontrol_total_count[i], "\n")
    cat("\n")
  }
}

# ===============================================================================
# Test 7: Source Tracking Comparison
# ===============================================================================

cat("Test 7: Source Tracking (FungalTraits vs FunGuild)\n")
cat(paste(rep("=", 80), collapse = ""), "\n")

python_ft_total <- sum(python_df$fungaltraits_genera)
python_fg_total <- sum(python_df$funguild_genera)
r_ft_total <- sum(r_df$fungaltraits_genera)
r_fg_total <- sum(r_df$funguild_genera)

cat("Python - FungalTraits:", format(python_ft_total, big.mark = ","),
    ", FunGuild:", format(python_fg_total, big.mark = ","), "\n")
cat("R      - FungalTraits:", format(r_ft_total, big.mark = ","),
    ", FunGuild:", format(r_fg_total, big.mark = ","), "\n")
cat("Diff   - FungalTraits:", format(r_ft_total - python_ft_total, big.mark = ","),
    ", FunGuild:", format(r_fg_total - python_fg_total, big.mark = ","), "\n")
cat("\n")

# Find plants with FunGuild differences
fg_diffs <- which(python_df$funguild_genera != r_df$funguild_genera)
cat("Plants with FunGuild count differences:", length(fg_diffs), "\n")

if (length(fg_diffs) > 0) {
  cat("\nFirst 10 plants with FunGuild differences:\n\n")

  for (i in head(fg_diffs, 10)) {
    cat("Row", i, ":", python_df$wfo_scientific_name[i], "\n")
    cat("  Python FunGuild genera:", python_df$funguild_genera[i], "\n")
    cat("  R FunGuild genera:     ", r_df$funguild_genera[i], "\n")
    cat("\n")
  }
}

# ===============================================================================
# Summary and Export Differences
# ===============================================================================

cat("================================================================================\n")
cat("SUMMARY\n")
cat("================================================================================\n\n")

cat("Checksum match:", if (python_md5 == r_md5) "YES ✓" else "NO ⚠️ ", "\n")
cat("Row count match:", if (nrow(python_df) == nrow(r_df)) "YES ✓" else "NO ✗", "\n")
cat("Numeric columns match:", if (all(numeric_diffs$diff == 0)) "YES ✓" else "NO ⚠️ ", "\n")
cat("List columns match:", if (all(list_diffs$rows_differ == 0)) "YES ✓" else "NO ⚠️ ", "\n")
cat("\n")

cat("Total plants with differences:", length(differing_rows),
    sprintf("(%.2f%%)\n", length(differing_rows)/nrow(python_df)*100))
cat("\n")

cat("Key differences:\n")
for (i in 1:nrow(numeric_diffs)) {
  if (numeric_diffs$diff[i] != 0) {
    cat(sprintf("  - %s: %+d (%d rows)\n",
                numeric_diffs$column[i],
                numeric_diffs$diff[i],
                numeric_diffs$rows_differ[i]))
  }
}
cat("\n")

# Export differing rows for detailed analysis
if (length(differing_rows) > 0) {
  diff_file <- "shipley_checks/validation/differing_rows_analysis.csv"

  diff_analysis <- tibble(
    row_number = differing_rows,
    plant_wfo_id = python_df$plant_wfo_id[differing_rows],
    wfo_scientific_name = python_df$wfo_scientific_name[differing_rows],
    python_pathogenic = python_df$pathogenic_fungi_count[differing_rows],
    r_pathogenic = r_df$pathogenic_fungi_count[differing_rows],
    python_mycorrhizae = python_df$mycorrhizae_total_count[differing_rows],
    r_mycorrhizae = r_df$mycorrhizae_total_count[differing_rows],
    python_biocontrol = python_df$biocontrol_total_count[differing_rows],
    r_biocontrol = r_df$biocontrol_total_count[differing_rows],
    python_ft = python_df$fungaltraits_genera[differing_rows],
    r_ft = r_df$fungaltraits_genera[differing_rows],
    python_fg = python_df$funguild_genera[differing_rows],
    r_fg = r_df$funguild_genera[differing_rows]
  )

  write_csv(diff_analysis, diff_file)
  cat("Exported differing rows to:", diff_file, "\n\n")
}

cat("================================================================================\n")
cat("Completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("================================================================================\n")
