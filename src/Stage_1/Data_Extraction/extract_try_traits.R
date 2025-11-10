# ================================================================================
# TRY Database Trait Extraction Script
# ================================================================================
# Purpose: Extract 7 functional plant traits from TRY database (v5.0)
#
# TRY (Plant Trait Database) provides standardized measurements of functional
# traits across ~280K plant species. This script extracts a focused set of
# traits for ecological indicator value prediction.
#
# Target Traits:
#   TraitID 7:    Mycorrhiza type (AM, EM, ERM, NM)
#   TraitID 46:   Leaf thickness (mm)
#   TraitID 37:   Leaf phenology type (deciduous, evergreen, etc.)
#   TraitID 22:   Photosynthesis pathway (C3, C4, CAM)
#   TraitID 31:   Species tolerance to frost (categorical)
#   TraitID 47:   Leaf dry matter content - LDMC (mg/g, lamina only)
#   TraitID 3115: Specific leaf area - SLA (mm²/mg, petiole excluded)
#
# IMPORTANT: TraitID 47 (LDMC) follows Bill Shipley's advice to use lamina-only
# measurements, avoiding petiole/cotyledon/rachis LDMC (TraitIDs 1010/3055/3081)
#
# Data Flow:
# Input:  data/TRY/*.txt (TRY text dumps, Latin-1 encoded)
# Output: data/stage1/try_selected_traits.parquet (618,932 records)
#         artifacts/stage1_data_extraction/*.rds (per-trait intermediate files)
#
# Execution Time: ~20-30 minutes for full TRY database
# ================================================================================

# ================================================================================
# Environment Configuration
# ================================================================================
# Set custom library path for R packages
.libPaths("/home/olier/ellenberg/.Rlib")

# Load required libraries
# rtry: Specialized package for TRY database handling (rtry_import, rtry_select_col)
# dplyr: Data manipulation (filter)
# data.table: High-performance aggregation (rbindlist, fwrite)
library(rtry)
library(dplyr)
library(data.table)

# ================================================================================
# Trait Selection Configuration
# ================================================================================
# Define the 7 functional traits to extract from TRY database
# Each trait includes: TraitID (TRY database identifier), name (slug), description
target_traits <- list(
  list(id = 7, name = "mycorrhiza_type", desc = "Mycorrhiza type"),
  list(id = 46, name = "leaf_thickness", desc = "Leaf thickness"),
  list(id = 37, name = "leaf_phenology_type", desc = "Leaf phenology type"),
  list(id = 22, name = "photosynthesis_pathway", desc = "Photosynthesis pathway"),
  list(id = 31, name = "species_tolerance_to_frost", desc = "Species tolerance to frost"),

  # Canonical LDMC for lamina: TraitID 47 (leaf dry mass per leaf fresh mass)
  # IMPORTANT: Bill Shipley advised using lamina-only LDMC measurements
  # Avoid petiole/cotyledon/rachis LDMC (TraitIDs 1010/3055/3081) which measure
  # different plant parts and are not comparable
  list(id = 47, name = "leaf_dry_matter_content", desc = "Leaf dry mass per leaf fresh mass (LDMC)"),

  # SLA with petiole excluded (TraitID 3115) for consistency with literature
  list(id = 3115, name = "specific_leaf_area", desc = "Leaf area per leaf dry mass (SLA, petiole excluded)")
)

# ================================================================================
# File Path Configuration
# ================================================================================
# Scan TRY data directory for all .txt files (TRY database exports)
# TRY data is typically split across multiple text files due to size
input_files <- sort(list.files(
  "/home/olier/ellenberg/data/TRY",
  pattern = "\\.txt$",
  full.names = TRUE
))

# Output directory for intermediate RDS files (per-trait, per-file extracts)
output_dir <- "/home/olier/ellenberg/artifacts/stage1_data_extraction"

