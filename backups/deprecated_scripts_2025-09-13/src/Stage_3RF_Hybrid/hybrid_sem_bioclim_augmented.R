#!/usr/bin/env Rscript

# Augmented SEM-Bioclim Hybrid Model
# Uses proven SEM equations as baseline, augments with bioclim variables
# Implements structured regression approach with multicollinearity handling

suppressPackageStartupMessages({
  library(optparse)
  library(tidyverse)
  library(car)      # for VIF
  library(jsonlite) # for JSON output
})

# Command line arguments
option_list <- list(
  make_option("--target", type = "character", default = "M",
              help = "Target EIVE axis: M, T, R, N, or L"),
  make_option("--cv_folds", type = "integer", default = 10,
              help = "Number of CV folds"),
  make_option("--cv_repeats", type = "integer", default = 5,
              help = "Number of CV repeats"),
  make_option("--vif_threshold", type = "numeric", default = 5,
              help = "VIF threshold for multicollinearity"),
  make_option("--bootstrap_n", type = "integer", default = 100,
              help = "Number of bootstrap samples for stability")
)

opt <- parse_args(OptionParser(option_list = option_list))
target <- opt$target

cat("=== Augmented SEM-Bioclim Hybrid Model ===\n")
cat(sprintf("Target: %s\n", target))
cat(sprintf("CV: %d-fold × %d repeats\n", opt$cv_folds, opt$cv_repeats))
cat(sprintf("VIF threshold: %.1f\n", opt$vif_threshold))
cat(sprintf("Bootstrap samples: %d\n\n", opt$bootstrap_n))

# Load merged trait-bioclim data
data_path <- "/home/olier/ellenberg/artifacts/model_data_trait_bioclim_merged.csv"
data <- read.csv(data_path, stringsAsFactors = FALSE)

# Fix column names if needed
if ("Nmass__mg_g_" %in% names(data)) {
  data$Nmass <- data$Nmass__mg_g_
}

# Select relevant columns  
trait_cols <- c("LMA", "Nmass", "LA", "H", "SM", "SSD")
bioclim_cols <- paste0("bio", 1:19)
target_col <- target

# Filter to complete cases
keep_cols <- c(trait_cols, bioclim_cols, target_col, "wfo_accepted_name", "Family", "Myco_Group_Final")
data_clean <- data[, keep_cols[keep_cols %in% names(data)]]
data_clean <- data_clean[complete.cases(data_clean), ]

cat(sprintf("Data: %d species with complete trait and bioclim data\n\n", nrow(data_clean)))

# Build composites function (matching original SEM approach)
build_composites <- function(train, test) {
  # LES composite from {-LMA, Nmass}
  Mtr_raw <- data.frame(negLMA = -train$LMA, Nmass = train$Nmass)
  M_LES_tr <- scale(as.matrix(Mtr_raw), center = TRUE, scale = TRUE)
  p_les <- prcomp(M_LES_tr, center = FALSE, scale. = FALSE)
  
  Mte_raw <- data.frame(negLMA = -test$LMA, Nmass = test$Nmass)
  M_LES_te <- scale(as.matrix(Mte_raw), 
                    center = attr(M_LES_tr, "scaled:center"),
                    scale = attr(M_LES_tr, "scaled:scale"))
  
  train$LES <- p_les$x[, 1]
  test$LES <- predict(p_les, M_LES_te)[, 1]
  
  # SIZE composite from {logH, logSM} if needed
  if (target %in% c("T", "R")) {
    Mtr_size <- data.frame(logH = log10(train$H), logSM = log10(train$SM))
    M_SIZE_tr <- scale(as.matrix(Mtr_size), center = TRUE, scale = TRUE)
    p_size <- prcomp(M_SIZE_tr, center = FALSE, scale. = FALSE)
    
    Mte_size <- data.frame(logH = log10(test$H), logSM = log10(test$SM))
    M_SIZE_te <- scale(as.matrix(Mte_size),
                       center = attr(M_SIZE_tr, "scaled:center"),
                       scale = attr(M_SIZE_tr, "scaled:scale"))
    
    train$SIZE <- p_size$x[, 1]
    test$SIZE <- predict(p_size, M_SIZE_te)[, 1]
  }
  
  # Log transforms
  train$logLA <- log10(train$LA)
  train$logH <- log10(train$H)
  train$logSM <- log10(train$SM)
  train$logSSD <- log10(train$SSD)
  
  test$logLA <- log10(test$LA)
  test$logH <- log10(test$H)
  test$logSM <- log10(test$SM)
  test$logSSD <- log10(test$SSD)
  
  return(list(train = train, test = test))
}

# Get base SEM formula for each axis (from proven equations)
get_base_formula <- function(target) {
  if (target == "M") {
    return("y ~ LES + logH + logSM + logSSD + logLA")
  } else if (target == "T") {
    return("y ~ LES + SIZE + logSSD + logLA")
  } else if (target == "R") {
    return("y ~ LES + SIZE + logSSD + logLA")
  } else if (target == "N") {
    return("y ~ LES + logH + logSM + logSSD + logLA + LES:logSSD")
  } else if (target == "L") {
    # Simplified linear version for now
    return("y ~ LES + logH + logSSD + logLA + LMA:logLA")
  }
}

