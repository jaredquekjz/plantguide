#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(jsonlite)
  library(readr)
  library(dplyr)
  library(purrr)
  library(stringr)
  library(tidyr)
  library(stats)
})

args <- commandArgs(trailingOnly = TRUE)

parse_args <- function(args) {
  kv <- list(
    input_csv = NULL,
    recipe_json = "results/composite_recipe.json",
    spouses = NULL,                # comma-separated like "L-M,T-R"
    spouses_csv = NULL,            # optional: results/stage_sem_run8_copula_fits.csv
    out_summary = "results/msep_test_summary.csv",
    out_claims = "results/msep_claims.csv",
    # New options to align with SEMwise flow
    cluster_var = "",             # e.g., Family; if present and lme4 available, fit random intercepts
    force_lm = "false",           # if true, never try lme4
    corr_method = "pearson",       # pearson|spearman|kendall (used in cor.test)
    rank_pit = "false",           # if true, map residuals to (rank-0.5)/n; if corr_method=pearson, test on normal scores
    fdr_q = "0.05"                # BH-FDR level (used for reporting only)
  )
  if (length(args) %% 2 != 0) stop("Invalid arguments. Use --key value pairs")
  for (i in seq(1, length(args), by = 2)) {
    key <- gsub("^--", "", args[[i]])
    val <- args[[i + 1]]
    if (!key %in% names(kv)) stop(sprintf("Unknown flag: --%s", key))
    kv[[key]] <- val
  }
  if (is.null(kv$input_csv)) stop("Missing --input_csv <path>")
  kv
}

`%||%` <- function(a, b) if (is.null(a)) b else a

log_transform <- function(x, offset) {
  ifelse(is.na(x), NA_real_, log(as.numeric(x) + as.numeric(offset)))
}

zscore <- function(x, mean, sd) {
  (x - mean) / sd
}

compute_composite <- function(df, comp_def, std) {
  vars <- comp_def$variables
  loads <- comp_def$loadings
  if (length(vars) != length(loads)) stop("Composite variables and loadings length mismatch")

  Z <- purrr::map_dfc(seq_along(vars), function(j) {
    v <- vars[[j]]
    sgn <- 1
    if (startsWith(v, "-")) { sgn <- -1; v <- substring(v, 2) }
    if (!v %in% names(df)) stop(sprintf("Missing variable for composite: %s", v))
    if (!v %in% names(std)) stop(sprintf("Missing standardization for variable: %s", v))
    m <- std[[v]][["mean"]]
    s <- std[[v]][["sd"]]
    sgn * zscore(df[[v]], m, s)
  })
  comp <- as.matrix(Z) %*% matrix(unlist(loads), ncol = 1)
  as.numeric(comp)
}

parse_spouses <- function(opt) {
  # returns a set of pairs like c("L-M","T-R") with A<B lexicographically
  pairs <- character(0)
  if (!is.null(opt$spouses) && nzchar(opt$spouses)) {
    items <- unlist(strsplit(opt$spouses, ","))
    pairs <- trimws(items)
  }
  if (is.null(opt$spouses_csv) || !file.exists(opt$spouses_csv)) return(unique(pairs))
  # Expect a CSV with columns A,B (or Pair)
  df <- tryCatch(readr::read_csv(opt$spouses_csv, show_col_types = FALSE), error = function(e) NULL)
  if (!is.null(df)) {
    if (all(c("A","B") %in% names(df))) {
      add <- sprintf("%s-%s", df$A, df$B)
      pairs <- c(pairs, add)
    } else if ("Pair" %in% names(df)) {
      pairs <- c(pairs, df$Pair)
    }
  }
  unique(pairs)
}

