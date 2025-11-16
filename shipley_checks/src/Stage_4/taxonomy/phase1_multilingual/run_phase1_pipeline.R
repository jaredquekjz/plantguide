#!/usr/bin/env Rscript
#' Simplified Phase 1: Real Vernacular Names Only
#'
#' Assigns multilingual vernacular names using:
#'   P1: iNaturalist species vernaculars (12 languages)
#'   P2: ITIS family vernaculars (English only)
#'
#' NOTE: Derived categories (word frequency) removed.
#'       Animal categorization now handled by Phase 2 (Kimi AI).
#'
#' Author: Claude Code
#' Date: 2025-11-16

suppressPackageStartupMessages({
  library(arrow)
})

cat(strrep("=", 80), "\n")
cat("PHASE 1: MULTILINGUAL VERNACULAR NAMES\n")
cat("(Real names only - no synthetic categories)\n")
cat(strrep("=", 80), "\n\n")

# Get script directory
script_path <- commandArgs(trailingOnly = FALSE)
script_path <- script_path[grep("^--file=", script_path)]
if (length(script_path) > 0) {
  script_dir <- dirname(sub("^--file=", "", script_path))
} else {
  script_dir <- getwd()
}

DATA_DIR <- "/home/olier/ellenberg/data/taxonomy"

# ============================================================================
# Run Vernacular Assignment
# ============================================================================

system2(
  command = "/usr/bin/Rscript",
  args = c(file.path(script_dir, "assign_vernacular_names.R")),
  env = c(sprintf("R_LIBS_USER=%s", Sys.getenv("R_LIBS_USER")))
)

cat("\n")
cat(strrep("=", 80), "\n")
cat("PHASE 1 VERIFICATION\n")
cat(strrep("=", 80), "\n\n")

# ============================================================================
# Verify Output
# ============================================================================

cat("Running verification checks...\n\n")

verification_result <- system2(
  command = "/home/olier/miniconda3/envs/AI/bin/python",
  args = c(file.path(script_dir, "verify_phase1_output.py")),
  stdout = TRUE,
  stderr = TRUE
)

cat(paste(verification_result, collapse = "\n"))
cat("\n\n")

# Check if verification passed
verification_exit <- attr(verification_result, "status")
if (!is.null(verification_exit) && verification_exit != 0) {
  cat("❌ PHASE 1 VERIFICATION FAILED\n")
  cat("Please review errors above before proceeding to Phase 2.\n\n")
  quit(status = 1)
}

cat(strrep("=", 80), "\n")
cat("PHASE 1 COMPLETE\n")
cat(strrep("=", 80), "\n\n")

# ============================================================================
# Summary
# ============================================================================

cat("Output files:\n")
cat(sprintf("  %s/plants_vernacular_final.parquet\n", DATA_DIR))
cat(sprintf("  %s/organisms_vernacular_final.parquet\n", DATA_DIR))
cat(sprintf("  %s/all_taxa_vernacular_final.parquet\n", DATA_DIR))
cat("\n")

cat("NOTE: Animal categorization is provided by Phase 2 (Kimi AI pipeline)\n")
cat("      See: shipley_checks/src/Stage_4/taxonomy/phase2_kimi/run_phase2_pipeline.sh\n")
cat("\n")
