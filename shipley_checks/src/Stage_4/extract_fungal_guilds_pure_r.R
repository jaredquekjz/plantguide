#!/usr/bin/env Rscript
#
# Pure R Extraction: Fungal Guilds (NO DuckDB)
#
# Purpose:
#   Replicate the 8-CTE Python DuckDB extraction using only R packages:
#   - arrow: Read parquet files
#   - dplyr: Data manipulation (filter, mutate, join, group_by, summarize)
#   - stringr: Text operations (str_detect, word)
#   - purrr: List operations
#
# This is an EXPERIMENT to test if pure R can exactly replicate Python DuckDB
# extraction for complex multi-source fungal guild classification.
#
# Usage:
#   Rscript shipley_checks/src/Stage_4/EXPERIMENT_extract_fungal_guilds_pure_r.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(stringr)
  library(purrr)
  library(readr)
})

cat("================================================================================\n")
cat("PURE R EXTRACTION: Fungal Guilds (NO DuckDB)\n")
cat("================================================================================\n")
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Paths
FUNGALTRAITS_PATH <- "data/fungaltraits/fungaltraits.parquet"
FUNGUILD_PATH <- "data/funguild/funguild.parquet"
PLANT_DATASET_PATH <- "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet"
GLOBI_PATH <- "data/stage1/globi_interactions_plants_wfo.parquet"

# ===============================================================================
# CTE 1: Target Plants
# ===============================================================================

cat("CTE 1: Loading target plants...\n")

target_plants <- read_parquet(PLANT_DATASET_PATH) %>%
  select(wfo_taxon_id, wfo_scientific_name, family, genus) %>%
  arrange(wfo_scientific_name)

cat("  ✓ Loaded", nrow(target_plants), "plants\n\n")

# ===============================================================================
# CTE 2: Extract Fungi from GloBI
# ===============================================================================

cat("CTE 2: Extracting fungi from GloBI (broad mining)...\n")

globi <- read_parquet(GLOBI_PATH)

hashost_fungi <- globi %>%
  filter(
    interactionTypeName %in% c('hasHost', 'parasiteOf', 'pathogenOf', 'interactsWith'),
    sourceTaxonKingdomName == 'Fungi',
    target_wfo_taxon_id %in% target_plants$wfo_taxon_id
  ) %>%
  mutate(
    # COALESCE(sourceTaxonGenusName, SPLIT_PART(sourceTaxonName, ' ', 1))
    genus = tolower(coalesce(sourceTaxonGenusName, word(sourceTaxonName, 1))),
    phylum = sourceTaxonPhylumName
  ) %>%
  select(target_wfo_taxon_id, genus, phylum)

cat("  ✓ Extracted", nrow(hashost_fungi), "fungal interaction records\n\n")

# ===============================================================================
# CTE 3: Match with FungalTraits (PRIMARY)
# ===============================================================================

cat("CTE 3: Matching with FungalTraits (PRIMARY)...\n")

fungaltraits <- read_parquet(FUNGALTRAITS_PATH)

# Homonym genera requiring phylum match
HOMONYM_GENERA <- c('adelolecia', 'campanulospora', 'caudospora',
                    'echinoascotheca', 'paranectriella', 'phialophoropsis')

ft_matches <- hashost_fungi %>%
  left_join(
    fungaltraits %>% mutate(GENUS_lower = tolower(GENUS)),
    by = c("genus" = "GENUS_lower"),
    relationship = "many-to-many"
  ) %>%
  filter(
    !is.na(GENUS),  # Successfully matched to FungalTraits
    # Homonym logic: For 6 homonyms, require Phylum match; for others, genus match sufficient
    (!genus %in% HOMONYM_GENERA) | (genus %in% HOMONYM_GENERA & phylum == Phylum)
  ) %>%
  mutate(
    source = 'FungalTraits',

    # Guild flags (10 complex classifications)
    is_pathogen = (primary_lifestyle == 'plant_pathogen' |
                   str_detect(tolower(coalesce(Secondary_lifestyle, '')), 'pathogen')),

    is_host_specific = !is.na(Specific_hosts),

    is_amf = (primary_lifestyle == 'arbuscular_mycorrhizal'),

    is_emf = (primary_lifestyle == 'ectomycorrhizal'),

    is_mycoparasite = (primary_lifestyle == 'mycoparasite'),

    is_entomopathogenic = (primary_lifestyle == 'animal_parasite' |
                           str_detect(tolower(coalesce(Secondary_lifestyle, '')), 'animal_parasite') |
                           str_detect(tolower(coalesce(Secondary_lifestyle, '')), 'arthropod')),

    is_endophytic = (primary_lifestyle %in% c('foliar_endophyte', 'root_endophyte') |
                     str_detect(tolower(coalesce(Secondary_lifestyle, '')), 'endophyte')),

    is_saprotrophic = (primary_lifestyle %in% c('wood_saprotroph', 'litter_saprotroph',
                                                 'soil_saprotroph', 'unspecified_saprotroph',
                                                 'dung_saprotroph', 'nectar/tap_saprotroph',
                                                 'pollen_saprotroph') |
                       str_detect(tolower(coalesce(Secondary_lifestyle, '')), 'saprotroph') |
                       str_detect(tolower(coalesce(Secondary_lifestyle, '')), 'decomposer')),

    is_trichoderma = (genus == 'trichoderma'),

    is_beauveria_metarhizium = (genus %in% c('beauveria', 'metarhizium'))
  ) %>%
  select(target_wfo_taxon_id, genus, source, is_pathogen, is_host_specific, is_amf,
         is_emf, is_mycoparasite, is_entomopathogenic, is_endophytic, is_saprotrophic,
         is_trichoderma, is_beauveria_metarhizium)

