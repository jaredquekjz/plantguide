#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(purrr)
  library(tidyr)
})

parse_args <- function(args) {
  opt <- list(
    predictions_csv = NULL,
    output_csv = "results/gardening/garden_requirements_no_eive.csv",
    bins = "0:3.5,3.5:6.5,6.5:10",
    borderline_width = 0.5,
    r2_L = NA_real_, r2_T = NA_real_, r2_M = NA_real_, r2_R = NA_real_, r2_N = NA_real_,
    abstain_strict = FALSE,
    validate_with_labels = NULL,
    # Joint suitability (optional)
    joint_requirement = NULL,            # e.g., "L=high,M=med,R=med"
    joint_min_prob = 0.6,               # threshold for OK
    copulas_json = "results/MAG_Run8/mag_copulas.json",
    metrics_dir = "artifacts/stage4_sem_piecewise_run7",
    nsim_joint = 20000,
    # Group-aware uncertainty (optional)
    group_col = NULL,                   # name of grouping column (either in predictions or in reference csv)
    group_ref_csv = "artifacts/model_data_complete_case_with_myco.csv",
    group_ref_id_col = "wfo_accepted_name",
    group_ref_group_col = NULL,
    sigma_mode = NULL,                  # global|by_group (default: by_group when group_col present)
    # Batch presets (optional)
    joint_presets_csv = NULL            # CSV with columns: label, requirement, joint_min_prob
  )
  if (length(args) %% 2 != 0) stop("Invalid arguments. Example: --predictions_csv <path> --output_csv <path>")
  for (i in seq(1, length(args), by = 2)) {
    key <- gsub("^--", "", args[[i]])
    val <- args[[i + 1]]
    if (!key %in% names(opt)) stop(sprintf("Unknown flag: --%s", key))
    if (key == "abstain_strict") opt[[key]] <- tolower(val) %in% c("true","1","yes")
    else if (grepl("^r2_", key)) opt[[key]] <- as.numeric(val)
    else if (key %in% c("borderline_width","joint_min_prob","nsim_joint")) opt[[key]] <- as.numeric(val)
    else opt[[key]] <- val
  }
  if (is.null(opt$predictions_csv)) stop("Missing required --predictions_csv <path>")
  opt
}

parse_bins <- function(spec) {
  parts <- strsplit(spec, ",", fixed = TRUE)[[1]]
  rng <- lapply(parts, function(p) as.numeric(strsplit(trimws(p), ":", fixed = TRUE)[[1]]))
  if (length(rng) != 3) stop("Expect exactly 3 bins: low,med,high")
  list(low = rng[[1]], med = rng[[2]], high = rng[[3]])
}

axis_labels_default <- function(axis) {
  switch(
    axis,
    L = list(low = "Deep/Partial Shade", med = "Partial Sun", high = "Full Sun"),
    T = list(low = "Cool Climate", med = "Temperate", high = "Warm Climate"),
    M = list(low = "Drought-Tolerant", med = "Average Moisture", high = "Requires Wet Soil"),
    R = list(low = "Acidic Soil", med = "Neutral Soil", high = "Alkaline Soil"),
    N = list(low = "Poor Soil", med = "Average/Rich Soil", high = "Requires Fertile Soil"),
    list(low = "Low", med = "Medium", high = "High")
  )
}

band_from_r2 <- function(r2) {
  if (is.na(r2)) return("unknown")
  if (r2 >= 0.35) return("high")
  if (r2 >= 0.20) return("medium")
  return("low")
}

is_borderline <- function(y, bins, width) {
  edges <- c(bins$low[2], bins$med[2])
  any(abs(y - edges) <= width)
}

bin_of <- function(y, bins) {
  if (is.na(y)) return(NA_character_)
  if (y >= bins$low[1] && y < bins$low[2]) return("low")
  if (y >= bins$med[1] && y < bins$med[2]) return("med")
  if (y >= bins$high[1] && y <= bins$high[2]) return("high")
  return(NA_character_)
}

confidence_policy <- function(borderline, band) {
  if (band %in% c("high")) return(if (borderline) "medium" else "high")
  if (band %in% c("medium")) return(if (borderline) "low" else "medium")
  if (band %in% c("low")) return(if (borderline) "very_low" else "low")
  return(if (borderline) "low" else "medium")
}

