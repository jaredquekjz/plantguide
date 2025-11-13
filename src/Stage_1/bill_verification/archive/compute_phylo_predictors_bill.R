#!/usr/bin/env Rscript
#
# Compute phylogenetic predictors for Bill's verification pipeline
# Adapted from compute_phylo_predictor_with_mapping.R
#

parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  opts <- list()
  for (a in args) {
    if (!startsWith(a, "--")) next
    kv <- sub("^--", "", a)
    if (grepl("=", kv, fixed = TRUE)) {
      parts <- strsplit(kv, "=", fixed = TRUE)[[1]]
      key <- parts[1]
      value <- parts[2]
    } else {
      key <- kv
      value <- ""
    }
    opts[[key]] <- value
  }
  required <- c("traits_csv", "eive_csv", "phylogeny_newick", "mapping_csv", "output_csv")
  for (r in required) {
    if (is.null(opts[[r]]) || !nzchar(opts[[r]])) stop(sprintf("--%s is required", r))
  }
  opts$x_exp <- as.numeric(ifelse(!is.null(opts$x_exp) && nzchar(opts$x_exp), opts$x_exp, 2))
  opts$k_trunc <- as.integer(ifelse(!is.null(opts$k_trunc) && nzchar(opts$k_trunc), opts$k_trunc, 0))
  opts
}

compute_p <- function(Dmat, values, x_exp = 2, k_trunc = 0) {
  n <- nrow(Dmat)
  if (n <= 1) return(rep(NA_real_, n))
  W <- matrix(0, n, n)
  mask <- is.finite(Dmat) & Dmat > 0
  W[mask] <- 1 / (Dmat[mask]^x_exp)
  good <- is.finite(values)
  if (!any(good)) return(rep(NA_real_, n))
  if (!all(good)) {
    W[, !good] <- 0
    values[!good] <- 0
  }
  if (k_trunc > 0 && n > k_trunc) {
    for (i in seq_len(n)) {
      row <- W[i, ]
      if (sum(row > 0, na.rm = TRUE) > k_trunc) {
        ord <- order(row, decreasing = TRUE)
        keep <- ord[seq_len(k_trunc)]
        row[-keep] <- 0
        W[i, ] <- row
      }
    }
  }
  num <- W %*% matrix(values, ncol = 1)
  den <- rowSums(W)
  den[den <= 0 | !is.finite(den)] <- NA_real_
  as.numeric(num) / den
}

opts <- parse_args()
if (!file.exists(opts$traits_csv)) stop(sprintf("Traits CSV not found: %s", opts$traits_csv))
if (!file.exists(opts$eive_csv)) stop(sprintf("EIVE CSV not found: %s", opts$eive_csv))
if (!file.exists(opts$phylogeny_newick)) stop(sprintf("Phylogeny not found: %s", opts$phylogeny_newick))
if (!file.exists(opts$mapping_csv)) stop(sprintf("Mapping CSV not found: %s", opts$mapping_csv))

message(sprintf("Loading traits from: %s", opts$traits_csv))
traits <- read.csv(opts$traits_csv, stringsAsFactors = FALSE)
if (!"wfo_taxon_id" %in% names(traits)) stop("Traits CSV must include wfo_taxon_id")
traits$wfo_taxon_id <- as.character(traits$wfo_taxon_id)

message(sprintf("Loading EIVE residuals from: %s", opts$eive_csv))
# Support hyphen (original), underscore (canonical), and period (R read.csv default)
EIVE_COLS_HYPHEN <- c("EIVEres-T", "EIVEres-M", "EIVEres-L", "EIVEres-N", "EIVEres-R")
EIVE_COLS_UNDERSCORE <- c("EIVEres_T", "EIVEres_M", "EIVEres_L", "EIVEres_N", "EIVEres_R")
EIVE_COLS_PERIOD <- c("EIVEres.T", "EIVEres.M", "EIVEres.L", "EIVEres.N", "EIVEres.R")
eive <- read.csv(opts$eive_csv, stringsAsFactors = FALSE)
if (!"wfo_taxon_id" %in% names(eive)) stop("EIVE CSV must include wfo_taxon_id")
eive$wfo_taxon_id <- as.character(eive$wfo_taxon_id)

