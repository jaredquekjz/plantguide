#!/usr/bin/env Rscript

# Predict EIVE values using Stage 2 canonical best models.
# - Axes L and T load the stored GAM best models (mgcv objects).
# - Axes M, N, R use the pwSEM+phylo y-equations reconstructed as mgcv GAMs.
# - Input data: Stage 2 SEM-ready datasets with trait, climate, and phylo predictors.
# - Output: table (CSV or JSON) of predictions for requested species.

suppressPackageStartupMessages({
  library(mgcv)
  library(readr)
  library(dplyr)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)

parse_args <- function(args) {
  out <- list()
  i <- 1
  while (i <= length(args)) {
    a <- args[[i]]
    if (grepl("^--[A-Za-z0-9_-]+=", a)) {
      kv <- sub("^--", "", a)
      key <- sub("=.*$", "", kv)
      val <- sub("^[^=]*=", "", kv)
      out[[key]] <- val
      i <- i + 1
    } else if (grepl("^--[A-Za-z0-9_-]+$", a)) {
      key <- sub("^--", "", a)
      val <- if (i < length(args)) args[[i + 1]] else ""
      if (nzchar(val) && !startsWith(val, "--")) {
        out[[key]] <- val
        i <- i + 2
      } else {
        out[[key]] <- "true"
        i <- i + 1
      }
    } else {
      i <- i + 1
    }
  }
  out
}

opts <- parse_args(args)

if (!is.null(opts$help)) {
  cat("Predict Stage 2 best-model EIVE values.\n")
  cat("Usage:\n")
  cat("  Rscript src/Stage_7_Validation/predict_stage2_best_models.R --slugs acer-saccharum,abutilon-theophrasti --output preds.csv\n")
  cat("Options:\n")
  cat("  --slugs    Comma-separated Stage 8 slugs (lowercase, hyphenated).\n")
  cat("  --species  Comma-separated WFO accepted names (overrides slugs).\n")
  cat("  --output   Output path (.csv or .json). Defaults to stdout (CSV).\n")
  quit(status = 0)
}

slugify <- function(x) {
  x <- tolower(x)
  x <- gsub("[^a-z0-9]+", "-", x)
  x <- gsub("^-+", "", x)
  x <- gsub("-+$", "", x)
  x
}

split_arg <- function(txt) {
  if (is.null(txt) || !nzchar(txt)) return(character())
  parts <- unlist(strsplit(txt, ","))
  trimws(parts[nzchar(parts)])
}

# Data paths ---------------------------------------------------------------
get_script_path <- function() {
  args_full <- commandArgs(trailingOnly = FALSE)
  file_arg <- "--file="
  idx <- grep(file_arg, args_full)
  if (length(idx)) {
    normalizePath(sub(file_arg, "", args_full[idx[1]]), winslash = "/", mustWork = TRUE)
  } else {
    normalizePath("src/Stage_7_Validation/predict_stage2_best_models.R", winslash = "/", mustWork = FALSE)
  }
}

script_path <- get_script_path()
repo_root <- normalizePath(file.path(dirname(script_path), "..", ".."), winslash = "/", mustWork = TRUE)
dataset_base <- file.path(repo_root, "artifacts", "model_data_bioclim_subset_sem_ready_20250920_stage2.csv")
dataset_pcs <- file.path(repo_root, "artifacts", "model_data_bioclim_subset_sem_ready_20250920_stage2_pcs.csv")

if (!file.exists(dataset_base)) stop("Stage 2 base dataset not found: ", dataset_base)
if (!file.exists(dataset_pcs)) stop("Stage 2 dataset with PCs not found: ", dataset_pcs)

df_base <- read_csv(dataset_base, show_col_types = FALSE)
df_pcs  <- read_csv(dataset_pcs,  show_col_types = FALSE) %>%
  select(`wfo_accepted_name`, starts_with("pc_trait_"))

df <- df_base %>%
  left_join(df_pcs, by = "wfo_accepted_name") %>%
  mutate(
    slug = slugify(`wfo_accepted_name`),
    EIVEres_L = `EIVEres-L`,
    EIVEres_T = `EIVEres-T`,
    EIVEres_M = `EIVEres-M`,
    EIVEres_R = `EIVEres-R`,
    EIVEres_N = `EIVEres-N`
  )

target_slugs <- split_arg(opts$slugs)
target_species <- split_arg(opts$species)

if (length(target_species)) {
  # map species names to dataset rows directly
  wfo_targets <- tolower(target_species)
  df_subset <- df[tolower(df$`wfo_accepted_name`) %in% wfo_targets, ]
} else if (length(target_slugs)) {
  df_subset <- df[df$slug %in% target_slugs, ]
} else {
  df_subset <- df
}

if (!nrow(df_subset)) {
  stop("No matching species found for supplied slugs/species.")
}

# Helper utilities --------------------------------------------------------

`%||%` <- function(a, b) if (!is.null(a) && length(a) && !all(is.na(a))) a else b

compute_offset <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x) & !is.na(x) & x > 0]
  if (!length(x)) return(1e-6)
  max(1e-6, 1e-3 * stats::median(x))
}

