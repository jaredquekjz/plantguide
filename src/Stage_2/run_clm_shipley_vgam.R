#!/usr/bin/env Rscript
# Shipley et al. (2017) Table 2 "Simplified Model" using VGAM (stable implementation)

suppressPackageStartupMessages({
  library(optparse)
  library(readr)
  library(dplyr)
  library(stringr)
  library(tidyr)
  library(purrr)
  library(VGAM)
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
              default = "artifacts/stage2_clm_shipley_vgam_tier1_20251030",
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

message("[setup] Running Shipley et al. (2017) 'Simplified Model' for axis ", axis)
message("        Formula: axis_y ~ plant_form * (logLA + logLDMC + logSLA + logSM)")
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

# Shipley Table 2 "Simplified Model without Interactions":
# plant_form interacts with all 4 traits (different slopes per plant type)
fit_clm <- function(df, weights_col) {
  formula_str <- "axis_y ~ plant_form * (logLA + logLDMC + logSLA + logSM)"

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

# Merge shrub into tree (only 3 shrubs - insufficient for interaction modeling)
stage2$plant_form <- as.character(stage2$plant_form)
stage2$plant_form[stage2$plant_form == "shrub"] <- "tree"
stage2$plant_form <- factor(stage2$plant_form,
                            levels = c("graminoid", "herb", "tree"))

message(sprintf("[data] %d species retained after filtering", nrow(stage2)))

# Get EIVE weights
eive_joined <- stage2 %>%
  left_join(eive_table %>% select(clean_name, matches("\\.n$")),
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

cv_folds <- stratified_partition(axis_response, opt$folds)
assignments <- cv_folds$assignments
meta <- cv_folds$meta

results <- vector("list", length(assignments))
coef_records <- vector("list", length(assignments))

message(sprintf("[cv] Running %d-fold CV", opt$folds))

# ---------------------------------------------------------------------------
# Cross-validation loop
# ---------------------------------------------------------------------------
for (i in seq_along(assignments)) {
  test_idx <- assignments[[i]]
  train_idx <- setdiff(seq_len(nrow(base_df)), test_idx)

  train_df <- base_df[train_idx, ]
  test_df <- base_df[test_idx, ]

  # Fit model
  fit <- fit_clm(train_df, weights_col = "weight")

  # Predictions
  train_pred <- predict_expected(fit, train_df)
  test_pred <- predict_expected(fit, test_df)

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

  # Calculate ordinal accuracy (within 1 and 2 ranks)
  train_acc_rank1 <- mean(abs(train_resid) <= 1.0) * 100
  train_acc_rank2 <- mean(abs(train_resid) <= 2.0) * 100
  test_acc_rank1 <- mean(abs(test_resid) <= 1.0) * 100
  test_acc_rank2 <- mean(abs(test_resid) <= 2.0) * 100

  results[[i]] <- tibble(
    fold_id = i,
    train_r2 = train_r2,
    test_r2 = test_r2,
    train_mae = train_mae,
    test_mae = test_mae,
    train_rmse = train_rmse,
    test_rmse = test_rmse,
    train_acc_rank1 = train_acc_rank1,
    train_acc_rank2 = train_acc_rank2,
    test_acc_rank1 = test_acc_rank1,
    test_acc_rank2 = test_acc_rank2,
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
    mean_train_r2 = mean(train_r2),
    sd_train_r2 = sd(train_r2),
    mean_test_r2 = mean(test_r2),
    sd_test_r2 = sd(test_r2),
    mean_train_mae = mean(train_mae),
    sd_train_mae = sd(train_mae),
    mean_test_mae = mean(test_mae),
    sd_test_mae = sd(test_mae),
    mean_train_rmse = mean(train_rmse),
    sd_train_rmse = sd(train_rmse),
    mean_test_rmse = mean(test_rmse),
    sd_test_rmse = sd(test_rmse),
    mean_train_acc_rank1 = mean(train_acc_rank1),
    sd_train_acc_rank1 = sd(train_acc_rank1),
    mean_test_acc_rank1 = mean(test_acc_rank1),
    sd_test_acc_rank1 = sd(test_acc_rank1),
    mean_train_acc_rank2 = mean(train_acc_rank2),
    sd_train_acc_rank2 = sd(train_acc_rank2),
    mean_test_acc_rank2 = mean(test_acc_rank2),
    sd_test_acc_rank2 = sd(test_acc_rank2)
  )

message("\n[results] Cross-validation summary:")
message(sprintf("  Train R²: %.3f ± %.3f", summary_stats$mean_train_r2, summary_stats$sd_train_r2))
message(sprintf("  Test R²:  %.3f ± %.3f", summary_stats$mean_test_r2, summary_stats$sd_test_r2))
message(sprintf("  Test MAE: %.3f ± %.3f", summary_stats$mean_test_mae, summary_stats$sd_test_mae))
message(sprintf("  Test RMSE: %.3f ± %.3f", summary_stats$mean_test_rmse, summary_stats$sd_test_rmse))
message(sprintf("  Test Acc±1: %.1f%% ± %.1f%%", summary_stats$mean_test_acc_rank1, summary_stats$sd_test_acc_rank1))
message(sprintf("  Test Acc±2: %.1f%% ± %.1f%%", summary_stats$mean_test_acc_rank2, summary_stats$sd_test_acc_rank2))

# ---------------------------------------------------------------------------
# Save outputs
# ---------------------------------------------------------------------------
out_dir <- file.path(opt$out_dir, axis)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

write_csv(results_df, file.path(out_dir, "cv_results.csv"))
write_csv(coef_df, file.path(out_dir, "coefficients.csv"))
write_csv(summary_stats, file.path(out_dir, "summary.csv"))

message(sprintf("\n[output] Results saved to: %s", out_dir))
message("[clm] Completed successfully")
