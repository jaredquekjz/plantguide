#!/usr/bin/env Rscript

# Assemble modeling dataset with ENHANCED traits by joining:
# 1. Existing model data with 6 core TRY traits
# 2. Newly extracted traits (46, 37, 22, 31) from Stage 1
# 3. EIVE indicator values
# 4. Mycorrhiza groupings
#
# This script extends assemble_model_data_with_myco.R to incorporate the 4 additional traits

suppressWarnings({
  suppressMessages({
    library(data.table)
    library(dplyr)
  })
})

# Set library path
.libPaths("/home/olier/ellenberg/.Rlib")

args <- commandArgs(trailingOnly = TRUE)

# Simple flag parser
parse_args <- function(args) {
  out <- list()
  for (a in args) {
    if (!grepl("^--[A-Za-z0-9_]+=", a)) next
    kv <- sub("^--", "", a)
    k <- sub("=.*$", "", kv)
    v <- sub("^[^=]*=", "", kv)
    out[[k]] <- v
  }
  out
}

opts <- parse_args(args)
`%||%` <- function(a, b) if (!is.null(a) && nzchar(a)) a else b

# === INPUT FILES ===
# Existing model data
existing_model <- opts[["existing_model"]] %||% "artifacts/model_data_complete_case_with_myco.csv"

# Newly extracted trait files
trait_46_file <- opts[["trait_46"]] %||% "artifacts/stage1_data_extraction/trait_46_leaf_thickness_combined.rds"
trait_37_file <- opts[["trait_37"]] %||% "artifacts/stage1_data_extraction/trait_37_leaf_phenology_type_combined.rds"
trait_22_file <- opts[["trait_22"]] %||% "artifacts/stage1_data_extraction/trait_22_photosynthesis_pathway_combined.rds"
trait_31_file <- opts[["trait_31"]] %||% "artifacts/stage1_data_extraction/trait_31_species_tolerance_to_frost_combined.rds"
# LDMC (Trait 47)
trait_47_file <- opts[["trait_47"]] %||% "artifacts/stage1_data_extraction/trait_47_leaf_dry_matter_content_combined.rds"

# === OUTPUT FILES ===
out_enhanced_full <- opts[["out_full"]] %||% "artifacts/model_data_enhanced_traits_full.csv"
out_enhanced_complete <- opts[["out_complete"]] %||% "artifacts/model_data_enhanced_traits_complete.csv"

# === HELPER FUNCTIONS ===
fail <- function(msg) {
  cat(sprintf("[error] %s\n", msg))
  quit(status = 1)
}

check_exists <- function(path, what) {
  if (!file.exists(path)) fail(sprintf("%s not found: '%s'", what, path))
}

ensure_dir <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
}

norm_name <- function(x) {
  x <- as.character(x)
  x <- gsub("[[:space:]]+", " ", x)
  x <- trimws(x)
  tolower(x)
}

