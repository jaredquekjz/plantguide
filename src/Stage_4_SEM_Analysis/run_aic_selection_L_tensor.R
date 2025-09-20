#!/usr/bin/env Rscript

library(tidyverse)
library(mgcv)
library(MuMIn)

set.seed(123)

cat("Loading AIC reduced dataset...\n")
data <- read.csv("artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2_pcs.csv",
                 check.names = FALSE, stringsAsFactors = FALSE)

target_col <- "EIVEres-L"
if (!(target_col %in% names(data))) stop("Target column missing")

data <- data[!is.na(data[[target_col]]), ]
cat(sprintf("Rows: %d\n", nrow(data)))

# Rename target for model friendliness
resp <- "target_y"
data[[resp]] <- data[[target_col]]

pc_cols <- paste0("pc_trait_", 1:4)
missing_pcs <- setdiff(pc_cols, names(data))
if (length(missing_pcs)) stop(sprintf("Missing PC columns: %s", paste(missing_pcs, collapse=", ")))

# Numeric casting
num_cols <- setdiff(names(data), c("Family", "is_woody", "wfo_accepted_name"))
num_cols <- num_cols[num_cols != "is_woody"]
data[num_cols] <- lapply(data[num_cols], function(x) suppressWarnings(as.numeric(x)))

if ("is_woody" %in% names(data)) data$is_woody <- factor(data$is_woody)
if (!("EIVEres_M" %in% names(data)) && "EIVEres-M" %in% names(data)) {
  data$EIVEres_M <- data[["EIVEres-M"]]
}

formula_txt <- paste(resp, "~",
  paste(c(pc_cols, "precip_cv", "tmin_mean", "mat_mean", "precip_mean",
          "lma_precip", "height_ssd", "lma_la", "size_temp", "EIVEres_M",
          "p_phylo_L", "is_woody"), collapse = " + "),
  "+ s(lma_precip, k=5) + te(pc_trait_2, precip_mean, k=c(5,5))")

form <- as.formula(formula_txt)
cat("Fitting tensor GAM...\n")
model <- gam(form, data = data, method = "ML")
print(summary(model))

aicc <- AICc(model)
aic <- AIC(model)
cat(sprintf("AICc=%.2f | AIC=%.2f\n", aicc, aic))

# Cross-validation (5×10 stratified)
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

y_vals <- data[[resp]]
repeats <- 5; folds <- 10
cv_scores <- c()

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
    ss_res <- sum((test[[resp]] - preds)^2)
    ss_tot <- sum((test[[resp]] - mean(test[[resp]]))^2)
    cv_scores <- c(cv_scores, 1 - ss_res/ss_tot)
  }
}

cv_scores <- cv_scores[is.finite(cv_scores)]
cat(sprintf("CV R² = %.3f ± %.3f\n", mean(cv_scores), sd(cv_scores)))

out_dir <- "results/aic_selection_L_tensor"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
saveRDS(model, file.path(out_dir, "best_model.rds"))
write.csv(data.frame(formula=formula_txt, AIC=aic, AICc=aicc,
                     cv_mean=mean(cv_scores), cv_sd=sd(cv_scores)),
          file.path(out_dir, "summary.csv"), row.names = FALSE)

cat("Done.\n")
