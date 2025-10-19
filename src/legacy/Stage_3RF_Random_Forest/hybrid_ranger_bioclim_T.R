#!/usr/bin/env Rscript

#' Hybrid Trait-Bioclim Model for Temperature using Ranger
#' Adapted from Stage_3RF_Random_Forest/run_ranger_regression.R
#' Integrates bioclim data with trait-based modeling

# Set library path
.libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))

suppressWarnings({
  suppressMessages({
    library(ranger)
    library(readr)
    library(jsonlite)
    library(dplyr)
    library(tidyr)
    library(MuMIn)
    library(mgcv)
  })
})

# Configuration
CONFIG <- list(
  trait_data = "artifacts/model_data_complete_case_with_myco.csv",
  bioclim_dir = "data/bioclim_extractions_cleaned/species_bioclim/",
  out_dir = "artifacts/stage4_hybrid_T/",
  target = "EIVEres-T",
  
  # CV parameters
  seed = 123,
  repeats = 5,
  folds = 10,
  stratify = TRUE,
  standardize = TRUE,
  
  # Ranger parameters
  num_trees = 1000,
  mtry = NULL,  # Will be set as sqrt(p)
  min_node_size = 5,
  
  # Bioclim parameters
  min_occurrences = 30
)

dir.create(CONFIG$out_dir, recursive = TRUE, showWarnings = FALSE)

# ============================================================================
# Helper Functions (from original scripts)
# ============================================================================

compute_offset <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x) & !is.na(x) & x > 0]
  if (!length(x)) return(1e-6)
  max(1e-6, 1e-3 * median(x))
}

zscore <- function(x, mean_ = NULL, sd_ = NULL) {
  x <- as.numeric(x)
  if (is.null(mean_)) mean_ <- mean(x, na.rm = TRUE)
  if (is.null(sd_)) sd_ <- sd(x, na.rm = TRUE)
  if (!is.finite(sd_) || sd_ == 0) sd_ <- 1
  list(x = (x - mean_) / sd_, mean = mean_, sd = sd_)
}

make_folds <- function(y, K, stratify = TRUE) {
  n <- length(y)
  if (!stratify) {
    return(sample(rep(1:K, length.out = n)))
  }
  
  # Stratified by deciles
  deciles <- cut(y, breaks = quantile(y, probs = seq(0, 1, 0.1), na.rm = TRUE), 
                 include.lowest = TRUE, labels = FALSE)
  folds <- integer(n)
  
  for (d in unique(deciles)) {
    idx <- which(deciles == d)
    folds[idx] <- sample(rep(1:K, length.out = length(idx)))
  }
  
  return(folds)
}

# ============================================================================
# Bioclim Processing
# ============================================================================

calculate_bioclim_metrics <- function(bioclim_dir, min_occurrences = 30) {
  
  cat("Loading pre-calculated bioclim metrics...\n")
  
  # Use the pre-calculated summary file for efficiency
  summary_file <- "data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv"
  
  if (file.exists(summary_file)) {
    climate_metrics <- read_csv(summary_file, show_col_types = FALSE) %>%
      filter(has_sufficient_data == TRUE) %>%
      select(
        species,
        n_occurrences,
        # Temperature metrics (rename to match our convention)
        mat_mean = bio1_mean,
        mat_sd = bio1_sd,
        temp_seasonality = bio4_mean,
        temp_range = bio7_mean,
        tmax_mean = bio5_mean,
        tmin_mean = bio6_mean,
        # For quantiles, we'll approximate from mean and sd
        # Since we don't have exact quantiles in summary
        precip_mean = bio12_mean,
        precip_sd = bio12_sd
      ) %>%
      mutate(
        # Approximate quantiles assuming normal distribution
        mat_q05 = mat_mean - 1.645 * mat_sd,
        mat_q95 = mat_mean + 1.645 * mat_sd,
        tmin_q05 = tmin_mean - 1.645 * 2,  # Approximate
        precip_cv = precip_sd / precip_mean
      )
    
    cat(sprintf("Loaded metrics for %d species from summary file\n", nrow(climate_metrics)))
    
  } else {
    # Fallback to calculating from individual files
    cat("Summary file not found, calculating from individual files...\n")
    
    bioclim_files <- list.files(bioclim_dir, pattern = "_bioclim.csv$", full.names = TRUE)
    
    climate_metrics <- do.call(rbind, lapply(bioclim_files, function(file) {
      species_name <- gsub("_bioclim.csv", "", basename(file))
      species_name <- gsub("_", " ", species_name)
      
      tryCatch({
        bio_data <- read_csv(file, show_col_types = FALSE) %>%
          filter(!is.na(bio1))
        
        if (nrow(bio_data) < min_occurrences) return(NULL)
        
        metrics <- bio_data %>%
          summarise(
            species = species_name,
            n_occurrences = n(),
            
            # Temperature metrics (key for T axis)
            mat_mean = mean(bio1, na.rm = TRUE),
            mat_sd = sd(bio1, na.rm = TRUE),
            mat_q05 = quantile(bio1, 0.05, na.rm = TRUE),
            mat_q95 = quantile(bio1, 0.95, na.rm = TRUE),
            temp_seasonality = mean(bio4, na.rm = TRUE),
            temp_range = mean(bio7, na.rm = TRUE),
            tmax_mean = mean(bio5, na.rm = TRUE),
            tmin_mean = mean(bio6, na.rm = TRUE),
            tmin_q05 = quantile(bio6, 0.05, na.rm = TRUE),
            
            # Some moisture metrics for interactions
            precip_mean = mean(bio12, na.rm = TRUE),
            precip_cv = sd(bio12, na.rm = TRUE) / mean(bio12, na.rm = TRUE),
            
            .groups = 'drop'
          )
        
        return(metrics)
      }, error = function(e) {
        return(NULL)
      })
    }))
    
    cat(sprintf("Calculated metrics for %d species\n", nrow(climate_metrics)))
  }
  
  return(climate_metrics)
}

