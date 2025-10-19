#!/usr/bin/env Rscript

# Pure AIC Selection for T Axis with Enhanced Climate Features
# No correlation clustering - let AIC decide based on predictive performance

library(tidyverse)
library(mgcv)
library(MuMIn)
library(nlme)
library(jsonlite)

script_args <- commandArgs(trailingOnly = FALSE)
script_file_arg <- sub("^--file=", "", grep("^--file=", script_args, value = TRUE))
if (length(script_file_arg)) {
  script_dir <- dirname(normalizePath(script_file_arg[1]))
} else {
  script_dir <- getwd()
}
source(file.path(script_dir, "nested_gam_cv_utils.R"))

set.seed(123)

# Load enhanced data with climate features
cat("Loading enhanced model data with climate features...\n")
data <- read.csv("artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv",
                 check.names = FALSE, stringsAsFactors = FALSE)

# Filter to T axis data
target_col <- "EIVEres-T"
target_response <- gsub("[^A-Za-z0-9_]", "_", target_col)

# First check if column exists
if (!(target_col %in% names(data))) {
  stop(sprintf("Target column %s not found in data", target_col))
}

# Filter for non-NA target values
data <- data[!is.na(data[[target_col]]), ]

if (!(target_response %in% names(data))) {
  data[[target_response]] <- data[[target_col]]
}

cat(sprintf("Working with %d complete cases for T axis\n", nrow(data)))

# Identify available predictors
trait_vars <- c("logH", "logSM", "logLA", "logSSD", "LES_core", "SIZE",
                "Nmass (mg/g)", "LMA (g/m2)", "LDMC (g/g)")

climate_vars <- c("mat_mean", "mat_sd", "mat_q05", "mat_q95",
                  "temp_seasonality", "temp_range", "tmax_mean",
                  "precip_mean", "precip_cv", "precip_seasonality",
                  "precip_coldest_q", "precip_driest_q", "precip_warmest_q",
                  "ai_mean", "ai_amp", "ai_cv_month", "ai_month_min",
                  "drought_min", "drought_max")

interaction_vars <- c("lma_precip", "height_temp", "size_temp",
                     "size_precip", "height_ssd", "les_drought",
                     "les_seasonality", "size_drought")

phylo_var <- "p_phylo_T"

# Check which variables exist
available_traits <- trait_vars[trait_vars %in% names(data)]
available_climate <- climate_vars[climate_vars %in% names(data)]
available_interactions <- interaction_vars[interaction_vars %in% names(data)]
has_phylo <- phylo_var %in% names(data)

cat("\nAvailable predictors:\n")
cat(sprintf("  Traits: %d/%d\n", length(available_traits), length(trait_vars)))
cat(sprintf("  Climate: %d/%d\n", length(available_climate), length(climate_vars)))
cat(sprintf("  Interactions: %d/%d\n", length(available_interactions), length(interaction_vars)))
cat(sprintf("  Phylogeny: %s\n", ifelse(has_phylo, "Yes", "No")))

species_vector <- if ("species_key" %in% names(data)) data$species_key else data$wfo_accepted_name
species_slugs <- slugify(species_vector)
species_slugs[!nzchar(species_slugs)] <- paste0("species_", seq_along(species_slugs))[!nzchar(species_slugs)]
species_labels <- if ("wfo_accepted_name" %in% names(data)) data$wfo_accepted_name else species_vector
family_vec <- if ("Family" %in% names(data)) data$Family else rep(NA_character_, nrow(data))

if (!"species_slug" %in% names(data)) {
  data$species_slug <- species_slugs
}

# Helper utilities ---------------------------------------------------------

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
  "mat_mean", "mat_q05", "mat_q95",
  "temp_seasonality", "precip_seasonality", "precip_cv", "tmax_mean"
)

stage1_extra_climate <- c("precip_mean", "drought_min", "ai_amp", "ai_cv_month")

stage1_interactions <- c("lma_precip", "height_temp", "size_temp", "size_precip", "height_ssd")

composite_interactions <- c("SIZE:mat_mean", "SIZE:precip_mean", "LES_core:temp_seasonality", "LES_core:drought_min")

# Define candidate models for AIC selection
# Start with different combinations of complexity

cat("\n=== Building Candidate Model Set ===\n")

