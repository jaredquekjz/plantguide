#!/usr/bin/env Rscript

# Pure AIC Selection for T Axis with Enhanced Climate Features
# No correlation clustering - let AIC decide based on predictive performance

library(tidyverse)
library(mgcv)
library(MuMIn)
library(nlme)
library(jsonlite)

slugify <- function(x) {
  x <- tolower(as.character(x))
  x <- gsub("[^0-9a-z]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  x[is.na(x)] <- ""
  x
}

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

load_occurrence_centroids <- function(path, species_slugs) {
  if (!file.exists(path)) {
    warning(sprintf("[warn] Occurrence file %s not found; spatial CV will fall back to single-species blocks", path))
    return(tibble(species_slug = character(), lat = numeric(), lon = numeric()))
  }

  occ <- suppressWarnings(read_csv(path, show_col_types = FALSE, progress = FALSE))

  species_col <- intersect(c("species_clean", "species", "wfo_accepted_name"), names(occ))[1]
  lat_col <- intersect(c("decimalLatitude", "decimallatitude", "latitude"), names(occ))[1]
  lon_col <- intersect(c("decimalLongitude", "decimallongitude", "longitude"), names(occ))[1]

  if (is.na(species_col) || is.na(lat_col) || is.na(lon_col)) {
    warning("[warn] Occurrence table missing species/lat/lon columns; skipping spatial blocking")
    return(tibble(species_slug = character(), lat = numeric(), lon = numeric()))
  }

  occ <- occ %>%
    mutate(
      species_slug = slugify(.data[[species_col]])
    ) %>%
    filter(species_slug %in% species_slugs) %>%
    filter(is.finite(.data[[lat_col]]), is.finite(.data[[lon_col]]))

  centroids <- occ %>%
    group_by(species_slug) %>%
    summarise(
      lat = mean(.data[[lat_col]], na.rm = TRUE),
      lon = mean(.data[[lon_col]], na.rm = TRUE),
      .groups = "drop"
    ) %>%
    filter(is.finite(lat), is.finite(lon))

  centroids
}

compute_spatial_blocks <- function(centroids, block_km = 500) {
  if (nrow(centroids) == 0) return(character(0))

  R <- 6371.0
  lat_rad <- centroids$lat * pi / 180
  lon_rad <- centroids$lon * pi / 180
  x_km <- R * cos(lat_rad) * lon_rad
  y_km <- R * lat_rad

  block_x <- floor(x_km / block_km)
  block_y <- floor(y_km / block_km)
  block_id <- paste(block_x, block_y, sep = ":")
  names(block_id) <- centroids$species_slug
  block_id
}

bootstrap_summary <- function(y_true, y_pred, reps = 1000, seed = 123) {
  if (length(y_true) == 0 || reps <= 0) {
    return(list(
      r2_mean = NA_real_, r2_sd = NA_real_,
      rmse_mean = NA_real_, rmse_sd = NA_real_,
      effective_samples = 0L
    ))
  }

  set.seed(seed)
  idx_vec <- seq_along(y_true)
  r2_vals <- numeric(0)
  rmse_vals <- numeric(0)
  for (i in seq_len(reps)) {
    idx <- sample(idx_vec, replace = TRUE)
    yt <- y_true[idx]
    yp <- y_pred[idx]
    if (length(unique(yt)) < 2) next
    ss_res <- sum((yt - yp)^2)
    ss_tot <- sum((yt - mean(yt))^2)
    r2_vals <- c(r2_vals, 1 - ss_res / ss_tot)
    rmse_vals <- c(rmse_vals, sqrt(mean((yt - yp)^2)))
  }

  list(
    r2_mean = if (length(r2_vals)) mean(r2_vals) else NA_real_,
    r2_sd = if (length(r2_vals)) sd(r2_vals) else NA_real_,
    rmse_mean = if (length(rmse_vals)) mean(rmse_vals) else NA_real_,
    rmse_sd = if (length(rmse_vals)) sd(rmse_vals) else NA_real_,
    effective_samples = length(r2_vals)
  )
}

build_nested_folds <- function(strategy, species_slugs, spatial_blocks = NULL) {
  idx <- seq_along(species_slugs)
  if (strategy == "loso") {
    keys <- paste0("loso::", species_slugs)
  } else if (strategy == "spatial") {
    if (is.null(spatial_blocks) || !length(spatial_blocks)) {
      keys <- paste0("spatial::unmapped::", species_slugs)
    } else {
      block_ids <- spatial_blocks[species_slugs]
      block_ids[is.na(block_ids)] <- paste0("unmapped::", species_slugs[is.na(block_ids)])
      keys <- paste0("spatial::", block_ids)
    }
  } else {
    stop(sprintf("Unknown nested CV strategy '%s'", strategy))
  }
  split(idx, keys)
}

run_nested_cv <- function(strategy,
                          fold_map,
                          base_data,
                          formula_obj,
                          is_gam,
                          target_col,
                          species_names,
                          species_slugs,
                          families,
                          output_dir,
                          bootstrap_reps = 1000) {

  axis_letter <- "T"
  n_folds <- length(fold_map)
  if (n_folds == 0) {
    cat(sprintf("[warn] No folds generated for strategy %s; skipping\n", strategy))
    return(invisible(NULL))
  }

  cat(sprintf("\n=== Nested CV (%s) — %d folds ===\n", strategy, n_folds))

  all_true <- numeric(0)
  all_pred <- numeric(0)
  prediction_rows <- vector("list", n_folds)
  fold_rows <- vector("list", n_folds)

  start_time <- Sys.time()

  for (i in seq_along(fold_map)) {
    fold_name <- names(fold_map)[i]
    test_idx <- fold_map[[i]]
    train_idx <- setdiff(seq_len(nrow(base_data)), test_idx)
    if (length(test_idx) == 0 || length(train_idx) == 0) next

    fold_start <- Sys.time()

    train_data <- base_data[train_idx, , drop = FALSE]
    test_data <- base_data[test_idx, , drop = FALSE]

    factor_cols <- intersect(c("Family", "is_woody"), names(train_data))
    for (col in factor_cols) {
      train_data[[col]] <- factor(train_data[[col]])
      test_data[[col]] <- factor(test_data[[col]], levels = levels(train_data[[col]]))
    }

    fit <- tryCatch({
      if (is_gam) {
        gam(formula_obj, data = train_data, method = "ML")
      } else {
        lm(formula_obj, data = train_data)
      }
    }, error = function(e) {
      warning(sprintf("[warn] %s fold %s failed: %s", strategy, fold_name, e$message))
      NULL
    })

    if (is.null(fit)) next

    preds <- tryCatch({
      as.numeric(predict(fit, newdata = test_data))
    }, error = function(e) {
      warning(sprintf("[warn] Prediction failed for fold %s: %s", fold_name, e$message))
      rep(NA_real_, length(test_idx))
    })

    truth <- base_data[[target_col]][test_idx]
    residuals <- truth - preds

    all_true <- c(all_true, truth)
    all_pred <- c(all_pred, preds)

    fold_r2 <- if (length(unique(truth)) >= 2 && all(is.finite(residuals))) {
      ss_res <- sum((truth - preds)^2)
      ss_tot <- sum((truth - mean(truth))^2)
      if (is.finite(ss_tot) && ss_tot > 0) 1 - ss_res / ss_tot else NA_real_
    } else {
      NA_real_
    }
    fold_rmse <- sqrt(mean((truth - preds)^2, na.rm = TRUE))
    fold_mae <- mean(abs(truth - preds), na.rm = TRUE)

    prediction_rows[[i]] <- tibble(
      fold = fold_name,
      species = species_names[test_idx],
      species_slug = species_slugs[test_idx],
      family = if ("Family" %in% names(base_data)) families[test_idx] else NA_character_,
      y_true = truth,
      y_pred = preds,
      residual = residuals
    )

    fold_rows[[i]] <- tibble(
      fold = fold_name,
      n_test = length(test_idx),
      r2 = fold_r2,
      rmse = fold_rmse,
      mae = fold_mae,
      elapsed_sec = as.numeric(difftime(Sys.time(), fold_start, units = "secs"))
    )

    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    avg_per_fold <- elapsed / i
    eta_min <- (n_folds - i) * avg_per_fold / 60
    cat(sprintf("[cv] %s fold %d/%d done in %.1fs | fold R²=%s RMSE=%.3f | ETA ≈ %.1f min\n",
                strategy, i, n_folds,
                fold_rows[[i]]$elapsed_sec,
                ifelse(is.na(fold_r2), "NA", sprintf("%.3f", fold_r2)),
                fold_rmse,
                eta_min))
  }

  predictions_df <- bind_rows(prediction_rows)
  folds_df <- bind_rows(fold_rows)

  valid <- is.finite(all_true) & is.finite(all_pred)
  y_all <- all_true[valid]
  y_hat_all <- all_pred[valid]
  ss_res <- sum((y_all - y_hat_all)^2)
  ss_tot <- sum((y_all - mean(y_all))^2)
  overall_r2 <- if (length(y_all) > 0 && ss_tot > 0) 1 - ss_res / ss_tot else NA_real_
  overall_rmse <- if (length(y_all) > 0) sqrt(mean((y_all - y_hat_all)^2)) else NA_real_

  boot <- bootstrap_summary(y_all, y_hat_all, reps = bootstrap_reps, seed = 321)

  metrics <- list(
    strategy = strategy,
    outer_folds = n_folds,
    n_predictions = length(y_all),
    overall_r2 = overall_r2,
    overall_rmse = overall_rmse,
    bootstrap_r2_mean = boot$r2_mean,
    bootstrap_r2_sd = boot$r2_sd,
    bootstrap_rmse_mean = boot$rmse_mean,
    bootstrap_rmse_sd = boot$rmse_sd,
    bootstrap_effective_samples = boot$effective_samples,
    per_fold_rmse_mean = mean(folds_df$rmse, na.rm = TRUE),
    per_fold_rmse_sd = sd(folds_df$rmse, na.rm = TRUE),
    per_fold_mae_mean = mean(folds_df$mae, na.rm = TRUE),
    per_fold_mae_sd = sd(folds_df$mae, na.rm = TRUE),
    inner_folds = NA_integer_,
    param_grid_size = 1L
  )

  metrics_path <- file.path(output_dir, sprintf("gam_%s_cv_metrics_%s.json", axis_letter, strategy))
  preds_path <- file.path(output_dir, sprintf("gam_%s_cv_predictions_%s.csv", axis_letter, strategy))
  folds_path <- file.path(output_dir, sprintf("gam_%s_cv_folds_%s.csv", axis_letter, strategy))

  write_json(metrics, metrics_path, auto_unbox = TRUE, pretty = TRUE)
  if (nrow(predictions_df)) write_csv(predictions_df, preds_path)
  if (nrow(folds_df)) write_csv(folds_df, folds_path)

  cat(sprintf("[cv] %s overall R² = %s | bootstrap mean ± sd = %s ± %s\n",
              strategy,
              ifelse(is.na(overall_r2), "NA", sprintf("%.3f", overall_r2)),
              ifelse(is.na(boot$r2_mean), "NA", sprintf("%.3f", boot$r2_mean)),
              ifelse(is.na(boot$r2_sd), "NA", sprintf("%.3f", boot$r2_sd))))

  invisible(metrics)
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
enable_nested_cv <- tolower(Sys.getenv("NESTED_CV_ENABLE", "false")) %in% c("1", "true", "yes", "y")
if (enable_nested_cv) {
  nested_strategies_raw <- Sys.getenv("NESTED_CV_STRATEGIES", "loso,spatial")
  nested_strategies <- nested_strategies_raw %>% strsplit(",") %>% unlist() %>% stringr::str_trim() %>% tolower()
  nested_strategies <- unique(nested_strategies[nested_strategies != ""])
  if (!length(nested_strategies)) nested_strategies <- c("loso", "spatial")

  occurrence_csv <- Sys.getenv(
    "NESTED_CV_OCC_CSV",
    "data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv"
  )
  spatial_block_km <- suppressWarnings(as.numeric(Sys.getenv("NESTED_CV_BLOCK_KM", "500")))
  if (!is.finite(spatial_block_km) || spatial_block_km <= 0) spatial_block_km <- 500
  bootstrap_reps <- suppressWarnings(as.integer(Sys.getenv("NESTED_CV_BOOTSTRAP", "1000")))
  if (!is.finite(bootstrap_reps) || bootstrap_reps < 0) bootstrap_reps <- 1000

  spatial_blocks <- character(0)
  if ("spatial" %in% nested_strategies) {
    centroids <- load_occurrence_centroids(occurrence_csv, unique(species_slugs))
    spatial_blocks <- compute_spatial_blocks(centroids, block_km = spatial_block_km)
    if (!length(spatial_blocks)) {
      warning("[warn] Spatial blocking fell back to single-species folds; check occurrence coverage.")
    } else {
      cat(sprintf("[info] Spatial blocking produced %d tiles (%.0f km)\n",
                  length(unique(spatial_blocks)), spatial_block_km))
    }
  }

  best_formula <- model_results[[best_model_name]]$formula
  is_gam_best <- inherits(best_model, "gam")

  for (strategy in nested_strategies) {
    fold_map <- switch(
      strategy,
      "loso" = build_nested_folds("loso", species_slugs),
      "spatial" = build_nested_folds("spatial", species_slugs, spatial_blocks),
      {
        warning(sprintf("[warn] Unknown nested CV strategy '%s' — skipping", strategy))
        NULL
      }
    )

    if (is.null(fold_map)) next

    run_nested_cv(
      strategy = strategy,
      fold_map = fold_map,
      base_data = data,
      formula_obj = best_formula,
      is_gam = is_gam_best,
      target_col = target_col,
      species_names = species_labels,
      species_slugs = species_slugs,
      families = family_vec,
      output_dir = output_dir,
      bootstrap_reps = bootstrap_reps
    )
  }
} else {
  cat("\n[nested] Set NESTED_CV_ENABLE=true to run LOSO/spatial deployment CV.\n")
}
