#!/usr/bin/env Rscript

#' SEM-Augmented Hybrid Trait-Bioclim Model
#' 
#' This script implements the correct approach:
#' 1. Start with PROVEN SEM equations as structured regression baseline
#' 2. Achieve the same high R² as SEM (e.g., 0.408 for M, 0.231 for T)
#' 3. THEN augment with bioclim variables to push even higher
#'
#' Key insight: We must leverage the validated structural equations,
#' not start from scratch with feature selection!

# Set library path
.libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))

# Load libraries
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(mgcv)
  library(optparse)
  library(jsonlite)
})

# Parse command-line arguments
option_list <- list(
  make_option(c("--target"), type="character", default="M",
              help="Target EIVE axis [T, M, R, N, L] (default: M)"),
  make_option(c("--output_dir"), type="character",
              default="artifacts/stage3rf_sem_augmented/",
              help="Output directory for results"),
  make_option(c("--cv_folds"), type="integer", default=10,
              help="Number of CV folds (default: 10)"),
  make_option(c("--cv_repeats"), type="integer", default=5,
              help="Number of CV repeats (default: 5)")
)

opt_parser <- OptionParser(option_list=option_list)
opt <- parse_args(opt_parser)

# Validate target
valid_targets <- c("T", "M", "R", "N", "L")
if (!opt$target %in% valid_targets) {
  stop(sprintf("Invalid target '%s'. Must be one of: %s", 
               opt$target, paste(valid_targets, collapse=", ")))
}

cat("==========================================\n")
cat("SEM-Augmented Hybrid Model\n")
cat("Target:", opt$target, "\n")
cat("==========================================\n\n")

# Configuration based on Run 7 SEM specifications
CONFIG <- list(
  target = paste0("EIVEres-", opt$target),
  target_axis = opt$target,
  
  # Data paths
  trait_data = "artifacts/model_data_complete_case_with_myco.csv",
  bioclim_summary = "data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv",
  
  # SEM equation specifications from Run 7
  # M and N use deconstructed SIZE (logH + logSM separately)
  # T, R use SIZE composite
  # L uses GAM with smooths (Run 7c specification)
  deconstruct_size = opt$target %in% c("M", "N"),
  
  # LES components (negLMA, Nmass)
  les_components = c("negLMA", "Nmass"),
  
  # Additional predictors
  add_logLA = opt$target %in% c("L", "T", "M", "R", "N"),  # All axes
  add_les_logssd = opt$target == "N",  # N has LES:logSSD interaction
  
  # GAM specifications for L
  use_gam_L = opt$target == "L",
  
  # Output
  output_dir = file.path(opt$output_dir, opt$target),
  cv_folds = opt$cv_folds,
  cv_repeats = opt$cv_repeats,
  seed = 123
)

# Create output directory
dir.create(CONFIG$output_dir, showWarnings = FALSE, recursive = TRUE)

# ============================================================================
# SECTION 1: DATA LOADING AND PREPARATION
# ============================================================================

# Load trait data
cat("Loading trait data...\n")
trait_data <- read_csv(CONFIG$trait_data, show_col_types = FALSE)

# Select necessary columns and transform
work_data <- trait_data %>%
  mutate(
    # Log transformations with offsets (matching SEM)
    logLA = log10(`Leaf area (mm2)` + 0.01),
    logH = log10(`Plant height (m)` + 0.01),
    logSM = log10(`Diaspore mass (mg)` + 0.01),
    logSSD = log10(`SSD used (mg/mm3)` + 0.01),
    LMA = `LMA (g/m2)`,
    Nmass = `Nmass (mg/g)`,
    negLMA = -LMA,  # For LES composite
    
    # Target variable
    y = .data[[CONFIG$target]],
    
    # Keep identifiers
    species = wfo_accepted_name,
    myco_group = Myco_Group_Final,
    family = Family
  ) %>%
  filter(!is.na(y))

cat(sprintf("Loaded %d species with target data\n", nrow(work_data)))

# ============================================================================
# SECTION 2: BUILD COMPOSITES (LES and SIZE) - CRITICAL!
# ============================================================================

