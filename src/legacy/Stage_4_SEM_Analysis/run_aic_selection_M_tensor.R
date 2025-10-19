#!/usr/bin/env Rscript

# Moisture axis GAM with targeted tensors on raw Stage-2 features
# Combines linear trait backbone, shrinkage smooths for climate, and
# trait × climate tensor interactions selected from Stage-1 diagnostics.

library(tidyverse)
library(mgcv)
library(MuMIn)

set.seed(123)

cat("Loading Stage 2 raw dataset...\n")
data <- read.csv(
  "artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv",
  check.names = FALSE,
  stringsAsFactors = FALSE
)

target_col <- "EIVEres-M"
if (!(target_col %in% names(data))) stop("Target column missing")

data <- data[!is.na(data[[target_col]]), ]

# Work with a sanitized response to avoid hyphen handling in formulas
response_safe <- gsub("[^A-Za-z0-9_]", "_", target_col)
if (!(response_safe %in% names(data))) {
  data[[response_safe]] <- data[[target_col]]
}
cat(sprintf("Rows: %d\n", nrow(data)))

# Convert numeric-looking columns to numeric; keep key factors
num_cols <- setdiff(names(data), c("Family", "is_woody", "wfo_accepted_name"))
if (length(num_cols)) {
  data[num_cols] <- lapply(data[num_cols], function(x) suppressWarnings(as.numeric(x)))
}
if ("is_woody" %in% names(data)) {
  data$is_woody <- factor(data$is_woody)
}

# Build trait principal components to reduce collinearity among mass/size traits
trait_cols <- c("logLA", "logSM", "logSSD", "logH", "LES_core", "SIZE", "LMA", "Nmass", "LDMC")
available_trait_cols <- trait_cols[trait_cols %in% names(data)]
if (!length(available_trait_cols)) stop("No trait columns available for PCA")
trait_matrix <- data[available_trait_cols]
complete_idx <- complete.cases(trait_matrix)
if (sum(complete_idx) < 10) stop("Insufficient complete cases for trait PCA")
pca <- prcomp(trait_matrix[complete_idx, , drop = FALSE], center = TRUE, scale. = TRUE)
pc_scores <- predict(pca, newdata = trait_matrix)
pc_keep <- min(4, ncol(pc_scores))
for (i in seq_len(pc_keep)) {
  data[[paste0("trait_pc", i)]] <- pc_scores[, i]
}

available_terms <- function(cols) cols[cols %in% names(data)]
quote_term <- function(term) {
  vapply(term, function(x) {
    if (is.na(x) || x == "") return("")
    if (grepl("[^A-Za-z0-9_]", x)) paste0("`", x, "`") else x
  }, character(1))
}

# Linear trait backbone (principal components to limit collinearity)
trait_linear <- available_terms(paste0("trait_pc", seq_len(pc_keep)))

# Stage-1 interaction features kept as linear terms
linear_interactions <- available_terms(c(
  "lma_precip", "size_temp", "height_temp", "les_drought", "wood_precip"
))

# Climate smooths with shrinkage to allow AIC to turn off weak effects
climate_smooths <- available_terms(c(
  "precip_coldest_q", "drought_min", "precip_mean", "precip_seasonality",
  "mat_mean", "temp_seasonality", "ai_roll3_min", "ai_amp", "ai_cv_month",
  "ai_month_min", "precip_cv"
))

if (!length(trait_linear)) stop("No trait predictors available")
if (!length(climate_smooths)) stop("No climate predictors available for smooths")

# Tensor interaction candidates derived from Stage-1 SHAP pairs
tensor_pairs <- list(
  c("trait_pc1", "precip_mean"),
  c("trait_pc1", "precip_coldest_q"),
  c("trait_pc2", "ai_amp"),
  c("trait_pc2", "precip_seasonality"),
  c("trait_pc3", "drought_min"),
  c("trait_pc3", "mat_mean"),
  c("trait_pc4", "ai_cv_month"),
  c("trait_pc1", "ai_roll3_min")
)

tensor_terms <- character(0)
for (pair in tensor_pairs) {
  if (all(pair %in% names(data))) {
    tensor_terms <- c(tensor_terms,
                      sprintf("ti(%s, %s, k=c(4,4))",
                              quote_term(pair[1]), quote_term(pair[2])))
  }
}
if (!length(tensor_terms)) stop("No tensor interaction terms available; adjust tensor_pairs")

