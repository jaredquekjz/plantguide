#!/usr/bin/env Rscript

# Simplified blending script for T axis only with bioclim-enhanced predictions

suppressPackageStartupMessages({
  library(ape)
})

# Read inputs
pwsem_preds <- read.csv("artifacts/stage4_sem_pwsem_T_bioclim_fixed/sem_pwsem_T_preds.csv", stringsAsFactors = FALSE)
df <- read.csv("artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv", stringsAsFactors = FALSE)
tree <- ape::read.tree("data/phylogeny/eive_try_tree.nwk")

# Settings
xexp <- 2
alpha_grid <- c(0, 0.25, 0.5, 0.75, 1)

# Get phylogenetic distances
tips <- tree$tip.label
ids <- unique(pwsem_preds$id)
ids_tips <- gsub(" ", "_", ids, fixed = TRUE)
have_tip <- ids_tips %in% tips
ids_keep <- ids[have_tip]
ids_tips_keep <- ids_tips[have_tip]

cat(sprintf("Found %d/%d species in phylogeny\n", length(ids_keep), length(ids)))

# Prune tree to species in predictions
tree2 <- ape::keep.tip(tree, ids_tips_keep)
cop <- ape::cophenetic.phylo(tree2)

# Map species to EIVE values
eive_map <- setNames(
  df$`EIVEres.T`[match(rownames(cop), gsub(" ", "_", df$wfo_accepted_name, fixed=TRUE))],
  rownames(cop)
)

# For each alpha value
results <- data.frame()

for (a in alpha_grid) {
  # For each rep-fold combination
  groups <- unique(pwsem_preds[, c("rep","fold")])
  r2s <- c()
  maes <- c()

  for (i in seq_len(nrow(groups))) {
    r <- groups$rep[i]
    k <- groups$fold[i]

    # Get test set
    idx <- which(pwsem_preds$rep == r & pwsem_preds$fold == k)
    test_ids <- pwsem_preds$id[idx]
    test_ids_tips <- gsub(" ", "_", test_ids, fixed = TRUE)

    # Compute phylogenetic predictor for each test species
    p_phylo <- numeric(length(idx))

    for (j in seq_along(test_ids)) {
      test_tip <- test_ids_tips[j]
      if (test_tip %in% rownames(cop)) {
        # Get distances to all other species (excluding self)
        dists <- cop[test_tip, ]
        dists[test_tip] <- NA  # Exclude self

        # Compute weights
        valid <- !is.na(dists) & dists > 0
        weights <- numeric(length(dists))
        weights[valid] <- 1 / (dists[valid]^xexp)

        # Get donor EIVE values
        donor_eive <- as.numeric(eive_map[names(dists)])

        # Compute weighted average (excluding test species from donors)
        valid_donors <- valid & !is.na(donor_eive) & (names(dists) != test_tip)
        if (sum(valid_donors) > 0) {
          p_phylo[j] <- sum(weights[valid_donors] * donor_eive[valid_donors]) / sum(weights[valid_donors])
        } else {
          # Fallback to train mean
          train_idx <- which(pwsem_preds$rep == r & pwsem_preds$fold != k)
          p_phylo[j] <- mean(pwsem_preds$y_true[train_idx], na.rm = TRUE)
        }
      } else {
        # Species not in tree - use train mean
        train_idx <- which(pwsem_preds$rep == r & pwsem_preds$fold != k)
        p_phylo[j] <- mean(pwsem_preds$y_true[train_idx], na.rm = TRUE)
      }
    }

    # Blend predictions
    y_true <- pwsem_preds$y_true[idx]
    y_sem <- pwsem_preds$y_pred[idx]
    y_blend <- a * p_phylo + (1 - a) * y_sem

    # Compute metrics
    r2 <- 1 - sum((y_true - y_blend)^2) / sum((y_true - mean(y_true))^2)
    mae <- mean(abs(y_true - y_blend))

    r2s <- c(r2s, r2)
    maes <- c(maes, mae)
  }

  results <- rbind(results, data.frame(
    axis = "T",
    alpha = a,
    r2_mean = mean(r2s),
    r2_sd = sd(r2s),
    mae_mean = mean(maes),
    mae_sd = sd(maes),
    baseline_r2 = if(a == 0) mean(r2s) else results$r2_mean[1]
  ))
}

# Print results
cat("\nBlending Results for Temperature Axis:\n")
cat("=====================================\n")
for (i in 1:nrow(results)) {
  cat(sprintf("α = %.2f: R² = %.4f (±%.4f), MAE = %.4f (±%.4f)",
              results$alpha[i], results$r2_mean[i], results$r2_sd[i],
              results$mae_mean[i], results$mae_sd[i]))
  if (results$alpha[i] > 0) {
    lift <- results$r2_mean[i] - results$baseline_r2[i]
    cat(sprintf(" [Δ = %+.4f]", lift))
  }
  cat("\n")
}

# Save results
write.csv(results, "artifacts/T_bioclim_phylo_blend_results.csv", row.names = FALSE)

# Find optimal alpha
best_idx <- which.max(results$r2_mean)
cat(sprintf("\nOptimal α = %.2f with R² = %.4f (baseline = %.4f, lift = %+.4f)\n",
            results$alpha[best_idx], results$r2_mean[best_idx],
            results$baseline_r2[1], results$r2_mean[best_idx] - results$baseline_r2[1]))

# Compare to XGBoost
cat(sprintf("\nXGBoost benchmark: R² = 0.590\n"))
cat(sprintf("pwSEM + bioclim + phylo: R² = %.4f (%.1f%% of XGBoost performance)\n",
            results$r2_mean[best_idx], 100 * results$r2_mean[best_idx] / 0.590))