build_composites <- function(data) {
  # LES composite: PC1 of standardized {-LMA, Nmass}
  les_mat <- data %>%
    select(negLMA, Nmass) %>%
    scale(center = TRUE, scale = TRUE)
  
  # Handle any NAs
  les_mat[is.na(les_mat)] <- 0
  
  les_pca <- prcomp(les_mat, center = FALSE, scale. = FALSE)
  les_rot <- les_pca$rotation[,1]
  
  # Ensure Nmass has positive loading (following SEM convention)
  if (les_rot["Nmass"] < 0) les_rot <- -les_rot
  
  data$LES <- as.numeric(les_mat %*% les_rot)
  
  # SIZE composite: PC1 of standardized {logH, logSM}
  size_mat <- data %>%
    select(logH, logSM) %>%
    scale(center = TRUE, scale = TRUE)
  
  size_mat[is.na(size_mat)] <- 0
  
  size_pca <- prcomp(size_mat, center = FALSE, scale. = FALSE)
  size_rot <- size_pca$rotation[,1]
  
  # Ensure logH has positive loading
  if (size_rot["logH"] < 0) size_rot <- -size_rot
  
  data$SIZE <- as.numeric(size_mat %*% size_rot)
  
  return(data)
}

work_data <- build_composites(work_data)

# ============================================================================
# SECTION 3: DEFINE SEM EQUATIONS (from Run 7 specifications)
# ============================================================================

get_sem_formula <- function(target_axis, deconstruct_size, use_gam = FALSE) {
  if (use_gam && target_axis == "L") {
    # Run 7c GAM specification for Light
    formula_str <- paste(
      "y ~ s(LMA, k=5) + s(logSSD, k=5) + s(logH, k=5) + s(logLA, k=5) +",
      "Nmass + LMA:logLA +",
      "t2(LMA, logSSD, k=c(5,5)) +",
      "ti(logLA, logH, k=c(5,5)) +",
      "ti(logH, logSSD, k=c(5,5))"
    )
  } else if (deconstruct_size) {
    # M and N use deconstructed SIZE
    formula_str <- "y ~ LES + logH + logSM + logSSD"
    
    if (target_axis %in% c("M", "N")) {
      formula_str <- paste(formula_str, "+ logLA")
    }
    
    if (target_axis == "N") {
      formula_str <- paste(formula_str, "+ LES:logSSD")
    }
  } else {
    # T and R use SIZE composite
    formula_str <- "y ~ LES + SIZE + logSSD"
    
    if (target_axis %in% c("T", "R")) {
      formula_str <- paste(formula_str, "+ logLA")
    }
  }
  
  return(as.formula(formula_str))
}

# ============================================================================
# SECTION 4: FIT SEM BASELINE MODEL
# ============================================================================

cat("\n==========================================\n")
cat("Stage 1: SEM Baseline (Traits Only)\n")
cat("==========================================\n\n")

# Get the appropriate formula
sem_formula <- get_sem_formula(CONFIG$target_axis, CONFIG$deconstruct_size, CONFIG$use_gam_L)
cat("SEM Formula:", deparse(sem_formula), "\n\n")

# Fit the baseline SEM model
if (CONFIG$use_gam_L && CONFIG$target_axis == "L") {
  # GAM for Light
  baseline_model <- gam(sem_formula, data = work_data, family = gaussian())
} else {
  # Linear model for other axes
  baseline_model <- lm(sem_formula, data = work_data)
}

# Calculate baseline R²
baseline_pred <- predict(baseline_model, work_data)
baseline_r2 <- cor(baseline_pred, work_data$y)^2

cat(sprintf("Baseline SEM R² (traits only): %.3f\n", baseline_r2))

# Expected R² from Run 7:
expected_r2 <- list(
  L = 0.300,  # Run 7c
  T = 0.231,  # Run 7
  M = 0.408,  # Run 7
  R = 0.155,  # Run 7
  N = 0.425   # Run 7
)

cat(sprintf("Expected R² from Run 7: %.3f\n", expected_r2[[CONFIG$target_axis]]))
cat(sprintf("Ratio: %.1f%%\n\n", 100 * baseline_r2 / expected_r2[[CONFIG$target_axis]]))

# ============================================================================
# SECTION 5: CROSS-VALIDATION FOR SEM BASELINE
# ============================================================================

cat("Running cross-validation for SEM baseline...\n")

set.seed(CONFIG$seed)
cv_results <- list()

