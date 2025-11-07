#!/usr/bin/env Rscript
# Build WorldFlora-enriched parquets for Bill's verification
# Outputs to data/shipley_checks/wfo_verification/ to avoid contaminating canonical data

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(data.table)
})

setwd("/home/olier/ellenberg")

log_msg <- function(...) {
  cat(..., "\n", sep = "")
  flush.console()
}

output_dir <- "data/shipley_checks/wfo_verification"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# ==============================================================================
# 1. DUKE
# ==============================================================================

log_msg("=== Processing Duke dataset ===")
duke_orig <- read_parquet("data/stage1/duke_original.parquet")
log_msg("Loaded Duke original: ", nrow(duke_orig), " rows")

duke_wfo <- fread("data/shipley_checks/wfo_verification/duke_wfo_worldflora.csv", data.table = FALSE)
log_msg("Loaded Duke WFO matches: ", nrow(duke_wfo), " rows")

# Convert empty string taxonID to NA (match Python behavior)
duke_wfo$taxonID[trimws(duke_wfo$taxonID) == ""] <- NA

# Build source name (prioritize scientific_name over taxonomy_taxon)
duke_wfo$src_name <- duke_wfo$scientific_name
empty_idx <- which(is.na(duke_wfo$src_name) | trimws(duke_wfo$src_name) == "")
if (length(empty_idx) > 0) {
  duke_wfo$src_name[empty_idx] <- duke_wfo$taxonomy_taxon[empty_idx]
}

# Ranking logic
duke_wfo$scientific_norm <- tolower(trimws(duke_wfo$scientificName))
duke_wfo$src_norm <- tolower(trimws(duke_wfo$src_name))
duke_wfo$matched_rank <- as.integer(!tolower(trimws(duke_wfo$Matched)) %in% c("true", "t", "1", "yes"))
duke_wfo$taxonid_rank <- as.integer(trimws(duke_wfo$taxonID) == "" | is.na(duke_wfo$taxonID))
duke_wfo$exact_rank <- as.integer(duke_wfo$scientific_norm != duke_wfo$src_norm)

duke_wfo$src_genus <- sapply(strsplit(duke_wfo$src_norm, " "), function(x) x[1])
duke_wfo$scientific_genus <- sapply(strsplit(duke_wfo$scientific_norm, " "), function(x) x[1])
duke_wfo$genus_rank <- as.integer(duke_wfo$scientific_genus != duke_wfo$src_genus)

duke_wfo$new_accepted_rank <- as.integer(!tolower(trimws(duke_wfo$New.accepted)) %in% c("true", "t", "1", "yes"))
# IMPORTANT: Duke uses pandas - case-INSENSITIVE comparison (canonical line 153)
duke_wfo$status_rank <- as.integer(tolower(trimws(duke_wfo$taxonomicStatus)) != "accepted")
duke_wfo$subseq_rank <- suppressWarnings(as.numeric(duke_wfo$Subseq))
duke_wfo$subseq_rank[is.na(duke_wfo$subseq_rank)] <- 9999999

# Note: plant_key is already a unique ID, no normalization needed for Duke
duke_wfo_sorted <- duke_wfo %>%
  arrange(plant_key, matched_rank, taxonid_rank, exact_rank, genus_rank,
          new_accepted_rank, status_rank, subseq_rank) %>%
  group_by(plant_key) %>%
  slice(1) %>%
  ungroup()

# Rename columns
duke_wfo_clean <- duke_wfo_sorted %>%
  select(
    plant_key,
    wf_spec_name = spec.name,
    wfo_taxon_id = taxonID,
    wfo_scientific_name = scientificName,
    wfo_taxonomic_status = taxonomicStatus,
    wfo_accepted_nameusage_id = acceptedNameUsageID,
    wfo_new_accepted = New.accepted,
    wfo_original_status = Old.status,
    wfo_original_id = Old.ID,
    wfo_original_name = Old.name,
    wfo_matched = Matched,
    wfo_unique = Unique,
    wfo_fuzzy = Fuzzy,
    wfo_fuzzy_distance = Fuzzy.dist
  )

# Merge
duke_enriched <- duke_orig %>%
  left_join(duke_wfo_clean, by = "plant_key")

log_msg("Writing Duke enriched parquet...")
write_parquet(duke_enriched, file.path(output_dir, "duke_worldflora_enriched.parquet"), compression = "snappy")
log_msg("Duke complete: ", nrow(duke_enriched), " rows\n")

