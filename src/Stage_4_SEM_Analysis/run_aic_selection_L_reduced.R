#!/usr/bin/env Rscript

library(tidyverse)
library(mgcv)
library(MuMIn)
library(nlme)

set.seed(123)

cat("Loading SEM-ready dataset...\n")
data <- read.csv("artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv",
                 check.names = FALSE, stringsAsFactors = FALSE)

target_col <- "EIVEres-L"
if (!(target_col %in% names(data))) stop("Target column missing")

data <- data[!is.na(data[[target_col]]), ]
target_clean <- "target_y"
data[[target_clean]] <- data[[target_col]]
cat(sprintf("Observations: %d\n", nrow(data)))

trait_cols <- c("logLA", "LES_core", "logSM", "LMA", "SIZE", "logH", "logSSD", "LDMC")
missing_traits <- setdiff(trait_cols, names(data))
if (length(missing_traits)) stop(sprintf("Missing trait columns: %s", paste(missing_traits, collapse = ", ")))

trait_matrix <- as.matrix(data[, trait_cols])
trait_pca <- prcomp(trait_matrix, center = TRUE, scale. = TRUE)
trait_scores <- predict(trait_pca)
cumvar <- summary(trait_pca)$importance[3,]
keep_idx <- which(cumvar >= 0.90)[1]
if (is.na(keep_idx)) keep_idx <- min(3, ncol(trait_scores))
trait_scores <- trait_scores[, seq_len(keep_idx), drop = FALSE]
trait_score_df <- as.data.frame(trait_scores)
colnames(trait_score_df) <- paste0("trait_PC", seq_len(ncol(trait_score_df)))
cat(sprintf("Trait PCs retained: %d (%.1f%% variance)\n", ncol(trait_score_df), cumvar[keep_idx] * 100))

model_df <- data %>%
  select(all_of(c(target_clean,
                  "precip_cv", "tmin_mean", "mat_mean", "precip_mean",
                  "lma_precip", "height_ssd", "lma_la", "size_temp",
                  "EIVEres-M", "p_phylo_L", "is_woody"))) %>%
  bind_cols(trait_score_df)

if ("EIVEres-M" %in% names(model_df)) {
  model_df$EIVEres_M <- model_df[["EIVEres-M"]]
  model_df[["EIVEres-M"]] <- NULL
}

model_df <- drop_na(model_df)
cat(sprintf("Rows after dropping NA: %d\n", nrow(model_df)))

if ("is_woody" %in% names(model_df)) model_df$is_woody <- factor(model_df$is_woody)

pc_cols <- colnames(trait_score_df)
climate_cols <- intersect(c("precip_cv", "tmin_mean", "mat_mean", "precip_mean"), names(model_df))
interaction_cols <- intersect(c("lma_precip", "height_ssd", "lma_la", "size_temp"), names(model_df))
cross_cols <- intersect(c("EIVEres_M"), names(model_df))
has_phylo <- "p_phylo_L" %in% names(model_df)

make_formula <- function(y, linear, smooth = NULL) {
  response <- if (grepl("-", y)) paste0("`", y, "`") else y
  linear <- linear[!is.na(linear) & linear != ""]
  form <- paste(response, "~", paste(linear, collapse = " + "))
  if (!is.null(smooth) && length(smooth) > 0) {
    smooth_txt <- paste0("s(", smooth, ", k=5)", collapse = " + ")
    form <- paste(form, smooth_txt, sep = " + ")
  }
  as.formula(form)
}

candidate_forms <- list()
candidate_forms[["core"]] <- make_formula(target_clean, pc_cols)
if (has_phylo) candidate_forms[["core_phylo"]] <- make_formula(target_clean, c(pc_cols, "p_phylo_L"))
candidate_forms[["core_climate"]] <- make_formula(target_clean, c(pc_cols, climate_cols))
if (has_phylo) candidate_forms[["core_climate_phylo"]] <- make_formula(target_clean, c(pc_cols, climate_cols, "p_phylo_L"))
candidate_forms[["full_linear"]] <- make_formula(target_clean, c(pc_cols, climate_cols, interaction_cols, cross_cols, if (has_phylo) "p_phylo_L" else NULL))
candidate_forms[["semi_gam"]] <- make_formula(target_clean, c(pc_cols, climate_cols, interaction_cols, cross_cols, if (has_phylo) "p_phylo_L" else NULL), smooth = c("lma_precip", "size_temp"))

