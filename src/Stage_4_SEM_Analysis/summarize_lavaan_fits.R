#!/usr/bin/env Rscript

suppressWarnings({
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
  })
})

args <- commandArgs(trailingOnly = TRUE)
parse_args <- function(args) { out<-list(); for (a in args) if (grepl('^--',a)) {k<-sub('^--','',a); k1<-sub('=.*$','',k); v<-sub('^[^=]*=','',k); out[[k1]]<-v}; out }
opts <- parse_args(args)
`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b

in_dir  <- opts[["in_dir"]]  %||% "artifacts/stage4_sem_lavaan"
out_csv <- opts[["out_csv"]] %||% "artifacts/stage4_sem_summary/lavaan_fit_summary.csv"

ensure_dir <- function(p) dir.create(p, recursive = TRUE, showWarnings = FALSE)
ensure_dir(dirname(out_csv))

targets <- c("L","T","M","R","N")
rows <- list()
for (t in targets) {
  fit_path  <- file.path(in_dir, sprintf("sem_lavaan_%s_fit_indices.csv", t))
  coeff_path<- file.path(in_dir, sprintf("sem_lavaan_%s_path_coefficients.csv", t))
  if (!file.exists(fit_path) || !file.exists(coeff_path)) next
  fit <- try(if (have_readr) readr::read_csv(fit_path, show_col_types = FALSE) else utils::read.csv(fit_path, check.names = FALSE), silent = TRUE)
  cf  <- try(if (have_readr) readr::read_csv(coeff_path, show_col_types = FALSE) else utils::read.csv(coeff_path, check.names = FALSE), silent = TRUE)
  if (inherits(fit,'try-error') || inherits(cf,'try-error')) next
  # Pull key fit indices
  kv <- setNames(fit$value, fit$measure)
  chisq <- as.numeric(kv[['chisq']]); df <- as.numeric(kv[['df']]); pval <- as.numeric(kv[['pvalue']])
  cfi <- as.numeric(kv[['cfi']]); tli <- as.numeric(kv[['tli']]); rmsea <- as.numeric(kv[['rmsea']]); srmr <- as.numeric(kv[['srmr']])
  # Structural paths: standardizedSolution fields typically include columns lhs, op, rhs, est.std, pvalue
  cn <- names(cf)
  # Try robust matching
  col_lhs <- which(cn %in% c('lhs','LHS'))[1]
  col_op  <- which(cn %in% c('op','OP'))[1]
  col_rhs <- which(cn %in% c('rhs','RHS'))[1]
  col_est <- which(cn %in% c('est.std','std.all','std.lv','est'))[1]
  col_p   <- which(cn %in% c('pvalue','p','P'))[1]
  b1 <- b2 <- b3 <- NA_real_
  p1 <- p2 <- p3 <- NA_real_
  if (all(is.finite(c(col_lhs,col_op,col_rhs,col_est))) && !is.na(col_lhs)) {
    rows_cf <- cf[cf[[col_lhs]] == 'y' & cf[[col_op]] == '~', , drop = FALSE]
    for (i in seq_len(nrow(rows_cf))) {
      rhs <- as.character(rows_cf[i, col_rhs])
      est <- suppressWarnings(as.numeric(rows_cf[i, col_est]))
      pv  <- if (!is.na(col_p)) suppressWarnings(as.numeric(rows_cf[i, col_p])) else NA_real_
      if (identical(rhs,'LES')) { b1 <- est; p1 <- pv }
      if (identical(rhs,'SIZE')) { b2 <- est; p2 <- pv }
      if (identical(rhs,'logSSD')) { b3 <- est; p3 <- pv }
    }
  }
  rows[[length(rows)+1]] <- data.frame(target=t, chisq=chisq, df=df, pvalue=pval, cfi=cfi, tli=tli, rmsea=rmsea, srmr=srmr,
                                       beta_LES=b1, p_LES=p1, beta_SIZE=b2, p_SIZE=p2, beta_logSSD=b3, p_logSSD=p3,
                                       stringsAsFactors = FALSE)
}

tab <- do.call(rbind, rows)
if (have_readr) readr::write_csv(tab, out_csv) else utils::write.csv(tab, out_csv, row.names = FALSE)
cat(sprintf("Wrote lavaan fit summary: %s (%d rows)\n", out_csv, nrow(tab)))

