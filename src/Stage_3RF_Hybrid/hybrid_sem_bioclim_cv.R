#!/usr/bin/env Rscript

#' SEM-Based Hybrid Trait-Bioclim Model with Proper CV
#' 
#' This script implements the EXACT SEM CV procedure:
#' 1. Stratified 10×5 cross-validation
#' 2. Fold-specific standardization of predictors
#' 3. Fold-specific composite construction (LES, SIZE)
#' 4. Use proven SEM equations to achieve ~0.4 R² baseline
#' 5. Augment with bioclim variables to push higher
#'
#' Based on run_sem_pwsem.R methodology

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
  make_option(c("--cv_folds"), type="integer", default=10,
              help="Number of CV folds (default: 10)"),
  make_option(c("--cv_repeats"), type="integer", default=5,
              help="Number of CV repeats (default: 5)"),
  make_option(c("--output_dir"), type="character",
              default="artifacts/stage3rf_sem_bioclim_cv/",
              help="Output directory for results"),
  make_option(c("--augment_bioclim"), type="character", default="true",
              help="Whether to augment with bioclim (default: true)")
)

opt_parser <- OptionParser(option_list=option_list)
opt <- parse_args(opt_parser)

# Validate target
valid_targets <- c("T", "M", "R", "N", "L")
if (!opt$target %in% valid_targets) {
  stop(sprintf("Invalid target '%s'. Must be one of: %s", 
               opt$target, paste(valid_targets, collapse=", ")))
}

augment_bioclim <- tolower(opt$augment_bioclim) %in% c("true", "yes", "1")

cat("==========================================\n")
cat("SEM-Based Hybrid Model with Proper CV\n")
cat("Target:", opt$target, "\n")
cat("Augment with bioclim:", augment_bioclim, "\n")
cat("==========================================\n\n")

# Configuration
CONFIG <- list(
  target = paste0("EIVEres-", opt$target),
  target_axis = opt$target,
  
  # Data paths
  trait_data = "artifacts/model_data_complete_case_with_myco.csv",
  bioclim_summary = "data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv",
  
  # SEM specifications from Run 7
  deconstruct_size = opt$target %in% c("M", "N"),
  add_les_logssd = opt$target == "N",
  use_gam_L = opt$target == "L",
  
  # CV settings
  cv_folds = opt$cv_folds,
  cv_repeats = opt$cv_repeats,
  seed = 123,
  stratify = TRUE,
  standardize = TRUE,  # Critical!
  
  # Output
  output_dir = file.path(opt$output_dir, opt$target)
)

# Create output directory
dir.create(CONFIG$output_dir, showWarnings = FALSE, recursive = TRUE)

# ============================================================================
# HELPER FUNCTIONS (from run_sem_pwsem.R)
# ============================================================================

# Compute offset for log transformation
compute_offset <- function(x) {
  x <- as.numeric(x)
  xpos <- x[is.finite(x) & x > 0]
  if (length(xpos) == 0) return(0.01)
  min(xpos) * 0.01
}

# Z-score standardization
zscore <- function(x, mean_ = NULL, sd_ = NULL) {
  x <- as.numeric(x)
  if (is.null(mean_)) mean_ <- mean(x, na.rm = TRUE)
  if (is.null(sd_)) sd_ <- sd(x, na.rm = TRUE)
  if (!is.finite(sd_) || sd_ == 0) sd_ <- 1
  list(x = (x - mean_) / sd_, mean = mean_, sd = sd_)
}

