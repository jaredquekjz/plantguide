#!/usr/bin/env Rscript
# Stage 4 Verification: Plant Fungal Guilds
#
# Verifies structure, coverage, and data quality of fungal guild classifications
# using FungalTraits (primary) + FunGuild (fallback) hybrid approach.
#
# Expected output: shipley_checks/stage4/plant_fungal_guilds_hybrid_11711.parquet
#
# Usage: Rscript shipley_checks/src/Stage_4/verify_fungal_guilds_bill.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

cat("================================================================================\n")
cat("STAGE 4 VERIFICATION: Plant Fungal Guilds\n")
cat("================================================================================\n")
cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# File paths
GUILDS_FILE <- "shipley_checks/stage4/plant_fungal_guilds_hybrid_11711.parquet"
MAIN_DATASET <- "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet"
REPORT_FILE <- "shipley_checks/reports/verify_fungal_guilds_bill.txt"

# Ensure report directory exists
dir.create("shipley_checks/reports", showWarnings = FALSE, recursive = TRUE)

# Redirect output to both console and file
sink(REPORT_FILE, split = TRUE)

cat("================================================================================\n")
cat("STAGE 4 VERIFICATION: Plant Fungal Guilds\n")
cat("================================================================================\n")
cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Initialize results
all_checks_pass <- TRUE
failed_checks <- c()

# Test 1: File exists
cat("Test 1: File Existence\n")
cat("  Checking:", GUILDS_FILE, "\n")
if (!file.exists(GUILDS_FILE)) {
  cat("  ❌ FAIL: File does not exist\n\n")
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "File existence")
  sink()
  quit(status = 1)
} else {
  file_size <- file.size(GUILDS_FILE) / 1024 / 1024
  cat(sprintf("  ✓ PASS: File exists (%.2f MB)\n\n", file_size))
}

# Load data
cat("Loading fungal guilds...\n")
guilds <- read_parquet(GUILDS_FILE)
cat(sprintf("  - Loaded %s rows\n\n", format(nrow(guilds), big.mark = ",")))

# Test 2: Row count
cat("Test 2: Row Count\n")
cat("  Expected: 11,711 plants\n")
cat(sprintf("  Actual: %s plants\n", format(nrow(guilds), big.mark = ",")))
if (nrow(guilds) != 11711) {
  cat(sprintf("  ❌ FAIL: Expected 11,711 rows, got %d\n\n", nrow(guilds)))
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "Row count")
} else {
  cat("  ✓ PASS\n\n")
}

# Test 3: Column structure
cat("Test 3: Column Structure\n")
expected_cols <- c(
  "plant_wfo_id", "wfo_scientific_name", "family", "genus",
  "pathogenic_fungi", "pathogenic_fungi_count",
  "pathogenic_fungi_host_specific", "pathogenic_fungi_host_specific_count",
  "amf_fungi", "amf_fungi_count",
  "emf_fungi", "emf_fungi_count",
  "mycorrhizae_total_count",
  "mycoparasite_fungi", "mycoparasite_fungi_count",
  "entomopathogenic_fungi", "entomopathogenic_fungi_count",
  "biocontrol_total_count",
  "endophytic_fungi", "endophytic_fungi_count",
  "saprotrophic_fungi", "saprotrophic_fungi_count",
  "trichoderma_count", "beauveria_metarhizium_count",
  "fungaltraits_genera", "funguild_genera"
)

actual_cols <- colnames(guilds)
missing_cols <- setdiff(expected_cols, actual_cols)
extra_cols <- setdiff(actual_cols, expected_cols)

if (length(missing_cols) > 0) {
  cat("  ❌ FAIL: Missing columns:", paste(missing_cols, collapse = ", "), "\n")
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "Missing columns")
} else {
  cat("  ✓ PASS: All expected columns present\n")
}

if (length(extra_cols) > 0) {
  cat("  ⚠️  WARNING: Extra columns found:", paste(extra_cols, collapse = ", "), "\n")
}
cat("\n")

# Test 4: Count columns match list lengths
cat("Test 4: Count Columns Match List Lengths\n")

check_list_count <- function(df, list_col, count_col) {
  mismatches <- df %>%
    mutate(
      list_len = sapply(.data[[list_col]], length),
      matches = (.data[[count_col]] == list_len)
    ) %>%
    filter(!matches) %>%
    nrow()

  return(mismatches)
}

