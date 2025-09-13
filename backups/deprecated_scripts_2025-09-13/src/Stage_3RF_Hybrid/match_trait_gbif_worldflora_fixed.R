#!/usr/bin/env Rscript

# Fixed version using WFO.one() for 1:1 matching
# Match trait species with GBIF species using WorldFlora package

suppressPackageStartupMessages({
  library(WorldFlora)
  library(data.table)
  library(tidyverse)
  library(jsonlite)
})

cat("=== Trait-GBIF Matching using WorldFlora (FIXED with WFO.one) ===\n\n")

# Configuration
config <- list(
  trait_file = "/home/olier/ellenberg/artifacts/model_data_complete_case_with_myco.csv",
  gbif_dir = "/home/olier/plantsdatabase/data/Stage_4/gbif_occurrences_complete",
  wfo_file = "/home/olier/ellenberg/data/classification.csv",
  output_file = "/home/olier/ellenberg/artifacts/trait_gbif_worldflora_fixed.json",
  sample_size = NULL  # Process ALL 386K files for complete verification
)

# Function to normalize species names for WFO (needs proper capitalization!)
normalize_species_name <- function(name) {
  # Remove hybrid markers
  name <- gsub("^×\\s*", "", name, perl = TRUE)
  name <- gsub("\\s*×\\s*", " ", name)
  name <- gsub("(^|\\s)x(\\s+)", " ", name)
  
  # Remove subspecies/variety indicators for species-level matching
  name <- gsub("\\s+(subsp\\.|var\\.|f\\.|forma|subspecies|variety).*", "", name, ignore.case = TRUE)
  
  # Clean whitespace
  name <- trimws(name)
  name <- gsub("\\s+", " ", name)
  
  # Proper capitalization for WFO: Genus species
  # Split into words
  words <- strsplit(name, " ")[[1]]
  if (length(words) >= 1) {
    # Capitalize first word (genus), lowercase rest
    words[1] <- paste0(toupper(substring(words[1], 1, 1)), 
                       tolower(substring(words[1], 2)))
    if (length(words) >= 2) {
      words[2:length(words)] <- tolower(words[2:length(words)])
    }
    name <- paste(words, collapse = " ")
  }
  
  return(name)
}

# Function to extract GBIF species names
extract_gbif_species <- function(gbif_dir, sample_size = NULL) {
  cat("Extracting GBIF species names...\n")
  
  cmd <- sprintf("find %s -name '*.csv.gz' -type f", gbif_dir)
  if (!is.null(sample_size)) {
    cmd <- paste(cmd, "| head -n", sample_size)
  }
  
  files <- system(cmd, intern = TRUE)
  
  species_names <- basename(files) %>%
    str_remove("\\.csv\\.gz$") %>%
    str_replace_all("-", " ")
  
  valid_species <- species_names[!str_starts(species_names, "taxon ")]
  
  # NORMALIZE the GBIF names before matching!
  normalized_species <- sapply(valid_species, normalize_species_name, USE.NAMES = FALSE)
  
  cat(sprintf("  Found %d valid species (skipped %d invalid)\n", 
              length(valid_species), 
              length(species_names) - length(valid_species)))
  
  return(data.table(
    gbif_name_raw = valid_species,
    gbif_name = normalized_species,  # Use normalized names for matching
    gbif_file = files[!str_starts(species_names, "taxon ")]
  ))
}

