#!/usr/bin/env Rscript

# Assemble modeling dataset by joining TRY-curated traits (matched to EIVE WFO
# accepted names) with EIVE indicator values AND classified Myco_Group data.
# Produces new CSVs with a '_with_myco' suffix.

suppressWarnings({
  suppressMessages({
    have_readr  <- requireNamespace("readr",  quietly = TRUE)
    have_dplyr  <- requireNamespace("dplyr",  quietly = TRUE)
    have_stringr<- requireNamespace("stringr",quietly = TRUE)
    have_tibble <- requireNamespace("tibble", quietly = TRUE)
    library(data.table)
  })
})

args <- commandArgs(trailingOnly = TRUE)

# Simple flag parser: expects --key=value
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

# Inputs (defaults follow repo structure)
traits_rds <- opts[["traits_rds"]] %||% "artifacts/traits_matched.rds"
traits_csv <- opts[["traits_csv"]] %||% "artifacts/traits_matched.csv"
eive_main  <- opts[["eive_main_csv"]] %||% "data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv"
eive_map   <- opts[["eive_map_csv"]]  %||% "data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv"
myco_data_rds <- opts[["myco_rds"]] %||% "data/species_myco_wfo_matched.rds" # NEW INPUT

# Outputs
out_full       <- opts[["out_full_csv"]]      %||% "artifacts/model_data_full_with_myco.csv"
out_complete   <- opts[["out_complete_csv"]]  %||% "artifacts/model_data_complete_case_with_myco.csv"
emit_obs_ssd   <- tolower(opts[["emit_observed_ssd_complete"]] %||% "false") %in% c("1","true","yes","y")
out_complete_o <- opts[["out_complete_observed_ssd_csv"]] %||% "artifacts/model_data_complete_case_observed_ssd_with_myco.csv"

fail <- function(msg) {
  cat(sprintf("[error] %s\n", msg))
  quit(status = 1)
}

check_exists <- function(path, what) {
  if (!file.exists(path)) fail(sprintf("%s not found: '%s'", what, path))
}

ensure_dir <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
}

norm_name <- function(x) {
  x <- as.character(x)
  x <- gsub("[[:space:]]+", " ", x)
  x <- trimws(x)
  tolower(x)
}

# Validate inputs early
check_exists(eive_main, "EIVE main CSV")
check_exists(eive_map,  "EIVE name map CSV")
check_exists(myco_data_rds, "Myco data RDS") # NEW CHECK

species_col <- "Species name standardized against TPL"

# Read traits (prefer RDS for fidelity)
traits_df <- NULL
if (file.exists(traits_rds)) {
  traits_df <- readRDS(traits_rds)
  cat(sprintf("Loaded traits RDS: %s (rows=%d, cols=%d)\n", traits_rds, nrow(traits_df), ncol(traits_df)))
} else if (file.exists(traits_csv)) {
  if (have_readr) {
    traits_df <- readr::read_csv(traits_csv, show_col_types = FALSE, progress = FALSE)
  } else {
    traits_df <- utils::read.csv(traits_csv, stringsAsFactors = FALSE, check.names = FALSE)
  }
  cat(sprintf("Loaded traits CSV: %s (rows=%d, cols=%d)\n", traits_csv, nrow(traits_df), ncol(traits_df)))
} else {
  fail(sprintf("Neither traits RDS nor CSV found at '%s' / '%s'", traits_rds, traits_csv))
}

if (!(species_col %in% names(traits_df))) {
  fail(sprintf("Traits file is missing species column: '%s'", species_col))
}

# SSD handling helpers
ssd_obs_col  <- "SSD observed (mg/mm3)"
ssd_comb_col <- "SSD combined (mg/mm3)"
ssd_no_col   <- "SSD (n.o.)"

if (!(ssd_obs_col %in% names(traits_df))) {
  cat(sprintf("[warn] Column not found: '%s' — will treat all SSD as combined or missing.\n", ssd_obs_col))
}
if (!(ssd_comb_col %in% names(traits_df))) {
  fail(sprintf("Traits file is missing column: '%s'", ssd_comb_col))
}

# Prepare normalized species key
traits_df$.__species_norm <- norm_name(traits_df[[species_col]])

# Compute SSD used value and flag
ssd_used_col <- "SSD used (mg/mm3)"
traits_df[[ssd_used_col]] <- NA_real_
traits_df$ssd_imputed_used <- NA_integer_

obs <- if (ssd_obs_col %in% names(traits_df)) traits_df[[ssd_obs_col]] else rep(NA_real_, nrow(traits_df))
cmb <- traits_df[[ssd_comb_col]]