cat("  ✓ Matched", nrow(ft_matches), "records to FungalTraits\n")
cat("  ✓ Unique genera matched:", length(unique(ft_matches$genus)), "\n\n")

# ===============================================================================
# CTE 4: Get Unmatched Genera for FunGuild Fallback
# ===============================================================================

cat("CTE 4: Identifying unmatched genera for FunGuild fallback...\n")

matched_genera <- unique(ft_matches$genus)

unmatched_genera <- hashost_fungi %>%
  filter(!genus %in% matched_genera) %>%
  distinct(genus, target_wfo_taxon_id, phylum)

cat("  ✓ Identified", length(unique(unmatched_genera$genus)), "unmatched genera\n\n")

# ===============================================================================
# CTE 5: FunGuild Lookup Table (Confidence-Filtered)
# ===============================================================================

cat("CTE 5: Building FunGuild lookup (Probable + Highly Probable only)...\n")

funguild <- read_parquet(FUNGUILD_PATH)

fg_genus_lookup <- funguild %>%
  filter(
    taxonomicLevel %in% c('13', '20'),
    confidenceRanking %in% c('Probable', 'Highly Probable')  # EXCLUDE 'Possible'
  ) %>%
  mutate(
    # Extract genus name based on taxonomicLevel
    genus = case_when(
      taxonomicLevel == '13' ~ tolower(trimws(taxon)),
      taxonomicLevel == '20' ~ tolower(trimws(word(str_replace_all(taxon, '_', ' '), 1)))
    ),

    # Guild classification flags
    is_pathogen = (str_detect(guild, 'Plant Pathogen') | str_detect(guild, 'Animal Pathogen')),
    is_mycorrhizal = str_detect(guild, 'mycorrhizal'),
    is_emf = str_detect(guild, 'Ectomycorrhizal'),
    is_amf = str_detect(guild, 'Arbuscular'),
    is_biocontrol_guild = (str_detect(guild, 'Mycoparasite') | str_detect(guild, 'Fungicolous')),
    is_endophytic = str_detect(guild, 'Endophyte'),
    is_saprotrophic = str_detect(guild, 'Saprotroph')
  ) %>%
  distinct(genus, guild, confidenceRanking, is_pathogen, is_mycorrhizal, is_emf,
           is_amf, is_biocontrol_guild, is_endophytic, is_saprotrophic)

cat("  ✓ Built lookup for", length(unique(fg_genus_lookup$genus)), "genera\n\n")

# ===============================================================================
# CTE 6: Match Unmatched Genera with FunGuild (FALLBACK)
# ===============================================================================

cat("CTE 6: Matching unmatched genera with FunGuild (FALLBACK)...\n")

# Aggregate FunGuild lookup to one row per genus (one genus can have multiple guilds)
fg_genus_aggregated <- fg_genus_lookup %>%
  group_by(genus) %>%
  summarize(
    is_pathogen_fg = any(is_pathogen),
    is_amf_fg = any(is_amf),
    is_emf_fg = any(is_emf),
    is_biocontrol_guild_fg = any(is_biocontrol_guild),
    is_endophytic_fg = any(is_endophytic),
    is_saprotrophic_fg = any(is_saprotrophic),
    .groups = 'drop'
  )

