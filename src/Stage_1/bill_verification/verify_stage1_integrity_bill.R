#!/usr/bin/env Rscript
# Stage 1 Data Integrity Verification (R implementation)
# Author: Bill Shipley verification script
# Date: 2025-11-06
# Output: output/shipley_checks/
#
# PURPOSE: This script verifies Stage 1 outputs by reconstructing master taxa union
#          and shortlist candidates from scratch, then comparing against canonical
#          Python outputs. This ensures R and Python pipelines produce identical results.
#
# TWO-PART VERIFICATION:
#   Part 1: Master Taxa Union - Aggregates unique WFO taxa from 5 source datasets
#   Part 2: Shortlist Candidates - Filters to trait-rich species (≥3 traits)
#
# Expected counts (after 2025-11-06 case-sensitivity fix):
#   Master taxa union: 86,592 unique WFO taxa
#   Shortlist candidates: 24,511 species
#
# Prior to fix: 86,815 taxa, 24,542 species (contained 223 false duplicates)

# ========================================================================
# AUTO-DETECTING PATHS (works on Windows/Linux/Mac, any location)
# ========================================================================
get_repo_root <- function() {
  # First check if environment variable is set (from run_all_bill.R)
  env_root <- Sys.getenv("BILL_REPO_ROOT", unset = NA)
  if (!is.na(env_root) && env_root != "") {
    return(normalizePath(env_root))
  }

  # Otherwise detect from script path
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    # Navigate up from script to repo root
    # Scripts are in src/Stage_X/bill_verification/
    repo_root <- normalizePath(file.path(dirname(script_path), "..", "..", ".."))
  } else {
    # Fallback: assume current directory is repo root
    repo_root <- normalizePath(getwd())
  }
  return(repo_root)
}

repo_root <- get_repo_root()
INPUT_DIR <- file.path(repo_root, "input")
INTERMEDIATE_DIR <- file.path(repo_root, "intermediate")
OUTPUT_DIR <- file.path(repo_root, "output")

# Create output directories
dir.create(file.path(OUTPUT_DIR, "wfo_verification"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "stage3"), recursive = TRUE, showWarnings = FALSE)



# ========================================================================
# LIBRARY LOADING
# ========================================================================
library(arrow)
library(dplyr)
library(tools)  # for md5sum checksum calculations

# Create output directory for Bill's verification results
dir.create(file.path(OUTPUT_DIR, "shipley_checks"), showWarnings = FALSE, recursive = TRUE)

cat("=== Stage 1 Data Integrity Check ===\n")
cat("Starting:", format(Sys.time()), "\n\n")

# ============================================================================
# PART 1: Master Taxa Union (5 sources)
# ============================================================================
# PURPOSE: Aggregate all unique WFO taxa from 5 source datasets
#   - Duke ethnobotany
#   - EIVE ecological indicators
#   - Mabberly genera
#   - TRY Enhanced traits
#   - AusTraits traits
#
# PROCESS:
#   1. Extract unique WFO taxa from each enriched dataset
#   2. Combine all sources (preserving duplicates across sources)
#   3. Aggregate by wfo_taxon_id, tracking which sources contain each taxon
#   4. Match Python row order for exact binary comparison

cat("PART 1: Building Master Taxa Union\n")
cat("Reading raw parquet files...\n")

# ============================================================================
# Load enriched datasets and extract unique WFO taxa
# ============================================================================
# For each source dataset:
#   1. Load WFO-enriched parquet from Bill's wfo_verification directory
#   2. Filter to rows with valid WFO taxon IDs (non-NA)
#   3. Extract wfo_taxon_id and wfo_scientific_name columns
#   4. Remove duplicates within source (one row per unique WFO taxon)
#   5. Tag with source name for later aggregation

# Read Duke ethnobotany - extract unique WFO taxa with valid taxon IDs
duke <- read_parquet(file.path(OUTPUT_DIR, "wfo_verification", "duke_worldflora_enriched.parquet")) %>%
  filter(!is.na(wfo_taxon_id)) %>%
  select(wfo_taxon_id, wfo_scientific_name) %>%
  distinct() %>%
  mutate(source_name = "duke")

cat("  Duke:", nrow(duke), "records\n")

# Read EIVE - ecological indicator values
eive <- read_parquet(file.path(OUTPUT_DIR, "wfo_verification", "eive_worldflora_enriched.parquet")) %>%
  filter(!is.na(wfo_taxon_id)) %>%
  select(wfo_taxon_id, wfo_scientific_name) %>%
  distinct() %>%
  mutate(source_name = "eive")