# Create output directory if it doesn't exist (idempotent)
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# ================================================================================
# MAIN PROCESSING LOOP: Iterate Over TRY Input Files
# ================================================================================
# TRY database is split across multiple .txt files
# Each file contains a subset of species and measurements
for (input_file in input_files) {
  if (!file.exists(input_file)) {
    message("File not found, skipping: ", input_file)
    next
  }

  message("\n===================================")
  message("Processing file: ", basename(input_file))
  message("===================================")

  # ==============================================================================
  # STEP 1: Import TRY Text File (Latin-1 Encoding)
  # ==============================================================================
  # rtry_import handles TRY-specific format:
  # - Tab-delimited text
  # - Latin-1 encoding (for accented botanical names)
  # - TRY-specific column structure (ObservationID, TraitID, etc.)
  message("Importing data from: ", input_file)
  try_data <- rtry_import(input_file)

  # ==============================================================================
  # STEP 2: Extract Each Target Trait from Current File
  # ==============================================================================
  for (trait in target_traits) {
    message("\n-----------------------------------")
    message("Extracting Trait ", trait$id, " (", trait$desc, ")...")

    # Filter to rows matching the target TraitID
    # TRY data contains hundreds of traits; we filter to our 7 target traits
    trait_data <- dplyr::filter(try_data, TraitID == trait$id)

    if (nrow(trait_data) > 0) {
      # ============================================================================
      # STEP 3: Select Relevant Columns for Downstream Analysis
      # ============================================================================
      # Keep only columns needed for trait analysis:
      # - AccSpeciesID/AccSpeciesName: Standardized species identifiers
      # - OrigValueStr: Original trait value as recorded (categorical traits)
      # - StdValue: Standardized numeric value (continuous traits)
      # - ValueKindName: Measurement type (mean, single, etc.)
      # - UnitName: Standardized units (mm, mg/g, etc.)
      trait_data_selected <- rtry_select_col(trait_data,
                                            AccSpeciesID,
                                            AccSpeciesName,
                                            SpeciesName,
                                            TraitID,
                                            TraitName,
                                            DataID,
                                            DataName,
                                            OrigValueStr,
                                            StdValue,
                                            ValueKindName,
                                            OrigUnitStr,
                                            UnitName)

      # ============================================================================
      # STEP 4: Save Per-File Per-Trait Extract to RDS
      # ============================================================================
      # Create unique filename: trait_<ID>_<name>_<source_file>.rds
      # Example: trait_47_leaf_dry_matter_content_try_data_1.rds
      file_suffix <- gsub(".txt", "", basename(input_file))
      output_file <- file.path(output_dir,
                              paste0("trait_", trait$id, "_", trait$name, "_", file_suffix, ".rds"))

      # RDS format preserves R data types (factors, NAs) better than CSV
      message("Saving extracted data to: ", output_file)
      saveRDS(trait_data_selected, file = output_file)

      # ============================================================================
      # STEP 5: Report Extraction Statistics
      # ============================================================================
      n_records <- nrow(trait_data_selected)
      n_species <- length(unique(trait_data_selected$AccSpeciesName))
      message(paste("Extracted", n_records, "records for", n_species, "unique species"))

      # For categorical traits (mycorrhiza, phenology, photosynthesis),
      # show sample values to verify extraction quality
      if (trait$id %in% c(7, 37, 22)) {
        unique_vals <- unique(trait_data_selected$OrigValueStr[!is.na(trait_data_selected$OrigValueStr)])
        message("Sample values: ", paste(head(unique_vals, 10), collapse = ", "))
      }
    } else {
      message("No data found for Trait ", trait$id, " in this file")
    }
  }

  # ==============================================================================
  # STEP 6: Memory Cleanup After Each File
  # ==============================================================================
  # TRY files can be large (>1GB in memory)
  # Explicitly remove and garbage collect after each file
  rm(try_data)
  gc(verbose = FALSE)
}

# ================================================================================
# AGGREGATION PHASE: Combine Per-File Extracts for Each Trait
# ================================================================================
message("\n===================================")
message("Combining results from multiple files...")
message("===================================")