for (rep in 1:CONFIG$cv_repeats) {
  # Create folds stratified by target
  fold_ids <- cut(rank(work_data$y), breaks = CONFIG$cv_folds, labels = FALSE)
  fold_ids <- sample(fold_ids)  # Shuffle
  
  for (fold in 1:CONFIG$cv_folds) {
    test_idx <- which(fold_ids == fold)
    train_idx <- which(fold_ids != fold)
    
    train_data <- work_data[train_idx, ]
    test_data <- work_data[test_idx, ]
    
    # Rebuild composites on training data
    train_data <- build_composites(train_data)
    
    # Apply same transformations to test
    les_train_mean <- attr(scale(train_data[c("negLMA", "Nmass")]), "scaled:center")
    les_train_sd <- attr(scale(train_data[c("negLMA", "Nmass")]), "scaled:scale")
    
    test_les_mat <- scale(test_data[c("negLMA", "Nmass")],
                          center = les_train_mean,
                          scale = les_train_sd)
    
    # Get rotation from training
    les_pca_train <- prcomp(scale(train_data[c("negLMA", "Nmass")]),
                             center = FALSE, scale. = FALSE)
    les_rot_train <- les_pca_train$rotation[,1]
    if (les_rot_train["Nmass"] < 0) les_rot_train <- -les_rot_train
    
    test_data$LES <- as.numeric(test_les_mat %*% les_rot_train)
    
    # Same for SIZE
    size_train_mean <- attr(scale(train_data[c("logH", "logSM")]), "scaled:center")
    size_train_sd <- attr(scale(train_data[c("logH", "logSM")]), "scaled:scale")
    
    test_size_mat <- scale(test_data[c("logH", "logSM")],
                           center = size_train_mean,
                           scale = size_train_sd)
    
    size_pca_train <- prcomp(scale(train_data[c("logH", "logSM")]),
                              center = FALSE, scale. = FALSE)
    size_rot_train <- size_pca_train$rotation[,1]
    if (size_rot_train["logH"] < 0) size_rot_train <- -size_rot_train
    
    test_data$SIZE <- as.numeric(test_size_mat %*% size_rot_train)
    
    # Fit model
    if (CONFIG$use_gam_L && CONFIG$target_axis == "L") {
      cv_model <- gam(sem_formula, data = train_data, family = gaussian())
    } else {
      cv_model <- lm(sem_formula, data = train_data)
    }
    
    # Predict
    pred <- predict(cv_model, test_data)
    
    # Store results
    cv_results[[length(cv_results) + 1]] <- data.frame(
      rep = rep,
      fold = fold,
      r2 = cor(pred, test_data$y)^2,
      rmse = sqrt(mean((pred - test_data$y)^2)),
      mae = mean(abs(pred - test_data$y))
    )
  }
}

cv_df <- bind_rows(cv_results)
cv_summary <- cv_df %>%
  summarise(
    r2_mean = mean(r2),
    r2_sd = sd(r2),
    rmse_mean = mean(rmse),
    rmse_sd = sd(rmse),
    mae_mean = mean(mae),
    mae_sd = sd(mae)
  )

cat(sprintf("\nCV Results (SEM baseline):\n"))
cat(sprintf("R² = %.3f ± %.3f\n", cv_summary$r2_mean, cv_summary$r2_sd))
cat(sprintf("RMSE = %.3f ± %.3f\n", cv_summary$rmse_mean, cv_summary$rmse_sd))
cat(sprintf("MAE = %.3f ± %.3f\n", cv_summary$mae_mean, cv_summary$mae_sd))

# ============================================================================
# SECTION 6: AUGMENT WITH BIOCLIM
# ============================================================================

cat("\n==========================================\n")
cat("Stage 2: Augmenting with Bioclim\n")
cat("==========================================\n\n")

# Load bioclim data
climate_summary <- read_csv(CONFIG$bioclim_summary, show_col_types = FALSE)

# Normalize species names for matching
normalize_species <- function(x) {
  tolower(gsub("[[:space:]_-]+", "_", x))
}

climate_data <- climate_summary %>%
  filter(has_sufficient_data == TRUE) %>%
  mutate(species_norm = normalize_species(species)) %>%
  select(
    species_norm,
    # Temperature
    mat_mean = bio1_mean,
    temp_seasonality = bio4_mean,
    temp_range = bio7_mean,
    # Moisture
    precip_mean = bio12_mean,
    precip_seasonality = bio15_mean,
    drought_min = bio14_mean
  )

# Merge with trait data
augmented_data <- work_data %>%
  mutate(species_norm = normalize_species(species)) %>%
  inner_join(climate_data, by = "species_norm")

cat(sprintf("Species with both traits and climate: %d\n", nrow(augmented_data)))

