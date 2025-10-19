#!/usr/bin/env Rscript

# Cumulative link models for EIVE L/M/N with Bill Shipley (2017) trait spec + phylogenetic predictor

suppressPackageStartupMessages({
  library(optparse)
  library(readr)
  library(dplyr)
  library(stringr)
  library(tidyr)
  library(purrr)
  library(VGAM)
  library(ape)
})

option_list <- list(
  make_option("--axis", type = "character", default = "L",
              help = "Target axis: L, M, or N"),
  make_option("--input", type = "character",
              default = "artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv",
              help = "Stage 2 species-level matrix"),
  make_option("--tree", type = "character",
              default = "data/phylogeny/eive_try_tree.nwk",
              help = "Phylogeny in Newick format"),
  make_option("--eive", type = "character",
              default = "data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv",
              help = "EIVE summary table with .n weights"),
  make_option("--out_dir", type = "character",
              default = "artifacts/stage2_clm_trait_phylo",
              help = "Output directory prefix"),
  make_option("--folds", type = "integer", default = 10,
              help = "Number of stratified folds (default 10)"),
  make_option("--repeats", type = "integer", default = 5,
              help = "Number of CV repeats (default 5 -> 50 stratified folds)"),
  make_option("--x_grid", type = "character", default = "0.5,1,2",
              help = "Comma-separated exponent grid for phylogenetic weighting"),
  make_option("--no_phylo", action = "store_true", default = FALSE,
              help = "Disable the phylogenetic predictor"),
  make_option("--overwrite", action = "store_true", default = FALSE,
              help = "Overwrite existing outputs"),
  make_option("--seed", type = "integer", default = 123,
              help = "Random seed")
)

opt <- parse_args(OptionParser(option_list = option_list))

axis <- toupper(opt$axis)
stopifnot(axis %in% c("L", "M", "N"))
axis_col <- paste0("EIVEres-", axis)

message("[setup] Running CLM workflow for axis ", axis)
if (nzchar(Sys.getenv("CLM_WARN2"))) options(warn = 2)
verbose <- tolower(Sys.getenv("CLM_VERBOSE", "false")) %in% c("1", "true", "yes")
set.seed(opt$seed)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
clean_taxon <- function(x) {
  x %>%
    str_replace(" subsp\\..*", "") %>%
    str_replace(" var\\..*", "") %>%
    str_replace(" ×", " x") %>%
    str_trim()
}

log_transform <- function(x) {
  out <- ifelse(is.finite(x) & x > 0, log(x), NA_real_)
  out
}

ordinal_response <- function(x) {
  ordered(round(x) + 1L, levels = 0:10 + 1L)
}

phylo_predict_train <- function(dist_mat, train_names, train_values, x_exp) {
  submat <- dist_mat[train_names, train_names, drop = FALSE]
  diag(submat) <- NA_real_
  weights <- submat^(-x_exp)
  weights[!is.finite(weights)] <- 0
  num <- weights %*% train_values
  den <- rowSums(weights)
  pred <- as.numeric(num / den)
  pred[!is.finite(pred)] <- mean(train_values, na.rm = TRUE)
  pred
}

phylo_predict_test <- function(dist_mat, test_names, train_names, train_values, x_exp) {
  submat <- dist_mat[test_names, train_names, drop = FALSE]
  weights <- submat^(-x_exp)
  weights[!is.finite(weights)] <- 0
  num <- weights %*% train_values
  den <- rowSums(weights)
  pred <- as.numeric(num / den)
  fallback <- mean(train_values, na.rm = TRUE)
  pred[!is.finite(pred)] <- fallback
  pred
}

