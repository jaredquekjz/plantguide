#!/usr/bin/env Rscript
# Compute phylogenetic VCV matrix from newick tree
#
# Usage:
# Rscript src/Stage_1/compute_vcv_matrix.R <tree_file> <output_csv>

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 2) {
  cat("Usage: Rscript compute_vcv_matrix.R <tree_file> <output_csv>\n")
  quit(status = 1)
}

tree_file <- args[1]
output_file <- args[2]

cat("================================================================================\n")
cat("PHYLOGENETIC VCV MATRIX COMPUTATION\n")
cat("================================================================================\n")
cat("Tree file:", tree_file, "\n")
cat("Output file:", output_file, "\n\n")

# Set library path to ONLY use custom .Rlib (avoid conda's broken R packages)
cat("[1] Setting R library path...\n")
.libPaths("/home/olier/ellenberg/.Rlib")
cat("  ✓ Using library:", .libPaths()[1], "\n\n")

# Load ape package
cat("[2] Loading ape package...\n")
library(ape)
cat("  ✓ ape loaded\n\n")

# Read tree
cat("[3] Reading phylogenetic tree...\n")
tree <- read.tree(tree_file)
cat("  ✓ Tree loaded\n")
cat("  Species:", length(tree$tip.label), "\n\n")

# Build VCV matrix
cat("[4] Building VCV matrix...\n")
vcv_matrix <- vcv(tree)
cat("  ✓ VCV matrix computed\n")
cat("  Dimensions:", nrow(vcv_matrix), "×", ncol(vcv_matrix), "\n")
cat("  Matrix size:", format(object.size(vcv_matrix), units = "MB"), "\n\n")

# Extract species IDs from tip labels (format: wfo-ID|Species_name)
tip_labels <- tree$tip.label
species_ids <- sapply(strsplit(tip_labels, "\\|"), "[", 1)

# Set row and column names
rownames(vcv_matrix) <- species_ids
colnames(vcv_matrix) <- species_ids

# Save VCV matrix
cat("[5] Saving VCV matrix...\n")
write.csv(vcv_matrix, output_file, row.names = TRUE)

file_size_mb <- file.size(output_file) / 1e6
cat("  ✓ Saved to:", output_file, "\n")
cat("  ✓ File size:", sprintf("%.2f", file_size_mb), "MB\n\n")

cat("================================================================================\n")
cat("✓ VCV MATRIX COMPUTATION COMPLETE\n")
cat("================================================================================\n")
