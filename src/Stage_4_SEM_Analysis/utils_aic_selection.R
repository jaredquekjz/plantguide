# Helper functions for AIC-based feature selection in pwSEM
# Based on Bill Shipley's methodology from Stage 3RF Hybrid

library(dplyr)

# Function to compute RF importance for all features
compute_rf_importance <- function(data, target_col, n_trees = 1000, seed = 123) {
  require(ranger)

  # Prepare data
  y <- data[[target_col]]

  # Exclude non-feature columns
  exclude_cols <- c(target_col, "wfo_accepted_name", "Family")
  X <- data[, !names(data) %in% exclude_cols, drop = FALSE]

  # Only keep numeric columns
  numeric_cols <- sapply(X, is.numeric)
  X <- X[, numeric_cols, drop = FALSE]

  # Remove columns with too many missing values (>50%)
  missing_prop <- colSums(is.na(X)) / nrow(X)
  keep_cols <- missing_prop < 0.5
  X <- X[, keep_cols, drop = FALSE]

  # Remove columns with no variation
  keep_cols <- apply(X, 2, function(x) {
    valid <- !is.na(x)
    if (sum(valid) < 2) return(FALSE)
    length(unique(x[valid])) > 1
  })
  X <- X[, keep_cols, drop = FALSE]

  # Complete cases only for RF
  complete_idx <- complete.cases(cbind(y, X))
  y_clean <- y[complete_idx]
  X_clean <- X[complete_idx, , drop = FALSE]

  message(sprintf("[RF] Training on %d complete cases with %d features",
                  sum(complete_idx), ncol(X_clean)))

  # Train RF
  set.seed(seed)
  rf_model <- ranger::ranger(
    x = X_clean,
    y = y_clean,
    num.trees = n_trees,
    importance = 'impurity',
    seed = seed
  )

  # Extract importance
  importance_df <- data.frame(
    feature = names(rf_model$variable.importance),
    rf_importance = as.numeric(rf_model$variable.importance),
    stringsAsFactors = FALSE
  ) %>%
    dplyr::arrange(dplyr::desc(rf_importance))

  message(sprintf("[RF] R² = %.3f (in-sample)", rf_model$r.squared))

  return(list(
    model = rf_model,
    importance = importance_df,
    r_squared = rf_model$r.squared
  ))
}

# Function to compute XGBoost importance using Python/conda
compute_xgb_importance <- function(data, target_col, n_rounds = 500, seed = 123) {

  # First pre-process data like RF does
  y <- data[[target_col]]

  # Exclude non-feature columns
  exclude_cols <- c(target_col, "wfo_accepted_name", "Family")
  X <- data[, !names(data) %in% exclude_cols, drop = FALSE]

  # Only keep numeric columns
  numeric_cols <- sapply(X, is.numeric)
  X <- X[, numeric_cols, drop = FALSE]

  # Remove columns with too many missing values (>50%)
  missing_prop <- colSums(is.na(X)) / nrow(X)
  keep_cols <- missing_prop < 0.5
  X <- X[, keep_cols, drop = FALSE]

  # Remove columns with no variation
  keep_cols <- apply(X, 2, function(x) {
    valid <- !is.na(x)
    if (sum(valid) < 2) return(FALSE)
    length(unique(x[valid])) > 1
  })
  X <- X[, keep_cols, drop = FALSE]

  # Combine back with target
  data_clean <- cbind(data.frame(y = y), X)

  # Write cleaned data to temporary file
  temp_data <- tempfile(fileext = ".csv")
  temp_output <- tempfile(fileext = ".csv")
  write.csv(data_clean, temp_data, row.names = FALSE)

  # Construct Python command
  python_script <- "src/Stage_4_SEM_Analysis/compute_xgb_importance.py"
  cmd <- sprintf(
    "conda run -n AI python %s --data %s --target %s --n_rounds %d --seed %d",
    python_script, temp_data, target_col, n_rounds, seed
  )

  # Call Python XGBoost
  message("[XGB] Computing importance via conda AI environment...")
  result <- system(cmd, intern = TRUE)

  # Parse the output (CSV format from stdout)
  con <- textConnection(result)
  importance_df <- read.csv(con, stringsAsFactors = FALSE)
  close(con)

  # Clean up temp files
  unlink(temp_data)

  # Check if we got valid results
  if (nrow(importance_df) == 0) {
    message("[XGB] Warning: No features selected (likely too few complete cases)")
    # Return empty but valid structure
    return(list(
      model = NULL,
      importance = data.frame(feature = character(), xgb_importance = numeric(), stringsAsFactors = FALSE),
      r_squared = NA
    ))
  }

  # Sort by importance
  importance_df <- importance_df %>%
    dplyr::arrange(dplyr::desc(xgb_importance))

  # Extract R² from stderr messages if available
  r_squared <- NA
  stderr_lines <- attr(result, "stderr")
  if (!is.null(stderr_lines)) {
    r2_line <- grep("R²", stderr_lines, value = TRUE)
    if (length(r2_line) > 0) {
      r_squared <- as.numeric(sub(".*R² = ([0-9.]+).*", "\\1", r2_line[1]))
    }
  }

  if (!is.na(r_squared)) {
    message(sprintf("[XGB] R² = %.3f (in-sample)", r_squared))
  }

  return(list(
    model = NULL,  # Model stays in Python
    importance = importance_df,
    r_squared = r_squared
  ))
}

