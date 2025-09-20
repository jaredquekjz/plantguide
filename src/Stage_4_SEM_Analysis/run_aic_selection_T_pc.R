#!/usr/bin/env Rscript

library(tidyverse)
library(mgcv)
library(MuMIn)

script_args <- commandArgs(trailingOnly = FALSE)
script_file_arg <- sub("^--file=", "", grep("^--file=", script_args, value = TRUE))
script_dir <- if (length(script_file_arg)) dirname(normalizePath(script_file_arg[1])) else getwd()
source(file.path(script_dir, "nested_gam_cv_utils.R"))

set.seed(123)

cat("Loading dataset with PCs...\n")
data <- read.csv("artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2_pcs.csv",
                 check.names = FALSE, stringsAsFactors = FALSE)

target_col <- "EIVEres-T"
if (!(target_col %in% names(data))) stop("Target column missing")

data <- data[!is.na(data[[target_col]]), ]
resp <- "target_y"
data[[resp]] <- data[[target_col]]
cat(sprintf("Rows: %d\n", nrow(data)))

species_vector <- if ("species_key" %in% names(data)) data$species_key else data$wfo_accepted_name
species_slugs <- slugify(species_vector)
species_slugs[!nzchar(species_slugs)] <- paste0("species_", seq_along(species_slugs))[!nzchar(species_slugs)]
species_labels <- if ("wfo_accepted_name" %in% names(data)) data$wfo_accepted_name else species_vector
family_vec <- if ("Family" %in% names(data)) data$Family else rep(NA_character_, nrow(data))

if (!"species_slug" %in% names(data)) {
  data$species_slug <- species_slugs
}

pc_cols <- paste0("pc_trait_", 1:4)
if (any(!pc_cols %in% names(data))) stop("Missing PC columns")

# stage-1 climate features for T axis
climate_cols <- c("mat_mean", "mat_q05", "mat_q95", "temp_seasonality",
                  "precip_seasonality", "precip_cv", "tmax_mean",
                  "ai_amp", "ai_cv_month", "ai_month_min")
interaction_cols <- c("lma_precip", "height_temp", "size_temp", "size_precip", "height_ssd")
extra_cols <- intersect(c("precip_mean", "mat_sd", "SIZE"), names(data))
phylo_col <- "p_phylo_T"

num_cols <- setdiff(names(data), c("Family", "is_woody", "wfo_accepted_name"))
num_cols <- num_cols[num_cols != "is_woody"]
data[num_cols] <- lapply(data[num_cols], function(x) suppressWarnings(as.numeric(x)))
if ("is_woody" %in% names(data)) data$is_woody <- factor(data$is_woody)

linear_terms <- c(pc_cols, intersect(climate_cols, names(data)),
                  intersect(interaction_cols, names(data)), extra_cols,
                  intersect(c("EIVEres_M"), names(data)), phylo_col,
                  intersect(c("is_woody"), names(data)))

formula_txt <- paste(resp, "~",
  paste(linear_terms, collapse = " + "),
  "+ s(lma_precip, k=6) + te(pc_trait_1, mat_mean, k=c(5,5)) + te(pc_trait_2, precip_seasonality, k=c(5,5))")

form <- as.formula(formula_txt)
cat("Fitting T-axis GAM (PC + tensors)...\n")
model <- gam(form, data = data, method = "ML")
print(summary(model))

aicc <- AICc(model)
aic <- AIC(model)
cat(sprintf("AICc=%.2f | AIC=%.2f\n", aicc, aic))

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

out_dir <- "results/aic_selection_T_pc"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
saveRDS(model, file.path(out_dir, "best_model.rds"))
write.csv(data.frame(formula=formula_txt, AIC=aic, AICc=aicc,
                     cv_mean=mean(cv_scores), cv_sd=sd(cv_scores)),
          file.path(out_dir, "summary.csv"), row.names = FALSE)

maybe_run_nested_cv(
  axis_letter = "Tpc",
  base_data = data,
  formula_obj = formula(model),
  is_gam = TRUE,
  target_col = target_col,
  species_names = species_labels,
  species_slugs = species_slugs,
  family_vec = family_vec,
  output_dir = out_dir
)

cat("Done.\n")
