#!/usr/bin/env Rscript

# Pure AIC Selection for M Axis with Stage-1 Predictors

library(tidyverse)
library(mgcv)
library(MuMIn)
library(nlme)

set.seed(123)

cat("Loading enhanced model data with climate features...\n")
data <- read.csv(
  "artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv",
  check.names = FALSE,
  stringsAsFactors = FALSE
)

target_col <- "EIVEres-M"
target_response <- gsub("[^A-Za-z0-9_]", "_", target_col)

if (!(target_col %in% names(data))) {
  stop(sprintf("Target column %s not found in data", target_col))
}

data <- data[!is.na(data[[target_col]]), ]

if (!(target_response %in% names(data))) {
  data[[target_response]] <- data[[target_col]]
}

cat(sprintf("Working with %d complete cases for M axis\n", nrow(data)))

# Candidate predictor pools derived from Stage-1 analysis --------------------

trait_vars <- c(
  "logLA", "logSM", "logH", "logSSD",
  "LES_core", "SIZE", "Nmass", "LMA", "LDMC"
)

climate_vars <- c(
  "precip_coldest_q", "precip_seasonality", "precip_mean", "precip_cv",
  "drought_min", "ai_roll3_min", "ai_amp", "ai_cv_month", "ai_month_min",
  "mat_mean", "temp_seasonality"
)

interaction_vars <- c(
  "lma_precip", "height_temp", "size_temp", "size_precip",
  "height_ssd", "les_drought", "les_seasonality", "lma_la", "wood_precip"
)

phylo_var <- "p_phylo_M"

available_terms <- function(cols) cols[cols %in% names(data)]

interaction_available <- function(term) {
  bits <- strsplit(term, ":", fixed = TRUE)[[1]]
  all(bits %in% names(data))
}

compute_vif <- function(model) {
  if (!inherits(model, "lm")) return(NULL)
  mm <- stats::model.matrix(model)
  if (ncol(mm) <= 1) return(NULL)
  mm <- mm[, colnames(mm) != "(Intercept)", drop = FALSE]
  vif_vals <- numeric(ncol(mm))
  names(vif_vals) <- colnames(mm)
  for (j in seq_len(ncol(mm))) {
    y_j <- mm[, j]
    x_j <- mm[, -j, drop = FALSE]
    if (ncol(x_j) == 0) {
      vif_vals[j] <- 1
    } else {
      sub_fit <- stats::lm(y_j ~ x_j)
      r2 <- summary(sub_fit)$r.squared
      vif_vals[j] <- if (is.finite(r2) && r2 < 1) 1 / (1 - r2) else Inf
    }
  }
  vif_vals
}

stage1_core_climate <- c(
  "precip_coldest_q", "drought_min", "precip_mean",
  "precip_seasonality", "mat_mean", "temp_seasonality", "ai_roll3_min"
)

stage1_extra_climate <- c("ai_amp", "ai_cv_month", "ai_month_min", "precip_cv")

stage1_interactions <- c(
  "lma_precip", "height_temp", "size_temp", "size_precip",
  "height_ssd", "les_drought", "les_seasonality", "lma_la", "wood_precip"
)

composite_interactions <- c(
  "SIZE:precip_mean", "SIZE:mat_mean",
  "LES_core:drought_min", "LES_core:temp_seasonality"
)

cat("\nAvailable predictors:\n")
available_traits <- available_terms(trait_vars)
available_climate <- available_terms(climate_vars)
available_interactions <- available_terms(interaction_vars)
has_phylo <- phylo_var %in% names(data)

cat(sprintf("  Traits: %d/%d\n", length(available_traits), length(trait_vars)))
cat(sprintf("  Climate: %d/%d\n", length(available_climate), length(climate_vars)))
cat(sprintf("  Interactions: %d/%d\n", length(available_interactions), length(interaction_vars)))
cat(sprintf("  Phylogeny: %s\n", ifelse(has_phylo, "Yes", "No")))