fg_matches <- unmatched_genera %>%
  left_join(fg_genus_aggregated, by = "genus") %>%
  mutate(
    source = 'FunGuild',

    # Guild flags (FunGuild-derived, use coalesce to handle NAs from left join)
    is_pathogen = coalesce(is_pathogen_fg, FALSE),
    is_host_specific = FALSE,  # FunGuild doesn't have host-specific info
    is_amf = coalesce(is_amf_fg, FALSE),
    is_emf = coalesce(is_emf_fg, FALSE),
    is_mycoparasite = coalesce(is_biocontrol_guild_fg, FALSE),
    is_entomopathogenic = FALSE,  # Simplified (FunGuild doesn't distinguish)
    is_endophytic = coalesce(is_endophytic_fg, FALSE),
    is_saprotrophic = coalesce(is_saprotrophic_fg, FALSE),
    is_trichoderma = (genus == 'trichoderma'),
    is_beauveria_metarhizium = (genus %in% c('beauveria', 'metarhizium'))
  ) %>%
  select(target_wfo_taxon_id, genus, source, is_pathogen, is_host_specific, is_amf,
         is_emf, is_mycoparasite, is_entomopathogenic, is_endophytic, is_saprotrophic,
         is_trichoderma, is_beauveria_metarhizium)

cat("  ✓ Matched", nrow(fg_matches), "records to FunGuild\n\n")

# ===============================================================================
# CTE 7: UNION All Matches (FungalTraits + FunGuild)
# ===============================================================================

cat("CTE 7: Combining FungalTraits and FunGuild matches...\n")

all_matches <- bind_rows(ft_matches, fg_matches)

cat("  ✓ Combined", nrow(all_matches), "total records\n")
cat("  ✓ FungalTraits:", nrow(ft_matches), "records\n")
cat("  ✓ FunGuild:", nrow(fg_matches), "records\n\n")

# ===============================================================================
# CTE 8: Aggregate by Plant (LIST Aggregations)
# ===============================================================================

cat("CTE 8: Aggregating fungi by plant (LIST aggregations)...\n")

plant_fungi_aggregated <- all_matches %>%
  group_by(target_wfo_taxon_id) %>%
  summarize(
    # Pathogenic (CRITICAL: Use %in% TRUE to exclude NA values)
    pathogenic_fungi = list(unique(genus[is_pathogen %in% TRUE])),
    pathogenic_fungi_host_specific = list(unique(genus[is_pathogen %in% TRUE & is_host_specific %in% TRUE])),

    # Mycorrhizal
    amf_fungi = list(unique(genus[is_amf %in% TRUE])),
    emf_fungi = list(unique(genus[is_emf %in% TRUE])),

    # Biocontrol
    mycoparasite_fungi = list(unique(genus[is_mycoparasite %in% TRUE])),
    entomopathogenic_fungi = list(unique(genus[is_entomopathogenic %in% TRUE])),

    # Endophytic
    endophytic_fungi = list(unique(genus[is_endophytic %in% TRUE])),

    # Saprotrophic
    saprotrophic_fungi = list(unique(genus[is_saprotrophic %in% TRUE])),

    # Multi-guild counts
    trichoderma_count = sum(is_trichoderma, na.rm = TRUE),
    beauveria_metarhizium_count = sum(is_beauveria_metarhizium, na.rm = TRUE),

    # Source tracking (count DISTINCT genera, not rows)
    ft_genera_count = sum(source == 'FungalTraits'),
    fg_genera_count = n_distinct(genus[source == 'FunGuild']),

    .groups = 'drop'
  )

cat("  ✓ Aggregated", nrow(plant_fungi_aggregated), "plants with fungi\n\n")

# ===============================================================================
# Final Join and Output
# ===============================================================================

cat("Final step: Joining back to plants and calculating counts...\n")

