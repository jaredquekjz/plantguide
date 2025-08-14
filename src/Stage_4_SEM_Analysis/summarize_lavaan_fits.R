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
  fit_path_std  <- file.path(in_dir, sprintf("sem_lavaan_%s_fit_indices.csv", t))
  coeff_path    <- file.path(in_dir, sprintf("sem_lavaan_%s_path_coefficients.csv", t))
  fit_path_grp  <- file.path(in_dir, sprintf("sem_lavaan_%s_fit_indices_by_group.csv", t))

  if (file.exists(fit_path_std)) {
    fit <- try(if (have_readr) readr::read_csv(fit_path_std, show_col_types = FALSE) else utils::read.csv(fit_path_std, check.names = FALSE), silent = TRUE)
    cf  <- try(if (have_readr) readr::read_csv(coeff_path,    show_col_types = FALSE) else utils::read.csv(coeff_path,    check.names = FALSE), silent = TRUE)
    if (inherits(fit,'try-error')) next
    kv <- setNames(fit$value, fit$measure)
    chisq <- as.numeric(kv[['chisq']]); df <- as.numeric(kv[['df']]); pval <- as.numeric(kv[['pvalue']])
    cfi <- as.numeric(kv[['cfi']]); tli <- as.numeric(kv[['tli']]); rmsea <- as.numeric(kv[['rmsea']]); srmr <- as.numeric(kv[['srmr']])
    b1 <- b2 <- b3 <- NA_real_; p1 <- p2 <- p3 <- NA_real_
    if (!inherits(cf,'try-error')) {
      cn <- names(cf)
      col_lhs <- which(cn %in% c('lhs','LHS'))[1]
      col_op  <- which(cn %in% c('op','OP'))[1]
      col_rhs <- which(cn %in% c('rhs','RHS'))[1]
      col_est <- which(cn %in% c('est.std','std.all','std.lv','est'))[1]
      col_p   <- which(cn %in% c('pvalue','p','P'))[1]
      if (!is.na(col_lhs) && !is.na(col_op) && !is.na(col_rhs) && !is.na(col_est)) {
        rows_cf <- cf[cf[[col_lhs]] == 'y' & cf[[col_op]] == '~', , drop = FALSE]
        for (i in seq_len(nrow(rows_cf))) {
          rhs <- as.character(rows_cf[i, col_rhs])
          est <- suppressWarnings(as.numeric(rows_cf[i, col_est]))
          pv  <- if (!is.na(col_p)) suppressWarnings(as.numeric(rows_cf[i, col_p])) else NA_real_
          if (identical(rhs,'LES'))     { b1 <- est; p1 <- pv }
          if (identical(rhs,'SIZE'))    { b2 <- est; p2 <- pv }
          if (identical(rhs,'logSSD'))  { b3 <- est; p3 <- pv }
          if (identical(rhs,'logH'))    { b2 <- est; p2 <- pv } # reuse SIZE columns to report stature effect
          if (identical(rhs,'logSM'))   { b3 <- est; p3 <- pv } # reuse logSSD column to report seed mass effect if deconstructed
        }
      }
    }
    rows[[length(rows)+1]] <- data.frame(target=t, group=NA_character_, chisq=chisq, df=df, pvalue=pval, cfi=cfi, tli=tli, rmsea=rmsea, srmr=srmr,
                                         beta_LES=b1, p_LES=p1, beta_SIZE_or_logH=b2, p_SIZE_or_logH=p2, beta_logSSD_or_logSM=b3, p_logSSD_or_logSM=p3,
                                         stringsAsFactors = FALSE)
  } else if (file.exists(fit_path_grp)) {
    # Read by-group fit indices; coefficients may be unavailable
    fitg <- try(if (have_readr) readr::read_csv(fit_path_grp, show_col_types = FALSE) else utils::read.csv(fit_path_grp, check.names = FALSE), silent = TRUE)
    if (inherits(fitg,'try-error')) next
    # Columns already in tidy form per group
    cn <- names(fitg)
    # Ensure expected columns exist
    need <- c('group','chisq','df','pvalue','cfi','tli','rmsea','srmr')
    for (nm in need) if (!(nm %in% cn)) fitg[[nm]] <- NA_real_
    for (i in seq_len(nrow(fitg))) {
      rows[[length(rows)+1]] <- data.frame(target=t, group=as.character(fitg$group[i]), chisq=as.numeric(fitg$chisq[i]), df=as.numeric(fitg$df[i]),
                                           pvalue=as.numeric(fitg$pvalue[i]), cfi=as.numeric(fitg$cfi[i]), tli=as.numeric(fitg$tli[i]),
                                           rmsea=as.numeric(fitg$rmsea[i]), srmr=as.numeric(fitg$srmr[i]),
                                           beta_LES=NA_real_, p_LES=NA_real_, beta_SIZE_or_logH=NA_real_, p_SIZE_or_logH=NA_real_,
                                           beta_logSSD_or_logSM=NA_real_, p_logSSD_or_logSM=NA_real_, stringsAsFactors = FALSE)
    }
  } else {
    next
  }
}

tab <- if (length(rows)) do.call(rbind, rows) else data.frame(target=character(), group=character(), chisq=double(), df=double(), pvalue=double(), cfi=double(), tli=double(), rmsea=double(), srmr=double(), beta_LES=double(), p_LES=double(), beta_SIZE_or_logH=double(), p_SIZE_or_logH=double(), beta_logSSD_or_logSM=double(), p_logSSD_or_logSM=double(), stringsAsFactors = FALSE)
if (have_readr) readr::write_csv(tab, out_csv) else utils::write.csv(tab, out_csv, row.names = FALSE)
cat(sprintf("Wrote lavaan fit summary: %s (%d rows)\n", out_csv, nrow(tab)))
