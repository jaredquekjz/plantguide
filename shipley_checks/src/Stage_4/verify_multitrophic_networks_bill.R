#!/usr/bin/env Rscript
# Stage 4 Verification: Multitrophic Networks
#
# Verifies structure, coverage, and data quality of three multitrophic
# network datasets used for biocontrol calculations.
#
# Expected outputs:
#   - shipley_checks/stage4/herbivore_predators_11711.parquet
#   - shipley_checks/stage4/pathogen_antagonists_11711.parquet
#   - shipley_checks/stage4/insect_fungal_parasites_11711.parquet
#
# Usage: Rscript shipley_checks/src/Stage_4/verify_multitrophic_networks_bill.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

cat("================================================================================\n")
cat("STAGE 4 VERIFICATION: Multitrophic Networks\n")
cat("================================================================================\n")
cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# File paths
HERB_PRED_FILE <- "shipley_checks/stage4/herbivore_predators_11711.parquet"
PATH_ANT_FILE <- "shipley_checks/stage4/pathogen_antagonists_11711.parquet"
INSECT_FUNG_FILE <- "shipley_checks/stage4/insect_fungal_parasites_11711.parquet"
ORGANISM_PROFILES <- "shipley_checks/stage4/plant_organism_profiles_11711.parquet"
REPORT_FILE <- "shipley_checks/reports/verify_multitrophic_networks_bill.txt"

# Ensure report directory exists
dir.create("shipley_checks/reports", showWarnings = FALSE, recursive = TRUE)

# Redirect output to both console and file
sink(REPORT_FILE, split = TRUE)

cat("================================================================================\n")
cat("STAGE 4 VERIFICATION: Multitrophic Networks\n")
cat("================================================================================\n")
cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Initialize results
all_checks_pass <- TRUE
failed_checks <- c()

# ================================================================================
# PART 1: HERBIVORE-PREDATOR NETWORK
# ================================================================================

cat("================================================================================\n")
cat("PART 1: HERBIVORE-PREDATOR NETWORK\n")
cat("================================================================================\n\n")

# Test 1.1: File exists
cat("Test 1.1: File Existence\n")
cat("  Checking:", HERB_PRED_FILE, "\n")
if (!file.exists(HERB_PRED_FILE)) {
  cat("  ❌ FAIL: File does not exist\n\n")
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "Herbivore-predator file existence")
} else {
  file_size <- file.size(HERB_PRED_FILE) / 1024
  cat(sprintf("  ✓ PASS: File exists (%.1f KB)\n\n", file_size))
}