fit_clm <- function(df, weights_col, include_phylo = TRUE) {
  trait_terms <- c("logLA", "logLDMC", "logSLA", "logSM")
  pairwise_terms <- apply(combn(trait_terms, 2), 2, paste, collapse = ":")
  three_way_terms <- apply(combn(trait_terms, 3), 2, paste, collapse = ":")
  four_way_term <- paste(trait_terms, collapse = ":")
  base_parts <- c(
    "plant_form",
    trait_terms,
    paste0("plant_form:", trait_terms),
    pairwise_terms,
    three_way_terms,
    four_way_term
  )
  formula_str <- paste("axis_y ~", paste(base_parts, collapse = " + "))
  if (include_phylo) {
    formula_str <- paste(formula_str, "+ phylo_pred")
  }
  vglm(
    formula = as.formula(formula_str),
    data = df,
    family = cumulative(link = "logit", parallel = TRUE),
    weights = df[[weights_col]]
  )
}

predict_expected <- function(fit, newdata) {
  probs <- predict(fit,
                   newdata = newdata,
                   type = "response",
                   type.fitted = "probabilities")
  classes <- suppressWarnings(as.numeric(colnames(probs)))
  if (anyNA(classes)) {
    classes <- seq_len(ncol(probs))
  }
  drop(probs %*% classes) - 1
}

stratified_partition <- function(y_factor, k, repeats) {
  n <- length(y_factor)
  assignments <- vector("list", repeats * k)
  meta <- tibble()
  counter <- 1L
  idx_all <- seq_len(n)
  for (r in seq_len(repeats)) {
    fold_assign <- integer(n)
    for (lvl in levels(y_factor)) {
      level_idx <- idx_all[y_factor == lvl]
      if (!length(level_idx)) next
      fold_seq <- sample(rep(seq_len(k), length.out = length(level_idx)))
      fold_assign[y_factor == lvl] <- fold_seq
    }
    for (fold in seq_len(k)) {
      test_idx <- which(fold_assign == fold)
      if (!length(test_idx)) next
      train_idx <- setdiff(idx_all, test_idx)
      assignments[[counter]] <- list(train = train_idx, test = test_idx)
      meta <- bind_rows(meta, tibble(rep_id = r, fold_id = fold))
      counter <- counter + 1L
    }
  }
  assignments <- assignments[seq_len(counter - 1L)]
  list(assignments = assignments, meta = meta)
}

# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------
if (!file.exists(opt$input)) stop("Input dataset not found: ", opt$input)
if (!file.exists(opt$tree)) stop("Tree not found: ", opt$tree)
if (!file.exists(opt$eive)) stop("EIVE table not found: ", opt$eive)

stage2 <- read_csv(opt$input, show_col_types = FALSE)
eive_table <- read_csv(opt$eive, show_col_types = FALSE)

stage2 <- stage2 %>% mutate(clean_name = clean_taxon(`wfo_accepted_name`))
eive_table <- eive_table %>% mutate(clean_name = clean_taxon(TaxonConcept))

if ("has_sufficient_data_bioclim" %in% names(stage2)) {
  stage2 <- stage2 %>% filter(!is.na(has_sufficient_data_bioclim) & has_sufficient_data_bioclim)
}

if (!(axis_col %in% names(stage2))) stop("Target column missing: ", axis_col)

trait_cols <- c("Leaf area (mm2)", "LDMC", "LMA", "Diaspore mass (mg)")
missing_trait <- setdiff(trait_cols, names(stage2))
if (length(missing_trait)) stop("Missing required trait columns: ", paste(missing_trait, collapse = ", "))

stage2 <- stage2 %>%
  mutate(
    logLA = log_transform(`Leaf area (mm2)`),
    logLDMC = log_transform(LDMC),
    logSLA = log_transform(1 / LMA),
    logSM = log_transform(`Diaspore mass (mg)`),
    plant_form = case_when(
      str_detect(`Growth Form`, "graminoid") ~ "graminoid",
      str_detect(`Growth Form`, "shrub") ~ "shrub",
      str_detect(`Growth Form`, "tree") ~ "tree",
      Woodiness == "woody" ~ "tree",
      TRUE ~ "herb"
    )
  )