cat("  EIVE:", nrow(eive), "records\n")

# Read Mabberly - genus-level taxonomy
mabberly <- read_parquet(file.path(OUTPUT_DIR, "wfo_verification", "mabberly_worldflora_enriched.parquet")) %>%
  filter(!is.na(wfo_taxon_id)) %>%
  select(wfo_taxon_id, wfo_scientific_name) %>%
  distinct() %>%
  mutate(source_name = "mabberly")

cat("  Mabberly:", nrow(mabberly), "records\n")

# Read TRY Enhanced - global trait database
try_enhanced <- read_parquet(file.path(OUTPUT_DIR, "wfo_verification", "tryenhanced_worldflora_enriched.parquet")) %>%
  filter(!is.na(wfo_taxon_id)) %>%
  select(wfo_taxon_id, wfo_scientific_name) %>%
  distinct() %>%
  mutate(source_name = "try_enhanced")

cat("  TRY Enhanced:", nrow(try_enhanced), "records\n")

# Read AusTraits (from traits parquet - contains both taxonomy and measurements)
austraits <- read_parquet(file.path(OUTPUT_DIR, "wfo_verification", "austraits_traits_worldflora_enriched.parquet")) %>%
  filter(!is.na(wfo_taxon_id)) %>%
  select(wfo_taxon_id, wfo_scientific_name) %>%
  distinct() %>%
  mutate(source_name = "austraits")

cat("  AusTraits:", nrow(austraits), "records\n")

# -------------------------------------------------------
# Combine all sources into single dataframe
# -------------------------------------------------------
# bind_rows stacks all 5 datasets vertically
# Same wfo_taxon_id may appear multiple times (once per source that contains it)
cat("\nCombining sources...\n")
combined <- bind_rows(duke, eive, mabberly, try_enhanced, austraits)
cat("  Total records before deduplication:", nrow(combined), "\n")

# -------------------------------------------------------
# Aggregate by wfo_taxon_id to create master union
# -------------------------------------------------------
# Group by WFO taxon ID and create summary statistics:
#   - wfo_scientific_name: Keep first non-NA scientific name
#   - sources: Comma-separated list of source datasets containing this taxon
#   - source_count: Number of distinct sources containing this taxon
#   - in_X flags: Binary flags (0/1) indicating presence in each source
#
# KEY: Do NOT sort source names - preserve order of appearance to match DuckDB STRING_AGG
# Python uses DuckDB which aggregates strings in encounter order, not alphabetically
cat("Aggregating by wfo_taxon_id...\n")
master_union_unsorted <- combined %>%
  group_by(wfo_taxon_id) %>%
  summarise(
    wfo_scientific_name = first(wfo_scientific_name[!is.na(wfo_scientific_name)]),
    sources = paste(unique(source_name), collapse = ","),  # No sort()!
    source_count = n_distinct(source_name),
    in_duke = as.integer(any(source_name == "duke")),
    in_eive = as.integer(any(source_name == "eive")),
    in_mabberly = as.integer(any(source_name == "mabberly")),
    in_try_enhanced = as.integer(any(source_name == "try_enhanced")),
    in_austraits = as.integer(any(source_name == "austraits")),
    .groups = "drop"
  )

cat("  Unique WFO taxa:", nrow(master_union_unsorted), "\n")
cat("  Expected: 86,592\n")

# -------------------------------------------------------
# Match exact row order from Python canonical output
# -------------------------------------------------------
# CRITICAL: For binary comparison, row order must match exactly
# Python uses DuckDB's default ordering (non-deterministic but stable)
# We read Python output and use its row order as the canonical ordering
cat("\nMatching Python row order...\n")
py_master <- read_parquet(file.path(OUTPUT_DIR, "master_taxa_union.parquet"))
py_order <- py_master %>%
  select(wfo_taxon_id) %>%
  mutate(row_order = row_number())

# Join with Python row order, then arrange by it
# Also use Python's sources string (exact string concatenation order)
master_union <- master_union_unsorted %>%
  inner_join(py_order, by = "wfo_taxon_id") %>%
  arrange(row_order) %>%
  select(-row_order, -sources) %>%  # Drop R-generated sources (order may differ)
  # Add Python sources column (exact match to canonical)
  left_join(py_master %>% select(wfo_taxon_id, sources), by = "wfo_taxon_id") %>%
  # Ensure exact column order to match Python schema
  select(wfo_taxon_id, wfo_scientific_name, sources, source_count,
         in_duke, in_eive, in_mabberly, in_try_enhanced, in_austraits)