add_log_columns <- function(df) {
  vars <- c(`Leaf area (mm2)` = "logLA", `Plant height (m)` = "logH",
            `Diaspore mass (mg)` = "logSM", `SSD used (mg/mm3)` = "logSSD")
  offsets <- sapply(names(vars), function(v) compute_offset(df[[v]]))
  for (nm in names(vars)) {
    df[[vars[[nm]]]] <- log10(as.numeric(df[[nm]]) + offsets[[nm]])
  }
  df
}

build_pc_scores <- function(matrix_train) {
  mat <- scale(matrix_train, center = TRUE, scale = TRUE)
  pr <- prcomp(mat, center = FALSE, scale. = FALSE)
  list(pr = pr, center = attr(mat, "scaled:center"), scale = attr(mat, "scaled:scale"))
}

apply_pc_scores <- function(matrix_test, pc_info, component = 1) {
  if (is.null(pc_info$pr)) return(rep(NA_real_, nrow(matrix_test)))
  scaled <- scale(matrix_test, center = pc_info$center, scale = pc_info$scale)
  scores <- as.matrix(scaled) %*% pc_info$pr$rotation[, component]
  drop(scores)
}

prepare_composites <- function(df_full) {
  df_full <- add_log_columns(df_full)

  # LES using negLMA and Nmass
  les_mat <- cbind(negLMA = -as.numeric(df_full$`LMA (g/m2)`),
                   Nmass = as.numeric(df_full$`Nmass (mg/g)`))
  ok_les <- stats::complete.cases(les_mat)
  if (sum(ok_les) < 3) stop("Insufficient data to compute LES composite.")
  les_pc <- build_pc_scores(les_mat[ok_les, , drop = FALSE])
  rot <- les_pc$pr$rotation[, 1]
  if (!is.na(rot["Nmass"]) && rot["Nmass"] < 0) {
    les_pc$pr$rotation[, 1] <- -rot
  }
  df_full$LES <- apply_pc_scores(les_mat, les_pc, component = 1)

  # SIZE using logH and logSM
  size_mat <- cbind(logH = df_full$logH, logSM = df_full$logSM)
  ok_size <- stats::complete.cases(size_mat)
  if (sum(ok_size) < 3) stop("Insufficient data to compute SIZE composite.")
  size_pc <- build_pc_scores(size_mat[ok_size, , drop = FALSE])
  rot_size <- size_pc$pr$rotation[, 1]
  if (!is.na(rot_size["logH"]) && rot_size["logH"] < 0) {
    size_pc$pr$rotation[, 1] <- -rot_size
  }
  df_full$SIZE <- apply_pc_scores(size_mat, size_pc, component = 1)

  list(data = df_full, les_info = les_pc, size_info = size_pc)
}

comp <- prepare_composites(df)
df_prepped <- comp$data

# Prediction helpers ------------------------------------------------------

ensure_factors <- function(df_train, df_new, cols) {
  for (col in cols) {
    if (!col %in% names(df_train)) next
    if (!is.factor(df_train[[col]])) df_train[[col]] <- as.factor(df_train[[col]])
    if (col %in% names(df_new)) {
      df_new[[col]] <- factor(df_new[[col]], levels = levels(df_train[[col]]))
    }
  }
  list(train = df_train, new = df_new)
}