axis_vector <- stage2[[axis_col]]

keep <- is.finite(axis_vector) &
  is.finite(stage2$logLA) &
  is.finite(stage2$logLDMC) &
  is.finite(stage2$logSLA) &
  is.finite(stage2$logSM) &
  !is.na(stage2$plant_form)

stage2 <- stage2[keep, ]
axis_vector <- axis_vector[keep]
stage2$plant_form <- factor(stage2$plant_form,
                            levels = c("graminoid", "herb", "shrub", "tree"))

message(sprintf("[data] %d species retained after filtering", nrow(stage2)))

# ---------------------------------------------------------------------------
# Phylogeny
# ---------------------------------------------------------------------------
phylo_tree <- read.tree(opt$tree)
phylo_tree$tip.label <- gsub("_", " ", phylo_tree$tip.label)

matched <- match(stage2$clean_name, phylo_tree$tip.label)
if (anyNA(matched)) {
  missing_species <- unique(stage2$clean_name[is.na(matched)])
  message("[phylo] Dropping ", length(missing_species),
          " species absent from tree: ", paste(missing_species, collapse = ", "))
  keep <- !is.na(matched)
  stage2 <- stage2[keep, ]
  axis_vector <- axis_vector[keep]
  matched <- matched[keep]
}

phylo_tree <- suppressWarnings(drop.tip(phylo_tree, setdiff(phylo_tree$tip.label, stage2$clean_name)))
dist_matrix <- cophenetic(phylo_tree)

# ---------------------------------------------------------------------------
# Prepare modelling data
# ---------------------------------------------------------------------------
axis_response <- ordinal_response(axis_vector)
x_values <- as.numeric(strsplit(opt$x_grid, ",")[[1]])
if (any(is.na(x_values))) stop("Invalid --x_grid specification")
use_phylo <- !isTRUE(opt$no_phylo)
if (!use_phylo) {
  message("[phylo] Predictor disabled via --no_phylo")
} else {
  if (length(x_values) > 1) {
    message("[phylo] Stage 2 alignment: using first exponent from --x_grid (", x_values[1], "); additional values ignored")
  }
}
x_fixed <- if (use_phylo) x_values[1] else NA_real_

base_df <- stage2 %>%
  mutate(
    axis_y = axis_response,
    weight = 1
  )

cv_folds <- stratified_partition(axis_response, opt$folds, opt$repeats)
assignments <- cv_folds$assignments
meta <- cv_folds$meta

results <- vector("list", length(assignments))
coef_records <- vector("list", length(assignments))