list_count_checks <- list(
  pathogenic_fungi = check_list_count(guilds, "pathogenic_fungi", "pathogenic_fungi_count"),
  pathogenic_fungi_host_specific = check_list_count(guilds, "pathogenic_fungi_host_specific",
                                                     "pathogenic_fungi_host_specific_count"),
  amf_fungi = check_list_count(guilds, "amf_fungi", "amf_fungi_count"),
  emf_fungi = check_list_count(guilds, "emf_fungi", "emf_fungi_count"),
  mycoparasite_fungi = check_list_count(guilds, "mycoparasite_fungi", "mycoparasite_fungi_count"),
  entomopathogenic_fungi = check_list_count(guilds, "entomopathogenic_fungi", "entomopathogenic_fungi_count"),
  endophytic_fungi = check_list_count(guilds, "endophytic_fungi", "endophytic_fungi_count"),
  saprotrophic_fungi = check_list_count(guilds, "saprotrophic_fungi", "saprotrophic_fungi_count")
)

all_match <- TRUE
for (field in names(list_count_checks)) {
  mismatches <- list_count_checks[[field]]
  if (mismatches > 0) {
    cat(sprintf("  ❌ FAIL: %s has %d mismatches\n", field, mismatches))
    all_checks_pass <- FALSE
    all_match <- FALSE
  }
}

if (all_match) {
  cat("  ✓ PASS: All count columns match their list lengths\n")
} else {
  failed_checks <- c(failed_checks, "List/count mismatches")
}
cat("\n")

# Test 5: Mycorrhizae and biocontrol totals are correct
cat("Test 5: Aggregate Count Columns\n")

# Check mycorrhizae_total_count = amf_fungi_count + emf_fungi_count
myc_mismatches <- guilds %>%
  mutate(
    expected_total = amf_fungi_count + emf_fungi_count,
    matches = (mycorrhizae_total_count == expected_total)
  ) %>%
  filter(!matches) %>%
  nrow()

# Check biocontrol_total_count = mycoparasite_fungi_count + entomopathogenic_fungi_count
bio_mismatches <- guilds %>%
  mutate(
    expected_total = mycoparasite_fungi_count + entomopathogenic_fungi_count,
    matches = (biocontrol_total_count == expected_total)
  ) %>%
  filter(!matches) %>%
  nrow()

if (myc_mismatches > 0) {
  cat(sprintf("  ❌ FAIL: mycorrhizae_total_count has %d mismatches\n", myc_mismatches))
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "Mycorrhizae total count")
}

if (bio_mismatches > 0) {
  cat(sprintf("  ❌ FAIL: biocontrol_total_count has %d mismatches\n", bio_mismatches))
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "Biocontrol total count")
}

if (myc_mismatches == 0 && bio_mismatches == 0) {
  cat("  ✓ PASS: All aggregate count columns are correct\n")
}
cat("\n")

# Test 6: Guild coverage statistics
cat("Test 6: Guild Coverage Statistics\n")
stats <- guilds %>%
  summarize(
    total = n(),
    with_pathogenic = sum(pathogenic_fungi_count > 0),
    with_mycorrhizal = sum(mycorrhizae_total_count > 0),
    with_biocontrol = sum(biocontrol_total_count > 0),
    with_endophytic = sum(endophytic_fungi_count > 0),
    with_saprotrophic = sum(saprotrophic_fungi_count > 0),
    pct_pathogenic = 100 * with_pathogenic / total,
    pct_mycorrhizal = 100 * with_mycorrhizal / total,
    pct_biocontrol = 100 * with_biocontrol / total,
    pct_endophytic = 100 * with_endophytic / total,
    pct_saprotrophic = 100 * with_saprotrophic / total
  )

cat(sprintf("  Pathogenic: %s (%.1f%%)\n",
            format(stats$with_pathogenic, big.mark = ","), stats$pct_pathogenic))
cat(sprintf("  Mycorrhizal: %s (%.1f%%)\n",
            format(stats$with_mycorrhizal, big.mark = ","), stats$pct_mycorrhizal))
cat(sprintf("  Biocontrol: %s (%.1f%%)\n",
            format(stats$with_biocontrol, big.mark = ","), stats$pct_biocontrol))