# ==============================================================================
# 2. EIVE
# ==============================================================================

log_msg("=== Processing EIVE dataset ===")
eive_orig <- read_parquet("data/stage1/eive_original.parquet")
log_msg("Loaded EIVE original: ", nrow(eive_orig), " rows")

eive_wfo <- fread("data/shipley_checks/wfo_verification/eive_wfo_worldflora.csv", data.table = FALSE)
log_msg("Loaded EIVE WFO matches: ", nrow(eive_wfo), " rows")

# Convert empty string taxonID to NA (match Python behavior)
eive_wfo$taxonID[trimws(eive_wfo$taxonID) == ""] <- NA

# Build source name
eive_wfo$src_name <- eive_wfo$TaxonConcept

# Ranking logic
eive_wfo$scientific_norm <- tolower(trimws(eive_wfo$scientificName))
eive_wfo$src_norm <- tolower(trimws(eive_wfo$src_name))
eive_wfo$matched_rank <- as.integer(!tolower(trimws(eive_wfo$Matched)) %in% c("true", "t", "1", "yes"))
eive_wfo$taxonid_rank <- as.integer(trimws(eive_wfo$taxonID) == "" | is.na(eive_wfo$taxonID))
eive_wfo$exact_rank <- as.integer(eive_wfo$scientific_norm != eive_wfo$src_norm)

eive_wfo$src_genus <- sapply(strsplit(eive_wfo$src_norm, " "), function(x) x[1])
eive_wfo$scientific_genus <- sapply(strsplit(eive_wfo$scientific_norm, " "), function(x) x[1])
eive_wfo$genus_rank <- as.integer(eive_wfo$scientific_genus != eive_wfo$src_genus)

eive_wfo$new_accepted_rank <- as.integer(!tolower(trimws(eive_wfo$New.accepted)) %in% c("true", "t", "1", "yes"))
# IMPORTANT: EIVE canonical fixed to case-INSENSITIVE (2025-11-06 bug fix)
eive_wfo$status_rank <- as.integer(tolower(trimws(eive_wfo$taxonomicStatus)) != "accepted")
eive_wfo$subseq_rank <- suppressWarnings(as.numeric(eive_wfo$Subseq))
eive_wfo$subseq_rank[is.na(eive_wfo$subseq_rank)] <- 9999999

# Create normalized join key BEFORE deduplication
eive_wfo$join_key_normalized <- tolower(trimws(eive_wfo$TaxonConcept))

eive_wfo_sorted <- eive_wfo %>%
  arrange(join_key_normalized, matched_rank, taxonid_rank, exact_rank, genus_rank,
          new_accepted_rank, status_rank, subseq_rank) %>%
  group_by(join_key_normalized) %>%
  slice(1) %>%
  ungroup()

# Rename columns (keep join_key_normalized for merging)
eive_wfo_clean <- eive_wfo_sorted %>%
  select(
    TaxonConcept,
    join_key_normalized,
    wf_spec_name = spec.name,
    wfo_taxon_id = taxonID,
    wfo_scientific_name = scientificName,
    wfo_taxonomic_status = taxonomicStatus,
    wfo_accepted_nameusage_id = acceptedNameUsageID,
    wfo_new_accepted = New.accepted,
    wfo_original_status = Old.status,
    wfo_original_id = Old.ID,
    wfo_original_name = Old.name,
    wfo_matched = Matched,
    wfo_unique = Unique,
    wfo_fuzzy = Fuzzy,
    wfo_fuzzy_distance = Fuzzy.dist
  )

# Merge with normalized keys (case-insensitive, whitespace-trimmed)
eive_orig$join_key_normalized <- tolower(trimws(eive_orig$TaxonConcept))

eive_enriched <- eive_orig %>%
  left_join(eive_wfo_clean %>% select(-TaxonConcept), by = "join_key_normalized") %>%
  select(-join_key_normalized) %>%
  # Convert empty strings to NA to match canonical NULL behavior
  mutate(across(where(is.character), ~na_if(., "")))

log_msg("Writing EIVE enriched parquet...")
write_parquet(eive_enriched, file.path(output_dir, "eive_worldflora_enriched.parquet"), compression = "snappy")
log_msg("EIVE complete: ", nrow(eive_enriched), " rows\n")

