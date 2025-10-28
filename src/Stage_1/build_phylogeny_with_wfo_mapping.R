#!/usr/bin/env Rscript
#
# Build phylogenetic tree with verified GBOTB→WFO mapping.
#
# This script replaces build_phylogeny_from_species.R with a robust approach:
# 1. Load species list with wfo_taxon_ids
# 2. Load GBOTB→WFO mapping (from WorldFlora canonical matching)
# 3. Match our species to GBOTB via WFO IDs
# 4. Build tree using V.PhyloMaker2 with GBOTB names
# 5. Map tree tips back to WFO IDs with 100% verification
#
# Usage:
# env R_LIBS_USER=/home/olier/ellenberg/.Rlib \
#   /usr/bin/Rscript src/Stage_1/build_phylogeny_with_wfo_mapping.R \
#     --species_csv=data/phylogeny/mixgb_shortlist_species_20251023.csv \
#     --gbotb_wfo_mapping=data/phylogeny/gbotb_wfo_mapping.parquet \
#     --output_newick=data/phylogeny/mixgb_shortlist_full_tree_20251026_wfo.nwk \
#     --output_log=logs/stage1_phylogeny/build_tree_with_wfo_mapping_20251026.log

parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  opts <- list()
  for (a in args) {
    if (!startsWith(a, "--")) next
    kv <- sub("^--", "", a)
    if (grepl("=", kv, fixed = TRUE)) {
      parts <- strsplit(kv, "=", fixed = TRUE)[[1]]
      opts[[parts[1]]] <- parts[2]
    }
  }
  required <- c("species_csv", "gbotb_wfo_mapping", "output_newick")
  for (r in required) {
    if (is.null(opts[[r]]) || !nzchar(opts[[r]])) {
      stop(sprintf("--%s is required", r))
    }
  }
  opts
}

log_msg <- function(...) {
  cat(..., "\n", sep = "")
  flush.console()
}

opts <- parse_args()

# Check input files
if (!file.exists(opts$species_csv)) {
  stop(sprintf("Species CSV not found: %s", opts$species_csv))
}
if (!file.exists(opts$gbotb_wfo_mapping)) {
  stop(sprintf("GBOTB→WFO mapping not found: %s", opts$gbotb_wfo_mapping))
}

log_msg("================================================================================")
log_msg("BUILD PHYLOGENETIC TREE WITH VERIFIED WFO MAPPING")
log_msg("================================================================================")
log_msg("Species CSV: ", opts$species_csv)
log_msg("GBOTB→WFO mapping: ", opts$gbotb_wfo_mapping)
log_msg("Output tree: ", opts$output_newick)
log_msg("")

# Load packages
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(arrow)  # For reading parquet
  library(V.PhyloMaker2)
  library(ape)
})

log_msg("[1] Loading species list")
species_df <- readr::read_csv(opts$species_csv, show_col_types = FALSE)
log_msg("  Input species: ", nrow(species_df))

# Verify wfo_taxon_id column exists
if (!"wfo_taxon_id" %in% names(species_df)) {
  stop("species_csv must contain wfo_taxon_id column")
}

# Remove any species without WFO ID
species_df <- species_df %>%
  filter(!is.na(wfo_taxon_id), nzchar(trimws(wfo_taxon_id)))
log_msg("  Species with WFO IDs: ", nrow(species_df))

log_msg("")
log_msg("[2] Loading GBOTB→WFO mapping")
gbotb_mapping <- arrow::read_parquet(opts$gbotb_wfo_mapping)
log_msg("  GBOTB species in mapping: ", nrow(gbotb_mapping))

# Filter to species with WFO IDs
gbotb_mapping <- gbotb_mapping %>%
  filter(!is.na(wfo_taxon_id), nzchar(trimws(wfo_taxon_id)))
log_msg("  GBOTB species with WFO IDs: ", nrow(gbotb_mapping))

log_msg("")
log_msg("[3] Matching our species to GBOTB")

# Match species to GBOTB via wfo_taxon_id
matched <- species_df %>%
  left_join(gbotb_mapping, by = "wfo_taxon_id", suffix = c("_input", "_gbotb"))

