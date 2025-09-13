#!/usr/bin/env Rscript

# =============================================================================
# Hybrid Climate + Phylogenetic Blending Model for Temperature (EIVE-T)
# =============================================================================
# This script extends the comprehensive hybrid trait-bioclim model by adding
# phylogenetic blending as the final enhancement step, following Shipley's
# complete recommendation: Traits + Climate (new data) + Phylogeny
#
# Workflow:
# 1. Build hybrid trait-climate model (as in comprehensive script)
# 2. Generate predictions from best model
# 3. Compute phylogenetic neighbor predictions
# 4. Blend predictions: (1-α) * climate_pred + α * phylo_pred
# 5. Evaluate performance across α grid
# =============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(ranger)
  library(ape)
  library(mgcv)
  library(car)
})

# Configuration
CONFIG <- list(
  # Data paths
  trait_data_path = "artifacts/model_data_complete_case_with_myco.csv",
  bioclim_summary = "data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv",
  phylogeny_path = "data/phylogeny/eive_try_tree.nwk",
  
  # Model parameters
  target_var = "EIVEres-T",
  seed = 123,
  cv_folds = 10,
  cv_repeats = 5,
  max_vif = 5,
  
  # Phylogenetic parameters
  x_exp = 2,  # Weight exponent: w_ij = 1/d_ij^x
  alpha_grid = c(0, 0.1, 0.25, 0.5, 0.75, 1),  # Blending weights
  
  # Output
  out_dir = "artifacts/stage3rf_hybrid_climate_phylo/"
)

set.seed(CONFIG$seed)
dir.create(CONFIG$out_dir, recursive = TRUE, showWarnings = FALSE)

cat("==========================================\n")
cat("Hybrid Climate + Phylogenetic Blending\n")
cat("Target:", CONFIG$target_var, "\n")
cat("==========================================\n\n")

# ============================================================================
# SECTION 1: DATA LOADING AND PREPARATION
# ============================================================================

# Load trait data
trait_data <- read_csv(CONFIG$trait_data_path, show_col_types = FALSE)
cat(sprintf("Loaded %d species with trait data\n", nrow(trait_data)))

# Load bioclim summary
climate_summary <- read_csv(CONFIG$bioclim_summary, show_col_types = FALSE)

# Filter for species with sufficient climate data
climate_metrics <- climate_summary %>%
  filter(has_sufficient_data == TRUE) %>%
  select(
    species,
    mat_mean = bio1_mean,
    tmax_mean = bio5_mean,
    tmin_mean = bio6_mean,
    precip_mean = bio12_mean,
    drought_min = bio14_mean
  )

# Normalize species names
normalize_species <- function(x) {
  tolower(gsub("[[:space:]_-]+", "_", x))
}

# Merge datasets
merged_data <- trait_data %>%
  mutate(species_normalized = normalize_species(wfo_accepted_name)) %>%
  inner_join(
    climate_metrics %>% mutate(species_normalized = normalize_species(species)),
    by = "species_normalized"
  )

cat(sprintf("Merged: %d species with both traits and climate\n", nrow(merged_data)))

# Prepare features with proper column names and transformations
features <- merged_data %>%
  mutate(
    # Create log-transformed variables
    logH = log10(`Plant height (m)`),
    logSM = log10(`Diaspore mass (mg)`),
    logSSD = log10(`SSD used (mg/mm3)`),
    logLA = log10(`Leaf area (mm2)`),
    # Rename columns to remove special characters
    LMA = `LMA (g/m2)`,
    Nmass = `Nmass (mg/g)`
  ) %>%
  select(
    # Target
    y = all_of(CONFIG$target_var),
    # Species identifier (for phylogeny)
    wfo_accepted_name,
    # Traits
    logH, logSM, logSSD, logLA, LMA, Nmass,
    # Climate
    mat_mean, tmax_mean, tmin_mean, precip_mean, drought_min
  ) %>%
  filter(complete.cases(.))

cat(sprintf("Final dataset: %d observations\n", nrow(features)))

# ============================================================================
# SECTION 2: LOAD PHYLOGENY AND COMPUTE DISTANCES
# ============================================================================

cat("\n==========================================\n")
cat("Loading Phylogenetic Tree\n")
cat("==========================================\n")

tree <- read.tree(CONFIG$phylogeny_path)
tips <- tree$tip.label

# Map species to tree tips
species_tips <- gsub(" ", "_", features$wfo_accepted_name, fixed = TRUE)
in_tree <- species_tips %in% tips

cat(sprintf("Species in phylogeny: %d/%d (%.1f%%)\n", 
            sum(in_tree), length(in_tree), 100 * mean(in_tree)))

# Keep only species in tree for this analysis
features_tree <- features[in_tree, ]
species_tips_tree <- species_tips[in_tree]

# Compute cophenetic distance matrix
cat("Computing phylogenetic distances...\n")
tree_pruned <- keep.tip(tree, species_tips_tree)
cop_dist <- cophenetic.phylo(tree_pruned)

