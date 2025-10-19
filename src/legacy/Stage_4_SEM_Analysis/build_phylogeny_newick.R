#!/usr/bin/env Rscript

# Build a Newick phylogeny for the modeled species using V.PhyloMaker2
# Inputs: CSV with column 'wfo_accepted_name' (Genus species)
# Output: Newick tree and coverage report
# Usage:
#   Rscript src/Stage_4_SEM_Analysis/build_phylogeny_newick.R \
#     --input_csv=artifacts/model_data_complete_case_with_myco.csv \
#     --output_newick=data/phylogeny/eive_try_tree.nwk \
#     --min_coverage=0.9

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

`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b

# Prepend extra library paths if provided via environment
extra_libs <- Sys.getenv("R_EXTRA_LIBS")
if (nzchar(extra_libs)) {
  paths <- unlist(strsplit(extra_libs, "[,:;]", perl = TRUE))
  paths <- paths[nzchar(paths)]
  if (length(paths)) .libPaths(c(paths, .libPaths()))
}

in_csv  <- opts[["input_csv"]]  %||% "artifacts/model_data_complete_case_with_myco.csv"
out_nwk <- opts[["output_newick"]] %||% "data/phylogeny/eive_try_tree.nwk"
min_cov <- suppressWarnings(as.numeric(opts[["min_coverage"]] %||% "0.9")); if (!is.finite(min_cov)) min_cov <- 0.9

if (!file.exists(in_csv)) {
  stop(sprintf("Input CSV not found: %s", in_csv))
}

suppressMessages({
  library(readr)
  library(tibble)
  library(tidyr)
  library(V.PhyloMaker2)
  library(ape)
})

dat <- readr::read_csv(in_csv, show_col_types = FALSE)
if (!("wfo_accepted_name" %in% names(dat))) stop("Column 'wfo_accepted_name' not found in input CSV")
sp <- unique(dat$wfo_accepted_name)
sp <- sp[is.finite(match(sp, sp)) & !is.na(sp) & nzchar(sp)]

df <- tibble::tibble(binomial = sp)
# Split into genus and specific epithet; discard extra pieces beyond two
df <- tidyr::separate(df, binomial, into = c("genus","species"), remove = TRUE, fill = "right")
df$genus[is.na(df$genus)] <- ""
df$species[is.na(df$species)] <- ""
# Drop incomplete rows (missing genus or species)
df <- df[nzchar(df$genus) & nzchar(df$species), , drop = FALSE]

data("GBOTB.extended.TPL", package = "V.PhyloMaker2")
if (!exists("GBOTB.extended.TPL")) {
  # Fallback: fetch from package namespace if 'data()' could not attach it
  ns <- try(asNamespace("V.PhyloMaker2"), silent = TRUE)
  if (!inherits(ns, "try-error") && exists("GBOTB.extended.TPL", envir = ns, inherits = FALSE)) {
    GBOTB.extended <- get("GBOTB.extended.TPL", envir = ns)
  } else {
    # Try original V.PhyloMaker package
    ns1 <- try(asNamespace("V.PhyloMaker"), silent = TRUE)
    if (!inherits(ns1, "try-error") && exists("GBOTB.extended.TPL", envir = ns1, inherits = FALSE)) {
      GBOTB.extended <- get("GBOTB.extended.TPL", envir = ns1)
    } else {
      stop("GBOTB.extended.TPL dataset not found in V.PhyloMaker2 or V.PhyloMaker; please check installation.")
    }
  }
} else {
  GBOTB.extended <- GBOTB.extended.TPL
}
cat(sprintf("Species input: %d\n", nrow(df)))

species_binom <- paste(df$genus, df$species)
# Deduplicate by full binomial to avoid cross-genus epithet collisions
keep <- !duplicated(species_binom)
species_binom <- species_binom[keep]
genus_vec <- df$genus[keep]
sp_list <- data.frame(species = species_binom, genus = genus_vec, family = NA_character_, stringsAsFactors = FALSE)
phy_out <- V.PhyloMaker2::phylo.maker(sp_list, GBOTB.extended, scenarios = "S3")

tree <- phy_out$scenario.3
if (is.null(tree)) stop("phylo.maker() did not return scenario.3 tree")

# Coverage assessment
tips <- gsub("_", " ", tree$tip.label)
binoms <- species_binom
covered <- sum(binoms %in% tips)
denom <- length(binoms)
coverage <- if (denom > 0) covered / denom else 0

out_dir <- dirname(out_nwk)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
ape::write.tree(tree, file = out_nwk)

report_path <- file.path(out_dir, "eive_try_tree_coverage.txt")
cat(sprintf("input_species=%d\nmatched_tips=%d\ncoverage=%.4f\nmin_required=%.4f\nout_newick=%s\n",
            nrow(df), covered, coverage, min_cov, normalizePath(out_nwk, winslash = "/", mustWork = FALSE)),
    file = report_path)

if (coverage < min_cov) {
  missing <- data.frame(wfo_accepted_name = binoms[!(binoms %in% tips)], stringsAsFactors = FALSE)
  miss_path <- file.path(out_dir, "eive_try_tree_missing_species.csv")
  utils::write.csv(missing, miss_path, row.names = FALSE)
  warning(sprintf("Coverage %.3f below threshold %.3f; see %s", coverage, min_cov, miss_path))
}

cat(sprintf("Newick written: %s\nCoverage: %.2f%% (%d / %d)\n",
            out_nwk, 100*coverage, covered, nrow(df)))
