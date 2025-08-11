#!/usr/bin/env Rscript
# Hierarchical wood density approximation for EIVE species
# Hierarchy: Measured > Family > Growth Form > Default
# Based on medfate methodology with validations from De Cáceres et al. 2021

suppressPackageStartupMessages({
  library(data.table)
})

cat("=== HIERARCHICAL WOOD DENSITY APPROXIMATION ===\n")
cat("Hierarchy: Measured > Family > Growth Form > Default\n\n")

# Load all necessary data
cat("Loading data sources...\n")
try_numeric <- fread("data/output/eive_numeric_trait_matrix.csv")
try_families <- fread("data/output/try_species_families.csv")
family_wd <- fread("data/approximations/lookup_tables/family_wood_density.csv")
growth_forms <- fread("data/output/species_growth_forms.csv")

# Check if wood density column exists
wd_col <- "4"  # TraitID for wood density
if(wd_col %in% names(try_numeric)) {
  cat("  ✓ Wood density measurements found (TraitID 4)\n")
  setnames(try_numeric, wd_col, "wood_density_measured")
} else {
  cat("  ✗ No measured wood density column\n")
  try_numeric$wood_density_measured <- NA_real_
}

# Merge all data sources
cat("\nMerging data sources...\n")
data <- merge(try_numeric[, .(AccSpeciesID, AccSpeciesName, wood_density_measured)],
              try_families[, .(AccSpeciesID, family)],
              by = "AccSpeciesID", all.x = TRUE)

data <- merge(data, family_wd, by.x = "family", by.y = "Family", all.x = TRUE)
setnames(data, "WoodDensity", "wood_density_family")

data <- merge(data, growth_forms[, .(AccSpeciesID, plant_growth_form, plant_woodiness)],
              by = "AccSpeciesID", all.x = TRUE)

cat(sprintf("  Merged data for %d species\n", nrow(data)))

# Process growth forms for wood density estimation
cat("\nProcessing growth forms...\n")

# Clean and standardize growth form values
standardize_growth_form <- function(gf, woodiness) {
  if(is.na(gf) && is.na(woodiness)) return(NA_character_)
  
  # Convert to lowercase for matching
  gf_lower <- tolower(as.character(gf))
  wood_lower <- tolower(as.character(woodiness))
  
  # Priority: Use growth form first, woodiness as backup
  
  # Trees (highest priority for identification)
  if(grepl("tree", gf_lower) || grepl("^t$", gf_lower)) {
    if(grepl("conif|gymnosperm", gf_lower)) return("tree_conifer")
    if(grepl("evergreen", gf_lower)) return("tree_evergreen")
    if(grepl("deciduous", gf_lower)) return("tree_deciduous")
    return("tree")
  }
  
  # Shrubs
  if(grepl("shrub", gf_lower) || grepl("^s$", gf_lower)) {
    if(grepl("evergreen", gf_lower)) return("shrub_evergreen")
    if(grepl("deciduous", gf_lower)) return("shrub_deciduous")
    return("shrub")
  }
  
  # Woody plants (from woodiness column)
  if(!is.na(woodiness) && grepl("^woody$|^w$", wood_lower)) {
    return("shrub")  # Default woody to shrub
  }
  
  # Grasses
  if(grepl("gramin|grass", gf_lower)) return("grass")
  
  # Herbs/Forbs
  if(grepl("herb|forb", gf_lower) || grepl("^h$", gf_lower)) return("herb")
  
  # Non-woody from woodiness column
  if(!is.na(woodiness) && grepl("non-woody|herbaceous", wood_lower)) return("herb")
  
  # Climbers/Vines (often semi-woody)
  if(grepl("climb|vine|liana", gf_lower)) return("shrub_deciduous")
  
  # Parasites (variable, default to herb)
  if(grepl("parasit", gf_lower)) return("herb")
  
  return(NA_character_)
}

data[, growth_form_std := mapply(standardize_growth_form, plant_growth_form, plant_woodiness)]

# Wood density values from growth form (medfate defaults)
growth_form_wd <- data.table(
  growth_form = c("tree", "tree_evergreen", "tree_deciduous", "tree_conifer",
                  "shrub", "shrub_evergreen", "shrub_deciduous",
                  "herb", "grass", "forb"),
  wd_value = c(0.65, 0.65, 0.55, 0.45,
              0.60, 0.60, 0.50,
              0.40, 0.35, 0.35)
)

data <- merge(data, growth_form_wd, by.x = "growth_form_std", by.y = "growth_form", all.x = TRUE)
setnames(data, "wd_value", "wood_density_growth_form")

# Apply hierarchical logic
cat("\nApplying hierarchical approximation...\n")
default_wd <- 0.652  # Global default from medfate

data[, wood_density_final := fifelse(
  !is.na(wood_density_measured), wood_density_measured,
  fifelse(!is.na(wood_density_family), wood_density_family,
  fifelse(!is.na(wood_density_growth_form), wood_density_growth_form, default_wd))
)]

