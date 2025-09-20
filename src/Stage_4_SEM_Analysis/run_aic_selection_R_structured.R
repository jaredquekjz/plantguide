#!/usr/bin/env Rscript

# Reaction (R) axis GAM aligned with pwSEM structured regression
# Keeps trait PCs + raw traits, soil pH profile, cross-axis dependency, and random effects

suppressPackageStartupMessages({
  library(tidyverse)
  library(mgcv)
  library(MuMIn)
})

script_args <- commandArgs(trailingOnly = FALSE)
script_file_arg <- sub("^--file=", "", grep("^--file=", script_args, value = TRUE))
script_dir <- if (length(script_file_arg)) dirname(normalizePath(script_file_arg[1])) else getwd()
source(file.path(script_dir, "nested_gam_cv_utils.R"))

set.seed(123)

`%||%` <- function(x, y) if (!is.null(x) && length(x) && !is.na(x[1])) x else y

cat("=== R Axis GAM (pwSEM-aligned) ===\n")

raw_path <- "artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv"
if (!file.exists(raw_path)) stop("Input dataset not found: ", raw_path)

data <- read.csv(raw_path, check.names = FALSE, stringsAsFactors = FALSE)

target_col <- "EIVEres-R"
if (!(target_col %in% names(data))) stop("Target column missing")

data <- data[!is.na(data[[target_col]]), ]
resp <- "target_y"
data[[resp]] <- data[[target_col]]
cat(sprintf("Working with %d complete cases for R axis\n", nrow(data)))

species_vector <- if ("species_key" %in% names(data)) data$species_key else data$wfo_accepted_name
species_slugs <- slugify(species_vector)
species_slugs[!nzchar(species_slugs)] <- paste0("species_", seq_along(species_slugs))[!nzchar(species_slugs)]
species_labels <- if ("wfo_accepted_name" %in% names(data)) data$wfo_accepted_name else species_vector
family_vec <- if ("Family" %in% names(data)) data$Family else rep(NA_character_, nrow(data))

if (!"species_slug" %in% names(data)) {
  data$species_slug <- species_slugs
}

# Cross-axis dependency
if ("EIVEres-N" %in% names(data) && !("EIVEres_N" %in% names(data))) {
  data$EIVEres_N <- data[["EIVEres-N"]]
  cat("[info] Added cross-axis feature EIVEres_N\n")
}

# Trait PCs + raw traits
trait_cols <- c("logLA", "logSM", "logSSD", "logH", "LES_core", "SIZE", "LMA", "Nmass", "LDMC", "log_ldmc_minus_log_la")
missing_traits <- setdiff(trait_cols, names(data))
if (length(missing_traits)) stop("Missing trait columns: ", paste(missing_traits, collapse = ", "))

trait_matrix <- data[trait_cols]
trait_matrix[] <- lapply(trait_matrix, function(col) {
  col <- as.numeric(col)
  ifelse(is.finite(col), col, NA_real_)
})
if (anyNA(trait_matrix)) {
  trait_matrix <- as.data.frame(lapply(trait_matrix, function(col) ifelse(is.na(col), mean(col, na.rm = TRUE), col)))
  cat("[info] Imputed missing trait values with column means before PCA\n")
}

pca <- prcomp(trait_matrix, center = TRUE, scale. = TRUE)
explained <- summary(pca)$importance[3, ]
pc_keep <- which(explained >= 0.90)
pc_keep <- if (length(pc_keep)) pc_keep[1] else min(4, ncol(pca$x))
pc_keep <- min(pc_keep, 4)
pc_scores <- pca$x[, seq_len(pc_keep), drop = FALSE]
for (i in seq_len(pc_keep)) data[[paste0("pc_trait_", i)]] <- pc_scores[, i]
cat(sprintf("[info] Retaining %d trait PCs (~%.1f%% variance)\n", pc_keep, explained[pc_keep] * 100))
pc_cols <- paste0("pc_trait_", seq_len(pc_keep))

# Feature sets
ph_features <- c(
  "phh2o_0_5cm_mean", "phh2o_0_5cm_p90",
  "phh2o_5_15cm_mean", "phh2o_5_15cm_p90", "phh2o_5_15cm_p10",
  "phh2o_15_30cm_mean", "phh2o_15_30cm_p90",
  "ph_rootzone_mean", "hplus_rootzone_mean"
)
climate_vars <- c(
  "mat_mean", "mat_q95", "temp_range", "temp_seasonality",
  "precip_mean", "precip_cv", "precip_warmest_q", "drought_min",
  "ai_amp", "ai_cv_month"
)
interaction_vars <- c("wood_precip", "height_temp", "lma_precip", "les_drought")
phylo_col <- "p_phylo_R"