use_obs_idx <- !is.na(obs)
use_cmb_idx <- is.na(obs) & !is.na(cmb)

traits_df[[ssd_used_col]][use_obs_idx] <- obs[use_obs_idx]
traits_df[[ssd_used_col]][use_cmb_idx] <- cmb[use_cmb_idx]

traits_df$ssd_imputed_used[use_obs_idx] <- 0L
traits_df$ssd_imputed_used[use_cmb_idx] <- 1L

# Compute min records across six traits when counts are available
count_cols <- c("Leaf area (n.o.)", "Nmass (n.o.)", "LMA (n.o.)", "Plant height (n.o.)", "Diaspore mass (n.o.)", ssd_no_col)
has_counts <- all(count_cols %in% names(traits_df))
if (has_counts) {
  suppressWarnings({
    counts_mat <- as.matrix(traits_df[, count_cols])
    storage.mode(counts_mat) <- "numeric"
  })
  min_rec <- apply(counts_mat, 1, function(r) {
    r <- r[!is.na(r)]
    if (!length(r)) return(NA_real_)
    min(r)
  })
  traits_df$min_records_6traits <- as.numeric(min_rec)
} else {
  traits_df$min_records_6traits <- NA_real_
  missing_counts <- setdiff(count_cols, names(traits_df))
  cat(sprintf("[warn] Missing count columns: %s — 'min_records_6traits' set to NA.\n", paste(missing_counts, collapse = ", ")))
}

# Read EIVE main and attach WFO accepted names
if (have_readr) {
  eive_main_df <- readr::read_csv(eive_main, show_col_types = FALSE, progress = FALSE)
  eive_map_df  <- readr::read_csv(eive_map,  show_col_types = FALSE, progress = FALSE)
} else {
  eive_main_df <- utils::read.csv(eive_main, stringsAsFactors = FALSE, check.names = FALSE)
  eive_map_df  <- utils::read.csv(eive_map,  stringsAsFactors = FALSE, check.names = FALSE)
}

name_col <- if ("wfo_accepted_name" %in% names(eive_map_df)) "wfo_accepted_name" else {
  candidates <- c("WFO_Accepted_Name", "wfo_accepted_full_name")
  hit <- candidates[candidates %in% names(eive_map_df)]
  if (!length(hit)) fail("Could not find an accepted-name column in EIVE map.")
  cat(sprintf("[warn] Using fallback accepted-name column: '%s'\n", hit[[1]]))
  hit[[1]]
}

if (!("TaxonConcept" %in% names(eive_main_df)) || !("TaxonConcept" %in% names(eive_map_df))) {
  fail("Both EIVE files must contain 'TaxonConcept' for joining.")
}

eive_joined <- merge(eive_main_df, eive_map_df[, c("TaxonConcept", name_col)], by = "TaxonConcept", all.x = TRUE)
names(eive_joined)[names(eive_joined) == name_col] <- "wfo_accepted_name"
eive_joined$.__species_norm <- norm_name(eive_joined$wfo_accepted_name)

# Select targets (primary EIVEres-*)
target_cols <- c("EIVEres-L", "EIVEres-T", "EIVEres-M", "EIVEres-R", "EIVEres-N")
have_targets <- target_cols[target_cols %in% names(eive_joined)]
if (length(have_targets) != length(target_cols)) {
  miss <- setdiff(target_cols, names(eive_joined))
  fail(sprintf("EIVE main table is missing target columns: %s", paste(miss, collapse=",")))
}

# Merge traits with EIVE targets by normalized accepted name
keep_cols_traits <- c(
  species_col,
  "Genus", "Family", "Woodiness", "Growth Form", "Leaf type",
  # six traits + SSD used
  "Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", "Plant height (m)", "Diaspore mass (mg)",
  ssd_obs_col, ssd_comb_col, ssd_used_col,
  # record counts
  "Leaf area (n.o.)", "Nmass (n.o.)", "LMA (n.o.)", "Plant height (n.o.)", "Diaspore mass (n.o.)", ssd_no_col,
  # provenance
  "ssd_imputed_used", "min_records_6traits"
)
keep_cols_traits <- keep_cols_traits[keep_cols_traits %in% names(traits_df)]

traits_keyed <- traits_df[, c(".__species_norm", keep_cols_traits), drop = FALSE]
eive_keyed   <- eive_joined[, c(".__species_norm", "wfo_accepted_name", target_cols), drop = FALSE]

model_full <- merge(eive_keyed, traits_keyed, by = ".__species_norm", all.x = FALSE, all.y = FALSE)