# Alternative: Function to compute XGBoost importance using native R (fallback)
compute_xgb_importance_r <- function(data, target_col, n_rounds = 500, seed = 123) {
  # Original R implementation kept as fallback
  if (!requireNamespace("xgboost", quietly = TRUE)) {
    stop("xgboost package not available in R, and Python fallback failed")
  }

  require(xgboost)

  # Prepare data
  y <- data[[target_col]]
  X <- data[, !names(data) %in% c(target_col, "wfo_accepted_name", "Family"), drop = FALSE]

  # Remove columns with no variation
  keep_cols <- apply(X, 2, function(x) {
    valid <- !is.na(x)
    length(unique(x[valid])) > 1
  })
  X <- X[, keep_cols, drop = FALSE]

  # Complete cases only for XGBoost
  complete_idx <- complete.cases(cbind(y, X))
  y_clean <- y[complete_idx]
  X_clean <- X[complete_idx, , drop = FALSE]

  message(sprintf("[XGB] Training on %d complete cases with %d features",
                  sum(complete_idx), ncol(X_clean)))

  # Convert to DMatrix
  dtrain <- xgboost::xgb.DMatrix(data = as.matrix(X_clean), label = y_clean)

  # Train XGBoost
  set.seed(seed)
  xgb_model <- xgboost::xgb.train(
    params = list(
      objective = "reg:squarederror",
      eta = 0.1,
      max_depth = 6,
      subsample = 0.8,
      colsample_bytree = 0.8
    ),
    data = dtrain,
    nrounds = n_rounds,
    verbose = 0
  )

  # Extract importance (gain-based)
  importance_matrix <- xgboost::xgb.importance(
    model = xgb_model,
    feature_names = colnames(X_clean)
  )

  # Convert to dataframe format matching RF output
  importance_df <- data.frame(
    feature = importance_matrix$Feature,
    xgb_importance = importance_matrix$Gain,
    stringsAsFactors = FALSE
  ) %>%
    dplyr::arrange(dplyr::desc(xgb_importance))

  # Compute R² for comparison
  pred <- predict(xgb_model, dtrain)
  r_squared <- 1 - sum((y_clean - pred)^2) / sum((y_clean - mean(y_clean))^2)

  message(sprintf("[XGB] R² = %.3f (in-sample)", r_squared))

  return(list(
    model = xgb_model,
    importance = importance_df,
    r_squared = r_squared
  ))
}