# ============================================================================
# SECTION 3: BUILD CLIMATE MODEL (SIMPLIFIED FOR STABILITY)
# ============================================================================

cat("\n==========================================\n")
cat("Building Climate-Enhanced Model\n")
cat("==========================================\n")

# Use simplified model based on stability analysis results
# Avoiding interaction terms and complex features that caused instability

model_data <- features_tree %>%
  select(-wfo_accepted_name) %>%
  as.data.frame()

# Simple climate + traits model (based on AIC selection from comprehensive)
climate_formula <- as.formula(paste("y ~", 
  paste(c("logH", "logSM", "logSSD", "logLA", "LMA", "Nmass",
          "mat_mean", "tmax_mean", "tmin_mean", "precip_mean", "drought_min"),
        collapse = " + ")))

climate_model <- lm(climate_formula, data = model_data)

# Compute in-sample predictions
climate_preds <- predict(climate_model, model_data)

cat(sprintf("Climate model R²: %.3f\n", 
            1 - sum((model_data$y - climate_preds)^2) / sum((model_data$y - mean(model_data$y))^2)))

# ============================================================================
# SECTION 4: COMPUTE PHYLOGENETIC NEIGHBOR PREDICTIONS
# ============================================================================

cat("\n==========================================\n")
cat("Computing Phylogenetic Neighbor Predictions\n")
cat("==========================================\n")

compute_phylo_predictions <- function(target_indices, donor_indices, 
                                     distances, donor_values, x_exp = 2) {
  # Compute weights matrix
  D <- distances[target_indices, donor_indices, drop = FALSE]
  W <- matrix(0, nrow(D), ncol(D))
  
  # Weight = 1/d^x for d > 0
  pos <- which(D > 0)
  W[pos] <- 1 / (D[pos]^x_exp)
  
  # Exclude self-predictions (diagonal)
  for (i in seq_len(nrow(D))) {
    self_idx <- which(donor_indices == target_indices[i])
    if (length(self_idx) > 0) {
      W[i, self_idx] <- 0
    }
  }
  
  # Compute weighted average
  numerator <- W %*% matrix(donor_values, ncol = 1)
  denominator <- rowSums(W)
  denominator[denominator == 0] <- NA
  
  as.numeric(numerator) / denominator
}

# For in-sample, compute leave-one-out phylogenetic predictions
phylo_preds <- numeric(nrow(features_tree))

for (i in seq_len(nrow(features_tree))) {
  # Target is species i, donors are all others
  target_idx <- i
  donor_idx <- setdiff(seq_len(nrow(features_tree)), i)
  
  phylo_preds[i] <- compute_phylo_predictions(
    target_indices = target_idx,
    donor_indices = donor_idx,
    distances = cop_dist,
    donor_values = model_data$y[donor_idx],
    x_exp = CONFIG$x_exp
  )
}

cat(sprintf("Phylogenetic predictor R²: %.3f\n",
            1 - sum((model_data$y - phylo_preds)^2, na.rm = TRUE) / 
                sum((model_data$y - mean(model_data$y))^2)))

# ============================================================================
# SECTION 5: BLEND PREDICTIONS ACROSS ALPHA GRID
# ============================================================================

cat("\n==========================================\n")
cat("Blending Climate and Phylogenetic Predictions\n")
cat("==========================================\n")

blend_results <- data.frame(
  alpha = CONFIG$alpha_grid,
  r2 = NA,
  rmse = NA,
  mae = NA
)

for (i in seq_along(CONFIG$alpha_grid)) {
  alpha <- CONFIG$alpha_grid[i]
  
  # Blend: (1-α) * climate + α * phylo
  blended_preds <- (1 - alpha) * climate_preds + alpha * phylo_preds
  
  # Calculate metrics
  residuals <- model_data$y - blended_preds
  r2 <- 1 - sum(residuals^2, na.rm = TRUE) / sum((model_data$y - mean(model_data$y))^2)
  rmse <- sqrt(mean(residuals^2, na.rm = TRUE))
  mae <- mean(abs(residuals), na.rm = TRUE)
  
  blend_results$r2[i] <- r2
  blend_results$rmse[i] <- rmse
  blend_results$mae[i] <- mae
  
  cat(sprintf("α = %.2f: R² = %.3f, RMSE = %.3f\n", alpha, r2, rmse))
}

# Find optimal alpha
best_idx <- which.max(blend_results$r2)
best_alpha <- blend_results$alpha[best_idx]
best_r2 <- blend_results$r2[best_idx]

cat(sprintf("\nOptimal blending: α = %.2f (R² = %.3f)\n", best_alpha, best_r2))
cat(sprintf("Improvement over climate-only: +%.1f%%\n", 
            100 * (best_r2 - blend_results$r2[1]) / blend_results$r2[1]))

# ============================================================================
# SECTION 6: CROSS-VALIDATION WITH BLENDING
# ============================================================================

cat("\n==========================================\n")
cat("Cross-Validation with Optimal Blending\n")
cat("==========================================\n")

