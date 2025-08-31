#!/usr/bin/env Rscript

# Cross-validated blending of SEM mean-structure predictions (Run 7c-compatible)
# with phylogenetic neighbor predictors.
#
# - L uses the non-linear GAM (if provided via --gam_L_rds) matching Run 7c.
# - T/R use SIZE; M/N deconstruct SIZE (logH, logSM), per MAG_Run8 equations.
# - p_k is computed fold-safely from training species only; α tunes the blend.

suppressPackageStartupMessages({
  library(jsonlite)
  library(ape)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a) && a != "") a else b

parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  kv <- list()
  for (i in seq_along(args)) {
    if (grepl("^--", args[[i]])) {
      key <- sub("^--", "", args[[i]])
      val <- if (i < length(args) && !grepl("^--", args[[i+1]])) args[[i+1]] else ""
      kv[[key]] <- val
    }
  }
  kv
}

log_transform <- function(x, offset) ifelse(is.na(x), NA_real_, log10(as.numeric(x) + as.numeric(offset)))
zscore <- function(x, mean, sd) (x - mean) / sd

compute_composite <- function(df, comp_def, std) {
  vars <- comp_def$variables
  loads <- comp_def$loadings
  Z <- sapply(seq_along(vars), function(j) {
    v <- vars[[j]]; sgn <- 1
    if (startsWith(v, "-")) { sgn <- -1; v <- substring(v, 2) }
    m <- std[[v]][["mean"]]; s <- std[[v]][["sd"]]
    sgn * zscore(df[[v]], m, s)
  })
  as.numeric(as.matrix(Z) %*% matrix(unlist(loads), ncol = 1))
}

predict_target <- function(terms_map, data_row) {
  y <- 0
  for (nm in names(terms_map)) {
    beta <- terms_map[[nm]]
    if (nm == "(Intercept)") y <- y + beta else if (grepl(":", nm, fixed = TRUE)) {
      parts <- strsplit(nm, ":", fixed = TRUE)[[1]]
      y <- y + beta * prod(as.numeric(data_row[parts]))
    } else {
      y <- y + beta * as.numeric(data_row[[nm]])
    }
  }
  y
}

args <- parse_args()
input_csv <- args[["input_csv"]] %||% "artifacts/model_data_complete_case.csv"
species_col <- args[["species_col"]] %||% "wfo_accepted_name"
eive_cols <- strsplit(args[["eive_cols"]] %||% "EIVEres-L,EIVEres-T,EIVEres-M,EIVEres-R,EIVEres-N", ",")[[1]]
comp_json <- args[["composites_json"]] %||% "results/MAG_Run8/composite_recipe.json"
eq_json <- args[["equations_json"]] %||% "results/MAG_Run8/mag_equations.json"
phylo_newick <- args[["phylogeny_newick"]] %||% "data/phylogeny/eive_try_tree.nwk"
xexp <- as.numeric(args[["x"]] %||% 2)
alpha_grid <- as.numeric(strsplit(args[["alpha_grid"]] %||% "0,0.25,0.5,0.75,1", ",")[[1]])
k_trunc <- as.integer(args[["k_trunc"]] %||% 0)
repeats <- as.integer(args[["repeats"]] %||% 2)
folds <- as.integer(args[["folds"]] %||% 5)
seed <- as.integer(args[["seed"]] %||% 42)
out_csv <- args[["output_csv"]] %||% "artifacts/sem_phylo_blend_cv_results.csv"
gam_L_rds <- args[["gam_L_rds"]] %||% ""

cat(sprintf("Effective parameters:\n  input_csv=%s\n  species_col=%s\n  eive_cols=%s\n  composites_json=%s\n  equations_json=%s\n  phylogeny_newick=%s\n  gam_L_rds=%s\n  x=%s\n  alpha_grid=%s\n  k_trunc=%d\n  repeats=%d folds=%d seed=%d\n  output_csv=%s\n",
            input_csv, species_col, paste(eive_cols, collapse=","), comp_json, eq_json,
            phylo_newick, gam_L_rds, xexp, paste(alpha_grid, collapse=","), k_trunc, repeats, folds, seed, out_csv))

stopifnot(file.exists(input_csv), file.exists(comp_json), file.exists(eq_json), file.exists(phylo_newick))

df0 <- read.csv(input_csv, stringsAsFactors = FALSE, check.names = FALSE)
if (!(species_col %in% names(df0))) stop(sprintf("Missing species_col: %s", species_col))
miss_tgt <- setdiff(eive_cols, names(df0)); if (length(miss_tgt) > 0) stop(sprintf("Missing targets: %s", paste(miss_tgt, collapse=",")))

comp <- jsonlite::fromJSON(comp_json, simplifyVector = TRUE)
eq <- jsonlite::fromJSON(eq_json, simplifyVector = TRUE)