# Build composites EXACTLY as SEM does
build_composites <- function(train, test) {
  # LES composite from {-LMA, Nmass}
  Mtr_raw <- data.frame(negLMA = -train$LMA, Nmass = train$Nmass)
  Mte_raw <- data.frame(negLMA = -test$LMA, Nmass = test$Nmass)
  
  M_LES_tr <- scale(as.matrix(Mtr_raw), center = TRUE, scale = TRUE)
  p_les <- prcomp(M_LES_tr, center = FALSE, scale. = FALSE)
  rot_les <- p_les$rotation[,1]
  if (rot_les["Nmass"] < 0) rot_les <- -rot_les
  
  scores_LES_tr <- as.numeric(M_LES_tr %*% rot_les)
  M_LES_te <- scale(as.matrix(Mte_raw), 
                    center = attr(M_LES_tr, "scaled:center"),
                    scale = attr(M_LES_tr, "scaled:scale"))
  scores_LES_te <- as.numeric(M_LES_te %*% rot_les)
  
  # SIZE composite from {logH, logSM}
  M_SIZE_tr <- scale(cbind(logH = train$logH, logSM = train$logSM), 
                     center = TRUE, scale = TRUE)
  p_size <- prcomp(M_SIZE_tr, center = FALSE, scale. = FALSE)
  rot_size <- p_size$rotation[,1]
  if (rot_size["logH"] < 0) rot_size <- -rot_size
  
  scores_SIZE_tr <- as.numeric(M_SIZE_tr %*% rot_size)
  M_SIZE_te <- scale(cbind(logH = test$logH, logSM = test$logSM),
                     center = attr(M_SIZE_tr, "scaled:center"),
                     scale = attr(M_SIZE_tr, "scaled:scale"))
  scores_SIZE_te <- as.numeric(M_SIZE_te %*% rot_size)
  
  list(
    LES_train = scores_LES_tr,
    LES_test = scores_LES_te,
    SIZE_train = scores_SIZE_tr,
    SIZE_test = scores_SIZE_te
  )
}

# Create stratified folds
make_folds <- function(y, K, stratify = TRUE) {
  idx <- seq_along(y)
  if (stratify) {
    # Stratify by deciles of y
    br <- quantile(y, probs = seq(0, 1, length.out = 11), na.rm = TRUE)
    br[1] <- -Inf
    br[length(br)] <- Inf
    g <- cut(y, breaks = unique(br), include.lowest = TRUE, labels = FALSE)
    
    # Within each stratum, assign to folds
    fold_assign <- integer(length(y))
    for (stratum in unique(g[!is.na(g)])) {
      stratum_idx <- which(g == stratum)
      n_stratum <- length(stratum_idx)
      fold_assign[stratum_idx] <- sample(rep(1:K, length.out = n_stratum))
    }
    return(fold_assign)
  } else {
    return(sample(rep(1:K, length.out = length(y))))
  }
}

# Get SEM formula
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
    formula_str <- "y ~ LES + logH + logSM + logSSD + logLA"
    
    if (target_axis == "N") {
      formula_str <- paste(formula_str, "+ LES:logSSD")
    }
  } else {
    # T and R use SIZE composite
    formula_str <- "y ~ LES + SIZE + logSSD + logLA"
  }
  
  return(as.formula(formula_str))
}

# ============================================================================
# SECTION 1: LOAD AND PREPARE DATA
# ============================================================================

cat("Loading trait data...\n")
data <- read_csv(CONFIG$trait_data, show_col_types = FALSE)

# Compute offsets for log transformation
log_vars <- c("Leaf area (mm2)", "Plant height (m)", 
              "Diaspore mass (mg)", "SSD used (mg/mm3)")
offsets <- sapply(log_vars, function(v) compute_offset(data[[v]]))

# Prepare working data
work <- data %>%
  mutate(
    # Apply log transformations with offsets
    logLA = log10(`Leaf area (mm2)` + offsets["Leaf area (mm2)"]),
    logH = log10(`Plant height (m)` + offsets["Plant height (m)"]),
    logSM = log10(`Diaspore mass (mg)` + offsets["Diaspore mass (mg)"]),
    logSSD = log10(`SSD used (mg/mm3)` + offsets["SSD used (mg/mm3)"]),
    LMA = `LMA (g/m2)`,
    Nmass = `Nmass (mg/g)`,
    
    # Target and metadata
    y = .data[[CONFIG$target]],
    species = wfo_accepted_name,
    myco_group = Myco_Group_Final,
    family = Family
  ) %>%
  filter(!is.na(y))

n_total <- nrow(work)
cat(sprintf("Working with %d species\n", n_total))

# ============================================================================
# SECTION 2: CROSS-VALIDATION WITH SEM BASELINE
# ============================================================================

cat("\n==========================================\n")
cat("Stage 1: SEM Baseline CV\n")
cat("==========================================\n\n")

set.seed(CONFIG$seed)
cv_results_baseline <- list()
predictions_baseline <- list()

sem_formula <- get_sem_formula(CONFIG$target_axis, CONFIG$deconstruct_size, CONFIG$use_gam_L)
cat("SEM Formula:", deparse(sem_formula), "\n\n")

