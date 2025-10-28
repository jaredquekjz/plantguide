#!/usr/bin/env Rscript

# Phylogenetic/Taxonomic gap-filling for enhanced traits using BHPMF
# - Uses BHPMF (Bayesian Hierarchical Probabilistic Matrix Factorization)
# - Hierarchy: Family -> Genus -> Species (WFO-accepted names)
# - Imputes continuous traits only (initially): Leaf_thickness_mm, Frost_tolerance_score, Leaf_N_per_area
# - Categorical traits (Leaf_phenology, Photosynthesis_pathway) are left as-is (see README plan for categorical imputation)

suppressWarnings({
  suppressMessages({
    library(data.table)
    library(dplyr)
    library(stringr)
  })
})

# Set library path
# Prefer R_LIBS_USER if provided; else use default project lib
lib_user <- Sys.getenv("R_LIBS_USER")
if (nzchar(lib_user)) {
  .libPaths(lib_user)
} else {
  .libPaths("/home/olier/ellenberg/.Rlib")
}

# --- Simple arg parser (consistent with other Stage_2 scripts) ---
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

# Inputs/outputs
in_csv        <- opts[["input_csv"]] %||% "artifacts/model_data_bioclim_subset_enhanced.csv"
out_csv       <- opts[["out_csv"]] %||% "artifacts/model_data_bioclim_subset_enhanced_imputed.csv"
out_dir_diag  <- opts[["diag_dir"]] %||% "artifacts/phylotraits_impute"
tmp_dir       <- opts[["tmp_dir"]] %||% file.path(out_dir_diag, "tmp_bhpmf")

# BHPMF parameters
used_levels_raw <- opts[["used_levels"]]
used_levels   <- suppressWarnings(as.integer(used_levels_raw))
prediction_lv <- as.integer(opts[["prediction_level"]] %||% "3")  # default; will be clamped to actual levels
num_samples   <- as.integer(opts[["num_samples"]] %||% "1000")
burn          <- as.integer(opts[["burn"]] %||% "100")
gaps          <- as.integer(opts[["gaps"]] %||% "2")
num_latent    <- as.integer(opts[["num_latent"]] %||% "10")
tuning        <- tolower(opts[["tuning"]] %||% "false") %in% c("true","1","yes")
verbose       <- tolower(opts[["verbose"]] %||% "false") %in% c("true","1","yes")

# Trait selection
traits_to_impute <- opts[["traits_to_impute"]] %||% "Leaf_thickness_mm,Frost_tolerance_score,Leaf_N_per_area,LDMC"
traits_to_impute <- strsplit(traits_to_impute, ",")[[1]] %>% trimws()

# Optional: include environmental covariates (species-level climate means) to help imputation
add_env_covars <- tolower(opts[["add_env_covars"]] %||% "false") %in% c("true","1","yes")
env_csv        <- opts[["env_csv"]] %||% "data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv"
env_cols_regex <- opts[["env_cols_regex"]] %||% "^bio[0-9]{1,2}_mean$"
env_center_scale <- tolower(opts[["env_center_scale"]] %||% "true") %in% c("true","1","yes")

# Helper
fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }
ok   <- function(msg)  { cat(sprintf("[ok] %s\n", msg)) }

ensure_dir <- function(path) { dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE) }

norm_species <- function(x) {
  x <- as.character(x)
  x <- gsub("[[:space:]]+", " ", x)
  x <- trimws(x)
  tolower(x)
}

# --- Load data ---
if (!file.exists(in_csv)) fail(sprintf("Input not found: %s", in_csv))
dt_raw <- fread(in_csv)
dt <- copy(dt_raw)
ok(sprintf("Loaded input: %s (%d rows, %d cols)", in_csv, nrow(dt), ncol(dt)))

# --- Build hierarchy (Family -> Genus -> Species) ---
if (!all(c("wfo_accepted_name","Genus","Family") %in% names(dt))) {
  fail("Input is missing required columns: wfo_accepted_name, Genus, Family")
}

