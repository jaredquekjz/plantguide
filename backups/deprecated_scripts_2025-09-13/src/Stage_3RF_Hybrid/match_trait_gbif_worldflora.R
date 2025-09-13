#!/usr/bin/env Rscript

# Match trait species with GBIF species using WorldFlora package
# Uses exact matching and synonym resolution (NO fuzzy matching)

suppressPackageStartupMessages({
  library(WorldFlora)
  library(data.table)
  library(tidyverse)
  library(jsonlite)
})

cat("=== Trait-GBIF Matching using WorldFlora Package ===\n\n")

# Configuration
config <- list(
  trait_file = "/home/olier/ellenberg/artifacts/model_data_complete_case_with_myco.csv",
  gbif_dir = "/home/olier/plantsdatabase/data/Stage_4/gbif_occurrences_complete",
  wfo_file = "/home/olier/ellenberg/data/classification.csv",
  output_file = "/home/olier/ellenberg/artifacts/trait_gbif_worldflora_matches.json",
  sample_size = 50000  # Set to NULL to process all files
)

# Function to extract GBIF species names
extract_gbif_species <- function(gbif_dir, sample_size = NULL) {
  cat("Extracting GBIF species names...\n")
  
  # Get list of files
  cmd <- sprintf("find %s -name '*.csv.gz' -type f", gbif_dir)
  if (!is.null(sample_size)) {
    cmd <- paste(cmd, "| head -n", sample_size)
  }
  
  files <- system(cmd, intern = TRUE)
  
  # Extract species names from filenames
  species_names <- basename(files) %>%
    str_remove("\\.csv\\.gz$") %>%
    str_replace_all("-", " ")
  
  # Filter out invalid entries
  valid_species <- species_names[!str_starts(species_names, "taxon ")]
  
  cat(sprintf("  Found %d valid species (skipped %d invalid)\n", 
              length(valid_species), 
              length(species_names) - length(valid_species)))
  
  return(data.table(
    gbif_name = valid_species,
    gbif_file = files[!str_starts(species_names, "taxon ")]
  ))
}