# --- NEW: JOIN WITH MYCO DATA ---
myco_df <- readRDS(myco_data_rds)
setDT(myco_df)
myco_df$.__species_norm <- norm_name(myco_df$wfo_accepted_name)
myco_keyed <- myco_df[, .(.wfo_accepted_name_myco = wfo_accepted_name, Myco_Group_Final, .__species_norm)]

# Perform a LEFT join to keep all species from the main dataset
model_full <- merge(model_full, myco_keyed, by = ".__species_norm", all.x = TRUE)
cat(sprintf("Joined with myco data. Found myco info for %d / %d species.\n",
            sum(!is.na(model_full$Myco_Group_Final)), nrow(model_full)))
# --- END NEW SECTION ---


# Deduplicate to one row per species (should already be unique)
model_full <- model_full[!duplicated(model_full$.__species_norm), , drop = FALSE]

# Compute complete-case using the six traits with SSD combined, per methodology
trait_cols_6 <- c("Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", "Plant height (m)", "Diaspore mass (mg)", ssd_comb_col)
have_all_6 <- Reduce(`&`, lapply(trait_cols_6, function(cn) !is.na(model_full[[cn]])))
model_cc <- model_full[have_all_6, , drop = FALSE]

# Optionally also produce an observed-SSD-only complete-case subset (sensitivity)
if (emit_obs_ssd && (ssd_obs_col %in% names(model_full))) {
  have_all_obs <- Reduce(`&`, lapply(c("Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", "Plant height (m)", "Diaspore mass (mg)", ssd_obs_col), function(cn) !is.na(model_full[[cn]])))
  model_cc_obs <- model_full[have_all_obs, , drop = FALSE]
} else {
  model_cc_obs <- NULL
}

# Ensure output directories exist and write CSVs
ensure_dir(out_full)
ensure_dir(out_complete)
if (have_readr) {
  readr::write_csv(model_full[, setdiff(names(model_full), c(".__species_norm", ".wfo_accepted_name_myco")), drop = FALSE], out_full)
  readr::write_csv(model_cc[,   setdiff(names(model_cc),   c(".__species_norm", ".wfo_accepted_name_myco")), drop = FALSE], out_complete)
  if (!is.null(model_cc_obs)) {
    ensure_dir(out_complete_o)
    readr::write_csv(model_cc_obs[, setdiff(names(model_cc_obs), c(".__species_norm", ".wfo_accepted_name_myco")), drop = FALSE], out_complete_o)
  }
} else {
  utils::write.csv(model_full[, setdiff(names(model_full), c(".__species_norm", ".wfo_accepted_name_myco")), drop = FALSE], out_full, row.names = FALSE)
  utils::write.csv(model_cc[,   setdiff(names(model_cc),   c(".__species_norm", ".wfo_accepted_name_myco")), drop = FALSE], out_complete, row.names = FALSE)
  if (!is.null(model_cc_obs)) {
    ensure_dir(out_complete_o)
    utils::write.csv(model_cc_obs[, setdiff(names(model_cc_obs), c(".__species_norm", ".wfo_accepted_name_myco")), drop = FALSE], out_complete_o, row.names = FALSE)
  }
}

# Print summary counts for verification
n_full <- nrow(model_full)
n_cc   <- nrow(model_cc)
ssd_breakdown <- NA
if ("ssd_imputed_used" %in% names(model_cc)) {
  tb <- table(factor(model_cc$ssd_imputed_used, levels = c(0,1)), useNA = "no")
  ssd_breakdown <- sprintf("observed=%d, imputed=%d", as.integer(tb[["0"]] %||% 0L), as.integer(tb[["1"]] %||% 0L))
}

cat("\nAssembly summary:\n")
cat(sprintf("  Joined rows (full): %s\n", format(n_full, big.mark = ",")))
cat(sprintf("  Complete-case (six traits w/ SSD combined): %s\n", format(n_cc, big.mark = ",")))
if (!is.na(ssd_breakdown)) cat(sprintf("    SSD provenance within complete-case: %s\n", ssd_breakdown))
if (!is.null(model_cc_obs)) {
  cat(sprintf("  Observed-SSD-only complete-case: %s\n", format(nrow(model_cc_obs), big.mark = ",")))
}
cat(sprintf("  Myco data found for %d / %d complete-case species.\n", sum(!is.na(model_cc$Myco_Group_Final)), n_cc))


cat("\nOutputs:\n")
cat(sprintf("  - %s\n", out_full))
cat(sprintf("  - %s\n", out_complete))
if (!is.null(model_cc_obs)) cat(sprintf("  - %s\n", out_complete_o))

invisible(NULL)