# Hierarchy mode: prefer genus+species by default to avoid multi-parent family issues
hierarchy_mode <- opts[["hierarchy"]] %||% "genus_species"  # alternatives: family_genus_species

dt$species_key <- norm_species(dt$wfo_accepted_name)
dt$Genus  <- ifelse(is.na(dt$Genus)  | dt$Genus  == "", "UnknownGenus", dt$Genus)
dt$Family <- ifelse(is.na(dt$Family) | dt$Family == "", "UnknownFamily", dt$Family)

# --- Detect anti-leakage vs legacy mode ---
# Anti-leakage: Only log traits (logLA, logNmass, etc.), no raw traits
# Legacy: Raw traits (Leaf area (mm2), etc.)
has_log_traits <- any(grepl("^log[A-Z]", names(dt)))
num_cols_core_raw <- c("Leaf area (mm2)", "Nmass (mg/g)", "SLA (mm2/mg)",
                       "Plant height (m)", "Diaspore mass (mg)")
has_raw_traits <- any(num_cols_core_raw %in% names(dt))

if (!has_raw_traits && !has_log_traits) {
  fail("No trait columns found (neither raw traits nor log traits)")
}

anti_leakage_mode <- !has_raw_traits && has_log_traits

if (anti_leakage_mode) {
  cat("[info] ANTI-LEAKAGE MODE: Using log traits only (no raw traits)\n")
  num_cols_core <- c()  # Empty - no raw traits
} else {
  cat("[info] LEGACY MODE: Using raw traits\n")
  num_cols_core <- num_cols_core_raw
}

# --- Build numeric matrix X for BHPMF ---
# Include core numeric traits to anchor correlations + selected new numeric traits
# NOTE: Use canonical SLA (mm2/mg) not LMA (g/m2) - see 1.3b_Dataset_Processing.md

# Legacy support: if LMA present but not SLA, convert
if (!("SLA (mm2/mg)" %in% names(dt)) && ("LMA (g/m2)" %in% names(dt))) {
  dt$`SLA (mm2/mg)` <- 1000 / dt$`LMA (g/m2)`
  message("Converted LMA to SLA (SLA = 1000/LMA)")
}

# SSD is optional (not always needed)
if ("SSD used (mg/mm3)" %in% names(dt)) {
  num_cols_core <- c(num_cols_core, "SSD used (mg/mm3)")
} else if ("SSD combined (mg/mm3)" %in% names(dt)) {
  dt$`SSD used (mg/mm3)` <- dt$`SSD combined (mg/mm3)`
  num_cols_core <- c(num_cols_core, "SSD used (mg/mm3)")
}

num_cols_new  <- intersect(c("Leaf_thickness_mm", "Frost_tolerance_score", "Leaf_N_per_area", "LDMC"), names(dt))
traits_existing <- intersect(traits_to_impute, names(dt))


# DUAL-SCALE MODIFICATION: DISABLED FOR CV (creates raw copies AFTER masking = broken)
# Raw trait copies are created AFTER CV masking, so they're also NA when target is masked.
# This defeats the purpose (using raw as covariate) and causes BHPMF to impute both.
# For CV: Use log transforms only, not raw copies.
#
# raw_trait_mapping <- list(
#   "Leaf area (mm2)" = "Leaf_area_raw",
#   "Nmass (mg/g)" = "Nmass_raw",
#   "SLA (mm2/mg)" = "SLA_raw",
#   "Plant height (m)" = "Height_raw",
#   "Diaspore mass (mg)" = "Seed_mass_raw",
#   "LDMC" = "LDMC_raw"
# )
#
# # Create raw auxiliary columns
# for (target in names(raw_trait_mapping)) {
#   if (target %in% names(dt)) {
#     raw_col <- raw_trait_mapping[[target]]
#     dt[[raw_col]] <- dt[[target]]  # Copy before in-place transformation
#   }
# }

