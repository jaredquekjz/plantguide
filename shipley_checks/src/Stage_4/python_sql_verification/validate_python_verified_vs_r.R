#!/usr/bin/env Rscript
#
# Validation: Compare VERIFIED Python vs Pure R
#

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(digest)
})

cat("================================================================================\n")
cat("VALIDATION: Verified Python vs Pure R\n")
cat("================================================================================\n\n")

# Paths
python_csv <- "shipley_checks/validation/fungal_guilds_python_VERIFIED.csv"
r_csv <- "shipley_checks/validation/fungal_guilds_pure_r.csv"

# Checksums
cat("File Checksums:\n")
cat(paste(rep("=", 80), collapse = ""), "\n")

python_md5 <- digest(file = python_csv, algo = "md5")
r_md5 <- digest(file = r_csv, algo = "md5")

cat("Python VERIFIED MD5:", python_md5, "\n")
cat("R MD5:              ", r_md5, "\n\n")

if (python_md5 == r_md5) {
  cat("✓ SUCCESS: Files are byte-for-byte IDENTICAL!\n\n")
  quit(save = "no", status = 0)
}

cat("Checksums differ - running detailed comparison...\n\n")

# Load data
python_df <- read_csv(python_csv, show_col_types = FALSE)
r_df <- read_csv(r_csv, show_col_types = FALSE)

# Numeric columns
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

cat("Numeric Column Comparison:\n")
cat(paste(rep("=", 80), collapse = ""), "\n")

all_match <- TRUE
for (col in numeric_cols) {
  python_total <- sum(python_df[[col]], na.rm = TRUE)
  r_total <- sum(r_df[[col]], na.rm = TRUE)
  diff <- r_total - python_total
  rows_differ <- sum(python_df[[col]] != r_df[[col]], na.rm = TRUE)

  status <- if (diff == 0) "✓" else "⚠️ "
  cat(sprintf("%s %s: Python=%s, R=%s, Diff=%+d (%d rows)\n",
              status, col, format(python_total, big.mark = ","),
              format(r_total, big.mark = ","), diff, rows_differ))

  if (diff != 0) all_match <- FALSE
}

cat("\n")

if (all_match) {
  cat("✓ SUCCESS: All numeric columns match exactly!\n\n")
} else {
  cat("⚠️  Some numeric columns differ - investigating...\n\n")
}

# Summary statistics
cat("Summary Statistics Comparison:\n")
cat(paste(rep("=", 80), collapse = ""), "\n")

cat("Python VERIFIED:\n")
cat(sprintf("  - Pathogenic: %d plants\n", sum(python_df$pathogenic_fungi_count > 0)))
cat(sprintf("  - Mycorrhizal: %d plants\n", sum(python_df$mycorrhizae_total_count > 0)))
cat(sprintf("  - Biocontrol: %d plants\n", sum(python_df$biocontrol_total_count > 0)))
cat(sprintf("  - FunGuild genera: %s\n", format(sum(python_df$funguild_genera), big.mark = ",")))

cat("\nR:\n")
cat(sprintf("  - Pathogenic: %d plants\n", sum(r_df$pathogenic_fungi_count > 0)))
cat(sprintf("  - Mycorrhizal: %d plants\n", sum(r_df$mycorrhizae_total_count > 0)))
cat(sprintf("  - Biocontrol: %d plants\n", sum(r_df$biocontrol_total_count > 0)))
cat(sprintf("  - FunGuild genera: %s\n", format(sum(r_df$funguild_genera), big.mark = ",")))

cat("\n================================================================================\n")
cat("RESULT:", if (all_match) "✓ VERIFIED" else "⚠️  DIFFERS", "\n")
cat("================================================================================\n")
