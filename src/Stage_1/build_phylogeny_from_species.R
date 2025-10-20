#!/usr/bin/env Rscript

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
  required <- c("species_csv", "output_newick")
  for (r in required) {
    if (is.null(opts[[r]]) || !nzchar(opts[[r]])) stop(sprintf("--%s is required", r))
  }
  opts
}

opts <- parse_args()
if (!file.exists(opts$species_csv)) stop(sprintf("Species CSV not found: %s", opts$species_csv))

suppressPackageStartupMessages({
  library(readr)
  library(tidyr)
  library(dplyr)
  library(V.PhyloMaker)
  library(ape)
})

dat <- readr::read_csv(opts$species_csv, show_col_types = FALSE)
col_candidates <- c("wfo_scientific_name", "wfo_accepted_name", "species")
col_name <- intersect(col_candidates, names(dat))
if (!length(col_name)) stop("Species CSV must contain one of: wfo_accepted_name, wfo_scientific_name, species")
col_name <- col_name[1]

family_col <- if ("family" %in% names(dat)) "family" else NULL
genus_col <- if ("genus" %in% names(dat)) "genus" else NULL

species_df <- dat[, unique(c(col_name, genus_col, family_col, "wfo_taxon_id")), drop = FALSE]
names(species_df)[names(species_df) == col_name] <- "binomial"
species_df$binomial <- trimws(species_df$binomial)
species_df <- species_df[!is.na(species_df$binomial) & nzchar(species_df$binomial), , drop = FALSE]

if (is.null(genus_col)) {
  tmp <- tidyr::separate(species_df, "binomial", into = c("genus","species"), remove = FALSE, fill = "right")
} else {
  tmp <- species_df
  tmp$species <- sub("^[^[:space:]]+[[:space:]]+", "", tmp$binomial)
  tmp$genus <- tmp[[genus_col]]
}

tmp$species <- trimws(tmp$species)
tmp$genus <- trimws(tmp$genus)
tmp <- tmp[!is.na(tmp$genus) & !is.na(tmp$species) & nzchar(tmp$genus) & nzchar(tmp$species), , drop = FALSE]
tmp <- distinct(tmp, binomial, genus, species, .keep_all = TRUE)

if (is.null(family_col)) {
  tmp$family <- NA_character_
} else {
  tmp$family <- tmp[[family_col]]
}

missing_family <- sum(is.na(tmp$family) | tmp$family == "" | tmp$family == "Unknown")
if (missing_family > 0) {
  warning(sprintf("%d species lack family information; V.PhyloMaker will place them using scenario S3 defaults", missing_family))
}

tmp$family <- ifelse(is.na(tmp$family) | tmp$family == "", NA_character_, tmp$family)
tmp$species_label <- paste(tmp$genus, tmp$species, sep = "_")
sp_list <- data.frame(species = tmp$species_label, genus = tmp$genus, family = tmp$family, stringsAsFactors = FALSE)

message(sprintf("Input species: %d", nrow(sp_list)))

data("GBOTB.extended", package = "V.PhyloMaker")
if (!exists("GBOTB.extended")) stop("GBOTB.extended dataset not available")
phy_out <- V.PhyloMaker::phylo.maker(sp_list, GBOTB.extended, scenarios = "S3")
if (is.null(phy_out$scenario.3)) stop("phylo.maker returned NULL scenario.3")

out_dir <- dirname(opts$output_newick)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
ape::write.tree(phy_out$scenario.3, file = opts$output_newick)
message(sprintf("Newick written to %s", opts$output_newick))
