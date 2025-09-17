#!/usr/bin/env Rscript

# Phylogenetic/taxonomic imputation for categorical traits
# - Targets: Leaf_phenology, Photosynthesis_pathway (configurable)
# - Strategy: Weighted majority vote using phylogenetic distances (from Newick tree) if available,
#             otherwise fall back to taxonomic proximity (same genus/family) then global majority.
# - Donor restriction via K-nearest and weight exponent X_EXP, consistent with p_k design elsewhere.

suppressWarnings({
  suppressMessages({
    library(data.table)
    library(dplyr)
    library(stringr)
  })
})

# Prefer R_LIBS_USER if set
lib_user <- Sys.getenv("R_LIBS_USER")
if (nzchar(lib_user)) {
  .libPaths(lib_user)
} else {
  .libPaths("/home/olier/ellenberg/.Rlib")
}

args <- commandArgs(trailingOnly = TRUE)
parse_args <- function(args) {
  out <- list()
  for (a in args) {
    if (!grepl("^--[A-Za-z0-9_]+=", a)) next
    kv <- sub("^--", "", a)
    k <- sub("=.*$", "", kv)
    v <- sub("^[^=]*=", "", kv)
    out[[k]] <- v
  }
  out
}
opts <- parse_args(args)
`%||%` <- function(a, b) if (!is.null(a) && nzchar(a)) a else b

# IO
in_csv   <- opts[["input_csv"]] %||% "artifacts/model_data_bioclim_subset_enhanced_imputed.csv"
out_csv  <- opts[["out_csv"]] %||% "artifacts/model_data_bioclim_subset_enhanced_imputed_cat.csv"
diag_dir <- opts[["diag_dir"]] %||% "artifacts/phylotraits_impute"

# Traits to impute (comma-separated)
traits_cat <- opts[["traits_cat"]] %||% "Leaf_phenology,Photosynthesis_pathway"
traits_cat <- strsplit(traits_cat, ",")[[1]] %>% trimws()

# Phylo settings
tree_path <- opts[["tree"]] %||% "data/phylogeny/eive_try_tree.nwk"
X_EXP     <- as.numeric(opts[["x_exp"]] %||% "2")
K_TRUNC   <- as.integer(opts[["k_trunc"]] %||% "0")

verbose   <- tolower(opts[["verbose"]] %||% "false") %in% c("true","1","yes")

ok <- function(msg) cat(sprintf("[ok] %s\n", msg))
fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }
ensure_dir <- function(path) dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
norm_species <- function(x) { x <- as.character(x); x <- gsub("[[:space:]]+"," ",x); x <- trimws(x); tolower(x) }

if (!file.exists(in_csv)) fail(sprintf("Input not found: %s", in_csv))
dt <- fread(in_csv)
if (!all(c("wfo_accepted_name","Genus","Family") %in% names(dt))) {
  fail("Input is missing required columns: wfo_accepted_name, Genus, Family")
}

dt$species_key <- norm_species(dt$wfo_accepted_name)
dt$Genus  <- ifelse(is.na(dt$Genus)  | dt$Genus  == "", "UnknownGenus", dt$Genus)
dt$Family <- ifelse(is.na(dt$Family) | dt$Family == "", "UnknownFamily", dt$Family)

# Load tree if available and ape is installed; otherwise fall back to taxonomy
tree <- NULL
dist_mat <- NULL
if (!is.null(tree_path) && nzchar(tree_path) && file.exists(tree_path) && requireNamespace("ape", quietly = TRUE)) {
  tree <- tryCatch(ape::read.tree(tree_path), error = function(e) NULL)
  if (!is.null(tree)) {
    tree$tip.label <- norm_species(tree$tip.label)
    # Keep only species present in data
    keep <- tree$tip.label %in% dt$species_key
    if (sum(keep) >= 2) {
      tree <- ape::drop.tip(tree, setdiff(tree$tip.label, dt$species_key))
      ok(sprintf("Loaded tree with %d tips after subsetting", length(tree$tip.label)))
      dist_mat <- ape::cophenetic.phylo(tree)
    } else {
      tree <- NULL
    }
  }
}

