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
    out_claims = "results/msep_claims.csv"
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

  # Read data and recipe
  df <- suppressMessages(readr::read_csv(opt$input_csv, show_col_types = FALSE))
  recipe <- jsonlite::fromJSON(opt$recipe_json, simplifyVector = TRUE)
  offs <- recipe$log_offsets
  std <- recipe$standardization
  comps <- recipe$composites

  df <- df %>% dplyr::mutate(
    logLA = log_transform(.data[["Leaf area (mm2)"]] %||% .data[["LeafArea"]], offs[["Leaf area (mm2)"]] %||% 0),
    logH  = log_transform(.data[["Plant height (m)"]] %||% .data[["PlantHeight"]], offs[["Plant height (m)"]] %||% 0),
    logSM = log_transform(.data[["Diaspore mass (mg)"]] %||% .data[["DiasporeMass"]], offs[["Diaspore mass (mg)"]] %||% 0),
    logSSD= log_transform(.data[["SSD used (mg/mm3)"]] %||% .data[["SSD"]], offs[["SSD used (mg/mm3)"]] %||% 0)
  )

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

  # Adopted DAG mean forms (Run 7):
  form_L <- as.formula("L ~ LES + SIZE + logSSD + logLA")
  form_T <- as.formula("T ~ LES + SIZE + logSSD + logLA")
  form_R <- as.formula("R ~ LES + SIZE + logSSD + logLA")
  form_M <- as.formula("M ~ LES + logH + logSM + logSSD + logLA")
  form_N <- as.formula("N ~ LES + logH + logSM + logSSD + logLA + LES:logSSD")

  fit_or_na <- function(f, data) tryCatch(lm(f, data = data), error = function(e) NULL)
  mods <- list(
    L = fit_or_na(form_L, df),
    T = fit_or_na(form_T, df),
    R = fit_or_na(form_R, df),
    M = fit_or_na(form_M, df),
    N = fit_or_na(form_N, df)
  )
  if (any(purrr::map_lgl(mods, is.null))) stop("One or more mean-structure fits failed; check input columns")

  resids <- purrr::map(mods, residuals) %>% as.data.frame(stringsAsFactors = FALSE)
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
    estimate = NA_real_
  )

  for (i in seq_len(nrow(claims))) {
    a <- claims$A[i]; b <- claims$B[i]
    x <- resids[[a]]; y <- resids[[b]]
    ct <- tryCatch(cor.test(x, y, method = "pearson"), error = function(e) NULL)
    if (!is.null(ct)) {
      claims$p_value[i] <- ct$p.value
      claims$estimate[i] <- unname(ct$estimate)
    }
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
    AIC_msep = AIC_msep
  ) %>% readr::write_csv(opt$out_summary)

  message(sprintf("m-sep test complete: k=%d, C=%.2f (df=%d), p=%.3f, AIC_msep=%.2f", k, C, dfC, pC, AIC_msep))
}

main()