# ==============================================================================
# 3. MABBERLY
# ==============================================================================

log_msg("=== Processing Mabberly dataset ===")
mab_orig <- read_parquet("data/stage1/mabberly_original.parquet")
log_msg("Loaded Mabberly original: ", nrow(mab_orig), " rows")

mab_wfo <- fread("data/shipley_checks/wfo_verification/mabberly_wfo_worldflora.csv", data.table = FALSE)
log_msg("Loaded Mabberly WFO matches: ", nrow(mab_wfo), " rows")

# Convert empty string taxonID to NA (match Python behavior)
mab_wfo$taxonID[trimws(mab_wfo$taxonID) == ""] <- NA

# Build source name
mab_wfo$src_name <- mab_wfo$Genus

# Ranking logic
mab_wfo$scientific_norm <- tolower(trimws(mab_wfo$scientificName))
mab_wfo$src_norm <- tolower(trimws(mab_wfo$src_name))
mab_wfo$matched_rank <- as.integer(!tolower(trimws(mab_wfo$Matched)) %in% c("true", "t", "1", "yes"))
mab_wfo$taxonid_rank <- as.integer(trimws(mab_wfo$taxonID) == "" | is.na(mab_wfo$taxonID))
mab_wfo$exact_rank <- as.integer(mab_wfo$scientific_norm != mab_wfo$src_norm)

# For genus matching, genus rank is just whether the first word matches the genus
mab_wfo$scientific_genus <- sapply(strsplit(mab_wfo$scientific_norm, " "), function(x) x[1])
mab_wfo$genus_rank <- as.integer(mab_wfo$scientific_genus != mab_wfo$src_norm)

mab_wfo$new_accepted_rank <- as.integer(!tolower(trimws(mab_wfo$New.accepted)) %in% c("true", "t", "1", "yes"))
# IMPORTANT: Mabberly uses pandas - case-INSENSITIVE comparison (canonical line 471)
mab_wfo$status_rank <- as.integer(tolower(trimws(mab_wfo$taxonomicStatus)) != "accepted")
mab_wfo$subseq_rank <- suppressWarnings(as.numeric(mab_wfo$Subseq))
mab_wfo$subseq_rank[is.na(mab_wfo$subseq_rank)] <- 9999999

# Create normalized join key BEFORE deduplication
mab_wfo$join_key_normalized <- tolower(trimws(mab_wfo$Genus))

mab_wfo_sorted <- mab_wfo %>%
  arrange(join_key_normalized, matched_rank, taxonid_rank, exact_rank, genus_rank,
          new_accepted_rank, status_rank, subseq_rank) %>%
  group_by(join_key_normalized) %>%
  slice(1) %>%
  ungroup()

# Rename columns (keep join_key_normalized for merging)
mab_wfo_clean <- mab_wfo_sorted %>%
  select(
    Genus,
    join_key_normalized,
    wf_spec_name = spec.name,
    wfo_taxon_id = taxonID,
    wfo_scientific_name = scientificName,
    wfo_taxonomic_status = taxonomicStatus,
    wfo_accepted_nameusage_id = acceptedNameUsageID,
    wfo_new_accepted = New.accepted,
    wfo_original_status = Old.status,
    wfo_original_id = Old.ID,
    wfo_original_name = Old.name,
    wfo_matched = Matched,
    wfo_unique = Unique,
    wfo_fuzzy = Fuzzy,
    wfo_fuzzy_distance = Fuzzy.dist
  )

# Merge with normalized keys (case-insensitive, whitespace-trimmed)
mab_orig$join_key_normalized <- tolower(trimws(mab_orig$Genus))

mab_enriched <- mab_orig %>%
  left_join(mab_wfo_clean %>% select(-Genus), by = "join_key_normalized") %>%
  select(-join_key_normalized)

log_msg("Writing Mabberly enriched parquet...")
write_parquet(mab_enriched, file.path(output_dir, "mabberly_worldflora_enriched.parquet"), compression = "uncompressed")
log_msg("Mabberly complete: ", nrow(mab_enriched), " rows\n")

# ==============================================================================
# 4. TRY ENHANCED
# ==============================================================================

log_msg("=== Processing TRY Enhanced dataset ===")
try_orig <- read_parquet("data/stage1/tryenhanced_species_original.parquet")
log_msg("Loaded TRY Enhanced original: ", nrow(try_orig), " rows")

