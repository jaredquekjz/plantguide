#!/usr/bin/env Rscript
#
# Calculate Faith's Phylogenetic Diversity using picante (gold standard)
#
# Usage:
#   Rscript calculate_faiths_pd.R <tree_file> <species_list_csv> <output_csv>
#
# Arguments:
#   tree_file: Path to Newick tree file
#   species_list_csv: CSV with columns 'guild_id' and 'tree_tip'
#   output_csv: Output CSV with columns 'guild_id', 'faiths_pd', 'n_species', 'n_species_in_tree'
#
# Dependencies: picante, ape

suppressPackageStartupMessages({
  library(ape)
  library(picante)
})

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) {
  cat("Usage: Rscript calculate_faiths_pd.R <tree_file> <species_list_csv> <output_csv>\n")
  quit(status = 1)
}

tree_file <- args[1]
species_list_csv <- args[2]
output_csv <- args[3]

cat("Faith's PD Calculator (picante)\n")
cat("================================\n\n")

# Load tree
cat(sprintf("Loading tree from: %s\n", tree_file))
tree <- read.tree(tree_file)
cat(sprintf("  Tips: %d\n", length(tree$tip.label)))

# Load species list
cat(sprintf("Loading species list from: %s\n", species_list_csv))
species_data <- read.csv(species_list_csv, stringsAsFactors = FALSE)
cat(sprintf("  Guilds: %d\n", length(unique(species_data$guild_id))))
cat(sprintf("  Species records: %d\n", nrow(species_data)))

# Create community matrix (guild × species)
# Each row is a guild, each column is a species
# 1 = species present, 0 = absent
cat("\nCreating community matrix...\n")

guilds <- unique(species_data$guild_id)
all_tips <- tree$tip.label

# Initialize matrix
comm_matrix <- matrix(0, nrow = length(guilds), ncol = length(all_tips))
rownames(comm_matrix) <- guilds
colnames(comm_matrix) <- all_tips

# Fill in presence/absence
for (i in seq_along(guilds)) {
  guild_id <- guilds[i]
  guild_species <- species_data$tree_tip[species_data$guild_id == guild_id]
  # Filter to species present in tree
  guild_species <- guild_species[guild_species %in% all_tips]
  if (length(guild_species) > 0) {
    comm_matrix[i, guild_species] <- 1
  }
}

# Remove columns (species) with zero occurrences across all guilds
species_present <- colSums(comm_matrix) > 0
comm_matrix <- comm_matrix[, species_present, drop = FALSE]

cat(sprintf("  Community matrix: %d guilds × %d species\n", nrow(comm_matrix), ncol(comm_matrix)))

# Calculate Faith's PD using picante
cat("\nCalculating Faith's PD using picante::pd()...\n")
pd_results <- pd(comm_matrix, tree, include.root = FALSE)

# include.root = FALSE is the standard approach
# It measures the phylogenetic diversity within the guild
# (not including the root-to-MRCA branch)

cat("  Done!\n")

# Prepare output
output <- data.frame(
  guild_id = rownames(pd_results),
  faiths_pd = pd_results$PD,
  n_species = pd_results$SR,  # Species richness (number of species in guild)
  stringsAsFactors = FALSE
)

# Also count how many were actually in the tree
output$n_species_in_tree <- sapply(output$guild_id, function(gid) {
  guild_tips <- species_data$tree_tip[species_data$guild_id == gid]
  sum(guild_tips %in% tree$tip.label)
})

# Write output
cat(sprintf("\nWriting output to: %s\n", output_csv))
write.csv(output, output_csv, row.names = FALSE)

# Summary statistics
cat("\nSummary Statistics:\n")
cat(sprintf("  Guilds calculated: %d\n", nrow(output)))
cat(sprintf("  Faith's PD range: %.2f - %.2f\n", min(output$faiths_pd), max(output$faiths_pd)))
cat(sprintf("  Median Faith's PD: %.2f\n", median(output$faiths_pd)))
cat(sprintf("  Species richness range: %d - %d\n", min(output$n_species), max(output$n_species)))

cat("\nDone!\n")