# Check match coverage
n_matched <- sum(!is.na(matched$species))  # GBOTB species column
n_unmatched <- nrow(matched) - n_matched

log_msg("  Matched to GBOTB: ", n_matched, " / ", nrow(matched), " (",
        sprintf("%.1f%%", 100 * n_matched / nrow(matched)), ")")

if (n_unmatched > 0) {
  log_msg("")
  log_msg("  WARNING: ", n_unmatched, " species could not be matched to GBOTB")
  log_msg("  These species will be EXCLUDED from the phylogenetic tree")

  # Show sample of unmatched
  unmatched_sample <- matched %>%
    filter(is.na(species)) %>%
    head(10)

  log_msg("")
  log_msg("  Sample unmatched species:")
  for (i in seq_len(nrow(unmatched_sample))) {
    wfo_id <- if (!is.null(unmatched_sample$wfo_taxon_id)) unmatched_sample$wfo_taxon_id[i] else "NA"
    sci_name <- if (!is.null(unmatched_sample$wfo_scientific_name_input)) {
      unmatched_sample$wfo_scientific_name_input[i]
    } else if (!is.null(unmatched_sample$wfo_scientific_name)) {
      unmatched_sample$wfo_scientific_name[i]
    } else {
      "NA"
    }
    log_msg("    ", wfo_id, " - ", sci_name)
  }
}

# Filter to matched species only
matched <- matched %>%
  filter(!is.na(species))

log_msg("")
log_msg("  Final species for tree: ", nrow(matched))

log_msg("")
log_msg("[4] Preparing species list for V.PhyloMaker2")

# Create species list in V.PhyloMaker format
# Use GBOTB species names and taxonomy (genus_gbotb, family_gbotb)
sp_list <- matched %>%
  select(species, genus = genus_gbotb, family = family_gbotb) %>%
  distinct()

log_msg("  Unique GBOTB species for phylo.maker: ", nrow(sp_list))

# Check family coverage
n_missing_family <- sum(is.na(sp_list$family) | sp_list$family == "" | sp_list$family == "Unknown")
if (n_missing_family > 0) {
  log_msg("  WARNING: ", n_missing_family, " species lack family; V.PhyloMaker2 will use scenario S3 placement")
}

log_msg("")
log_msg("[5] Building phylogenetic tree with V.PhyloMaker2")

# Load GBOTB megaphylogeny
data("GBOTB.extended.TPL", package = "V.PhyloMaker2")
if (!exists("GBOTB.extended.TPL")) {
  stop("GBOTB.extended.TPL dataset not available")
}

log_msg("  Running phylo.maker (scenario S3)...")
phy_out <- V.PhyloMaker2::phylo.maker(sp_list, GBOTB.extended.TPL, scenarios = "S3")

if (is.null(phy_out$scenario.3)) {
  stop("phylo.maker returned NULL scenario.3")
}

tree <- phy_out$scenario.3
log_msg("  ✓ Tree built with ", length(tree$tip.label), " tips")

log_msg("")
log_msg("[6] Mapping tree tips to WFO IDs")

# Create lookup: GBOTB species → wfo_taxon_id
# Note: Some GBOTB species may map to multiple WFO IDs (if our input has duplicates)
# We take distinct GBOTB→WFO pairs
gbotb_to_wfo <- matched %>%
  select(species, wfo_taxon_id) %>%
  distinct()

log_msg("  GBOTB species → WFO ID mappings: ", nrow(gbotb_to_wfo))

# Check if any GBOTB species map to multiple WFO IDs
duplicates <- gbotb_to_wfo %>%
  group_by(species) %>%
  filter(n() > 1)

if (nrow(duplicates) > 0) {
  n_dup_species <- length(unique(duplicates$species))
  log_msg("  WARNING: ", n_dup_species, " GBOTB species map to multiple WFO IDs")
  log_msg("  Using first occurrence for tree tip labeling")

  gbotb_to_wfo <- gbotb_to_wfo %>%
    group_by(species) %>%
    slice(1) %>%
    ungroup()
}