# Create CV folds
n <- nrow(model_data)
fold_assignments <- rep(1:CONFIG$cv_folds, length.out = n)

cv_results <- list()

for (rep in 1:CONFIG$cv_repeats) {
  # Shuffle fold assignments
  fold_assignments <- sample(fold_assignments)
  
  for (fold in 1:CONFIG$cv_folds) {
    test_idx <- which(fold_assignments == fold)
    train_idx <- setdiff(1:n, test_idx)
    
    # Fit climate model on training data
    train_data <- model_data[train_idx, ]
    test_data <- model_data[test_idx, ]
    
    cv_climate_model <- lm(climate_formula, data = train_data)
    cv_climate_preds <- predict(cv_climate_model, test_data)
    
    # Compute phylogenetic predictions for test set using training donors
    cv_phylo_preds <- compute_phylo_predictions(
      target_indices = test_idx,
      donor_indices = train_idx,
      distances = cop_dist,
      donor_values = train_data$y,
      x_exp = CONFIG$x_exp
    )
    
    # Blend with optimal alpha
    cv_blended_preds <- (1 - best_alpha) * cv_climate_preds + best_alpha * cv_phylo_preds
    
    # Store results
    cv_results[[length(cv_results) + 1]] <- data.frame(
      rep = rep,
      fold = fold,
      y_true = test_data$y,
      y_climate = cv_climate_preds,
      y_phylo = cv_phylo_preds,
      y_blended = cv_blended_preds
    )
  }
}

# Combine CV results
cv_df <- bind_rows(cv_results)

# Calculate CV metrics
cv_metrics <- cv_df %>%
  summarise(
    r2_climate = 1 - sum((y_true - y_climate)^2) / sum((y_true - mean(y_true))^2),
    r2_phylo = 1 - sum((y_true - y_phylo)^2, na.rm = TRUE) / sum((y_true - mean(y_true))^2),
    r2_blended = 1 - sum((y_true - y_blended)^2, na.rm = TRUE) / sum((y_true - mean(y_true))^2),
    rmse_blended = sqrt(mean((y_true - y_blended)^2, na.rm = TRUE))
  )

cat(sprintf("\nCross-Validation Results (α = %.2f):\n", best_alpha))
cat(sprintf("  Climate-only R²: %.3f\n", cv_metrics$r2_climate))
cat(sprintf("  Phylo-only R²: %.3f\n", cv_metrics$r2_phylo))
cat(sprintf("  Blended R²: %.3f\n", cv_metrics$r2_blended))
cat(sprintf("  Improvement: +%.1f%%\n", 
            100 * (cv_metrics$r2_blended - cv_metrics$r2_climate) / cv_metrics$r2_climate))

# ============================================================================
# SECTION 7: SAVE RESULTS
# ============================================================================

cat("\n==========================================\n")
cat("Saving Results\n")
cat("==========================================\n")

# Save blend results
write_csv(blend_results, file.path(CONFIG$out_dir, "blend_results.csv"))

# Save CV results
write_csv(cv_df, file.path(CONFIG$out_dir, "cv_predictions.csv"))

# Save summary
summary_df <- data.frame(
  model = c("Climate-only", "Phylo-only", "Blended", "Blended_CV"),
  r2 = c(blend_results$r2[1], 
         1 - sum((model_data$y - phylo_preds)^2, na.rm = TRUE) / 
             sum((model_data$y - mean(model_data$y))^2),
         best_r2,
         cv_metrics$r2_blended),
  optimal_alpha = c(NA, NA, best_alpha, best_alpha)
)

write_csv(summary_df, file.path(CONFIG$out_dir, "summary.csv"))

# Save models
saveRDS(climate_model, file.path(CONFIG$out_dir, "climate_model.rds"))
saveRDS(list(distances = cop_dist, x_exp = CONFIG$x_exp), 
        file.path(CONFIG$out_dir, "phylo_params.rds"))

cat(sprintf("\nResults saved to: %s\n", CONFIG$out_dir))

# ============================================================================
# FINAL SUMMARY
# ============================================================================

cat("\n==========================================\n")
cat("FINAL SUMMARY\n")
cat("==========================================\n")
cat(sprintf("Climate model R²: %.3f\n", blend_results$r2[1]))
cat(sprintf("Phylogenetic predictor R²: %.3f\n", 
            1 - sum((model_data$y - phylo_preds)^2, na.rm = TRUE) / 
                sum((model_data$y - mean(model_data$y))^2)))
cat(sprintf("Optimal blending (α = %.2f) R²: %.3f\n", best_alpha, best_r2))
cat(sprintf("Cross-validation blended R²: %.3f\n", cv_metrics$r2_blended))
cat(sprintf("\nTotal improvement over climate-only: +%.1f%%\n",
            100 * (cv_metrics$r2_blended - cv_metrics$r2_climate) / cv_metrics$r2_climate))

cat("\n==========================================\n")
cat("Analysis Complete!\n")
cat("==========================================\n")