#!/usr/bin/env Rscript
# Exact replication of Shipley et al. (2017) Table 2 models using ordinal::clm

suppressPackageStartupMessages({
  library(optparse)
  library(readr)
  library(stringr)
  library(tidyr)
  library(purrr)
  library(MASS)     # Load before dplyr
  library(dplyr)
  library(ordinal)
})

option_list <- list(
  make_option("--axis", type = "character", default = "L",
              help = "Target axis: L, M, or N"),
  make_option("--input", type = "character",
              default = "model_data/inputs/stage2_clm/clm_master_tier1_20251029.csv",
              help = "CLM master table"),
  make_option("--eive", type = "character",
              default = "data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv",
              help = "EIVE summary table"),
  make_option("--out_dir", type = "character",
              default = "artifacts/stage2_clm_shipley_exact_tier1_20251030",
              help = "Output directory"),
  make_option("--folds", type = "integer", default = 10,
              help = "Number of CV folds"),
  make_option("--seed", type = "integer", default = 42,
              help = "Random seed")
)

opt <- parse_args(OptionParser(option_list = option_list))

axis <- toupper(opt$axis)
stopifnot(axis %in% c("L", "M", "N"))
axis_col <- paste0("EIVEres-", axis)

message("[setup] Replicating Shipley et al. (2017) Table 2 for axis ", axis)
set.seed(opt$seed)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
clean_taxon <- function(x) {
  x %>%
    str_replace(" ×", " x") %>%
    str_trim()
}

ordinal_response <- function(x) {
  ordered(round(x) + 1L, levels = 0:10 + 1L)
}

# Get Shipley Table 2 formulas
# Based on "Simplified Model without Interactions" and "Best Model Using AIC"
get_shipley_formulas <- function(axis) {
  if (axis == "N") {
    # Nutrients: Table 2 shows Simplified and Best with 2-way interactions
    list(
      simplified = "axis_y ~ plant_form * (logLA + logLDMC + logSLA + logSM)",
      best = "axis_y ~ plant_form * (logLA + logLDMC + logSLA + logSM) +
                       (logLA + logLDMC + logSLA + logSM)^2"
    )
  } else if (axis == "L") {
    # Light: Table 2 shows up to 4-way interactions
    list(
      simplified = "axis_y ~ plant_form * (logLA + logLDMC + logSLA + logSM)",
      best = "axis_y ~ plant_form * (logLA + logLDMC + logSLA + logSM) +
                       (logLA + logLDMC + logSLA + logSM)^4"
    )
  } else if (axis == "M") {
    # Moisture: Table 2 shows up to 3-way interactions
    list(
      simplified = "axis_y ~ plant_form * (logLA + logLDMC + logSLA + logSM)",
      best = "axis_y ~ plant_form * (logLA + logLDMC + logSLA + logSM) +
                       (logLA + logLDMC + logSLA + logSM)^3"
    )
  }
}

fit_clm_safe <- function(df, formula_str, weights_col) {
  tryCatch({
    clm(
      formula = as.formula(formula_str),
      data = df,
      link = "logit",
      weights = df[[weights_col]]
    )
  }, error = function(e) {
    message("[warn] Model failed: ", e$message)
    return(NULL)
  })
}

predict_expected <- function(fit, newdata) {
  tryCatch({
    # Get predicted probabilities
    pred_result <- predict(fit, newdata = newdata, type = "prob")
    probs <- pred_result$fit

    # Get class levels (column names of probability matrix)
    if (!is.null(colnames(probs))) {
      classes <- as.numeric(colnames(probs)) - 1
    } else {
      classes <- as.numeric(levels(fit$model$axis_y)) - 1
    }

    # Calculate expected value: E[Y] = sum(class * prob)
    if (is.matrix(probs)) {
      as.vector(probs %*% classes)
    } else {
      sum(probs * classes)
    }
  }, error = function(e) {
    message("[warn] Prediction failed: ", e$message)
    return(NULL)
  })
}

stratified_partition <- function(y_factor, k) {
  n <- length(y_factor)
  assignments <- vector("list", k)
  meta <- tibble()
  idx_all <- seq_len(n)

  fold_assign <- integer(n)
  for (lvl in levels(y_factor)) {
    level_idx <- idx_all[y_factor == lvl]
    if (!length(level_idx)) next
    fold_seq <- sample(rep(seq_len(k), length.out = length(level_idx)))
    fold_assign[y_factor == lvl] <- fold_seq
  }

  for (fold in seq_len(k)) {
    test_idx <- which(fold_assign == fold)
    assignments[[fold]] <- test_idx
    meta <- bind_rows(meta, tibble(
      fold_id = fold,
      test_n = length(test_idx)
    ))
  }

  list(assignments = assignments, meta = meta)
}

