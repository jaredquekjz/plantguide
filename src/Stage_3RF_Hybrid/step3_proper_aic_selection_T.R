#!/usr/bin/env Rscript

# =============================================================================
# Step 3: Proper AIC-Based Model Selection for Temperature
# =============================================================================
# Following Shipley's framework correctly:
# 1. Use black-box insights to guide model building
# 2. Test multiple model forms WITHOUT premature VIF reduction
# 3. Select best model via AIC
# 4. THEN handle multicollinearity in the winning model only
# =============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(ranger)
  library(MuMIn)  # For AICc
  library(car)     # For VIF
  # library(glmnet)  # For Ridge/LASSO - skip if not installed
})

# Configuration
CONFIG <- list(
  trait_data_path = "artifacts/model_data_complete_case_with_myco.csv",
  bioclim_summary = "data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv",
  target_var = "EIVEres-T",
  seed = 123,
  out_dir = "artifacts/stage3rf_step3_proper_aic/"
)

set.seed(CONFIG$seed)
dir.create(CONFIG$out_dir, recursive = TRUE, showWarnings = FALSE)

cat("==========================================\n")
cat("Step 3: Proper AIC Model Selection for T\n")
cat("==========================================\n\n")

# ============================================================================
# DATA PREPARATION
# ============================================================================

# Load and merge data (same as before)
trait_data <- read_csv(CONFIG$trait_data_path, show_col_types = FALSE)
climate_summary <- read_csv(CONFIG$bioclim_summary, show_col_types = FALSE)

climate_metrics <- climate_summary %>%
  filter(has_sufficient_data == TRUE) %>%
  select(
    species,
    # All bioclim variables based on RF importance
    mat_mean = bio1_mean,
    mat_sd = bio1_sd,
    temp_seasonality = bio4_mean,
    tmax_mean = bio5_mean,
    tmin_mean = bio6_mean,
    temp_range = bio7_mean,
    precip_mean = bio12_mean,
    precip_sd = bio12_sd,
    drought_min = bio14_mean,
    precip_seasonality = bio15_mean
  ) %>%
  mutate(
    # Derived metrics
    mat_q05 = mat_mean - 1.645 * mat_sd,
    mat_q95 = mat_mean + 1.645 * mat_sd,
    tmin_q05 = tmin_mean - 1.645 * (tmin_mean * 0.2),  # Approximate
    precip_cv = precip_sd / pmax(precip_mean, 1)
  )

normalize_species <- function(x) {
  tolower(gsub("[[:space:]_-]+", "_", x))
}

merged_data <- trait_data %>%
  mutate(species_normalized = normalize_species(wfo_accepted_name)) %>%
  inner_join(
    climate_metrics %>% mutate(species_normalized = normalize_species(species)),
    by = "species_normalized"
  )

# Create all features INCLUDING interactions (don't remove yet!)
features <- merged_data %>%
  mutate(
    # Log transforms
    logH = log10(`Plant height (m)`),
    logSM = log10(`Diaspore mass (mg)`),
    logSSD = log10(`SSD used (mg/mm3)`),
    logLA = log10(`Leaf area (mm2)`),
    
    # Clean names
    LMA = `LMA (g/m2)`,
    Nmass = `Nmass (mg/g)`,
    
    # Composite traits
    SIZE = logH + logSM,
    LES_core = -LMA/100 + Nmass/10,
    
    # Key interactions from RF insights
    wood_cold = logSSD * tmin_mean,
    size_temp = SIZE * mat_mean,
    height_temp = logH * mat_mean,
    les_seasonality = LES_core * temp_seasonality,
    lma_precip = LMA * precip_mean/1000
  ) %>%
  select(
    y = all_of(CONFIG$target_var),
    # All traits
    logH, logSM, logSSD, logLA, LMA, Nmass, SIZE, LES_core,
    # All climate
    mat_mean, mat_sd, mat_q05, mat_q95,
    temp_seasonality, temp_range,
    tmax_mean, tmin_mean, tmin_q05,
    precip_mean, precip_cv, drought_min,
    # All interactions
    wood_cold, size_temp, height_temp, les_seasonality, lma_precip
  ) %>%
  filter(complete.cases(.))

cat(sprintf("Dataset: %d species × %d features\n\n", nrow(features), ncol(features)-1))

# ============================================================================
# STEP 3A: BUILD CANDIDATE MODELS (WITHOUT VIF REDUCTION!)
# ============================================================================

cat("==========================================\n")
cat("Building Candidate Models\n")
cat("==========================================\n\n")

# Based on Step 1 RF insights, build targeted models
model_data <- as.data.frame(features)

# Model 1: Baseline traits only
m1_baseline <- lm(y ~ logH + logSM + logSSD + logLA + LMA + Nmass, 
                  data = model_data)

# Model 2: Traits + Size composite (to reduce collinearity)
m2_traits_size <- lm(y ~ SIZE + logSSD + logLA + LMA + Nmass,
                     data = model_data)

