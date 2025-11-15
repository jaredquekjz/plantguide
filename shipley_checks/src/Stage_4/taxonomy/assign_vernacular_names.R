#!/usr/bin/env Rscript
#' Canonical Vernacular Name Assignment Pipeline
#'
#' Assigns vernacular names to both plants and beneficial organisms using
#' hierarchical priority-based matching
#'
#' Priority order (most specific to least specific):
#'   P1: iNaturalist species (all languages)
#'   P2: Derived genus categories (word frequency)
#'   P3: ITIS family vernaculars
#'   P4: Derived family categories (word frequency)
#'
#' Author: Claude Code
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(duckdb)
  library(dplyr)
  library(arrow)
})

cat("=== Canonical Vernacular Name Assignment Pipeline ===\n\n")
start_time <- Sys.time()

# ============================================================================
# Configuration
# ============================================================================

DATA_DIR <- "/home/olier/ellenberg/data"
OUTPUT_DIR <- file.path(DATA_DIR, "taxonomy")

# Input files
PLANT_FILE <- "/home/olier/ellenberg/shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.csv"
ORGANISM_FILE <- file.path(DATA_DIR, "taxonomy/organism_taxonomy_enriched.parquet")
INAT_TAXA_FILE <- file.path(DATA_DIR, "inaturalist/taxa.csv")
INAT_VERNACULARS_FILE <- file.path(OUTPUT_DIR, "inat_vernaculars_all_languages.parquet")

# Animal-specific derived categories
ANIMAL_GENUS_DERIVED_FILE <- file.path(OUTPUT_DIR, "animal_genus_vernaculars_derived.parquet")
ANIMAL_FAMILY_DERIVED_FILE <- file.path(OUTPUT_DIR, "animal_family_vernaculars_derived.parquet")

# Plant-specific derived categories
PLANT_GENUS_DERIVED_FILE <- file.path(OUTPUT_DIR, "plant_genus_vernaculars_derived.parquet")
PLANT_FAMILY_DERIVED_FILE <- file.path(OUTPUT_DIR, "plant_family_vernaculars_derived.parquet")

# ITIS family (applies to both)
FAMILY_ITIS_FILE <- file.path(OUTPUT_DIR, "family_vernacular_names_itis.parquet")

# Output files
PLANT_OUTPUT <- file.path(OUTPUT_DIR, "plants_vernacular_final.parquet")
ORGANISM_OUTPUT <- file.path(OUTPUT_DIR, "organisms_vernacular_final.parquet")
COMBINED_OUTPUT <- file.path(OUTPUT_DIR, "all_taxa_vernacular_final.parquet")

# ============================================================================
# Helper Functions
# ============================================================================

