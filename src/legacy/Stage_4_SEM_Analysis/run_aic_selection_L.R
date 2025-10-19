#!/usr/bin/env Rscript

# Pure AIC Selection for L Axis with Stage 1 Feature Guidance

library(tidyverse)
library(mgcv)
library(MuMIn)
library(nlme)

set.seed(123)

cat("Loading SEM-ready dataset with climate + trait features...\n")
data <- read.csv("artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv",
                 check.names = FALSE, stringsAsFactors = FALSE)

target_col <- "EIVEres-L"
target_response <- gsub("[^A-Za-z0-9_]", "_", target_col)

if (!(target_col %in% names(data))) stop(sprintf("Missing target column %s", target_col))

data <- data[!is.na(data[[target_col]]), ]
if (!(target_response %in% names(data))) data[[target_response]] <- data[[target_col]]

if (!("EIVEres_M" %in% names(data)) && "EIVEres-M" %in% names(data)) {
  data$EIVEres_M <- data[["EIVEres-M"]]
}

cat(sprintf("Working with %d observations for L axis\n", nrow(data)))

trait_terms <- c("logLA", "LES_core", "logSM", "LMA", "SIZE", "logH", "logSSD", "LDMC", "Nmass", "is_woody")
climate_terms <- c("precip_cv", "tmin_mean", "mat_mean", "precip_mean")
interaction_terms <- c("lma_precip", "height_ssd", "les_seasonality", "lma_la", "size_precip", "size_temp", "wood_precip")
cross_axis_terms <- c("EIVEres_M")
phylo_var <- "p_phylo_L"

available_terms <- function(cols) cols[cols %in% names(data)]
available_traits <- available_terms(trait_terms)
available_climate <- available_terms(climate_terms)
available_interactions <- available_terms(interaction_terms)
available_cross <- available_terms(cross_axis_terms)
has_phylo <- phylo_var %in% names(data)

cat("\nAvailable Stage-1 guided predictors:\n")
cat(sprintf("  Traits: %d/%d\n", length(available_traits), length(trait_terms)))
cat(sprintf("  Climate: %d/%d\n", length(available_climate), length(climate_terms)))
cat(sprintf("  Interactions: %d/%d\n", length(available_interactions), length(interaction_terms)))
cat(sprintf("  Cross-axis: %d/%d\n", length(available_cross), length(cross_axis_terms)))
cat(sprintf("  Phylogeny: %s\n", ifelse(has_phylo, "Yes", "No")))

sanitize_terms <- function(x) {
  if (length(x) == 0) return(character())
  ifelse(grepl("[^A-Za-z0-9_]", x), paste0("`", x, "`"), x)
}

make_formula <- function(response, base_terms, linear_terms = NULL, smooth_terms = NULL) {
  response <- if (grepl("-", response)) paste0("`", response, "`") else response
  pieces <- sanitize_terms(base_terms)
  if (length(linear_terms) > 0) pieces <- c(pieces, sanitize_terms(linear_terms))
  if (length(pieces) == 0) stop("No fixed effects supplied")
  formula_txt <- paste(response, "~", paste(pieces, collapse = " + "))
  if (length(smooth_terms) > 0) {
    smooth_txt <- paste0("s(", smooth_terms, ", k=5)", collapse = " + ")
    formula_txt <- paste(formula_txt, smooth_txt, sep = " + ")
  }
  as.formula(formula_txt)
}

model_candidates <- list()

base_terms <- available_terms(c("logLA"))
if (length(base_terms) == 0) stop("Required base predictor logLA missing")

model_candidates[["traits_core"]] <- make_formula(target_response, base_terms, linear_terms = setdiff(available_traits, base_terms))
if (has_phylo) {
  model_candidates[["traits_phylo"]] <- make_formula(target_response, base_terms, linear_terms = c(setdiff(available_traits, base_terms), phylo_var))
}

if (length(available_climate) > 0) {
  model_candidates[["traits_climate"]] <- make_formula(target_response, base_terms, linear_terms = c(setdiff(available_traits, base_terms), available_climate))
  if (has_phylo) {
    model_candidates[["traits_climate_phylo"]] <- make_formula(target_response, base_terms, linear_terms = c(setdiff(available_traits, base_terms), available_climate, phylo_var))
  }
}