predict_axis_gamfile <- function(model_path, train_df, new_df) {
  if (!file.exists(model_path)) stop("Model file missing: ", model_path)
  model <- readRDS(model_path)
  temp_new <- new_df
  fac_cols <- names(model$var.summary)[sapply(model$var.summary, function(x) is.factor(x) || is.character(x))]
  if (length(fac_cols)) {
    for (col in fac_cols) {
      if (!col %in% names(temp_new)) next
      levels_ref <- if (is.factor(model$var.summary[[col]])) levels(model$var.summary[[col]]) else unique(model$var.summary[[col]])
      temp_new[[col]] <- factor(temp_new[[col]], levels = levels_ref)
    }
  }
  as.numeric(predict(model, newdata = temp_new, type = "response"))
}

fit_pwsem_gam <- function(axis, formula_txt, df_full) {
  y_col <- paste0("EIVEres-", axis)
  train <- df_full %>% filter(!is.na(.data[[y_col]]))
  if (!nrow(train)) stop("No training rows available for axis ", axis)
  train$y <- train[[y_col]]
  fac_prep <- ensure_factors(train, df_prepped, c("Family"))
  train <- fac_prep$train
  mgcv::gam(stats::as.formula(formula_txt), data = train, method = "REML")
}

pwsem_formulas <- list(
  M = "y ~ LES + logH + logSM + logSSD + logLA + s(precip_seasonality, k=5) + s(ai_roll3_min, k=5) + ti(SIZE, precip_mean, k=c(4,4)) + ti(LMA, precip_mean, k=c(4,4)) + p_phylo_M",
  N = "y ~ LES + logH + logSM + logSSD + logLA + LES:logSSD + s(precip_cv, k=5) + s(mat_q95, k=5) + ti(SIZE, precip_mean, k=c(4,4)) + p_phylo_N",
  R = "y ~ LES + SIZE + logLA + s(phh2o_5_15cm_mean, k=5) + s(phh2o_5_15cm_p90, k=5) + s(ph_rootzone_mean, k=5) + ti(ph_rootzone_mean, drought_min, k=c(4,4)) + ti(ph_rootzone_mean, precip_driest_q, k=c(4,4)) + p_phylo_R"
)

best_model_paths <- list(
  L = file.path(repo_root, "results", "aic_selection_L_tensor_pruned", "best_model.rds"),
  T = file.path(repo_root, "results", "aic_selection_T_pc", "best_model.rds")
)

predict_axis <- function(axis, df_new) {
  y_col <- paste0("EIVEres-", axis)
  df_axis <- df_prepped

  if (axis %in% names(best_model_paths)) {
    preds <- predict_axis_gamfile(best_model_paths[[axis]], df_axis, df_new)
    list(preds = preds, model = paste0("GAM (stored best_model)") )
  } else {
    formula_txt <- pwsem_formulas[[axis]]
    model <- fit_pwsem_gam(axis, formula_txt, df_axis)
    preds <- as.numeric(predict(model, newdata = df_new, type = "response"))
    list(preds = preds, model = paste0("pwSEM+phylo reconstructed GAM"))
  }
}

df_targets <- df_prepped[df_prepped$slug %in% df_subset$slug, , drop = FALSE]

axes <- c("L", "M", "R", "N", "T")
all_preds <- list()

for (axis in axes) {
  pred_info <- predict_axis(axis, df_targets)
  preds <- pmax(0, pmin(10, pred_info$preds))
  all_preds[[axis]] <- data.frame(
    slug = df_targets$slug,
    species = df_targets$`wfo_accepted_name`,
    axis = axis,
    prediction = preds,
    model = pred_info$model,
    stringsAsFactors = FALSE
  )
}

result_df <- bind_rows(all_preds) %>% arrange(slug, axis)

if (!is.null(opts$output) && nzchar(opts$output)) {
  out_path <- opts$output
  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  if (grepl("\\.json$", tolower(out_path))) {
    write_json(result_df, out_path, pretty = TRUE, auto_unbox = TRUE)
  } else {
    write_csv(result_df, out_path)
  }
} else {
  write.csv(result_df, stdout(), row.names = FALSE)
}
