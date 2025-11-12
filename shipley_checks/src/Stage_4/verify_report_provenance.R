#!/usr/bin/env Rscript
#
# Verify Report Provenance
#
# Traces organism data in generated markdown reports back to source parquet files.
# Verifies:
# - Fungal species counts and categorizations match source data
# - Pollinator counts match source data
# - Sample organism names exist in source data
# - Shared organism calculations are correct
#
# Usage: Rscript verify_report_provenance.R <report_md_path>
#
# Dependencies: arrow, dplyr, stringr, glue
# Author: Verification pipeline for Stage 4 dual verification

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(stringr)
  library(glue)
})

# ============================================================================
# Helper Functions
# ============================================================================

#' Parse markdown report to extract guild metadata
parse_report <- function(report_path) {
  lines <- readLines(report_path)

  result <- list(
    guild_name = NA_character_,
    plant_wfo_ids = character(),
    claimed_fungi_count = NA_integer_,
    claimed_pollinator_count = NA_integer_,
    sample_pollinators = character(),
    sample_fungi = character(),
    m5_score = NA_real_,
    m7_score = NA_real_
  )

  # Extract guild name (first line after "# Guild Report: ")
  title_line <- lines[str_detect(lines, "^# Guild Report:")]
  if (length(title_line) > 0) {
    result$guild_name <- str_trim(str_remove(title_line[1], "^# Guild Report:\\s*"))
  }

  # Extract plant WFO IDs (lines with `wfo-`)
  plant_lines <- lines[str_detect(lines, "`wfo-\\d+`")]
  wfo_ids <- str_extract_all(plant_lines, "wfo-\\d+") %>% unlist() %>% unique()
  result$plant_wfo_ids <- wfo_ids

  # Extract M5 (fungal) data
  # Pattern: "Evidence: 147 shared fungal species"
  m5_evidence <- lines[str_detect(lines, "Evidence:.*shared fungal species")]
  if (length(m5_evidence) > 0) {
    result$claimed_fungi_count <- as.integer(str_extract(m5_evidence[1], "\\d+"))
  }

  # Extract M7 (pollinator) data
  # Pattern: "170 pollinator species serve multiple plants"
  m7_evidence <- lines[str_detect(lines, "pollinator species serve multiple plants")]
  if (length(m7_evidence) > 0) {
    result$claimed_pollinator_count <- as.integer(str_extract(m7_evidence[1], "\\d+"))
  }

  # Extract sample pollinator names from evidence line
  # Pattern: "Evidence: Philomastix macleaii, Cheilosia, ..."
  pollinator_evidence <- lines[str_detect(lines, "Evidence:.*") &
                                str_detect(lines, "(Philomastix|Wind|Vespa|Bombus|Apoidea)")]
  if (length(pollinator_evidence) > 0) {
    # Remove "Evidence: " prefix
    taxa_str <- str_remove(pollinator_evidence[1], "^.*Evidence:\\s*")
    result$sample_pollinators <- str_split(taxa_str, ",\\s*")[[1]]
  }

  # Extract M5/M7 scores from detailed metrics table
  # Pattern: "| Beneficial Fungi (M5) | ██████████░░░░░░░░░░ 50.0 |"
  m5_line <- lines[str_detect(lines, "Beneficial Fungi \\(M5\\)")]
  if (length(m5_line) > 0) {
    result$m5_score <- as.numeric(str_extract(m5_line[1], "\\d+\\.\\d+"))
  }

  m7_line <- lines[str_detect(lines, "Pollinator Support \\(M7\\)")]
  if (length(m7_line) > 0) {
    result$m7_score <- as.numeric(str_extract(m7_line[1], "\\d+\\.\\d+"))
  }

  return(result)
}

#' Load source data for guild plants
load_source_data <- function(plant_wfo_ids) {
  # Load fungal guilds data
  fungal_data <- read_parquet('shipley_checks/stage4/plant_fungal_guilds_hybrid_11711.parquet') %>%
    filter(plant_wfo_id %in% plant_wfo_ids)

  # Load organism profiles data
  organism_data <- read_parquet('shipley_checks/stage4/plant_organism_profiles_11711.parquet') %>%
    filter(plant_wfo_id %in% plant_wfo_ids)

  return(list(
    fungal = fungal_data,
    organism = organism_data
  ))
}