# ============================================================================
# Main Analysis
# ============================================================================

cat("==========================================\n")
cat("Hybrid Trait-Bioclim Model for Temperature\n")
cat("==========================================\n\n")

# Load trait data
cat("Loading trait data...\n")
trait_data <- read_csv(CONFIG$trait_data, show_col_types = FALSE)
cat(sprintf("Loaded %d species with trait data\n", nrow(trait_data)))

# Calculate bioclim metrics
climate_metrics <- calculate_bioclim_metrics(CONFIG$bioclim_dir, CONFIG$min_occurrences)

# Save climate metrics
write_csv(climate_metrics, file.path(CONFIG$out_dir, "climate_metrics.csv"))

# Merge trait and climate data
cat("\nMerging trait and climate data...\n")

# Normalize species names for better matching
# Handle spaces, hyphens, and underscores consistently
normalize_species <- function(x) {
  tolower(gsub("[[:space:]_-]+", "_", x))
}

merged_data <- trait_data %>%
  mutate(species_normalized = normalize_species(wfo_accepted_name)) %>%
  inner_join(
    climate_metrics %>% mutate(species_normalized = normalize_species(species)),
    by = "species_normalized",
    suffix = c("", "_climate")
  ) %>%
  filter(!is.na(mat_mean))  # Keep only species with climate data

cat(sprintf("Merged data: %d species with both traits and climate\n", nrow(merged_data)))

