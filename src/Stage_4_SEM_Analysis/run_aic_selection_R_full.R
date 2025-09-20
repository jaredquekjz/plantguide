#!/usr/bin/env Rscript

# Full AIC Selection for R Axis (Reaction/pH) with ALL Features
# Includes critical soil pH features, cross-axis dependencies, and phylogenetic enhancement

library(tidyverse)
library(mgcv)
library(MuMIn)

set.seed(123)

cat("=== R Axis (Reaction/pH) Full Feature GAM Analysis ===\n")
cat("Including soil pH profiles, cross-axis dependencies, and phylogenetic enhancement\n\n")

# Load data
cat("Loading Stage 2 dataset...\n")
data <- read.csv(
  "artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv",
  check.names = FALSE,
  stringsAsFactors = FALSE
)

target_col <- "EIVEres-R"
target_response <- gsub("[^A-Za-z0-9_]", "_", target_col)

if (!(target_col %in% names(data))) {
  stop(sprintf("Target column %s not found in data", target_col))
}

# Filter to complete cases for target
data <- data[!is.na(data[[target_col]]), ]

# Create safe response column
if (!(target_response %in% names(data))) {
  data[[target_response]] <- data[[target_col]]
}

cat(sprintf("Working with %d complete cases for R axis\n", nrow(data)))

# Convert numeric columns
num_cols <- setdiff(names(data), c("Family", "is_woody", "wfo_accepted_name"))
if (length(num_cols)) {
  data[num_cols] <- lapply(data[num_cols], function(x) suppressWarnings(as.numeric(x)))
}
if ("is_woody" %in% names(data)) {
  data$is_woody <- factor(data$is_woody)
}

# Handle cross-axis dependency (EIVEres-N)
if ("EIVEres-N" %in% names(data)) {
  data$EIVEres_N <- data[["EIVEres-N"]]
  cat("Cross-axis dependency EIVEres-N available\n")
} else {
  data$EIVEres_N <- NULL
  cat("Warning: EIVEres-N not available (important cross-axis dependency)\n")
}

# Define comprehensive feature sets for R axis
# Trait features
trait_vars <- c(
  "logSM",                    # Stem mass (4.6% SHAP)
  "log_ldmc_minus_log_la",    # Trait ratio (3.7% SHAP)
  "logLA", "logH", "logSSD",  # Standard traits
  "LES_core", "SIZE",         # Composite traits
  "LDMC", "Nmass"             # Additional traits
)

# Soil pH features - CRITICAL for R axis!
ph_features <- c(
  "phh2o_5_15cm_p90",         # TOP PREDICTOR (10.5% SHAP)!
  "phh2o_5_15cm_mean",        # Mean surface pH (6.3% SHAP)
  "phh2o_0_5cm_mean",         # Top layer
  "phh2o_15_30cm_mean",       # Subsurface
  "phh2o_5_15cm_p10",         # Lower percentile
  "phh2o_0_5cm_p90",          # Top layer extreme
  "phh2o_15_30cm_p90"         # Subsurface extreme
)

# Climate features
climate_vars <- c(
  "mat_mean",                 # Mean annual temp (in pwSEM)
  "temp_range",               # Temperature range (in pwSEM)
  "drought_min",              # Drought minimum (in pwSEM)
  "precip_warmest_q",         # Summer precipitation (4.3% SHAP)
  "mat_q95",                  # Temperature extreme (2.2% SHAP)
  "ai_cv_month",              # Aridity variation (2.8% SHAP)
  "ai_amp",                   # Aridity amplitude (2.0% SHAP)
  "precip_mean",              # Mean precipitation
  "temp_seasonality"          # Temperature seasonality
)

# Interaction terms
interaction_vars <- c(
  "wood_precip",              # Woody × precipitation (3.0% SHAP)
  "height_temp",              # Height × temperature
  "lma_precip",               # LMA × precipitation
  "les_drought"               # LES × drought
)

