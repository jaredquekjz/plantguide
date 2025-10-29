#!/usr/bin/env Rscript
# Convert tree tip labels from WFO-ID|Species_name format to just Species name (spaces)

library(ape)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Usage: Rscript convert_tree_to_scientific_names.R <input.nwk> <output.nwk>")
}

input_file <- args[1]
output_file <- args[2]

# Read tree
tree <- read.tree(input_file)
cat(sprintf("[tree] Loaded tree with %d tips\n", length(tree$tip.label)))

# Extract scientific names from "wfo-ID|Species_name" format
# Replace underscores with spaces
tree$tip.label <- sapply(tree$tip.label, function(label) {
  # Split by pipe, take second part
  parts <- strsplit(label, "\\|")[[1]]
  if (length(parts) == 2) {
    name <- parts[2]
  } else {
    name <- label  # Fallback if no pipe found
  }
  # Replace underscores with spaces
  gsub("_", " ", name)
})

# Write modified tree
write.tree(tree, file = output_file)
cat(sprintf("[tree] Wrote tree with scientific name labels to: %s\n", output_file))