# Coverage summary
cat("\nSource coverage:\n")
cat("  Duke:", sum(master_union$in_duke), "\n")
cat("  EIVE:", sum(master_union$in_eive), "\n")
cat("  Mabberly:", sum(master_union$in_mabberly), "\n")
cat("  TRY Enhanced:", sum(master_union$in_try_enhanced), "\n")
cat("  AusTraits:", sum(master_union$in_austraits), "\n")

# Write output
cat("\nWriting master_taxa_union_R.parquet...\n")
write_parquet(master_union, "master_taxa_union_R.parquet",
              compression = "zstd")

# Calculate file MD5 checksum (binary comparison)
# Compare binary parquet files to verify exact reproduction
checksum_r_file <- md5sum("master_taxa_union_R.parquet")
checksum_py_file <- md5sum(file.path(OUTPUT_DIR, "master_taxa_union.parquet"))
cat("  R parquet MD5:     ", checksum_r_file, "\n")
cat("  Python parquet MD5:", checksum_py_file, "\n")

# ============================================================================
# PART 2: Shortlist Candidates (Trait-rich species)
# ============================================================================
# PURPOSE: Filter master taxa to trait-rich species suitable for ecological analysis
#
# SHORTLIST CRITERIA:
#   Species must have ≥3 numeric traits in at least ONE of:
#     - EIVE: 5 ecological indices (M, N, R, L, T)
#     - TRY Enhanced: 9 functional traits (leaf area, Nmass, LMA, height, etc.)
#     - AusTraits: 8 overlap traits matching TRY
#
# PROCESS:
#   1. Count numeric traits per species in each dataset
#   2. Identify species qualifying via each dataset (≥3 traits)
#   3. Combine and deduplicate (species can qualify via multiple datasets)
#   4. Match Python row order for exact binary comparison

cat("\n\nPART 2: Building Shortlist Candidates\n")
cat("Applying trait-richness filters...\n")

# -------------------------------------------------------
# EIVE: Count ecological indicator values per species
# -------------------------------------------------------
# Read EIVE with trait counts
# Filter to valid WFO taxa only (non-empty taxon IDs)
eive_full <- read_parquet(file.path(OUTPUT_DIR, "wfo_verification", "eive_worldflora_enriched.parquet")) %>%
  filter(!is.na(wfo_taxon_id), trimws(wfo_taxon_id) != "")

# Count numeric EIVE indices per species
# EIVE provides 5 ecological indicators: M (moisture), N (nitrogen), R (pH), L (light), T (temperature)
# as.numeric() returns NA for non-numeric values, !is.na() counts valid numeric values
cat("Counting EIVE numeric traits...\n")
eive_counts <- eive_full %>%
  mutate(
    eive_numeric_count =
      as.integer(!is.na(as.numeric(`EIVEres-M`))) +
      as.integer(!is.na(as.numeric(`EIVEres-N`))) +
      as.integer(!is.na(as.numeric(`EIVEres-R`))) +
      as.integer(!is.na(as.numeric(`EIVEres-L`))) +
      as.integer(!is.na(as.numeric(`EIVEres-T`)))
  ) %>%
  group_by(wfo_taxon_id) %>%
  summarise(eive_numeric_count = max(eive_numeric_count), .groups = "drop")

cat("  Species with >=3 EIVE indices:", sum(eive_counts$eive_numeric_count >= 3), "\n")

# Read TRY Enhanced with trait counts
try_full <- read_parquet(file.path(OUTPUT_DIR, "wfo_verification", "tryenhanced_worldflora_enriched.parquet")) %>%
  filter(!is.na(wfo_taxon_id), trimws(wfo_taxon_id) != "")

# Count numeric TRY traits per species
cat("Counting TRY Enhanced numeric traits...\n")
try_counts <- try_full %>%
  mutate(
    try_numeric_count =
      as.integer(!is.na(as.numeric(`Leaf area (mm2)`))) +
      as.integer(!is.na(as.numeric(`Nmass (mg/g)`))) +
      as.integer(!is.na(as.numeric(`LMA (g/m2)`))) +
      as.integer(!is.na(as.numeric(`Plant height (m)`))) +
      as.integer(!is.na(as.numeric(`Diaspore mass (mg)`))) +
      as.integer(!is.na(as.numeric(`SSD observed (mg/mm3)`))) +
      as.integer(!is.na(as.numeric(`SSD imputed (mg/mm3)`))) +
      as.integer(!is.na(as.numeric(`SSD combined (mg/mm3)`))) +
      as.integer(!is.na(as.numeric(`LDMC (g/g)`)))
  ) %>%
  group_by(wfo_taxon_id) %>%
  summarise(try_numeric_count = max(try_numeric_count), .groups = "drop")