#' Calculate ground truth fungal metrics
calculate_fungal_ground_truth <- function(fungal_data) {
  # Collect all fungal species across categories
  all_fungi <- c()
  beneficial_fungi <- c()

  for (i in seq_len(nrow(fungal_data))) {
    row <- fungal_data[i, ]
    plant_fungi <- c()

    # Beneficial fungi: AMF + EMF + Endophytic + Saprotrophic
    if (!is.null(row$amf_fungi[[1]])) {
      plant_fungi <- c(plant_fungi, row$amf_fungi[[1]])
    }
    if (!is.null(row$emf_fungi[[1]])) {
      plant_fungi <- c(plant_fungi, row$emf_fungi[[1]])
    }
    if (!is.null(row$endophytic_fungi[[1]])) {
      plant_fungi <- c(plant_fungi, row$endophytic_fungi[[1]])
    }
    if (!is.null(row$saprotrophic_fungi[[1]])) {
      plant_fungi <- c(plant_fungi, row$saprotrophic_fungi[[1]])
    }

    # De-duplicate within this plant (matches scorer logic)
    plant_fungi_unique <- unique(plant_fungi[!is.na(plant_fungi)])
    beneficial_fungi <- c(beneficial_fungi, plant_fungi_unique)
  }

  unique_beneficial <- unique(beneficial_fungi)

  # Calculate shared fungi (present in 2+ plants)
  fungal_counts <- table(beneficial_fungi)
  shared_fungi <- names(fungal_counts[fungal_counts >= 2])

  return(list(
    total_unique = length(unique_beneficial),
    shared_count = length(shared_fungi),
    shared_species = shared_fungi,
    all_beneficial = unique_beneficial
  ))
}

#' Calculate ground truth pollinator metrics
calculate_pollinator_ground_truth <- function(organism_data) {
  all_pollinators <- c()

  for (i in seq_len(nrow(organism_data))) {
    row <- organism_data[i, ]
    plant_pollinators <- c()

    # Pollinators + Flower visitors (matches scorer logic)
    if (!is.null(row$pollinators[[1]])) {
      plant_pollinators <- c(plant_pollinators, row$pollinators[[1]])
    }
    if (!is.null(row$flower_visitors[[1]])) {
      plant_pollinators <- c(plant_pollinators, row$flower_visitors[[1]])
    }

    # De-duplicate within this plant (matches scorer logic)
    plant_pollinators_unique <- unique(plant_pollinators[!is.na(plant_pollinators)])
    all_pollinators <- c(all_pollinators, plant_pollinators_unique)
  }

  unique_pollinators <- unique(all_pollinators)

  # Calculate shared pollinators (present in 2+ plants)
  pollinator_counts <- table(all_pollinators)
  shared_pollinators <- names(pollinator_counts[pollinator_counts >= 2])

  return(list(
    total_unique = length(unique_pollinators),
    shared_count = length(shared_pollinators),
    shared_species = shared_pollinators,
    all_species = unique_pollinators
  ))
}

#' Verify sample organism names exist in source data
verify_sample_names <- function(sample_names, source_species) {
  if (length(sample_names) == 0) return(list(found = character(), missing = character()))

  found <- character()
  missing <- character()

  for (name in sample_names) {
    # Case-insensitive partial match
    match_found <- any(str_detect(tolower(source_species), tolower(str_trim(name))))

    if (match_found) {
      found <- c(found, name)
    } else {
      missing <- c(missing, name)
    }
  }

  return(list(found = found, missing = missing))
}