# Function to combine RF and XGBoost importance scores
combine_importances <- function(rf_importance, xgb_importance, method = "average_rank") {

  # Handle empty dataframes
  if (nrow(rf_importance) == 0 && nrow(xgb_importance) == 0) {
    return(data.frame(
      feature = character(),
      combined_importance = numeric(),
      rf_importance = numeric(),
      xgb_importance = numeric(),
      stringsAsFactors = FALSE
    ))
  }

  if (nrow(rf_importance) == 0) {
    # Use only XGBoost
    return(data.frame(
      feature = xgb_importance$feature,
      combined_importance = xgb_importance$xgb_importance,
      rf_importance = 0,
      xgb_importance = xgb_importance$xgb_importance,
      stringsAsFactors = FALSE
    ) %>% dplyr::arrange(dplyr::desc(combined_importance)))
  }

  if (nrow(xgb_importance) == 0) {
    # Use only RF
    return(data.frame(
      feature = rf_importance$feature,
      combined_importance = rf_importance$rf_importance,
      rf_importance = rf_importance$rf_importance,
      xgb_importance = 0,
      stringsAsFactors = FALSE
    ) %>% dplyr::arrange(dplyr::desc(combined_importance)))
  }

  # Merge the two importance dataframes
  merged <- merge(
    rf_importance,
    xgb_importance,
    by = "feature",
    all = TRUE
  )

  # Fill missing values with 0 (features not selected by one method)
  merged$rf_importance[is.na(merged$rf_importance)] <- 0
  merged$xgb_importance[is.na(merged$xgb_importance)] <- 0

  if (method == "average_rank") {
    # Rank-based combination
    merged$rf_rank <- rank(-merged$rf_importance, ties.method = "average")
    merged$xgb_rank <- rank(-merged$xgb_importance, ties.method = "average")
    merged$combined_rank <- (merged$rf_rank + merged$xgb_rank) / 2
    merged$combined_importance <- -merged$combined_rank  # Lower rank = higher importance

  } else if (method == "average_normalized") {
    # Normalize to [0,1] and average
    rf_max <- max(merged$rf_importance, na.rm = TRUE)
    xgb_max <- max(merged$xgb_importance, na.rm = TRUE)

    if (rf_max > 0) {
      merged$rf_norm <- merged$rf_importance / rf_max
    } else {
      merged$rf_norm <- 0
    }

    if (xgb_max > 0) {
      merged$xgb_norm <- merged$xgb_importance / xgb_max
    } else {
      merged$xgb_norm <- 0
    }

    merged$combined_importance <- (merged$rf_norm + merged$xgb_norm) / 2

  } else if (method == "max") {
    # Take maximum of normalized scores
    rf_max <- max(merged$rf_importance, na.rm = TRUE)
    xgb_max <- max(merged$xgb_importance, na.rm = TRUE)

    merged$rf_norm <- ifelse(rf_max > 0, merged$rf_importance / rf_max, 0)
    merged$xgb_norm <- ifelse(xgb_max > 0, merged$xgb_importance / xgb_max, 0)
    merged$combined_importance <- pmax(merged$rf_norm, merged$xgb_norm)

  } else {
    stop("Unknown combination method. Use 'average_rank', 'average_normalized', or 'max'")
  }

  # Create final importance dataframe
  combined_df <- data.frame(
    feature = merged$feature,
    combined_importance = merged$combined_importance,
    rf_importance = merged$rf_importance,
    xgb_importance = merged$xgb_importance,
    stringsAsFactors = FALSE
  ) %>%
    dplyr::arrange(dplyr::desc(combined_importance))

  return(combined_df)
}