# Add pre-computed log transforms as auxiliary features (like XGBoost)
num_cols_log <- intersect(c("logLA", "logNmass", "logSLA", "logH", "logSM", "logLDMC"), names(dt))
# num_cols_raw_aux <- unlist(raw_trait_mapping[traits_existing])  # DISABLED

num_cols_all  <- unique(c(num_cols_core, num_cols_new, traits_existing, num_cols_log))

# AUTO-DETECT environmental q50 columns already in merged data (for merged workflow)
env_q50_cols <- grep("_q50$", names(dt), value = TRUE)
if (length(env_q50_cols) > 0 && !add_env_covars) {
  ok(sprintf("Auto-detected %d env q50 columns already in merged data", length(env_q50_cols)))
  num_cols_all <- unique(c(num_cols_all, env_q50_cols))
}

# Optionally join environmental covariates and add to X
if (add_env_covars) {
  if (!file.exists(env_csv)) fail(sprintf("Environmental summary not found: %s", env_csv))
  env <- fread(env_csv)
  # Build normalized species key for join
  env$species_key <- norm_species(env$species)
  dt$species_key <- norm_species(dt$wfo_accepted_name)
  env_keep <- grep(env_cols_regex, names(env), value = TRUE)
  if (length(env_keep) == 0) fail(sprintf("No env columns matched regex '%s'", env_cols_regex))
  env_sub <- env[, c("species_key", env_keep), with = FALSE]
  dt <- merge(dt, env_sub, by = "species_key", all.x = TRUE)
  if (env_center_scale) {
    for (cn in env_keep) {
      mu <- mean(dt[[cn]], na.rm = TRUE)
      sdv <- sd(dt[[cn]], na.rm = TRUE)
      if (!is.finite(sdv) || sdv == 0) next
      dt[[cn]] <- (dt[[cn]] - mu) / sdv
    }
  }
  num_cols_all <- unique(c(num_cols_all, env_keep))
}

# --- Build hierarchy after all merges ---
if (tolower(hierarchy_mode) == "family_genus_species") {
  # Order from lowest level (Species) to highest (Family) as BHPMF expects
  hierarchy.info <- as.matrix(data.frame(Species = dt$species_key,
                                         Genus   = dt$Genus,
                                         Family  = dt$Family,
                                         stringsAsFactors = FALSE))
} else {
  # Default: lowest to highest (Species, Genus)
  hierarchy.info <- as.matrix(data.frame(Species = dt$species_key,
                                         Genus   = dt$Genus,
                                         stringsAsFactors = FALSE))
}

# Additional validation for legacy mode (raw traits)
if (!anti_leakage_mode && length(num_cols_core) > 0) {
  missing_core <- setdiff(num_cols_core, names(dt))
  if (length(missing_core) > 0) {
    fail(sprintf("Missing core numeric trait columns: %s", paste(missing_core, collapse=", ")))
  }
}

# Ensure numeric types
cat("[progress] Transforming and standardizing features...\n")
transform_info <- list()
log_traits <- c("Leaf area (mm2)", "Nmass (mg/g)", "SLA (mm2/mg)",
                "Plant height (m)", "Diaspore mass (mg)")
fraction_traits <- c("LDMC")
eps <- 1e-06