if (file.exists(HERB_PRED_FILE)) {
  # Load data
  cat("Loading herbivore-predator network...\n")
  herb_pred <- read_parquet(HERB_PRED_FILE)
  cat(sprintf("  - Loaded %s herbivore species\n\n", format(nrow(herb_pred), big.mark = ",")))

  # Test 1.2: Column structure
  cat("Test 1.2: Column Structure\n")
  expected_cols <- c("herbivore", "predators", "predator_count")
  actual_cols <- colnames(herb_pred)
  missing_cols <- setdiff(expected_cols, actual_cols)

  if (length(missing_cols) > 0) {
    cat("  ❌ FAIL: Missing columns:", paste(missing_cols, collapse = ", "), "\n\n")
    all_checks_pass <- FALSE
    failed_checks <- c(failed_checks, "Herbivore-predator missing columns")
  } else {
    cat("  ✓ PASS: All expected columns present\n\n")
  }

  # Test 1.3: Count matches list length
  cat("Test 1.3: Predator Count Matches List Length\n")
  mismatches <- herb_pred %>%
    mutate(
      list_len = sapply(predators, length),
      matches = (predator_count == list_len)
    ) %>%
    filter(!matches) %>%
    nrow()

  if (mismatches > 0) {
    cat(sprintf("  ❌ FAIL: %d mismatches between predator_count and list length\n\n", mismatches))
    all_checks_pass <- FALSE
    failed_checks <- c(failed_checks, "Herbivore-predator count mismatches")
  } else {
    cat("  ✓ PASS: All counts match list lengths\n\n")
  }

  # Test 1.4: Coverage statistics
  cat("Test 1.4: Coverage Statistics\n")
  herb_stats <- herb_pred %>%
    summarize(
      total_herbivores = n(),
      total_predators = sum(predator_count),
      avg_predators = mean(predator_count),
      median_predators = median(predator_count),
      max_predators = max(predator_count)
    )

  cat(sprintf("  Total herbivores: %s\n", format(herb_stats$total_herbivores, big.mark = ",")))
  cat(sprintf("  Total predator relationships: %s\n", format(herb_stats$total_predators, big.mark = ",")))
  cat(sprintf("  Avg predators per herbivore: %.1f\n", herb_stats$avg_predators))
  cat(sprintf("  Median: %.0f, Max: %d\n\n", herb_stats$median_predators, herb_stats$max_predators))

  # Expected: 934 herbivores, ~14,282 relationships, ~15.3 avg
  if (herb_stats$total_herbivores < 900 || herb_stats$total_herbivores > 1000) {
    cat(sprintf("  ⚠️  WARNING: Herbivore count (%d) outside expected range (900-1000)\n",
                herb_stats$total_herbivores))
  }

  if (herb_stats$avg_predators < 10 || herb_stats$avg_predators > 20) {
    cat(sprintf("  ⚠️  WARNING: Average predators per herbivore (%.1f) outside expected range (10-20)\n",
                herb_stats$avg_predators))
  } else {
    cat("  ✓ PASS: Coverage statistics look reasonable\n\n")
  }
}

# ================================================================================
# PART 2: PATHOGEN-ANTAGONIST NETWORK
# ================================================================================

cat("================================================================================\n")
cat("PART 2: PATHOGEN-ANTAGONIST NETWORK\n")
cat("================================================================================\n\n")

# Test 2.1: File exists
cat("Test 2.1: File Existence\n")
cat("  Checking:", PATH_ANT_FILE, "\n")
if (!file.exists(PATH_ANT_FILE)) {
  cat("  ❌ FAIL: File does not exist\n\n")
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "Pathogen-antagonist file existence")
} else {
  file_size <- file.size(PATH_ANT_FILE) / 1024
  cat(sprintf("  ✓ PASS: File exists (%.1f KB)\n\n", file_size))
}