# Multicollinearity handling with VIF
check_vif <- function(model, threshold = 5) {
  vif_vals <- vif(model)
  high_vif <- names(vif_vals[vif_vals > threshold])
  return(list(vif = vif_vals, high_vif = high_vif))
}

# Remove correlated bioclim variables
filter_bioclim_by_correlation <- function(data, bioclim_cols, threshold = 0.9) {
  bio_data <- data[, bioclim_cols]
  cor_mat <- cor(bio_data, use = "complete.obs")
  
  # Find highly correlated pairs
  high_cor <- which(abs(cor_mat) > threshold & upper.tri(cor_mat), arr.ind = TRUE)
  
  # Keep variables with lower average correlation
  to_remove <- c()
  for (i in seq_len(nrow(high_cor))) {
    var1 <- colnames(cor_mat)[high_cor[i, 1]]
    var2 <- colnames(cor_mat)[high_cor[i, 2]]
    
    avg_cor1 <- mean(abs(cor_mat[var1, ]), na.rm = TRUE)
    avg_cor2 <- mean(abs(cor_mat[var2, ]), na.rm = TRUE)
    
    if (avg_cor1 > avg_cor2) {
      to_remove <- c(to_remove, var1)
    } else {
      to_remove <- c(to_remove, var2)
    }
  }
  
  to_remove <- unique(to_remove)
  keep_cols <- setdiff(bioclim_cols, to_remove)
  
  cat(sprintf("Removed %d highly correlated bioclim variables\n", length(to_remove)))
  cat(sprintf("Keeping: %s\n", paste(keep_cols, collapse = ", ")))
  
  return(keep_cols)
}

# Bootstrap stability testing
bootstrap_stability <- function(data, formula, n_boot = 100) {
  coef_matrix <- matrix(NA, nrow = n_boot, ncol = length(coef(lm(formula, data = data))))
  colnames(coef_matrix) <- names(coef(lm(formula, data = data)))
  
  for (i in 1:n_boot) {
    boot_idx <- sample(nrow(data), replace = TRUE)
    boot_data <- data[boot_idx, ]
    
    tryCatch({
      model <- lm(formula, data = boot_data)
      coef_matrix[i, ] <- coef(model)
    }, error = function(e) {
      # Skip if model fails
    })
  }
  
  # Calculate stability metrics
  coef_means <- colMeans(coef_matrix, na.rm = TRUE)
  coef_sds <- apply(coef_matrix, 2, sd, na.rm = TRUE)
  coef_cv <- abs(coef_sds / coef_means)
  
  # Variables with CV < 0.5 are considered stable
  stable_vars <- names(coef_cv[coef_cv < 0.5 & !is.na(coef_cv)])
  
  return(list(
    coef_matrix = coef_matrix,
    coef_means = coef_means,
    coef_cv = coef_cv,
    stable_vars = stable_vars
  ))
}

# Create folds manually (replacement for caret::createFolds)
create_folds <- function(y, k = 10) {
  n <- length(y)
  idx <- sample(1:n)
  fold_size <- ceiling(n / k)
  folds <- list()
  
  for (i in 1:k) {
    start_idx <- (i - 1) * fold_size + 1
    end_idx <- min(i * fold_size, n)
    folds[[paste0("Fold", i)]] <- idx[start_idx:end_idx]
  }
  
  return(folds)
}

# Main CV loop
set.seed(123)
cv_results <- list()

# Filter bioclim variables first
selected_bioclim <- filter_bioclim_by_correlation(data_clean, bioclim_cols, threshold = 0.9)