for (cn in num_cols_all) {
  if (!(cn %in% names(dt))) next
  suppressWarnings({ dt[[cn]] <- as.numeric(dt[[cn]]) })
  bad <- !is.finite(dt[[cn]])
  if (any(bad, na.rm = TRUE)) dt[[cn]][bad] <- NA_real_
  values <- dt[[cn]]
  tf_type <- "identity"

  # DUAL-SCALE APPROACH:
  # - TARGET traits (traits_to_impute): log/logit transform IN-PLACE (bounded predictions)
  # - RAW auxiliary (*_raw): just standardize (cross-scale covariate)
  # - PRE-COMPUTED logs (log*): just standardize (already in log space)
  # - ENV features: just standardize

  is_target <- cn %in% traits_to_impute
  is_raw_aux <- grepl("_raw$", cn)
  is_precomputed_log <- grepl("^log", cn)

  # Auxiliary features: no transformation, just standardize
  if (is_raw_aux || is_precomputed_log) {
    mu <- mean(values, na.rm = TRUE)
    sdv <- stats::sd(values, na.rm = TRUE)
    if (!is.finite(mu)) mu <- 0
    if (!is.finite(sdv) || sdv < 1e-09) sdv <- 1
    dt[[cn]] <- (values - mu) / sdv
    transform_info[[cn]] <- list(type = "identity", mean = mu, sd = sdv)
    next
  }

  # TARGET traits: transform in-place (like original BHPMF paper)
  if (is_target && cn %in% log_traits) {
    values[values <= 0] <- NA_real_
    logged <- log(values)
    mu <- mean(logged, na.rm = TRUE)
    sdv <- stats::sd(logged, na.rm = TRUE)
    if (!is.finite(mu)) mu <- 0
    if (!is.finite(sdv) || sdv < 1e-09) sdv <- 1
    dt[[cn]] <- (logged - mu) / sdv
    transform_info[[cn]] <- list(type = "log", mean = mu, sd = sdv)
    next
  }

  if (is_target && cn %in% fraction_traits) {
    values[values <= 0] <- NA_real_
    values[values >= 1] <- 1 - eps
    logit <- log(values / (1 - values))
    mu <- mean(logit, na.rm = TRUE)
    sdv <- stats::sd(logit, na.rm = TRUE)
    if (!is.finite(mu)) mu <- 0
    if (!is.finite(sdv) || sdv < 1e-09) sdv <- 1
    dt[[cn]] <- (logit - mu) / sdv
    transform_info[[cn]] <- list(type = "logit", mean = mu, sd = sdv)
    next
  }

  # default: center & scale (env features, other covariates)
  mu <- mean(values, na.rm = TRUE)
  sdv <- stats::sd(values, na.rm = TRUE)
  if (!is.finite(mu)) mu <- 0
  if (!is.finite(sdv) || sdv < 1e-09) sdv <- 1
  dt[[cn]] <- (values - mu) / sdv
  transform_info[[cn]] <- list(type = "identity", mean = mu, sd = sdv)
}

# BHPMF cannot handle rows with all features missing; ensure at least 1 observation per row
# Filter num_cols_all to only existing columns (anti-leakage safety)
existing_cols <- intersect(num_cols_all, names(dt))
missing_cols <- setdiff(num_cols_all, names(dt))
if (length(missing_cols) > 0) {
  cat(sprintf("[warn] Excluding %d non-existent columns from BHPMF matrix\n", length(missing_cols)))
  num_cols_all <- existing_cols
}

have_any_numeric <- Reduce(`|`, lapply(num_cols_all, function(cn) !is.na(dt[[cn]])))
if (!all(have_any_numeric)) {
  n_drop <- sum(!have_any_numeric)
  ok(sprintf("Dropping %d rows with all-numeric NA (BHPMF requirement)", n_drop))
}
X <- as.matrix(dt[have_any_numeric, ..num_cols_all])
rownames(X) <- dt$species_key[have_any_numeric]
hier_sub <- hierarchy.info[have_any_numeric, , drop = FALSE]

# Finalize used_levels: if not provided or out of range, set to (num_levels - 1)
num_levels_total <- ncol(hier_sub)
# Allow explicit used_levels=0 (pure PMF) to bypass hierarchy
if (length(used_levels_raw) == 0 || is.na(used_levels)) {
  used_levels <- max(0L, num_levels_total - 1L)
} else {
  # Clamp to [0, num_levels_total-1]
  if (used_levels > (num_levels_total - 1L)) used_levels <- max(0L, num_levels_total - 1L)
  if (used_levels < 0L) used_levels <- 0L
}

