#!/usr/bin/env Rscript
#' Simplified Vernacular Name Assignment Pipeline
#'
#' Assigns REAL vernacular names to both plants and beneficial organisms
#' using hierarchical priority-based matching.
#'
#' Priority order (most specific to least specific):
#'   P1: iNaturalist species vernaculars (all 61 languages - dynamically loaded)
#'   P2: ITIS family vernaculars (English only)
#'
#' Languages: All 61 languages from iNaturalist Darwin Core export, including:
#'   Major: en, zh, ja, ru, cs, fi, fr, es, de, pt, nl, pl, it, sv, nb, da, ko, hu, lt, th, etc.
#'
#' NOTE: Synthetic derived categories (P2/P4 word frequency) have been removed.
#' Animal categorization is now handled by Phase 2 (Kimi AI pipeline).
#'
#' Author: Claude Code
#' Date: 2025-11-16

suppressPackageStartupMessages({
  library(duckdb)
  library(dplyr)
  library(arrow)
})

cat("=== Simplified Vernacular Name Assignment Pipeline ===\n")
cat("(Vernaculars only - no derived categories)\n\n")
start_time <- Sys.time()

# ============================================================================
# Configuration
# ============================================================================

DATA_DIR <- "/home/olier/ellenberg/data"
OUTPUT_DIR <- file.path(DATA_DIR, "taxonomy")

# Input files
PLANT_FILE <- "/home/olier/ellenberg/shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv"
ORGANISM_FILE <- file.path(DATA_DIR, "taxonomy/organisms_with_taxonomy_11711.parquet")  # From Phase 0
INAT_TAXA_FILE <- file.path(DATA_DIR, "inaturalist/taxa.csv")
INAT_VERNACULARS_FILE <- file.path(OUTPUT_DIR, "inat_vernaculars_all_languages.parquet")

# ITIS family vernaculars (applies to both plants and animals)
FAMILY_ITIS_FILE <- file.path(OUTPUT_DIR, "family_vernacular_names_itis.parquet")

# Output files
PLANT_OUTPUT <- file.path(OUTPUT_DIR, "plants_vernacular_final.parquet")
ORGANISM_OUTPUT <- file.path(OUTPUT_DIR, "organisms_vernacular_final.parquet")
COMBINED_OUTPUT <- file.path(OUTPUT_DIR, "all_taxa_vernacular_final.parquet")

# ============================================================================
# Helper Functions
# ============================================================================

