#!/usr/bin/env Rscript

library(arrow)
library(dplyr)
library(jsonlite)
library(httr)

cat("=== GBIF Vernacular Name Extraction (All Organisms) ===\n\n")

# Config
BATCH_SIZE <- 100
SAVE_EVERY <- 500  # Save progress every N organisms
RATE_LIMIT_DELAY <- 0.1  # seconds between requests (10 req/sec)
OUTPUT_FILE <- "data/taxonomy/gbif_vernaculars_all.parquet"
PROGRESS_FILE <- "data/taxonomy/gbif_vernaculars_progress.parquet"

# Load all organisms (plants + invertebrates)
cat("Loading all organisms...\n")
all_organisms <- arrow::read_parquet("data/taxonomy/organism_taxonomy_enriched.parquet")
cat(sprintf("Total organisms: %d\n", nrow(all_organisms)))

# Check existing progress
processed_organisms <- character(0)
if (file.exists(PROGRESS_FILE)) {
  existing <- arrow::read_parquet(PROGRESS_FILE)
  processed_organisms <- existing$organism_name
  cat(sprintf("Found existing progress: %d organisms already processed\n", length(processed_organisms)))
}

# Filter to unprocessed organisms
to_process <- all_organisms %>%
  filter(!organism_name %in% processed_organisms)

cat(sprintf("Organisms to process: %d\n\n", nrow(to_process)))

if (nrow(to_process) == 0) {
  cat("All organisms already processed!\n")
  quit(save = "no")
}

# Function to get GBIF vernacular names
get_gbif_vernaculars <- function(organism_name) {
  tryCatch({
    # Step 1: Match organism name to GBIF
    match_url <- sprintf("https://api.gbif.org/v1/species/match?name=%s",
                         URLencode(organism_name, reserved = TRUE))
    match_response <- GET(match_url)

    if (status_code(match_response) != 200) {
      return(NULL)
    }

    match_data <- content(match_response, as = "parsed")

    if (is.null(match_data$usageKey)) {
      return(NULL)
    }

    usage_key <- match_data$usageKey

    # Step 2: Get vernacular names
    vern_url <- sprintf("https://api.gbif.org/v1/species/%s/vernacularNames", usage_key)
    vern_response <- GET(vern_url)

    if (status_code(vern_response) != 200) {
      return(NULL)
    }

    vern_data <- content(vern_response, as = "parsed")

    if (length(vern_data$results) == 0) {
      return(NULL)
    }

    # Extract English vernaculars
    vern_list <- vern_data$results
    english_names <- sapply(vern_list, function(v) {
      if (!is.null(v$language) && v$language == "eng") {
        return(v$vernacularName)
      }
      return(NA)
    })

    english_names <- english_names[!is.na(english_names)]

    if (length(english_names) == 0) {
      return(NULL)
    }

    return(data.frame(
      organism_name = organism_name,
      gbif_key = usage_key,
      gbif_vernaculars = paste(english_names, collapse = "; "),
      n_vernaculars = length(english_names),
      source = "gbif_api",
      stringsAsFactors = FALSE
    ))

  }, error = function(e) {
    return(NULL)
  })
}

# Process in batches
results <- list()
n_processed <- 0
n_success <- 0
start_time <- Sys.time()

cat(sprintf("Starting extraction at %s\n", format(start_time, "%Y-%m-%d %H:%M:%S")))
cat(sprintf("Will save progress every %d organisms\n\n", SAVE_EVERY))

for (i in 1:nrow(to_process)) {
  organism <- to_process$organism_name[i]

  # Query GBIF
  result <- get_gbif_vernaculars(organism)

  if (!is.null(result)) {
    results[[length(results) + 1]] <- result
    n_success <- n_success + 1
  }

  n_processed <- n_processed + 1

  # Progress update
  if (n_processed %% 100 == 0) {
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    rate <- n_processed / elapsed
    remaining <- nrow(to_process) - n_processed
    eta_secs <- remaining / rate
    eta_mins <- eta_secs / 60

    cat(sprintf("[%s] Processed: %d/%d (%.1f%%), Success: %d (%.1f%%), Rate: %.1f org/sec, ETA: %.0f min\n",
                format(Sys.time(), "%H:%M:%S"),
                n_processed, nrow(to_process),
                100 * n_processed / nrow(to_process),
                n_success,
                100 * n_success / n_processed,
                rate,
                eta_mins))
  }

  # Save progress
  if (n_processed %% SAVE_EVERY == 0 || i == nrow(to_process)) {
    if (length(results) > 0) {
      # Combine new results with existing
      new_df <- do.call(rbind, results)

      if (file.exists(PROGRESS_FILE)) {
        existing_df <- arrow::read_parquet(PROGRESS_FILE)
        combined_df <- rbind(existing_df, new_df)
      } else {
        combined_df <- new_df
      }

      arrow::write_parquet(combined_df, PROGRESS_FILE)
      cat(sprintf("  → Progress saved: %d total organisms with vernaculars\n", nrow(combined_df)))

      results <- list()  # Clear results after saving
    }
  }

  # Rate limiting
  Sys.sleep(RATE_LIMIT_DELAY)
}

# Final save
if (file.exists(PROGRESS_FILE)) {
  final_df <- arrow::read_parquet(PROGRESS_FILE)
  arrow::write_parquet(final_df, OUTPUT_FILE)

  cat(sprintf("\n\n=== Extraction Complete ===\n"))
  cat(sprintf("Total organisms with GBIF vernaculars: %d\n", nrow(final_df)))
  cat(sprintf("Output saved to: %s\n", OUTPUT_FILE))

  # Summary stats
  vern_counts <- table(final_df$n_vernaculars)
  cat("\nVernacular names per organism:\n")
  print(vern_counts)

  cat("\nSample results:\n")
  print(head(final_df[, c("organism_name", "gbif_vernaculars", "n_vernaculars")], 20))
}

elapsed_total <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
cat(sprintf("\nTotal time: %.1f minutes\n", elapsed_total))