# Model 3: Traits + Top 3 climate (from RF)
m3_traits_climate_top <- lm(y ~ logH + logSM + logSSD + logLA + LMA + Nmass +
                            tmax_mean + mat_mean + mat_q05,
                            data = model_data)

# Model 4: Traits + All climate (let AIC decide)
m4_traits_climate_all <- lm(y ~ logH + logSM + logSSD + logLA + LMA + Nmass +
                            mat_mean + mat_sd + temp_seasonality + temp_range +
                            tmax_mean + tmin_mean + precip_mean + drought_min,
                            data = model_data)

# Model 5: Traits + Climate + Top interactions (from RF)
m5_with_interactions <- lm(y ~ logH + logSM + logSSD + logLA + LMA + Nmass +
                          mat_mean + tmax_mean + tmin_mean + precip_mean +
                          wood_cold + size_temp + les_seasonality,
                          data = model_data)

# Model 6: Traits + Climate + All interactions
m6_full <- lm(y ~ logH + logSM + logSSD + logLA + LMA + Nmass +
              mat_mean + mat_sd + temp_seasonality + tmax_mean + tmin_mean +
              precip_mean + drought_min +
              wood_cold + size_temp + height_temp + les_seasonality + lma_precip,
              data = model_data)

# Model 7: Reduced based on RF importance (top 10 features)
m7_rf_top10 <- lm(y ~ tmax_mean + mat_mean + mat_q05 + mat_q95 + tmin_mean +
                  precip_mean + drought_min + logH + wood_cold + SIZE,
                  data = model_data)

# Model 8: Climate only (no traits)
m8_climate_only <- lm(y ~ mat_mean + tmax_mean + tmin_mean + precip_mean + 
                      temp_seasonality + drought_min,
                      data = model_data)

# Model 9: Polynomial for temperature (non-linear response)
m9_poly_temp <- lm(y ~ logH + logSM + logSSD + LMA + Nmass +
                   poly(mat_mean, 2) + tmax_mean + tmin_mean + precip_mean,
                   data = model_data)

# Model 10: Interactions only for significant traits
m10_targeted <- lm(y ~ SIZE + logSSD + LMA + Nmass +
                   mat_mean + tmax_mean +
                   SIZE:mat_mean + logSSD:tmin_mean,
                   data = model_data)

# ============================================================================
# STEP 3B: AIC-BASED MODEL SELECTION
# ============================================================================

cat("==========================================\n")
cat("AIC-Based Model Selection\n")
cat("==========================================\n\n")

models <- list(
  baseline = m1_baseline,
  traits_size = m2_traits_size,
  climate_top3 = m3_traits_climate_top,
  climate_all = m4_traits_climate_all,
  interactions_top = m5_with_interactions,
  full = m6_full,
  rf_top10 = m7_rf_top10,
  climate_only = m8_climate_only,
  poly_temp = m9_poly_temp,
  targeted = m10_targeted
)

# Calculate AIC metrics
aic_comparison <- data.frame(
  model = names(models),
  aic = sapply(models, AIC),
  aicc = sapply(models, AICc),
  bic = sapply(models, BIC),
  r2 = sapply(models, function(m) summary(m)$r.squared),
  adj_r2 = sapply(models, function(m) summary(m)$adj.r.squared),
  n_params = sapply(models, function(m) length(coef(m))),
  stringsAsFactors = FALSE
) %>%
  mutate(
    delta_aic = aic - min(aic),
    weight = exp(-0.5 * delta_aic) / sum(exp(-0.5 * delta_aic))
  ) %>%
  arrange(aic)

print(aic_comparison, digits = 3)

# Save comparison
write_csv(aic_comparison, file.path(CONFIG$out_dir, "aic_comparison.csv"))

# ============================================================================
# STEP 3C: DIAGNOSE WINNING MODEL
# ============================================================================

cat("\n==========================================\n")
cat("Winning Model Diagnostics\n")
cat("==========================================\n\n")

best_model_name <- aic_comparison$model[1]
best_model <- models[[best_model_name]]

cat(sprintf("Best model: %s\n", best_model_name))
cat(sprintf("AIC: %.1f (weight = %.3f)\n", aic_comparison$aic[1], aic_comparison$weight[1]))
cat(sprintf("R²: %.3f (Adj R² = %.3f)\n", 
            aic_comparison$r2[1], aic_comparison$adj_r2[1]))
cat(sprintf("Parameters: %d\n\n", aic_comparison$n_params[1]))