# Helper function to create formula
make_formula <- function(response, fixed_terms, smooth_terms = NULL, linear_terms = NULL) {
  # Properly quote response if it contains special characters
  if (grepl("-", response)) {
    response <- paste0("`", response, "`")
  }
  formula_str <- paste(response, "~", paste(fixed_terms, collapse = " + "))

  if (!is.null(smooth_terms) && length(smooth_terms) > 0) {
    smooth_str <- paste0("s(", smooth_terms, ", k=5)", collapse = " + ")
    formula_str <- paste(formula_str, smooth_str, sep = " + ")
  }

  if (!is.null(linear_terms) && length(linear_terms) > 0) {
    linear_str <- paste(linear_terms, collapse = " + ")
    formula_str <- paste(formula_str, linear_str, sep = " + ")
  }

  as.formula(formula_str)
}

# Define model candidates based on Stage 1 signal
model_candidates <- list()

base_terms <- available_terms(c("LES_core", "logH", "logSM", "logLA"))
core_climate_terms <- available_terms(stage1_core_climate)
extra_climate_terms <- available_terms(stage1_extra_climate)
interaction_columns <- available_terms(stage1_interactions)
composite_terms <- Filter(interaction_available, composite_interactions)

model_candidates[["traits_only"]] <- make_formula(
  target_response,
  fixed_terms = base_terms
)

if (has_phylo) {
  model_candidates[["traits_phylo"]] <- make_formula(
    target_response,
    fixed_terms = base_terms,
    linear_terms = phylo_var
  )
}

if (length(core_climate_terms) >= 2) {
  model_candidates[["traits_stage1_climate"]] <- make_formula(
    target_response,
    fixed_terms = base_terms,
    linear_terms = core_climate_terms
  )

  if (has_phylo) {
    model_candidates[["traits_stage1_climate_phylo"]] <- make_formula(
      target_response,
      fixed_terms = base_terms,
      linear_terms = c(core_climate_terms, phylo_var)
    )
  }
}

stage1_full_linear_terms <- unique(c(core_climate_terms, extra_climate_terms, interaction_columns, composite_terms))
if (length(stage1_full_linear_terms) > 0) {
  model_candidates[["stage1_full_linear"]] <- make_formula(
    target_response,
    fixed_terms = base_terms,
    linear_terms = stage1_full_linear_terms
  )

  if (has_phylo) {
    model_candidates[["stage1_full_linear_phylo"]] <- make_formula(
      target_response,
      fixed_terms = base_terms,
      linear_terms = c(stage1_full_linear_terms, phylo_var)
    )
  }
}

# GAM candidates mirroring Stage 1 climate structure
smooth_candidates <- core_climate_terms
if (length(smooth_candidates) >= 2) {
  model_candidates[["stage1_core_gam"]] <- make_formula(
    target_response,
    fixed_terms = base_terms,
    smooth_terms = smooth_candidates
  )

  if (has_phylo) {
    model_candidates[["stage1_core_phylo_gam"]] <- make_formula(
      target_response,
      fixed_terms = base_terms,
      smooth_terms = smooth_candidates,
      linear_terms = phylo_var
    )
  }
}

extended_smooths <- unique(c(core_climate_terms, extra_climate_terms))
if (length(extended_smooths) >= 3) {
  model_candidates[["stage1_extended_gam"]] <- make_formula(
    target_response,
    fixed_terms = base_terms,
    smooth_terms = extended_smooths
  )

  if (has_phylo) {
    model_candidates[["stage1_extended_phylo_gam"]] <- make_formula(
      target_response,
      fixed_terms = base_terms,
      smooth_terms = extended_smooths,
      linear_terms = phylo_var
    )
  }
}

cat(sprintf("\nTotal candidate models: %d\n", length(model_candidates)))

# Fit all models and compute AIC
cat("\n=== Fitting Models and Computing AIC ===\n")

model_results <- list()