# Phylogenetic predictor - STRONGEST signal for R axis!
phylo_var <- "p_phylo_R"

# Check feature availability
available_terms <- function(cols) cols[cols %in% names(data)]

cat("\n=== Feature Availability Check ===\n")
available_traits <- available_terms(trait_vars)
available_ph <- available_terms(ph_features)
available_climate <- available_terms(climate_vars)
available_interactions <- available_terms(interaction_vars)
has_phylo <- phylo_var %in% names(data)
has_cross_axis <- "EIVEres_N" %in% names(data)

cat(sprintf("Trait features: %d/%d available\n", length(available_traits), length(trait_vars)))
cat(sprintf("Soil pH features: %d/%d available\n", length(available_ph), length(ph_features)))
if (length(available_ph) == 0) {
  warning("CRITICAL: No soil pH features available - these are essential for R axis!")
}
cat(sprintf("Climate features: %d/%d available\n", length(available_climate), length(climate_vars)))
cat(sprintf("Interactions: %d/%d available\n", length(available_interactions), length(interaction_vars)))
cat(sprintf("Phylogenetic predictor: %s\n", ifelse(has_phylo, "Yes", "No")))
cat(sprintf("Cross-axis dependency (EIVEres-N): %s\n", ifelse(has_cross_axis, "Yes", "No")))

# pH profile analysis
if (length(available_ph) > 0) {
  cat("\n=== Soil pH Profile Analysis ===\n")
  ph_depths <- list(
    surface = c("phh2o_0_5cm_mean", "phh2o_0_5cm_p90"),
    main = c("phh2o_5_15cm_mean", "phh2o_5_15cm_p90", "phh2o_5_15cm_p10"),
    subsurface = c("phh2o_15_30cm_mean", "phh2o_15_30cm_p90")
  )

  for (depth in names(ph_depths)) {
    available_depth <- available_terms(ph_depths[[depth]])
    if (length(available_depth) > 0) {
      cat(sprintf("  %s layer: %s\n", depth, paste(available_depth, collapse=", ")))
    }
  }
}

# Helper function to create formulas
make_formula <- function(response, fixed_terms, smooth_terms = NULL, linear_terms = NULL) {
  if (grepl("-", response)) {
    response <- paste0("`", response, "`")
  }

  safe_term <- function(term) {
    if (grepl("[:() -]", term) && !grepl(":", term)) {
      return(paste0("`", term, "`"))
    }
    term
  }

  fixed_terms <- vapply(fixed_terms, safe_term, character(1))

  formula_str <- paste(response, "~", paste(fixed_terms, collapse = " + "))

  if (!is.null(smooth_terms) && length(smooth_terms) > 0) {
    smooth_terms_safe <- vapply(smooth_terms, safe_term, character(1))
    smooth_str <- paste0("s(", smooth_terms_safe, ", k=5)", collapse = " + ")
    formula_str <- paste(formula_str, smooth_str, sep = " + ")
  }

  if (!is.null(linear_terms) && length(linear_terms) > 0) {
    linear_terms_safe <- vapply(linear_terms, safe_term, character(1))
    formula_str <- paste(formula_str, paste(linear_terms_safe, collapse = " + "), sep = " + ")
  }

  as.formula(formula_str)
}

# Build comprehensive model candidates
model_candidates <- list()

# 1. pwSEM baseline (current features only)
pwsem_baseline <- available_terms(c("mat_mean", "temp_range", "drought_min"))
if (length(pwsem_baseline) > 0) {
  model_candidates[["pwsem_baseline"]] <- make_formula(target_response, pwsem_baseline)

  if (has_phylo) {
    model_candidates[["pwsem_phylo"]] <- make_formula(
      target_response,
      c(pwsem_baseline, phylo_var)
    )
  }
}