# Check VIF for winning model
vif_df <- NULL
if (length(coef(best_model)) > 2) {
  tryCatch({
    vif_vals <- vif(best_model)
    cat("VIF values for winning model:\n")
    vif_df <- data.frame(
      variable = names(vif_vals),
      vif = as.numeric(vif_vals)
    ) %>%
      arrange(desc(vif))
    
    print(vif_df, digits = 2)
    
    if (!is.null(vif_df) && any(vif_df$vif > 10)) {
      cat("\n⚠ Warning: Some VIF values > 10 (severe multicollinearity)\n")
      cat("Variables with VIF > 10:\n")
      print(vif_df %>% filter(vif > 10))
    } else if (any(vif_df$vif > 5)) {
      cat("\n⚠ Note: Some VIF values > 5 (moderate multicollinearity)\n")
    } else {
      cat("\n✓ All VIF values < 5 (acceptable)\n")
    }
  }, error = function(e) {
    cat("\n⚠ VIF calculation failed (likely perfect collinearity)\n")
    cat("   This suggests aliased coefficients in the model.\n")
    cat("   Checking for NA coefficients...\n\n")
    
    coef_vals <- coef(best_model)
    if (any(is.na(coef_vals))) {
      cat("Aliased (NA) coefficients:\n")
      print(names(coef_vals)[is.na(coef_vals)])
      cat("\nThese variables are perfectly collinear with others.\n")
    }
  })
}

# ============================================================================
# STEP 3D: HANDLE MULTICOLLINEARITY (ONLY IF NEEDED)
# ============================================================================

if (!is.null(vif_df) && any(vif_df$vif > 10)) {
  cat("\n==========================================\n")
  cat("Addressing Multicollinearity\n")
  cat("==========================================\n\n")
  
  cat("Severe multicollinearity detected (VIF > 10)\n")
  cat("Options to address:\n")
  cat("1. Use ridge regression or elastic net (requires glmnet package)\n")
  cat("2. Remove correlated predictors\n")
  cat("3. Create composite variables\n")
  cat("4. Accept multicollinearity if prediction is the goal\n\n")
  
  # If prediction is the main goal, multicollinearity may be acceptable
  cat("Note: Since our goal is prediction (not inference),\n")
  cat("      multicollinearity may not be problematic.\n")
}

# ============================================================================
# STEP 3E: CROSS-VALIDATION OF BEST MODEL
# ============================================================================

cat("\n==========================================\n")
cat("Cross-Validation (10-fold)\n")
cat("==========================================\n\n")

n <- nrow(model_data)
folds <- sample(rep(1:10, length.out = n))
cv_results <- numeric(10)

for (fold in 1:10) {
  train_idx <- which(folds != fold)
  test_idx <- which(folds == fold)
  
  # Refit model on training data
  train_formula <- formula(best_model)
  cv_model <- lm(train_formula, data = model_data[train_idx, ])
  
  # Predict on test data
  pred <- predict(cv_model, newdata = model_data[test_idx, ])
  actual <- model_data$y[test_idx]
  
  # Calculate fold R²
  cv_results[fold] <- 1 - sum((actual - pred)^2) / sum((actual - mean(actual))^2)
}

cat(sprintf("CV R²: %.3f ± %.3f\n", mean(cv_results), sd(cv_results)))
cat(sprintf("Min fold R²: %.3f\n", min(cv_results)))
cat(sprintf("Max fold R²: %.3f\n", max(cv_results)))

# ============================================================================
# SAVE RESULTS
# ============================================================================

cat("\n==========================================\n")
cat("Saving Results\n")
cat("==========================================\n")

# Save best model
saveRDS(best_model, file.path(CONFIG$out_dir, "best_model.rds"))

# Save summary
summary_results <- list(
  best_model = best_model_name,
  aic_comparison = aic_comparison,
  best_model_stats = list(
    aic = aic_comparison$aic[1],
    r2 = aic_comparison$r2[1],
    adj_r2 = aic_comparison$adj_r2[1],
    n_params = aic_comparison$n_params[1],
    cv_r2 = mean(cv_results),
    cv_r2_sd = sd(cv_results)
  ),
  vif_diagnostics = if(exists("vif_df")) vif_df else NULL,
  formula = as.character(formula(best_model))[3]
)

saveRDS(summary_results, file.path(CONFIG$out_dir, "summary_results.rds"))

cat(sprintf("\nResults saved to: %s\n", CONFIG$out_dir))

# ============================================================================
# FINAL RECOMMENDATIONS
# ============================================================================

cat("\n==========================================\n")
cat("RECOMMENDATIONS\n")
cat("==========================================\n\n")

cat("1. Model Selection:\n")
cat(sprintf("   - Best model '%s' selected via AIC\n", best_model_name))
cat(sprintf("   - Achieves R² = %.3f without premature feature removal\n", aic_comparison$r2[1]))

if (exists("vif_df") && any(vif_df$vif > 10)) {
  cat("\n2. Multicollinearity:\n")
  cat("   - Severe multicollinearity detected (VIF > 10)\n")
  cat("   - Consider ridge regression or elastic net\n")
  cat("   - DO NOT remove features before model selection\n")
}

cat("\n3. Next Steps:\n")
cat("   - If R² satisfactory, proceed with this model\n")
cat("   - If multicollinearity problematic, use regularization\n")
cat("   - Test on independent validation set if available\n")

cat("\n==========================================\n")
cat("Analysis Complete!\n")
cat("==========================================\n")