make_formula <- function(response, fixed_terms, smooth_terms = NULL, linear_terms = NULL) {
  if (grepl("-", response)) {
    response <- paste0("`", response, "`")
  }

  safe_term <- function(term) {
    if (grepl("[:() ]", term) && !grepl(":", term)) {
      return(paste0("`", term, "`"))
    }
    term
  }

  fixed_terms <- vapply(fixed_terms, safe_term, character(1))

  formula_str <- paste(response, "~", paste(fixed_terms, collapse = " + "))

  if (!is.null(smooth_terms) && length(smooth_terms) > 0) {
    smooth_terms_safe <- vapply(smooth_terms, safe_term, character(1))
    smooth_str <- paste0("s(", smooth_terms_safe, ", k=5)", collapse = " + ")
    formula_str <- paste(formula_str, smooth_str, sep = " + ")
  }

  if (!is.null(linear_terms) && length(linear_terms) > 0) {
    linear_terms_safe <- vapply(linear_terms, safe_term, character(1))
    formula_str <- paste(formula_str, paste(linear_terms_safe, collapse = " + "), sep = " + ")
  }

  as.formula(formula_str)
}

model_candidates <- list()

base_terms <- available_terms(c("logLA", "logSM", "logH", "logSSD", "LES_core", "SIZE"))
core_climate_terms <- available_terms(stage1_core_climate)
extra_climate_terms <- available_terms(stage1_extra_climate)
interaction_columns <- available_terms(stage1_interactions)
composite_terms <- Filter(interaction_available, composite_interactions)

model_candidates[["traits_only"]] <- make_formula(target_response, base_terms)

if (has_phylo) {
  model_candidates[["traits_phylo"]] <- make_formula(target_response, base_terms, linear_terms = phylo_var)
}

if (length(core_climate_terms) >= 2) {
  model_candidates[["traits_stage1_climate"]] <- make_formula(
    target_response,
    base_terms,
    linear_terms = core_climate_terms
  )

  if (has_phylo) {
    model_candidates[["traits_stage1_climate_phylo"]] <- make_formula(
      target_response,
      base_terms,
      linear_terms = c(core_climate_terms, phylo_var)
    )
  }
}

stage1_full_linear_terms <- unique(c(core_climate_terms, extra_climate_terms, interaction_columns, composite_terms))

if (length(stage1_full_linear_terms) > 0) {
  model_candidates[["stage1_full_linear"]] <- make_formula(
    target_response,
    base_terms,
    linear_terms = stage1_full_linear_terms
  )

  if (has_phylo) {
    model_candidates[["stage1_full_linear_phylo"]] <- make_formula(
      target_response,
      base_terms,
      linear_terms = c(stage1_full_linear_terms, phylo_var)
    )
  }
}

smooth_candidates <- core_climate_terms
if (length(smooth_candidates) >= 2) {
  model_candidates[["stage1_core_gam"]] <- make_formula(
    target_response,
    base_terms,
    smooth_terms = smooth_candidates
  )

  if (has_phylo) {
    model_candidates[["stage1_core_phylo_gam"]] <- make_formula(
      target_response,
      base_terms,
      smooth_terms = smooth_candidates,
      linear_terms = phylo_var
    )
  }
}

extended_smooths <- unique(c(core_climate_terms, extra_climate_terms))
if (length(extended_smooths) >= 3) {
  model_candidates[["stage1_extended_gam"]] <- make_formula(
    target_response,
    base_terms,
    smooth_terms = extended_smooths
  )

  if (has_phylo) {
    model_candidates[["stage1_extended_phylo_gam"]] <- make_formula(
      target_response,
      base_terms,
      smooth_terms = extended_smooths,
      linear_terms = phylo_var
    )
  }
}

if (length(stage1_full_linear_terms) > 0 && length(smooth_candidates) >= 2) {
  model_candidates[["stage1_full_gam"]] <- make_formula(
    target_response,
    base_terms,
    smooth_terms = smooth_candidates,
    linear_terms = setdiff(stage1_full_linear_terms, smooth_candidates)
  )

  if (has_phylo) {
    model_candidates[["stage1_full_phylo_gam"]] <- make_formula(
      target_response,
      base_terms,
      smooth_terms = smooth_candidates,
      linear_terms = setdiff(c(stage1_full_linear_terms, phylo_var), smooth_candidates)
    )
  }
}

