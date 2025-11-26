#!/usr/bin/env Rscript
#
# Verify Phase 7 data integrity
#
# Checks:
# 1. Flat parquets exist and have correct schema
# 2. No NULL values in key columns
# 3. Source columns match Phase 0 column names exactly
# 4. Row counts from flat format match counts from wide format
# 5. Sample plant verification: flat counts = wide counts
#

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

project_root <- "/home/olier/ellenberg"

cat("================================================================================\n")
cat("PHASE 7: DATA INTEGRITY VERIFICATION\n")
cat("================================================================================\n\n")

errors <- 0
warnings <- 0

# Helper function
check <- function(condition, msg_pass, msg_fail) {
  if (condition) {
    cat("PASS:", msg_pass, "\n")
  } else {
    cat("FAIL:", msg_fail, "\n")
    errors <<- errors + 1
  }
}

# ============================================================================
# 1. ORGANISMS FLAT
# ============================================================================

cat("--------------------------------------------------------------------------------\n")
cat("1. ORGANISMS FLAT VERIFICATION\n")
cat("--------------------------------------------------------------------------------\n\n")

organisms_flat_path <- file.path(project_root, "shipley_checks/stage4/phase7_output/organisms_flat.parquet")
organisms_wide_path <- file.path(project_root, "shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet")

check(file.exists(organisms_flat_path),
      "organisms_flat.parquet exists",
      "organisms_flat.parquet NOT FOUND")

if (file.exists(organisms_flat_path) && file.exists(organisms_wide_path)) {
  organisms_flat <- read_parquet(organisms_flat_path)
  organisms_wide <- read_parquet(organisms_wide_path)

  # Schema check
  expected_cols <- c("plant_wfo_id", "organism_taxon", "source_column")
  check(all(expected_cols %in% names(organisms_flat)),
        paste("Schema correct:", paste(names(organisms_flat), collapse = ", ")),
        paste("Missing columns:", paste(setdiff(expected_cols, names(organisms_flat)), collapse = ", ")))

  check(ncol(organisms_flat) == 3,
        "Exactly 3 columns (no spurious derived columns)",
        paste("Extra columns found:", ncol(organisms_flat)))

  # NULL checks
  check(sum(is.na(organisms_flat$plant_wfo_id)) == 0,
        "No NULL plant_wfo_id",
        paste("Found", sum(is.na(organisms_flat$plant_wfo_id)), "NULL plant_wfo_id"))

  check(sum(is.na(organisms_flat$organism_taxon)) == 0,
        "No NULL organism_taxon",
        paste("Found", sum(is.na(organisms_flat$organism_taxon)), "NULL organism_taxon"))

  # Source column validity
  valid_sources <- c("pollinators", "herbivores", "pathogens", "flower_visitors",
                     "predators_hasHost", "predators_interactsWith",
                     "predators_adjacentTo", "fungivores_eats")
  actual_sources <- unique(organisms_flat$source_column)
  check(all(actual_sources %in% valid_sources),
        paste("Source columns valid:", paste(actual_sources, collapse = ", ")),
        paste("Invalid source columns:", paste(setdiff(actual_sources, valid_sources), collapse = ", ")))

  # Count verification: sample 5 plants
  cat("\nSample plant count verification:\n")
  sample_plants <- head(unique(organisms_wide$plant_wfo_id), 5)

  for (plant_id in sample_plants) {
    # Wide format counts
    wide_row <- organisms_wide %>% filter(plant_wfo_id == plant_id)
    wide_poll <- wide_row$pollinator_count[1]
    wide_herb <- wide_row$herbivore_count[1]

    # Flat format counts
    flat_poll <- organisms_flat %>%
      filter(plant_wfo_id == plant_id, source_column == "pollinators") %>%
      nrow()
    flat_herb <- organisms_flat %>%
      filter(plant_wfo_id == plant_id, source_column == "herbivores") %>%
      nrow()

    poll_match <- is.na(wide_poll) || wide_poll == flat_poll
    herb_match <- is.na(wide_herb) || wide_herb == flat_herb

    if (poll_match && herb_match) {
      cat("  ", plant_id, ": pollinators", flat_poll, "herbivores", flat_herb, "OK\n")
    } else {
      cat("  ", plant_id, ": MISMATCH poll=", wide_poll, "vs", flat_poll,
          "herb=", wide_herb, "vs", flat_herb, "\n")
      errors <- errors + 1
    }
  }

  cat("\nOrganisms summary:\n")
  cat("  Total rows:", nrow(organisms_flat), "\n")
  cat("  Unique organisms:", length(unique(organisms_flat$organism_taxon)), "\n")
  cat("  Plants with data:", length(unique(organisms_flat$plant_wfo_id)), "\n")
}

# ============================================================================
# 2. FUNGI FLAT
# ============================================================================

cat("\n--------------------------------------------------------------------------------\n")
cat("2. FUNGI FLAT VERIFICATION\n")
cat("--------------------------------------------------------------------------------\n\n")

fungi_flat_path <- file.path(project_root, "shipley_checks/stage4/phase7_output/fungi_flat.parquet")
fungi_wide_path <- file.path(project_root, "shipley_checks/stage4/phase0_output/fungal_guilds_hybrid_11711.parquet")