# 2. Add soil pH features (critical!)
if (length(available_ph) > 0) {
  # Simple pH model
  top_ph <- available_terms(c("phh2o_5_15cm_mean", "phh2o_5_15cm_p90"))
  if (length(top_ph) > 0) {
    model_candidates[["ph_simple"]] <- make_formula(
      target_response,
      c(pwsem_baseline, top_ph[1])
    )

    if (length(top_ph) > 1) {
      model_candidates[["ph_percentiles"]] <- make_formula(
        target_response,
        c(pwsem_baseline, top_ph)
      )
    }

    # Full pH profile
    model_candidates[["ph_profile"]] <- make_formula(
      target_response,
      c(pwsem_baseline, available_ph[1:min(5, length(available_ph))])
    )

    # pH with phylo
    if (has_phylo) {
      model_candidates[["ph_profile_phylo"]] <- make_formula(
        target_response,
        c(pwsem_baseline, available_ph[1:min(5, length(available_ph))], phylo_var)
      )
    }
  }
}

# 3. Add traits
if (length(available_traits) > 0 && length(available_ph) > 0) {
  model_candidates[["traits_ph"]] <- make_formula(
    target_response,
    c(available_traits[1:min(6, length(available_traits))],
      available_ph[1:min(3, length(available_ph))])
  )

  if (has_phylo) {
    model_candidates[["traits_ph_phylo"]] <- make_formula(
      target_response,
      c(available_traits[1:min(6, length(available_traits))],
        available_ph[1:min(3, length(available_ph))],
        phylo_var)
    )
  }
}

# 4. Full linear model
all_linear <- unique(c(available_traits, available_ph, available_climate, available_interactions))
if (length(all_linear) > 10) {
  model_candidates[["full_linear"]] <- make_formula(target_response, all_linear)

  if (has_phylo) {
    model_candidates[["full_linear_phylo"]] <- make_formula(
      target_response,
      c(all_linear, phylo_var)
    )
  }

  # Add cross-axis dependency
  if (has_cross_axis) {
    model_candidates[["full_linear_cross"]] <- make_formula(
      target_response,
      c(all_linear, phylo_var, "EIVEres_N")
    )
  }
}

# 5. GAM models with pH smooths (pH response likely non-linear)
if (length(available_ph) > 0 && length(available_traits) > 0) {
  # GAM with smooth pH
  model_candidates[["gam_ph"]] <- make_formula(
    target_response,
    available_traits[1:min(5, length(available_traits))],
    smooth_terms = available_ph[1:min(3, length(available_ph))],
    linear_terms = available_climate[1:min(4, length(available_climate))]
  )

  if (has_phylo) {
    # GAM with phylo linear
    model_candidates[["gam_ph_phylo"]] <- make_formula(
      target_response,
      c(available_traits[1:min(5, length(available_traits))], phylo_var),
      smooth_terms = available_ph[1:min(3, length(available_ph))],
      linear_terms = available_climate[1:min(4, length(available_climate))]
    )

    # GAM with phylo smooth (R has strongest phylo signal)
    model_candidates[["gam_ph_phylo_smooth"]] <- make_formula(
      target_response,
      available_traits[1:min(5, length(available_traits))],
      smooth_terms = c(available_ph[1:min(3, length(available_ph))], phylo_var),
      linear_terms = available_climate[1:min(4, length(available_climate))]
    )
  }

  # GAM with cross-axis smooth
  if (has_cross_axis) {
    model_candidates[["gam_cross"]] <- make_formula(
      target_response,
      c(available_traits[1:min(5, length(available_traits))],
        if(has_phylo) phylo_var else NULL),
      smooth_terms = c(available_ph[1:min(2, length(available_ph))], "EIVEres_N"),
      linear_terms = available_climate[1:min(3, length(available_climate))]
    )
  }
}