result <- target_plants %>%
  left_join(plant_fungi_aggregated, by = c("wfo_taxon_id" = "target_wfo_taxon_id")) %>%
  mutate(
    # Replace NULL lists with empty lists
    pathogenic_fungi = map(pathogenic_fungi, ~if(is.null(.x)) character(0) else .x),
    pathogenic_fungi_host_specific = map(pathogenic_fungi_host_specific, ~if(is.null(.x)) character(0) else .x),
    amf_fungi = map(amf_fungi, ~if(is.null(.x)) character(0) else .x),
    emf_fungi = map(emf_fungi, ~if(is.null(.x)) character(0) else .x),
    mycoparasite_fungi = map(mycoparasite_fungi, ~if(is.null(.x)) character(0) else .x),
    entomopathogenic_fungi = map(entomopathogenic_fungi, ~if(is.null(.x)) character(0) else .x),
    endophytic_fungi = map(endophytic_fungi, ~if(is.null(.x)) character(0) else .x),
    saprotrophic_fungi = map(saprotrophic_fungi, ~if(is.null(.x)) character(0) else .x),

    # Calculate counts
    pathogenic_fungi_count = map_int(pathogenic_fungi, length),
    pathogenic_fungi_host_specific_count = map_int(pathogenic_fungi_host_specific, length),
    amf_fungi_count = map_int(amf_fungi, length),
    emf_fungi_count = map_int(emf_fungi, length),
    mycorrhizae_total_count = amf_fungi_count + emf_fungi_count,
    mycoparasite_fungi_count = map_int(mycoparasite_fungi, length),
    entomopathogenic_fungi_count = map_int(entomopathogenic_fungi, length),
    biocontrol_total_count = mycoparasite_fungi_count + entomopathogenic_fungi_count,
    endophytic_fungi_count = map_int(endophytic_fungi, length),
    saprotrophic_fungi_count = map_int(saprotrophic_fungi, length),

    # Replace NA counts with 0
    trichoderma_count = coalesce(trichoderma_count, 0L),
    beauveria_metarhizium_count = coalesce(beauveria_metarhizium_count, 0L),
    fungaltraits_genera = coalesce(ft_genera_count, 0L),
    funguild_genera = coalesce(fg_genera_count, 0L)
  ) %>%
  select(
    plant_wfo_id = wfo_taxon_id,
    wfo_scientific_name,
    family,
    genus,
    pathogenic_fungi,
    pathogenic_fungi_count,
    pathogenic_fungi_host_specific,
    pathogenic_fungi_host_specific_count,
    amf_fungi,
    amf_fungi_count,
    emf_fungi,
    emf_fungi_count,
    mycorrhizae_total_count,
    mycoparasite_fungi,
    mycoparasite_fungi_count,
    entomopathogenic_fungi,
    entomopathogenic_fungi_count,
    biocontrol_total_count,
    endophytic_fungi,
    endophytic_fungi_count,
    saprotrophic_fungi,
    saprotrophic_fungi_count,
    trichoderma_count,
    beauveria_metarhizium_count,
    fungaltraits_genera,
    funguild_genera
  )

cat("  ✓ Final dataset:", nrow(result), "plants\n\n")

# ===============================================================================
# Sort and Convert Lists to Pipe-Separated Strings (for CSV)
# ===============================================================================

cat("Preparing CSV output with sorted rows and sorted list columns...\n")

# Sort by plant_wfo_id (deterministic row order)
result <- result %>% arrange(plant_wfo_id)

# Convert list columns to sorted pipe-separated strings
list_cols <- c(
  'pathogenic_fungi',
  'pathogenic_fungi_host_specific',
  'amf_fungi',
  'emf_fungi',
  'mycoparasite_fungi',
  'entomopathogenic_fungi',
  'endophytic_fungi',
  'saprotrophic_fungi'
)

for (col in list_cols) {
  result[[col]] <- map_chr(result[[col]], function(x) {
    if (length(x) == 0) {
      return('')
    } else {
      return(paste(sort(x), collapse = '|'))
    }
  })
}

cat("  ✓ Lists converted to sorted pipe-separated strings\n\n")

# ===============================================================================
# Save CSV
# ===============================================================================

output_file <- "shipley_checks/validation/fungal_guilds_pure_r.csv"

cat("Saving CSV to", output_file, "...\n")
write_csv(result, output_file)

file_size_mb <- file.size(output_file) / 1024 / 1024
cat(sprintf("  ✓ Saved (%.2f MB)\n\n", file_size_mb))

# ===============================================================================
# Generate Checksums
# ===============================================================================

cat("Generating checksums...\n")

# Use system md5sum and sha256sum
md5_result <- system2("md5sum", args = output_file, stdout = TRUE)
md5_hash <- trimws(strsplit(md5_result, "\\s+")[[1]][1])

sha256_result <- system2("sha256sum", args = output_file, stdout = TRUE)
sha256_hash <- trimws(strsplit(sha256_result, "\\s+")[[1]][1])

cat("  MD5:   ", md5_hash, "\n")
cat("  SHA256:", sha256_hash, "\n\n")

# Save checksums
checksum_file <- "shipley_checks/validation/fungal_guilds_pure_r.checksums.txt"
writeLines(
  c(
    paste0("MD5:    ", md5_hash),
    paste0("SHA256: ", sha256_hash),
    "",
    paste0("File: ", output_file),
    paste0("Size: ", format(file.size(output_file), big.mark = ","), " bytes"),
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  ),
  checksum_file
)