cat(sprintf("  Endophytic: %s (%.1f%%)\n",
            format(stats$with_endophytic, big.mark = ","), stats$pct_endophytic))
cat(sprintf("  Saprotrophic: %s (%.1f%%)\n",
            format(stats$with_saprotrophic, big.mark = ","), stats$pct_saprotrophic))

# Expected ranges (from Python output, allowing ±2%)
expected_ranges <- list(
  pathogenic = c(59.6, 63.6),
  mycorrhizal = c(1.9, 5.9),
  biocontrol = c(3.0, 7.0),
  endophytic = c(14.5, 18.5),
  saprotrophic = c(39.1, 43.1)
)

coverage_ok <- TRUE
check_coverage <- function(actual, expected, name) {
  if (actual < expected[1] || actual > expected[2]) {
    cat(sprintf("  ⚠️  WARNING: %s coverage (%.1f%%) outside expected range (%.1f%%-%.1f%%)\n",
                name, actual, expected[1], expected[2]))
    return(FALSE)
  }
  return(TRUE)
}

coverage_ok <- coverage_ok && check_coverage(stats$pct_pathogenic, expected_ranges$pathogenic, "Pathogenic")
coverage_ok <- coverage_ok && check_coverage(stats$pct_mycorrhizal, expected_ranges$mycorrhizal, "Mycorrhizal")
coverage_ok <- coverage_ok && check_coverage(stats$pct_biocontrol, expected_ranges$biocontrol, "Biocontrol")
coverage_ok <- coverage_ok && check_coverage(stats$pct_endophytic, expected_ranges$endophytic, "Endophytic")
coverage_ok <- coverage_ok && check_coverage(stats$pct_saprotrophic, expected_ranges$saprotrophic, "Saprotrophic")

if (coverage_ok) {
  cat("  ✓ PASS: All guild coverage statistics within expected ranges\n")
} else {
  cat("  ⚠️  Some coverage values outside expected ranges (not critical)\n")
}
cat("\n")

# Test 7: Host-specific subset relationship
cat("Test 7: Host-Specific Pathogens Are Subset\n")
cat("  Checking that host-specific pathogens ⊆ pathogenic fungi...\n")

subset_violations <- guilds %>%
  rowwise() %>%
  mutate(
    all_host_specific_in_pathogenic = all(pathogenic_fungi_host_specific %in% pathogenic_fungi)
  ) %>%
  ungroup() %>%
  filter(!all_host_specific_in_pathogenic) %>%
  nrow()

if (subset_violations > 0) {
  cat(sprintf("  ❌ FAIL: %d plants have host-specific fungi not in pathogenic fungi\n", subset_violations))
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "Host-specific subset violation")
} else {
  cat("  ✓ PASS: All host-specific pathogens are subset of pathogenic fungi\n")
}
cat("\n")

# Test 8: Data source tracking
cat("Test 8: Data Source Tracking\n")
source_stats <- guilds %>%
  summarize(
    total_ft_genera = sum(fungaltraits_genera),
    total_fg_genera = sum(funguild_genera),
    fg_contribution = 100 * total_fg_genera / (total_ft_genera + total_fg_genera)
  )

cat(sprintf("  FungalTraits genera: %s\n", format(source_stats$total_ft_genera, big.mark = ",")))
cat(sprintf("  FunGuild genera: %s\n", format(source_stats$total_fg_genera, big.mark = ",")))
cat(sprintf("  FunGuild contribution: %.1f%%\n", source_stats$fg_contribution))

if (source_stats$fg_contribution > 10.0) {
  cat("  ⚠️  WARNING: FunGuild contribution >10% (expected <5%)\n")
  cat("  (FunGuild is fallback only, FungalTraits should dominate)\n")
} else {
  cat("  ✓ PASS: FungalTraits is primary source as expected\n")
}
cat("\n")

# Test 9: All fungi at genus level
cat("Test 9: All Fungi at Genus Level (Sample Check)\n")
cat("  Checking first 100 plants for species-level names...\n")

check_genus_level <- function(fungi_list) {
  if (length(fungi_list) == 0) return(0)
  # Species names contain space (e.g., "Genus species")
  sum(grepl(" ", fungi_list))
}