# 6. Full GAM with all smooths
if (length(available_ph) > 0 && length(available_climate) > 2) {
  model_candidates[["gam_full"]] <- make_formula(
    target_response,
    c(available_traits, available_interactions),
    smooth_terms = c(available_ph[1:min(4, length(available_ph))],
                     available_climate[1:min(4, length(available_climate))])
  )

  if (has_phylo) {
    model_candidates[["gam_full_phylo_smooth"]] <- make_formula(
      target_response,
      c(available_traits, available_interactions),
      smooth_terms = c(available_ph[1:min(3, length(available_ph))],
                       available_climate[1:min(3, length(available_climate))],
                       phylo_var)
    )
  }
}

# 7. Targeted model focusing on top SHAP features
top_features <- available_terms(c("phh2o_5_15cm_p90", "phh2o_5_15cm_mean", "logSM",
                                   "precip_warmest_q", "log_ldmc_minus_log_la"))
if (length(top_features) >= 3) {
  model_candidates[["gam_targeted"]] <- make_formula(
    target_response,
    top_features[1:2],
    smooth_terms = top_features[3:min(length(top_features), 4)]
  )

  if (has_phylo) {
    model_candidates[["gam_targeted_phylo"]] <- make_formula(
      target_response,
      c(top_features[1:2], phylo_var),
      smooth_terms = top_features[3:min(length(top_features), 4)]
    )
  }
}

cat(sprintf("\nTotal candidate models: %d\n", length(model_candidates)))

# Fit models and compute AIC
cat("\n=== Fitting Models and Computing AIC ===\n")
model_results <- list()

for (model_name in names(model_candidates)) {
  cat(sprintf("\nFitting %s...\n", model_name))

  tryCatch({
    formula_str <- as.character(model_candidates[[model_name]])[3]

    # Determine model type based on formula
    if (grepl("s\\(", formula_str)) {
      model <- gam(model_candidates[[model_name]], data = data, method = "ML")
    } else {
      model <- lm(model_candidates[[model_name]], data = data)
    }

    # Calculate metrics
    n_params <- if (inherits(model, "gam")) sum(model$edf) else length(coef(model))

    model_results[[model_name]] <- list(
      model = model,
      formula = model_candidates[[model_name]],
      AIC = AIC(model),
      AICc = AICc(model),
      R2 = summary(model)$r.sq,
      adj_R2 = if(inherits(model, "gam")) summary(model)$r.sq else summary(model)$adj.r.squared,
      n_params = n_params
    )

    cat(sprintf(
      "  AICc = %.2f, R² = %.3f, Adj R² = %.3f, params = %.1f\n",
      model_results[[model_name]]$AICc,
      model_results[[model_name]]$R2,
      model_results[[model_name]]$adj_R2,
      model_results[[model_name]]$n_params
    ))

  }, error = function(e) {
    cat(sprintf("  ERROR: %s\n", e$message))
    model_results[[model_name]] <- list(
      model = NULL,
      formula = model_candidates[[model_name]],
      AIC = Inf,
      AICc = Inf,
      R2 = NA,
      adj_R2 = NA,
      n_params = NA,
      error = e$message
    )
  })
}

# Rank models by AICc
cat("\n=== Model Ranking by AICc ===\n")
valid_results <- Filter(function(x) !is.na(x$AICc) && is.finite(x$AICc), model_results)