# Map input columns to keys based on schema
schema <- comp$input_schema$columns
if (is.data.frame(schema)) {
  name_to_key <- setNames(schema$key, schema$name)
} else if (is.list(schema)) {
  name_to_key <- setNames(vapply(schema, function(s) s$key, ""), vapply(schema, function(s) s$name, ""))
} else stop("Unexpected schema format in composites JSON")
for (nm in names(name_to_key)) {
  key <- name_to_key[[nm]]
  if (nm %in% names(df0)) df0[[key]] <- df0[[nm]]
}

required_keys <- c("LMA","Nmass","LeafArea","PlantHeight","DiasporeMass","SSD")
missing_keys <- setdiff(required_keys, names(df0))
if (length(missing_keys) > 0) stop(sprintf("Missing required keys after mapping: %s", paste(missing_keys, collapse=",")))

# Build features
offs <- comp$log_offsets
df0$logLA  <- log_transform(df0$LeafArea, offs[["Leaf area (mm2)"]] %||% 0)
df0$logH   <- log_transform(df0$PlantHeight, offs[["Plant height (m)"]] %||% 0)
df0$logSM  <- log_transform(df0$DiasporeMass, offs[["Diaspore mass (mg)"]] %||% 0)
df0$logSSD <- log_transform(df0$SSD, offs[["SSD used (mg/mm3)"]] %||% 0)

std <- comp$standardization
df0$LES_core <- compute_composite(df0[c("LMA","Nmass")], comp$composites$LES_core, std)
df0$SIZE     <- compute_composite(df0[c("logH","logSM")], comp$composites$SIZE, std)
df0$LES <- df0$LES_core

# SEM predictions (deterministic for T/M/R/N; provisional for L)
targets <- names(eq$equations)
for (t in targets) {
  terms <- eq$equations[[t]]$terms
  df0[[paste0(t, "_sem")]] <- apply(df0, 1, function(r) predict_target(terms, as.list(r)))
}

# Override L with non-linear GAM if provided (Run 7c)
if (nzchar(gam_L_rds) && file.exists(gam_L_rds)) {
  if (!requireNamespace("mgcv", quietly = TRUE)) {
    warning("mgcv not available; cannot use --gam_L_rds; keeping linear L from equations.")
  } else {
    gm <- tryCatch(readRDS(gam_L_rds), error = function(e) NULL)
    if (is.null(gm)) {
      warning(sprintf("Failed to read GAM RDS: %s; keeping linear L from equations.", gam_L_rds))
    } else {
      # Build mgcv feature frame using log10 + small offsets (approximate 7c preproc)
      compute_offset <- function(x) {
        x <- as.numeric(x)
        x <- x[is.finite(x) & !is.na(x) & x > 0]
        if (!length(x)) return(1e-6)
        max(1e-6, 1e-3 * stats::median(x))
      }
      # Prefer original column names if present; else use keys
      la_raw  <- if ("Leaf area (mm2)" %in% names(df0)) df0[["Leaf area (mm2)"]] else df0$LeafArea
      h_raw   <- if ("Plant height (m)" %in% names(df0)) df0[["Plant height (m)"]] else df0$PlantHeight
      ssd_raw <- if ("SSD used (mg/mm3)" %in% names(df0)) df0[["SSD used (mg/mm3)"]] else df0$SSD
      off_la  <- compute_offset(la_raw)
      off_h   <- compute_offset(h_raw)
      off_ssd <- compute_offset(ssd_raw)
      new_mg <- data.frame(
        LMA = df0$LMA,
        Nmass = df0$Nmass,
        logLA = log10(la_raw + off_la),
        logH = log10(h_raw + off_h),
        logSSD = log10(ssd_raw + off_ssd)
      )
      df0$L_sem <- tryCatch(as.numeric(stats::predict(gm, newdata = new_mg, type = "link")),
                            error = function(e) { warning(sprintf("GAM predict failed: %s", e$message)); df0$L_sem })
    }
  }
}

# Keep only complete cases for targets and species mapping to tree
df <- df0[complete.cases(df0[, eive_cols, drop = FALSE]), , drop = FALSE]
species <- df[[species_col]]

# Phylogenetic distances
tree <- ape::read.tree(phylo_newick)
tips <- tree$tip.label
species_tips <- gsub(" ", "_", species, fixed = TRUE)
in_tree <- species_tips %in% tips
df <- df[in_tree, , drop = FALSE]
species_tips <- species_tips[in_tree]

tree2 <- ape::keep.tip(tree, unique(species_tips))
cop <- ape::cophenetic.phylo(tree2)
pos <- match(species_tips, rownames(cop))
if (any(is.na(pos))) stop("Failed to align species to cophenetic matrix")
D <- cop[pos, pos, drop = FALSE]
diag(D) <- 0

