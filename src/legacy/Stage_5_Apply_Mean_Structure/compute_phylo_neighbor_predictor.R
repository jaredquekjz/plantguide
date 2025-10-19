#!/usr/bin/env Rscript

# Compute phylogenetic neighbor predictors p_k for a target species list
# given a reference EIVE table (donors) and a Newick tree.
#
# For axis k and target species j: p_k(j) = sum_i w_ij * E_k(i) / sum_i w_ij
# with weights w_ij = 1 / d_ij^x for i != j. If the target is also in the
# donor set, its self-weight is excluded (i.e., set to zero).
#
# CLI example:
#   Rscript src/Stage_5_Apply_Mean_Structure/compute_phylo_neighbor_predictor.R \
#     --target_csv data/new_traits.csv --target_species_col Species \
#     --reference_eive_csv artifacts/model_data_complete_case.csv \
#     --reference_species_col wfo_accepted_name \
#     --eive_cols EIVEres-L,EIVEres-T,EIVEres-M,EIVEres-R,EIVEres-N \
#     --phylogeny_newick data/phylogeny/eive_try_tree.nwk \
#     --x 2 --k_trunc 0 \
#     --output_csv results/mag_predictions_phylo_neighbor.csv

suppressPackageStartupMessages({
  library(ape)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a) && a != "") a else b

parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  kv <- list()
  for (i in seq_along(args)) {
    if (grepl("^--", args[[i]])) {
      key <- sub("^--", "", args[[i]])
      val <- if (i < length(args) && !grepl("^--", args[[i+1]])) args[[i+1]] else ""
      kv[[key]] <- val
    }
  }
  kv
}

args <- parse_args()
target_csv <- args[["target_csv"]]
target_species_col <- args[["target_species_col"]] %||% "Species"
ref_csv <- args[["reference_eive_csv"]]
ref_species_col <- args[["reference_species_col"]] %||% "wfo_accepted_name"
eive_cols <- strsplit(args[["eive_cols"]] %||% "EIVEres-L,EIVEres-T,EIVEres-M,EIVEres-R,EIVEres-N", ",")[[1]]
phylo_newick <- args[["phylogeny_newick"]] %||% "data/phylogeny/eive_try_tree.nwk"
xexp <- as.numeric(args[["x"]] %||% 2)
k_trunc <- as.integer(args[["k_trunc"]] %||% 0)
out_csv <- args[["output_csv"]] %||% "results/mag_predictions_phylo_neighbor.csv"

if (is.null(target_csv) || is.null(ref_csv)) {
  stop("Missing required flags: --target_csv and --reference_eive_csv")
}
stopifnot(file.exists(target_csv))
stopifnot(file.exists(ref_csv))
stopifnot(file.exists(phylo_newick))

cat(sprintf("Effective parameters:\n  target_csv=%s\n  target_species_col=%s\n  reference_eive_csv=%s\n  reference_species_col=%s\n  eive_cols=%s\n  phylogeny_newick=%s\n  x=%s\n  k_trunc=%d\n  output_csv=%s\n",
            target_csv, target_species_col, ref_csv, ref_species_col,
            paste(eive_cols, collapse=","), phylo_newick, xexp, k_trunc, out_csv))

target <- read.csv(target_csv, stringsAsFactors = FALSE, check.names = FALSE)
ref <- read.csv(ref_csv, stringsAsFactors = FALSE, check.names = FALSE)
if (!(target_species_col %in% names(target))) stop(sprintf("Missing target species column: %s", target_species_col))
if (!(ref_species_col %in% names(ref))) stop(sprintf("Missing reference species column: %s", ref_species_col))
miss_cols <- setdiff(eive_cols, names(ref))
if (length(miss_cols) > 0) stop(sprintf("Missing EIVE columns in reference: %s", paste(miss_cols, collapse=",")))

tree <- read.tree(phylo_newick)
tips <- tree$tip.label

target_names <- target[[target_species_col]]
ref_names <- ref[[ref_species_col]]

# Map names to tip labels (underscore convention)
target_tips <- gsub(" ", "_", target_names, fixed=TRUE)
ref_tips <- gsub(" ", "_", ref_names, fixed=TRUE)

# Keep only those present in tree
target_in <- target_tips %in% tips
ref_in <- ref_tips %in% tips
if (!any(target_in)) stop("None of the target species are present in the tree tips.")
if (!any(ref_in)) stop("None of the reference species are present in the tree tips.")

target_tips <- target_tips[target_in]
ref_tips <- ref_tips[ref_in]
target_rows <- which(target_in)
ref_rows <- which(ref_in)

# Prune tree to tips we need, then compute distances
tree2 <- keep.tip(tree, unique(c(target_tips, ref_tips)))
cop <- cophenetic.phylo(tree2)

# Indices in cophenetic matrix
ti <- match(target_tips, rownames(cop))
ri <- match(ref_tips, colnames(cop))
D <- cop[ti, ri, drop=FALSE]

# Weight matrix W for targets (rows) by donors (cols)
W <- matrix(0, nrow(D), ncol(D))
pos <- which(D > 0)
W[pos] <- 1 / (D[pos]^xexp)

# Exclude self if a target is also a donor (same tip label)
for (j in seq_len(nrow(D))) {
  matches <- which(colnames(D) == rownames(D)[j])
  if (length(matches) > 0) W[j, matches] <- 0
}

# Optional k-NN truncation
if (k_trunc > 0) {
  for (j in seq_len(nrow(W))) {
    ord <- order(D[j, ], na.last = NA)
    keep <- head(ord[D[j, ord] > 0], k_trunc)
    drop <- setdiff(seq_len(ncol(W)), keep)
    if (length(drop) > 0) W[j, drop] <- 0
  }
}

den <- rowSums(W)
den[den <= .Machine$double.eps] <- NA_real_

out <- data.frame(
  target_row = target_rows,
  species = target_names[target_rows],
  stringsAsFactors = FALSE
)

for (axis in eive_cols) {
  Ek <- ref[[axis]][ref_rows]
  num <- W %*% matrix(Ek, ncol=1)
  pk <- as.numeric(num) / den
  out[[paste0(axis, "_phylo")]] <- pk
}

dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)
write.csv(out, out_csv, row.names = FALSE)
cat(sprintf("Wrote phylo neighbor predictions: %s (rows %d)\n", out_csv, nrow(out)))