check(file.exists(fungi_flat_path),
      "fungi_flat.parquet exists",
      "fungi_flat.parquet NOT FOUND")

if (file.exists(fungi_flat_path) && file.exists(fungi_wide_path)) {
  fungi_flat <- read_parquet(fungi_flat_path)
  fungi_wide <- read_parquet(fungi_wide_path)

  # Schema check
  expected_cols <- c("plant_wfo_id", "fungus_taxon", "source_column")
  check(all(expected_cols %in% names(fungi_flat)),
        paste("Schema correct:", paste(names(fungi_flat), collapse = ", ")),
        paste("Missing columns:", paste(setdiff(expected_cols, names(fungi_flat)), collapse = ", ")))

  check(ncol(fungi_flat) == 3,
        "Exactly 3 columns (no spurious derived columns)",
        paste("Extra columns found:", ncol(fungi_flat)))

  # NULL checks
  check(sum(is.na(fungi_flat$plant_wfo_id)) == 0,
        "No NULL plant_wfo_id",
        paste("Found", sum(is.na(fungi_flat$plant_wfo_id)), "NULL plant_wfo_id"))

  check(sum(is.na(fungi_flat$fungus_taxon)) == 0,
        "No NULL fungus_taxon",
        paste("Found", sum(is.na(fungi_flat$fungus_taxon)), "NULL fungus_taxon"))

  # Source column validity
  valid_sources <- c("pathogenic_fungi", "pathogenic_fungi_host_specific",
                     "amf_fungi", "emf_fungi", "mycoparasite_fungi",
                     "entomopathogenic_fungi", "endophytic_fungi", "saprotrophic_fungi")
  actual_sources <- unique(fungi_flat$source_column)
  check(all(actual_sources %in% valid_sources),
        paste("Source columns valid:", paste(actual_sources, collapse = ", ")),
        paste("Invalid source columns:", paste(setdiff(actual_sources, valid_sources), collapse = ", ")))

  # Count verification: sample 5 plants
  cat("\nSample plant count verification:\n")
  sample_plants <- head(unique(fungi_wide$plant_wfo_id), 5)

  for (plant_id in sample_plants) {
    # Wide format counts
    wide_row <- fungi_wide %>% filter(plant_wfo_id == plant_id)
    wide_amf <- wide_row$amf_fungi_count[1]
    wide_emf <- wide_row$emf_fungi_count[1]

    # Flat format counts
    flat_amf <- fungi_flat %>%
      filter(plant_wfo_id == plant_id, source_column == "amf_fungi") %>%
      nrow()
    flat_emf <- fungi_flat %>%
      filter(plant_wfo_id == plant_id, source_column == "emf_fungi") %>%
      nrow()

    amf_match <- is.na(wide_amf) || wide_amf == flat_amf
    emf_match <- is.na(wide_emf) || wide_emf == flat_emf

    if (amf_match && emf_match) {
      cat("  ", plant_id, ": amf", flat_amf, "emf", flat_emf, "OK\n")
    } else {
      cat("  ", plant_id, ": MISMATCH amf=", wide_amf, "vs", flat_amf,
          "emf=", wide_emf, "vs", flat_emf, "\n")
      errors <- errors + 1
    }
  }

  cat("\nFungi summary:\n")
  cat("  Total rows:", nrow(fungi_flat), "\n")
  cat("  Unique fungi:", length(unique(fungi_flat$fungus_taxon)), "\n")
  cat("  Plants with data:", length(unique(fungi_flat$plant_wfo_id)), "\n")
}

# ============================================================================
# 3. MASTER DATASET CHECK
# ============================================================================

cat("\n--------------------------------------------------------------------------------\n")
cat("3. MASTER DATASET ACCESSIBILITY\n")
cat("--------------------------------------------------------------------------------\n\n")

# Find master dataset
master_pattern <- file.path(project_root, "shipley_checks/stage3/bill_with_csr_ecoservices_11711_*.parquet")
master_files <- Sys.glob(master_pattern)

check(length(master_files) > 0,
      paste("Master dataset found:", basename(master_files[1])),
      "Master dataset NOT FOUND in stage3/")

if (length(master_files) > 0) {
  master <- read_parquet(master_files[1])
  cat("  Rows:", nrow(master), "\n")
  cat("  Columns:", ncol(master), "\n")

  # Check key columns exist
  key_cols <- c("wfo_taxon_id", "EIVEres-L_complete", "C", "S", "R")
  missing <- setdiff(key_cols, names(master))
  check(length(missing) == 0,
        "Key columns present (wfo_taxon_id, EIVEres-L_complete, C, S, R)",
        paste("Missing key columns:", paste(missing, collapse = ", ")))
}

# ============================================================================
# SUMMARY
# ============================================================================

cat("\n================================================================================\n")
cat("VERIFICATION SUMMARY\n")
cat("================================================================================\n\n")

if (errors == 0) {
  cat("ALL CHECKS PASSED\n\n")
  cat("Phase 7 data is ready for use.\n")
  quit(status = 0)
} else {
  cat("ERRORS:", errors, "\n\n")
  cat("Phase 7 data integrity check FAILED.\n")
  quit(status = 1)
}