#' Generate verification report
generate_verification_report <- function(report_metadata, source_data,
                                        fungal_truth, pollinator_truth,
                                        pollinator_name_check) {

  cat(strrep("=", 80), "\n")
  cat(glue("PROVENANCE VERIFICATION REPORT: {report_metadata$guild_name}"), "\n")
  cat(strrep("=", 80), "\n\n")

  cat("GUILD COMPOSITION\n")
  cat(strrep("-", 80), "\n")
  cat(glue("Plants in guild: {length(report_metadata$plant_wfo_ids)}"), "\n")
  cat(glue("Plant IDs: {paste(report_metadata$plant_wfo_ids, collapse = ', ')}"), "\n\n")

  # Verify M5 (Beneficial Fungi)
  cat("M5: BENEFICIAL FUNGI VERIFICATION\n")
  cat(strrep("-", 80), "\n")
  cat(glue("Claimed shared fungi count: {report_metadata$claimed_fungi_count}"), "\n")
  cat(glue("Ground truth shared fungi count: {fungal_truth$shared_count}"), "\n")

  if (!is.na(report_metadata$claimed_fungi_count)) {
    if (report_metadata$claimed_fungi_count == fungal_truth$shared_count) {
      cat("✓ VERIFIED: Fungal count matches source data\n")
    } else {
      diff <- abs(report_metadata$claimed_fungi_count - fungal_truth$shared_count)
      cat(glue("✗ DISCREPANCY: Count differs by {diff}\n"))
      cat(glue("  - Report shows: {report_metadata$claimed_fungi_count}\n"))
      cat(glue("  - Source data: {fungal_truth$shared_count}\n"))
    }
  } else {
    cat("⚠ WARNING: No fungal count found in report\n")
  }

  cat(glue("\nGround truth details:"), "\n")
  cat(glue("  - Total unique beneficial fungi: {fungal_truth$total_unique}"), "\n")
  cat(glue("  - Shared fungi (2+ plants): {fungal_truth$shared_count}"), "\n")
  cat(glue("  - M5 Score in report: {report_metadata$m5_score}"), "\n\n")

  # Verify M7 (Pollinators)
  cat("M7: POLLINATOR VERIFICATION\n")
  cat(strrep("-", 80), "\n")
  cat(glue("Claimed pollinator count: {report_metadata$claimed_pollinator_count}"), "\n")
  cat(glue("Ground truth shared pollinator count: {pollinator_truth$shared_count}"), "\n")

  if (!is.na(report_metadata$claimed_pollinator_count)) {
    if (report_metadata$claimed_pollinator_count == pollinator_truth$shared_count) {
      cat("✓ VERIFIED: Pollinator count matches source data\n")
    } else {
      diff <- abs(report_metadata$claimed_pollinator_count - pollinator_truth$shared_count)
      cat(glue("✗ DISCREPANCY: Count differs by {diff}\n"))
      cat(glue("  - Report shows: {report_metadata$claimed_pollinator_count}\n"))
      cat(glue("  - Source data: {pollinator_truth$shared_count}\n"))
    }
  } else {
    cat("⚠ WARNING: No pollinator count found in report\n")
  }

  cat(glue("\nGround truth details:"), "\n")
  cat(glue("  - Total unique pollinators: {pollinator_truth$total_unique}"), "\n")
  cat(glue("  - Shared pollinators (2+ plants): {pollinator_truth$shared_count}"), "\n")
  cat(glue("  - M7 Score in report: {report_metadata$m7_score}"), "\n\n")

  # Verify sample pollinator names
  if (length(report_metadata$sample_pollinators) > 0) {
    cat("SAMPLE POLLINATOR NAME VERIFICATION\n")
    cat(strrep("-", 80), "\n")
    cat(glue("Sample names extracted from report: {length(report_metadata$sample_pollinators)}"), "\n")

    if (length(pollinator_name_check$found) > 0) {
      cat(glue("✓ FOUND in source data ({length(pollinator_name_check$found)}):"), "\n")
      for (name in pollinator_name_check$found) {
        cat(glue("  - {name}"), "\n")
      }
    }

    if (length(pollinator_name_check$missing) > 0) {
      cat(glue("\n✗ NOT FOUND in source data ({length(pollinator_name_check$missing)}):"), "\n")
      for (name in pollinator_name_check$missing) {
        cat(glue("  - {name}"), "\n")
      }
    }

    cat("\n")
  }

  # Source data coverage
  cat("SOURCE DATA COVERAGE\n")
  cat(strrep("-", 80), "\n")
  cat(glue("Fungal data records loaded: {nrow(source_data$fungal)}"), "\n")
  cat(glue("Organism profile records loaded: {nrow(source_data$organism)}"), "\n")

  missing_fungal <- setdiff(report_metadata$plant_wfo_ids, source_data$fungal$plant_wfo_id)
  missing_organism <- setdiff(report_metadata$plant_wfo_ids, source_data$organism$plant_wfo_id)

  if (length(missing_fungal) > 0) {
    cat(glue("✗ Missing fungal data for: {paste(missing_fungal, collapse = ', ')}"), "\n")
  } else {
    cat("✓ All plants have fungal data\n")
  }

  if (length(missing_organism) > 0) {
    cat(glue("✗ Missing organism data for: {paste(missing_organism, collapse = ', ')}"), "\n")
  } else {
    cat("✓ All plants have organism profile data\n")
  }

  cat("\n")
  cat(strrep("=", 80), "\n")
  cat("VERIFICATION COMPLETE\n")
  cat(strrep("=", 80), "\n\n")
}

# ============================================================================
# Main Execution
# ============================================================================

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  # Default to all reports if no argument
  if (length(args) == 0) {
    report_files <- list.files('shipley_checks/reports', pattern = "\\.md$", full.names = TRUE)
    cat(glue("Verifying {length(report_files)} reports..."), "\n\n")
  } else {
    report_files <- args
  }

  for (report_path in report_files) {
    if (!file.exists(report_path)) {
      cat(glue("ERROR: Report not found: {report_path}"), "\n")
      next
    }

    # Parse report
    report_metadata <- parse_report(report_path)

    # Load source data
    source_data <- load_source_data(report_metadata$plant_wfo_ids)

    # Calculate ground truth
    fungal_truth <- calculate_fungal_ground_truth(source_data$fungal)
    pollinator_truth <- calculate_pollinator_ground_truth(source_data$organism)

    # Verify sample names
    pollinator_name_check <- verify_sample_names(
      report_metadata$sample_pollinators,
      pollinator_truth$all_species
    )

    # Generate verification report
    generate_verification_report(
      report_metadata,
      source_data,
      fungal_truth,
      pollinator_truth,
      pollinator_name_check
    )
  }
}

# Run main
main()