# Match tree tips to WFO IDs
matched_wfo <- gbotb_to_wfo$wfo_taxon_id[match(tree$tip.label, gbotb_to_wfo$species)]

n_mapped <- sum(!is.na(matched_wfo))
n_unmapped <- length(matched_wfo) - n_mapped

log_msg("  Tree tips mapped to WFO IDs: ", n_mapped, " / ", length(tree$tip.label),
        " (", sprintf("%.1f%%", 100 * n_mapped / length(tree$tip.label)), ")")

if (n_unmapped > 0) {
  log_msg("")
  log_msg("  ERROR: ", n_unmapped, " tree tips could not be mapped to WFO IDs")
  log_msg("  This indicates V.PhyloMaker2 modified species labels")

  unmapped_tips <- tree$tip.label[is.na(matched_wfo)]
  log_msg("")
  log_msg("  Sample unmapped tips:")
  for (tip in head(unmapped_tips, 10)) {
    log_msg("    ", tip)
  }

  log_msg("")
  log_msg("  CRITICAL: Cannot proceed with unmapped tips")
  log_msg("  Tree building FAILED - 100% WFO ID mapping required")
  quit(status = 1)
}

log_msg("  ✓ All tree tips successfully mapped to WFO IDs")

# Set tip labels: wfo-XXXXXXXXXX|Genus_species
tree$tip.label <- paste(matched_wfo, tree$tip.label, sep = "|")

log_msg("")
log_msg("[7] Verification")

# Verify all tips have wfo- prefix
all_have_wfo <- all(grepl("^wfo-", tree$tip.label))
if (all_have_wfo) {
  log_msg("  ✓ All tips have wfo- prefix")
} else {
  n_missing <- sum(!grepl("^wfo-", tree$tip.label))
  log_msg("  ERROR: ", n_missing, " tips missing wfo- prefix")
  quit(status = 1)
}

# Check for Species|Species fallback pattern (should be ZERO)
# Extract species names after | and before |, check if they match (indicating fallback)
tip_parts <- strsplit(tree$tip.label, "\\|", fixed = TRUE)
has_fallback <- sapply(tip_parts, function(x) {
  if (length(x) == 2 && !startsWith(x[1], "wfo-")) {
    # If first part doesn't start with wfo-, it's a fallback
    return(TRUE)
  }
  return(FALSE)
})
n_fallback <- sum(has_fallback)
if (n_fallback > 0) {
  log_msg("  ERROR: ", n_fallback, " tips have fallback Species|Species format")
  quit(status = 1)
} else {
  log_msg("  ✓ No fallback Species|Species patterns detected")
}

log_msg("")
log_msg("[8] Writing tree")

# Create output directory
out_dir <- dirname(opts$output_newick)
if (!dir.exists(out_dir)) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
}

ape::write.tree(tree, file = opts$output_newick)
file_size_kb <- file.size(opts$output_newick) / 1024

log_msg("  ✓ Newick written to: ", opts$output_newick)
log_msg("  ✓ File size: ", sprintf("%.1f", file_size_kb), " KB")
log_msg("  ✓ Tree tips: ", length(tree$tip.label))

log_msg("")
log_msg("================================================================================")
log_msg("✓ PHYLOGENETIC TREE BUILT SUCCESSFULLY")
log_msg("================================================================================")
log_msg("Summary:")
log_msg("  Input species: ", nrow(species_df))
log_msg("  Matched to GBOTB: ", nrow(matched))
log_msg("  Tree tips: ", length(tree$tip.label))
log_msg("  WFO ID coverage: 100.0%")
log_msg("")
log_msg("Next step:")
log_msg("  Extract phylogenetic eigenvectors:")
log_msg("  conda run -n AI python src/Stage_1/build_phylogenetic_eigenvectors.py \\")
log_msg("    --tree=", opts$output_newick, " \\")
log_msg("    --output=model_data/inputs/phylo_eigenvectors_11680_20251026.csv")
log_msg("================================================================================")