#' Apply priority-based vernacular matching (P1 + P2 only)
#'
#' @param df Data frame with species names (must have 'scientific_name' column)
#' @param family_col Name of family column
#' @param con DuckDB connection
#' @return Data frame with vernacular assignments
assign_vernaculars <- function(df, family_col = "family", con) {

  cat(sprintf("  Processing %s taxa...\n", format(nrow(df), big.mark = ",")))

  # Register input dataframe in DuckDB
  duckdb_register(con, "input_taxa", df)

  # Get all language columns from inat_matched view
  inat_cols <- dbGetQuery(con, "
    SELECT column_name
    FROM (DESCRIBE inat_matched)
    WHERE column_name LIKE 'vernacular_name_%'
    ORDER BY column_name
  ")$column_name

  # Generate language column selections (iNat only for non-English)
  lang_selects <- sapply(inat_cols, function(col) {
    if (col == "vernacular_name_en") {
      # English: merge iNat + ITIS with priority
      sprintf("COALESCE(inat.%s, fv_itis.vernacular_names) as %s", col, col)
    } else {
      # Other languages: iNat only (ITIS is English-only)
      sprintf("inat.%s", col)
    }
  })

  # Build SQL query with language columns and family column
  sql_query <- sprintf("
    SELECT
      t.*,
      inat.inat_taxon_id,

      -- Vernacular source (only P1 and P2)
      CASE
        WHEN inat.inat_taxon_id IS NOT NULL AND inat.n_vernaculars > 0
          THEN 'P1_inat_species'
        WHEN fv_itis.vernacular_names IS NOT NULL
          THEN 'P2_itis_family'
        ELSE 'uncategorized'
      END as vernacular_source,

      -- All language columns (dynamically generated)
      %s,

      -- Total count of vernacular names
      CASE
        WHEN inat.vernacular_name_en IS NOT NULL THEN inat.n_vernaculars
        WHEN fv_itis.vernacular_names IS NOT NULL THEN fv_itis.n_names
        ELSE 0
      END as n_vernaculars_total

    FROM input_taxa t
    LEFT JOIN inat_matched inat
      ON LOWER(t.scientific_name) = LOWER(inat.organism_name)
    LEFT JOIN family_itis fv_itis
      ON CAST(t.%s AS VARCHAR) = fv_itis.family
  ", paste(lang_selects, collapse = ",\n      "), family_col)

  # Apply hierarchical matching via SQL (P1 iNat + P2 ITIS only)
  result <- dbGetQuery(con, sql_query)

  # Unregister
  duckdb_unregister(con, "input_taxa")

  return(as_tibble(result))
}

#' Print coverage summary
print_coverage <- function(df, label) {
  n_total <- nrow(df)
  # Count as categorized if source is not 'uncategorized' (may have vernaculars in non-English languages)
  n_categorized <- sum(df$vernacular_source != 'uncategorized')
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
    for (source in c("P1_inat_species", "P2_itis_family", "uncategorized")) {
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
  WHERE 
    -- Filter out known code lexicons
    lexicon NOT IN (
      'Aou 4 Letter Codes', 
      'Vermont Flora Codes', 
      'U.S.D.A. Symbol', 
      'Aou 6 Letter Codes', 
      '6 Letter Flora Codes', 
      'Usda Plant Code', 
      'Ontario Plant Codes'
    )
    -- Safety net: Filter out 4+ letter uppercase codes (with optional numbers)
    -- This catches ~1,800 codes mislabeled as 'English' (e.g., 'LONJAP')
    AND NOT regexp_matches(vernacularName, '^[A-Z]{4,}[0-9]*$')
", INAT_VERNACULARS_FILE))

# Create matched view (taxa + vernaculars by language - wide format)
cat("  Creating iNaturalist matched view...\n")

# Get all unique languages dynamically
all_languages <- dbGetQuery(con, "
  SELECT DISTINCT language
  FROM inat_vernaculars
  WHERE language IS NOT NULL
  ORDER BY language
")$language

cat(sprintf("  Found %d languages in vernacular data\n", length(all_languages)))

# Language mappings for combined codes
# en: English only (removed 'und' to prevent pollution with codes like ACESA1)
# zh + zh-CN -> zh (Chinese variants)
language_mappings <- list(
  en = c("en"),
  zh = c("zh", "zh-CN")
)

# Generate SQL for each language column
language_columns <- c()
for (lang in all_languages) {
  if (lang == "und") next  # Skip 'und', it's merged with 'en'
  if (lang == "zh-CN") next  # Skip 'zh-CN', it's merged with 'zh'

  # Check if this language has a mapping
  lang_codes <- if (lang %in% names(language_mappings)) {
    paste0("'", paste(language_mappings[[lang]], collapse = "', '"), "'")
  } else {
    paste0("'", lang, "'")
  }

  # Sanitize language code for column name (replace hyphens with underscores)
  col_name <- gsub("-", "_", lang)

  sql_fragment <- sprintf(
    "STRING_AGG(CASE WHEN v.language IN (%s) AND NOT regexp_matches(v.vernacularName, '^[A-Z]{4,}[0-9]*$') THEN v.vernacularName END, '; ')\n      FILTER (WHERE v.language IN (%s) AND NOT regexp_matches(v.vernacularName, '^[A-Z]{4,}[0-9]*$')) as vernacular_name_%s",
    lang_codes, lang_codes, col_name
  )
  language_columns <- c(language_columns, sql_fragment)
}

# Build complete SQL query with deduplication by taxonomic rank
sql_query <- sprintf("
  CREATE OR REPLACE VIEW inat_matched AS
  WITH ranked_taxa AS (
    SELECT
      t.scientificName as organism_name,
      t.id as inat_taxon_id,
      t.taxonRank,
      -- Wide format: separate column per language (all %d languages)
      %s,
      -- Total count of vernacular names (all languages)
      COUNT(DISTINCT v.vernacularName) as n_vernaculars,
      -- Rank priority: prefer species > variety > subspecies > genus > others
      ROW_NUMBER() OVER (
        PARTITION BY t.scientificName
        ORDER BY
          CASE t.taxonRank
            WHEN 'species' THEN 1
            WHEN 'variety' THEN 2
            WHEN 'subspecies' THEN 3
            WHEN 'genus' THEN 4
            WHEN 'form' THEN 5
            ELSE 99
          END,
          COUNT(DISTINCT v.vernacularName) DESC  -- Tie-break: prefer more vernaculars
      ) as rank_priority
    FROM inat_taxa t
    LEFT JOIN inat_vernaculars v ON t.id = v.id
    GROUP BY t.scientificName, t.id, t.taxonRank
  )
  SELECT
    organism_name,
    inat_taxon_id,
    taxonRank,
    %s,
    n_vernaculars
  FROM ranked_taxa
  WHERE rank_priority = 1
", length(language_columns), paste(language_columns, collapse = ",\n      "),
   paste(paste0("vernacular_name_", gsub("-", "_", setdiff(all_languages, c("und", "zh-CN")))), collapse = ",\n    "))

dbExecute(con, sql_query)

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

# ============================================================================
# Load Input Datasets
# ============================================================================

cat("\nStep 3: Load input datasets\n")
cat("  Loading plants...\n")
plants_raw <- dbGetQuery(con, sprintf("
  SELECT DISTINCT
    wfo_scientific_name as scientific_name,
    SPLIT_PART(wfo_scientific_name, ' ', 1) as genus,
    family
  FROM read_csv('%s', all_varchar=true, sample_size=-1)
  WHERE wfo_scientific_name IS NOT NULL
", PLANT_FILE))

cat(sprintf("    → %s plant species\n", format(nrow(plants_raw), big.mark = ",")))

cat("  Loading organisms...\n")
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

cat(sprintf("    → %s beneficial organisms\n", format(nrow(organisms_raw), big.mark = ",")))

# ============================================================================
# Assign Vernaculars
# ============================================================================

cat("\nStep 4: Assign vernaculars\n")
cat("Processing plants...\n")
plants_final <- assign_vernaculars(plants_raw,
                                   family_col = "family",
                                   con = con)

# Add organism type
plants_final$organism_type <- "plant"

print_coverage(plants_final, "PLANTS")

cat("\nProcessing organisms...\n")
organisms_final <- assign_vernaculars(organisms_raw,
                                     family_col = "family",
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
  n_categorized <- sum(role_df$vernacular_source != 'uncategorized')
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
total_categorized <- sum(combined$vernacular_source != 'uncategorized')
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
