#!/usr/bin/env Rscript
#
# Check which V.PhyloMaker2 backbone (TPL, LCVP, WP) has best coverage
# for our WFO species list.
#
# This diagnostic helps determine whether:
# 1. LCVP/WP backbones (newer) have better WFO coverage than TPL
# 2. We need to implement WFO→TPL pre-standardization
#
# Usage:
# env R_LIBS_USER=/home/olier/ellenberg/.Rlib \
#   /usr/bin/Rscript src/Stage_1/check_vphylomaker_backbones.R \
#     --species_csv=data/phylogeny/mixgb_shortlist_species_20251023.csv

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
  if (is.null(opts$species_csv)) {
    stop("--species_csv is required")
  }
  opts
}

cat("================================================================================\n")
cat("CHECK V.PHYLOMAKER2 BACKBONE COVERAGE\n")
cat("================================================================================\n\n")

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(V.PhyloMaker2)
})

opts <- parse_args()

# Load our species
cat("[1] Loading our species list\n")
our_species <- readr::read_csv(opts$species_csv, show_col_types = FALSE)
cat(sprintf("  Our species: %d\n", nrow(our_species)))

# Extract species epithet from scientific name (format: "Genus species")
our_species$species_epithet <- sapply(strsplit(our_species$wfo_scientific_name, " "), function(x) if(length(x) >= 2) x[2] else "")

# Create species labels (Genus_species format used by V.PhyloMaker)
our_species$species_label <- paste(our_species$genus, our_species$species_epithet, sep = "_")

cat("\n[2] Loading V.PhyloMaker2 backbones\n")

# Load TPL backbone
data("tips.info.TPL", package = "V.PhyloMaker2")
cat(sprintf("  TPL species: %d\n", nrow(tips.info.TPL)))

# Load LCVP backbone
data("tips.info.LCVP", package = "V.PhyloMaker2")
cat(sprintf("  LCVP species: %d\n", nrow(tips.info.LCVP)))

# Load WP backbone
data("tips.info.WP", package = "V.PhyloMaker2")
cat(sprintf("  WP species: %d\n", nrow(tips.info.WP)))

cat("\n[3] Checking exact species name matches\n")

# Check exact matches
tpl_matches <- our_species$species_label %in% tips.info.TPL$species
lcvp_matches <- our_species$species_label %in% tips.info.LCVP$species
wp_matches <- our_species$species_label %in% tips.info.WP$species

cat(sprintf("  TPL exact matches: %d / %d (%.1f%%)\n",
    sum(tpl_matches), nrow(our_species),
    100 * sum(tpl_matches) / nrow(our_species)))

cat(sprintf("  LCVP exact matches: %d / %d (%.1f%%)\n",
    sum(lcvp_matches), nrow(our_species),
    100 * sum(lcvp_matches) / nrow(our_species)))

cat(sprintf("  WP exact matches: %d / %d (%.1f%%)\n",
    sum(wp_matches), nrow(our_species),
    100 * sum(wp_matches) / nrow(our_species)))

cat("\n[4] Checking genus-level matches\n")

# Check genus matches (for species that can be added via phylo.maker scenarios)
tpl_genus <- our_species$genus %in% tips.info.TPL$genus
lcvp_genus <- our_species$genus %in% tips.info.LCVP$genus
wp_genus <- our_species$genus %in% tips.info.WP$genus

cat(sprintf("  TPL genus matches: %d / %d (%.1f%%)\n",
    sum(tpl_genus), nrow(our_species),
    100 * sum(tpl_genus) / nrow(our_species)))

cat(sprintf("  LCVP genus matches: %d / %d (%.1f%%)\n",
    sum(lcvp_genus), nrow(our_species),
    100 * sum(lcvp_genus) / nrow(our_species)))

cat(sprintf("  WP genus matches: %d / %d (%.1f%%)\n",
    sum(wp_genus), nrow(our_species),
    100 * sum(wp_genus) / nrow(our_species)))

cat("\n[5] Sample unmatchable species (missing from all 3 backbones)\n")

# Species with no genus match in any backbone
no_genus_match <- !tpl_genus & !lcvp_genus & !wp_genus
unmatchable <- our_species[no_genus_match, ]

if (nrow(unmatchable) > 0) {
  cat(sprintf("  Unmatchable species (genus not in any backbone): %d\n", nrow(unmatchable)))
  cat("\n  Sample unmatchable species:\n")
  sample_unmatchable <- head(unmatchable, 20)
  for (i in seq_len(nrow(sample_unmatchable))) {
    cat(sprintf("    %s - %s %s (Family: %s)\n",
        sample_unmatchable$wfo_taxon_id[i],
        sample_unmatchable$genus[i],
        sample_unmatchable$species[i],
        sample_unmatchable$family[i]))
  }
} else {
  cat("  All genera are present in at least one backbone\n")
}

cat("\n================================================================================\n")
cat("SUMMARY\n")
cat("================================================================================\n")
cat(sprintf("Best exact match coverage: %s (%.1f%%)\n",
    c("TPL", "LCVP", "WP")[which.max(c(sum(tpl_matches), sum(lcvp_matches), sum(wp_matches)))],
    100 * max(sum(tpl_matches), sum(lcvp_matches), sum(wp_matches)) / nrow(our_species)))

cat(sprintf("Best genus coverage: %s (%.1f%%)\n",
    c("TPL", "LCVP", "WP")[which.max(c(sum(tpl_genus), sum(lcvp_genus), sum(wp_genus)))],
    100 * max(sum(tpl_genus), sum(lcvp_genus), sum(wp_genus)) / nrow(our_species)))

cat("\nRecommendation:\n")
if (max(sum(lcvp_matches), sum(wp_matches)) > sum(tpl_matches)) {
  best <- c("LCVP", "WP")[which.max(c(sum(lcvp_matches), sum(wp_matches)))]
  cat(sprintf("  Use GBOTB.extended.%s backbone - better coverage than TPL\n", best))
} else if (sum(tpl_matches) / nrow(our_species) >= 0.90) {
  cat("  TPL backbone has acceptable coverage (>90%) - use as is\n")
} else {
  cat("  None of the backbones have good exact match coverage\n")
  cat("  Need to implement WFO→TPL pre-standardization OR rely on genus/family matching\n")
}
cat("================================================================================\n")