# Function to perform correlation clustering and select representatives
select_climate_representatives <- function(data, climate_vars, importance_df,
                                          cor_threshold = 0.8,
                                          offer_all = FALSE) {

  # Check which climate variables are present
  climate_present <- intersect(climate_vars, names(data))

  if (length(climate_present) == 0) {
    message("[Clustering] No climate variables found in data")
    return(character(0))
  }

  if (offer_all) {
    message(sprintf("[Clustering] Offering all %d climate variables (no clustering)",
                    length(climate_present)))
    return(climate_present)
  }

  # Compute correlation matrix
  cor_matrix <- cor(data[, climate_present, drop = FALSE],
                   use = "pairwise.complete.obs")

  # Handle NAs in correlation matrix
  cor_matrix[is.na(cor_matrix)] <- 0

  # Hierarchical clustering
  hc <- hclust(as.dist(1 - abs(cor_matrix)))
  clusters <- cutree(hc, h = 1 - cor_threshold)

  message(sprintf("[Clustering] Found %d correlation clusters among %d climate variables",
                  max(clusters), length(climate_present)))

  # Select representative from each cluster based on RF importance
  selected_climate <- character(0)

  for (cluster_id in unique(clusters)) {
    cluster_vars <- names(clusters)[clusters == cluster_id]

    # Find variable with highest importance
    cluster_importance <- importance_df %>%
      dplyr::filter(feature %in% cluster_vars) %>%
      dplyr::slice_max(rf_importance, n = 1)

    if (nrow(cluster_importance) > 0) {
      selected_climate <- c(selected_climate, cluster_importance$feature[1])

      if (length(cluster_vars) > 1) {
        message(sprintf("  Cluster %d: selected '%s' from {%s}",
                        cluster_id,
                        cluster_importance$feature[1],
                        paste(cluster_vars, collapse = ", ")))
      }
    } else {
      # If no importance score, take first variable
      selected_climate <- c(selected_climate, cluster_vars[1])
    }
  }

  return(selected_climate)
}

# Function to build candidate model formulas
build_candidate_formulas <- function(target_letter, trait_vars, climate_vars,
                                     interaction_vars = NULL, phylo_var = NULL) {

  formulas <- list()

  # Always include core SEM structure
  core_traits <- c("LES", "SIZE", "logSSD")
  extra_traits <- intersect(trait_vars, c("logLA", "Nmass", "LMA", "logH", "logSM"))

  # Model 1: Baseline (traits only)
  formulas$baseline <- paste("y ~", paste(c(core_traits, extra_traits), collapse = " + "))

  # Model 2: Traits + Climate main effects
  if (length(climate_vars) > 0) {
    formulas$climate <- paste("y ~",
                             paste(c(core_traits, extra_traits, climate_vars),
                                   collapse = " + "))
  }

  # Model 3: Full (with interactions)
  if (length(interaction_vars) > 0) {
    all_vars <- c(core_traits, extra_traits, climate_vars, interaction_vars)
    formulas$full <- paste("y ~", paste(all_vars, collapse = " + "))
  }

  # Model 4: GAM formulas (target-specific)
  if (target_letter == "T") {
    # Temperature-specific GAM
    gam_terms <- character(0)

    # Trait smooths
    if ("LES" %in% trait_vars) gam_terms <- c(gam_terms, "s(LES, k=5)")
    if ("SIZE" %in% trait_vars) gam_terms <- c(gam_terms, "s(SIZE, k=5)")

    # Climate smooths
    climate_smooth <- intersect(c("mat_mean", "temp_seasonality", "precip_seasonality"),
                                climate_vars)
    for (v in climate_smooth) {
      gam_terms <- c(gam_terms, sprintf("s(%s, k=5)", v))
    }

    # Interactions
    if (all(c("SIZE", "mat_mean") %in% c(trait_vars, climate_vars))) {
      gam_terms <- c(gam_terms, "ti(SIZE, mat_mean, k=c(4,4))")
    }

    # Linear terms
    linear_terms <- setdiff(c(extra_traits, "logSSD"),
                           c("LES", "SIZE"))
    gam_terms <- c(gam_terms, linear_terms)

    if (length(gam_terms) > 0) {
      formulas$gam <- paste("y ~", paste(gam_terms, collapse = " + "))
    }
  }

  # Add phylogenetic predictor to all models if available
  if (!is.null(phylo_var) && nzchar(phylo_var)) {
    for (model_name in names(formulas)) {
      formulas[[model_name]] <- paste(formulas[[model_name]], "+", phylo_var)
    }
  }

  return(formulas)
}

