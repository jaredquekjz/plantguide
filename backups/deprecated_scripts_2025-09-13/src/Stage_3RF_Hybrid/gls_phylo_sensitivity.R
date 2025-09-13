#!/usr/bin/env Rscript

# Lightweight phylogenetic GLS sensitivity for hybrid structured regressions
# - Fits the selected linear model with and without a Brownian correlation
#   structure on a pruned phylogeny, then reports coefficient shifts.
# - Designed for quick robustness checks, not for CV scoring.

suppressWarnings({
  .libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))
  suppressPackageStartupMessages({
    have_readr <- requireNamespace("readr", quietly = TRUE)
    have_dplyr <- requireNamespace("dplyr", quietly = TRUE)
    have_ape   <- requireNamespace("ape",   quietly = TRUE)
    have_nlme  <- requireNamespace("nlme",  quietly = TRUE)
    have_opt   <- requireNamespace("optparse", quietly = TRUE)
  })
})

fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }

if (!have_opt) fail("Package 'optparse' is required.")

optparse <- getNamespace("optparse")
OptionParser <- optparse$OptionParser
make_option  <- optparse$make_option
parse_args   <- optparse$parse_args

option_list <- list(
  make_option(c("--target"), type = "character", default = "T",
              help = "Target axis letter [T|M|R|N|L] (default T)", metavar = "char"),
  make_option(c("--trait_csv"), type = "character",
              default = "artifacts/model_data_complete_case_with_myco.csv",
              help = "Trait CSV (complete-case)", metavar = "path"),
  make_option(c("--bioclim_summary"), type = "character",
              default = "data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv",
              help = "Species-level bioclim summary CSV", metavar = "path"),
  make_option(c("--phylogeny_newick"), type = "character",
              default = "data/phylogeny/eive_try_tree.nwk",
              help = "Phylogeny in Newick format", metavar = "path"),
  make_option(c("--min_occurrences"), type = "integer", default = 30,
              help = "Min occurrences to keep species (default 30)", metavar = "int"),
  make_option(c("--formula"), type = "character", default = "",
              help = "Model formula (e.g., 'y ~ tmax_mean + mat_mean + mat_q05 + mat_q95 + tmin_mean + precip_mean + drought_min + logH + wood_cold + SIZE')",
              metavar = "string"),
  make_option(c("--output_dir"), type = "character",
              default = "artifacts/stage3rf_hybrid_climate_phylo",
              help = "Output directory (default artifacts/stage3rf_hybrid_climate_phylo)", metavar = "path")
)

opt <- parse_args(OptionParser(option_list = option_list))

if (!have_ape)  fail("Package 'ape' is required (install.packages('ape')).")
if (!have_nlme) fail("Package 'nlme' is required (install.packages('nlme')).")

dplyr <- getNamespace("dplyr"); readr <- getNamespace("readr")
ape   <- getNamespace("ape");    nlme  <- getNamespace("nlme")

# Load data
if (!file.exists(opt$trait_csv)) fail(sprintf("Trait CSV not found: %s", opt$trait_csv))
if (!file.exists(opt$bioclim_summary)) fail(sprintf("Bioclim summary not found: %s", opt$bioclim_summary))
if (!file.exists(opt$phylogeny_newick)) fail(sprintf("Phylogeny not found: %s", opt$phylogeny_newick))

trait <- readr$read_csv(opt$trait_csv, show_col_types = FALSE)
bio   <- readr$read_csv(opt$bioclim_summary, show_col_types = FALSE)

# Filter robust species and compute climate metrics
bio_s <- dplyr$filter(bio, tolower(as.character(.data$has_sufficient_data)) %in% c("true","t","1"))
bio_s <- dplyr$mutate(bio_s,
  mat_mean = .data$bio1_mean,
  mat_sd   = .data$bio1_sd,
  tmax_mean = .data$bio5_mean,
  tmin_mean = .data$bio6_mean,
  temp_seasonality = .data$bio4_mean,
  temp_range = .data$bio7_mean,
  precip_mean = .data$bio12_mean,
  precip_sd   = .data$bio12_sd,
  drought_min = .data$bio14_mean,
  precip_seasonality = .data$bio15_mean,
  mat_q05 = .data$mat_mean - 1.645*.data$mat_sd,
  mat_q95 = .data$mat_mean + 1.645*.data$mat_sd,
  tmin_q05 = .data$tmin_mean - 1.645*(.data$tmin_mean*0.2),
  precip_cv = .data$precip_sd / pmax(.data$precip_mean, 1)
)