for (model_name in names(model_candidates)) {
  cat(sprintf("\nFitting %s...\n", model_name))

  tryCatch({
    # Determine model type based on formula
    formula_str <- as.character(model_candidates[[model_name]])[3]

    if (grepl("s\\(", formula_str)) {
      # GAM model fitted with ML for AIC comparability
      model <- gam(model_candidates[[model_name]],
                   data = data,
                   method = "ML")
    } else {
      # Linear model
      model <- lm(model_candidates[[model_name]],
                  data = data)
    }

    n_params <- if (inherits(model, "gam")) sum(model$edf) else length(coef(model))

    # Store results
    model_results[[model_name]] <- list(
      model = model,
      formula = model_candidates[[model_name]],
      AIC = AIC(model),
      AICc = AICc(model),
      R2 = summary(model)$r.sq,
      n_params = n_params
    )

    cat(sprintf("  AICc = %.2f, R² = %.3f, params = %.1f\n",
                model_results[[model_name]]$AICc,
                model_results[[model_name]]$R2,
                model_results[[model_name]]$n_params))

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

# Rank models by AICc
cat("\n=== Model Ranking by AICc ===\n")

# Extract AICc values
aic_values <- sapply(model_results, function(x) x$AICc)
aic_table <- data.frame(
  Model = names(model_results),
  AICc = aic_values,
  AIC = sapply(model_results, function(x) x$AIC),
  R2 = sapply(model_results, function(x) x$R2),
  n_params = sapply(model_results, function(x) x$n_params),
  stringsAsFactors = FALSE
)

# Filter for finite AICc values and sort
aic_table <- aic_table[is.finite(aic_table$AICc), ]

if (nrow(aic_table) == 0) {
  cat("\nERROR: No models converged successfully. Check data and formulas.\n")
  stop("No valid models to rank")
}

aic_table <- aic_table[order(aic_table$AICc), ]

# Calculate delta AICc and weights
aic_table$delta_AICc <- aic_table$AICc - min(aic_table$AICc)
aic_table$weight <- exp(-0.5 * aic_table$delta_AICc)
aic_table$weight <- aic_table$weight / sum(aic_table$weight)

# Display results
print(aic_table, digits = 3)

# Best model details
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

# Show model summary
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

# Models within 2 AICc units (essentially equivalent)
cat("\n=== Models within ΔAICc < 2 ===\n")
equivalent_models <- aic_table[aic_table$delta_AICc < 2, ]
print(equivalent_models, digits = 3)

# Save results
output_dir <- "results/aic_selection_T"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Save AIC table
write.csv(aic_table,
          file.path(output_dir, "aic_ranking_table.csv"),
          row.names = FALSE)

# Save best model
saveRDS(best_model,
        file.path(output_dir, "best_model.rds"))

# Save all results
saveRDS(model_results,
        file.path(output_dir, "all_models.rds"))

cat(sprintf("\n\nResults saved to %s/\n", output_dir))

# Cross-validation of best model
cat("\n=== Cross-Validation of Best Model ===\n")

# Repeated stratified 10-fold CV (5 repeats)
set.seed(123)
repeats <- 5
folds <- 10
y_vals <- data[[target_col]]

assign_stratified_folds <- function(y, k) {
  qs <- stats::quantile(y, probs = seq(0, 1, length.out = k + 1), na.rm = TRUE, type = 7)
  qs[1] <- -Inf; qs[length(qs)] <- Inf
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
      gam(model_results[[best_model_name]]$formula,
          data = train_data,
          method = "ML")
    } else {
      lm(model_results[[best_model_name]]$formula,
         data = train_data)
    }

    predictions <- predict(cv_model, newdata = test_data)
    ss_res <- sum((test_data[[target_col]] - predictions)^2, na.rm = TRUE)
    ss_tot <- sum((test_data[[target_col]] - mean(test_data[[target_col]]))^2, na.rm = TRUE)
    cv_scores <- c(cv_scores, 1 - (ss_res / ss_tot))
  }
}

cv_scores <- cv_scores[is.finite(cv_scores)]
cv_mean <- if (length(cv_scores)) mean(cv_scores) else NA_real_
cv_sd <- if (length(cv_scores)) sd(cv_scores) else NA_real_

if (length(cv_scores) == 0) {
  cat("\n[warn] Cross-validation produced no valid folds; check data split logic.\n")
} else {
  cat(sprintf("\n5×10-fold stratified CV R²: %.3f ± %.3f\n",
              cv_mean, cv_sd))
}

# Compare with previous results
cat("\n=== Performance Comparison ===\n")
cat("Method                     | R² (CV)        | Notes\n")
cat("---------------------------|----------------|------------------\n")
cat(sprintf("AIC Best Model             | %.3f ± %.3f | %s\n",
            cv_mean, cv_sd, best_model_name))
cat("pwSEM Enhanced (previous)  | 0.546 ± 0.085  | With climate features\n")
cat("pwSEM Original            | 0.543 ± 0.100  | Without climate\n")
cat("XGBoost (Stage 1)         | 0.590 ± 0.033  | Black-box baseline\n")

# Deployment-style CV (optional)
maybe_run_nested_cv(
  axis_letter = "T",
  base_data = data,
  formula_obj = model_results[[best_model_name]]$formula,
  is_gam = inherits(best_model, "gam"),
  target_col = target_col,
  species_names = species_labels,
  species_slugs = species_slugs,
  family_vec = family_vec,
  output_dir = output_dir
)
