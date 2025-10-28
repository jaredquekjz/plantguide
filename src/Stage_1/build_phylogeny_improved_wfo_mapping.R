#!/usr/bin/env Rscript
#
# Build phylogenetic tree with improved WFO ID mapping.
#
# Root cause: Original script had 93% WFO coverage due to infraspecific taxa.
# Solution: Use GBOTB→WFO mapping for species-level tips, extract parent species
#           for infraspecific taxa.
#
# Fixes:
# 1. Species-level tips (10,844): Map via GBOTB→WFO lookup (73,354 species)
# 2. Infraspecific tips (920): Extract parent species, map to input WFO IDs
#
# Expected coverage: ~100% (vs original 93%)
#
# Usage:
# env R_LIBS_USER=/home/olier/ellenberg/.Rlib \
#   /usr/bin/Rscript src/Stage_1/build_phylogeny_improved_wfo_mapping.R \
#     --species_csv=data/phylogeny/mixgb_shortlist_species_20251023.csv \
#     --gbotb_wfo_mapping=data/phylogeny/gbotb_wfo_mapping.parquet \
#     --output_newick=data/phylogeny/mixgb_shortlist_tree_20251026_wfo_improved.nwk \
#     --output_log=logs/stage1_phylogeny/build_tree_improved_wfo_20251026.log

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
log_msg("BUILD PHYLOGENETIC TREE WITH IMPROVED WFO MAPPING")
log_msg("================================================================================")
log_msg("Species CSV: ", opts$species_csv)
log_msg("GBOTB→WFO mapping: ", opts$gbotb_wfo_mapping)
log_msg("Output tree: ", opts$output_newick)
log_msg("")

# Load packages
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(arrow)
  library(V.PhyloMaker2)
  library(ape)
})

log_msg("[1] Loading species list")
species_df <- readr::read_csv(opts$species_csv, show_col_types = FALSE)
log_msg("  Input species: ", nrow(species_df))

# Extract species epithet from scientific name
species_df$species_epithet <- sapply(strsplit(species_df$wfo_scientific_name, " "),
                                      function(x) if(length(x) >= 2) x[2] else "")

# Create species labels for phylo.maker
species_df$species_label <- paste(species_df$genus, species_df$species_epithet, sep = "_")

# Identify infraspecific taxa (subsp., var., f.)
species_df$is_infraspecific <- grepl("subsp\\.|var\\.|f\\.|×", species_df$wfo_scientific_name)
n_infraspecific <- sum(species_df$is_infraspecific)

log_msg("  Species-level taxa: ", nrow(species_df) - n_infraspecific)
log_msg("  Infraspecific taxa: ", n_infraspecific)

log_msg("")
log_msg("[2] Loading GBOTB→WFO mapping")
gbotb_wfo <- arrow::read_parquet(opts$gbotb_wfo_mapping)
log_msg("  GBOTB species with WFO IDs: ", nrow(gbotb_wfo))

# Create GBOTB species_label for matching
gbotb_wfo$species_label <- gsub(" ", "_", gbotb_wfo$species)

log_msg("")
log_msg("[3] Building phylogenetic tree with V.PhyloMaker2")

# Prepare species list for phylo.maker
sp_list <- data.frame(
  species = species_df$species_label,
  genus = species_df$genus,
  family = species_df$family,
  stringsAsFactors = FALSE
)

log_msg("  Running phylo.maker (scenario S3)...")
data("GBOTB.extended.TPL", package = "V.PhyloMaker2")
phy_out <- V.PhyloMaker2::phylo.maker(sp_list, GBOTB.extended.TPL, scenarios = "S3")

if (is.null(phy_out$scenario.3)) {
  stop("phylo.maker returned NULL scenario.3")
}

tree <- phy_out$scenario.3
log_msg("  ✓ Tree built with ", length(tree$tip.label), " tips")

log_msg("")
log_msg("[4] Mapping tree tips to WFO IDs (improved algorithm)")

# Strategy:
# 1. Try exact match with GBOTB→WFO mapping (for species-level tips)
# 2. Try exact match with original input (for newly added species)
# 3. For infraspecific taxa (Species|Species pattern), extract parent species

n_mapped <- 0
n_gbotb_lookup <- 0
n_input_lookup <- 0
n_infraspecific_lookup <- 0
n_failed <- 0

wfo_ids <- character(length(tree$tip.label))