if (file.exists(PATH_ANT_FILE)) {
  # Load data
  cat("Loading pathogen-antagonist network...\n")
  path_ant <- read_parquet(PATH_ANT_FILE)
  cat(sprintf("  - Loaded %s pathogen species\n\n", format(nrow(path_ant), big.mark = ",")))

  # Test 2.2: Column structure
  cat("Test 2.2: Column Structure\n")
  expected_cols <- c("pathogen", "antagonists", "antagonist_count")
  actual_cols <- colnames(path_ant)
  missing_cols <- setdiff(expected_cols, actual_cols)

  if (length(missing_cols) > 0) {
    cat("  ❌ FAIL: Missing columns:", paste(missing_cols, collapse = ", "), "\n\n")
    all_checks_pass <- FALSE
    failed_checks <- c(failed_checks, "Pathogen-antagonist missing columns")
  } else {
    cat("  ✓ PASS: All expected columns present\n\n")
  }

  # Test 2.3: Count matches list length
  cat("Test 2.3: Antagonist Count Matches List Length\n")
  mismatches <- path_ant %>%
    mutate(
      list_len = sapply(antagonists, length),
      matches = (antagonist_count == list_len)
    ) %>%
    filter(!matches) %>%
    nrow()

  if (mismatches > 0) {
    cat(sprintf("  ❌ FAIL: %d mismatches between antagonist_count and list length\n\n", mismatches))
    all_checks_pass <- FALSE
    failed_checks <- c(failed_checks, "Pathogen-antagonist count mismatches")
  } else {
    cat("  ✓ PASS: All counts match list lengths\n\n")
  }

  # Test 2.4: Coverage statistics
  cat("Test 2.4: Coverage Statistics\n")
  path_stats <- path_ant %>%
    summarize(
      total_pathogens = n(),
      total_antagonists = sum(antagonist_count),
      avg_antagonists = mean(antagonist_count),
      median_antagonists = median(antagonist_count),
      max_antagonists = max(antagonist_count)
    )

  cat(sprintf("  Total pathogens: %s\n", format(path_stats$total_pathogens, big.mark = ",")))
  cat(sprintf("  Total antagonist relationships: %s\n", format(path_stats$total_antagonists, big.mark = ",")))
  cat(sprintf("  Avg antagonists per pathogen: %.1f\n", path_stats$avg_antagonists))
  cat(sprintf("  Median: %.0f, Max: %d\n\n", path_stats$median_antagonists, path_stats$max_antagonists))

  # Expected: 942 pathogens, ~5,873 relationships, ~6.2 avg
  if (path_stats$total_pathogens < 900 || path_stats$total_pathogens > 1000) {
    cat(sprintf("  ⚠️  WARNING: Pathogen count (%d) outside expected range (900-1000)\n",
                path_stats$total_pathogens))
  }

  if (path_stats$avg_antagonists < 4 || path_stats$avg_antagonists > 10) {
    cat(sprintf("  ⚠️  WARNING: Average antagonists per pathogen (%.1f) outside expected range (4-10)\n",
                path_stats$avg_antagonists))
  } else {
    cat("  ✓ PASS: Coverage statistics look reasonable\n\n")
  }

  # Test 2.5: Known data quality issue (inverted relationships)
  cat("Test 2.5: Known Data Quality Issue\n")
  cat("  ⚠️  DOCUMENTED ISSUE: Pathogen-antagonist relationships inverted in ~95%% of data\n")
  cat("  This is a known GloBI data quality issue documented in 4.3b_Data_Extraction_Verification.md\n")
  cat("  Relationships are still used but interpreted with caution in scoring.\n\n")
}

# ================================================================================
# PART 3: INSECT-FUNGAL PARASITE NETWORK
# ================================================================================

cat("================================================================================\n")
cat("PART 3: INSECT-FUNGAL PARASITE NETWORK\n")
cat("================================================================================\n\n")

# Test 3.1: File exists
cat("Test 3.1: File Existence\n")
cat("  Checking:", INSECT_FUNG_FILE, "\n")
if (!file.exists(INSECT_FUNG_FILE)) {
  cat("  ❌ FAIL: File does not exist\n\n")
  all_checks_pass <- FALSE
  failed_checks <- c(failed_checks, "Insect-fungal file existence")
} else {
  file_size <- file.size(INSECT_FUNG_FILE) / 1024
  cat(sprintf("  ✓ PASS: File exists (%.1f KB)\n\n", file_size))
}

