#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

# Minimal, dependency-free CLI parsing
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  # supports --k=v or --k v
  i <- which(grepl(paste0("^", flag, "(=|$)"), args))
  if (length(i) == 0) return(default)
  a <- args[i[1]]
  if (grepl("=", a)) {
    sub("^[^=]*=", "", a)
  } else if (i[1] < length(args) && !grepl("^--", args[i[1] + 1])) {
    args[i[1] + 1]
  } else default
}

trait_csv <- get_arg("--trait_csv", "/home/olier/ellenberg/artifacts/model_data_complete_case_with_myco.csv")
bioclim_summary <- get_arg("--bioclim_summary", "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_bioclim_summary.csv")
min_occ <- suppressWarnings(as.integer(get_arg("--min_occ", "3")))
if (is.na(min_occ)) min_occ <- 3
output_csv <- get_arg("--output_csv", "/home/olier/ellenberg/artifacts/model_data_bioclim_subset_expanded600.csv")

normalize_species <- function(x) tolower(gsub("[[:space:]_-]+", "_", x))

cat("=== Prepare Bioclim Subset Traits ===\n")
cat(sprintf("Traits:   %s\n", trait_csv))
cat(sprintf("Summary:  %s\n", bioclim_summary))
cat(sprintf("min_occ:  %d (≥3)\n", min_occ))
cat(sprintf("Output:   %s\n\n", output_csv))

# Load inputs
traits <- read_csv(trait_csv, show_col_types = FALSE)
bio    <- read_csv(bioclim_summary, show_col_types = FALSE)

if (!all(c("species", "n_occurrences") %in% names(bio))) {
  stop("Bioclim summary must contain 'species' and 'n_occurrences' columns.")
}

# Filter species by occurrences (≥ min_occ; default 3)
bio_ok <- bio %>%
  filter(n_occurrences >= min_occ) %>%
  mutate(species_norm = normalize_species(species)) %>%
  distinct(species_norm, .keep_all = TRUE)

# Align trait names
traits_ok <- traits %>%
  mutate(species_norm = normalize_species(wfo_accepted_name)) %>%
  semi_join(bio_ok %>% select(species_norm), by = "species_norm") %>%
  select(-species_norm)

cat(sprintf("Matched species: %d\n", nrow(traits_ok)))

# Save filtered traits
readr::write_csv(traits_ok, output_csv)
cat(sprintf("Saved filtered traits to: %s\n", output_csv))