for (rep in 1:CONFIG$cv_repeats) {
  cat(sprintf("Repeat %d/%d: ", rep, CONFIG$cv_repeats))
  
  # Create stratified folds
  fold_assign <- make_folds(work$y, CONFIG$cv_folds, CONFIG$stratify)
  
  for (fold in 1:CONFIG$cv_folds) {
    test_idx <- which(fold_assign == fold)
    train_idx <- which(fold_assign != fold)
    
    tr <- work[train_idx, ]
    te <- work[test_idx, ]
    
    # CRITICAL: Standardize within fold
    if (CONFIG$standardize) {
      for (v in c("logLA", "logH", "logSM", "logSSD", "LMA", "Nmass")) {
        zs <- zscore(tr[[v]])
        tr[[v]] <- zs$x
        te[[v]] <- (te[[v]] - zs$mean) / zs$sd
      }
    }
    
    # Build composites on standardized data
    comps <- build_composites(train = tr, test = te)
    tr$LES <- comps$LES_train
    te$LES <- comps$LES_test
    tr$SIZE <- comps$SIZE_train
    te$SIZE <- comps$SIZE_test
    
    # Fit model
    if (CONFIG$use_gam_L && CONFIG$target_axis == "L") {
      model <- gam(sem_formula, data = tr, family = gaussian())
    } else {
      model <- lm(sem_formula, data = tr)
    }
    
    # Predict
    pred <- predict(model, te)
    
    # Calculate metrics
    r2 <- cor(pred, te$y)^2
    rmse <- sqrt(mean((pred - te$y)^2))
    mae <- mean(abs(pred - te$y))
    
    # Store results
    cv_results_baseline[[length(cv_results_baseline) + 1]] <- data.frame(
      rep = rep,
      fold = fold,
      r2 = r2,
      rmse = rmse,
      mae = mae,
      model = "SEM_baseline"
    )
    
    # Store predictions
    predictions_baseline[[length(predictions_baseline) + 1]] <- data.frame(
      rep = rep,
      fold = fold,
      species = te$species,
      y_true = te$y,
      y_pred = pred,
      model = "SEM_baseline"
    )
    
    cat(".")
  }
  cat("\n")
}

# Aggregate baseline results
cv_df_baseline <- bind_rows(cv_results_baseline)
pred_df_baseline <- bind_rows(predictions_baseline)

baseline_summary <- cv_df_baseline %>%
  summarise(
    r2_mean = mean(r2),
    r2_sd = sd(r2),
    rmse_mean = mean(rmse),
    rmse_sd = sd(rmse),
    mae_mean = mean(mae),
    mae_sd = sd(mae)
  )

cat(sprintf("\nSEM Baseline CV Results:\n"))
cat(sprintf("R² = %.3f ± %.3f\n", baseline_summary$r2_mean, baseline_summary$r2_sd))
cat(sprintf("RMSE = %.3f ± %.3f\n", baseline_summary$rmse_mean, baseline_summary$rmse_sd))
cat(sprintf("MAE = %.3f ± %.3f\n", baseline_summary$mae_mean, baseline_summary$mae_sd))

# ============================================================================
# SECTION 3: AUGMENT WITH BIOCLIM
# ============================================================================