main <- function() {
  opt <- parse_args(args)

  # Parse booleans/numerics
  tf <- function(x) tolower(x %||% "false") %in% c("1","true","yes","y")
  rank_pit <- tf(opt$rank_pit)
  force_lm <- tf(opt$force_lm)
  corr_method <- tolower(opt$corr_method %||% "pearson")
  if (!corr_method %in% c("pearson","spearman","kendall")) stop("--corr_method must be pearson|spearman|kendall")
  fdr_q <- suppressWarnings(as.numeric(opt$fdr_q %||% "0.05")); if (!is.finite(fdr_q)) fdr_q <- 0.05
  cluster_var <- opt$cluster_var %||% ""

  # Read data and recipe
  df <- suppressMessages(readr::read_csv(opt$input_csv, show_col_types = FALSE))
  recipe <- jsonlite::fromJSON(opt$recipe_json, simplifyVector = TRUE)
  offs <- recipe$log_offsets
  std <- recipe$standardization
  comps <- recipe$composites

  # Ensure short names exist for composites
  if (!"LMA" %in% names(df) && "LMA (g/m2)" %in% names(df)) df$LMA <- df[["LMA (g/m2)"]]
  if (!"Nmass" %in% names(df) && "Nmass (mg/g)" %in% names(df)) df$Nmass <- df[["Nmass (mg/g)"]]

  df <- df %>% dplyr::mutate(
    logLA = log_transform(.data[["Leaf area (mm2)"]] %||% .data[["LeafArea"]], offs[["Leaf area (mm2)"]] %||% 0),
    logH  = log_transform(.data[["Plant height (m)"]] %||% .data[["PlantHeight"]], offs[["Plant height (m)"]] %||% 0),
    logSM = log_transform(.data[["Diaspore mass (mg)"]] %||% .data[["DiasporeMass"]], offs[["Diaspore mass (mg)"]] %||% 0),
    logSSD= log_transform(.data[["SSD used (mg/mm3)"]] %||% .data[["SSD"]], offs[["SSD used (mg/mm3)"]] %||% 0)
  )

  # Targets: map EIVEres-* to short L/T/M/R/N if needed
  if (!"L" %in% names(df) && "EIVEres-L" %in% names(df)) df$L <- df[["EIVEres-L"]]
  if (!"T" %in% names(df) && "EIVEres-T" %in% names(df)) df$T <- df[["EIVEres-T"]]
  if (!"M" %in% names(df) && "EIVEres-M" %in% names(df)) df$M <- df[["EIVEres-M"]]
  if (!"R" %in% names(df) && "EIVEres-R" %in% names(df)) df$R <- df[["EIVEres-R"]]
  if (!"N" %in% names(df) && "EIVEres-N" %in% names(df)) df$N <- df[["EIVEres-N"]]

  if (!is.null(comps$LES_core)) {
    df$LES_core <- compute_composite(
      df %>% dplyr::select(dplyr::any_of(c("LMA","Nmass"))),
      comps$LES_core,
      std
    )
  } else stop("LES_core composite missing in recipe")

  if (!is.null(comps$SIZE)) {
    if (is.null(std$logH) || is.null(std$logSM)) stop("Standardization for logH/logSM missing in recipe")
    df$SIZE <- compute_composite(df %>% dplyr::select(logH, logSM), comps$SIZE, std)
  } else stop("SIZE composite missing in recipe")

  df$LES <- df$LES_core

  # Restrict to rows complete for all variables used in any target
  needed <- c("LES","SIZE","logSSD","logLA","logH","logSM","L","T","M","R","N")
  have <- intersect(needed, names(df))
  df <- df[stats::complete.cases(df[, have, drop = FALSE]), , drop = FALSE]

  # Adopted DAG mean forms (Run 7):
  form_L <- as.formula("L ~ LES + SIZE + logSSD + logLA")
  form_T <- as.formula("T ~ LES + SIZE + logSSD + logLA")
  form_R <- as.formula("R ~ LES + SIZE + logSSD + logLA")
  form_M <- as.formula("M ~ LES + logH + logSM + logSSD + logLA")
  form_N <- as.formula("N ~ LES + logH + logSM + logSSD + logLA + LES:logSSD")

  # Mixed-effects support (random intercept) if requested and available
  have_lme4 <- FALSE
  if (!force_lm) {
    have_lme4 <- requireNamespace("lme4", quietly = TRUE)
  }

  fit_or_na <- function(f, data) {
    # Try mixed model if cluster_var is usable; else OLS
    if (nzchar(cluster_var) && (cluster_var %in% names(data)) && have_lme4) {
      cl <- data[[cluster_var]]
      if (length(unique(na.omit(cl))) > 1) {
        rhs <- paste(deparse(f), collapse = "")
        fr  <- tryCatch(as.formula(paste(rhs, "+ (1|", cluster_var, ")")), error = function(e) NULL)
        if (!is.null(fr)) {
          m <- tryCatch(lme4::lmer(fr, data = data, REML = FALSE), error = function(e) NULL)
          if (!is.null(m)) return(m)
        }
      }
    }
    tryCatch(lm(f, data = data), error = function(e) NULL)
  }

  mods <- list(
    L = fit_or_na(form_L, df),
    T = fit_or_na(form_T, df),
    R = fit_or_na(form_R, df),
    M = fit_or_na(form_M, df),
    N = fit_or_na(form_N, df)
  )
  if (any(purrr::map_lgl(mods, is.null))) stop("One or more mean-structure fits failed; check input columns")

  resids <- purrr::map(mods, function(m) {
    # lmer/lm both support residuals(); use conditional residuals for lmer
    as.numeric(residuals(m))
  }) %>% as.data.frame(stringsAsFactors = FALSE)
  names(resids) <- names(mods)

  spouses <- parse_spouses(opt)
  norm_pair <- function(a,b) paste(sort(c(a,b)), collapse = "-")
  if (length(spouses) > 0) {
    spouses <- unique(unlist(lapply(spouses, function(p) {
      ab <- unlist(strsplit(p, "-")); if (length(ab)==2) norm_pair(ab[1], ab[2]) else p
    })))
  }

  axes <- c("L","T","M","R","N")
  all_pairs <- t(combn(axes, 2)) %>% as.data.frame() %>% dplyr::rename(A=V1,B=V2)
  all_pairs$Pair <- mapply(norm_pair, all_pairs$A, all_pairs$B)

  claims <- all_pairs %>% dplyr::mutate(
    expected = ifelse(Pair %in% spouses, "dependent", "independent"),
    p_value = NA_real_,
    estimate = NA_real_,
    n = NA_integer_
  )

  # Optional: rank-PIT transform each axis residual to pseudo-observations
  U <- NULL
  if (rank_pit) {
    U <- as.data.frame(lapply(resids, function(x) {
      r <- rank(x, ties.method = "average")
      (r - 0.5) / length(r)
    }))
    names(U) <- names(resids)
  }

  for (i in seq_len(nrow(claims))) {
    a <- claims$A[i]; b <- claims$B[i]
    x <- resids[[a]]; y <- resids[[b]]
    if (rank_pit) {
      xu <- U[[a]]; yu <- U[[b]]
      if (corr_method == "pearson") {
        # Normal scores for Pearson after PIT
        xs <- stats::qnorm(pmin(pmax(xu, .Machine$double.eps), 1 - .Machine$double.eps))
        ys <- stats::qnorm(pmin(pmax(yu, .Machine$double.eps), 1 - .Machine$double.eps))
        ct <- tryCatch(cor.test(xs, ys, method = "pearson"), error = function(e) NULL)
      } else {
        ct <- tryCatch(cor.test(xu, yu, method = corr_method), error = function(e) NULL)
      }
    } else {
      ct <- tryCatch(cor.test(x, y, method = corr_method), error = function(e) NULL)
    }
    if (!is.null(ct)) {
      claims$p_value[i] <- ct$p.value
      claims$estimate[i] <- unname(ct$estimate)
      claims$n[i] <- length(na.omit(x))
    }
  }

  # Add BH-FDR q-values for reporting
  claims$q_value <- NA_real_
  ok <- which(!is.na(claims$p_value) & claims$p_value > 0)
  if (length(ok) > 0) {
    claims$q_value[ok] <- p.adjust(claims$p_value[ok], method = "BH")
  }

  indep <- claims %>% dplyr::filter(expected == "independent" & !is.na(p_value) & p_value > 0)
  k <- nrow(indep)
  if (k == 0) stop("No independence claims available to compute m-sep Fisher's C")
  C <- -2 * sum(log(indep$p_value))
  dfC <- 2 * k
  pC <- 1 - pchisq(C, dfC)
  AIC_msep <- C + 2 * k

  dir.create(dirname(opt$out_summary), showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(claims, opt$out_claims)
  tibble::tibble(
    k_claims = k,
    C = C,
    df = dfC,
    p_value = pC,
    AIC_msep = AIC_msep,
    method = corr_method,
    rank_pit = rank_pit,
    cluster_var = if (nzchar(cluster_var)) cluster_var else NA_character_,
    fdr_q = fdr_q
  ) %>% readr::write_csv(opt$out_summary)

  message(sprintf("m-sep test complete: k=%d, C=%.2f (df=%d), p=%.3f, AIC_msep=%.2f [method=%s, rank_pit=%s, cluster=%s]",
                  k, C, dfC, pC, AIC_msep, corr_method, as.character(rank_pit), if (nzchar(cluster_var)) cluster_var else "none"))
}

main()