candidate_forms <- candidate_forms[!sapply(candidate_forms, is.null)]
cat(sprintf("Total candidate formulas: %d\n", length(candidate_forms)))

fit_results <- list()
for (nm in names(candidate_forms)) {
  form <- candidate_forms[[nm]]
  cat(sprintf("\nFitting %s...\n", nm))
  has_smooth <- any(grepl("s\\(", deparse(form)))
  model <- try(if (has_smooth) gam(form, data = model_df, method = "ML") else lm(form, data = model_df), silent = TRUE)
  if (inherits(model, "try-error")) {
    cat("  ERROR: ", model[[1]], "\n", sep = "")
    next
  }
  aicc <- AICc(model)
  aic <- AIC(model)
  r2 <- summary(model)$r.sq
  params <- if (inherits(model, "gam")) sum(model$edf) else length(coef(model))
  fit_results[[nm]] <- list(model = model, AICc = aicc, AIC = aic, R2 = r2, params = params, formula = form)
  cat(sprintf("  AICc=%.2f | R²=%.3f | params=%.1f\n", aicc, r2, params))
}

if (length(fit_results) == 0) stop("No successful models")

aic_table <- tibble(
  Model = names(fit_results),
  AICc = purrr::map_dbl(fit_results, "AICc"),
  AIC = purrr::map_dbl(fit_results, "AIC"),
  R2 = purrr::map_dbl(fit_results, "R2"),
  params = purrr::map_dbl(fit_results, "params")
) %>%
  arrange(AICc) %>%
  mutate(delta_AICc = AICc - first(AICc),
         weight = exp(-0.5 * delta_AICc))

aic_table$weight <- aic_table$weight / sum(aic_table$weight)
print(aic_table, digits = 3)

best_name <- aic_table$Model[1]
best_info <- fit_results[[best_name]]
cat(sprintf("\nBest model: %s\n", best_name))
print(summary(best_info$model))

cat("\n5×10 stratified CV...\n")
repeats <- 5; folds <- 10
cv_scores <- c()

assign_strata <- function(y, K) {
  qs <- quantile(y, probs = seq(0,1,length.out = K+1), na.rm = TRUE, type = 7)
  qs[1] <- -Inf; qs[length(qs)] <- Inf
  groups <- cut(y, breaks = unique(qs), include.lowest = TRUE, labels = FALSE)
  fold_assign <- integer(length(y))
  for (grp in unique(groups)) {
    idx <- which(groups == grp)
    if (length(idx) == 0) next
    fold_assign[idx] <- sample(rep(seq_len(K), length.out = length(idx)))
  }
  fold_assign
}

for (r in seq_len(repeats)) {
  set.seed(123 + r)
  fold_assign <- assign_strata(model_df[[target_clean]], folds)
  for (k in seq_len(folds)) {
    test_idx <- which(fold_assign == k)
    train_idx <- setdiff(seq_len(nrow(model_df)), test_idx)
    if (length(test_idx) < 5 || length(train_idx) < 20) next
    train <- model_df[train_idx, , drop = FALSE]
    test <- model_df[test_idx, , drop = FALSE]
    form <- best_info$formula
    has_smooth <- any(grepl("s\\(", deparse(form)))
    fit <- if (has_smooth) gam(form, data = train, method = "ML") else lm(form, data = train)
    preds <- predict(fit, newdata = test)
    ss_res <- sum((test[[target_clean]] - preds)^2)
    ss_tot <- sum((test[[target_clean]] - mean(test[[target_clean]]))^2)
    cv_scores <- c(cv_scores, 1 - ss_res/ss_tot)
  }
}

cv_scores <- cv_scores[is.finite(cv_scores)]
cat(sprintf("CV R² = %.3f ± %.3f\n", mean(cv_scores), sd(cv_scores)))

out_dir <- "results/aic_selection_L_reduced"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
write.csv(aic_table, file.path(out_dir, "aic_ranking_table.csv"), row.names = FALSE)
saveRDS(best_info$model, file.path(out_dir, "best_model.rds"))
saveRDS(fit_results, file.path(out_dir, "all_models.rds"))

cat("Done.\n")
