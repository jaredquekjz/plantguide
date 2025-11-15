#!/usr/bin/env Rscript
#' Complete Taxonomic Vernacular Pipeline
#'
#' Orchestrates the complete end-to-end pipeline:
#' 1. Initial assignment (P1 iNat species + P3 ITIS family)
#' 2. Derive categories from species vernaculars (P2 genus + P4 family)
#' 3. Final assignment with all priority levels (P1-P4)
#'
#' Author: Claude Code
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(arrow)
})

cat(strrep("=", 80), "\n")
cat("TAXONOMIC VERNACULAR CATEGORIZATION - COMPLETE PIPELINE\n")
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
# STEP 1: Initial Assignment (P1 + P3)
# ============================================================================

cat("STEP 1: Initial vernacular assignment (P1 iNat + P3 ITIS)\n")
cat(strrep("-", 80), "\n\n")

system2(
  command = "/usr/bin/Rscript",
  args = c(file.path(script_dir, "assign_vernacular_names.R")),
  env = c(sprintf("R_LIBS_USER=%s", Sys.getenv("R_LIBS_USER")))
)

cat("\n")
cat("✓ Step 1 complete\n\n")

# ============================================================================
# STEP 2: Derive Categories
# ============================================================================

cat(strrep("=", 80), "\n")
cat("STEP 2: Derive genus and family categories\n")
cat(strrep("=", 80), "\n\n")

combinations <- expand.grid(
  organism_type = c("animal", "plant"),
  level = c("genus", "family"),
  stringsAsFactors = FALSE
)

for (i in seq_len(nrow(combinations))) {
  org_type <- combinations$organism_type[i]
  level <- combinations$level[i]

  cat(sprintf("Deriving %s %s categories...\n", org_type, level))

  system2(
    command = "/usr/bin/Rscript",
    args = c(
      file.path(script_dir, "derive_all_vernaculars.R"),
      "--organism-type", org_type,
      "--level", level,
      "--data-dir", DATA_DIR
    ),
    env = c(sprintf("R_LIBS_USER=%s", Sys.getenv("R_LIBS_USER")))
  )

  cat("\n")
}

cat("✓ Step 2 complete\n\n")

# ============================================================================
# STEP 3: Final Assignment (P1-P4)
# ============================================================================

cat(strrep("=", 80), "\n")
cat("STEP 3: Final vernacular assignment (all priority levels)\n")
cat(strrep("=", 80), "\n\n")

system2(
  command = "/usr/bin/Rscript",
  args = c(file.path(script_dir, "assign_vernacular_names.R")),
  env = c(sprintf("R_LIBS_USER=%s", Sys.getenv("R_LIBS_USER")))
)

cat("\n")
cat(strrep("=", 80), "\n")
cat("PIPELINE COMPLETE\n")
cat(strrep("=", 80), "\n\n")

# ============================================================================
# Summary
# ============================================================================

cat("Output files:\n")
cat(sprintf("  %s/plants_vernacular_final.parquet\n", DATA_DIR))
cat(sprintf("  %s/organisms_vernacular_final.parquet\n", DATA_DIR))
cat(sprintf("  %s/all_taxa_vernacular_final.parquet\n", DATA_DIR))
cat("\n")

cat("Derived categories:\n")
cat(sprintf("  %s/animal_genus_vernaculars_derived.parquet\n", DATA_DIR))
cat(sprintf("  %s/animal_family_vernaculars_derived.parquet\n", DATA_DIR))
cat(sprintf("  %s/plant_genus_vernaculars_derived.parquet\n", DATA_DIR))
cat(sprintf("  %s/plant_family_vernaculars_derived.parquet\n", DATA_DIR))
cat("\n")