# Helper to compute donor weights
compute_weights <- function(target, donors) {
  # target and donors are species_key strings
  # returns named weight vector over donors
  if (!is.null(dist_mat) && target %in% rownames(dist_mat)) {
    d <- dist_mat[target, donors]
    # Some donors may be NA if pruned; drop them
    good <- is.finite(d)
    donors2 <- donors[good]
    d2 <- d[good]
    if (length(donors2) > 0) {
      # Avoid zero distance (self): if present set to min positive distance
      eps <- .Machine$double.eps
      d2[d2 < eps] <- eps
      w <- 1 / (d2 ^ X_EXP)
      if (K_TRUNC > 0 && length(w) > K_TRUNC) {
        ord <- order(d2)
        donors2 <- donors2[ord][1:K_TRUNC]
        w <- w[ord][1:K_TRUNC]
      }
      w <- w / sum(w)
      names(w) <- donors2
      return(w)
    }
  }
  # Fallback: taxonomy-based proximity
  # same genus -> d=0.5; same family -> d=1; else d=2
  genus_same  <- donors[dt$Genus[match(donors, dt$species_key)] == dt$Genus[match(target, dt$species_key)]]
  family_same <- setdiff(donors[dt$Family[match(donors, dt$species_key)] == dt$Family[match(target, dt$species_key)]], genus_same)
  other <- setdiff(donors, c(genus_same, family_same))
  donors2 <- c(genus_same, family_same, other)
  if (length(donors2) == 0) return(numeric(0))
  d2 <- c(rep(0.5, length(genus_same)), rep(1.0, length(family_same)), rep(2.0, length(other)))
  w <- 1 / (d2 ^ X_EXP)
  if (K_TRUNC > 0 && length(w) > K_TRUNC) {
    ord <- order(d2)
    donors2 <- donors2[ord][1:K_TRUNC]
    w <- w[ord][1:K_TRUNC]
  }
  w <- w / sum(w)
  names(w) <- donors2
  w
}

# Impute function for one categorical trait
impute_categorical <- function(trait_col) {
  if (!(trait_col %in% names(dt))) {
    ok(sprintf("Trait %s not found; skipping", trait_col))
    return(invisible(NULL))
  }
  vals <- dt[[trait_col]]
  # Normalize string empties to NA
  if (is.character(vals)) {
    vals[vals == ""] <- NA
  }
  observed_idx <- which(!is.na(vals) & vals != "")
  missing_idx  <- which(is.na(vals) | vals == "")
  if (length(missing_idx) == 0) {
    ok(sprintf("No missing values in %s", trait_col))
    return(invisible(NULL))
  }
  donors <- dt$species_key[observed_idx]
  donors_val <- as.character(vals[observed_idx])
  names(donors_val) <- donors
  pred <- character(length(missing_idx))
  conf <- numeric(length(missing_idx))
  for (k in seq_along(missing_idx)) {
    i <- missing_idx[k]
    target <- dt$species_key[i]
    w <- compute_weights(target, donors)
    if (length(w) == 0) {
      # Global majority fallback
      tab <- sort(table(donors_val), decreasing = TRUE)
      pred[k] <- names(tab)[1]
      conf[k] <- as.numeric(tab[1]) / sum(tab)
      next
    }
    # Weighted vote
    # Aggregate weights by class
    classes <- unique(donors_val[names(w)])
    pr <- sapply(classes, function(cl) sum(w[donors_val[names(w)] == cl]))
    # Normalize to sum 1
    if (sum(pr) > 0) pr <- pr / sum(pr)
    j <- which.max(pr)
    pred[k] <- names(pr)[j]
    conf[k] <- pr[j]
  }
  # Apply predictions
  new_vals <- vals
  new_vals[missing_idx] <- pred
  flag_col <- paste0(trait_col, "_imputed_flag")
  prob_col <- paste0(trait_col, "_imputed_prob")
  dt[[trait_col]] <- new_vals
  dt[[flag_col]]  <- 0L
  dt[[flag_col]][missing_idx] <- 1L
  dt[[prob_col]]  <- NA_real_
  dt[[prob_col]][missing_idx] <- conf
  # Coverage report
  before <- length(observed_idx)
  after  <- sum(!is.na(dt[[trait_col]]) & dt[[trait_col]] != "")
  data.frame(trait = trait_col, before = before, after = after, stringsAsFactors = FALSE)
}

ensure_dir(out_csv)
dir.create(diag_dir, recursive = TRUE, showWarnings = FALSE)

coverage <- do.call(rbind, lapply(traits_cat, impute_categorical))
fwrite(dt, out_csv)
fwrite(coverage, file.path(diag_dir, "categorical_coverage_before_after.csv"))

ok(sprintf("Wrote categorical-imputed dataset: %s", out_csv))
ok(sprintf("Coverage deltas written: %s", file.path(diag_dir, "categorical_coverage_before_after.csv")))

invisible(NULL)