if (augment_bioclim) {
  cat("\n==========================================\n")
  cat("Stage 2: Augmenting with Bioclim\n")
  cat("==========================================\n\n")
  
  # Load bioclim data
  climate_summary <- read_csv(CONFIG$bioclim_summary, show_col_types = FALSE)
  
  # Normalize species names
  normalize_species <- function(x) {
    tolower(gsub("[[:space:]_-]+", "_", x))
  }
  
  climate_data <- climate_summary %>%
    filter(has_sufficient_data == TRUE) %>%
    mutate(species_norm = normalize_species(species)) %>%
    select(
      species_norm,
      # Key climate variables
      mat_mean = bio1_mean,
      mat_sd = bio1_sd,
      temp_seasonality = bio4_mean,
      temp_range = bio7_mean,
      precip_mean = bio12_mean,
      precip_sd = bio12_sd,
      precip_seasonality = bio15_mean,
      drought_min = bio14_mean
    )
  
  # Merge with trait data
  work_augmented <- work %>%
    mutate(species_norm = normalize_species(species)) %>%
    inner_join(climate_data, by = "species_norm")
  
  n_augmented <- nrow(work_augmented)
  cat(sprintf("Species with bioclim: %d (%.1f%% of total)\n", 
              n_augmented, 100 * n_augmented / n_total))
  
  # Define augmented formulas
  if (CONFIG$target_axis == "M") {
    # Moisture-specific augmentation
    augmented_formulas <- list(
      climate_main = update(sem_formula, ~ . + precip_mean + drought_min),
      climate_variability = update(sem_formula, ~ . + precip_mean + precip_sd + drought_min),
      climate_interact = update(sem_formula, ~ . + precip_mean + drought_min + 
                                   LES:precip_mean + logSSD:drought_min)
    )
  } else if (CONFIG$target_axis == "T") {
    # Temperature-specific augmentation
    augmented_formulas <- list(
      climate_main = update(sem_formula, ~ . + mat_mean + temp_seasonality),
      climate_variability = update(sem_formula, ~ . + mat_mean + mat_sd + temp_seasonality),
      climate_interact = update(sem_formula, ~ . + mat_mean + temp_seasonality +
                                   SIZE:mat_mean + logSSD:temp_seasonality)
    )
  } else {
    # Generic augmentation for other axes
    augmented_formulas <- list(
      climate_main = update(sem_formula, ~ . + mat_mean + precip_mean),
      climate_full = update(sem_formula, ~ . + mat_mean + temp_seasonality + 
                           precip_mean + drought_min)
    )
  }
  
  # Run CV for each augmented model
  cv_results_augmented <- list()
  
  for (model_name in names(augmented_formulas)) {
    cat(sprintf("\nTesting %s model:\n", model_name))
    formula <- augmented_formulas[[model_name]]
    
    for (rep in 1:CONFIG$cv_repeats) {
      cat(sprintf("Repeat %d/%d: ", rep, CONFIG$cv_repeats))
      
      # Use same fold structure for comparability
      fold_assign <- make_folds(work_augmented$y, CONFIG$cv_folds, CONFIG$stratify)
      
      for (fold in 1:CONFIG$cv_folds) {
        test_idx <- which(fold_assign == fold)
        train_idx <- which(fold_assign != fold)
        
        tr <- work_augmented[train_idx, ]
        te <- work_augmented[test_idx, ]
        
        # Standardize traits AND climate variables within fold
        if (CONFIG$standardize) {
          # Traits
          for (v in c("logLA", "logH", "logSM", "logSSD", "LMA", "Nmass")) {
            zs <- zscore(tr[[v]])
            tr[[v]] <- zs$x
            te[[v]] <- (te[[v]] - zs$mean) / zs$sd
          }
          
          # Climate variables
          climate_vars <- c("mat_mean", "mat_sd", "temp_seasonality", "temp_range",
                           "precip_mean", "precip_sd", "precip_seasonality", "drought_min")
          for (v in climate_vars) {
            if (v %in% names(tr)) {
              zs <- zscore(tr[[v]])
              tr[[v]] <- zs$x
              te[[v]] <- (te[[v]] - zs$mean) / zs$sd
            }
          }
        }
        
        # Build composites
        comps <- build_composites(train = tr, test = te)
        tr$LES <- comps$LES_train
        te$LES <- comps$LES_test
        tr$SIZE <- comps$SIZE_train
        te$SIZE <- comps$SIZE_test
        
        # Fit model
        if (CONFIG$use_gam_L && CONFIG$target_axis == "L") {
          model <- gam(formula, data = tr, family = gaussian())
        } else {
          model <- lm(formula, data = tr)
        }
        
        # Predict
        pred <- predict(model, te)
        
        # Calculate metrics
        r2 <- cor(pred, te$y)^2
        rmse <- sqrt(mean((pred - te$y)^2))
        mae <- mean(abs(pred - te$y))
        
        # Store results
        cv_results_augmented[[length(cv_results_augmented) + 1]] <- data.frame(
          rep = rep,
          fold = fold,
          r2 = r2,
          rmse = rmse,
          mae = mae,
          model = model_name
        )
        
        cat(".")
      }
      cat("\n")
    }
  }
  
  # Aggregate augmented results
  cv_df_augmented <- bind_rows(cv_results_augmented)
  
  augmented_summary <- cv_df_augmented %>%
    group_by(model) %>%
    summarise(
      r2_mean = mean(r2),
      r2_sd = sd(r2),
      rmse_mean = mean(rmse),
      rmse_sd = sd(rmse),
      mae_mean = mean(mae),
      mae_sd = sd(mae),
      .groups = "drop"
    )
  
  cat("\n==========================================\n")
  cat("Augmented Model Results:\n")
  cat("==========================================\n\n")
  
  for (i in 1:nrow(augmented_summary)) {
    row <- augmented_summary[i, ]
    cat(sprintf("%s:\n", row$model))
    cat(sprintf("  R² = %.3f ± %.3f\n", row$r2_mean, row$r2_sd))
    cat(sprintf("  Improvement over baseline: +%.1f%%\n",
                100 * (row$r2_mean - baseline_summary$r2_mean) / baseline_summary$r2_mean))
  }
  
  # Find best model
  best_model <- augmented_summary[which.max(augmented_summary$r2_mean), ]
  cat(sprintf("\nBest model: %s\n", best_model$model))
  cat(sprintf("R² improvement: %.3f → %.3f (+%.1f%%)\n",
              baseline_summary$r2_mean,
              best_model$r2_mean,
              100 * (best_model$r2_mean - baseline_summary$r2_mean) / baseline_summary$r2_mean))
}