# Clamp prediction level to available levels (species is the last column)
if (is.na(prediction_lv) || prediction_lv > num_levels_total || prediction_lv < 1L) {
  prediction_lv <- num_levels_total
}

# --- BHPMF availability check ---
bhpmf_loaded <- FALSE
try({ suppressPackageStartupMessages(library(BHPMF)); bhpmf_loaded <- TRUE }, silent = TRUE)
if (!bhpmf_loaded) {
  # Try devtools::load_all to use local repo
  try({
    suppressPackageStartupMessages(library(devtools))
    devtools::load_all("/home/olier/BHPMF", quiet = TRUE)
    bhpmf_loaded <- TRUE
  }, silent = TRUE)
}
if (!bhpmf_loaded) {
  fail(paste(
    "BHPMF is not available. Install/compile the local package first.",
    "\nHints:",
    "- R <= 3.4.4 is recommended by BHPMF README due to compiler compatibility.",
    "- From R: devtools::install('/home/olier/BHPMF', build = TRUE)",
    "- Or: R CMD INSTALL /home/olier/BHPMF",
    sep = "\n"
  ))
}

# --- Run BHPMF gap filling ---
ensure_dir(out_csv)
dir.create(out_dir_diag, recursive = TRUE, showWarnings = FALSE)
dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)

mean_out <- file.path(out_dir_diag, "bhpmf_mean.tsv")
std_out  <- file.path(out_dir_diag, "bhpmf_std.tsv")

cat("\n============================================================\n")
cat("BHPMF GAP FILLING\n")
cat("============================================================\n")
cat(sprintf("Rows: %d, Cols: %d, Used levels: %d, Predict level: %d\n",
            nrow(X), ncol(X), used_levels, prediction_lv))

cat("[progress] Starting BHPMF GapFilling (this may take 10-30 seconds)...\n")
flush.console()
set.seed(123)
start_time <- Sys.time()
GapFilling(
  X = X,
  hierarchy.info = hier_sub,
  prediction.level = prediction_lv,
  used.num.hierarchy.levels = used_levels,
  num.samples = num_samples,
  burn = burn,
  gaps = gaps,
  num.latent.feats = num_latent,
  tuning = tuning,
  num.folds.tuning = if (tuning) 10 else 0,
  tmp.dir = tmp_dir,
  mean.gap.filled.output.path = mean_out,
  std.gap.filled.output.path = std_out,
  rmse.plot.test.data = TRUE,
  verbose = verbose
)
end_time <- Sys.time()
elapsed <- round(difftime(end_time, start_time, units = "secs"), 1)
cat(sprintf("[progress] BHPMF completed in %.1f seconds\n", elapsed))

# --- Read BHPMF outputs and merge back ---
cat("[progress] Reading BHPMF outputs...\n")
pred_mean <- as.data.frame(as.matrix(read.table(mean_out, sep = "\t", header = TRUE, check.names = FALSE)))
pred_std  <- as.data.frame(as.matrix(read.table(std_out,  sep = "\t", header = TRUE, check.names = FALSE)))

# Sanity: preserve column ordering
pred_mean <- pred_mean[, colnames(X), drop = FALSE]
pred_std  <- pred_std[,  colnames(X), drop = FALSE]

# Map back to full species table
dt_imputed <- copy(dt_raw)
row_map <- match(dt$species_key, rownames(X))

# Only impute for selected traits; skip categorical ones here
traits_supported <- intersect(traits_to_impute, colnames(X))
if (length(traits_supported) == 0) {
  fail(sprintf("None of the requested traits_to_impute are numeric BHPMF features: %s",
               paste(traits_to_impute, collapse=",")))
}