try_wfo <- fread("data/shipley_checks/wfo_verification/tryenhanced_wfo_worldflora.csv", data.table = FALSE)
log_msg("Loaded TRY Enhanced WFO matches: ", nrow(try_wfo), " rows")

# Convert empty string taxonID to NA (match Python behavior)
try_wfo$taxonID[trimws(try_wfo$taxonID) == ""] <- NA

# Build source name
try_wfo$src_name <- try_wfo$SpeciesName

# Ranking logic
try_wfo$scientific_norm <- tolower(trimws(try_wfo$scientificName))
try_wfo$src_norm <- tolower(trimws(try_wfo$src_name))
try_wfo$matched_rank <- as.integer(!tolower(trimws(try_wfo$Matched)) %in% c("true", "t", "1", "yes"))
try_wfo$taxonid_rank <- as.integer(trimws(try_wfo$taxonID) == "" | is.na(try_wfo$taxonID))
try_wfo$exact_rank <- as.integer(try_wfo$scientific_norm != try_wfo$src_norm)

try_wfo$src_genus <- sapply(strsplit(try_wfo$src_norm, " "), function(x) x[1])
try_wfo$scientific_genus <- sapply(strsplit(try_wfo$scientific_norm, " "), function(x) x[1])
try_wfo$genus_rank <- as.integer(try_wfo$scientific_genus != try_wfo$src_genus)

try_wfo$new_accepted_rank <- as.integer(!tolower(trimws(try_wfo$New.accepted)) %in% c("true", "t", "1", "yes"))
# IMPORTANT: TRY Enhanced canonical fixed to case-INSENSITIVE (2025-11-06 bug fix)
try_wfo$status_rank <- as.integer(tolower(trimws(try_wfo$taxonomicStatus)) != "accepted")
try_wfo$subseq_rank <- suppressWarnings(as.numeric(try_wfo$Subseq))
try_wfo$subseq_rank[is.na(try_wfo$subseq_rank)] <- 9999999

# Create normalized join key BEFORE deduplication
try_wfo$join_key_normalized <- tolower(trimws(try_wfo$SpeciesName))

try_wfo_sorted <- try_wfo %>%
  arrange(join_key_normalized, matched_rank, taxonid_rank, exact_rank, genus_rank,
          new_accepted_rank, status_rank, subseq_rank) %>%
  group_by(join_key_normalized) %>%
  slice(1) %>%
  ungroup()

# Rename columns (keep join_key_normalized for merging)
try_wfo_clean <- try_wfo_sorted %>%
  select(
    SpeciesName,
    join_key_normalized,
    wf_spec_name = spec.name,
    wfo_taxon_id = taxonID,
    wfo_scientific_name = scientificName,
    wfo_taxonomic_status = taxonomicStatus,
    wfo_accepted_nameusage_id = acceptedNameUsageID,
    wfo_new_accepted = New.accepted,
    wfo_original_status = Old.status,
    wfo_original_id = Old.ID,
    wfo_original_name = Old.name,
    wfo_matched = Matched,
    wfo_unique = Unique,
    wfo_fuzzy = Fuzzy,
    wfo_fuzzy_distance = Fuzzy.dist
  )

# Merge with normalized keys (case-insensitive, whitespace-trimmed)
try_orig$join_key_normalized <- tolower(trimws(try_orig$`Species name standardized against TPL`))

try_enriched <- try_orig %>%
  left_join(try_wfo_clean %>% select(-SpeciesName), by = "join_key_normalized") %>%
  select(-join_key_normalized) %>%
  # Convert empty strings to NA to match canonical NULL behavior
  mutate(across(where(is.character), ~na_if(., "")))

log_msg("Writing TRY Enhanced enriched parquet...")
write_parquet(try_enriched, file.path(output_dir, "tryenhanced_worldflora_enriched.parquet"), compression = "snappy")
log_msg("TRY Enhanced complete: ", nrow(try_enriched), " rows\n")

# ==============================================================================
# 5. AUSTRAITS TRAITS
# ==============================================================================

log_msg("=== Processing AusTraits Traits dataset ===")
aus_traits_orig <- read_parquet("data/stage1/austraits/traits.parquet")
log_msg("Loaded AusTraits traits original: ", nrow(aus_traits_orig), " rows")