num_cols <- setdiff(names(data), c("Family", "is_woody", "wfo_accepted_name"))
if (length(num_cols)) data[num_cols] <- lapply(data[num_cols], function(x) suppressWarnings(as.numeric(x)))
if ("is_woody" %in% names(data)) data$is_woody <- factor(data$is_woody)
if ("Family" %in% names(data)) data$Family <- factor(data$Family)

quote_term <- function(term) {
  vapply(term, function(x) {
    if (is.na(x) || x == "") return("")
    if (grepl("[^A-Za-z0-9_]", x)) paste0("`", x, "`") else x
  }, character(1))
}

linear_vars <- unique(c(
  'logSM', 'log_ldmc_minus_log_la', 'logLA', 'logH', 'logSSD',
  'LES_core', 'SIZE', 'Nmass', 'mat_mean', 'temp_range', 'drought_min',
  'precip_warmest_q', 'wood_precip', 'height_temp', 'lma_precip', 'les_drought',
  phylo_col, 'EIVEres_N', 'is_woody'
))
if ("is_woody" %in% names(data)) linear_vars <- c(linear_vars, "is_woody")
linear_terms <- unique(quote_term(linear_vars))

interaction_terms <- character(0)
if (all(c("SIZE", "logSSD") %in% names(data))) interaction_terms <- c(interaction_terms, "SIZE:logSSD")

smooth_vars <- intersect(c('phh2o_5_15cm_mean', 'phh2o_5_15cm_p90', 'phh2o_15_30cm_mean', 'EIVEres_N'), names(data))
smooth_terms <- if (length(smooth_vars)) sprintf("s(%s, k=5)", quote_term(smooth_vars)) else character(0)

tensor_terms <- character(0)
if (all(c('ph_rootzone_mean', 'drought_min') %in% names(data))) tensor_terms <- c(tensor_terms, 'ti(ph_rootzone_mean, drought_min, k=c(4,4))')

random_terms <- character(0)
if (phylo_col %in% names(data)) random_terms <- c(random_terms, "s(p_phylo_R, bs=\"re\")")

formula_terms <- c(linear_terms, interaction_terms, smooth_terms, tensor_terms, random_terms)
formula_terms <- formula_terms[nzchar(formula_terms)]
formula_txt <- paste(resp, "~", paste(formula_terms, collapse = " + "))
form <- as.formula(formula_txt)

cat("\nFitting R-axis GAM with pwSEM-aligned structure...\n")
cat(sprintf("  Total terms: %d\n", length(formula_terms)))
cat(sprintf("  Tensors: %d\n", length(tensor_terms)))
cat(sprintf("  Random-effect smooths: %d\n", length(random_terms)))

model <- gam(form, data = data, method = "ML")
sm <- summary(model)

cat("\n=== Model Summary ===\n")
print(sm)

aic <- AIC(model)
aicc <- AICc(model)
adj_r2 <- sm$r.sq
dev_expl <- sm$dev.expl
n_params <- sum(model$edf)

cat("\n=== In-sample Performance ===\n")
cat(sprintf("Adjusted R² = %.3f\n", adj_r2))
cat(sprintf("Deviance explained = %.1f%%\n", dev_expl * 100))
cat(sprintf("AIC = %.2f | AICc = %.2f | Effective params = %.1f\n", aic, aicc, n_params))

assign_strata <- function(y, K) {
  qs <- quantile(y, probs = seq(0, 1, length.out = K + 1), na.rm = TRUE, type = 7)
  qs[1] <- -Inf; qs[length(qs)] <- Inf
  groups <- cut(y, breaks = unique(qs), include.lowest = TRUE, labels = FALSE)
  fold_assign <- integer(length(y))
  for (grp in unique(groups)) {
    idx <- which(groups == grp)
    if (!length(idx)) next
    fold_assign[idx] <- sample(rep(seq_len(K), length.out = length(idx)))
  }
  fold_assign
}

y_vals <- data[[resp]]
repeats <- as.numeric(Sys.getenv("CV_REPEATS", "5"))
folds <- as.numeric(Sys.getenv("CV_FOLDS", "10"))
cv_scores <- numeric(0)
rmse_scores <- numeric(0)

