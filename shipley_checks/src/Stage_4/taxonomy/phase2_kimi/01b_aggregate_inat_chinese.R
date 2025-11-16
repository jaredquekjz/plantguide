#!/usr/bin/env Rscript
#' Aggregate iNaturalist Chinese Vernacular Names by Genus
#'
#' Joins iNaturalist vernaculars with target genera and aggregates
#' Chinese vernacular names by genus for vector classification.
#'
#' Input:
#'   - data/taxonomy/target_genera.parquet (combined organisms + plants)
#'   - data/inaturalist/taxa.csv (iNaturalist taxonomy)
#'   - data/taxonomy/inat_vernaculars_all_languages.parquet
#'
#' Output:
#'   - data/taxonomy/genus_vernacular_aggregations_chinese.parquet
#'
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(duckdb)
  library(dplyr)
  library(arrow)
})

cat("=", rep("=", 78), "\n", sep = "")
cat("Aggregating Chinese iNaturalist Vernaculars by Genus\n")
cat("=", rep("=", 78), "\n\n", sep = "")

# ============================================================================
# Configuration
# ============================================================================

TARGET_GENERA_FILE <- "/home/olier/ellenberg/data/taxonomy/target_genera.parquet"
TAXA_FILE <- "/home/olier/ellenberg/data/inaturalist/taxa.csv"
VERNACULARS_FILE <- "/home/olier/ellenberg/data/taxonomy/inat_vernaculars_all_languages.parquet"
OUTPUT_FILE <- "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations_chinese.parquet"

# ============================================================================
# Connect to DuckDB
# ============================================================================

cat("Connecting to DuckDB...\n")
con <- dbConnect(duckdb::duckdb())

# ============================================================================
# Load and Process Data
# ============================================================================

cat("\nStep 1: Loading target genera...\n")

# Load target genera (combined from organisms + plants)
target_genera_query <- sprintf("
  SELECT DISTINCT genus
  FROM read_parquet('%s')
  WHERE genus IS NOT NULL
", TARGET_GENERA_FILE)

target_genera <- dbGetQuery(con, target_genera_query)
cat(sprintf("  Loaded %d target genera\n", nrow(target_genera)))

# Register as temp table
duckdb::duckdb_register(con, "target_genera", target_genera)

cat("\nStep 2: Loading iNaturalist taxa...\n")

# Load taxa with genus extraction
taxa_query <- sprintf("
  SELECT
    id AS taxon_id,
    scientificName,
    CASE
      WHEN TRIM(SPLIT_PART(scientificName, ' ', 1)) != ''
      THEN TRIM(SPLIT_PART(scientificName, ' ', 1))
      ELSE NULL
    END AS genus,
    kingdom
  FROM read_csv('%s', ignore_errors=true, header=true, auto_detect=true)
  WHERE scientificName IS NOT NULL
    AND TRIM(scientificName) != ''
", TAXA_FILE)

taxa <- dbGetQuery(con, taxa_query)
cat(sprintf("  Loaded %d taxa records\n", nrow(taxa)))

# Register as temp table
duckdb::duckdb_register(con, "taxa_temp", taxa)

cat("\nStep 3: Loading vernacular names...\n")

# Filter to Chinese vernaculars only (zh, zh-CN, zh-TW, zh-HK)
vernaculars_query <- sprintf("
  SELECT
    id AS taxon_id,
    vernacularName,
    language
  FROM read_parquet('%s')
  WHERE vernacularName IS NOT NULL
    AND language IS NOT NULL
    AND (language = 'zh'
         OR language = 'zh-CN'
         OR language = 'zh-TW'
         OR language = 'zh-HK')
", VERNACULARS_FILE)

vernaculars <- dbGetQuery(con, vernaculars_query)
cat(sprintf("  Loaded %d Chinese vernacular names\n", nrow(vernaculars)))

# Register as temp table
duckdb::duckdb_register(con, "vernaculars_temp", vernaculars)

cat("\nStep 4: Joining and aggregating by genus...\n")

# Join taxa with vernaculars, filter to target genera, then aggregate
join_query <- "
  SELECT
    t.genus,
    t.kingdom,
    v.language,
    v.vernacularName
  FROM taxa_temp t
  INNER JOIN vernaculars_temp v ON t.taxon_id = v.taxon_id
  INNER JOIN target_genera tg ON t.genus = tg.genus
  WHERE t.genus IS NOT NULL
"

joined_data <- dbGetQuery(con, join_query)
cat(sprintf("  Joined %d genus-vernacular pairs\n", nrow(joined_data)))

# Aggregate by genus
aggregation_query <- "
  SELECT
    genus,
    MAX(kingdom) AS kingdom,
    STRING_AGG(DISTINCT vernacularName, '; ' ORDER BY vernacularName) AS vernaculars_all,
    COUNT(*) AS n_vernaculars,
    COUNT(DISTINCT vernacularName) AS n_unique_vernaculars,
    COUNT(DISTINCT language) AS n_languages
  FROM joined_data
  GROUP BY genus
  ORDER BY genus
"

duckdb::duckdb_register(con, "joined_data", joined_data)
aggregated <- dbGetQuery(con, aggregation_query)

cat(sprintf("  Aggregated to %d genera with Chinese vernaculars\n", nrow(aggregated)))

# ============================================================================
# Summary Statistics
# ============================================================================

cat("\nSummary Statistics:\n")
cat(rep("-", 80), "\n", sep = "")

cat(sprintf("Total genera with Chinese vernaculars: %d\n", nrow(aggregated)))
cat(sprintf("Total Chinese vernacular names: %d\n", sum(aggregated$n_vernaculars)))
cat(sprintf("Unique Chinese vernacular names: %d\n", sum(aggregated$n_unique_vernaculars)))

cat("\nVernaculars per genus:\n")
quantiles <- quantile(aggregated$n_unique_vernaculars, probs = c(0.25, 0.5, 0.75, 0.9, 0.95))
cat(sprintf("  25%%: %.0f\n", quantiles[1]))
cat(sprintf("  50%% (median): %.0f\n", quantiles[2]))
cat(sprintf("  75%%: %.0f\n", quantiles[3]))
cat(sprintf("  90%%: %.0f\n", quantiles[4]))
cat(sprintf("  95%%: %.0f\n", quantiles[5]))
cat(sprintf("  Max: %d\n", max(aggregated$n_unique_vernaculars)))

cat("\nKingdom distribution:\n")
kingdom_summary <- aggregated %>%
  count(kingdom) %>%
  arrange(desc(n))
print(as.data.frame(kingdom_summary))

# ============================================================================
# Write Output
# ============================================================================

cat("\nWriting output...\n")
cat(sprintf("  Output: %s\n", OUTPUT_FILE))

write_parquet(aggregated, OUTPUT_FILE)

cat(sprintf("\n✓ Successfully wrote %d genera with Chinese vernaculars\n", nrow(aggregated)))

# ============================================================================
# Cleanup
# ============================================================================

dbDisconnect(con, shutdown = TRUE)

cat("\n", rep("=", 80), "\n", sep = "")
cat("Complete\n")
cat(rep("=", 80), "\n\n", sep = "")
