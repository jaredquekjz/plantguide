#!/usr/bin/env Rscript

suppressWarnings({
  suppressMessages({
    have_readr <- requireNamespace("readr", quietly = TRUE)
  })
})

args <- commandArgs(trailingOnly = TRUE)
parse_args <- function(args) { out<-list(); for (a in args) if (grepl('^--',a)) {k<-sub('^--','',a); k1<-sub('=.*$','',k); v<-sub('^[^=]*=','',k); out[[k1]]<-v}; out }
opts <- parse_args(args)
`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b

in_dir  <- opts[["in_dir"]]  %||% "artifacts/stage4_sem_piecewise"
out_csv <- opts[["out_csv"]] %||% "artifacts/stage4_sem_summary/piecewise_dsep_summary.csv"

ensure_dir <- function(p) dir.create(p, recursive = TRUE, showWarnings = FALSE)
ensure_dir(dirname(out_csv))

targets <- c("L","T","M","R","N")
rows <- list()
for (t in targets) {
  f <- file.path(in_dir, sprintf("sem_piecewise_%s_dsep_fit.csv", t))
  if (!file.exists(f)) next
  df <- try(if (have_readr) readr::read_csv(f, show_col_types = FALSE) else utils::read.csv(f, check.names = FALSE), silent = TRUE)
  if (inherits(df,'try-error')) next
  cn <- names(df)
  cnl <- tolower(cn)
  cidx <- which(cnl %in% c('c','c.stat','fisher.c','fisherc'))[1]
  pidx <- which(cnl %in% c('p','p.value','pvalue'))[1]
  if (is.na(pidx)) pidx <- which(cn %in% c('P.Value','P','Pr(>C)'))[1]
  dfidx<- which(cnl %in% c('df','d.f.','dof'))[1]
  Cres <- if (!is.na(cidx)) as.numeric(df[[cn[cidx]]][1]) else NA_real_
  pval <- if (!is.na(pidx)) as.numeric(df[[cn[ pidx]]][1]) else NA_real_
  dfr  <- if (!is.na(dfidx)) as.numeric(df[[cn[dfidx]]][1]) else NA_real_
  rows[[length(rows)+1]] <- data.frame(target=t, fisher_C=Cres, df=dfr, pvalue=pval, stringsAsFactors = FALSE)
}

if (length(rows) == 0) {
  tab <- data.frame(target=character(), fisher_C=double(), df=double(), pvalue=double(), stringsAsFactors = FALSE)
} else {
  tab <- do.call(rbind, rows)
}
if (have_readr) readr::write_csv(tab, out_csv) else utils::write.csv(tab, out_csv, row.names = FALSE)
cat(sprintf("Wrote piecewise d-sep summary: %s (%d rows)\n", out_csv, nrow(tab)))
