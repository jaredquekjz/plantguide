#!/usr/bin/env Rscript
#
# Verify Bill's XGBoost imputation against canonical Python pipeline
#
# Compares:
# 1. CV metrics (RMSE, R²)
# 2. Complete imputed dataset
# 3. Phylogenetic predictors
# 4. Final Stage 2 dataset
#

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

parse_args <- function(args) {
  out <- list()
  for (a in args) {
    if (!grepl('^--[A-Za-z0-9_]+=', a)) next
    kv <- sub('^--', '', a)
    key <- sub('=.*$', '', kv)
    val <- sub('^[^=]*=', '', kv)
    out[[key]] <- val
  }
  out
}

args <- commandArgs(trailingOnly = TRUE)
opts <- parse_args(args)
get_opt <- function(name, default) {
  if (!is.null(opts[[name]]) && nzchar(opts[[name]])) {
    opts[[name]]
  } else {
    default
  }
}

# Bill's verification paths
bill_cv <- get_opt('bill_cv', 'data/shipley_checks/imputation/mixgb_cv_rmse_bill.csv')
bill_final <- get_opt('bill_final', 'data/shipley_checks/imputation/bill_complete_final_11711_20251107.csv')

# Canonical paths (to be specified)
canon_cv <- get_opt('canon_cv', 'results/experiments/perm2_11680/cv_10fold_eta0025_n3000_20251028.csv')
canon_final <- get_opt('canon_final', 'model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.csv')

output_path <- get_opt('output', 'data/shipley_checks/imputation/verification_report_bill.txt')

cat(strrep('=', 80), '\n')
cat('Bill XGBoost Imputation Verification\n')
cat(strrep('=', 80), '\n\n')

# Collect verification results
results <- list()
errors <- character()

# 1. Compare CV metrics
cat('[1/3] Comparing CV metrics...\n')
if (file.exists(bill_cv) && file.exists(canon_cv)) {
  bill_cv_df <- readr::read_csv(bill_cv, show_col_types = FALSE)
  canon_cv_df <- readr::read_csv(canon_cv, show_col_types = FALSE)

  # Match traits
  common_traits <- intersect(bill_cv_df$trait, canon_cv_df$trait)
  if (length(common_traits) == 0) {
    errors <- c(errors, 'No common traits found in CV metrics')
  } else {
    cat(sprintf('  ✓ Found %d common traits\n', length(common_traits)))

    # Compare RMSE and R²
    for (trait in common_traits) {
      bill_row <- bill_cv_df[bill_cv_df$trait == trait, ]
      canon_row <- canon_cv_df[canon_cv_df$trait == trait, ]

      rmse_diff <- abs(bill_row$rmse_mean - canon_row$rmse_mean)
      r2_diff <- abs(bill_row$r2_transformed - canon_row$r2_transformed)

      cat(sprintf('  %s: RMSE diff=%.6f, R² diff=%.6f\n', trait, rmse_diff, r2_diff))

      results[[paste0('cv_', trait, '_rmse_diff')]] <- rmse_diff
      results[[paste0('cv_', trait, '_r2_diff')]] <- r2_diff

      # Flag large differences (>1%)
      if (rmse_diff > 0.01) {
        errors <- c(errors, sprintf('Large RMSE difference for %s: %.6f', trait, rmse_diff))
      }
      if (r2_diff > 0.01) {
        errors <- c(errors, sprintf('Large R² difference for %s: %.6f', trait, r2_diff))
      }
    }
  }
} else {
  errors <- c(errors, 'CV metric files not found')
  cat('  ✗ CV metric files not found\n')
}

