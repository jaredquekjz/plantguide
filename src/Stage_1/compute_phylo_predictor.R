#!/usr/bin/env Rscript

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
  required <- c("traits_csv", "eive_csv", "phylogeny_newick", "output_csv")
  for (r in required) {
    if (is.null(opts[[r]]) || !nzchar(opts[[r]])) stop(sprintf("--%s is required", r))
  }
  opts$x_exp <- as.numeric(ifelse(!is.null(opts$x_exp) && nzchar(opts$x_exp), opts$x_exp, 2))
  opts$k_trunc <- as.integer(ifelse(!is.null(opts$k_trunc) && nzchar(opts$k_trunc), opts$k_trunc, 0))
  opts
}

normalise_name <- function(x) {
  out <- tolower(x)
  out <- gsub("^[[:space:]]+|[[:space:]]+$", "", out)
  out <- gsub("[[:space:]]+", "_", out)
  gsub("[^a-z0-9_]+", "_", out)
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

traits <- read.csv(opts$traits_csv, stringsAsFactors = FALSE)
if (!"wfo_taxon_id" %in% names(traits)) stop("Traits CSV must include wfo_taxon_id")
if (!"wfo_scientific_name" %in% names(traits)) {
  if ("canonical_name" %in% names(traits)) {
    names(traits)[names(traits) == "canonical_name"] <- "wfo_scientific_name"
  } else {
    stop("Traits CSV must include wfo_scientific_name (or canonical_name)")
  }
}
traits$wfo_taxon_id <- as.character(traits$wfo_taxon_id)

EIVE_COLS <- c("EIVEres_T", "EIVEres_M", "EIVEres_L", "EIVEres_N", "EIVEres_R")
eive <- read.csv(opts$eive_csv, stringsAsFactors = FALSE)
if (!"wfo_taxon_id" %in% names(eive)) stop("EIVE CSV must include wfo_taxon_id")
eive$wfo_taxon_id <- as.character(eive$wfo_taxon_id)
missing_cols <- setdiff(EIVE_COLS, names(eive))
if (length(missing_cols) > 0) stop(sprintf("EIVE CSV missing columns: %s", paste(missing_cols, collapse=", ")))

merged <- merge(traits[, c("wfo_taxon_id", "wfo_scientific_name")], eive,
                by = "wfo_taxon_id", all.x = TRUE, sort = FALSE)
merged$tip_label <- normalise_name(merged$wfo_scientific_name)

library(ape)
phy <- read.tree(opts$phylogeny_newick)
tree_labels_norm <- normalise_name(phy$tip.label)
match_idx <- match(merged$tip_label, tree_labels_norm)
present_idx <- which(!is.na(match_idx))
if (length(present_idx) < 2) stop("Not enough species overlap between traits and phylogeny")

selected_labels <- phy$tip.label[match_idx[present_idx]]
phy_pruned <- keep.tip(phy, selected_labels)
cop <- cophenetic.phylo(phy_pruned)
map <- match(phy_pruned$tip.label, selected_labels)
feature_idx <- present_idx[map]

results <- data.frame(wfo_taxon_id = merged$wfo_taxon_id, stringsAsFactors = FALSE)
for (axis in c("T","M","L","N","R")) {
  col <- paste0("EIVEres_", axis)
  values <- merged[[col]][feature_idx]
  p_vals <- compute_p(cop, values, x_exp = opts$x_exp, k_trunc = opts$k_trunc)
  out <- rep(NA_real_, nrow(merged))
  out[feature_idx] <- p_vals
  results[[paste0("p_phylo_", axis)]] <- out
  coverage <- sum(!is.na(out))
  message(sprintf("Axis %s: computed p_phylo for %d / %d species", axis, coverage, nrow(merged)))
}

write.csv(results, opts$output_csv, row.names = FALSE)
message(sprintf("Written p_phylo CSV to %s", opts$output_csv))

coverage_summary <- colSums(!is.na(results[, -1, drop = FALSE]))
print(coverage_summary)
