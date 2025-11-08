#!/usr/bin/env Rscript
# verify_stage2_training_bill.R - Verify Stage 2 XGBoost training quality
# Author: Pipeline verification framework, Date: 2025-11-07

suppressPackageStartupMessages({library(dplyr); library(jsonlite)})

check_pass <- function(cond, msg) {
  stat <- if (cond) "✓" else "✗"
  cat(sprintf("  %s %s\n", stat, msg))
  return(cond)
}

cat("========================================================================\n")
cat("VERIFICATION: Stage 2 Training\n")
cat("========================================================================\n\n")

MODEL_DIR <- "data/shipley_checks/stage2_models"
AXES <- c("L", "T", "M", "N", "R")

all_pass <- TRUE

for (axis in AXES) {
  cat(sprintf("\n[Axis %s]\n", axis))
  
  model_file <- sprintf("%s/xgb_%s_model.json", MODEL_DIR, axis)
  metrics_file <- sprintf("%s/xgb_%s_cv_metrics.json", MODEL_DIR, axis)
  
  all_pass <- check_pass(file.exists(model_file), "Model file exists") && all_pass
  all_pass <- check_pass(file.exists(metrics_file), "CV metrics exist") && all_pass
  
  if (file.exists(metrics_file)) {
    metrics <- fromJSON(metrics_file)
    
    r2_mean <- metrics$r2_mean
    acc1_mean <- metrics$acc_within_1_mean
    
    # Expected ranges (with one-hot categorical)
    r2_ok <- if (axis == "L") r2_mean > 0.55
             else if (axis == "T") r2_mean > 0.78
             else if (axis == "M") r2_mean > 0.62
             else if (axis == "N") r2_mean > 0.56
             else r2_mean > 0.40  # R
    
    acc1_ok <- acc1_mean > 0.75
    
    all_pass <- check_pass(r2_ok, sprintf("R² = %.3f (reasonable)", r2_mean)) && all_pass
    all_pass <- check_pass(acc1_ok, sprintf("Acc±1 = %.1f%% (≥75%%)", acc1_mean * 100)) && all_pass
  }
}

cat("\n========================================================================\n")
if (all_pass) {
  cat("✓ VERIFICATION PASSED\n")
  cat("========================================================================\n\n")
  quit(status = 0)
} else {
  cat("✗ VERIFICATION FAILED\n")
  cat("========================================================================\n\n")
  quit(status = 1)
}