# CV setup
set.seed(seed)
n <- nrow(df)
alpha_grid <- sort(unique(pmin(pmax(alpha_grid, 0), 1)))
idx_all <- seq_len(n)

# helper: compute p_k fold-safely
pvalue_cv <- function(D, E, train_idx, x = 2, k_trunc = 0L) {
  n <- length(E)
  W <- matrix(0, n, n)
  pos <- which(D > 0)
  W[pos] <- 1 / (D[pos]^x)
  diag(W) <- 0
  W[-train_idx, ] <- 0
  if (k_trunc > 0L) {
    for (j in seq_len(n)) {
      dcol <- D[, j]
      ord <- order(dcol, na.last = NA)
      ord <- ord[ord %in% train_idx & dcol[ord] > 0]
      if (length(ord) > k_trunc) {
        drop_rows <- setdiff(train_idx, ord[seq_len(k_trunc)])
        if (length(drop_rows) > 0) W[drop_rows, j] <- 0
      }
    }
  }
  top <- as.numeric(crossprod(E, W))
  bot <- colSums(W)
  mu <- mean(E[train_idx])
  ifelse(bot > .Machine$double.eps, top / bot, mu)
}

results <- list()
for (axis in eive_cols) {
  y <- df[[axis]]
  r2_alpha <- setNames(numeric(length(alpha_grid)), as.character(alpha_grid))
  mae_alpha <- r2_alpha
  for (ai in seq_along(alpha_grid)) {
    a <- alpha_grid[[ai]]
    r2s <- c(); maes <- c()
    for (rep in seq_len(repeats)) {
      fold_ids <- sample(rep(seq_len(folds), length.out = n))
      for (fold in seq_len(folds)) {
        test_idx <- which(fold_ids == fold)
        train_idx <- setdiff(idx_all, test_idx)

        # Compute SEM predictions for this fold and axis
        y_sem_te <- NA_real_
        if (axis == "EIVEres-L") {
          # Use fixed GAM predictions if available, else linear export
          if (!is.null(df$L_sem)) {
            y_sem_te <- df$L_sem[test_idx]
          } else {
            terms <- eq$equations[["L"]]$terms
            y_sem_te <- apply(df[test_idx, , drop = FALSE], 1, function(r) predict_target(terms, as.list(r)))
          }
        } else if (axis %in% c("EIVEres-T","EIVEres-R")) {
          zsc <- function(x, idx) { m <- mean(x[idx], na.rm=TRUE); s <- stats::sd(x[idx], na.rm=TRUE); if (!is.finite(s) || s==0) s <- 1; list(m=m,s=s) }
          zs_LMA <- zsc(df$LMA, train_idx); zs_Nm <- zsc(df$Nmass, train_idx)
          M_LES_tr <- cbind(negLMA = -(df$LMA[train_idx] - zs_LMA$m)/zs_LMA$s,
                            Nmass  =  (df$Nmass[train_idx] - zs_Nm$m)/zs_Nm$s)
          p_les <- stats::prcomp(M_LES_tr, center = FALSE, scale. = FALSE)
          rot_les <- p_les$rotation[,1]; if (rot_les["Nmass"] < 0) rot_les <- -rot_les
          LES_all <- (-(df$LMA - zs_LMA$m)/zs_LMA$s) * rot_les["negLMA"] + ((df$Nmass - zs_Nm$m)/zs_Nm$s) * rot_les["Nmass"]
          zs_logH <- zsc(df$logH, train_idx); zs_logSM <- zsc(df$logSM, train_idx)
          M_SIZE_tr <- cbind(logH = (df$logH[train_idx] - zs_logH$m)/zs_logH$s,
                             logSM= (df$logSM[train_idx] - zs_logSM$m)/zs_logSM$s)
          p_size <- stats::prcomp(M_SIZE_tr, center = FALSE, scale. = FALSE)
          rot_size <- p_size$rotation[,1]; if (rot_size["logH"] < 0) rot_size <- -rot_size
          SIZE_all <- ((df$logH - zs_logH$m)/zs_logH$s) * rot_size["logH"] + ((df$logSM - zs_logSM$m)/zs_logSM$s) * rot_size["logSM"]
          dat_tr <- data.frame(y=y[train_idx], LES=LES_all[train_idx], SIZE=SIZE_all[train_idx], logSSD=df$logSSD[train_idx], logLA=df$logLA[train_idx])
          fm <- stats::lm(y ~ LES + SIZE + logSSD + logLA, data = dat_tr)
          dat_te <- data.frame(LES=LES_all[test_idx], SIZE=SIZE_all[test_idx], logSSD=df$logSSD[test_idx], logLA=df$logLA[test_idx])
          y_sem_te <- as.numeric(stats::predict(fm, newdata = dat_te))
        } else if (axis == "EIVEres-M") {
          zsc <- function(x, idx) { m <- mean(x[idx], na.rm=TRUE); s <- stats::sd(x[idx], na.rm=TRUE); if (!is.finite(s) || s==0) s <- 1; list(m=m,s=s) }
          zs_LMA <- zsc(df$LMA, train_idx); zs_Nm <- zsc(df$Nmass, train_idx)
          M_LES_tr <- cbind(negLMA = -(df$LMA[train_idx] - zs_LMA$m)/zs_LMA$s,
                            Nmass  =  (df$Nmass[train_idx] - zs_Nm$m)/zs_Nm$s)
          p_les <- stats::prcomp(M_LES_tr, center = FALSE, scale. = FALSE)
          rot_les <- p_les$rotation[,1]; if (rot_les["Nmass"] < 0) rot_les <- -rot_les
          LES_all <- (-(df$LMA - zs_LMA$m)/zs_LMA$s) * rot_les["negLMA"] + ((df$Nmass - zs_Nm$m)/zs_Nm$s) * rot_les["Nmass"]
          dat_tr <- data.frame(y=y[train_idx], LES=LES_all[train_idx], logH=df$logH[train_idx], logSM=df$logSM[train_idx], logSSD=df$logSSD[train_idx], logLA=df$logLA[train_idx])
          fm <- stats::lm(y ~ LES + logH + logSM + logSSD + logLA, data = dat_tr)
          dat_te <- data.frame(LES=LES_all[test_idx], logH=df$logH[test_idx], logSM=df$logSM[test_idx], logSSD=df$logSSD[test_idx], logLA=df$logLA[test_idx])
          y_sem_te <- as.numeric(stats::predict(fm, newdata = dat_te))
        } else if (axis == "EIVEres-N") {
          zsc <- function(x, idx) { m <- mean(x[idx], na.rm=TRUE); s <- stats::sd(x[idx], na.rm=TRUE); if (!is.finite(s) || s==0) s <- 1; list(m=m,s=s) }
          zs_LMA <- zsc(df$LMA, train_idx); zs_Nm <- zsc(df$Nmass, train_idx)
          M_LES_tr <- cbind(negLMA = -(df$LMA[train_idx] - zs_LMA$m)/zs_LMA$s,
                            Nmass  =  (df$Nmass[train_idx] - zs_Nm$m)/zs_Nm$s)
          p_les <- stats::prcomp(M_LES_tr, center = FALSE, scale. = FALSE)
          rot_les <- p_les$rotation[,1]; if (rot_les["Nmass"] < 0) rot_les <- -rot_les
          LES_all <- (-(df$LMA - zs_LMA$m)/zs_LMA$s) * rot_les["negLMA"] + ((df$Nmass - zs_Nm$m)/zs_Nm$s) * rot_les["Nmass"]
          dat_tr <- data.frame(y=y[train_idx], LES=LES_all[train_idx], logH=df$logH[train_idx], logSM=df$logSM[train_idx], logSSD=df$logSSD[train_idx], logLA=df$logLA[train_idx])
          fm <- stats::lm(y ~ LES + logH + logSM + logSSD + logLA + LES:logSSD, data = dat_tr)
          dat_te <- data.frame(LES=LES_all[test_idx], logH=df$logH[test_idx], logSM=df$logSM[test_idx], logSSD=df$logSSD[test_idx], logLA=df$logLA[test_idx])
          y_sem_te <- as.numeric(stats::predict(fm, newdata = dat_te))
        }

        # p_k via training-only donors
        p_all <- pvalue_cv(D, y, train_idx, x = xexp, k_trunc = k_trunc)
        yhat <- (1 - a) * y_sem_te + a * p_all[test_idx]
        y_te <- y[test_idx]
        sse <- sum((y_te - yhat)^2)
        sst <- sum((y_te - mean(y[train_idx]))^2)
        r2s <- c(r2s, 1 - sse / (ifelse(sst > 0, sst, .Machine$double.eps)))
        maes <- c(maes, mean(abs(y_te - yhat)))
      }
    }
    r2_alpha[[ai]] <- mean(r2s); mae_alpha[[ai]] <- mean(maes)
  }
  best_idx <- which.max(r2_alpha)
  best_alpha <- alpha_grid[[best_idx]]
  results[[length(results) + 1L]] <- data.frame(
    axis = axis, alpha = alpha_grid,
    r2_mean = as.numeric(r2_alpha),
    mae_mean = as.numeric(mae_alpha),
    best_alpha = best_alpha,
    stringsAsFactors = FALSE
  )
}

res <- do.call(rbind, results)
res <- res[order(res$axis, res$alpha), ]
dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)
write.csv(res, out_csv, row.names = FALSE)
cat(sprintf("Wrote SEM+phylo blend CV results: %s (rows %d)\n", out_csv, nrow(res)))
