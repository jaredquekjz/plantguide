#!/usr/bin/env Rscript
# Prune full phylogenetic tree to 1,084 modelling species for Tier 1 p_phylo calculation
# Date: 2025-10-29
# Purpose: Create context-appropriate phylogenetic neighborhood for hyperparameter tuning

library(ape)

cat("=== Pruning Tree for Tier 1 Modelling Subset ===\n\n")

# Load full tree
tree_path <- "data/stage1/phlogeny/mixgb_tree_11676_species_20251027.nwk"
cat(sprintf("Loading full tree: %s\n", tree_path))
phy <- read.tree(tree_path)
cat(sprintf("Full tree: %d tips\n\n", length(phy$tip.label)))

# Load modelling master to get 1,084 species
modelling_path <- "model_data/inputs/modelling_master_1084_20251029.csv"
cat(sprintf("Loading modelling species: %s\n", modelling_path))
modelling <- read.csv(modelling_path, stringsAsFactors = FALSE)
cat(sprintf("Modelling dataset: %d species\n\n", nrow(modelling)))

# Load mapping to get tree tips for these species
mapping_path <- "data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11676.csv"
cat(sprintf("Loading WFO-to-tree mapping: %s\n", mapping_path))
mapping <- read.csv(mapping_path, stringsAsFactors = FALSE)
cat(sprintf("Mapping file: %d entries\n\n", nrow(mapping)))

# Get tree tips for 1,084 modelling species
modelling_ids <- as.character(modelling$wfo_taxon_id)
modelling_mapping <- mapping[mapping$wfo_taxon_id %in% modelling_ids, ]
cat(sprintf("Species in mapping: %d / %d\n", nrow(modelling_mapping), length(modelling_ids)))

# Get tree tips that are actually present in the tree
modelling_tips <- modelling_mapping$tree_tip
tips_in_tree <- modelling_tips[modelling_tips %in% phy$tip.label]
cat(sprintf("Tree tips found in full tree: %d\n\n", length(tips_in_tree)))

# Prune tree to modelling subset
cat("Pruning tree to modelling subset...\n")
phy_1084 <- keep.tip(phy, tips_in_tree)
cat(sprintf("Pruned tree: %d tips\n\n", length(phy_1084$tip.label)))

# Save pruned tree
output_path <- "data/stage1/phlogeny/mixgb_tree_1084_modelling_20251029.nwk"
cat(sprintf("Saving pruned tree: %s\n", output_path))
write.tree(phy_1084, output_path)

cat("\n=== Summary ===\n")
cat(sprintf("Input tree: %d tips\n", length(phy$tip.label)))
cat(sprintf("Modelling species: %d\n", nrow(modelling)))
cat(sprintf("Output tree: %d tips\n", length(phy_1084$tip.label)))
cat(sprintf("Coverage: %.1f%%\n", 100 * length(phy_1084$tip.label) / nrow(modelling)))
cat("\nPruned tree saved successfully!\n")