# Function to process and aggregate trait data to species level
process_trait_data <- function(trait_file, trait_id, trait_name, is_categorical = FALSE) {
  cat(sprintf("\nProcessing Trait %d (%s)...\n", trait_id, trait_name))
  
  if (!file.exists(trait_file)) {
    cat(sprintf("  WARNING: File not found: %s\n", trait_file))
    return(NULL)
  }
  
  trait_data <- readRDS(trait_file)
  setDT(trait_data)
  
  # Normalize species names
  trait_data$species_norm <- norm_name(trait_data$AccSpeciesName)
  
  if (is_categorical) {
    # For categorical traits, take the most common value per species
    # First, standardize values
    if (trait_id == 37) {
      # Leaf phenology: standardize to evergreen/deciduous/semi-deciduous
      trait_data$value_std <- trait_data$OrigValueStr
      trait_data[grepl("evergreen|^E$|^EV$|always.*green|persistent", value_std, ignore.case = TRUE), 
                 value_std := "evergreen"]
      trait_data[grepl("deciduous|^D$|^DEC|summer green|aestival", value_std, ignore.case = TRUE), 
                 value_std := "deciduous"]
      trait_data[grepl("semi", value_std, ignore.case = TRUE), 
                 value_std := "semi-deciduous"]
    } else if (trait_id == 22) {
      # Photosynthesis pathway: standardize C3/C4/CAM
      trait_data$value_std <- toupper(trait_data$OrigValueStr)
      trait_data[value_std %in% c("C3", "C3?"), value_std := "C3"]
      trait_data[value_std %in% c("C4", "C4?"), value_std := "C4"]
      trait_data[value_std == "CAM", value_std := "CAM"]
      trait_data[value_std %in% c("C3/C4", "UNKNOWN", "?", "??", ""), value_std := NA]
    } else if (trait_id == 7) {
      # Mycorrhiza type: standardize AM/EM/NM etc
      trait_data$value_std <- trait_data$OrigValueStr
      trait_data[grepl("^AM$|arbuscular|vesicular", value_std, ignore.case = TRUE), 
                 value_std := "AM"]
      trait_data[grepl("ecto|^EM$", value_std, ignore.case = TRUE), 
                 value_std := "EM"]
      trait_data[grepl("^NM$|^No$|non-myco", value_std, ignore.case = TRUE), 
                 value_std := "NM"]
      trait_data[grepl("^Yes$", value_std, ignore.case = TRUE), 
                 value_std := "Myco_unspecified"]
    }
    
    # Aggregate: take most common value per species
    species_agg <- trait_data[!is.na(value_std), 
                              .(value = names(sort(table(value_std), decreasing = TRUE)[1]),
                                n_records = .N),
                              by = .(species_norm, AccSpeciesName)]
  } else {
    # For numeric traits, take mean/median
    if (trait_id == 46) {
      # Leaf thickness - use StdValue (in mm)
      species_agg <- trait_data[!is.na(StdValue),
                                .(value = median(StdValue, na.rm = TRUE),
                                  value_mean = mean(StdValue, na.rm = TRUE),
                                  value_sd = sd(StdValue, na.rm = TRUE),
                                  n_records = .N),
                                by = .(species_norm, AccSpeciesName)]
    } else if (trait_id == 31) {
      # Frost tolerance - use OrigValueStr as numeric
      trait_data$value_numeric <- as.numeric(trait_data$OrigValueStr)
      species_agg <- trait_data[!is.na(value_numeric),
                                .(value = median(value_numeric, na.rm = TRUE),
                                  value_mean = mean(value_numeric, na.rm = TRUE),
                                  value_sd = sd(value_numeric, na.rm = TRUE),
                                  n_records = .N),
                                by = .(species_norm, AccSpeciesName)]
    } else if (trait_id == 47) {
      # LDMC - leaf dry mass per leaf fresh mass (dimensionless ratio)
      species_agg <- trait_data[!is.na(StdValue),
                                .(value = median(StdValue, na.rm = TRUE),
                                  value_mean = mean(StdValue, na.rm = TRUE),
                                  value_sd = sd(StdValue, na.rm = TRUE),
                                  n_records = .N),
                                by = .(species_norm, AccSpeciesName)]
    }
  }
  
  # Rename value column to trait-specific name
  col_name <- switch(as.character(trait_id),
                     "7" = "Mycorrhiza_type_enhanced",
                     "46" = "Leaf_thickness_mm",
                     "37" = "Leaf_phenology",
                     "22" = "Photosynthesis_pathway",
                     "31" = "Frost_tolerance_score",
                     "47" = "LDMC")
  
  setnames(species_agg, "value", col_name)
  
  # Add record count column
  count_col <- paste0(col_name, "_n")
  setnames(species_agg, "n_records", count_col)
  
  cat(sprintf("  Aggregated to %d species\n", nrow(species_agg)))
  cat(sprintf("  Column names: %s\n", paste(names(species_agg), collapse = ", ")))
  
  return(species_agg)
}

# === MAIN PROCESSING ===

cat("================================================================================\n")
cat("ASSEMBLING MODEL DATA WITH ENHANCED TRAITS\n")
cat("================================================================================\n")

# 1. Load existing model data
check_exists(existing_model, "Existing model data")
model_data <- fread(existing_model)
cat(sprintf("\nLoaded existing model data: %d species, %d columns\n", 
            nrow(model_data), ncol(model_data)))

# Store original columns for comparison
original_cols <- names(model_data)

# Normalize species names for merging
model_data$species_norm <- norm_name(model_data$wfo_accepted_name)

# 2. Process each new trait
trait_46_agg <- process_trait_data(trait_46_file, 46, "Leaf thickness", is_categorical = FALSE)
trait_37_agg <- process_trait_data(trait_37_file, 37, "Leaf phenology", is_categorical = TRUE)
trait_22_agg <- process_trait_data(trait_22_file, 22, "Photosynthesis pathway", is_categorical = TRUE)
trait_31_agg <- process_trait_data(trait_31_file, 31, "Frost tolerance", is_categorical = FALSE)
trait_47_agg <- process_trait_data(trait_47_file, 47, "LDMC", is_categorical = FALSE)

# 3. Merge new traits with model data
cat("\n--- Merging new traits ---\n")