# Main function
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
  
  cat("\n=== Performing WFO Matching ===\n")
  
  # Match trait species - EXACT only
  cat("\nMatching trait species through WFO (exact only)...\n")
  
  trait_wfo_matches <- WFO.match(
    spec.data = trait_species,
    WFO.data = WFO_data,
    Fuzzy = FALSE,  # NO fuzzy matching
    verbose = FALSE,
    counter = 1000,
    acceptedNameUsageID.match = TRUE
  )
  
  # Use WFO.one to get 1:1 matches
  cat("  Applying WFO.one for 1:1 matching...\n")
  trait_one <- WFO.one(trait_wfo_matches, spec.name = "spec.name")
  
  # Count successful matches
  n_matched <- sum(trait_one$Matched == TRUE, na.rm = TRUE)
  cat(sprintf("  WFO matched %d out of %d trait species\n", n_matched, nrow(trait_one)))
  
  # Process GBIF species
  cat("\nMatching GBIF species through WFO...\n")
  
  # Process in batches
  batch_size <- 5000
  n_batches <- ceiling(nrow(gbif_species) / batch_size)
  
  gbif_matches_list <- list()
  
  for (i in 1:n_batches) {
    start_idx <- (i - 1) * batch_size + 1
    end_idx <- min(i * batch_size, nrow(gbif_species))
    
    batch <- gbif_species$gbif_name[start_idx:end_idx]
    
    if (i %% 10 == 1) {
      cat(sprintf("  Processing batch %d/%d...\n", i, n_batches))
    }
    
    # Match batch
    batch_matches <- WFO.match(
      spec.data = batch,
      WFO.data = WFO_data,
      Fuzzy = FALSE,
      verbose = FALSE,
      counter = 1000,
      acceptedNameUsageID.match = TRUE
    )
    
    # Get 1:1 matches
    batch_one <- WFO.one(batch_matches, spec.name = "spec.name")
    batch_one$gbif_file <- gbif_species$gbif_file[start_idx:end_idx]
    
    gbif_matches_list[[i]] <- batch_one
  }
  
  # Combine all GBIF matches
  gbif_one <- bind_rows(gbif_matches_list)
  
  n_gbif_matched <- sum(gbif_one$Matched == TRUE, na.rm = TRUE)
  cat(sprintf("  WFO matched %d out of %d GBIF species\n", n_gbif_matched, nrow(gbif_one)))
  
  # Cross-match trait and GBIF
  cat("\n=== Cross-matching Results ===\n")
  
  # Prepare for matching - use scientificName from WFO matches
  trait_matched <- trait_one %>%
    filter(Matched == TRUE) %>%
    mutate(
      wfo_name = ifelse(!is.na(scientificName), scientificName, spec.name),
      wfo_name_norm = str_to_lower(str_trim(wfo_name))
    )
  
  gbif_matched <- gbif_one %>%
    filter(Matched == TRUE) %>%
    mutate(
      wfo_name = ifelse(!is.na(scientificName), scientificName, spec.name),
      wfo_name_norm = str_to_lower(str_trim(wfo_name))
    )
  
  # Find matches based on WFO resolved names
  # Note: spec.name in gbif_matched contains the normalized name we fed to WFO
  final_matches <- trait_matched %>%
    inner_join(
      gbif_matched %>% select(wfo_name_norm, gbif_name_normalized = spec.name, gbif_file),
      by = "wfo_name_norm"
    ) %>%
    mutate(
      # Extract original GBIF name from file path for display
      gbif_name_original = gsub(".*/([^/]+)\\.csv\\.gz$", "\\1", gbif_file),
      gbif_name_original = gsub("-", " ", gbif_name_original)
    ) %>%
    select(
      trait_name = spec.name,
      wfo_name,
      gbif_name = gbif_name_original,
      gbif_file,
      trait_matched = Matched,
      trait_accepted = New.accepted
    ) %>%
    distinct()
  
  # Find unmatched
  unmatched_traits <- trait_one %>%
    filter(!(spec.name %in% final_matches$trait_name)) %>%
    select(trait_name = spec.name, matched = Matched)
  
  # Summary
  cat(sprintf("\nTotal trait species: %d\n", length(trait_species)))
  cat(sprintf("Matched with GBIF: %d (%.1f%%)\n", 
              nrow(final_matches),
              100 * nrow(final_matches) / length(trait_species)))
  cat(sprintf("Unmatched: %d (%.1f%%)\n",
              nrow(unmatched_traits),
              100 * nrow(unmatched_traits) / length(trait_species)))
  
  # Analyze match types
  direct_matches <- sum(final_matches$trait_name == final_matches$gbif_name)
  synonym_matches <- nrow(final_matches) - direct_matches
  
  cat("\nMatch types:\n")
  cat(sprintf("  Direct name matches: %d\n", direct_matches))
  cat(sprintf("  Via WFO resolution: %d\n", synonym_matches))
  
  # Save results
  results <- list(
    summary = list(
      total_trait_species = length(trait_species),
      trait_matched_wfo = n_matched,
      gbif_species_processed = nrow(gbif_species),
      gbif_matched_wfo = n_gbif_matched,
      final_matched = nrow(final_matches),
      unmatched = nrow(unmatched_traits)
    ),
    matched_species = final_matches,
    unmatched_species = unmatched_traits
  )
  
  write_json(results, config$output_file, pretty = TRUE, auto_unbox = TRUE)
  cat(sprintf("\nResults saved to: %s\n", config$output_file))
  
  # Show samples
  if (nrow(unmatched_traits) > 0) {
    cat("\nSample unmatched species:\n")
    print(head(unmatched_traits, 10))
  }
  
  if (!is.null(config$sample_size)) {
    cat(sprintf("\nNote: Processed first %d GBIF files as a test.\n", config$sample_size))
    cat("Set sample_size = NULL to process all files.\n")
  }
}

# Run
if (!interactive()) {
  main()
} else {
  cat("Script loaded. Run main() to execute.\n")
}