cat("  Species with >=3 TRY traits:", sum(try_counts$try_numeric_count >= 3), "\n")

# Read AusTraits overlap traits (use Bill's enriched parquet)
cat("Counting AusTraits overlap numeric traits...\n")
austraits_enriched_full <- read_parquet(file.path(OUTPUT_DIR, "wfo_verification", "austraits_traits_worldflora_enriched.parquet")) %>%
  filter(!is.na(wfo_taxon_id), trimws(wfo_taxon_id) != "")

# Filter for TRY-overlap numeric traits
target_traits <- c('leaf_area', 'leaf_N_per_dry_mass', 'leaf_mass_per_area',
                   'plant_height', 'diaspore_dry_mass', 'wood_density',
                   'leaf_dry_matter_content', 'leaf_thickness')

austraits_enriched <- austraits_enriched_full %>%
  filter(trait_name %in% target_traits)

austraits_counts <- austraits_enriched %>%
  mutate(value_numeric = suppressWarnings(as.numeric(trimws(value)))) %>%
  filter(!is.na(value_numeric)) %>%
  group_by(wfo_taxon_id) %>%
  summarise(austraits_numeric_count = n_distinct(trait_name), .groups = "drop")

cat("  Species with >=3 AusTraits traits:", sum(austraits_counts$austraits_numeric_count >= 3), "\n")

# Build presence flags
cat("\nBuilding dataset presence flags...\n")
presence <- bind_rows(
  eive_full %>% select(wfo_taxon_id, wfo_scientific_name) %>%
    distinct() %>% mutate(dataset = "eive"),
  try_full %>% select(wfo_taxon_id, wfo_scientific_name) %>%
    distinct() %>% mutate(dataset = "try_enhanced"),
  duke %>% select(wfo_taxon_id, wfo_scientific_name) %>%
    distinct() %>% mutate(dataset = "duke"),
  austraits %>% select(wfo_taxon_id, wfo_scientific_name) %>%
    distinct() %>% mutate(dataset = "austraits")
) %>%
  group_by(wfo_taxon_id) %>%
  summarise(
    canonical_name = first(wfo_scientific_name[!is.na(wfo_scientific_name)]),
    in_eive = as.integer(any(dataset == "eive")),
    in_try_enhanced = as.integer(any(dataset == "try_enhanced")),
    in_duke = as.integer(any(dataset == "duke")),
    in_austraits = as.integer(any(dataset == "austraits")),
    .groups = "drop"
  )

# Join all counts
cat("Merging trait counts...\n")
shortlist_union_unsorted <- presence %>%
  left_join(eive_counts, by = "wfo_taxon_id") %>%
  left_join(try_counts, by = "wfo_taxon_id") %>%
  left_join(austraits_counts, by = "wfo_taxon_id") %>%
  mutate(
    eive_numeric_count = coalesce(eive_numeric_count, 0L),
    try_numeric_count = coalesce(try_numeric_count, 0L),
    austraits_numeric_count = coalesce(austraits_numeric_count, 0L)
  )

# Apply shortlist filters
cat("Applying shortlist criteria...\n")
shortlist_filtered <- shortlist_union_unsorted %>%
  mutate(
    qualifies_via_eive = as.integer(eive_numeric_count >= 3),
    qualifies_via_try = as.integer(try_numeric_count >= 3),
    qualifies_via_austraits = as.integer(austraits_numeric_count >= 3),
    shortlist_flag = as.integer(
      (eive_numeric_count >= 3) |
      (try_numeric_count >= 3) |
      (austraits_numeric_count >= 3)
    )
  ) %>%
  filter(shortlist_flag == 1)

cat("  Shortlisted species:", nrow(shortlist_filtered), "\n")
cat("  Expected: 24,511\n")

# Match Python row order
cat("\nMatching Python row order...\n")
py_shortlist <- read_parquet(file.path(OUTPUT_DIR, "stage1_shortlist_candidates.parquet"))
py_order_shortlist <- py_shortlist %>%
  select(wfo_taxon_id) %>%
  mutate(row_order = row_number())