comprehensive_linear <- unique(c(available_traits, available_climate, available_interactions, available_cross))
if (length(comprehensive_linear) > 0) {
  model_candidates[["stage1_full_linear"]] <- make_formula(target_response, base_terms, linear_terms = comprehensive_linear)
  if (has_phylo) {
    model_candidates[["stage1_full_linear_phylo"]] <- make_formula(target_response, base_terms, linear_terms = c(comprehensive_linear, phylo_var))
  }
}

smooth_candidates <- available_terms(c("precip_cv", "tmin_mean", "mat_mean", "precip_mean"))
if (length(smooth_candidates) >= 1) {
  model_candidates[["stage1_gam"]] <- make_formula(target_response, base_terms, linear_terms = setdiff(available_traits, base_terms), smooth_terms = smooth_candidates)
  if (has_phylo) {
    model_candidates[["stage1_gam_phylo"]] <- make_formula(target_response, base_terms, linear_terms = c(setdiff(available_traits, base_terms), phylo_var), smooth_terms = smooth_candidates)
  }
}

if (length(available_interactions) >= 2) {
  model_candidates[["interactions_gam"]] <- make_formula(target_response, base_terms,
    linear_terms = c(setdiff(available_traits, base_terms), available_cross, phylo_var[has_phylo]),
    smooth_terms = smooth_candidates)
}

cat(sprintf("\nTotal models queued for AIC comparison: %d\n", length(model_candidates)))

compute_vif <- function(model) {
  if (!inherits(model, "lm")) return(NULL)
  mm <- stats::model.matrix(model)
  if (ncol(mm) <= 1) return(NULL)
  mm <- mm[, colnames(mm) != "(Intercept)", drop = FALSE]
  out <- numeric(ncol(mm)); names(out) <- colnames(mm)
  for (j in seq_len(ncol(mm))) {
    yj <- mm[, j]; xj <- mm[, -j, drop = FALSE]
    if (!ncol(xj)) { out[j] <- 1; next }
    r2 <- summary(lm(yj ~ xj))$r.squared
    out[j] <- if (is.finite(r2) && r2 < 1) 1/(1-r2) else Inf
  }
  out
}

model_results <- list()
for (nm in names(model_candidates)) {
  formula_obj <- model_candidates[[nm]]
  cat(sprintf("\nFitting %s...\n", nm))
  tryCatch({
    has_smooth <- any(grepl("s\\(", deparse(formula_obj)))
    model <- if (has_smooth) gam(formula_obj, data = data, method = "ML") else lm(formula_obj, data = data)
    model_results[[nm]] <- list(
      model = model,
      formula = formula_obj,
      AIC = AIC(model),
      AICc = AICc(model),
      R2 = summary(model)$r.sq,
      n_params = if (inherits(model, "gam")) sum(model$edf) else length(coef(model))
    )
    cat(sprintf("  AICc = %.2f, R² = %.3f, params = %.1f\n",
                model_results[[nm]]$AICc,
                model_results[[nm]]$R2,
                model_results[[nm]]$n_params))
  }, error = function(e) {
    cat(sprintf("  ERROR: %s\n", e$message))
    model_results[[nm]] <- list(model=NULL, formula=formula_obj, AIC=Inf, AICc=Inf, R2=NA_real_, n_params=NA_real_, error=e$message)
  })
}

cat("\nCompiling AIC leaderboard...\n")
aic_table <- tibble(
  Model = names(model_results),
  AICc = purrr::map_dbl(model_results, ~ .x$AICc),
  AIC = purrr::map_dbl(model_results, ~ .x$AIC),
  R2 = purrr::map_dbl(model_results, ~ .x$R2),
  n_params = purrr::map_dbl(model_results, ~ .x$n_params)
) %>%
  filter(is.finite(AICc)) %>%
  arrange(AICc) %>%
  mutate(delta_AICc = AICc - min(AICc),
         weight = exp(-0.5 * delta_AICc))

if (nrow(aic_table) == 0) stop("No successful models to rank")
aic_table$weight <- aic_table$weight / sum(aic_table$weight)
print(aic_table, digits = 3)