for (repeat_i in 1:opt$cv_repeats) {
  folds <- create_folds(data_clean[[target]], k = opt$cv_folds)
  
  for (fold_i in seq_along(folds)) {
    test_idx <- folds[[fold_i]]
    train_data <- data_clean[-test_idx, ]
    test_data <- data_clean[test_idx, ]
    
    # Build composites
    comp_data <- build_composites(train_data, test_data)
    train_data <- comp_data$train
    test_data <- comp_data$test
    
    # Standardize predictors within fold
    trait_pred_cols <- c("LES", "logH", "logSM", "logSSD", "logLA")
    if (target %in% c("T", "R")) {
      trait_pred_cols <- c("LES", "SIZE", "logSSD", "logLA")
    }
    
    # Standardize traits
    for (col in trait_pred_cols) {
      if (col %in% names(train_data)) {
        train_mean <- mean(train_data[[col]], na.rm = TRUE)
        train_sd <- sd(train_data[[col]], na.rm = TRUE)
        train_data[[col]] <- (train_data[[col]] - train_mean) / train_sd
        test_data[[col]] <- (test_data[[col]] - train_mean) / train_sd
      }
    }
    
    # Standardize bioclim
    for (col in selected_bioclim) {
      if (col %in% names(train_data)) {
        train_mean <- mean(train_data[[col]], na.rm = TRUE)
        train_sd <- sd(train_data[[col]], na.rm = TRUE)
        train_data[[col]] <- (train_data[[col]] - train_mean) / train_sd
        test_data[[col]] <- (test_data[[col]] - train_mean) / train_sd
      }
    }
    
    train_data$y <- train_data[[target]]
    test_data$y <- test_data[[target]]
    
    # Start with base SEM formula
    base_formula <- get_base_formula(target)
    
    # Fit base model
    base_model <- lm(as.formula(base_formula), data = train_data)
    base_r2 <- summary(base_model)$r.squared
    
    # Try adding bioclim variables one by one, keeping those that improve AIC
    current_formula <- base_formula
    current_model <- base_model
    current_aic <- AIC(current_model)
    
    for (bio_var in selected_bioclim) {
      test_formula <- paste(current_formula, "+", bio_var)
      test_model <- lm(as.formula(test_formula), data = train_data)
      test_aic <- AIC(test_model)
      
      # Check VIF
      vif_check <- tryCatch({
        check_vif(test_model, threshold = opt$vif_threshold)
      }, error = function(e) {
        list(high_vif = bio_var)  # Mark as high VIF if check fails
      })
      
      # Keep if improves AIC and doesn't violate VIF
      if (test_aic < current_aic && length(vif_check$high_vif) == 0) {
        current_formula <- test_formula
        current_model <- test_model
        current_aic <- test_aic
        cat(sprintf("  Added %s (AIC: %.1f -> %.1f)\n", bio_var, current_aic, test_aic))
      }
    }
    
    # Final model
    final_model <- current_model
    
    # Make predictions
    preds <- predict(final_model, newdata = test_data)
    
    # Calculate metrics
    r2 <- 1 - sum((test_data$y - preds)^2) / sum((test_data$y - mean(test_data$y))^2)
    rmse <- sqrt(mean((test_data$y - preds)^2))
    mae <- mean(abs(test_data$y - preds))
    
    cv_results[[length(cv_results) + 1]] <- list(
      repeat_i = repeat_i,
      fold_i = fold_i,
      r2 = r2,
      rmse = rmse,
      mae = mae,
      base_r2 = base_r2,
      formula = as.character(formula(final_model))[3],
      n_bioclim = length(grep("bio", all.vars(formula(final_model)), value = TRUE))
    )
    
    cat(sprintf("Repeat %d, Fold %d: R²=%.3f (base=%.3f), RMSE=%.3f, Bioclim vars=%d\n",
                repeat_i, fold_i, r2, base_r2, rmse, cv_results[[length(cv_results)]]$n_bioclim))
  }
}

# Aggregate results
results_df <- do.call(rbind, lapply(cv_results, as.data.frame))

cat("\n=== Final Results ===\n")
cat(sprintf("Base R² (traits only): %.3f ± %.3f\n",
            mean(results_df$base_r2), sd(results_df$base_r2)))
cat(sprintf("Augmented R²: %.3f ± %.3f\n",
            mean(results_df$r2), sd(results_df$r2)))
cat(sprintf("Improvement: +%.1f%%\n",
            100 * (mean(results_df$r2) - mean(results_df$base_r2)) / mean(results_df$base_r2)))
cat(sprintf("RMSE: %.3f ± %.3f\n",
            mean(results_df$rmse), sd(results_df$rmse)))
cat(sprintf("MAE: %.3f ± %.3f\n",
            mean(results_df$mae), sd(results_df$mae)))
cat(sprintf("Avg bioclim vars used: %.1f\n", mean(results_df$n_bioclim)))

# Save results
output_dir <- sprintf("artifacts/hybrid_sem_bioclim_augmented_%s", target)
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

write.csv(results_df, file.path(output_dir, "cv_results.csv"), row.names = FALSE)

# Save summary
summary_json <- list(
  target = target,
  n_species = nrow(data_clean),
  cv_folds = opt$cv_folds,
  cv_repeats = opt$cv_repeats,
  base_r2_mean = mean(results_df$base_r2),
  base_r2_sd = sd(results_df$base_r2),
  augmented_r2_mean = mean(results_df$r2),
  augmented_r2_sd = sd(results_df$r2),
  improvement_pct = 100 * (mean(results_df$r2) - mean(results_df$base_r2)) / mean(results_df$base_r2),
  rmse_mean = mean(results_df$rmse),
  rmse_sd = sd(results_df$rmse),
  mae_mean = mean(results_df$mae),
  mae_sd = sd(results_df$mae),
  avg_bioclim_vars = mean(results_df$n_bioclim),
  selected_bioclim = selected_bioclim
)

jsonlite::write_json(summary_json, file.path(output_dir, "summary.json"), pretty = TRUE)

cat(sprintf("\nResults saved to %s\n", output_dir))