sample_species_level <- guilds %>%
  head(100) %>%
  rowwise() %>%
  mutate(
    species_level_count = sum(
      check_genus_level(pathogenic_fungi),
      check_genus_level(amf_fungi),
      check_genus_level(emf_fungi),
      check_genus_level(mycoparasite_fungi),
      check_genus_level(entomopathogenic_fungi),
      check_genus_level(endophytic_fungi),
      check_genus_level(saprotrophic_fungi)
    )
  ) %>%
  ungroup() %>%
  summarize(total_species_level = sum(species_level_count))

if (sample_species_level$total_species_level > 10) {
  cat(sprintf("  ⚠️  WARNING: Found %d species-level names in sample (expected genus-level only)\n",
              sample_species_level$total_species_level))
} else {
  cat("  ✓ PASS: Fungi appear to be at genus level\n")
}
cat("\n")

# Test 10: Cross-reference with main dataset
cat("Test 10: Cross-Reference with Main Dataset\n")
cat("  Loading main dataset...\n")
main_dataset <- read_parquet(MAIN_DATASET)
cat(sprintf("  - Main dataset has %s plants\n", format(nrow(main_dataset), big.mark = ",")))

# Check all guild plant IDs exist in main dataset
guild_ids <- unique(guilds$plant_wfo_id)
main_ids <- unique(main_dataset$wfo_taxon_id)

missing_in_main <- setdiff(guild_ids, main_ids)
if (length(missing_in_main) > 0) {
  cat(sprintf("  ❌ FAIL: %d plant IDs in guilds not found in main dataset\n", length(missing_in_main)))
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "Plant IDs not in main dataset")
} else {
  cat("  ✓ PASS: All plant IDs exist in main dataset\n")
}
cat("\n")

# Test 11: Sample data inspection
cat("Test 11: Sample Data Inspection\n")
cat("  Top 5 plants by total fungal diversity:\n")
sample_plants <- guilds %>%
  mutate(
    total_fungi = pathogenic_fungi_count + mycorrhizae_total_count +
                  biocontrol_total_count + endophytic_fungi_count + saprotrophic_fungi_count
  ) %>%
  arrange(desc(total_fungi)) %>%
  head(5) %>%
  select(wfo_scientific_name, pathogenic_fungi_count, mycorrhizae_total_count,
         biocontrol_total_count, endophytic_fungi_count, saprotrophic_fungi_count, total_fungi)

print(sample_plants, row.names = FALSE)
cat("\n")

# Final summary
cat("================================================================================\n")
cat("VERIFICATION SUMMARY\n")
cat("================================================================================\n\n")

if (all_checks_pass) {
  cat("✓ ALL TESTS PASSED\n\n")
  cat("Summary:\n")
  cat(sprintf("  - Total plants: %s\n", format(nrow(guilds), big.mark = ",")))
  cat(sprintf("  - Pathogenic fungi: %s plants (%.1f%%)\n",
              format(stats$with_pathogenic, big.mark = ","), stats$pct_pathogenic))
  cat(sprintf("  - Mycorrhizal fungi: %s plants (%.1f%%)\n",
              format(stats$with_mycorrhizal, big.mark = ","), stats$pct_mycorrhizal))
  cat(sprintf("  - Biocontrol fungi: %s plants (%.1f%%)\n",
              format(stats$with_biocontrol, big.mark = ","), stats$pct_biocontrol))
  cat(sprintf("  - FungalTraits genera: %s\n", format(source_stats$total_ft_genera, big.mark = ",")))
  cat(sprintf("  - FunGuild genera (fallback): %s (%.1f%%)\n",
              format(source_stats$total_fg_genera, big.mark = ","), source_stats$fg_contribution))
  cat("\n✓ Dataset is ready for guild calibration\n\n")
} else {
  cat("❌ SOME TESTS FAILED\n\n")
  cat("Failed checks:\n")
  for (check in failed_checks) {
    cat(sprintf("  - %s\n", check))
  }
  cat("\n⚠️  Please review failures before proceeding\n\n")
}

cat("================================================================================\n")
cat("Completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Report saved to:", REPORT_FILE, "\n")
cat("================================================================================\n")

sink()

# Exit with appropriate status code
if (all_checks_pass) {
  quit(status = 0)
} else {
  quit(status = 1)
}