for (i in seq_along(tree$tip.label)) {
  tip <- tree$tip.label[i]

  # Method 1: GBOTB→WFO lookup (for species from backbone)
  gbotb_match <- gbotb_wfo$wfo_taxon_id[match(tip, gbotb_wfo$species_label)]
  if (!is.na(gbotb_match)) {
    wfo_ids[i] <- gbotb_match
    n_gbotb_lookup <- n_gbotb_lookup + 1
    n_mapped <- n_mapped + 1
    next
  }

  # Method 2: Direct match with input species (for newly added species)
  input_match <- species_df$wfo_taxon_id[match(tip, species_df$species_label)]
  if (!is.na(input_match)) {
    wfo_ids[i] <- input_match
    n_input_lookup <- n_input_lookup + 1
    n_mapped <- n_mapped + 1
    next
  }

  # Method 3: Infraspecific taxa (Species|Species pattern)
  # Extract parent species name from duplicated pattern
  if (grepl("\\|", tip)) {
    # Extract species name before |
    parent_species <- strsplit(tip, "\\|")[[1]][1]

    # Try GBOTB→WFO lookup for parent
    parent_gbotb <- gbotb_wfo$wfo_taxon_id[match(parent_species, gbotb_wfo$species_label)]
    if (!is.na(parent_gbotb)) {
      wfo_ids[i] <- parent_gbotb
      n_infraspecific_lookup <- n_infraspecific_lookup + 1
      n_mapped <- n_mapped + 1
      next
    }

    # Try input lookup for parent (without subsp./var.)
    # Extract genus and species epithet from parent
    parent_parts <- strsplit(parent_species, "_")[[1]]
    if (length(parent_parts) >= 2) {
      parent_binomial <- paste(parent_parts[1], parent_parts[2])
      # Find in input by matching binomial at start of scientific name
      input_infraspecific <- species_df[species_df$is_infraspecific, ]
      for (j in seq_len(nrow(input_infraspecific))) {
        if (startsWith(input_infraspecific$wfo_scientific_name[j], parent_binomial)) {
          wfo_ids[i] <- input_infraspecific$wfo_taxon_id[j]
          n_infraspecific_lookup <- n_infraspecific_lookup + 1
          n_mapped <- n_mapped + 1
          break
        }
      }
      if (wfo_ids[i] != "") next
    }
  }

  # Failed to map
  n_failed <- n_failed + 1
}

log_msg("  Mapping results:")
log_msg("    GBOTB→WFO lookup: ", n_gbotb_lookup)
log_msg("    Input direct match: ", n_input_lookup)
log_msg("    Infraspecific parent: ", n_infraspecific_lookup)
log_msg("    Failed: ", n_failed)
log_msg("")
log_msg("  ✓ WFO ID coverage: ", n_mapped, " / ", length(tree$tip.label),
        " (", sprintf("%.1f%%", 100 * n_mapped / length(tree$tip.label)), ")")

if (n_failed > 0) {
  log_msg("")
  log_msg("  WARNING: ", n_failed, " tips could not be mapped to WFO IDs")
  failed_tips <- tree$tip.label[wfo_ids == ""]
  log_msg("  Sample unmapped tips:")
  for (tip in head(failed_tips, 10)) {
    log_msg("    ", tip)
  }
}

# Set tip labels: wfo-ID|Species_name
for (i in seq_along(tree$tip.label)) {
  if (wfo_ids[i] != "") {
    tree$tip.label[i] <- paste(wfo_ids[i], tree$tip.label[i], sep = "|")
  } else {
    # Fallback: keep original label duplicated
    tree$tip.label[i] <- paste(tree$tip.label[i], tree$tip.label[i], sep = "|")
  }
}

log_msg("")
log_msg("[5] Verification")

# Check all tips have wfo- prefix or Species|Species fallback
n_wfo <- sum(grepl("^wfo-", tree$tip.label))
n_fallback <- length(tree$tip.label) - n_wfo

log_msg("  WFO-prefixed tips: ", n_wfo, " / ", length(tree$tip.label),
        " (", sprintf("%.1f%%", 100 * n_wfo / length(tree$tip.label)), ")")

if (n_fallback > 0) {
  log_msg("  Fallback tips (Species|Species): ", n_fallback)
}

log_msg("")
log_msg("[6] Writing tree")

# Create output directory
out_dir <- dirname(opts$output_newick)
if (!dir.exists(out_dir)) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
}

ape::write.tree(tree, file = opts$output_newick)
file_size_kb <- file.size(opts$output_newick) / 1024

log_msg("  ✓ Newick written to: ", opts$output_newick)
log_msg("  ✓ File size: ", sprintf("%.1f KB", file_size_kb))
log_msg("  ✓ Tree tips: ", length(tree$tip.label))

log_msg("")
log_msg("================================================================================")
log_msg("✓ PHYLOGENETIC TREE BUILT SUCCESSFULLY")
log_msg("================================================================================")
log_msg("Summary:")
log_msg("  Input species: ", nrow(species_df))
log_msg("  Tree tips: ", length(tree$tip.label))
log_msg("  WFO ID coverage: ", sprintf("%.1f%%", 100 * n_wfo / length(tree$tip.label)))
log_msg("")
log_msg("Improvement over original:")
log_msg("  Original coverage: 93.0% (10,844 / 11,670)")
log_msg("  New coverage: ", sprintf("%.1f%%", 100 * n_wfo / length(tree$tip.label)))
log_msg("")
log_msg("Next step:")
log_msg("  Extract phylogenetic eigenvectors:")
log_msg("  conda run -n AI python src/Stage_1/build_phylogenetic_eigenvectors.py \\")
log_msg("    --tree=", opts$output_newick, " \\")
log_msg("    --output=model_data/inputs/phylo_eigenvectors_11680_20251026.csv")
log_msg("================================================================================")