cat(sprintf("\nTotal candidate models: %d\n", length(model_candidates)))

cat("\n=== Fitting Models and Computing AIC ===\n")

model_results <- list()

for (model_name in names(model_candidates)) {
  cat(sprintf("\nFitting %s...\n", model_name))

  tryCatch({
    formula_str <- as.character(model_candidates[[model_name]])[3]

    if (grepl("s\\(", formula_str)) {
      model <- gam(model_candidates[[model_name]], data = data, method = "ML")
    } else {
      model <- lm(model_candidates[[model_name]], data = data)
    }

    n_params <- if (inherits(model, "gam")) sum(model$edf) else length(coef(model))

    model_results[[model_name]] <- list(
      model = model,
      formula = model_candidates[[model_name]],
      AIC = AIC(model),
      AICc = AICc(model),
      R2 = summary(model)$r.sq,
      n_params = n_params
    )

    cat(sprintf(
      "  AICc = %.2f, R² = %.3f, params = %.1f\n",
      model_results[[model_name]]$AICc,
      model_results[[model_name]]$R2,
      model_results[[model_name]]$n_params
    ))

  }, error = function(e) {
    cat(sprintf("  ERROR: %s\n", e$message))
    model_results[[model_name]] <- list(
      model = NULL,
      formula = model_candidates[[model_name]],
      AIC = Inf,
      AICc = Inf,
      R2 = NA,
      n_params = NA,
      error = e$message
    )
  })
}

cat("\n=== Model Ranking by AICc ===\n")

aic_table <- data.frame(
  Model = names(model_results),
  AICc = sapply(model_results, function(x) x$AICc),
  AIC = sapply(model_results, function(x) x$AIC),
  R2 = sapply(model_results, function(x) x$R2),
  n_params = sapply(model_results, function(x) x$n_params),
  stringsAsFactors = FALSE
)

aic_table <- aic_table[is.finite(aic_table$AICc), ]

if (nrow(aic_table) == 0) {
  stop("No models converged successfully")
}

aic_table <- aic_table[order(aic_table$AICc), ]
aic_table$delta_AICc <- aic_table$AICc - min(aic_table$AICc)
aic_table$weight <- exp(-0.5 * aic_table$delta_AICc)
aic_table$weight <- aic_table$weight / sum(aic_table$weight)

print(aic_table, digits = 3)

cat("\n=== Best Model Details ===\n")

best_model_name <- aic_table$Model[1]
best_model <- model_results[[best_model_name]]$model

cat(sprintf("\nBest model: %s\n", best_model_name))

best_formula_txt <- paste(deparse(model_results[[best_model_name]]$formula), collapse = " ")
if (target_response != target_col) {
  best_formula_txt <- gsub(target_response, paste0("`", target_col, "`"), best_formula_txt, fixed = TRUE)
}
cat(sprintf("Formula: %s\n", best_formula_txt))
cat(sprintf("AICc: %.2f\n", aic_table$AICc[1]))
cat(sprintf("R²: %.3f\n", aic_table$R2[1]))
cat(sprintf("Parameters: %.1f\n", aic_table$n_params[1]))

cat("\nModel Summary:\n")
print(summary(best_model))

if (inherits(best_model, "lm")) {
  vif_vals <- compute_vif(best_model)
  if (!is.null(vif_vals)) {
    cat("\nVariance Inflation Factors (VIF):\n")
    print(round(vif_vals, 2))
    high_vif <- vif_vals[vif_vals > 5]
    if (length(high_vif) > 0) {
      cat("[warn] VIF > 5 detected for:", paste(names(high_vif), collapse = ", "), "\n")
    }
  }
}

cat("\n=== Models within ΔAICc < 2 ===\n")
equivalent_models <- aic_table[aic_table$delta_AICc < 2, ]
print(equivalent_models, digits = 3)

output_dir <- "results/aic_selection_M"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

write.csv(aic_table, file.path(output_dir, "aic_ranking_table.csv"), row.names = FALSE)

saveRDS(best_model, file.path(output_dir, "best_model.rds"))