# ---------------------------------------------------------------------------
# Load and prepare data
# ---------------------------------------------------------------------------
if (!file.exists(opt$input)) stop("Input dataset not found: ", opt$input)
if (!file.exists(opt$eive)) stop("EIVE table not found: ", opt$eive)

stage2 <- read_csv(opt$input, show_col_types = FALSE)
eive_table <- read_csv(opt$eive, show_col_types = FALSE)

stage2 <- stage2 %>% mutate(clean_name = clean_taxon(wfo_scientific_name))
eive_table <- eive_table %>% mutate(clean_name = clean_taxon(TaxonConcept))

if (!(axis_col %in% names(stage2))) stop("Target column missing: ", axis_col)

# Calculate log-transformed traits
stage2 <- stage2 %>%
  mutate(
    logLA = log(`Leaf area (mm2)`),
    logLDMC = log(LDMC),
    logSLA = log(1 / LMA),
    logSM = log(`Diaspore mass (mg)`)
  )

axis_vector <- stage2[[axis_col]]

# Filter to complete cases
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

# Get EIVE weights
eive_joined <- stage2 %>%
  left_join(eive_table %>% dplyr::select(clean_name, matches("\\.n$")),
            by = "clean_name")

weight_col <- paste0(axis, ".n")
if (!(weight_col %in% names(eive_joined))) {
  message("[warn] EIVE weight column ", weight_col, " not found; using uniform weights")
  eive_joined[[weight_col]] <- 1.0
} else {
  eive_joined[[weight_col]] <- ifelse(
    is.na(eive_joined[[weight_col]]) | eive_joined[[weight_col]] <= 0,
    1.0,
    eive_joined[[weight_col]]
  )
}

# ---------------------------------------------------------------------------
# Prepare modeling data
# ---------------------------------------------------------------------------
axis_response <- ordinal_response(axis_vector)

base_df <- eive_joined %>%
  mutate(
    axis_y = axis_response,
    weight = .data[[weight_col]]
  )

# Get Shipley formulas
formulas <- get_shipley_formulas(axis)

# ---------------------------------------------------------------------------
# Fit both models on full data to get AIC
# ---------------------------------------------------------------------------
message("\n[model_comparison] Fitting Shipley models on full dataset...")

model_comparison <- tibble()

for (model_name in names(formulas)) {
  formula_str <- formulas[[model_name]]
  message(sprintf("  Fitting %s model...", model_name))

  fit <- fit_clm_safe(base_df, formula_str, weights_col = "weight")

  if (!is.null(fit)) {
    aic_val <- AIC(fit)
    n_params <- length(coef(fit))

    model_comparison <- bind_rows(model_comparison, tibble(
      model = model_name,
      aic = aic_val,
      n_params = n_params
    ))

    message(sprintf("    AIC = %.2f, n_params = %d", aic_val, n_params))
  }
}

if (nrow(model_comparison) == 0) {
  stop("Both models failed to fit")
}

# Use simplified model for CV (more stable)
# Note: Shipley reports both; we prioritize stability
cv_formula <- formulas$simplified
message(sprintf("\n[cv] Using simplified model for CV (more stable)"))

# ---------------------------------------------------------------------------
# Cross-validation
# ---------------------------------------------------------------------------
cv_folds <- stratified_partition(axis_response, opt$folds)
assignments <- cv_folds$assignments
meta <- cv_folds$meta

results <- vector("list", length(assignments))
coef_records <- vector("list", length(assignments))

message(sprintf("[cv] Running %d-fold CV", opt$folds))