cat(sprintf("\n=== Cross-Validation (%d repeats × %d folds) ===\n", repeats, folds))

for (r in seq_len(repeats)) {
  set.seed(123 + r)
  fold_assign <- assign_strata(y_vals, folds)
  for (k in seq_len(folds)) {
    test_idx <- which(fold_assign == k)
    train_idx <- setdiff(seq_len(nrow(data)), test_idx)
    if (length(test_idx) < 5 || length(train_idx) < 20) next

    train <- data[train_idx, , drop = FALSE]
    test <- data[test_idx, , drop = FALSE]

    if ("Family" %in% names(data)) {
      train$Family <- factor(train$Family, levels = levels(data$Family))
      test$Family <- factor(test$Family, levels = levels(data$Family))
    }
    if ("is_woody" %in% names(data)) {
      train$is_woody <- factor(train$is_woody, levels = levels(data$is_woody))
      test$is_woody <- factor(test$is_woody, levels = levels(data$is_woody))
    }

    fit <- try(gam(form, data = train, method = "ML"), silent = TRUE)
    if (inherits(fit, "try-error")) {
      cat(sprintf("  Warning: failed to fit fold %d-%d (%s)\n", r, k, fit))
      next
    }

    req_cols <- intersect(names(fit$var.summary), names(test))
    comp_idx <- if (length(req_cols)) complete.cases(test[, req_cols, drop = FALSE]) else rep(TRUE, nrow(test))
    if (sum(comp_idx) < 5) next
    test_comp <- test[comp_idx, , drop = FALSE]

    preds <- predict(fit, newdata = test_comp, allow.new.levels = TRUE)
    if (anyNA(preds)) {
      preds_no_re <- predict(fit, newdata = test_comp, allow.new.levels = TRUE, exclude = c('s(p_phylo_R)'))
      preds[is.na(preds)] <- preds_no_re[is.na(preds)]
    }
    residuals <- test_comp[[resp]] - preds
    ss_res <- sum(residuals^2)
    ss_tot <- sum((test_comp[[resp]] - mean(test_comp[[resp]]))^2)
    if (ss_tot <= 1e-8) next
    r2 <- 1 - ss_res/ss_tot
    rmse <- sqrt(mean(residuals^2))

    if (is.finite(r2)) cv_scores <- c(cv_scores, r2)
    if (is.finite(rmse)) rmse_scores <- c(rmse_scores, rmse)
  }
}

cat("\n=== Cross-Validation Results ===\n")
cat(sprintf("CV R² = %.3f ± %.3f (n=%d)\n", mean(cv_scores), sd(cv_scores), length(cv_scores)))
cat(sprintf("CV RMSE = %.3f ± %.3f\n", mean(rmse_scores), sd(rmse_scores)))

cat("\n=== Benchmark Comparison ===\n")
cat("GAM (previous full features): R² = 0.230 ± 0.137\n")
cat("pwSEM baseline: 0.166 ± 0.092\n")
cat("pwSEM+phylo: 0.222 ± 0.077\n")
cat("XGBoost pk: 0.225 ± 0.070\n")
cat(sprintf("Current model: R² = %.3f ± %.3f\n", mean(cv_scores), sd(cv_scores)))

out_dir <- "results/aic_selection_R_structured"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

summary_df <- tibble(
  formula = formula_txt,
  AIC = aic,
  AICc = aicc,
  adj_r2 = adj_r2,
  dev_explained = dev_expl,
  n_params = n_params,
  cv_mean = mean(cv_scores),
  cv_sd = sd(cv_scores),
  rmse_mean = mean(rmse_scores),
  rmse_sd = sd(rmse_scores),
  n_folds = length(cv_scores)
)
write_csv(summary_df, file.path(out_dir, "summary.csv"))

coef_df <- tibble(term = names(coef(model)), coefficient = as.numeric(coef(model)))
write_csv(coef_df, file.path(out_dir, "coefficients.csv"))
saveRDS(model, file.path(out_dir, "best_model.rds"))

maybe_run_nested_cv(
  axis_letter = "R",
  base_data = data,
  formula_obj = formula(model),
  is_gam = TRUE,
  target_col = target_col,
  species_names = species_labels,
  species_slugs = species_slugs,
  family_vec = family_vec,
  output_dir = out_dir
)

cat(sprintf("\nResults saved to %s/\n", out_dir))
cat("Done.\n")