recommend_axis <- function(axis, y, bins, width, r2, abstain_strict = FALSE) {
  b <- bin_of(y, bins)
  border <- is_borderline(y, bins, width)
  band <- band_from_r2(r2)
  conf <- confidence_policy(border, band)
  labels <- axis_labels_default(axis)
  label <- if (is.na(b)) NA_character_ else labels[[b]]
  notes <- character(0)
  if (border) notes <- c(notes, "borderline")
  if (band == "low") notes <- c(notes, "low_model_reliability")
  if (band == "high") notes <- c(notes, "high_model_reliability")
  if (abstain_strict && conf %in% c("low", "very_low")) {
    return(list(bin = NA_character_, borderline = border, confidence = conf, recommendation = "Uncertain", notes = paste(notes, collapse = "; ")))
  }
  list(bin = b, borderline = border, confidence = conf, recommendation = label, notes = paste(notes, collapse = "; "))
}

read_labels_if_any <- function(path) {
  if (is.null(path) || !nzchar(path)) return(NULL)
  if (!file.exists(path)) { warning(sprintf("Label file not found: %s", path)); return(NULL) }
  suppressMessages(readr::read_csv(path, show_col_types = FALSE))
}

compute_validation <- function(pred_df, rec_df, labels_df) {
  key <- NULL
  if ("species_id" %in% names(pred_df) && "species_id" %in% names(labels_df)) key <- "species_id"
  if (is.null(key) && "species" %in% names(pred_df) && "species" %in% names(labels_df)) key <- "species"
  if (is.null(key) && "row_id" %in% names(pred_df) && "row_id" %in% names(labels_df)) key <- "row_id"
  if (is.null(key)) { pred_df$.__row__ <- seq_len(nrow(pred_df)); labels_df$.__row__ <- seq_len(nrow(labels_df)); key <- ".__row__" }
  joined <- pred_df %>% select(all_of(key)) %>%
    left_join(rec_df %>% select(all_of(key), ends_with("_bin")), by = key) %>%
    left_join(labels_df %>% select(any_of(c(key, "L","T","M","R","N"))), by = key)
  axes <- c("L","T","M","R","N")
  metrics <- purrr::map_dfr(axes, function(ax) {
    pred_col <- paste0(ax, "_bin")
    if (!pred_col %in% names(joined) || !ax %in% names(joined)) return(tibble(axis=ax, accuracy=NA_real_, n=0))
    valid <- joined %>% filter(!is.na(.data[[pred_col]]), !is.na(.data[[ax]]))
    acc <- if (nrow(valid)==0) NA_real_ else mean(valid[[pred_col]] == tolower(valid[[ax]]))
    tibble(axis=ax, accuracy=acc, n=nrow(valid))
  })
  list(metrics = metrics, n = nrow(joined))
}

write_validation_report <- function(val, path) {
  lines <- c("# Gardening Validation Report","", sprintf("Total rows evaluated: %d", val$n), "", "| Axis | Accuracy | N |", "|------|----------|---|")
  for (i in seq_len(nrow(val$metrics))) {
    r <- val$metrics[i,]
    acc_str <- if (is.na(r$accuracy)) "NA" else sprintf("%.3f", r$accuracy)
    lines <- c(lines, sprintf("| %s | %s | %d |", r$axis, acc_str, r$n))
  }
  writeLines(lines, con = path)
}