# Merge traits + climate
normalize_species <- function(x) tolower(gsub("[[:space:]_-]+","_", x))
trait$species_normalized <- normalize_species(trait$wfo_accepted_name)
bio_s$species_normalized <- normalize_species(bio_s$species)
df <- dplyr$inner_join(trait, bio_s, by = "species_normalized")

# Build features (match comprehensive pipeline)
compute_offset <- function(x) {
  x <- as.numeric(x); x <- x[is.finite(x) & !is.na(x) & x > 0]
  if (!length(x)) return(1e-6)
  max(1e-6, 1e-3 * stats::median(x))
}

offs <- c(
  LA  = compute_offset(df[["Leaf area (mm2)"]]),
  H   = compute_offset(df[["Plant height (m)"]]),
  SM  = compute_offset(df[["Diaspore mass (mg)"]]),
  SSD = compute_offset(df[["SSD used (mg/mm3)"]])
)

dat <- dplyr$mutate(df,
  logLA   = log10(`Leaf area (mm2)` + offs[["LA"]]),
  logH    = log10(`Plant height (m)` + offs[["H"]]),
  logSM   = log10(`Diaspore mass (mg)` + offs[["SM"]]),
  logSSD  = log10(`SSD used (mg/mm3)` + offs[["SSD"]]),
  LMA     = `LMA (g/m2)`,
  Nmass   = `Nmass (mg/g)`
)

# Simple composites (global; GLS sensitivity only)
z <- function(x) { s <- stats::sd(x, na.rm=TRUE); if (!is.finite(s) || s == 0) s <- 1; (x - mean(x, na.rm=TRUE))/s }
dat$SIZE     <- z(dat$logH) + z(dat$logSM)
dat$LES_core <- -dat$LMA + z(dat$Nmass)
dat$wood_cold <- dat$logSSD * dat$tmin_q05

target_name <- paste0("EIVEres-", toupper(opt$target))
dat$y <- as.numeric(dat[[target_name]])
dat <- dat[stats::complete.cases(dat[, c("y","logH","SIZE","wood_cold","tmax_mean","mat_mean","mat_q05","mat_q95","tmin_mean","precip_mean","drought_min")]), ]

# Default formula if none provided (Temperature exemplar)
fm_str <- opt$formula
if (!nzchar(fm_str)) {
  if (toupper(opt$target) == "T") {
    fm_str <- "y ~ tmax_mean + mat_mean + mat_q05 + mat_q95 + tmin_mean + precip_mean + drought_min + logH + wood_cold + SIZE"
  } else {
    fm_str <- "y ~ SIZE + logSSD + logLA + LMA + Nmass + mat_mean + precip_mean + drought_min"  # generic fallback
  }
}
fm <- stats::as.formula(fm_str)

# Align phylogeny (tree tips use underscores; map trait names accordingly)
phy <- ape$read.tree(opt$phylogeny_newick)
tip_name <- gsub("[[:space:]]+", "_", dat$wfo_accepted_name)
common <- intersect(phy$tip.label, tip_name)
if (length(common) < 20) fail("Too few species overlap for GLS (need at least 20).")
phy2 <- ape$keep.tip(phy, common)
dat2 <- dat[match(common, tip_name), , drop = FALSE]

dir.create(opt$output_dir, recursive = TRUE, showWarnings = FALSE)
out_txt <- file.path(opt$output_dir, sprintf("gls_phylo_sensitivity_%s.txt", toupper(opt$target)))

sink(out_txt)
cat("Phylogenetic GLS Sensitivity\n")
cat(sprintf("Target: %s\n", toupper(opt$target)))
cat(sprintf("Formula: %s\n", fm_str))
cat(sprintf("Species: %d\n\n", nrow(dat2)))

# OLS reference
ols <- stats::lm(fm, data = dat2)
cat("OLS coefficients:\n")
print(summary(ols))

# GLS with Brownian correlation (ape::corBrownian provides corStruct for nlme::gls)
cor_struct <- ape::corBrownian(1, phy = phy2)
gls_fit <- try(nlme::gls(fm, data = dat2, correlation = cor_struct, method = "REML"), silent = TRUE)
cat("\nGLS (Brownian) coefficients:\n")
if (inherits(gls_fit, "try-error")) {
  cat("[warn] GLS failed to converge; Brownian structure may be ill-posed for this subset.\n")
} else {
  print(summary(gls_fit))
}

cat("\nNotes:\n- Use results for robustness checks only (different likelihood vs OLS).\n- Focus on sign stability and approximate magnitudes.\n")
sink(NULL)

cat(sprintf("Wrote: %s\n", out_txt))