for (i in seq_along(assignments)) {
  test_idx <- assignments[[i]]
  train_idx <- setdiff(seq_len(nrow(base_df)), test_idx)

  train_df <- base_df[train_idx, ]
  test_df <- base_df[test_idx, ]

  # Fit model
  fit <- fit_clm_safe(train_df, cv_formula, weights_col = "weight")

  if (is.null(fit)) {
    message(sprintf("[cv] Fold %d failed to fit", i))
    next
  }

  # Predictions
  train_pred <- predict_expected(fit, train_df)
  test_pred <- predict_expected(fit, test_df)

  if (is.null(train_pred) || is.null(test_pred)) {
    message(sprintf("[cv] Fold %d prediction failed", i))
    next
  }

  # Extract true values
  train_y <- as.numeric(train_df$axis_y) - 1
  test_y <- as.numeric(test_df$axis_y) - 1

  # Metrics
  train_resid <- train_y - train_pred
  test_resid <- test_y - test_pred

  train_ss_res <- sum(train_resid^2)
  train_ss_tot <- sum((train_y - mean(train_y))^2)
  train_r2 <- 1 - train_ss_res / train_ss_tot

  test_ss_res <- sum(test_resid^2)
  test_ss_tot <- sum((test_y - mean(test_y))^2)
  test_r2 <- 1 - test_ss_res / test_ss_tot

  train_mae <- mean(abs(train_resid))
  test_mae <- mean(abs(test_resid))

  train_rmse <- sqrt(mean(train_resid^2))
  test_rmse <- sqrt(mean(test_resid^2))

  results[[i]] <- tibble(
    fold_id = i,
    train_r2 = train_r2,
    test_r2 = test_r2,
    train_mae = train_mae,
    test_mae = test_mae,
    train_rmse = train_rmse,
    test_rmse = test_rmse,
    train_n = length(train_idx),
    test_n = length(test_idx)
  )

  # Extract coefficients
  coefs <- coef(fit)
  coef_records[[i]] <- tibble(
    fold_id = i,
    term = names(coefs),
    estimate = as.numeric(coefs)
  )

  if (i %% 5 == 0) {
    message(sprintf("[cv] Completed fold %d/%d (test R² = %.3f)",
                    i, length(assignments), test_r2))
  }
}

# ---------------------------------------------------------------------------
# Aggregate results
# ---------------------------------------------------------------------------
results_df <- bind_rows(results) %>%
  left_join(meta, by = "fold_id")

coef_df <- bind_rows(coef_records)

# Summary statistics
summary_stats <- results_df %>%
  summarise(
    mean_train_r2 = mean(train_r2, na.rm = TRUE),
    sd_train_r2 = sd(train_r2, na.rm = TRUE),
    mean_test_r2 = mean(test_r2, na.rm = TRUE),
    sd_test_r2 = sd(test_r2, na.rm = TRUE),
    mean_train_mae = mean(train_mae, na.rm = TRUE),
    sd_train_mae = sd(train_mae, na.rm = TRUE),
    mean_test_mae = mean(test_mae, na.rm = TRUE),
    sd_test_mae = sd(test_mae, na.rm = TRUE),
    mean_train_rmse = mean(train_rmse, na.rm = TRUE),
    sd_train_rmse = sd(train_rmse, na.rm = TRUE),
    mean_test_rmse = mean(test_rmse, na.rm = TRUE),
    sd_test_rmse = sd(test_rmse, na.rm = TRUE)
  )

message("\n[results] Cross-validation summary:")
message(sprintf("  Train R²: %.3f ± %.3f", summary_stats$mean_train_r2, summary_stats$sd_train_r2))
message(sprintf("  Test R²:  %.3f ± %.3f", summary_stats$mean_test_r2, summary_stats$sd_test_r2))
message(sprintf("  Test MAE: %.3f ± %.3f", summary_stats$mean_test_mae, summary_stats$sd_test_mae))
message(sprintf("  Test RMSE: %.3f ± %.3f", summary_stats$mean_test_rmse, summary_stats$sd_test_rmse))

# ---------------------------------------------------------------------------
# Save outputs
# ---------------------------------------------------------------------------
out_dir <- file.path(opt$out_dir, axis)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

write_csv(results_df, file.path(out_dir, "cv_results.csv"))
write_csv(coef_df, file.path(out_dir, "coefficients.csv"))
write_csv(summary_stats, file.path(out_dir, "summary.csv"))
write_csv(model_comparison, file.path(out_dir, "model_comparison.csv"))

# Save formula info
formula_info <- tibble(
  model = names(formulas),
  formula = as.character(formulas)
)
write_csv(formula_info, file.path(out_dir, "formulas.csv"))

message(sprintf("\n[output] Results saved to: %s", out_dir))
message("[clm] Completed successfully")