# Test different augmentation strategies
augmentation_formulas <- list(
  baseline = sem_formula,
  
  # Add main climate effects
  climate_main = update(sem_formula, ~ . + mat_mean + precip_mean),
  
  # Add climate with seasonality
  climate_full = update(sem_formula, ~ . + mat_mean + temp_seasonality + 
                        precip_mean + precip_seasonality),
  
  # Add trait-climate interactions
  climate_interact = update(sem_formula, ~ . + mat_mean + precip_mean +
                           LES:mat_mean + logSSD:precip_mean)
)

# Fit each augmented model
augmented_results <- list()

for (model_name in names(augmentation_formulas)) {
  formula <- augmentation_formulas[[model_name]]
  
  if (CONFIG$use_gam_L && CONFIG$target_axis == "L") {
    model <- gam(formula, data = augmented_data, family = gaussian())
  } else {
    model <- lm(formula, data = augmented_data)
  }
  
  pred <- predict(model, augmented_data)
  r2 <- cor(pred, augmented_data$y)^2
  aic <- AIC(model)
  
  augmented_results[[model_name]] <- list(
    model = model,
    r2 = r2,
    aic = aic,
    n_params = length(coef(model))
  )
  
  cat(sprintf("%-20s: R² = %.3f, AIC = %.1f\n", model_name, r2, aic))
}

# Select best model by AIC
best_model_name <- names(which.min(sapply(augmented_results, function(x) x$aic)))
best_model <- augmented_results[[best_model_name]]

cat(sprintf("\nBest model by AIC: %s\n", best_model_name))
cat(sprintf("Improvement over baseline: +%.1f%%\n", 
            100 * (best_model$r2 - augmented_results$baseline$r2) / 
            augmented_results$baseline$r2))

# ============================================================================
# SECTION 7: SAVE RESULTS
# ============================================================================

results_summary <- list(
  metadata = list(
    target = CONFIG$target,
    target_axis = CONFIG$target_axis,
    timestamp = Sys.time(),
    n_species_traits = nrow(work_data),
    n_species_augmented = nrow(augmented_data)
  ),
  
  sem_baseline = list(
    formula = deparse(sem_formula),
    r2_full = baseline_r2,
    r2_cv = cv_summary$r2_mean,
    r2_cv_sd = cv_summary$r2_sd,
    expected_r2 = expected_r2[[CONFIG$target_axis]],
    achievement_ratio = baseline_r2 / expected_r2[[CONFIG$target_axis]]
  ),
  
  augmented_models = lapply(augmented_results, function(x) {
    list(r2 = x$r2, aic = x$aic, n_params = x$n_params)
  }),
  
  best_model = best_model_name,
  
  improvement = list(
    absolute = best_model$r2 - augmented_results$baseline$r2,
    relative_pct = 100 * (best_model$r2 - augmented_results$baseline$r2) / 
                   augmented_results$baseline$r2
  )
)

# Save outputs
write_json(results_summary,
          file.path(CONFIG$output_dir, sprintf("sem_augmented_results_%s.json", 
                                               CONFIG$target_axis)),
          pretty = TRUE, auto_unbox = TRUE)

write_csv(cv_df, file.path(CONFIG$output_dir, 
                           sprintf("cv_results_%s.csv", CONFIG$target_axis)))

saveRDS(best_model$model, file.path(CONFIG$output_dir,
                                    sprintf("best_augmented_model_%s.rds", 
                                           CONFIG$target_axis)))

cat(sprintf("\nResults saved to: %s\n", CONFIG$output_dir))

# ============================================================================
# FINAL SUMMARY
# ============================================================================

cat("\n==========================================\n")
cat("SUMMARY\n")
cat("==========================================\n\n")

cat(sprintf("Target: %s\n", CONFIG$target))
cat(sprintf("SEM Baseline R²: %.3f (expected: %.3f)\n", 
            baseline_r2, expected_r2[[CONFIG$target_axis]]))
cat(sprintf("Best Augmented R²: %.3f\n", best_model$r2))
cat(sprintf("Total Improvement: +%.1f%%\n", 
            100 * (best_model$r2 - baseline_r2) / baseline_r2))

if (baseline_r2 < 0.9 * expected_r2[[CONFIG$target_axis]]) {
  cat("\n⚠ Warning: Baseline R² is >10% below expected Run 7 value\n")
  cat("  Check composite construction and formula specification\n")
}

cat("\n✓ Using proven SEM equations as baseline\n")
cat("✓ Augmenting with bioclim variables\n")
cat("✓ Following structured regression approach\n")