# Assemble formula components
formula_terms <- c()
formula_terms <- c(formula_terms, quote_term(trait_linear))
formula_terms <- c(formula_terms, quote_term(linear_interactions))

smooth_chunks <- sprintf("s(%s, k=5, bs=\"ts\")", quote_term(climate_smooths))
formula_terms <- c(formula_terms, smooth_chunks)

formula_terms <- c(formula_terms, tensor_terms)

# Allow non-linear phylogeny contribution with shrinkage
if ("p_phylo_M" %in% names(data)) {
  formula_terms <- c(formula_terms, "s(p_phylo_M, k=5, bs=\"ts\")")
} else {
  stop("p_phylo_M column required for phylogeny term")
}

if ("is_woody" %in% names(data)) {
  formula_terms <- c(formula_terms, "is_woody")
}

formula_txt <- paste(quote_term(response_safe), "~", paste(formula_terms, collapse = " + "))
form <- as.formula(formula_txt)

cat("Fitting M-axis GAM with tensors...\n")
model <- gam(form, data = data, method = "ML")
print(summary(model))

aic_val <- AIC(model)
aicc_val <- AICc(model)
cat(sprintf("AICc=%.2f | AIC=%.2f\n", aicc_val, aic_val))

assign_strata <- function(y, K) {
  qs <- quantile(y, probs = seq(0, 1, length.out = K + 1), na.rm = TRUE, type = 7)
  qs[1] <- -Inf
  qs[length(qs)] <- Inf
  groups <- cut(y, breaks = unique(qs), include.lowest = TRUE, labels = FALSE)
  fold_assign <- integer(length(y))
  for (grp in sort(unique(groups))) {
    idx <- which(groups == grp)
    if (length(idx) == 0) next
    fold_assign[idx] <- sample(rep(seq_len(K), length.out = length(idx)))
  }
  fold_assign
}

y_vals <- data[[target_col]]
repeats <- 5
folds <- 10
cv_r2 <- numeric(0)
cv_rmse <- numeric(0)

for (r in seq_len(repeats)) {
  set.seed(123 + r)
  fold_assign <- assign_strata(y_vals, folds)
  for (k in seq_len(folds)) {
    test_idx <- which(fold_assign == k)
    train_idx <- setdiff(seq_len(nrow(data)), test_idx)
    if (length(test_idx) < 5 || length(train_idx) < 20) next
    train <- data[train_idx, , drop = FALSE]
    test <- data[test_idx, , drop = FALSE]
    fit <- gam(form, data = train, method = "ML")
    preds <- predict(fit, newdata = test)
    residuals <- test[[target_col]] - preds
    ss_res <- sum(residuals^2, na.rm = TRUE)
    ss_tot <- sum((test[[target_col]] - mean(test[[target_col]]))^2, na.rm = TRUE)
    cv_r2 <- c(cv_r2, 1 - (ss_res / ss_tot))
    cv_rmse <- c(cv_rmse, sqrt(mean(residuals^2, na.rm = TRUE)))
  }
}

cv_r2 <- cv_r2[is.finite(cv_r2)]
cv_rmse <- cv_rmse[is.finite(cv_rmse)]
cv_mean <- if (length(cv_r2)) mean(cv_r2) else NA_real_
cv_sd <- if (length(cv_r2)) sd(cv_r2) else NA_real_
rmse_mean <- if (length(cv_rmse)) mean(cv_rmse) else NA_real_
rmse_sd <- if (length(cv_rmse)) sd(cv_rmse) else NA_real_

if (!length(cv_r2)) {
  cat("\n[warn] Cross-validation produced no valid folds.\n")
} else {
  cat(sprintf("\n5x10-fold stratified CV R²: %.3f ± %.3f\n", cv_mean, cv_sd))
  cat(sprintf("5x10-fold stratified CV RMSE: %.3f ± %.3f\n", rmse_mean, rmse_sd))
}

out_dir <- "results/aic_selection_M_tensor"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

saveRDS(model, file.path(out_dir, "best_model.rds"))

summary_tbl <- tibble(
  formula = formula_txt,
  AIC = aic_val,
  AICc = aicc_val,
  cv_mean = cv_mean,
  cv_sd = cv_sd,
  rmse_mean = rmse_mean,
  rmse_sd = rmse_sd,
  deviance_explained = summary(model)$dev.expl,
  adj_r2 = summary(model)$r.sq
)

write_csv(summary_tbl, file.path(out_dir, "summary.csv"))

cat("Done.\n")