if (!is.null(trait_46_agg)) {
  model_data <- merge(model_data, 
                      trait_46_agg[, .(species_norm, Leaf_thickness_mm, Leaf_thickness_mm_n)],
                      by = "species_norm", all.x = TRUE)
  cat(sprintf("  Trait 46 (Leaf thickness): %d matches\n", 
              sum(!is.na(model_data$Leaf_thickness_mm))))
}

if (!is.null(trait_37_agg)) {
  model_data <- merge(model_data,
                      trait_37_agg[, .(species_norm, Leaf_phenology, Leaf_phenology_n)],
                      by = "species_norm", all.x = TRUE)
  cat(sprintf("  Trait 37 (Leaf phenology): %d matches\n", 
              sum(!is.na(model_data$Leaf_phenology))))
}

if (!is.null(trait_22_agg)) {
  model_data <- merge(model_data,
                      trait_22_agg[, .(species_norm, Photosynthesis_pathway, Photosynthesis_pathway_n)],
                      by = "species_norm", all.x = TRUE)
  cat(sprintf("  Trait 22 (Photosynthesis): %d matches\n", 
              sum(!is.na(model_data$Photosynthesis_pathway))))
}

if (!is.null(trait_31_agg)) {
  model_data <- merge(model_data,
                      trait_31_agg[, .(species_norm, Frost_tolerance_score, Frost_tolerance_score_n)],
                      by = "species_norm", all.x = TRUE)
  cat(sprintf("  Trait 31 (Frost tolerance): %d matches\n", 
              sum(!is.na(model_data$Frost_tolerance_score))))
}

if (!is.null(trait_47_agg)) {
  model_data <- merge(model_data,
                      trait_47_agg[, .(species_norm, LDMC, LDMC_n)],
                      by = "species_norm", all.x = TRUE)
  cat(sprintf("  Trait 47 (LDMC): %d matches\n", 
              sum(!is.na(model_data$LDMC))))
}

# 4. Calculate derived trait (Leaf N per area from Nmass and LMA)
if ("Nmass (mg/g)" %in% names(model_data) && "LMA (g/m2)" %in% names(model_data)) {
  # Leaf N per area = Nmass / LMA * 1000 (to get mg/m2)
  model_data$Leaf_N_per_area <- model_data$`Nmass (mg/g)` / model_data$`LMA (g/m2)` * 1000
  cat(sprintf("\n  Calculated Leaf N per area for %d species\n", 
              sum(!is.na(model_data$Leaf_N_per_area))))
}

# 5. Derived LDMC-based features for Light axis
if ("LDMC" %in% names(model_data) && "Leaf area (mm2)" %in% names(model_data)) {
  valid <- !is.na(model_data$LDMC) & (model_data$LDMC > 0) &
           !is.na(model_data$`Leaf area (mm2)`) & (model_data$`Leaf area (mm2)` > 0)
  model_data$log_ldmc_plus_log_la  <- NA_real_
  model_data$log_ldmc_minus_log_la <- NA_real_
  model_data$log_ldmc_plus_log_la[valid]  <- log(model_data$LDMC[valid]) + log(model_data$`Leaf area (mm2)`[valid])
  model_data$log_ldmc_minus_log_la[valid] <- log(model_data$LDMC[valid]) - log(model_data$`Leaf area (mm2)`[valid])
  cat(sprintf("\n  Computed LDMC-derived features for %d species\n", sum(valid)))
}

# 6. Remove temporary norm column and reorder
model_data[, species_norm := NULL]

# Put new trait columns after existing traits
new_trait_cols <- c("Leaf_thickness_mm", "Leaf_thickness_mm_n",
                   "LDMC", "LDMC_n",
                   "log_ldmc_plus_log_la", "log_ldmc_minus_log_la",
                   "Leaf_phenology", "Leaf_phenology_n", 
                   "Photosynthesis_pathway", "Photosynthesis_pathway_n",
                   "Frost_tolerance_score", "Frost_tolerance_score_n",
                   "Leaf_N_per_area")
new_trait_cols <- new_trait_cols[new_trait_cols %in% names(model_data)]

# Find position after SSD columns
ssd_col_idx <- which(names(model_data) == "SSD used (mg/mm3)")
if (length(ssd_col_idx) == 0) ssd_col_idx <- which(names(model_data) == "SSD (n.o.)")

if (length(ssd_col_idx) > 0) {
  before_cols <- names(model_data)[1:ssd_col_idx]
  after_cols <- setdiff(names(model_data), c(before_cols, new_trait_cols))
  model_data <- model_data[, c(before_cols, new_trait_cols, after_cols), with = FALSE]
}