# Function to fit candidate models and compute AIC
fit_and_compare_models <- function(data, formulas, use_gam = TRUE) {
  require(MuMIn)

  models <- list()
  aic_values <- numeric(0)

  for (model_name in names(formulas)) {
    formula_str <- formulas[[model_name]]

    # Check if it's a GAM formula
    is_gam <- grepl("\\bs\\(|\\bti\\(|\\bt2\\(", formula_str)

    if (is_gam && use_gam) {
      require(mgcv)
      tryCatch({
        models[[model_name]] <- mgcv::gam(
          as.formula(formula_str),
          data = data,
          method = "REML"
        )
        aic_values[model_name] <- AIC(models[[model_name]])
      }, error = function(e) {
        message(sprintf("[AIC] Failed to fit GAM model '%s': %s",
                       model_name, e$message))
        aic_values[model_name] <- Inf
      })
    } else {
      tryCatch({
        models[[model_name]] <- lm(as.formula(formula_str), data = data)
        aic_values[model_name] <- AIC(models[[model_name]])
      }, error = function(e) {
        message(sprintf("[AIC] Failed to fit linear model '%s': %s",
                       model_name, e$message))
        aic_values[model_name] <- Inf
      })
    }
  }

  # Compute AIC weights
  valid_aic <- aic_values[is.finite(aic_values)]
  if (length(valid_aic) == 0) {
    stop("No models could be fitted successfully")
  }

  delta_aic <- aic_values - min(valid_aic)
  weights <- exp(-0.5 * delta_aic) / sum(exp(-0.5 * delta_aic[is.finite(delta_aic)]))

  comparison <- data.frame(
    model = names(aic_values),
    aic = aic_values,
    delta_aic = delta_aic,
    weight = weights,
    stringsAsFactors = FALSE
  ) %>%
    dplyr::arrange(aic)

  # Best model
  best_name <- comparison$model[1]

  return(list(
    models = models,
    comparison = comparison,
    best_model = models[[best_name]],
    best_name = best_name
  ))
}

# Function to get axis-specific climate variables
get_axis_climate_vars <- function(target_letter) {

  # Common climate variables
  base_climate <- c(
    "mat_mean", "mat_sd", "mat_q05", "mat_q95",
    "temp_seasonality", "temp_range",
    "tmax_mean", "tmin_mean", "tmin_q05",
    "precip_mean", "precip_cv", "precip_seasonality",
    "drought_min", "precip_driest_q", "precip_warmest_q", "precip_coldest_q"
  )

  # Aridity indices
  aridity_vars <- c(
    "ai_month_min", "ai_month_p10", "ai_roll3_min",
    "ai_dry_frac_t020", "ai_dry_run_max_t020",
    "ai_dry_frac_t050", "ai_dry_run_max_t050",
    "ai_amp", "ai_cv_month"
  )

  # Soil variables
  soil_vars <- c(
    "ph_rootzone_mean", "hplus_rootzone_mean",
    "phh2o_5_15cm_mean", "phh2o_5_15cm_p90"
  )

  # Combine based on axis
  if (target_letter == "T") {
    return(c(base_climate, aridity_vars))
  } else if (target_letter == "M") {
    return(c(base_climate, aridity_vars))
  } else if (target_letter == "L") {
    return(base_climate)
  } else if (target_letter == "N") {
    return(c(base_climate, aridity_vars))
  } else if (target_letter == "R") {
    return(c(base_climate, soil_vars))
  } else {
    return(c(base_climate, aridity_vars, soil_vars))
  }
}

# Function to get axis-specific interaction variables
get_axis_interactions <- function(target_letter) {
  if (target_letter == "T") {
    return(c("size_temp", "height_temp", "les_seasonality", "wood_cold", "lma_precip"))
  } else if (target_letter == "M") {
    return(c("lma_precip", "wood_precip", "size_precip", "les_drought"))
  } else if (target_letter == "L") {
    return(c("height_ssd", "lma_la"))
  } else if (target_letter == "N") {
    return(c("les_drought", "les_seasonality", "size_precip"))
  } else if (target_letter == "R") {
    return(c("ph_rootzone_mean", "drought_min"))
  } else {
    return(character(0))
  }
}