if (length(valid_results) > 0) {
  ranking_df <- data.frame(
    model = names(valid_results),
    AICc = sapply(valid_results, function(x) x$AICc),
    R2 = sapply(valid_results, function(x) x$R2),
    adj_R2 = sapply(valid_results, function(x) x$adj_R2),
    n_params = sapply(valid_results, function(x) x$n_params),
    stringsAsFactors = FALSE
  )

  ranking_df <- ranking_df[order(ranking_df$AICc), ]
  ranking_df$delta_AICc <- ranking_df$AICc - min(ranking_df$AICc)
  ranking_df$weight <- exp(-0.5 * ranking_df$delta_AICc)
  ranking_df$weight <- ranking_df$weight / sum(ranking_df$weight)

  print(ranking_df[1:min(10, nrow(ranking_df)), ])

  # Select best model
  best_model_name <- ranking_df$model[1]
  best_model <- valid_results[[best_model_name]]$model

  cat(sprintf("\n=== Best Model: %s ===\n", best_model_name))
  print(summary(best_model))

  # Cross-validation on best model
  cat("\n=== Cross-Validation of Best Model ===\n")

  # Stratified CV function
  assign_strata <- function(y, K) {
    qs <- quantile(y, probs = seq(0, 1, length.out = K + 1), na.rm = TRUE, type = 7)
    qs[1] <- -Inf
    qs[length(qs)] <- Inf
    groups <- cut(y, breaks = unique(qs), include.lowest = TRUE, labels = FALSE)
    fold_assign <- integer(length(y))
    for (grp in unique(groups)) {
      idx <- which(groups == grp)
      if (length(idx) == 0) next
      fold_assign[idx] <- sample(rep(seq_len(K), length.out = length(idx)))
    }
    fold_assign
  }

  # CV parameters
  y_vals <- data[[target_response]]
  repeats <- as.numeric(Sys.getenv("CV_REPEATS", "5"))
  folds <- as.numeric(Sys.getenv("CV_FOLDS", "10"))
  cv_scores <- c()
  rmse_scores <- c()

  cat(sprintf("Running %d repeats × %d folds cross-validation...\n", repeats, folds))

  for (r in seq_len(repeats)) {
    set.seed(123 + r)
    fold_assign <- assign_strata(y_vals, folds)

    for (k in seq_len(folds)) {
      test_idx <- which(fold_assign == k)
      train_idx <- setdiff(seq_len(nrow(data)), test_idx)

      if (length(test_idx) < 5 || length(train_idx) < 20) next

      train <- data[train_idx, , drop = FALSE]
      test <- data[test_idx, , drop = FALSE]

      tryCatch({
        # Refit model on training data
        if (inherits(best_model, "gam")) {
          fit <- gam(formula(best_model), data = train, method = "ML")
        } else {
          fit <- lm(formula(best_model), data = train)
        }

        # Predict on test data
        preds <- predict(fit, newdata = test)

        # Calculate metrics
        ss_res <- sum((test[[target_response]] - preds)^2)
        ss_tot <- sum((test[[target_response]] - mean(test[[target_response]]))^2)
        r2 <- 1 - ss_res/ss_tot
        rmse <- sqrt(mean((test[[target_response]] - preds)^2))

        if (is.finite(r2)) {
          cv_scores <- c(cv_scores, r2)
          rmse_scores <- c(rmse_scores, rmse)
          if ((r * folds + k) %% 10 == 0) {
            cat(sprintf("  Progress: Rep %d Fold %d - R²=%.3f\n", r, k, r2))
          }
        }
      }, error = function(e) {
        cat(sprintf("  Warning: Failed fold %d-%d: %s\n", r, k, e$message))
      })
    }
  }

  cv_scores <- cv_scores[is.finite(cv_scores)]
  rmse_scores <- rmse_scores[is.finite(rmse_scores)]

  cat("\n=== Cross-Validation Results ===\n")
  cat(sprintf("CV R² = %.3f ± %.3f (n=%d)\n", mean(cv_scores), sd(cv_scores), length(cv_scores)))
  cat(sprintf("CV RMSE = %.3f ± %.3f\n", mean(rmse_scores), sd(rmse_scores)))

  cat("\n=== Performance Comparison ===\n")
  cat("Target benchmarks:\n")
  cat("  pwSEM baseline: R² = 0.166 ± 0.092\n")
  cat("  pwSEM+phylo: R² = 0.222 ± 0.077 (target to beat)\n")
  cat("  XGBoost: R² = 0.225 ± 0.070 (gold standard)\n")
  cat(sprintf("\nThis model (%s): R² = %.3f ± %.3f %s\n",
      best_model_name,
      mean(cv_scores), sd(cv_scores),
      ifelse(mean(cv_scores) > 0.225, "✓ MATCHES/EXCEEDS XGBoost!",
             ifelse(mean(cv_scores) > 0.222, "✓ BEATS pwSEM+phylo!",
                    ifelse(mean(cv_scores) > 0.166, "(beats baseline)", "")))))

  # Feature importance for best model
  if (!is.null(best_model)) {
    cat("\n=== Feature Importance (Best Model) ===\n")

    if (inherits(best_model, "gam")) {
      # GAM: Show parametric coefficients and smooth significance
      cat("\nParametric coefficients (|t| > 2):\n")
      coef_summary <- summary(best_model)$p.table
      if (nrow(coef_summary) > 0) {
        significant_coefs <- coef_summary[abs(coef_summary[,"t value"]) > 2, , drop=FALSE]
        if (nrow(significant_coefs) > 0) {
          print(significant_coefs[order(abs(significant_coefs[,"t value"]), decreasing=TRUE), ])
        }
      }

      cat("\nSmooth terms:\n")
      if (!is.null(summary(best_model)$s.table)) {
        print(summary(best_model)$s.table)
      }
    } else {
      # Linear model: Show top coefficients
      coefs <- coef(best_model)[-1]  # Remove intercept
      coef_df <- data.frame(
        feature = names(coefs),
        coefficient = coefs,
        abs_coef = abs(coefs)
      )
      coef_df <- coef_df[order(coef_df$abs_coef, decreasing = TRUE), ]
      cat("\nTop 10 features by |coefficient|:\n")
      print(head(coef_df, 10))
    }
  }

  # Check critical features
  cat("\n=== Critical Feature Check ===\n")
  model_terms <- tryCatch(names(coef(best_model)), error = function(e) character(0))

  if ("phh2o_5_15cm_p90" %in% model_terms || grepl("phh2o_5_15cm_p90", formula_str)) {
    cat("✓ phh2o_5_15cm_p90 (top predictor, 10.5% SHAP) included\n")
  } else {
    cat("✗ WARNING: phh2o_5_15cm_p90 missing from best model\n")
  }

  if ("p_phylo_R" %in% model_terms || grepl("p_phylo_R", formula_str)) {
    cat("✓ p_phylo_R (strongest phylo signal) included\n")
  } else {
    cat("✗ WARNING: p_phylo_R missing from best model\n")
  }

  if ("EIVEres_N" %in% model_terms || grepl("EIVEres_N", formula_str)) {
    cat("✓ EIVEres_N (cross-axis dependency) included\n")
  }

  # Save results
  out_dir <- "results/aic_selection_R_full"
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # Save best model
  saveRDS(best_model, file.path(out_dir, "best_model.rds"))

  # Save ranking table
  write.csv(ranking_df, file.path(out_dir, "aic_ranking_table.csv"), row.names = FALSE)

  # Save CV results
  cv_summary <- data.frame(
    model = best_model_name,
    formula = as.character(formula(best_model))[3],
    AIC = best_model$aic,
    AICc = valid_results[[best_model_name]]$AICc,
    in_sample_r2 = valid_results[[best_model_name]]$R2,
    adj_r2 = valid_results[[best_model_name]]$adj_R2,
    cv_mean = mean(cv_scores),
    cv_sd = sd(cv_scores),
    rmse_mean = mean(rmse_scores),
    rmse_sd = sd(rmse_scores),
    n_params = valid_results[[best_model_name]]$n_params,
    n_folds = length(cv_scores)
  )
  write.csv(cv_summary, file.path(out_dir, "cv_summary.csv"), row.names = FALSE)

  cat(sprintf("\nResults saved to %s/\n", out_dir))

} else {
  cat("ERROR: No valid models fitted\n")
}

cat("\nAnalysis complete.\n")