aus_wfo <- fread("data/shipley_checks/wfo_verification/austraits_wfo_worldflora.csv", data.table = FALSE)
log_msg("Loaded AusTraits WFO matches: ", nrow(aus_wfo), " rows")

# Convert empty string taxonID to NA (match Python behavior)
aus_wfo$taxonID[trimws(aus_wfo$taxonID) == ""] <- NA

# Build source name
aus_wfo$src_name <- aus_wfo$taxon_name

# Ranking logic
aus_wfo$scientific_norm <- tolower(trimws(aus_wfo$scientificName))
aus_wfo$src_norm <- tolower(trimws(aus_wfo$src_name))
aus_wfo$matched_rank <- as.integer(!tolower(trimws(aus_wfo$Matched)) %in% c("true", "t", "1", "yes"))
aus_wfo$taxonid_rank <- as.integer(trimws(aus_wfo$taxonID) == "" | is.na(aus_wfo$taxonID))
aus_wfo$exact_rank <- as.integer(aus_wfo$scientific_norm != aus_wfo$src_norm)

aus_wfo$src_genus <- sapply(strsplit(aus_wfo$src_norm, " "), function(x) x[1])
aus_wfo$scientific_genus <- sapply(strsplit(aus_wfo$scientific_norm, " "), function(x) x[1])
aus_wfo$genus_rank <- as.integer(aus_wfo$scientific_genus != aus_wfo$src_genus)

aus_wfo$new_accepted_rank <- as.integer(!tolower(trimws(aus_wfo$New.accepted)) %in% c("true", "t", "1", "yes"))
# IMPORTANT: AusTraits uses pandas - case-INSENSITIVE comparison (canonical line 640)
aus_wfo$status_rank <- as.integer(tolower(trimws(aus_wfo$taxonomicStatus)) != "accepted")
aus_wfo$subseq_rank <- suppressWarnings(as.numeric(aus_wfo$Subseq))
aus_wfo$subseq_rank[is.na(aus_wfo$subseq_rank)] <- 9999999

# Create normalized join key BEFORE deduplication
aus_wfo$join_key_normalized <- tolower(trimws(aus_wfo$taxon_name))

aus_wfo_sorted <- aus_wfo %>%
  arrange(join_key_normalized, matched_rank, taxonid_rank, exact_rank, genus_rank,
          new_accepted_rank, status_rank, subseq_rank) %>%
  group_by(join_key_normalized) %>%
  slice(1) %>%
  ungroup()

# Rename columns (keep join_key_normalized for merging)
aus_wfo_clean <- aus_wfo_sorted %>%
  select(
    taxon_name,
    join_key_normalized,
    wf_spec_name = spec.name,
    wfo_taxon_id = taxonID,
    wfo_scientific_name = scientificName,
    wfo_taxonomic_status = taxonomicStatus,
    wfo_accepted_nameusage_id = acceptedNameUsageID,
    wfo_new_accepted = New.accepted,
    wfo_original_status = Old.status,
    wfo_original_id = Old.ID,
    wfo_original_name = Old.name,
    wfo_matched = Matched,
    wfo_unique = Unique,
    wfo_fuzzy = Fuzzy,
    wfo_fuzzy_distance = Fuzzy.dist
  )

# Merge with normalized keys (case-insensitive, whitespace-trimmed)
aus_traits_orig$join_key_normalized <- tolower(trimws(aus_traits_orig$taxon_name))

aus_traits_enriched <- aus_traits_orig %>%
  left_join(aus_wfo_clean %>% select(-taxon_name), by = "join_key_normalized") %>%
  select(-join_key_normalized)

log_msg("Writing AusTraits traits enriched parquet...")
write_parquet(aus_traits_enriched, file.path(output_dir, "austraits_traits_worldflora_enriched.parquet"), compression = "snappy")
log_msg("AusTraits traits complete: ", nrow(aus_traits_enriched), " rows")
log_msg("  (Note: Contains both trait measurements and WFO taxonomy for all AusTraits species)\n")

# ==============================================================================
# 7. TRY SELECTED TRAITS
# ==============================================================================

log_msg("=== Processing TRY Selected Traits dataset ===")
try_sel_orig <- read_parquet("data/stage1/try_selected_traits.parquet")
log_msg("Loaded TRY Selected Traits original: ", nrow(try_sel_orig), " rows")