# Detect which naming convention is used
if (all(EIVE_COLS_PERIOD %in% names(eive))) {
  EIVE_COLS <- EIVE_COLS_PERIOD
  message("Using period EIVE column names (EIVEres.L, etc.) - R read.csv default")
} else if (all(EIVE_COLS_HYPHEN %in% names(eive))) {
  EIVE_COLS <- EIVE_COLS_HYPHEN
  message("Using hyphenated EIVE column names (EIVEres-L, etc.)")
} else if (all(EIVE_COLS_UNDERSCORE %in% names(eive))) {
  EIVE_COLS <- EIVE_COLS_UNDERSCORE
  message("Using underscore EIVE column names (EIVEres_L, etc.)")
} else {
  stop(sprintf("EIVE CSV missing expected columns. Found: %s", paste(head(names(eive), 50), collapse=", ")))
}

message(sprintf("Loading WFO-to-tree mapping from: %s", opts$mapping_csv))
mapping <- read.csv(opts$mapping_csv, stringsAsFactors = FALSE)
if (!"wfo_taxon_id" %in% names(mapping)) stop("Mapping CSV must include wfo_taxon_id")
if (!"tree_tip" %in% names(mapping)) stop("Mapping CSV must include tree_tip")
mapping$wfo_taxon_id <- as.character(mapping$wfo_taxon_id)

message(sprintf("Loading phylogeny from: %s", opts$phylogeny_newick))
library(ape)
phy <- read.tree(opts$phylogeny_newick)
message(sprintf("Tree has %d tips", length(phy$tip.label)))

# Merge traits with EIVE and mapping
merged <- merge(traits[, c("wfo_taxon_id"), drop=FALSE], eive, by = "wfo_taxon_id", all.x = TRUE, sort = FALSE)
merged <- merge(merged, mapping[, c("wfo_taxon_id", "tree_tip"), drop=FALSE], by = "wfo_taxon_id", all.x = TRUE, sort = FALSE)

# Filter to species present in tree
present_idx <- which(!is.na(merged$tree_tip) & merged$tree_tip %in% phy$tip.label)
if (length(present_idx) < 2) stop(sprintf("Not enough species overlap: only %d species match tree", length(present_idx)))

message(sprintf("Found %d / %d species in phylogeny", length(present_idx), nrow(traits)))

# Subset phylogeny to matching species
selected_tips <- merged$tree_tip[present_idx]
phy_pruned <- keep.tip(phy, selected_tips)
message(sprintf("Pruned tree to %d tips", length(phy_pruned$tip.label)))

# Compute cophenetic distances
cop <- cophenetic.phylo(phy_pruned)

# Match order: cophenetic matrix rows/cols are in tree$tip.label order
# We need to map back to the original species order
map <- match(phy_pruned$tip.label, selected_tips)
feature_idx <- present_idx[map]

# Compute phylogenetic predictors for each EIVE axis
results <- data.frame(wfo_taxon_id = traits$wfo_taxon_id, stringsAsFactors = FALSE)
# Determine separator for EIVE column names
eive_sep <- if (grepl("\\.", EIVE_COLS[1])) "." else if (grepl("-", EIVE_COLS[1])) "-" else "_"
for (axis in c("T","M","L","N","R")) {
  col <- paste0("EIVEres", eive_sep, axis)
  values <- merged[[col]][feature_idx]
  p_vals <- compute_p(cop, values, x_exp = opts$x_exp, k_trunc = opts$k_trunc)
  out <- rep(NA_real_, nrow(traits))
  out[feature_idx] <- p_vals
  results[[paste0("p_phylo_", axis)]] <- out
  coverage <- sum(!is.na(out))
  message(sprintf("Axis %s: computed p_phylo for %d / %d species", axis, coverage, nrow(traits)))
}

message(sprintf("Writing output to: %s", opts$output_csv))
write.csv(results, opts$output_csv, row.names = FALSE)
message("Done!")

coverage_summary <- colSums(!is.na(results[, -1, drop = FALSE]))
print(coverage_summary)