main <- function() {
  opt <- parse_args(commandArgs(trailingOnly = TRUE))
  bins <- parse_bins(opt$bins)
  message(sprintf("Reading predictions: %s", opt$predictions_csv))
  preds <- suppressMessages(readr::read_csv(opt$predictions_csv, show_col_types = FALSE))
  id_col <- NULL
  for (cand in c("species", "species_id", "Species")) if (cand %in% names(preds)) { id_col <- cand; break }
  if (is.null(id_col)) { preds$row_id <- seq_len(nrow(preds)); id_col <- "row_id" }
  axes <- c("L","T","M","R","N")
  r2_map <- c(L = opt$r2_L, T = opt$r2_T, M = opt$r2_M, R = opt$r2_R, N = opt$r2_N)
  defaults <- c(L=0.237,T=0.234,M=0.415,R=0.155,N=0.424)
  for (ax in axes) if (is.na(r2_map[[ax]])) r2_map[[ax]] <- defaults[[ax]]
  pred_cols <- paste0(axes, "_pred")
  missing_pred <- setdiff(pred_cols, names(preds))
  if (length(missing_pred) > 0) stop(sprintf("Missing prediction columns: %s", paste(missing_pred, collapse=", ")))

  base <- preds %>% select(all_of(c(id_col, pred_cols)), any_of("source"))
  recs <- base
  for (ax in axes) {
    y_raw <- as.numeric(base[[paste0(ax, "_pred")]])
    y <- pmin(10, pmax(0, y_raw))
    b <- vapply(y, function(z) bin_of(z, bins), character(1))
    border <- vapply(y, function(z) is_borderline(z, bins, as.numeric(opt$borderline_width)), logical(1))
    band <- band_from_r2(r2_map[[ax]])
    conf <- ifelse(border, confidence_policy(TRUE, band), confidence_policy(FALSE, band))
    labels <- axis_labels_default(ax)
    reco <- ifelse(is.na(b), NA_character_, unname(unlist(labels))[match(b, names(labels))])
    notes <- character(length(y))
    notes[border] <- paste0(notes[border], ifelse(nchar(notes[border])>0, "; ", ""), "borderline")
    if (band == "low") notes <- paste0(notes, ifelse(nchar(notes)>0, "; ", ""), "low_model_reliability")
    else if (band == "high") notes <- paste0(notes, ifelse(nchar(notes)>0, "; ", ""), "high_model_reliability")
    if (opt$abstain_strict) { uncertain <- conf %in% c("low","very_low"); b[uncertain] <- NA_character_; reco[uncertain] <- "Uncertain" }
    recs[[paste0(ax, "_bin")]] <- b
    recs[[paste0(ax, "_borderline")]] <- border
    recs[[paste0(ax, "_confidence")]] <- conf
    recs[[paste0(ax, "_recommendation")]] <- reco
    recs[[paste0(ax, "_notes")]] <- notes
  }

  readr::write_csv(recs, opt$output_csv)
  message(sprintf("Wrote recommendations: %s", opt$output_csv))

  labels_df <- read_labels_if_any(opt$validate_with_labels)
  if (!is.null(labels_df)) {
    val <- compute_validation(preds %>% select(any_of(c(id_col, paste0(axes, "_pred")))), recs %>% select(any_of(c(id_col, paste0(axes, c("_bin","_borderline","_confidence","_recommendation","_notes"))))), labels_df)
    report_path <- file.path("results", "garden_validation_report.md")
    write_validation_report(val, report_path)
    message(sprintf("Wrote validation report: %s", report_path))
  }

  # Optional: Joint suitability via Gaussian copulas (Run 8)
  if (!is.null(opt$joint_requirement) && nzchar(opt$joint_requirement)) {
    message(sprintf("Computing joint suitability for requirement: %s", opt$joint_requirement))
    # Helpers for joint computation
    parse_bins <- function(spec) {
      parts <- strsplit(spec, ",", fixed = TRUE)[[1]]
      rng <- lapply(parts, function(p) as.numeric(strsplit(trimws(p), ":", fixed = TRUE)[[1]]))
      if (length(rng) != 3) stop("Expect exactly 3 bins: low,med,high")
      list(low = rng[[1]], med = rng[[2]], high = rng[[3]])
    }
    parse_req <- function(s) {
      bits <- strsplit(s, ",", fixed = TRUE)[[1]]
      out <- list()
      for (b in bits) {
        kv <- strsplit(trimws(b), "=", fixed = TRUE)[[1]]
        if (length(kv) != 2) next
        ax <- toupper(trimws(kv[1]))
        lv <- tolower(trimws(kv[2]))
        if (!(ax %in% axes) || !(lv %in% c("low","med","high"))) next
        out[[ax]] <- lv
      }
      out
    }
    bins <- parse_bins(opt$bins)
    req <- parse_req(opt$joint_requirement)
    if (!length(req)) stop("No valid axis=level entries parsed from --joint_requirement")

    # Read RMSE per axis (Run 7)
    read_sigma <- function(dir, letter) {
      p <- file.path(dir, sprintf("sem_piecewise_%s_metrics.json", letter))
      if (!file.exists(p)) stop(sprintf("Metrics JSON not found: %s", p))
      jj <- jsonlite::fromJSON(p)
      ag <- jj$metrics$aggregate
      if (is.data.frame(ag)) rmse <- as.numeric(ag$RMSE_mean[1]) else rmse <- as.numeric(ag[[1]]$RMSE_mean)
      if (!is.finite(rmse)) stop(sprintf("Could not read RMSE_mean from %s", p))
      rmse
    }
    sigmas_global <- c(L = read_sigma(opt$metrics_dir, "L"), T = read_sigma(opt$metrics_dir, "T"), M = read_sigma(opt$metrics_dir, "M"), R = read_sigma(opt$metrics_dir, "R"), N = read_sigma(opt$metrics_dir, "N"))
    # Build Corr from copulas JSON (global + optional per-group)
    cop <- jsonlite::fromJSON(opt$copulas_json)
    names <- axes
    build_corr <- function(districts) {
      C <- diag(5)
      if (is.data.frame(districts)) {
        for (i in seq_len(nrow(districts))) {
          mem <- toupper(unlist(districts$members[[i]])); rho <- as.numeric(districts$params$rho[i])
          a <- match(mem[1], names); b <- match(mem[2], names); C[a,b] <- C[b,a] <- rho
        }
      } else if (is.list(districts)) {
        for (d in districts) { mem <- toupper(unlist(d$members)); rho <- as.numeric(d$params$rho); a <- match(mem[1], names); b <- match(mem[2], names); C[a,b] <- C[b,a] <- rho }
      }
      C
    }
    Corr_global <- build_corr(cop$districts)
    by_group_corr <- list()
    if (!is.null(cop$by_group) && is.list(cop$by_group)) {
      for (nm in names(cop$by_group)) {
        if (is.null(cop$by_group[[nm]]$districts)) next
        by_group_corr[[nm]] <- build_corr(cop$by_group[[nm]]$districts)
      }
    }
    Corr_for_group <- function(glab) {
      if (!is.null(by_group_corr) && length(by_group_corr) && !is.null(glab) && nzchar(glab) && (glab %in% names(by_group_corr))) return(by_group_corr[[glab]])
      Corr_global
    }
    # Optional: per-group sigmas
    sigma_mode <- tolower(ifelse(is.null(opt$sigma_mode) || !nzchar(opt$sigma_mode), ifelse(!is.null(opt$group_col) && nzchar(opt$group_col), "by_group", "global"), opt$sigma_mode))
    group_vals <- NULL
    sigmas_by_group <- NULL
    group_col_use <- opt$group_col
    if (sigma_mode == "by_group" && !is.null(group_col_use) && nzchar(group_col_use)) {
      # Attach group column to 'base' if missing via reference join
      if (!(group_col_use %in% names(base))) {
        ref_path <- opt$group_ref_csv
        gid <- opt$group_ref_id_col
        gcol <- if (!is.null(opt$group_ref_group_col) && nzchar(opt$group_ref_group_col)) opt$group_ref_group_col else group_col_use
        if (file.exists(ref_path) && (gid %in% names(preds)) && (gcol %in% names(readr::read_csv(ref_path, show_col_types = FALSE, n_max = 1)))) {
          ref <- suppressMessages(readr::read_csv(ref_path, show_col_types = FALSE))
          base <- base %>% left_join(ref %>% select(all_of(c(gid, gcol))), by = setNames(gid, id_col))
          names(base)[names(base) == gcol] <- group_col_use
        } else {
          message("Group reference missing or columns not found; falling back to global sigmas")
        }
      }
      if (group_col_use %in% names(base)) {
        group_vals <- as.character(base[[group_col_use]])
        # compute per-group RMSE by joining Run7 preds to reference
        ref_path <- opt$group_ref_csv
        gid <- opt$group_ref_id_col
        gcol <- if (!is.null(opt$group_ref_group_col) && nzchar(opt$group_ref_group_col)) opt$group_ref_group_col else group_col_use
        if (file.exists(ref_path)) {
          ref <- suppressMessages(readr::read_csv(ref_path, show_col_types = FALSE))
          per_axis <- list()
          for (ax in axes) {
            ppath <- file.path(opt$metrics_dir, sprintf("sem_piecewise_%s_preds.csv", ax))
            if (!file.exists(ppath)) { per_axis[[ax]] <- NULL; next }
            dfp <- suppressMessages(readr::read_csv(ppath, show_col_types = FALSE))
            if (!("id" %in% names(dfp)) || !(gid %in% names(ref)) || !(gcol %in% names(ref))) { per_axis[[ax]] <- NULL; next }
            tmp <- dfp %>% left_join(ref %>% select(all_of(c(gid, gcol))), by = setNames(gid, "id"))
            if (!(gcol %in% names(tmp)) || !all(c("y_true","y_pred") %in% names(tmp))) { per_axis[[ax]] <- NULL; next }
            tmp <- tmp %>% mutate(err = y_true - y_pred) %>% filter(is.finite(err), !is.na(.data[[gcol]]))
            if (nrow(tmp) == 0) { per_axis[[ax]] <- NULL; next }
            agg <- tmp %>% group_by(.data[[gcol]]) %>% summarize(RMSE = sqrt(mean(err^2)), .groups = "drop")
            v <- agg$RMSE; names(v) <- as.character(agg[[gcol]]); per_axis[[ax]] <- v
          }
          sigmas_by_group <- per_axis
        }
      }
    }
    # Prepare predictions matrix
    mu_mat <- as.matrix(base[, paste0(axes, "_pred")])
    # Precompute residual draws
    nsim <- as.integer(opt$nsim_joint); if (!is.finite(nsim) || nsim < 1000) nsim <- 10000
    Z <- matrix(stats::rnorm(nsim*5), ncol=5)
    # Helper: pick sigma vector for group
    sigma_for_group <- function(glab) {
      s <- sigmas_global
      if (!is.null(sigmas_by_group) && length(sigmas_by_group)) {
        for (ax in axes) {
          vec <- sigmas_by_group[[ax]]
          if (!is.null(vec) && !is.na(glab) && nzchar(glab) && (glab %in% names(vec))) s[[ax]] <- as.numeric(vec[[glab]])
        }
      }
      s
    }
    # Bounds
    lo <- rep(-Inf, 5); hi <- rep(Inf, 5)
    for (k in seq_along(axes)) {
      ax <- axes[k]
      if (!is.null(req[[ax]])) { b <- bins[[ req[[ax]] ]]; lo[k] <- b[1]; hi[k] <- b[2] }
    }
    inside_rect_E <- function(Euse, mu) {
      Y <- sweep(Euse, 2, mu, "+")
      ok <- rep(TRUE, nrow(Y))
      for (j in 1:5) {
        if (is.finite(lo[j])) ok <- ok & (Y[,j] >= lo[j])
        if (is.finite(hi[j])) ok <- ok & (Y[,j] <= hi[j])
      }
      mean(ok)
    }
    # Compute by group (if available) else global
    if (!is.null(group_vals)) {
      probs <- numeric(nrow(mu_mat))
      glabs <- unique(group_vals)
      for (g in glabs) {
        idx <- which(group_vals == g)
        svec <- sigma_for_group(g)
        Cg <- Corr_for_group(g)
        Dg <- diag(as.numeric(svec[axes])); Sigmag <- Dg %*% Cg %*% Dg; Rg <- chol(Sigmag)
        Eg <- Z %*% Rg
        probs[idx] <- apply(mu_mat[idx, , drop = FALSE], 1, function(mu) inside_rect_E(Eg, mu))
      }
    } else {
      D <- diag(as.numeric(sigmas_global[names])); Sigma <- D %*% Corr_global %*% D; Rchol <- chol(Sigma)
      E <- Z %*% Rchol
      probs <- apply(mu_mat, 1, function(mu) inside_rect_E(E, mu))
    }
    recs$joint_requirement <- opt$joint_requirement
    recs$joint_prob <- probs
    recs$joint_ok <- recs$joint_prob >= as.numeric(opt$joint_min_prob)

    # Optional: add a global note for fails
    if (!"global_notes" %in% names(recs)) recs$global_notes <- ""
    idx_fail <- which(!recs$joint_ok)
    if (length(idx_fail)) {
      recs$global_notes[idx_fail] <- ifelse(nchar(recs$global_notes[idx_fail])>0,
        paste0(recs$global_notes[idx_fail], "; joint_prob_below_threshold"), "joint_prob_below_threshold")
    }
    # Rewrite output with joint columns
    readr::write_csv(recs, opt$output_csv)
    message(sprintf("Wrote recommendations with joint columns: %s", opt$output_csv))
  }

  # Optional: Batch presets — annotate best joint scenario per species
  if (!is.null(opt$joint_presets_csv) && nzchar(opt$joint_presets_csv)) {
    if (!file.exists(opt$joint_presets_csv)) stop(sprintf("Presets CSV not found: %s", opt$joint_presets_csv))
    message(sprintf("Annotating best joint scenario from presets: %s", opt$joint_presets_csv))
    presets <- suppressMessages(readr::read_csv(opt$joint_presets_csv, show_col_types = FALSE))
    reqs <- presets$requirement
    thr  <- if ("joint_min_prob" %in% names(presets)) as.numeric(presets$joint_min_prob) else rep(as.numeric(opt$joint_min_prob), nrow(presets))
    # Build Corr and Sigma once
    read_sigma <- function(dir, letter) {
      p <- file.path(dir, sprintf("sem_piecewise_%s_metrics.json", letter))
      jj <- jsonlite::fromJSON(p)
      ag <- jj$metrics$aggregate
      if (is.data.frame(ag)) as.numeric(ag$RMSE_mean[1]) else as.numeric(ag[[1]]$RMSE_mean)
    }
    sigmas_global <- c(L=read_sigma(opt$metrics_dir, "L"), T=read_sigma(opt$metrics_dir, "T"), M=read_sigma(opt$metrics_dir, "M"), R=read_sigma(opt$metrics_dir, "R"), N=read_sigma(opt$metrics_dir, "N"))
    cop <- jsonlite::fromJSON(opt$copulas_json)
    axes <- c("L","T","M","R","N")
    build_corr <- function(districts) {
      C <- diag(5)
      if (is.data.frame(districts)) {
        for (i in seq_len(nrow(districts))) {
          mem <- toupper(unlist(districts$members[[i]])); rho <- as.numeric(districts$params$rho[i])
          a <- match(mem[1], axes); b <- match(mem[2], axes); C[a,b] <- C[b,a] <- rho
        }
      } else if (is.list(districts)) {
        for (d in districts) { mem <- toupper(unlist(d$members)); rho <- as.numeric(d$params$rho); a <- match(mem[1], axes); b <- match(mem[2], axes); C[a,b] <- C[b,a] <- rho }
      }
      C
    }
    Corr_global <- build_corr(cop$districts)
    by_group_corr <- list()
    if (!is.null(cop$by_group) && is.list(cop$by_group)) {
      for (nm in names(cop$by_group)) {
        if (is.null(cop$by_group[[nm]]$districts)) next
        by_group_corr[[nm]] <- build_corr(cop$by_group[[nm]]$districts)
      }
    }
    Corr_for_group <- function(glab) {
      if (!is.null(by_group_corr) && length(by_group_corr) && !is.null(glab) && nzchar(glab) && (glab %in% names(by_group_corr))) return(by_group_corr[[glab]])
      Corr_global
    }
    # Optional per-group sigmas
    sigma_mode <- tolower(ifelse(is.null(opt$sigma_mode) || !nzchar(opt$sigma_mode), ifelse(!is.null(opt$group_col) && nzchar(opt$group_col), "by_group", "global"), opt$sigma_mode))
    group_vals <- NULL
    sigmas_by_group <- NULL
    group_col_use <- opt$group_col
    if (sigma_mode == "by_group" && !is.null(group_col_use) && nzchar(group_col_use)) {
      if (!(group_col_use %in% names(base))) {
        ref_path <- opt$group_ref_csv
        gid <- opt$group_ref_id_col
        gcol <- if (!is.null(opt$group_ref_group_col) && nzchar(opt$group_ref_group_col)) opt$group_ref_group_col else group_col_use
        if (file.exists(ref_path) && (gid %in% names(preds)) && (gcol %in% names(readr::read_csv(ref_path, show_col_types = FALSE, n_max = 1)))) {
          ref <- suppressMessages(readr::read_csv(ref_path, show_col_types = FALSE))
          base <- base %>% left_join(ref %>% select(all_of(c(gid, gcol))), by = setNames(gid, id_col))
          names(base)[names(base) == gcol] <- group_col_use
        }
      }
      if (group_col_use %in% names(base)) {
        group_vals <- as.character(base[[group_col_use]])
        ref <- suppressMessages(readr::read_csv(opt$group_ref_csv, show_col_types = FALSE))
        per_axis <- list()
        gid <- opt$group_ref_id_col
        gcol <- if (!is.null(opt$group_ref_group_col) && nzchar(opt$group_ref_group_col)) opt$group_ref_group_col else group_col_use
        for (ax in axes) {
          ppath <- file.path(opt$metrics_dir, sprintf("sem_piecewise_%s_preds.csv", ax))
          if (!file.exists(ppath)) { per_axis[[ax]] <- NULL; next }
          dfp <- suppressMessages(readr::read_csv(ppath, show_col_types = FALSE))
          tmp <- dfp %>% left_join(ref %>% select(all_of(c(gid, gcol))), by = setNames(gid, "id"))
          if (!(gcol %in% names(tmp)) || !all(c("y_true","y_pred") %in% names(tmp))) { per_axis[[ax]] <- NULL; next }
          tmp <- tmp %>% mutate(err = y_true - y_pred) %>% filter(is.finite(err), !is.na(.data[[gcol]]))
          if (nrow(tmp) == 0) { per_axis[[ax]] <- NULL; next }
          agg <- tmp %>% group_by(.data[[gcol]]) %>% summarize(RMSE = sqrt(mean(err^2)), .groups = "drop")
          v <- agg$RMSE; names(v) <- as.character(agg[[gcol]]); per_axis[[ax]] <- v
        }
        sigmas_by_group <- per_axis
      }
    }

    # Build default global Sigma (used when no groups)
    Sigma_global <- diag(as.numeric(sigmas_global)) %*% Corr_global %*% diag(as.numeric(sigmas_global))
    Rchol_global <- chol(Sigma_global)
    mu_mat <- as.matrix(base[, paste0(axes, "_pred")])
    nsim <- as.integer(opt$nsim_joint); if (!is.finite(nsim) || nsim < 1000) nsim <- 10000
    Z <- matrix(stats::rnorm(nsim*5), ncol=5)
    E_global <- Z %*% Rchol_global
    parse_req <- function(s) {
      bits <- strsplit(s, ",", fixed = TRUE)[[1]]
      out <- vector("list", length=0)
      for (b in bits) { kv <- strsplit(trimws(b), "=", fixed = TRUE)[[1]]; if (length(kv)!=2) next; out[[toupper(trimws(kv[1]))]] <- tolower(trimws(kv[2])) }
      out
    }
    inside_rect_E <- function(Euse, mu, lo, hi) {
      Y <- sweep(Euse, 2, mu, "+")
      ok <- rep(TRUE, nrow(Y))
      for (j in 1:5) { if (is.finite(lo[j])) ok <- ok & (Y[,j] >= lo[j]); if (is.finite(hi[j])) ok <- ok & (Y[,j] <= hi[j]) }
      mean(ok)
    }
    # Compute probs per preset
    probs_mat <- matrix(NA_real_, nrow=nrow(base), ncol=nrow(presets))
    for (i in seq_len(nrow(presets))) {
      pr <- parse_req(reqs[i])
      lo <- rep(-Inf, 5); hi <- rep(Inf, 5)
      for (k in seq_along(axes)) { ax <- axes[k]; if (!is.null(pr[[ax]])) { b <- parse_bins(opt$bins)[[ pr[[ax]] ]]; lo[k] <- b[1]; hi[k] <- b[2] } }
      # Compute probs per preset, by group if available
      if (!is.null(group_vals)) {
        pv <- numeric(nrow(mu_mat))
        for (g in unique(group_vals)) {
          idx <- which(group_vals == g)
          # choose group sigma
          svec <- sigmas_global
          if (!is.null(sigmas_by_group) && length(sigmas_by_group)) {
            for (ax in axes) {
              vec <- sigmas_by_group[[ax]]
              if (!is.null(vec) && (g %in% names(vec))) svec[[ax]] <- as.numeric(vec[[g]])
            }
          }
          Cg <- Corr_for_group(g)
          Dg <- diag(as.numeric(svec)); Sigmag <- Dg %*% Cg %*% Dg; Rg <- chol(Sigmag); Eg <- Z %*% Rg
          pv[idx] <- apply(mu_mat[idx, , drop = FALSE], 1, function(mu) inside_rect_E(Eg, mu, lo, hi))
        }
        probs_mat[,i] <- pv
      } else {
        probs_mat[,i] <- apply(mu_mat, 1, function(mu) inside_rect_E(E_global, mu, lo, hi))
      }
    }
    # Best scenario per species
    best_idx <- apply(probs_mat, 1, which.max)
    recs$best_scenario_label <- presets$label[best_idx]
    recs$best_scenario_prob  <- probs_mat[cbind(seq_len(nrow(recs)), best_idx)]
    thr_vec <- thr[best_idx]; recs$best_scenario_ok <- recs$best_scenario_prob >= thr_vec
    readr::write_csv(recs, opt$output_csv)
    message(sprintf("Wrote recommendations with best scenario columns: %s", opt$output_csv))
  }
}

main()