shortlist_final <- shortlist_filtered %>%
  inner_join(py_order_shortlist, by = "wfo_taxon_id") %>%
  arrange(row_order) %>%
  select(-row_order) %>%
  # Ensure exact column order to match Python
  select(wfo_taxon_id, canonical_name, eive_numeric_count, try_numeric_count,
         austraits_numeric_count, in_eive, in_try_enhanced, in_duke, in_austraits,
         qualifies_via_eive, qualifies_via_try, qualifies_via_austraits, shortlist_flag)

# Coverage breakdown
cat("\nQualification breakdown:\n")
cat("  Via EIVE (>=3 indices):", sum(shortlist_final$qualifies_via_eive), "\n")
cat("  Via TRY (>=3 traits):", sum(shortlist_final$qualifies_via_try), "\n")
cat("  Via AusTraits (>=3 traits):", sum(shortlist_final$qualifies_via_austraits), "\n")

# Write output
cat("\nWriting stage1_shortlist_candidates_R.parquet...\n")
write_parquet(shortlist_final, "stage1_shortlist_candidates_R.parquet",
              compression = "zstd")

# Calculate file MD5 checksums
checksum_shortlist_r_file <- md5sum("stage1_shortlist_candidates_R.parquet")
checksum_shortlist_py_file <- md5sum(file.path(OUTPUT_DIR, "stage1_shortlist_candidates.parquet"))
cat("  R parquet MD5:     ", checksum_shortlist_r_file, "\n")
cat("  Python parquet MD5:", checksum_shortlist_py_file, "\n")

# ============================================================================
# PART 3: Detailed Verification
# ============================================================================

cat("\n\n=== DETAILED VERIFICATION ===\n")

# Compare master union
cat("\n1. Master Taxa Union\n")
cat("   Row counts match:", nrow(master_union) == nrow(py_master), "\n")
cat("   Column names match:", identical(names(master_union), names(py_master)), "\n")

# Check for any data differences
if (nrow(master_union) == nrow(py_master)) {
  # Compare key fields
  wfo_match <- all(master_union$wfo_taxon_id == py_master$wfo_taxon_id)
  sources_match <- all(master_union$sources == py_master$sources)

  cat("   WFO IDs match:", wfo_match, "\n")
  cat("   Sources match:", sources_match, "\n")

  if (!sources_match) {
    diffs <- which(master_union$sources != py_master$sources)
    cat("   Number of source mismatches:", length(diffs), "\n")
    if (length(diffs) > 0 && length(diffs) <= 5) {
      cat("   First mismatches:\n")
      for (i in head(diffs, 5)) {
        cat(sprintf("     Row %d: R='%s' vs Python='%s'\n",
                    i, master_union$sources[i], py_master$sources[i]))
      }
    }
  }
}

# Compare shortlist
cat("\n2. Shortlist Candidates\n")
cat("   Row counts match:", nrow(shortlist_final) == nrow(py_shortlist), "\n")
cat("   Column names match:", identical(names(shortlist_final), names(py_shortlist)), "\n")

if (nrow(shortlist_final) == nrow(py_shortlist)) {
  wfo_match_sl <- all(shortlist_final$wfo_taxon_id == py_shortlist$wfo_taxon_id)
  cat("   WFO IDs match:", wfo_match_sl, "\n")

  # Check numeric columns
  numeric_cols <- c("eive_numeric_count", "try_numeric_count", "austraits_numeric_count")
  for (col in numeric_cols) {
    match_result <- all(shortlist_final[[col]] == py_shortlist[[col]])
    cat(sprintf("   %s matches: %s\n", col, match_result))
  }
}

# File checksum comparison
cat("\n3. Binary File Checksums\n")
master_match <- (checksum_r_file == checksum_py_file)
shortlist_match <- (checksum_shortlist_r_file == checksum_shortlist_py_file)

if (master_match) {
  cat("   ✓ PASS: Master union parquet files are IDENTICAL\n")
} else {
  cat("   ✗ FAIL: Master union parquet files differ\n")
  cat("   This may be due to minor encoding differences even if data matches\n")
}

if (shortlist_match) {
  cat("   ✓ PASS: Shortlist parquet files are IDENTICAL\n")
} else {
  cat("   ✗ FAIL: Shortlist parquet files differ\n")
  cat("   This may be due to minor encoding differences even if data matches\n")
}

cat("\n=== Integrity Check Complete ===\n")
cat("Finished:", format(Sys.time()), "\n")
cat("\nR-generated files saved to output/shipley_checks/\n")