#' Apply priority-based vernacular matching
#'
#' @param df Data frame with species names (must have 'scientific_name' column)
#' @param genus_col Name of genus column
#' @param family_col Name of family column
#' @param genus_view Name of genus derived view to use
#' @param family_view Name of family derived view to use
#' @param con DuckDB connection
#' @return Data frame with vernacular assignments
assign_vernaculars <- function(df, genus_col = "genus", family_col = "family",
                                genus_view = "genus_derived",
                                family_view = "family_derived",
                                con) {

  cat(sprintf("  Processing %s taxa...\n", format(nrow(df), big.mark = ",")))

  # Register input dataframe in DuckDB
  duckdb_register(con, "input_taxa", df)

  # Apply hierarchical matching via SQL with language metadata
  result <- dbGetQuery(con, sprintf("
    SELECT
      t.*,
      inat.inat_taxon_id,
      inat.inat_all_vernaculars,
      inat.n_vernaculars,
      gv.derived_vernacular as genus_derived_vernacular,
      fv_itis.vernacular_names as itis_family_vernacular,
      fv_derived.derived_vernacular as family_derived_vernacular,
      -- Vernacular source (priority-based)
      CASE
        WHEN inat.inat_all_vernaculars IS NOT NULL THEN 'P1_inat_species'
        WHEN gv.derived_vernacular IS NOT NULL THEN 'P2_derived_genus'
        WHEN fv_itis.vernacular_names IS NOT NULL THEN 'P3_itis_family'
        WHEN fv_derived.derived_vernacular IS NOT NULL THEN 'P4_derived_family'
        ELSE 'uncategorized'
      END as vernacular_source,
      -- Vernacular name (all languages)
      COALESCE(
        inat.inat_all_vernaculars,
        gv.derived_vernacular,
        fv_itis.vernacular_names,
        fv_derived.derived_vernacular
      ) as vernacular_name,
      -- NEW: English vernacular name
      CASE
        WHEN inat.inat_vernaculars_english IS NOT NULL THEN inat.inat_vernaculars_english
        WHEN gv.derived_vernacular IS NOT NULL THEN gv.derived_vernacular
        WHEN fv_itis.vernacular_names IS NOT NULL THEN fv_itis.vernacular_names
        WHEN fv_derived.derived_vernacular IS NOT NULL THEN fv_derived.derived_vernacular
        ELSE NULL
      END as vernacular_name_english,
      -- NEW: Primary language (ISO 639-1)
      CASE
        WHEN inat.inat_language_primary IS NOT NULL THEN inat.inat_language_primary
        WHEN gv.derived_vernacular IS NOT NULL THEN 'en'
        WHEN fv_itis.vernacular_names IS NOT NULL THEN 'en'
        WHEN fv_derived.derived_vernacular IS NOT NULL THEN 'en'
        ELSE NULL
      END as vernacular_language_primary,
      -- NEW: All languages (semicolon-separated)
      CASE
        WHEN inat.inat_languages_all IS NOT NULL THEN inat.inat_languages_all
        WHEN gv.derived_vernacular IS NOT NULL THEN 'en'
        WHEN fv_itis.vernacular_names IS NOT NULL THEN 'en'
        WHEN fv_derived.derived_vernacular IS NOT NULL THEN 'en'
        ELSE NULL
      END as vernacular_languages_all,
      -- NEW: Total count of vernacular names (based on matched source)
      CASE
        WHEN inat.inat_all_vernaculars IS NOT NULL THEN inat.n_vernaculars
        WHEN gv.derived_vernacular IS NOT NULL THEN 1
        WHEN fv_itis.vernacular_names IS NOT NULL THEN fv_itis.n_names
        WHEN fv_derived.derived_vernacular IS NOT NULL THEN 1
        ELSE 0
      END as n_vernaculars_total
    FROM input_taxa t
    LEFT JOIN inat_matched inat
      ON LOWER(t.scientific_name) = LOWER(inat.organism_name)
    LEFT JOIN %s gv
      ON CAST(t.%s AS VARCHAR) = gv.genus
    LEFT JOIN family_itis fv_itis
      ON CAST(t.%s AS VARCHAR) = fv_itis.family
    LEFT JOIN %s fv_derived
      ON CAST(t.%s AS VARCHAR) = fv_derived.family
  ", genus_view, genus_col, family_col, family_view, family_col))

  # Unregister
  duckdb_unregister(con, "input_taxa")

  return(as_tibble(result))
}

#' Print coverage summary
print_coverage <- function(df, label) {
  n_total <- nrow(df)
  n_categorized <- sum(!is.na(df$vernacular_name))
  pct_categorized <- 100 * n_categorized / n_total

  cat(sprintf("\n=== %s Coverage ===\n", label))
  cat(sprintf("Total: %s\n", format(n_total, big.mark = ",")))
  cat(sprintf("Categorized: %s (%.1f%%)\n",
              format(n_categorized, big.mark = ","), pct_categorized))
  cat(sprintf("Uncategorized: %s (%.1f%%)\n",
              format(n_total - n_categorized, big.mark = ","),
              100 - pct_categorized))

  # Breakdown by source
  if (n_categorized > 0) {
    cat("\nBreakdown by source:\n")
    source_counts <- table(df$vernacular_source)
    for (source in c("P1_inat_species", "P2_derived_genus", "P3_itis_family",
                     "P4_derived_family", "uncategorized")) {
      if (source %in% names(source_counts)) {
        count <- source_counts[source]
        pct <- 100 * count / n_total
        cat(sprintf("  %s: %s (%.1f%%)\n",
                    source, format(count, big.mark = ","), pct))
      }
    }
  }
}

# ============================================================================
# Main Pipeline
# ============================================================================

cat("Step 1: Initialize DuckDB connection\n")
con <- dbConnect(duckdb::duckdb())

cat("\nStep 2: Load reference data\n")

# Load iNaturalist taxa
cat("  Loading iNaturalist taxa...\n")
dbExecute(con, sprintf("
  CREATE OR REPLACE VIEW inat_taxa AS
  SELECT * FROM read_csv('%s', ignore_errors=true)
", INAT_TAXA_FILE))

# Load iNaturalist vernaculars (all languages)
cat("  Loading iNaturalist vernaculars (all languages)...\n")
dbExecute(con, sprintf("
  CREATE OR REPLACE VIEW inat_vernaculars AS
  SELECT * FROM read_parquet('%s')
", INAT_VERNACULARS_FILE))

# Create matched view (taxa + vernaculars aggregated with language metadata)
cat("  Creating iNaturalist matched view...\n")
dbExecute(con, "
  CREATE OR REPLACE VIEW inat_matched AS
  SELECT
    t.scientificName as organism_name,
    t.id as inat_taxon_id,
    t.taxonRank,
    -- All vernacular names (ordered)
    STRING_AGG(DISTINCT v.vernacularName, '; ' ORDER BY v.vernacularName) as inat_all_vernaculars,
    -- English vernacular names only (language='en' or 'und')
    STRING_AGG(CASE WHEN v.language IN ('en', 'und') THEN v.vernacularName END, '; ')
      FILTER (WHERE v.language IN ('en', 'und')) as inat_vernaculars_english,
    -- All languages (ISO 639-1 codes, ordered)
    STRING_AGG(DISTINCT v.language, '; ' ORDER BY v.language)
      FILTER (WHERE v.language IS NOT NULL) as inat_languages_all,
    -- Primary language (prefer 'en', else most frequent by count)
    MODE(v.language) FILTER (WHERE v.language IS NOT NULL) as inat_language_primary,
    -- Count of vernacular names
    COUNT(DISTINCT v.vernacularName) as n_vernaculars
  FROM inat_taxa t
  LEFT JOIN inat_vernaculars v ON t.id = v.id
  GROUP BY t.scientificName, t.id, t.taxonRank
")

# Load animal derived genus categories
cat("  Loading animal derived genus categories...\n")
if (file.exists(ANIMAL_GENUS_DERIVED_FILE)) {
  dbExecute(con, sprintf("
    CREATE OR REPLACE VIEW genus_derived_animal AS
    SELECT
      CAST(genus AS VARCHAR) as genus,
      derived_vernacular,
      n_species_with_vernaculars,
      dominant_category,
      category_percentage
    FROM read_parquet('%s')
  ", ANIMAL_GENUS_DERIVED_FILE))
} else {
  cat("    (File not found - creating empty view)\n")
  dbExecute(con, "
    CREATE OR REPLACE VIEW genus_derived_animal AS
    SELECT
      CAST(NULL AS VARCHAR) as genus,
      CAST(NULL AS VARCHAR) as derived_vernacular,
      CAST(NULL AS INTEGER) as n_species_with_vernaculars,
      CAST(NULL AS VARCHAR) as dominant_category,
      CAST(NULL AS DOUBLE) as category_percentage
    WHERE FALSE
  ")
}

# Load plant derived genus categories
cat("  Loading plant derived genus categories...\n")
if (file.exists(PLANT_GENUS_DERIVED_FILE)) {
  dbExecute(con, sprintf("
    CREATE OR REPLACE VIEW genus_derived_plant AS
    SELECT
      CAST(genus AS VARCHAR) as genus,
      derived_vernacular,
      n_species_with_vernaculars,
      dominant_category,
      category_percentage
    FROM read_parquet('%s')
  ", PLANT_GENUS_DERIVED_FILE))
} else {
  cat("    (File not found - creating empty view)\n")
  dbExecute(con, "
    CREATE OR REPLACE VIEW genus_derived_plant AS
    SELECT
      CAST(NULL AS VARCHAR) as genus,
      CAST(NULL AS VARCHAR) as derived_vernacular,
      CAST(NULL AS INTEGER) as n_species_with_vernaculars,
      CAST(NULL AS VARCHAR) as dominant_category,
      CAST(NULL AS DOUBLE) as category_percentage
    WHERE FALSE
  ")
}

# Load ITIS family vernaculars (applies to both plants and animals)
cat("  Loading ITIS family vernaculars...\n")
dbExecute(con, sprintf("
  CREATE OR REPLACE VIEW family_itis AS
  SELECT
    CAST(family AS VARCHAR) as family,
    vernacular_names,
    n_names
  FROM read_parquet('%s')
", FAMILY_ITIS_FILE))

# Load animal derived family categories
cat("  Loading animal derived family categories...\n")
if (file.exists(ANIMAL_FAMILY_DERIVED_FILE)) {
  dbExecute(con, sprintf("
    CREATE OR REPLACE VIEW family_derived_animal AS
    SELECT
      CAST(family AS VARCHAR) as family,
      derived_vernacular,
      n_species_with_vernaculars,
      dominant_category,
      dominant_score
    FROM read_parquet('%s')
  ", ANIMAL_FAMILY_DERIVED_FILE))
} else {
  cat("    (File not found - creating empty view)\n")
  dbExecute(con, "
    CREATE OR REPLACE VIEW family_derived_animal AS
    SELECT
      CAST(NULL AS VARCHAR) as family,
      CAST(NULL AS VARCHAR) as derived_vernacular,
      CAST(NULL AS INTEGER) as n_species_with_vernaculars,
      CAST(NULL AS VARCHAR) as dominant_category,
      CAST(NULL AS DOUBLE) as dominant_score
    WHERE FALSE
  ")
}

# Load plant derived family categories
cat("  Loading plant derived family categories...\n")
if (file.exists(PLANT_FAMILY_DERIVED_FILE)) {
  dbExecute(con, sprintf("
    CREATE OR REPLACE VIEW family_derived_plant AS
    SELECT
      CAST(family AS VARCHAR) as family,
      derived_vernacular,
      n_species_with_vernaculars,
      dominant_category,
      dominant_score
    FROM read_parquet('%s')
  ", PLANT_FAMILY_DERIVED_FILE))
} else {
  cat("    (File not found - creating empty view)\n")
  dbExecute(con, "
    CREATE OR REPLACE VIEW family_derived_plant AS
    SELECT
      CAST(NULL AS VARCHAR) as family,
      CAST(NULL AS VARCHAR) as derived_vernacular,
      CAST(NULL AS INTEGER) as n_species_with_vernaculars,
      CAST(NULL AS VARCHAR) as dominant_category,
      CAST(NULL AS DOUBLE) as dominant_score
    WHERE FALSE
  ")
}

# ============================================================================
# Process Plants
# ============================================================================

cat(paste0("\n", strrep("=", 80), "\n"))
cat("PLANTS\n")
cat(paste0(strrep("=", 80), "\n"))

cat("\nStep 3: Load plant data\n")
plants_raw <- dbGetQuery(con, sprintf("
  SELECT DISTINCT
    wfo_scientific_name as scientific_name,
    SPLIT_PART(wfo_scientific_name, ' ', 1) as genus,
    family
  FROM read_csv('%s', all_varchar=true, sample_size=-1)
  WHERE wfo_scientific_name IS NOT NULL
", PLANT_FILE))

cat(sprintf("  Loaded %s unique plant species\n", format(nrow(plants_raw), big.mark = ",")))

cat("\nStep 4: Assign vernaculars to plants\n")
plants_final <- assign_vernaculars(plants_raw,
                                   genus_col = "genus",
                                   family_col = "family",
                                   genus_view = "genus_derived_plant",
                                   family_view = "family_derived_plant",
                                   con = con)

# Add organism type
plants_final$organism_type <- "plant"

print_coverage(plants_final, "PLANTS")

# ============================================================================
# Process Beneficial Organisms
# ============================================================================

cat(paste0("\n", strrep("=", 80), "\n"))
cat("BENEFICIAL ORGANISMS\n")
cat(paste0(strrep("=", 80), "\n"))

cat("\nStep 5: Load beneficial organism data\n")
organisms_raw <- dbGetQuery(con, sprintf("
  SELECT
    organism_name as scientific_name,
    genus,
    family,
    \"order\" as order_name,
    class,
    kingdom,
    is_herbivore,
    is_pollinator,
    is_predator
  FROM read_parquet('%s')
", ORGANISM_FILE))

cat(sprintf("  Loaded %s beneficial organisms\n", format(nrow(organisms_raw), big.mark = ",")))

cat("\nStep 6: Assign vernaculars to organisms\n")
organisms_final <- assign_vernaculars(organisms_raw,
                                     genus_col = "genus",
                                     family_col = "family",
                                     genus_view = "genus_derived_animal",
                                     family_view = "family_derived_animal",
                                     con = con)

# Add organism type
organisms_final$organism_type <- "beneficial_organism"

print_coverage(organisms_final, "BENEFICIAL ORGANISMS")

# Coverage by role
cat("\n--- Coverage by Ecological Role ---\n")
for (role in c("is_herbivore", "is_pollinator", "is_predator")) {
  role_name <- gsub("is_", "", role)
  role_name <- paste0(toupper(substring(role_name, 1, 1)),
                      substring(role_name, 2))
  role_name <- paste0(role_name, "s")

  role_df <- organisms_final[organisms_final[[role]] == TRUE, ]
  n_total <- nrow(role_df)
  n_categorized <- sum(!is.na(role_df$vernacular_name))
  pct_categorized <- 100 * n_categorized / n_total
  pct_other <- 100 - pct_categorized

  cat(sprintf("%s: %s / %s categorized (%.1f%% → %.1f%% 'Other')\n",
              role_name,
              format(n_categorized, big.mark = ","),
              format(n_total, big.mark = ","),
              pct_categorized,
              pct_other))
}

# ============================================================================
# Save Results
# ============================================================================

cat(paste0("\n", strrep("=", 80), "\n"))
cat("SAVING RESULTS\n")
cat(paste0(strrep("=", 80), "\n\n"))

cat(sprintf("Writing plants to: %s\n", PLANT_OUTPUT))
write_parquet(plants_final, PLANT_OUTPUT)

cat(sprintf("Writing organisms to: %s\n", ORGANISM_OUTPUT))
write_parquet(organisms_final, ORGANISM_OUTPUT)

# Combine both datasets (ensure type compatibility)
cat(sprintf("Writing combined dataset to: %s\n", COMBINED_OUTPUT))
plants_final$family <- as.character(plants_final$family)
organisms_final$family <- as.character(organisms_final$family)
plants_final$genus <- as.character(plants_final$genus)
organisms_final$genus <- as.character(organisms_final$genus)
combined <- bind_rows(plants_final, organisms_final)
write_parquet(combined, COMBINED_OUTPUT)

# ============================================================================
# Final Summary
# ============================================================================

cat(paste0("\n", strrep("=", 80), "\n"))
cat("FINAL SUMMARY\n")
cat(paste0(strrep("=", 80), "\n\n"))

total_taxa <- nrow(combined)
total_categorized <- sum(!is.na(combined$vernacular_name))
pct_total <- 100 * total_categorized / total_taxa

cat(sprintf("Total taxa processed: %s\n", format(total_taxa, big.mark = ",")))
cat(sprintf("  Plants: %s\n", format(nrow(plants_final), big.mark = ",")))
cat(sprintf("  Beneficial organisms: %s\n", format(nrow(organisms_final), big.mark = ",")))
cat(sprintf("\nTotal categorized: %s (%.1f%%)\n",
            format(total_categorized, big.mark = ","), pct_total))
cat(sprintf("Total uncategorized: %s (%.1f%%)\n",
            format(total_taxa - total_categorized, big.mark = ","),
            100 - pct_total))

# Cleanup
dbDisconnect(con, shutdown = TRUE)

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
cat(sprintf("\n✓ Pipeline completed in %.1f seconds\n", elapsed))
