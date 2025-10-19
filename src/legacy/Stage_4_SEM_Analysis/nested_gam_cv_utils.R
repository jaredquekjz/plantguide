# Utility functions for nested LOSO / spatial CV in Stage 4 GAM scripts

slugify <- function(x) {
  x <- tolower(as.character(x))
  x <- gsub("[^0-9a-z]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  x[is.na(x)] <- ""
  x
}

load_occurrence_centroids <- function(path, species_slugs) {
  if (!length(species_slugs)) {
    return(tibble(species_slug = character(), lat = numeric(), lon = numeric()))
  }
  if (!file.exists(path)) {
    warning(sprintf("[warn] Occurrence file %s not found; spatial CV will fall back to single-species blocks", path))
    return(tibble(species_slug = character(), lat = numeric(), lon = numeric()))
  }
  suppressWarnings({
    occ <- readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
  })
  species_col <- intersect(c("species_clean", "species", "wfo_accepted_name", "species_key"), names(occ))[1]
  lat_col <- intersect(c("decimalLatitude", "decimallatitude", "latitude"), names(occ))[1]
  lon_col <- intersect(c("decimalLongitude", "decimallongitude", "longitude"), names(occ))[1]
  if (is.na(species_col) || is.na(lat_col) || is.na(lon_col)) {
    warning("[warn] Occurrence table missing species/lat/lon columns; skipping spatial blocking")
    return(tibble(species_slug = character(), lat = numeric(), lon = numeric()))
  }
  occ <- occ %>%
    mutate(species_slug = slugify(.data[[species_col]])) %>%
    filter(species_slug %in% species_slugs) %>%
    filter(is.finite(.data[[lat_col]]), is.finite(.data[[lon_col]]))
  centroids <- occ %>%
    group_by(species_slug) %>%
    summarise(
      lat = mean(.data[[lat_col]], na.rm = TRUE),
      lon = mean(.data[[lon_col]], na.rm = TRUE),
      .groups = "drop"
    ) %>%
    filter(is.finite(lat), is.finite(lon))
  centroids
}

compute_spatial_blocks <- function(centroids, block_km = 500) {
  if (nrow(centroids) == 0) return(character(0))
  R <- 6371.0
  lat_rad <- centroids$lat * pi / 180
  lon_rad <- centroids$lon * pi / 180
  x_km <- R * cos(lat_rad) * lon_rad
  y_km <- R * lat_rad
  block_x <- floor(x_km / block_km)
  block_y <- floor(y_km / block_km)
  block_id <- paste(block_x, block_y, sep = ":")
  names(block_id) <- centroids$species_slug
  block_id
}

bootstrap_summary <- function(y_true, y_pred, reps = 1000, seed = 123) {
  if (length(y_true) == 0 || reps <= 0) {
    return(list(
      r2_mean = NA_real_, r2_sd = NA_real_,
      rmse_mean = NA_real_, rmse_sd = NA_real_,
      effective_samples = 0L
    ))
  }
  set.seed(seed)
  idx_vec <- seq_along(y_true)
  r2_vals <- numeric(0)
  rmse_vals <- numeric(0)
  for (i in seq_len(reps)) {
    idx <- sample(idx_vec, replace = TRUE)
    yt <- y_true[idx]
    yp <- y_pred[idx]
    if (length(unique(yt)) < 2) next
    ss_res <- sum((yt - yp)^2)
    ss_tot <- sum((yt - mean(yt))^2)
    r2_vals <- c(r2_vals, 1 - ss_res / ss_tot)
    rmse_vals <- c(rmse_vals, sqrt(mean((yt - yp)^2)))
  }
  list(
    r2_mean = if (length(r2_vals)) mean(r2_vals) else NA_real_,
    r2_sd = if (length(r2_vals)) sd(r2_vals) else NA_real_,
    rmse_mean = if (length(rmse_vals)) mean(rmse_vals) else NA_real_,
    rmse_sd = if (length(rmse_vals)) sd(rmse_vals) else NA_real_,
    effective_samples = length(r2_vals)
  )
}

build_nested_folds <- function(strategy, species_slugs, spatial_blocks = NULL, families = NULL) {
  idx <- seq_along(species_slugs)
  if (strategy == "loso") {
    keys <- paste0("loso::", species_slugs)
  } else if (strategy == "loco") {
    if (is.null(families) || !length(families)) {
      warning("[warn] LOCO requested but family labels missing; defaulting to LOSO folds")
      keys <- paste0("loso::", species_slugs)
    } else {
      fam_vec <- as.character(families)
      fam_vec[!nzchar(fam_vec) | is.na(fam_vec)] <- "Unknown"
      keys <- paste0("loco::", fam_vec)
    }
  } else if (strategy == "spatial") {
    if (is.null(spatial_blocks) || !length(spatial_blocks)) {
      keys <- paste0("spatial::unmapped::", species_slugs)
    } else {
      block_ids <- spatial_blocks[species_slugs]
      block_ids[is.na(block_ids)] <- paste0("unmapped::", species_slugs[is.na(block_ids)])
      keys <- paste0("spatial::", block_ids)
    }
  } else {
    stop(sprintf("Unknown nested CV strategy '%s'", strategy))
  }
  split(idx, keys)
}

run_nested_cv <- function(strategy,
                          fold_map,
                          base_data,
                          formula_obj,
                          is_gam,
                          target_col,
                          species_names,
                          species_slugs,
                          families,
                          output_dir,
                          axis_letter,
                          bootstrap_reps = 1000) {
  n_folds <- length(fold_map)
  if (n_folds == 0) {
    message(sprintf("[warn] No folds generated for strategy %s; skipping", strategy))
    return(invisible(NULL))
  }
  cat(sprintf("\n=== Nested CV (%s) — %d folds ===\n", strategy, n_folds))

  all_true <- numeric(0)
  all_pred <- numeric(0)
  prediction_rows <- vector("list", n_folds)
  fold_rows <- vector("list", n_folds)

  start_time <- Sys.time()
  for (i in seq_along(fold_map)) {
    fold_name <- names(fold_map)[i]
    test_idx <- fold_map[[i]]
    train_idx <- setdiff(seq_len(nrow(base_data)), test_idx)
    if (length(test_idx) == 0 || length(train_idx) == 0) next

    fold_start <- Sys.time()

    train_data <- base_data[train_idx, , drop = FALSE]
    test_data <- base_data[test_idx, , drop = FALSE]

    factor_cols <- intersect(c("Family", "is_woody"), names(train_data))
    for (col in factor_cols) {
      train_data[[col]] <- factor(train_data[[col]])
      test_data[[col]] <- factor(test_data[[col]], levels = levels(train_data[[col]]))
    }

    fit <- tryCatch({
      if (is_gam) {
        mgcv::gam(formula_obj, data = train_data, method = "ML")
      } else {
        stats::lm(formula_obj, data = train_data)
      }
    }, error = function(e) {
      warning(sprintf("[warn] %s fold %s failed: %s", strategy, fold_name, e$message))
      NULL
    })
    if (is.null(fit)) next

    preds <- tryCatch({
      as.numeric(predict(fit, newdata = test_data))
    }, error = function(e) {
      warning(sprintf("[warn] Prediction failed for fold %s: %s", fold_name, e$message))
      rep(NA_real_, length(test_idx))
    })

    truth <- base_data[[target_col]][test_idx]
    residuals <- truth - preds

    all_true <- c(all_true, truth)
    all_pred <- c(all_pred, preds)

    fold_r2 <- if (length(unique(truth)) >= 2 && all(is.finite(residuals))) {
      ss_res <- sum((truth - preds)^2)
      ss_tot <- sum((truth - mean(truth))^2)
      if (is.finite(ss_tot) && ss_tot > 0) 1 - ss_res / ss_tot else NA_real_
    } else {
      NA_real_
    }
    fold_rmse <- sqrt(mean((truth - preds)^2, na.rm = TRUE))
    fold_mae <- mean(abs(truth - preds), na.rm = TRUE)

    prediction_rows[[i]] <- tibble(
      fold = fold_name,
      species = species_names[test_idx],
      species_slug = species_slugs[test_idx],
      family = if ("Family" %in% names(base_data)) families[test_idx] else NA_character_,
      y_true = truth,
      y_pred = preds,
      residual = residuals
    )

    fold_rows[[i]] <- tibble(
      fold = fold_name,
      n_test = length(test_idx),
      r2 = fold_r2,
      rmse = fold_rmse,
      mae = fold_mae,
      elapsed_sec = as.numeric(difftime(Sys.time(), fold_start, units = "secs"))
    )

    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    avg_per_fold <- elapsed / i
    eta_min <- (n_folds - i) * avg_per_fold / 60
    cat(sprintf("[cv] %s fold %d/%d done in %.1fs | fold R²=%s RMSE=%.3f | ETA ≈ %.1f min\n",
                strategy, i, n_folds,
                fold_rows[[i]]$elapsed_sec,
                ifelse(is.na(fold_r2), "NA", sprintf("%.3f", fold_r2)),
                fold_rmse,
                eta_min))
  }

  predictions_df <- dplyr::bind_rows(prediction_rows)
  folds_df <- dplyr::bind_rows(fold_rows)

  valid <- is.finite(all_true) & is.finite(all_pred)
  y_all <- all_true[valid]
  y_hat_all <- all_pred[valid]
  ss_res <- sum((y_all - y_hat_all)^2)
  ss_tot <- sum((y_all - mean(y_all))^2)
  overall_r2 <- if (length(y_all) > 0 && ss_tot > 0) 1 - ss_res / ss_tot else NA_real_
  overall_rmse <- if (length(y_all) > 0) sqrt(mean((y_all - y_hat_all)^2)) else NA_real_

  boot <- bootstrap_summary(y_all, y_hat_all, reps = bootstrap_reps, seed = 321)

  metrics <- list(
    strategy = strategy,
    outer_folds = n_folds,
    n_predictions = length(y_all),
    overall_r2 = overall_r2,
    overall_rmse = overall_rmse,
    bootstrap_r2_mean = boot$r2_mean,
    bootstrap_r2_sd = boot$r2_sd,
    bootstrap_rmse_mean = boot$rmse_mean,
    bootstrap_rmse_sd = boot$rmse_sd,
    bootstrap_effective_samples = boot$effective_samples,
    per_fold_rmse_mean = mean(folds_df$rmse, na.rm = TRUE),
    per_fold_rmse_sd = sd(folds_df$rmse, na.rm = TRUE),
    per_fold_mae_mean = mean(folds_df$mae, na.rm = TRUE),
    per_fold_mae_sd = sd(folds_df$mae, na.rm = TRUE)
  )

  metrics_path <- file.path(output_dir, sprintf("gam_%s_cv_metrics_%s.json", axis_letter, strategy))
  preds_path <- file.path(output_dir, sprintf("gam_%s_cv_predictions_%s.csv", axis_letter, strategy))
  folds_path <- file.path(output_dir, sprintf("gam_%s_cv_folds_%s.csv", axis_letter, strategy))

  jsonlite::write_json(metrics, metrics_path, auto_unbox = TRUE, pretty = TRUE)
  if (nrow(predictions_df)) readr::write_csv(predictions_df, preds_path)
  if (nrow(folds_df)) readr::write_csv(folds_df, folds_path)

  cat(sprintf("[cv] %s overall R² = %s | bootstrap mean ± sd = %s ± %s\n",
              strategy,
              ifelse(is.na(overall_r2), "NA", sprintf("%.3f", overall_r2)),
              ifelse(is.na(boot$r2_mean), "NA", sprintf("%.3f", boot$r2_mean)),
              ifelse(is.na(boot$r2_sd), "NA", sprintf("%.3f", boot$r2_sd))))

  invisible(metrics)
}

maybe_run_nested_cv <- function(axis_letter,
                                base_data,
                                formula_obj,
                                is_gam,
                                target_col,
                                species_names,
                                species_slugs,
                                family_vec,
                                output_dir) {
  enable_nested_cv <- tolower(Sys.getenv("NESTED_CV_ENABLE", "false")) %in% c("1", "true", "yes", "y")
  if (!enable_nested_cv) {
    cat("\n[nested] Set NESTED_CV_ENABLE=true to run LOSO/spatial deployment CV.\n")
    return(invisible(NULL))
  }

  nested_strategies_raw <- Sys.getenv("NESTED_CV_STRATEGIES", "loso,spatial")
  nested_strategies <- nested_strategies_raw %>% strsplit(",") %>% unlist() %>% stringr::str_trim() %>% tolower()
  nested_strategies <- unique(nested_strategies[nested_strategies != ""])
  if (!length(nested_strategies)) nested_strategies <- c("loso", "spatial")

  occurrence_csv <- Sys.getenv(
    "NESTED_CV_OCC_CSV",
    "data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv"
  )
  spatial_block_km <- suppressWarnings(as.numeric(Sys.getenv("NESTED_CV_BLOCK_KM", "500")))
  if (!is.finite(spatial_block_km) || spatial_block_km <= 0) spatial_block_km <- 500
  bootstrap_reps <- suppressWarnings(as.integer(Sys.getenv("NESTED_CV_BOOTSTRAP", "1000")))
  if (!is.finite(bootstrap_reps) || bootstrap_reps < 0) bootstrap_reps <- 1000

  spatial_blocks <- character(0)
  if ("spatial" %in% nested_strategies) {
    centroids <- load_occurrence_centroids(occurrence_csv, unique(species_slugs))
    spatial_blocks <- compute_spatial_blocks(centroids, block_km = spatial_block_km)
    if (!length(spatial_blocks)) {
      warning("[warn] Spatial blocking fell back to single-species folds; check occurrence coverage.")
    } else {
      cat(sprintf("[info] Spatial blocking produced %d tiles (%.0f km)\n",
                  length(unique(spatial_blocks)), spatial_block_km))
    }
  }

  for (strategy in nested_strategies) {
    fold_map <- switch(
      strategy,
      "loso" = build_nested_folds("loso", species_slugs),
      "loco" = build_nested_folds("loco", species_slugs, families = family_vec),
      "spatial" = build_nested_folds("spatial", species_slugs, spatial_blocks),
      {
        warning(sprintf("[warn] Unknown nested CV strategy '%s' — skipping", strategy))
        NULL
      }
    )

    if (is.null(fold_map)) next

    run_nested_cv(
      strategy = strategy,
      fold_map = fold_map,
      base_data = base_data,
      formula_obj = formula_obj,
      is_gam = is_gam,
      target_col = target_col,
      species_names = species_names,
      species_slugs = species_slugs,
      families = family_vec,
      output_dir = output_dir,
      axis_letter = axis_letter,
      bootstrap_reps = bootstrap_reps
    )
  }

  invisible(NULL)
}