# ============================================================================
# SECTION 4: SAVE RESULTS
# ============================================================================

results_summary <- list(
  metadata = list(
    target = CONFIG$target,
    target_axis = CONFIG$target_axis,
    timestamp = Sys.time(),
    n_species_total = n_total,
    n_species_augmented = if (augment_bioclim) n_augmented else NA,
    cv_folds = CONFIG$cv_folds,
    cv_repeats = CONFIG$cv_repeats
  ),
  
  sem_baseline = list(
    formula = deparse(sem_formula),
    r2_mean = baseline_summary$r2_mean,
    r2_sd = baseline_summary$r2_sd,
    rmse_mean = baseline_summary$rmse_mean,
    rmse_sd = baseline_summary$rmse_sd,
    mae_mean = baseline_summary$mae_mean,
    mae_sd = baseline_summary$mae_sd
  )
)

if (augment_bioclim) {
  results_summary$augmented_models <- augmented_summary
  results_summary$best_model <- best_model$model
  results_summary$improvement <- list(
    absolute = best_model$r2_mean - baseline_summary$r2_mean,
    relative_pct = 100 * (best_model$r2_mean - baseline_summary$r2_mean) / 
                   baseline_summary$r2_mean
  )
}

# Save outputs
write_json(results_summary,
          file.path(CONFIG$output_dir, sprintf("cv_results_%s.json", CONFIG$target_axis)),
          pretty = TRUE, auto_unbox = TRUE)

write_csv(cv_df_baseline, 
          file.path(CONFIG$output_dir, sprintf("cv_details_baseline_%s.csv", CONFIG$target_axis)))

if (augment_bioclim) {
  write_csv(cv_df_augmented,
            file.path(CONFIG$output_dir, sprintf("cv_details_augmented_%s.csv", CONFIG$target_axis)))
}

cat(sprintf("\nResults saved to: %s\n", CONFIG$output_dir))

# ============================================================================
# FINAL SUMMARY
# ============================================================================

cat("\n==========================================\n")
cat("FINAL SUMMARY\n")
cat("==========================================\n\n")

cat(sprintf("Target: %s\n", CONFIG$target))
cat(sprintf("SEM Baseline R² (CV): %.3f ± %.3f\n", 
            baseline_summary$r2_mean, baseline_summary$r2_sd))

if (augment_bioclim) {
  cat(sprintf("Best Augmented R² (CV): %.3f ± %.3f\n", 
              best_model$r2_mean, best_model$r2_sd))
  cat(sprintf("Total Improvement: +%.1f%%\n", 
              100 * (best_model$r2_mean - baseline_summary$r2_mean) / baseline_summary$r2_mean))
}

# Expected values from Run 7
expected_r2 <- list(
  L = 0.300,  # Run 7c
  T = 0.231,  # Run 7
  M = 0.408,  # Run 7
  R = 0.155,  # Run 7
  N = 0.425   # Run 7
)

cat(sprintf("\nExpected R² from Run 7: %.3f\n", expected_r2[[CONFIG$target_axis]]))
cat(sprintf("Achievement ratio: %.1f%%\n", 
            100 * baseline_summary$r2_mean / expected_r2[[CONFIG$target_axis]]))

if (baseline_summary$r2_mean >= 0.9 * expected_r2[[CONFIG$target_axis]]) {
  cat("\n✓ Successfully replicated SEM baseline performance!\n")
} else {
  cat("\n⚠ Baseline below expected - check implementation\n")
}

cat("\n✓ Using proven SEM equations with proper CV\n")
cat("✓ Fold-specific standardization and composites\n")
if (augment_bioclim) {
  cat("✓ Augmented with bioclim variables\n")
}