# 2. Compare final datasets
cat('\n[2/3] Comparing final datasets...\n')
if (file.exists(bill_final) && file.exists(canon_final)) {
  bill_final_df <- readr::read_csv(bill_final, show_col_types = FALSE)
  canon_final_df <- readr::read_csv(canon_final, show_col_types = FALSE)

  cat(sprintf('  Bill: %d species × %d columns\n', nrow(bill_final_df), ncol(bill_final_df)))
  cat(sprintf('  Canonical: %d species × %d columns\n', nrow(canon_final_df), ncol(canon_final_df)))

  # Check dimensions
  if (ncol(bill_final_df) != ncol(canon_final_df)) {
    errors <- c(errors, sprintf('Column count mismatch: %d (Bill) vs %d (Canonical)',
                                ncol(bill_final_df), ncol(canon_final_df)))
  }

  # Find common species (11,680 canonical vs 11,711 Bill)
  # Bill has 31 extra species due to GBIF bug fix
  common_ids <- intersect(bill_final_df$wfo_taxon_id, canon_final_df$wfo_taxon_id)
  cat(sprintf('  Common species: %d\n', length(common_ids)))

  if (length(common_ids) > 0) {
    # Subset to common species for comparison
    bill_common <- bill_final_df %>% filter(wfo_taxon_id %in% common_ids) %>% arrange(wfo_taxon_id)
    canon_common <- canon_final_df %>% filter(wfo_taxon_id %in% common_ids) %>% arrange(wfo_taxon_id)

    # Compare log traits
    log_traits <- c('logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM')
    cat('\n  Comparing log traits:\n')
    for (trait in log_traits) {
      if (trait %in% names(bill_common) && trait %in% names(canon_common)) {
        bill_vals <- bill_common[[trait]]
        canon_vals <- canon_common[[trait]]

        # Compute differences
        diffs <- bill_vals - canon_vals
        max_diff <- max(abs(diffs), na.rm = TRUE)
        mean_diff <- mean(abs(diffs), na.rm = TRUE)

        cat(sprintf('    %s: max_diff=%.6f, mean_diff=%.6f\n', trait, max_diff, mean_diff))

        results[[paste0('trait_', trait, '_max_diff')]] <- max_diff
        results[[paste0('trait_', trait, '_mean_diff')]] <- mean_diff

        # Flag large differences (>1e-6 for numerical precision)
        if (max_diff > 1e-6) {
          errors <- c(errors, sprintf('Large trait difference for %s: %.6f', trait, max_diff))
        }
      }
    }

    # Compare phylo predictors
    p_phylo_cols <- grep('^p_phylo_', names(bill_common), value = TRUE)
    cat('\n  Comparing phylo predictors:\n')
    for (col in p_phylo_cols) {
      if (col %in% names(canon_common)) {
        bill_vals <- bill_common[[col]]
        canon_vals <- canon_common[[col]]

        # Only compare non-NA values
        valid_idx <- !is.na(bill_vals) & !is.na(canon_vals)
        if (sum(valid_idx) > 0) {
          diffs <- bill_vals[valid_idx] - canon_vals[valid_idx]
          max_diff <- max(abs(diffs), na.rm = TRUE)
          mean_diff <- mean(abs(diffs), na.rm = TRUE)

          cat(sprintf('    %s: max_diff=%.6f, mean_diff=%.6f (n=%d)\n',
                      col, max_diff, mean_diff, sum(valid_idx)))

          results[[paste0('p_phylo_', col, '_max_diff')]] <- max_diff
          results[[paste0('p_phylo_', col, '_mean_diff')]] <- mean_diff
        }
      }
    }
  }
} else {
  errors <- c(errors, 'Final dataset files not found')
  cat('  ✗ Final dataset files not found\n')
}

# 3. Summary
cat('\n[3/3] Writing verification report...\n')

sink(output_path)
cat(strrep('=', 80), '\n')
cat('Bill XGBoost Imputation Verification Report\n')
cat(strrep('=', 80), '\n\n')
cat(sprintf('Generated: %s\n\n', Sys.time()))

cat('Files compared:\n')
cat(sprintf('  Bill CV: %s\n', bill_cv))
cat(sprintf('  Canonical CV: %s\n', canon_cv))
cat(sprintf('  Bill final: %s\n', bill_final))
cat(sprintf('  Canonical final: %s\n', canon_final))

cat('\n', strrep('-', 80), '\n')
cat('Verification Results\n')
cat(strrep('-', 80), '\n\n')

if (length(errors) == 0) {
  cat('✓ PASS: All comparisons within tolerance\n\n')
} else {
  cat(sprintf('✗ FAIL: %d issues found:\n\n', length(errors)))
  for (err in errors) {
    cat(sprintf('  - %s\n', err))
  }
}

cat('\nDetailed metrics:\n')
for (name in names(results)) {
  cat(sprintf('  %s: %.10f\n', name, results[[name]]))
}

sink()

cat(sprintf('  ✓ Report saved: %s\n', output_path))

# Print summary to console
cat('\n', strrep('=', 80), '\n')
cat('VERIFICATION SUMMARY\n')
cat(strrep('=', 80), '\n\n')

if (length(errors) == 0) {
  cat('✓ PASS: Bill\'s R pipeline matches canonical Python pipeline\n')
  cat('  All metrics within numerical precision tolerance\n')
} else {
  cat(sprintf('✗ FAIL: %d verification issues found\n', length(errors)))
  cat(sprintf('  See full report: %s\n', output_path))
}

cat('\n')