cat("  ✓ Checksums saved to", checksum_file, "\n\n")

# ===============================================================================
# Summary Statistics
# ===============================================================================

cat("================================================================================\n")
cat("SUMMARY STATISTICS\n")
cat("================================================================================\n")

total_plants <- nrow(result)
plants_with_pathogens <- sum(result$pathogenic_fungi_count > 0)
plants_with_mycorrhizae <- sum(result$mycorrhizae_total_count > 0)
plants_with_biocontrol <- sum(result$biocontrol_total_count > 0)
plants_with_endophytic <- sum(result$endophytic_fungi_count > 0)
plants_with_saprotrophic <- sum(result$saprotrophic_fungi_count > 0)
total_ft_genera <- sum(result$fungaltraits_genera)
total_fg_genera <- sum(result$funguild_genera)

cat("Total plants:", format(total_plants, big.mark = ","), "\n\n")

cat("Plants with fungi by guild:\n")
cat(sprintf("  - Pathogenic: %s (%.1f%%)\n", format(plants_with_pathogens, big.mark = ","),
            plants_with_pathogens/total_plants*100))
cat(sprintf("  - Mycorrhizal: %s (%.1f%%)\n", format(plants_with_mycorrhizae, big.mark = ","),
            plants_with_mycorrhizae/total_plants*100))
cat(sprintf("  - Biocontrol: %s (%.1f%%)\n", format(plants_with_biocontrol, big.mark = ","),
            plants_with_biocontrol/total_plants*100))
cat(sprintf("  - Endophytic: %s (%.1f%%)\n", format(plants_with_endophytic, big.mark = ","),
            plants_with_endophytic/total_plants*100))
cat(sprintf("  - Saprotrophic: %s (%.1f%%)\n", format(plants_with_saprotrophic, big.mark = ","),
            plants_with_saprotrophic/total_plants*100))
cat("\n")

cat("Data source breakdown:\n")
cat(sprintf("  - FungalTraits genera: %s\n", format(total_ft_genera, big.mark = ",")))
cat(sprintf("  - FunGuild genera (fallback): %s\n", format(total_fg_genera, big.mark = ",")))
cat(sprintf("  - FunGuild contribution: %.1f%%\n", total_fg_genera/(total_ft_genera+total_fg_genera)*100))
cat("\n")

# Save summary
summary_file <- "shipley_checks/validation/fungal_guilds_pure_r.summary.txt"
writeLines(
  c(
    "PURE R EXTRACTION SUMMARY",
    paste(rep("=", 80), collapse = ""),
    "",
    paste("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    paste("CSV file:", output_file),
    sprintf("File size: %.2f MB", file_size_mb),
    "",
    paste("Total plants:", format(total_plants, big.mark = ",")),
    "",
    "Plants with fungi by guild:",
    sprintf("  - Pathogenic: %s (%.1f%%)", format(plants_with_pathogens, big.mark = ","),
            plants_with_pathogens/total_plants*100),
    sprintf("  - Mycorrhizal: %s (%.1f%%)", format(plants_with_mycorrhizae, big.mark = ","),
            plants_with_mycorrhizae/total_plants*100),
    sprintf("  - Biocontrol: %s (%.1f%%)", format(plants_with_biocontrol, big.mark = ","),
            plants_with_biocontrol/total_plants*100),
    sprintf("  - Endophytic: %s (%.1f%%)", format(plants_with_endophytic, big.mark = ","),
            plants_with_endophytic/total_plants*100),
    sprintf("  - Saprotrophic: %s (%.1f%%)", format(plants_with_saprotrophic, big.mark = ","),
            plants_with_saprotrophic/total_plants*100),
    "",
    "Data source breakdown:",
    sprintf("  - FungalTraits genera: %s", format(total_ft_genera, big.mark = ",")),
    sprintf("  - FunGuild genera (fallback): %s", format(total_fg_genera, big.mark = ",")),
    sprintf("  - FunGuild contribution: %.1f%%", total_fg_genera/(total_ft_genera+total_fg_genera)*100),
    "",
    "Checksums:",
    paste("  MD5:   ", md5_hash),
    paste("  SHA256:", sha256_hash)
  ),
  summary_file
)

cat("  ✓ Summary saved to", summary_file, "\n\n")

cat("================================================================================\n")
cat("Completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Output:", output_file, "\n")
cat("Checksums:", checksum_file, "\n")
cat("Summary:", summary_file, "\n")
cat("================================================================================\n")