# Prepare features
log_vars <- c("Leaf area (mm2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
offsets <- sapply(log_vars, function(v) compute_offset(merged_data[[v]]))

# Create feature matrix with traits
X_traits <- merged_data %>%
  mutate(
    logLA = log10(`Leaf area (mm2)` + offsets["Leaf area (mm2)"]),
    logH = log10(`Plant height (m)` + offsets["Plant height (m)"]),
    logSM = log10(`Diaspore mass (mg)` + offsets["Diaspore mass (mg)"]),
    logSSD = log10(`SSD used (mg/mm3)` + offsets["SSD used (mg/mm3)"]),
    LES_core = -`LMA (g/m2)` + scale(`Nmass (mg/g)`)[,1],
    SIZE = scale(logH)[,1] + scale(logSM)[,1]
  ) %>%
  select(logLA, logH, logSM, logSSD, `Nmass (mg/g)`, `LMA (g/m2)`, LES_core, SIZE)

# Add climate features
X_climate <- merged_data %>%
  select(mat_mean, mat_sd, temp_seasonality, temp_range, tmin_q05, precip_mean, precip_cv)

# Create interactions
X_interactions <- data.frame(
  size_temp = X_traits$SIZE * X_climate$mat_mean,
  height_temp = X_traits$logH * X_climate$mat_mean,
  les_seasonality = X_traits$LES_core * X_climate$temp_seasonality,
  wood_cold = X_traits$logSSD * X_climate$tmin_q05
)

# Combine all features
X_all <- cbind(X_traits, X_climate, X_interactions)
y <- merged_data[[CONFIG$target]]

# Remove rows with missing values
complete_idx <- complete.cases(X_all, y)
X_all <- X_all[complete_idx, ]
y <- y[complete_idx]

cat(sprintf("\nFinal dataset: %d observations, %d features\n", length(y), ncol(X_all)))

# ============================================================================
# Cross-Validation with Multiple Models
# ============================================================================

set.seed(CONFIG$seed)

cv_results <- list()
model_comparison <- list()

for (rep in 1:CONFIG$repeats) {
  
  folds <- make_folds(y, CONFIG$folds, CONFIG$stratify)
  
  for (fold in 1:CONFIG$folds) {
    
    # Split data
    train_idx <- folds != fold
    X_train <- X_all[train_idx, ]
    X_test <- X_all[!train_idx, ]
    y_train <- y[train_idx]
    y_test <- y[!train_idx]
    
    # Standardize if requested
    if (CONFIG$standardize) {
      train_means <- colMeans(X_train, na.rm = TRUE)
      train_sds <- apply(X_train, 2, sd, na.rm = TRUE)
      train_sds[train_sds == 0] <- 1
      
      X_train <- scale(X_train, center = train_means, scale = train_sds)
      X_test <- scale(X_test, center = train_means, scale = train_sds)
    }
    
    # Model 1: Trait-only (baseline)
    rf_traits <- ranger(
      x = X_train[, 1:8],  # Just trait features
      y = y_train,
      num.trees = CONFIG$num_trees,
      mtry = ceiling(sqrt(8)),
      min.node.size = CONFIG$min_node_size,
      importance = 'impurity'
    )
    pred_traits <- predict(rf_traits, X_test[, 1:8])$predictions
    
    # Model 2: Trait + Climate (no interactions)
    rf_climate <- ranger(
      x = X_train[, 1:15],  # Traits + climate
      y = y_train,
      num.trees = CONFIG$num_trees,
      mtry = ceiling(sqrt(15)),
      min.node.size = CONFIG$min_node_size,
      importance = 'impurity'
    )
    pred_climate <- predict(rf_climate, X_test[, 1:15])$predictions
    
    # Model 3: Full hybrid (all features)
    rf_full <- ranger(
      x = X_train,
      y = y_train,
      num.trees = CONFIG$num_trees,
      mtry = ceiling(sqrt(ncol(X_train))),
      min.node.size = CONFIG$min_node_size,
      importance = 'impurity'
    )
    pred_full <- predict(rf_full, X_test)$predictions
    
    # Store results
    cv_results[[length(cv_results) + 1]] <- data.frame(
      rep = rep,
      fold = fold,
      model = c("traits_only", "traits_climate", "full_hybrid"),
      rmse = c(
        sqrt(mean((y_test - pred_traits)^2)),
        sqrt(mean((y_test - pred_climate)^2)),
        sqrt(mean((y_test - pred_full)^2))
      ),
      r2 = c(
        cor(y_test, pred_traits)^2,
        cor(y_test, pred_climate)^2,
        cor(y_test, pred_full)^2
      ),
      mae = c(
        mean(abs(y_test - pred_traits)),
        mean(abs(y_test - pred_climate)),
        mean(abs(y_test - pred_full))
      )
    )
  }
}

# Combine CV results
cv_df <- do.call(rbind, cv_results)

# Calculate summary statistics
cv_summary <- cv_df %>%
  group_by(model) %>%
  summarise(
    r2_mean = mean(r2),
    r2_sd = sd(r2),
    rmse_mean = mean(rmse),
    rmse_sd = sd(rmse),
    mae_mean = mean(mae),
    mae_sd = sd(mae),
    .groups = 'drop'
  ) %>%
  arrange(desc(r2_mean))

cat("\n==========================================\n")
cat("Cross-Validation Results (10-fold × 5 repeats):\n")
cat("==========================================\n")
print(cv_summary)

# Save CV results
write_csv(cv_df, file.path(CONFIG$out_dir, "cv_results_detailed.csv"))
write_csv(cv_summary, file.path(CONFIG$out_dir, "cv_results_summary.csv"))

# ============================================================================
# Train Final Models and Compare with Linear Regression
# ============================================================================

cat("\n==========================================\n")
cat("Training Final Models on Full Data\n")
cat("==========================================\n")

# Standardize full data if needed
if (CONFIG$standardize) {
  X_all_scaled <- scale(X_all)
} else {
  X_all_scaled <- X_all
}

# Final Random Forest model
rf_final <- ranger(
  x = X_all_scaled,
  y = y,
  num.trees = CONFIG$num_trees,
  mtry = ceiling(sqrt(ncol(X_all))),
  min.node.size = CONFIG$min_node_size,
  importance = 'impurity'
)

# Feature importance
importance_df <- data.frame(
  feature = names(X_all),
  importance = rf_final$variable.importance
) %>%
  arrange(desc(importance))

cat("\nTop 10 Important Features:\n")
print(head(importance_df, 10))

write_csv(importance_df, file.path(CONFIG$out_dir, "feature_importance.csv"))

# Linear models for comparison
cat("\n==========================================\n")
cat("Linear Model Comparison (AIC Selection)\n")
cat("==========================================\n")

# Prepare data for linear models
lm_data <- cbind(data.frame(T = y), X_all_scaled)

# Prepare data for linear models - rename columns with special characters
lm_data_renamed <- lm_data %>%
  rename(
    Nmass = `Nmass (mg/g)`,
    LMA = `LMA (g/m2)`
  )

# Model 1: Baseline (traits only)
lm1 <- lm(T ~ logLA + logH + logSM + logSSD + Nmass + LMA + LES_core + SIZE, 
          data = lm_data_renamed)

# Model 2: Add climate
lm2 <- lm(T ~ logLA + logH + logSM + logSSD + Nmass + LMA + LES_core + SIZE +
          mat_mean + temp_seasonality + temp_range + tmin_q05,
          data = lm_data_renamed)

# Model 3: Add interactions
lm3 <- lm(T ~ logLA + logH + logSM + logSSD + Nmass + LMA + LES_core + SIZE +
          mat_mean + temp_seasonality + temp_range + tmin_q05 +
          size_temp + height_temp + les_seasonality + wood_cold,
          data = lm_data_renamed)

# Model 4: GAM with smoothers
gam1 <- gam(T ~ s(logH, k=5) + s(logSM, k=5) + logSSD + Nmass + LMA +
            s(mat_mean, k=5) + s(temp_seasonality, k=5) + tmin_q05 +
            ti(logH, mat_mean, k=c(5,5)),
            data = lm_data_renamed)

# Model comparison
model_comparison <- data.frame(
  model = c("lm_traits", "lm_climate", "lm_interactions", "gam_smooth", "rf_full"),
  aic = c(AIC(lm1), AIC(lm2), AIC(lm3), AIC(gam1), NA),
  aicc = c(AICc(lm1), AICc(lm2), AICc(lm3), AICc(gam1), NA),
  r2 = c(
    summary(lm1)$r.squared,
    summary(lm2)$r.squared,
    summary(lm3)$r.squared,
    summary(gam1)$r.sq,
    rf_final$r.squared
  ),
  n_params = c(
    length(coef(lm1)),
    length(coef(lm2)),
    length(coef(lm3)),
    sum(summary(gam1)$edf),
    NA
  )
) %>%
  mutate(
    delta_aic = aic - min(aic, na.rm = TRUE),
    weight = exp(-0.5 * delta_aic) / sum(exp(-0.5 * delta_aic[!is.na(delta_aic)]))
  )

cat("\nModel Comparison:\n")
print(model_comparison)

write_csv(model_comparison, file.path(CONFIG$out_dir, "model_comparison.csv"))

# Save best linear model
if (!is.na(model_comparison$aic[4]) && model_comparison$aic[4] == min(model_comparison$aic, na.rm = TRUE)) {
  best_model <- gam1
  best_name <- "gam_smooth"
} else {
  best_idx <- which.min(model_comparison$aic[1:3])
  best_model <- list(lm1, lm2, lm3)[[best_idx]]
  best_name <- model_comparison$model[best_idx]
}

saveRDS(best_model, file.path(CONFIG$out_dir, "best_linear_model.rds"))
saveRDS(rf_final, file.path(CONFIG$out_dir, "rf_final_model.rds"))

# ============================================================================
# Summary Report
# ============================================================================

summary_results <- list(
  timestamp = Sys.time(),
  n_species_traits = nrow(trait_data),
  n_species_climate = nrow(climate_metrics),
  n_species_merged = nrow(merged_data),
  n_observations = length(y),
  n_features = ncol(X_all),
  
  cv_results = cv_summary,
  model_comparison = model_comparison,
  top_features = head(importance_df, 15),
  
  performance = list(
    baseline_r2 = model_comparison$r2[1],
    best_linear_r2 = model_comparison$r2[which(model_comparison$model == best_name)],
    rf_r2 = rf_final$r.squared,
    improvement_pct = round(100 * (rf_final$r.squared - model_comparison$r2[1]) / model_comparison$r2[1], 1)
  ),
  
  best_model = best_name,
  config = CONFIG
)

# Save summary as JSON
write_json(summary_results, file.path(CONFIG$out_dir, "summary.json"), pretty = TRUE, auto_unbox = TRUE)

cat("\n==========================================\n")
cat("SUMMARY\n")
cat("==========================================\n")
cat(sprintf("Baseline R² (traits only): %.3f\n", summary_results$performance$baseline_r2))
cat(sprintf("Best Linear Model R²: %.3f\n", summary_results$performance$best_linear_r2))
cat(sprintf("Random Forest R²: %.3f\n", summary_results$performance$rf_r2))
cat(sprintf("Improvement: +%.1f%%\n", summary_results$performance$improvement_pct))
cat(sprintf("\nResults saved to: %s\n", CONFIG$out_dir))