# 6. Create complete-case dataset (ALL species with the original 6 traits)
# For phylogenetic imputation, we keep ALL species regardless of new trait completeness
trait_cols_6 <- c("Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", 
                  "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
have_all_6 <- Reduce(`&`, lapply(trait_cols_6, function(cn) !is.na(model_data[[cn]])))

# Count how many new traits each species has (for reporting only)
new_trait_value_cols <- c("Leaf_thickness_mm", "LDMC", "Leaf_phenology", 
                          "Photosynthesis_pathway", "Frost_tolerance_score")
new_trait_value_cols <- new_trait_value_cols[new_trait_value_cols %in% names(model_data)]

# Count valid new traits (excluding empty strings)
model_data[, n_new_traits := 
  (!is.na(Leaf_thickness_mm)) + 
  (!is.na(LDMC)) +
  (!is.na(Leaf_phenology) & Leaf_phenology != "") +
  (!is.na(Photosynthesis_pathway) & Photosynthesis_pathway != "") +
  (!is.na(Frost_tolerance_score))]

# Complete case: has all 6 original traits (keeping ALL for phylogenetic imputation)
model_complete <- model_data[have_all_6]

# Clean up empty strings to NA for consistency
if ("Leaf_phenology" %in% names(model_complete)) {
  model_complete[Leaf_phenology == "", Leaf_phenology := NA]
}
if ("Photosynthesis_pathway" %in% names(model_complete)) {
  model_complete[Photosynthesis_pathway == "", Photosynthesis_pathway := NA]
}

# 7. Save outputs
ensure_dir(out_enhanced_full)
ensure_dir(out_enhanced_complete)

fwrite(model_data, out_enhanced_full)
fwrite(model_complete, out_enhanced_complete)

# 8. Print summary
cat("\n================================================================================\n")
cat("SUMMARY\n")
cat("================================================================================\n\n")

cat(sprintf("Full dataset: %d species, %d columns\n", nrow(model_data), ncol(model_data)))
cat(sprintf("Complete-case dataset: %d species (%.1f%%)\n", 
            nrow(model_complete), 100 * nrow(model_complete) / nrow(model_data)))
cat("Note: All species retained for phylogenetic imputation\n")

# Check original categorical traits
cat_traits <- c("Woodiness", "Growth Form", "Leaf type")
cat("\nOriginal categorical trait coverage:\n")
for (trait in cat_traits) {
  if (trait %in% names(model_complete)) {
    n_available <- sum(!is.na(model_complete[[trait]]) & model_complete[[trait]] != "")
    cat(sprintf("  %s: %d species (%.1f%%)\n", 
                trait, n_available, 100 * n_available / nrow(model_complete)))
  }
}

cat("\nNew trait coverage in complete-case data:\n")
for (col in new_trait_value_cols) {
  n_available <- sum(!is.na(model_complete[[col]]) & 
                    (if(is.character(model_complete[[col]])) model_complete[[col]] != "" else TRUE))
  cat(sprintf("  %s: %d species (%.1f%%)\n", 
              col, n_available, 100 * n_available / nrow(model_complete)))
}

# Distribution of species by number of new traits
cat("\nDistribution by number of valid new traits:\n")
trait_dist <- table(model_complete$n_new_traits)
for (i in 1:length(trait_dist)) {
  n_traits <- names(trait_dist)[i]
  n_species <- trait_dist[i]
  cat(sprintf("  %s new traits: %d species\n", n_traits, n_species))
}

cat("\nValue distributions in complete-case:\n")
if ("Leaf_phenology" %in% names(model_complete)) {
  cat("  Leaf phenology:\n")
  pheno_table <- table(model_complete$Leaf_phenology, useNA = "ifany")
  for (i in 1:length(pheno_table)) {
    cat(sprintf("    %s: %d\n", names(pheno_table)[i], pheno_table[i]))
  }
}

if ("Photosynthesis_pathway" %in% names(model_complete)) {
  cat("  Photosynthesis pathway:\n")
  photo_table <- table(model_complete$Photosynthesis_pathway, useNA = "ifany")
  for (i in 1:length(photo_table)) {
    cat(sprintf("    %s: %d\n", names(photo_table)[i], photo_table[i]))
  }
}

cat("\nOutputs written:\n")
cat(sprintf("  - Full: %s\n", out_enhanced_full))
cat(sprintf("  - Complete: %s\n", out_enhanced_complete))

cat("\n================================================================================\n")
cat("DONE!\n")
cat("================================================================================\n")

invisible(NULL)