try_sel_wfo <- fread("data/shipley_checks/wfo_verification/try_selected_traits_wfo_worldflora.csv", data.table = FALSE)
log_msg("Loaded TRY Selected Traits WFO matches: ", nrow(try_sel_wfo), " rows")

# Convert empty string taxonID to NA (match Python behavior)
try_sel_wfo$taxonID[trimws(try_sel_wfo$taxonID) == ""] <- NA

# Build source name (use AccSpeciesName)
try_sel_wfo$src_name <- try_sel_wfo$AccSpeciesName

# Ranking logic
try_sel_wfo$scientific_norm <- tolower(trimws(try_sel_wfo$scientificName))
try_sel_wfo$src_norm <- tolower(trimws(try_sel_wfo$src_name))
try_sel_wfo$matched_rank <- as.integer(!tolower(trimws(try_sel_wfo$Matched)) %in% c("true", "t", "1", "yes"))
try_sel_wfo$taxonid_rank <- as.integer(trimws(try_sel_wfo$taxonID) == "" | is.na(try_sel_wfo$taxonID))
try_sel_wfo$exact_rank <- as.integer(try_sel_wfo$scientific_norm != try_sel_wfo$src_norm)

try_sel_wfo$src_genus <- sapply(strsplit(try_sel_wfo$src_norm, " "), function(x) x[1])
try_sel_wfo$scientific_genus <- sapply(strsplit(try_sel_wfo$scientific_norm, " "), function(x) x[1])
try_sel_wfo$genus_rank <- as.integer(try_sel_wfo$scientific_genus != try_sel_wfo$src_genus)

try_sel_wfo$new_accepted_rank <- as.integer(!tolower(trimws(try_sel_wfo$New.accepted)) %in% c("true", "t", "1", "yes"))
try_sel_wfo$status_rank <- as.integer(tolower(trimws(try_sel_wfo$taxonomicStatus)) != "accepted")
try_sel_wfo$subseq_rank <- suppressWarnings(as.numeric(try_sel_wfo$Subseq))
try_sel_wfo$subseq_rank[is.na(try_sel_wfo$subseq_rank)] <- 9999999

# Create normalized join key BEFORE deduplication
try_sel_wfo$join_key_normalized <- tolower(trimws(try_sel_wfo$AccSpeciesName))

try_sel_wfo_sorted <- try_sel_wfo %>%
  arrange(join_key_normalized, matched_rank, taxonid_rank, exact_rank, genus_rank,
          new_accepted_rank, status_rank, subseq_rank) %>%
  group_by(join_key_normalized) %>%
  slice(1) %>%
  ungroup()

# Rename columns (keep join_key_normalized for merging)
try_sel_wfo_clean <- try_sel_wfo_sorted %>%
  select(
    AccSpeciesName,
    join_key_normalized,
    wf_spec_name = spec.name,
    wfo_taxon_id = taxonID,
    wfo_scientific_name = scientificName,
    wfo_taxonomic_status = taxonomicStatus,
    wfo_accepted_nameusage_id = acceptedNameUsageID,
    wfo_new_accepted = New.accepted,
    wfo_original_status = Old.status,
    wfo_original_id = Old.ID,
    wfo_original_name = Old.name,
    wfo_matched = Matched,
    wfo_unique = Unique,
    wfo_fuzzy = Fuzzy,
    wfo_fuzzy_distance = Fuzzy.dist
  )

# Merge with normalized keys (case-insensitive, whitespace-trimmed)
try_sel_orig$join_key_normalized <- tolower(trimws(try_sel_orig$AccSpeciesName))

try_sel_enriched <- try_sel_orig %>%
  left_join(try_sel_wfo_clean %>% select(-AccSpeciesName), by = "join_key_normalized") %>%
  select(-join_key_normalized) %>%
  # Convert empty strings to NA to match canonical NULL behavior
  mutate(across(where(is.character), ~na_if(., "")))

log_msg("Writing TRY Selected Traits enriched parquet...")
write_parquet(try_sel_enriched, file.path(output_dir, "try_selected_traits_worldflora_enriched.parquet"), compression = "snappy")
log_msg("TRY Selected Traits complete: ", nrow(try_sel_enriched), " rows\n")

log_msg("=== All enriched parquets created successfully ===")
log_msg("Output directory: ", output_dir)