for (cn in traits_supported) {
  imputed_vals <- rep(NA_real_, nrow(dt))
  imputed_sds  <- rep(NA_real_, nrow(dt))
  idx <- which(!is.na(row_map))
  imputed_vals[idx] <- pred_mean[cbind(row_map[idx], match(cn, colnames(X)))]
  imputed_sds[idx]  <- pred_std[cbind(row_map[idx],  match(cn, colnames(X)))]
  flag_col <- paste0(cn, "_imputed_flag")
  sd_col   <- paste0(cn, "_impute_sd")
  
  # If original missing, replace with imputed; else keep original
  orig <- dt_imputed[[cn]]
  replaced <- is.na(orig) & !is.na(imputed_vals)
  info <- transform_info[[cn]]

  inv_transform <- function(zvals, info) {
    # Clip extreme z-scores to prevent nonsensical back-transforms
    # ±4 SD covers 99.99% of normal distribution
    zvals_clipped <- pmin(pmax(zvals, -4), 4)

    scaled <- zvals_clipped * info$sd + info$mean
    if (info$type == "log") {
      return(exp(scaled))
    } else if (info$type == "logit") {
      return(1 / (1 + exp(-scaled)))
    } else {
      return(scaled)
    }
  }

  inv_sd <- function(sd_z, zvals, info) {
    if (is.null(sd_z)) return(sd_z)
    scaled_sd <- sd_z * info$sd
    scaled_mean <- zvals * info$sd + info$mean
    if (info$type == "log") {
      return(scaled_sd * exp(scaled_mean))
    } else if (info$type == "logit") {
      p <- 1 / (1 + exp(-scaled_mean))
      return(scaled_sd * p * (1 - p))
    } else {
      return(scaled_sd)
    }
  }

  converted_vals <- inv_transform(imputed_vals[replaced], info)
  dt_imputed[[cn]][replaced] <- converted_vals
  dt_imputed[[flag_col]] <- as.integer(replaced)
  dt_imputed[[sd_col]]   <- NA_real_
  if (!all(is.na(imputed_sds))) {
    dt_imputed[[sd_col]][replaced] <- inv_sd(imputed_sds[replaced], imputed_vals[replaced], info)
  }
  ok(sprintf("Imputed %s: replaced %d missing values", cn, sum(replaced)))
}

# Recompute LDMC-derived features given imputed LDMC (if available)
if ("LDMC" %in% names(dt_imputed) && "Leaf area (mm2)" %in% names(dt_imputed)) {
  valid <- !is.na(dt_imputed$LDMC) & (dt_imputed$LDMC > 0) &
           !is.na(dt_imputed$`Leaf area (mm2)`) & (dt_imputed$`Leaf area (mm2)` > 0)
  dt_imputed$log_ldmc_plus_log_la  <- NA_real_
  dt_imputed$log_ldmc_minus_log_la <- NA_real_
  dt_imputed$log_ldmc_plus_log_la[valid]  <- log(dt_imputed$LDMC[valid]) + log(dt_imputed$`Leaf area (mm2)`[valid])
  dt_imputed$log_ldmc_minus_log_la[valid] <- log(dt_imputed$LDMC[valid]) - log(dt_imputed$`Leaf area (mm2)`[valid])
  ok(sprintf("Recomputed LDMC-derived features for %d species", sum(valid)))
}

# --- Coverage report ---
cov_before <- sapply(traits_supported, function(cn) sum(!is.na(dt[[cn]])))
cov_after  <- sapply(traits_supported, function(cn) sum(!is.na(dt_imputed[[cn]])))
coverage <- data.frame(trait = traits_supported,
                       before = as.integer(cov_before),
                       after = as.integer(cov_after),
                       stringsAsFactors = FALSE)
fwrite(coverage, file.path(out_dir_diag, "coverage_before_after.csv"))

# --- Save final table ---
fwrite(dt_imputed, out_csv)
ok(sprintf("Wrote imputed dataset: %s (%d rows, %d cols)", out_csv, nrow(dt_imputed), ncol(dt_imputed)))
ok(sprintf("Diagnostics in: %s", out_dir_diag))

cat("\nDone.\n")

invisible(NULL)