if (file.exists(INSECT_FUNG_FILE)) {
  # Load data
  cat("Loading insect-fungal parasite network...\n")
  insect_fung <- read_parquet(INSECT_FUNG_FILE)
  cat(sprintf("  - Loaded %s insect/mite species\n\n", format(nrow(insect_fung), big.mark = ",")))

  # Test 3.2: Column structure
  cat("Test 3.2: Column Structure\n")
  expected_cols <- c("herbivore", "herbivore_family", "herbivore_order", "herbivore_class",
                     "entomopathogenic_fungi", "fungal_parasite_count")
  actual_cols <- colnames(insect_fung)
  missing_cols <- setdiff(expected_cols, actual_cols)

  if (length(missing_cols) > 0) {
    cat("  ❌ FAIL: Missing columns:", paste(missing_cols, collapse = ", "), "\n\n")
    all_checks_pass <- FALSE
    failed_checks <- c(failed_checks, "Insect-fungal missing columns")
  } else {
    cat("  ✓ PASS: All expected columns present\n\n")
  }

  # Test 3.3: Count matches list length
  cat("Test 3.3: Fungal Parasite Count Matches List Length\n")
  mismatches <- insect_fung %>%
    mutate(
      list_len = sapply(entomopathogenic_fungi, length),
      matches = (fungal_parasite_count == list_len)
    ) %>%
    filter(!matches) %>%
    nrow()

  if (mismatches > 0) {
    cat(sprintf("  ❌ FAIL: %d mismatches between fungal_parasite_count and list length\n\n", mismatches))
    all_checks_pass <- FALSE
    failed_checks <- c(failed_checks, "Insect-fungal count mismatches")
  } else {
    cat("  ✓ PASS: All counts match list lengths\n\n")
  }

  # Test 3.4: Coverage statistics
  cat("Test 3.4: Coverage Statistics\n")
  insect_stats <- insect_fung %>%
    summarize(
      total_insects = n(),
      total_fungi = sum(fungal_parasite_count),
      avg_fungi = mean(fungal_parasite_count),
      median_fungi = median(fungal_parasite_count),
      max_fungi = max(fungal_parasite_count)
    )

  cat(sprintf("  Total insects/mites: %s\n", format(insect_stats$total_insects, big.mark = ",")))
  cat(sprintf("  Total fungus-insect relationships: %s\n", format(insect_stats$total_fungi, big.mark = ",")))
  cat(sprintf("  Avg fungi per insect: %.1f\n", insect_stats$avg_fungi))
  cat(sprintf("  Median: %.0f, Max: %d\n\n", insect_stats$median_fungi, insect_stats$max_fungi))

  # Expected: 1,212 insects, ~6,724 relationships, ~5.5 avg
  if (insect_stats$total_insects < 1100 || insect_stats$total_insects > 1300) {
    cat(sprintf("  ⚠️  WARNING: Insect count (%d) outside expected range (1100-1300)\n",
                insect_stats$total_insects))
  }

  if (insect_stats$avg_fungi < 4 || insect_stats$avg_fungi > 8) {
    cat(sprintf("  ⚠️  WARNING: Average fungi per insect (%.1f) outside expected range (4-8)\n",
                insect_stats$avg_fungi))
  } else {
    cat("  ✓ PASS: Coverage statistics look reasonable\n\n")
  }

  # Test 3.5: Taxonomic breakdown
  cat("Test 3.5: Taxonomic Breakdown\n")
  tax_breakdown <- insect_fung %>%
    group_by(herbivore_class) %>%
    summarize(
      count = n(),
      pct = 100 * n() / nrow(insect_fung),
      .groups = "drop"
    ) %>%
    arrange(desc(count))

  print(tax_breakdown, row.names = FALSE)
  cat("\n")

  # Expected: mostly Insecta (>95%), some Arachnida
  insecta_pct <- tax_breakdown %>%
    filter(herbivore_class == "Insecta") %>%
    pull(pct)

  if (length(insecta_pct) > 0 && insecta_pct[1] > 90) {
    cat("  ✓ PASS: Insecta dominates as expected (>90%)\n\n")
  } else {
    cat("  ⚠️  WARNING: Expected Insecta to dominate (>90%)\n\n")
  }
}

# ================================================================================
# PART 4: CROSS-REFERENCE CHECKS
# ================================================================================

cat("================================================================================\n")
cat("PART 4: CROSS-REFERENCE CHECKS\n")
cat("================================================================================\n\n")