saveRDS(model_results, file.path(output_dir, "all_models.rds"))

cat(sprintf("\nResults saved to %s/\n", output_dir))

cat("\n=== Cross-Validation of Best Model ===\n")

set.seed(123)
repeats <- 5
folds <- 10
y_vals <- data[[target_col]]

assign_stratified_folds <- function(y, k) {
  qs <- stats::quantile(y, probs = seq(0, 1, length.out = k + 1), na.rm = TRUE, type = 7)
  qs[1] <- -Inf
  qs[length(qs)] <- Inf
  groups <- cut(y, breaks = unique(qs), include.lowest = TRUE, labels = FALSE)
  fold_assign <- integer(length(y))
  for (grp in sort(unique(groups))) {
    idx <- which(groups == grp)
    if (length(idx) == 0) next
    idx <- sample(idx)
    fold_assign[idx] <- rep(seq_len(k), length.out = length(idx))
  }
  fold_assign
}

cv_scores <- numeric(0)
cv_rmse <- numeric(0)

for (r in seq_len(repeats)) {
  set.seed(123 + r)
  fold_assign <- assign_stratified_folds(y_vals, folds)

  for (k in seq_len(folds)) {
    test_idx <- which(fold_assign == k)
    train_idx <- setdiff(seq_len(nrow(data)), test_idx)
    if (length(test_idx) < 5 || length(train_idx) < 20) next

    train_data <- data[train_idx, , drop = FALSE]
    test_data <- data[test_idx, , drop = FALSE]

    cv_model <- if (inherits(best_model, "gam")) {
      gam(model_results[[best_model_name]]$formula, data = train_data, method = "ML")
    } else {
      lm(model_results[[best_model_name]]$formula, data = train_data)
    }

    predictions <- predict(cv_model, newdata = test_data)
    residuals <- test_data[[target_col]] - predictions
    ss_res <- sum(residuals^2, na.rm = TRUE)
    ss_tot <- sum((test_data[[target_col]] - mean(test_data[[target_col]]))^2, na.rm = TRUE)
    cv_scores <- c(cv_scores, 1 - (ss_res / ss_tot))
    cv_rmse <- c(cv_rmse, sqrt(mean(residuals^2, na.rm = TRUE)))
  }
}

cv_scores <- cv_scores[is.finite(cv_scores)]
cv_rmse <- cv_rmse[is.finite(cv_rmse)]
cv_mean <- if (length(cv_scores)) mean(cv_scores) else NA_real_
cv_sd <- if (length(cv_scores)) sd(cv_scores) else NA_real_
rmse_mean <- if (length(cv_rmse)) mean(cv_rmse) else NA_real_
rmse_sd <- if (length(cv_rmse)) sd(cv_rmse) else NA_real_

if (length(cv_scores) == 0) {
  cat("\n[warn] Cross-validation produced no valid folds; check data split logic.\n")
} else {
  cat(sprintf("\n5x10-fold stratified CV R²: %.3f ± %.3f\n", cv_mean, cv_sd))
  cat(sprintf("5x10-fold stratified CV RMSE: %.3f ± %.3f\n", rmse_mean, rmse_sd))
}

cat("\n=== Performance Comparison ===\n")
cat("Method                     | R² (CV)        | Notes\n")
cat("---------------------------|----------------|------------------\n")
cat(sprintf("AIC Best Model             | %.3f ± %.3f | %s\n", cv_mean, cv_sd, best_model_name))
cat("pwSEM Enhanced (previous)  | 0.399 ± 0.082  | With climate features\n")
cat("pwSEM Original            | 0.366 ± 0.090  | Legacy baseline\n")
cat("XGBoost (Stage 1)         | 0.366 ± 0.086  | Black-box baseline\n")

print_cv <- data.frame(
  metric = c("cv_mean", "cv_sd", "rmse_mean", "rmse_sd"),
  value = c(cv_mean, cv_sd, rmse_mean, rmse_sd)
)

write.csv(
  print_cv,
  file.path(output_dir, "cv_metrics.csv"),
  row.names = FALSE
)

cat("\nDone.\n")
