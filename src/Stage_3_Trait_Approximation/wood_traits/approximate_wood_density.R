#!/usr/bin/env Rscript
# Approximate wood density using hierarchical approach:
# 1. Use measured values (TraitID 4) when available
# 2. Use family-level averages from medfate
# 3. Use default value (0.652 g/cm³) for families not in table

suppressPackageStartupMessages({
  library(data.table)
})

cat("=== WOOD DENSITY APPROXIMATION ===\n")
cat("Hierarchical approach: Measured > Family > Default\n\n")

# Load data
cat("Loading data...\n")
try_numeric <- fread("data/output/eive_numeric_trait_matrix.csv")
try_families <- fread("data/output/try_species_families.csv")
family_wd <- fread("src/Stage_3_Trait_Approximation/data/family_wood_density.csv")

# Check if wood density column exists
wd_col <- "4"  # TraitID for wood density
if(wd_col %in% names(try_numeric)) {
  cat("  Found wood density measurements (TraitID 4)\n")
  setnames(try_numeric, wd_col, "wood_density_measured")
} else {
  cat("  No wood density column found, all values will be approximated\n")
  try_numeric$wood_density_measured <- NA_real_
}

# Merge with family information
cat("\nMerging with family data...\n")
data <- merge(try_numeric[, .(AccSpeciesID, AccSpeciesName, wood_density_measured)],
              try_families[, .(AccSpeciesID, family)],
              by = "AccSpeciesID",
              all.x = TRUE)

# Merge with family wood density values
data <- merge(data, family_wd, by.x = "family", by.y = "Family", all.x = TRUE)
setnames(data, "WoodDensity", "wood_density_family")

# Create hierarchical approximation
cat("\nApplying hierarchical approximation...\n")
default_wd <- 0.652  # Default from medfate

data[, wood_density_final := fifelse(
  !is.na(wood_density_measured), wood_density_measured,
  fifelse(!is.na(wood_density_family), wood_density_family, default_wd)
)]

# Track source of values
data[, wood_density_source := fifelse(
  !is.na(wood_density_measured), "measured",
  fifelse(!is.na(wood_density_family), "family", "default")
)]

# Calculate statistics
cat("\n=== APPROXIMATION STATISTICS ===\n")
source_counts <- data[, .N, by = wood_density_source]
setorder(source_counts, -N)
for(i in 1:nrow(source_counts)) {
  cat(sprintf("  %-10s: %4d species (%.1f%%)\n", 
              source_counts$wood_density_source[i],
              source_counts$N[i],
              100 * source_counts$N[i] / nrow(data)))
}

# Summary statistics
cat("\n=== WOOD DENSITY DISTRIBUTION ===\n")
cat(sprintf("  Mean:   %.3f g/cm³\n", mean(data$wood_density_final)))
cat(sprintf("  Median: %.3f g/cm³\n", median(data$wood_density_final)))
cat(sprintf("  Range:  %.3f - %.3f g/cm³\n", 
            min(data$wood_density_final), max(data$wood_density_final)))

# Distribution by source
cat("\nMean values by source:\n")
mean_by_source <- data[, .(mean_wd = mean(wood_density_final), .N), by = wood_density_source]
for(i in 1:nrow(mean_by_source)) {
  cat(sprintf("  %-10s: %.3f g/cm³ (n=%d)\n", 
              mean_by_source$wood_density_source[i],
              mean_by_source$mean_wd[i],
              mean_by_source$N[i]))
}

# Check families using default
families_using_default <- unique(data[wood_density_source == "default"]$family)
if(length(families_using_default) > 0) {
  cat("\n=== FAMILIES USING DEFAULT ===\n")
  for(fam in families_using_default[!is.na(families_using_default)]) {
    n_species <- sum(data$family == fam & data$wood_density_source == "default", na.rm = TRUE)
    cat(sprintf("  %-25s: %d species\n", fam, n_species))
  }
}

# Create output dataset with approximations
cat("\n💾 Saving approximated wood density...\n")
output <- data[, .(
  AccSpeciesID,
  AccSpeciesName,
  family,
  wood_density_measured,
  wood_density_family,
  wood_density_final,
  wood_density_source
)]
setorder(output, AccSpeciesID)

# Save full dataset
output_file <- "src/Stage_3_Trait_Approximation/wood_traits/wood_density_approximated.csv"
fwrite(output, output_file)
cat(sprintf("  Full dataset: %s\n", output_file))

# Save summary
summary_file <- "src/Stage_3_Trait_Approximation/wood_traits/wood_density_summary.csv"
summary_data <- data.table(
  metric = c("n_total", "n_measured", "n_family", "n_default", 
             "mean_overall", "median_overall", "min_overall", "max_overall"),
  value = c(nrow(data), 
            sum(data$wood_density_source == "measured"),
            sum(data$wood_density_source == "family"),
            sum(data$wood_density_source == "default"),
            mean(data$wood_density_final),
            median(data$wood_density_final),
            min(data$wood_density_final),
            max(data$wood_density_final))
)
fwrite(summary_data, summary_file)
cat(sprintf("  Summary: %s\n", summary_file))

# Create simplified output for merging back
simple_output <- data[, .(AccSpeciesID, 
                          APPROX_wood_density = wood_density_final,
                          APPROX_wood_density_source = wood_density_source)]
simple_file <- "src/Stage_3_Trait_Approximation/wood_traits/wood_density_for_merge.csv"
fwrite(simple_output, simple_file)
cat(sprintf("  For merging: %s\n", simple_file))

cat("\n✅ WOOD DENSITY APPROXIMATION COMPLETE!\n")
cat(sprintf("All %d species now have wood density values.\n", nrow(data)))