# Main matching function
main <- function() {
  
  # Load WFO data
  cat("\nLoading WFO backbone...\n")
  WFO_data <- fread(config$wfo_file, encoding = "UTF-8")
  cat(sprintf("  Loaded %d WFO records\n", nrow(WFO_data)))
  
  # Load trait species
  cat("\nLoading trait species...\n")
  trait_data <- read.csv(config$trait_file, stringsAsFactors = FALSE)
  trait_species <- unique(trait_data$wfo_accepted_name)
  cat(sprintf("  Loaded %d unique trait species\n", length(trait_species)))
  
  # Extract GBIF species
  gbif_species <- extract_gbif_species(config$gbif_dir, config$sample_size)
  
  # Prepare for matching
  cat("\n=== Performing WFO Matching ===\n")
  
  # Match trait species using WorldFlora
  cat("\nMatching trait species through WFO...\n")
  
  # Use WFO.match with NO fuzzy matching (Fuzzy = FALSE for exact only)
  trait_wfo_matches <- WFO.match(
    spec.data = trait_species,
    WFO.data = WFO_data,
    Fuzzy = FALSE,  # EXACT matching only (no fuzzy)
    verbose = FALSE,
    counter = 1000,
    acceptedNameUsageID.match = TRUE  # Automatically resolve synonyms
  )
  
  # WFO.match returns a row for each input species with columns about the match
  # The spec.name column contains the original input name
  trait_wfo_matches$original_name <- trait_wfo_matches$spec.name
  
  # Report how many matched
  n_matched <- sum(!is.na(trait_wfo_matches$scientificName))
  cat(sprintf("  WFO matched %d out of %d species\n", n_matched, nrow(trait_wfo_matches)))
  
  # Get accepted names for trait species
  # WorldFlora already resolves to accepted names when acceptedNameUsageID.match = TRUE
  # The New.accepted column indicates if resolution happened
  trait_wfo_matches <- trait_wfo_matches %>%
    mutate(
      resolved_name = case_when(
        !is.na(scientificName) & New.accepted == TRUE ~ scientificName,
        !is.na(scientificName) ~ scientificName,
        TRUE ~ original_name
      )
    )
  
  cat(sprintf("  WFO resolved %d trait species\n", sum(!is.na(trait_wfo_matches$scientificName))))
  
  # Match GBIF species through WFO
  cat("\nMatching GBIF species through WFO (this may take a while)...\n")
  
  # Process in batches for memory efficiency
  batch_size <- 5000
  n_batches <- ceiling(nrow(gbif_species) / batch_size)
  
  gbif_wfo_matches <- list()
  
  for (i in 1:n_batches) {
    start_idx <- (i - 1) * batch_size + 1
    end_idx <- min(i * batch_size, nrow(gbif_species))
    
    batch <- gbif_species$gbif_name[start_idx:end_idx]
    
    if (i %% 10 == 1) {
      cat(sprintf("  Processing batch %d/%d...\n", i, n_batches))
    }
    
    batch_matches <- WFO.match(
      spec.data = batch,
      WFO.data = WFO_data,
      Fuzzy = FALSE,  # EXACT matching only
      verbose = FALSE,
      counter = 1000,
      acceptedNameUsageID.match = TRUE
    )
    
    batch_matches$original_name <- batch
    batch_matches$gbif_file <- gbif_species$gbif_file[start_idx:end_idx]
    
    gbif_wfo_matches[[i]] <- batch_matches
  }
  
  # Combine all GBIF matches
  gbif_wfo_all <- bind_rows(gbif_wfo_matches)
  
  # Get resolved names for GBIF
  gbif_wfo_all <- gbif_wfo_all %>%
    mutate(
      resolved_name = case_when(
        !is.na(scientificName) & New.accepted == TRUE ~ scientificName,
        !is.na(scientificName) ~ scientificName,
        TRUE ~ original_name
      )
    )
  
  cat(sprintf("  WFO resolved %d GBIF species\n", sum(!is.na(gbif_wfo_all$scientificName))))
  
  # Match trait and GBIF through resolved names
  cat("\n=== Cross-matching Results ===\n")
  
  # Normalize for matching
  normalize_name <- function(x) {
    x %>%
      str_to_lower() %>%
      str_trim() %>%
      str_replace_all("\\s+", " ")
  }
  
  trait_wfo_matches$norm_resolved <- normalize_name(trait_wfo_matches$resolved_name)
  gbif_wfo_all$norm_resolved <- normalize_name(gbif_wfo_all$resolved_name)
  
  # Find matches
  matched_species <- trait_wfo_matches %>%
    inner_join(
      gbif_wfo_all %>% select(norm_resolved, gbif_name = original_name, gbif_file),
      by = "norm_resolved"
    ) %>%
    select(
      trait_name = original_name,
      wfo_resolved = resolved_name,
      gbif_name,
      gbif_file,
      trait_status = taxonomicStatus
    ) %>%
    distinct()
  
  # Find unmatched
  unmatched_traits <- trait_wfo_matches %>%
    filter(!norm_resolved %in% gbif_wfo_all$norm_resolved) %>%
    select(trait_name = original_name, wfo_resolved = resolved_name)
  
  # Summary statistics
  cat(sprintf("\nTotal trait species: %d\n", length(trait_species)))
  cat(sprintf("Matched with GBIF: %d (%.1f%%)\n", 
              nrow(matched_species),
              100 * nrow(matched_species) / length(trait_species)))
  cat(sprintf("Unmatched: %d (%.1f%%)\n",
              nrow(unmatched_traits),
              100 * nrow(unmatched_traits) / length(trait_species)))
  
  # Check match types
  direct_matches <- sum(matched_species$trait_name == matched_species$gbif_name)
  synonym_matches <- nrow(matched_species) - direct_matches
  
  cat("\nMatch breakdown:\n")
  cat(sprintf("  Direct name matches: %d\n", direct_matches))
  cat(sprintf("  Via WFO synonyms: %d\n", synonym_matches))
  
  # Save results
  results <- list(
    summary = list(
      total_trait_species = length(trait_species),
      gbif_species_processed = nrow(gbif_species),
      matched = nrow(matched_species),
      unmatched = nrow(unmatched_traits),
      direct_matches = direct_matches,
      synonym_matches = synonym_matches
    ),
    matched_species = matched_species,
    unmatched_species = unmatched_traits
  )
  
  write_json(results, config$output_file, pretty = TRUE, auto_unbox = TRUE)
  cat(sprintf("\nResults saved to: %s\n", config$output_file))
  
  # Show sample unmatched
  if (nrow(unmatched_traits) > 0) {
    cat("\nSample unmatched species:\n")
    print(head(unmatched_traits, 10))
  }
  
  # Note about sample size
  if (!is.null(config$sample_size)) {
    cat(sprintf("\nNote: Processed first %d GBIF files as a test.\n", config$sample_size))
    cat("Set sample_size = NULL in config to process all files.\n")
  }
}

# Run main function
if (!interactive()) {
  main()
} else {
  cat("Script loaded. Run main() to execute.\n")
}