# Track source
data[, wood_density_source := fifelse(
  !is.na(wood_density_measured), "measured",
  fifelse(!is.na(wood_density_family), "family",
  fifelse(!is.na(wood_density_growth_form), "growth_form", "default"))
)]

# Statistics
cat("\n=== APPROXIMATION STATISTICS ===\n")
source_counts <- data[, .N, by = wood_density_source]
setorder(source_counts, wood_density_source)
total_species <- nrow(data)

for(i in 1:nrow(source_counts)) {
  cat(sprintf("  %-11s: %4d species (%5.1f%%)\n", 
              source_counts$wood_density_source[i],
              source_counts$N[i],
              100 * source_counts$N[i] / total_species))
}

# Quality check
cat("\n=== QUALITY METRICS ===\n")
cat(sprintf("  Mean wood density:   %.3f g/cm³\n", mean(data$wood_density_final)))
cat(sprintf("  Median wood density: %.3f g/cm³\n", median(data$wood_density_final)))
cat(sprintf("  SD wood density:     %.3f g/cm³\n", sd(data$wood_density_final)))
cat(sprintf("  Range:               %.3f - %.3f g/cm³\n", 
            min(data$wood_density_final), max(data$wood_density_final)))

# Mean by source
mean_by_source <- data[, .(
  mean_wd = mean(wood_density_final),
  sd_wd = sd(wood_density_final),
  .N
), by = wood_density_source]
setorder(mean_by_source, wood_density_source)

cat("\nMean (±SD) by source:\n")
for(i in 1:nrow(mean_by_source)) {
  cat(sprintf("  %-11s: %.3f ± %.3f g/cm³ (n=%d)\n", 
              mean_by_source$wood_density_source[i],
              mean_by_source$mean_wd[i],
              mean_by_source$sd_wd[i],
              mean_by_source$N[i]))
}

# Check growth form assignments
gf_summary <- data[wood_density_source == "growth_form", .N, by = growth_form_std]
if(nrow(gf_summary) > 0) {
  cat("\n=== GROWTH FORM ASSIGNMENTS ===\n")
  setorder(gf_summary, -N)
  for(i in 1:nrow(gf_summary)) {
    cat(sprintf("  %-20s: %4d species\n", gf_summary$growth_form_std[i], gf_summary$N[i]))
  }
}

# Save outputs
cat("\n💾 Saving approximated wood density...\n")

# Full dataset with all columns
output_full <- data[, .(
  AccSpeciesID,
  AccSpeciesName,
  family,
  plant_growth_form,
  plant_woodiness,
  growth_form_standardized = growth_form_std,
  wood_density_measured,
  wood_density_family,
  wood_density_growth_form,
  wood_density_final,
  wood_density_source
)]
setorder(output_full, AccSpeciesID)

output_file <- "data/approximations/wood_density/wood_density_hierarchical.csv"
fwrite(output_full, output_file)
cat(sprintf("  Full dataset: %s\n", output_file))

# Simplified version for merging
output_simple <- data[, .(
  AccSpeciesID,
  APPROX_wood_density = wood_density_final,
  APPROX_wood_density_source = wood_density_source
)]

simple_file <- "data/approximations/wood_density/wood_density_for_merge.csv"
fwrite(output_simple, simple_file)
cat(sprintf("  For merging: %s\n", simple_file))

# Summary statistics
summary_stats <- data.table(
  metric = c("n_total", "n_measured", "n_family", "n_growth_form", "n_default",
             "mean_overall", "median_overall", "sd_overall", "min_overall", "max_overall",
             "pct_measured", "pct_family", "pct_growth_form", "pct_default"),
  value = c(
    nrow(data),
    sum(data$wood_density_source == "measured"),
    sum(data$wood_density_source == "family"),
    sum(data$wood_density_source == "growth_form"),
    sum(data$wood_density_source == "default"),
    mean(data$wood_density_final),
    median(data$wood_density_final),
    sd(data$wood_density_final),
    min(data$wood_density_final),
    max(data$wood_density_final),
    100 * sum(data$wood_density_source == "measured") / nrow(data),
    100 * sum(data$wood_density_source == "family") / nrow(data),
    100 * sum(data$wood_density_source == "growth_form") / nrow(data),
    100 * sum(data$wood_density_source == "default") / nrow(data)
  )
)

summary_file <- "data/approximations/wood_density/wood_density_summary.csv"
fwrite(summary_stats, summary_file)
cat(sprintf("  Summary stats: %s\n", summary_file))

cat("\n✅ HIERARCHICAL WOOD DENSITY APPROXIMATION COMPLETE!\n")
cat(sprintf("All %d species now have wood density values through optimal hierarchy.\n", nrow(data)))
cat("Ready for integration with TRY+GROOT merged dataset.\n")