if (file.exists(ORGANISM_PROFILES) && exists("herb_pred") && exists("path_ant") && exists("insect_fung")) {
  cat("Loading organism profiles for cross-reference...\n")
  profiles <- read_parquet(ORGANISM_PROFILES)
  cat(sprintf("  - Loaded %s plant profiles\n\n", format(nrow(profiles), big.mark = ",")))

  # Test 4.1: Herbivores in network appear in profiles
  cat("Test 4.1: Herbivore Network Coverage\n")
  all_profile_herbivores <- unique(unlist(profiles$herbivores))
  cat(sprintf("  Unique herbivores in profiles: %s\n", format(length(all_profile_herbivores), big.mark = ",")))
  cat(sprintf("  Herbivores with predators in network: %s\n", format(nrow(herb_pred), big.mark = ",")))

  coverage_pct <- 100 * nrow(herb_pred) / length(all_profile_herbivores)
  cat(sprintf("  Coverage: %.1f%%\n", coverage_pct))

  if (coverage_pct < 10) {
    cat("  ⚠️  WARNING: Low coverage (<10%) - most herbivores lack predator data\n")
    cat("  (This is expected due to GloBI data sparsity)\n\n")
  } else {
    cat("  ✓ Reasonable coverage given GloBI data limitations\n\n")
  }

  # Test 4.2: Pathogens in network appear in profiles
  cat("Test 4.2: Pathogen Network Coverage\n")
  all_profile_pathogens <- unique(unlist(profiles$pathogens))
  cat(sprintf("  Unique pathogens in profiles: %s\n", format(length(all_profile_pathogens), big.mark = ",")))
  cat(sprintf("  Pathogens with antagonists in network: %s\n", format(nrow(path_ant), big.mark = ",")))

  coverage_pct <- 100 * nrow(path_ant) / length(all_profile_pathogens)
  cat(sprintf("  Coverage: %.1f%%\n", coverage_pct))

  if (coverage_pct < 3) {
    cat("  ⚠️  WARNING: Low coverage (<3%) - most pathogens lack antagonist data\n")
    cat("  (This is expected due to GloBI data sparsity)\n\n")
  } else {
    cat("  ✓ Reasonable coverage given GloBI data limitations\n\n")
  }

  # Test 4.3: Insect-fungal network herbivores overlap with profiles
  cat("Test 4.3: Insect-Fungal Network Overlap\n")
  insect_fung_herbivores <- insect_fung$herbivore
  overlap_count <- sum(insect_fung_herbivores %in% all_profile_herbivores)
  overlap_pct <- 100 * overlap_count / length(insect_fung_herbivores)

  cat(sprintf("  Insects in fungal network: %s\n", format(length(insect_fung_herbivores), big.mark = ",")))
  cat(sprintf("  Also appear in plant profiles: %s (%.1f%%)\n",
              format(overlap_count, big.mark = ","), overlap_pct))

  if (overlap_pct < 5) {
    cat("  ⚠️  WARNING: Low overlap (<5%) - most fungal-parasitized insects not in our plant network\n")
    cat("  (Expected - insect-fungal network is broader than our specific plants)\n\n")
  } else {
    cat("  ✓ Some overlap exists for biocontrol calculations\n\n")
  }
}

# ================================================================================
# FINAL SUMMARY
# ================================================================================

cat("================================================================================\n")
cat("VERIFICATION SUMMARY\n")
cat("================================================================================\n\n")

if (all_checks_pass) {
  cat("✓ ALL CRITICAL TESTS PASSED\n\n")
  cat("Summary:\n")
  if (exists("herb_pred")) {
    cat(sprintf("  - Herbivore-predator network: %s herbivores, %s relationships\n",
                format(nrow(herb_pred), big.mark = ","),
                format(herb_stats$total_predators, big.mark = ",")))
  }
  if (exists("path_ant")) {
    cat(sprintf("  - Pathogen-antagonist network: %s pathogens, %s relationships\n",
                format(nrow(path_ant), big.mark = ","),
                format(path_stats$total_antagonists, big.mark = ",")))
  }
  if (exists("insect_fung")) {
    cat(sprintf("  - Insect-fungal parasite network: %s insects, %s relationships\n",
                format(nrow(insect_fung), big.mark = ","),
                format(insect_stats$total_fungi, big.mark = ",")))
  }
  cat("\n✓ Datasets are ready for guild calibration\n\n")
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