for (trait in target_traits) {
  # ==============================================================================
  # STEP 1: Find All RDS Files for Current Trait
  # ==============================================================================
  # Pattern matches: trait_<ID>_<name>_<any_source_file>.rds
  # Example: trait_47_leaf_dry_matter_content_*.rds
  pattern <- paste0("trait_", trait$id, "_", trait$name, "_.*\\.rds$")
  trait_files <- list.files(output_dir, pattern = pattern, full.names = TRUE)

  if (length(trait_files) > 0) {
    message("\nCombining Trait ", trait$id, " (", trait$desc, ")...")

    # ============================================================================
    # STEP 2: Load and Row-Bind All Per-File Extracts
    # ============================================================================
    # Combine extracts from multiple TRY source files
    # Example: trait_47 may appear in try_data_1.txt AND try_data_2.txt
    combined_data <- NULL
    for (file in trait_files) {
      data <- readRDS(file)
      if (is.null(combined_data)) {
        combined_data <- data
      } else {
        # Note: Using rbind in loop (not optimal for performance)
        # For large datasets, consider data.table::rbindlist upfront
        combined_data <- rbind(combined_data, data)
      }
    }

    # ============================================================================
    # STEP 3: Remove Duplicate Records
    # ============================================================================
    # TRY data may have overlapping records across source files
    # unique() removes exact row duplicates
    combined_data <- unique(combined_data)
    
    # Save combined file (full name) and canonical simplified name when required
    output_file <- file.path(output_dir, paste0("trait_", trait$id, "_", trait$name, "_combined.rds"))
    saveRDS(combined_data, file = output_file)

    # Also save simplified canonical outputs for downstream modeling
    # Expected (per user):
    #   - trait_46_leaf_thickness.rds
    #   - trait_37_leaf_phenology_type.rds
    #   - trait_22_photosynthesis_pathway.rds
    #   - trait_31_species_tolerance_to_frost.rds
    if (trait$id %in% c(46, 37, 22, 31, 47, 3115)) {
      canonical_out <- file.path(output_dir, paste0("trait_", trait$id, "_", trait$name, ".rds"))
      saveRDS(combined_data, file = canonical_out)
      message("  Canonical output saved to: ", canonical_out)
    }
    
    # Report summary
    n_records <- nrow(combined_data)
    n_species <- length(unique(combined_data$AccSpeciesName))
    message(paste("  Combined:", n_records, "total records,", n_species, "unique species"))
    message("  Saved to:", output_file)
    
    # Clean up individual files (optional - comment out if you want to keep them)
    # for (file in trait_files) {
    #   file.remove(file)
    # }
  }
}

# Create summary CSV
message("\n===================================")
message("Creating summary report...")
message("===================================")

summary_data <- data.frame(
  TraitID = integer(),
  TraitName = character(),
  Description = character(),
  TotalRecords = integer(),
  UniqueSpecies = integer(),
  stringsAsFactors = FALSE
)

all_trait_records <- list()

for (trait in target_traits) {
  combined_file <- file.path(output_dir, paste0("trait_", trait$id, "_", trait$name, "_combined.rds"))
  if (file.exists(combined_file)) {
    data <- readRDS(combined_file)
    data$TraitSlug <- trait$name
    summary_data <- rbind(summary_data, data.frame(
      TraitID = trait$id,
      TraitName = trait$name,
      Description = trait$desc,
      TotalRecords = nrow(data),
      UniqueSpecies = length(unique(data$AccSpeciesName)),
      stringsAsFactors = FALSE
    ))
    all_trait_records[[length(all_trait_records) + 1]] <- data
  }
}

summary_file <- file.path(output_dir, "extracted_traits_summary.csv")
write.csv(summary_data, summary_file, row.names = FALSE)
message("Summary saved to: ", summary_file)

if (length(all_trait_records) > 0) {
  combined_traits <- rbindlist(all_trait_records, fill = TRUE)
  combined_traits <- unique(combined_traits)
  csv_output_path <- "/home/olier/ellenberg/data/stage1/try_selected_traits.csv"
  parquet_source <- file.path(output_dir, "try_selected_traits.csv")
  fwrite(combined_traits, csv_output_path)
  fwrite(combined_traits, parquet_source)
  message("Combined CSV saved to: ", csv_output_path)
  message("Combined CSV (artifact copy) saved to: ", parquet_source)
}

message("\n===================================")
message("Script finished successfully!")
message("===================================")
message("All extracted trait data saved to: ", output_dir)