# ---------------------------------------------------------------------------
# Cross-validation
# ---------------------------------------------------------------------------
for (i in seq_along(assignments)) {
  fold_info <- assignments[[i]]
  train_idx <- fold_info$train
  test_idx <- fold_info$test

  train_df <- base_df[train_idx, ]
  test_df <- base_df[test_idx, ]

  train_names <- train_df$clean_name
  test_names <- test_df$clean_name
  train_values <- axis_vector[train_idx]

  best_x <- if (use_phylo) x_fixed else NA_real_
  best_fit <- NULL
  best_preds <- NULL

  train_tmp <- train_df
  test_tmp <- test_df
  mu <- 0
  sigma <- 1
  if (use_phylo) {
    raw_train <- phylo_predict_train(dist_matrix, train_names, train_values, best_x)
    mu <- mean(raw_train, na.rm = TRUE)
    sigma <- sd(raw_train, na.rm = TRUE)
    if (!is.finite(sigma) || sigma == 0) sigma <- 1
    train_tmp$phylo_pred <- (raw_train - mu) / sigma
    raw_test <- phylo_predict_test(dist_matrix, test_names, train_names, train_values, best_x)
    test_tmp$phylo_pred <- (raw_test - mu) / sigma
  } else {
    train_tmp$phylo_pred <- 0
    test_tmp$phylo_pred <- 0
  }

  fit <- tryCatch(
    fit_clm(train_tmp, "weight", include_phylo = use_phylo),
    error = function(e) {
      if (verbose) message("[fold ", i, "] model error: ", e$message)
      NULL
    }
  )
  if (!is.null(fit)) {
    best_fit <- fit
    best_preds <- tryCatch(
      predict_expected(fit, test_tmp),
      error = function(e) rep(NA_real_, nrow(test_tmp))
    )
  }

  if (is.null(best_fit)) {
    warning("[fold] Unable to fit any model for fold ", i)
    next
  }

  if (use_phylo) {
    raw_train <- phylo_predict_train(dist_matrix, train_names, train_values, best_x)
    mu <- mean(raw_train, na.rm = TRUE)
    sigma <- sd(raw_train, na.rm = TRUE)
    if (!is.finite(sigma) || sigma == 0) sigma <- 1
  } else {
    mu <- 0
    sigma <- 1
  }

  results[[i]] <- tibble(
    rep_id = meta$rep_id[i],
    fold_id = meta$fold_id[i],
    species = test_df$`wfo_accepted_name`,
    plant_form = as.character(test_df$plant_form),
    y_true = axis_vector[test_idx],
    y_pred = best_preds,
    abs_error = abs(y_true - y_pred),
    sq_error = (y_true - y_pred)^2,
    within_1 = abs_error <= 1,
    best_x = best_x
  )

  coef_records[[i]] <- tibble(
    rep_id = meta$rep_id[i],
    fold_id = meta$fold_id[i],
    x_exp = best_x,
    term = names(coef(best_fit)),
    estimate = coef(best_fit)
  )
}

cv_results <- bind_rows(results)
coef_df <- bind_rows(coef_records)

metrics <- cv_results %>%
  summarise(
    mae = mean(abs_error, na.rm = TRUE),
    rmse = sqrt(mean(sq_error, na.rm = TRUE)),
    bias = mean(y_pred - y_true, na.rm = TRUE),
    within_1_rate = mean(within_1, na.rm = TRUE)
  )

message("[cv] MAE = ", round(metrics$mae, 3),
        " | RMSE = ", round(metrics$rmse, 3),
        " | within ±1 = ", round(metrics$within_1_rate, 3))

# ---------------------------------------------------------------------------
# Fit final model on full dataset using median x
# ---------------------------------------------------------------------------
if (use_phylo) {
  global_x <- x_fixed
  train_names <- base_df$clean_name
  train_values <- axis_vector
  raw_train <- phylo_predict_train(dist_matrix, train_names, train_values, global_x)
  mu <- mean(raw_train, na.rm = TRUE)
  sigma <- sd(raw_train, na.rm = TRUE)
  if (!is.finite(sigma) || sigma == 0) sigma <- 1
  base_df$phylo_pred <- (raw_train - mu) / sigma
} else {
  global_x <- NA_real_
  mu <- 0
  sigma <- 1
  base_df$phylo_pred <- 0
}

final_model <- fit_clm(base_df, "weight", include_phylo = use_phylo)

out_dir <- file.path(opt$out_dir, axis)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
if (!opt$overwrite && file.exists(file.path(out_dir, "cv_metrics.csv"))) {
  stop("Outputs already exist in ", out_dir, "; use --overwrite to replace")
}

write_csv(cv_results, file.path(out_dir, "cv_predictions.csv"))
write_csv(coef_df, file.path(out_dir, "cv_coefficients.csv"))
write_csv(metrics, file.path(out_dir, "cv_metrics.csv"))
write_csv(meta, file.path(out_dir, "cv_meta.csv"))
write_csv(tibble(global_x = global_x, center = mu, scale = sigma, use_phylo = use_phylo),
          file.path(out_dir, "phylo_scaling.csv"))
saveRDS(final_model, file.path(out_dir, "final_model.rds"))

message("[done] Outputs written to ", out_dir)
