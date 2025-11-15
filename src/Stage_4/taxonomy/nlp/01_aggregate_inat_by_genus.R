#!/usr/bin/env Rscript
#' Aggregate iNaturalist Vernacular Names by Genus
#'
#' Joins iNaturalist taxa with vernacular names and aggregates by genus,
#' preserving language metadata for wide-format output.
#'
#' Input:
#'   - data/inaturalist/taxa.csv (taxonomic hierarchy)
#'   - data/taxonomy/inat_vernaculars_all_languages.parquet (vernacular names)
#'
#' Output:
#'   - data/taxonomy/genus_vernacular_aggregations.parquet
#'
#' Author: Claude Code
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(duckdb)
  library(dplyr)
  library(arrow)
  library(stringr)
})

cat("=", rep("=", 78), "\n", sep = "")
cat("Aggregating iNaturalist Vernaculars by Genus\n")
cat("=", rep("=", 78), "\n\n", sep = "")

# ============================================================================
# Configuration
# ============================================================================

DATA_DIR <- "/home/olier/ellenberg/data"
TAXA_FILE <- file.path(DATA_DIR, "inaturalist/taxa.csv")
VERNACULARS_FILE <- file.path(DATA_DIR, "taxonomy/inat_vernaculars_all_languages.parquet")
OUTPUT_FILE <- file.path(DATA_DIR, "taxonomy/genus_vernacular_aggregations.parquet")

# Verify input files exist
if (!file.exists(TAXA_FILE)) {
  stop("Taxa file not found: ", TAXA_FILE)
}
if (!file.exists(VERNACULARS_FILE)) {
  stop("Vernaculars file not found: ", VERNACULARS_FILE)
}

# ============================================================================
# Load Data with DuckDB
# ============================================================================

cat("Loading data...\n")

con <- dbConnect(duckdb::duckdb())

# Load taxa (only need genus and kingdom)
cat("  Reading taxa.csv...\n")
taxa_query <- sprintf("
  SELECT
    id AS taxon_id,
    genus,
    kingdom
  FROM read_csv('%s', ignore_errors=true, header=true, auto_detect=true)
  WHERE genus IS NOT NULL
    AND kingdom IN ('Animalia', 'Plantae')
", TAXA_FILE)

taxa <- dbGetQuery(con, taxa_query)
cat(sprintf("    → %s taxa with genus information\n", format(nrow(taxa), big.mark = ",")))

# Load vernaculars
cat("  Reading vernaculars parquet...\n")
vernaculars_query <- sprintf("
  SELECT
    id AS taxon_id,
    vernacularName,
    language
  FROM read_parquet('%s')
  WHERE vernacularName IS NOT NULL
    AND language IS NOT NULL
", VERNACULARS_FILE)

vernaculars <- dbGetQuery(con, vernaculars_query)
cat(sprintf("    → %s vernacular names\n", format(nrow(vernaculars), big.mark = ",")))

# ============================================================================
# Join Taxa with Vernaculars
# ============================================================================

cat("\nJoining taxa with vernaculars...\n")

# Register dataframes in DuckDB
dbExecute(con, "DROP TABLE IF EXISTS taxa_temp")
dbExecute(con, "DROP TABLE IF EXISTS vernaculars_temp")
duckdb_register(con, "taxa_temp", taxa)
duckdb_register(con, "vernaculars_temp", vernaculars)

# Join and aggregate
join_query <- "
  SELECT
    t.genus,
    t.kingdom,
    v.language,
    v.vernacularName
  FROM taxa_temp t
  INNER JOIN vernaculars_temp v ON t.taxon_id = v.taxon_id
  WHERE t.genus IS NOT NULL
"

joined <- dbGetQuery(con, join_query)
cat(sprintf("  → %s genus-vernacular pairs\n", format(nrow(joined), big.mark = ",")))

# ============================================================================
# Aggregate by Genus
# ============================================================================

cat("\nAggregating by genus...\n")

# Aggregate all vernaculars per genus (semicolon-separated)
genus_agg <- joined %>%
  group_by(genus, kingdom) %>%
  summarise(
    # All vernaculars combined (for udpipe frequency extraction)
    vernaculars_all = paste(unique(tolower(vernacularName)), collapse = "; "),

    # Top languages (for reference)
    languages = paste(unique(language), collapse = ", "),

    # Counts
    n_vernaculars = n(),
    n_unique_vernaculars = n_distinct(vernacularName),
    n_languages = n_distinct(language),

    .groups = "drop"
  ) %>%
  arrange(desc(n_vernaculars))

cat(sprintf("  → %s unique genera\n", format(nrow(genus_agg), big.mark = ",")))

# Summary statistics
cat("\nSummary statistics:\n")
cat(sprintf("  Animalia genera: %s\n",
            format(sum(genus_agg$kingdom == "Animalia"), big.mark = ",")))
cat(sprintf("  Plantae genera: %s\n",
            format(sum(genus_agg$kingdom == "Plantae"), big.mark = ",")))

# Distribution of vernacular counts
quantiles <- quantile(genus_agg$n_vernaculars, probs = c(0.25, 0.5, 0.75, 0.9, 0.95, 0.99))
cat("\nVernaculars per genus (quantiles):\n")
cat(sprintf("  25%%: %d\n", quantiles[1]))
cat(sprintf("  50%%: %d\n", quantiles[2]))
cat(sprintf("  75%%: %d\n", quantiles[3]))
cat(sprintf("  90%%: %d\n", quantiles[4]))
cat(sprintf("  95%%: %d\n", quantiles[5]))
cat(sprintf("  99%%: %d\n", quantiles[6]))

# Top genera by vernacular count
cat("\nTop 10 genera by vernacular count:\n")
top_genera <- genus_agg %>%
  select(genus, kingdom, n_vernaculars, n_languages) %>%
  head(10)
print(as.data.frame(top_genera), row.names = FALSE)

# ============================================================================
# Write Output
# ============================================================================

cat("\nWriting output...\n")
cat(sprintf("  Output: %s\n", OUTPUT_FILE))

write_parquet(genus_agg, OUTPUT_FILE)

cat(sprintf("\n✓ Successfully wrote %s genus aggregations\n",
            format(nrow(genus_agg), big.mark = ",")))

# ============================================================================
# Cleanup
# ============================================================================

dbDisconnect(con, shutdown = TRUE)

# ============================================================================
# Summary
# ============================================================================

cat("\n", rep("=", 80), "\n", sep = "")
cat("Summary\n")
cat(rep("=", 80), "\n", sep = "")
cat(sprintf("Total genera: %s\n", format(nrow(genus_agg), big.mark = ",")))
cat(sprintf("Animalia: %s\n", format(sum(genus_agg$kingdom == "Animalia"), big.mark = ",")))
cat(sprintf("Plantae: %s\n", format(sum(genus_agg$kingdom == "Plantae"), big.mark = ",")))
cat(sprintf("Total vernacular names: %s\n", format(sum(genus_agg$n_vernaculars), big.mark = ",")))
cat(sprintf("Median vernaculars per genus: %d\n", median(genus_agg$n_vernaculars)))
cat("\nOutput file: ", OUTPUT_FILE, "\n", sep = "")
cat(rep("=", 80), "\n\n", sep = "")