best_name <- aic_table$Model[1]
best_model <- model_results[[best_name]]$model
best_formula <- paste(deparse(model_results[[best_name]]$formula), collapse = " ")
if (target_response != target_col) best_formula <- gsub(target_response, paste0("`", target_col, "`"), best_formula, fixed = TRUE)

cat(sprintf("\nBest model: %s\n", best_name))
cat(sprintf("Formula: %s\n", best_formula))
cat(sprintf("AICc: %.2f\n", aic_table$AICc[1]))
cat(sprintf("R²: %.3f\n", aic_table$R2[1]))
cat(sprintf("Effective parameters: %.1f\n", aic_table$n_params[1]))

cat("\nModel summary:\n")
print(summary(best_model))

if (inherits(best_model, "lm")) {
  vif_vals <- compute_vif(best_model)
  if (!is.null(vif_vals)) {
    cat("\nVariance Inflation Factors:\n")
    print(round(vif_vals, 2))
    hi <- vif_vals[vif_vals > 5]
    if (length(hi)) cat("[warn] VIF > 5 for:", paste(names(hi), collapse = ", "), "\n")
  }
}

cat("\nModels within ΔAICc < 2:\n")
print(filter(aic_table, delta_AICc < 2), digits = 3)

out_dir <- "results/aic_selection_L"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
write.csv(aic_table, file.path(out_dir, "aic_ranking_table.csv"), row.names = FALSE)
saveRDS(best_model, file.path(out_dir, "best_model.rds"))
saveRDS(model_results, file.path(out_dir, "all_models.rds"))
cat(sprintf("\nArtifacts written to %s/\n", out_dir))

cat("\nRepeating stratified 5×10 CV for best model...\n")
repeats <- 5; folds <- 10
set.seed(123)
y_vals <- data[[target_col]]

assign_strat <- function(y, K) {
  qs <- quantile(y, probs = seq(0,1,length.out = K+1), na.rm = TRUE, type = 7)
  qs[1] <- -Inf; qs[length(qs)] <- Inf
  groups <- cut(y, breaks = unique(qs), include.lowest = TRUE, labels = FALSE)
  fold_assign <- integer(length(y))
  for (grp in unique(groups)) {
    idx <- which(groups == grp)
    if (length(idx) == 0) next
    idx <- sample(idx)
    fold_assign[idx] <- rep(seq_len(K), length.out = length(idx))
  }
  fold_assign
}

cv_scores <- numeric(0)
for (r in seq_len(repeats)) {
  set.seed(123 + r)
  fold_assign <- assign_strat(y_vals, folds)
  for (k in seq_len(folds)) {
    te_idx <- which(fold_assign == k)
    tr_idx <- setdiff(seq_len(nrow(data)), te_idx)
    if (length(te_idx) < 5 || length(tr_idx) < 20) next
    train <- data[tr_idx, , drop = FALSE]
    test <- data[te_idx, , drop = FALSE]
    fit <- if (inherits(best_model, "gam")) gam(model_results[[best_name]]$formula, data = train, method = "ML") else lm(model_results[[best_name]]$formula, data = train)
    preds <- predict(fit, newdata = test)
    ss_res <- sum((test[[target_col]] - preds)^2, na.rm = TRUE)
    ss_tot <- sum((test[[target_col]] - mean(test[[target_col]]))^2, na.rm = TRUE)
    cv_scores <- c(cv_scores, 1 - ss_res/ss_tot)
  }
}

cv_scores <- cv_scores[is.finite(cv_scores)]
if (length(cv_scores) == 0) {
  cv_mean <- NA_real_; cv_sd <- NA_real_
  cat("[warn] Cross-validation failed to produce finite scores\n")
} else {
  cv_mean <- mean(cv_scores); cv_sd <- sd(cv_scores)
  cat(sprintf("CV R² (5×10 stratified): %.3f ± %.3f\n", cv_mean, cv_sd))
}

comparison <- tibble(
  Method = c("AIC Best Model", "pwSEM Enhanced", "pwSEM Baseline", "XGBoost pk"),
  `R² (CV)` = c(sprintf("%.3f ± %.3f", cv_mean, cv_sd), "0.324 ± 0.098", "0.285 ± 0.098", "0.373 ± 0.078"),
  Notes = c(best_name, "Stage 2 climate-enhanced", "Stage 2 original", "Stage 1 benchmark")
)
print(comparison)

cat("Done.\n")
