suppressPackageStartupMessages({
  library(mixgb)
  library(dplyr)
  library(purrr)
  library(readr)
})

input_path <- 'model_data/inputs/mixgb/mixgb_input_20251023_1084.csv'
output_path <- 'model_data/inputs/mixgb/mixgb_cv_rmse_1084_gpu_20251023.csv'

mix_data <- readr::read_csv(input_path, show_col_types = FALSE)
message('Loaded input with ', nrow(mix_data), ' rows and ', ncol(mix_data), ' columns')

id_cols <- c('wfo_taxon_id', 'wfo_scientific_name')
drop_predictors <- c('leaf_area_source', 'nmass_source', 'ldmc_source', 'lma_source',
                     'height_source', 'seed_mass_source', 'sla_source',
                     'try_parasitism', 'try_carnivory', 'try_succulence',
                     'accepted_name', 'accepted_norm', 'accepted_wfo_id',
                     'duke_files', 'duke_original_names', 'duke_matched_names', 'duke_scientific_names',
                     'eive_taxon_concepts', 'try_source_species',
                     'genus', 'family', 'try_genus', 'try_family')
keep_cats <- c('try_woodiness', 'try_growth_form', 'try_habitat_adaptation',
               'try_leaf_type')
for (col in intersect(keep_cats, names(mix_data))) {
  mix_data[[col]] <- as.factor(mix_data[[col]])
}

feature_cols_base <- setdiff(names(mix_data), c(id_cols, drop_predictors))

prepare_features <- function(df) {
  feat <- df[, feature_cols_base, drop = FALSE]

  # Drop all-NA columns
  all_na_cols <- names(feat)[colSums(!is.na(feat)) == 0]
  if (length(all_na_cols) > 0) {
    feat <- feat %>% select(-all_of(all_na_cols))
  }

  # Convert characters to factors
  char_cols <- map_lgl(feat, is.character)
  if (any(char_cols)) {
    feat[char_cols] <- lapply(feat[char_cols], factor)
  }

  # Drop constant columns
  const_cols <- names(feat)[sapply(feat, function(col) {
    vals <- unique(col[!is.na(col)])
    length(vals) <= 1L
  })]
  if (length(const_cols) > 0) {
    feat <- feat %>% select(-all_of(const_cols))
  }

  # Drop high-cardinality categoricals
  high_card_cols <- names(feat)[sapply(feat, function(col) {
    if (is.factor(col)) {
      nlevels(col) > 50
    } else {
      FALSE
    }
  })]
  if (length(high_card_cols) > 0) {
    feat <- feat %>% select(-all_of(high_card_cols))
  }

  feat
}

trait_info <- tibble::tibble(
  trait = c('leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac', 'lma_g_m2', 'plant_height_m', 'seed_mass_mg'),
  transform = c('log', 'log', 'logit', 'log', 'log', 'log')
)

logit <- function(x, eps = 1e-06) {
  x <- pmin(pmax(x, eps), 1 - eps)
  log(x / (1 - x))
}

apply_transform <- function(x, type) {
  if (type == 'log') {
    if (any(x <= 0, na.rm = TRUE)) warning('Non-positive values encountered in log transform; coercing to NA.')
    return(log(x))
  }
  if (type == 'logit') {
    return(logit(x))
  }
  x
}

set.seed(20251023)
K <- 5
results <- list()

for (i in seq_len(nrow(trait_info))) {
  trait <- trait_info$trait[i]
  transform_type <- trait_info$transform[i]
  message('Evaluating trait: ', trait)
  observed_idx <- which(!is.na(mix_data[[trait]]))
  if (length(observed_idx) < K) {
    warning('Trait ', trait, ' has fewer than ', K, ' observed values; skipping.')
    next
  }
  fold_ids <- sample(rep(seq_len(K), length.out = length(observed_idx)))
  errors <- c()

  for (fold in seq_len(K)) {
    test_local_idx <- observed_idx[fold_ids == fold]
    train_local_idx <- setdiff(observed_idx, test_local_idx)

    df_fold <- mix_data
    df_fold[[trait]][test_local_idx] <- NA_real_

    feature_data <- prepare_features(df_fold)

    fit <- mixgb(feature_data,
                 m = 1,
                 nrounds = 300,
                 pmm.type = 2,
                 pmm.k = 4,
                 xgb.params = list(device = 'cuda', tree_method = 'hist'),
                 verbose = 0)

    imputed <- fit[[1]]
    preds <- imputed[[trait]][test_local_idx]
    actual <- mix_data[[trait]][test_local_idx]

    valid <- is.finite(preds) & is.finite(actual)
    preds <- preds[valid]
    actual <- actual[valid]

    if (length(preds) == 0) next

    preds_t <- apply_transform(preds, transform_type)
    actual_t <- apply_transform(actual, transform_type)
    err <- preds_t - actual_t
    rmse_fold <- sqrt(mean(err^2, na.rm = TRUE))
    errors <- c(errors, rmse_fold)
    message('  Fold ', fold, ': RMSE = ', signif(rmse_fold, 4), ' (n=', length(preds), ')')
  }
  results[[trait]] <- data.frame(trait = trait,
                                rmse_mean = mean(errors),
                                rmse_median = median(errors),
                                rmse_sd = stats::sd(errors),
                                folds = length(errors))
}

result_df <- dplyr::bind_rows(results)
print(result_df)
readr::write_csv(result_df, output_path)
message('Saved CV RMSE summary to ', output_path)
