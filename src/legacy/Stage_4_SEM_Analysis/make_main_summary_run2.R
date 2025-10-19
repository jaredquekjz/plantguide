#!/usr/bin/env Rscript

suppressWarnings({
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
    have_jsonlite <- requireNamespace("jsonlite", quietly = TRUE)
  })
})

args <- commandArgs(trailingOnly = TRUE)
parse_args <- function(args) { out<-list(); for (a in args) if (grepl('^--',a)) {k<-sub('^--','',a); k1<-sub('=.*$','',k); v<-sub('^[^=]*=','',k); out[[k1]]<-v}; out }
`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b
opts <- parse_args(args)

dir_lavaan <- opts[["lavaan_dir"]] %||% "artifacts/stage4_sem_lavaan_run2_deconstruct"
dir_pw_LTR <- opts[["piecewise_dir_LTR"]] %||% "artifacts/stage4_sem_piecewise_run2"
dir_pw_MN  <- opts[["piecewise_dir_MN"]]  %||% "artifacts/stage4_sem_piecewise_run2_deconstructed"
dir_pw_Rlin<- opts[["piecewise_dir_R"]]   %||% "artifacts/stage4_sem_piecewise_run2_linear"
out_csv    <- opts[["out_csv"]]           %||% "artifacts/stage4_sem_summary_run2/sem_metrics_summary_main.csv"

ensure_dir <- function(p) dir.create(p, recursive = TRUE, showWarnings = FALSE)
ensure_dir(dirname(out_csv))

read_metrics <- function(path, method, form=NA_character_) {
  x <- try(jsonlite::fromJSON(path), silent = TRUE)
  if (inherits(x,'try-error')) return(NULL)
  tgt <- as.character(x$target)
  tletter <- sub('^EIVEres-', '', tgt)
  agg <- x$metrics$aggregate
  data.frame(
    method = method,
    target = tletter,
    form = form,
    n = as.integer(x$n),
    repeats = as.integer(x$repeats),
    folds = as.integer(x$folds),
    stratify = as.logical(x$stratify),
    R2_mean = as.numeric(agg$R2_mean), R2_sd = as.numeric(agg$R2_sd),
    RMSE_mean = as.numeric(agg$RMSE_mean), RMSE_sd = as.numeric(agg$RMSE_sd),
    MAE_mean = as.numeric(agg$MAE_mean), MAE_sd = as.numeric(agg$MAE_sd),
    stringsAsFactors = FALSE
  )
}

rows <- list()
# lavaan metrics (composite proxies)
for (t in c('L','T','M','R','N')) {
  f <- file.path(dir_lavaan, sprintf('sem_lavaan_%s_metrics.json', t))
  if (file.exists(f)) rows[[length(rows)+1]] <- read_metrics(f, method='lavaan_composite')
}

# piecewise chosen forms: L,T from run2; M,N from deconstructed; R from linear
for (t in c('L','T')) {
  f <- file.path(dir_pw_LTR, sprintf('sem_piecewise_%s_metrics.json', t))
  if (file.exists(f)) rows[[length(rows)+1]] <- read_metrics(f, method='piecewise', form='linear_size')
}
f <- file.path(dir_pw_MN, 'sem_piecewise_M_metrics.json'); if (file.exists(f)) rows[[length(rows)+1]] <- read_metrics(f, method='piecewise', form='linear_deconstructed')
f <- file.path(dir_pw_MN, 'sem_piecewise_N_metrics.json'); if (file.exists(f)) rows[[length(rows)+1]] <- read_metrics(f, method='piecewise', form='linear_deconstructed')
f <- file.path(dir_pw_Rlin, 'sem_piecewise_R_metrics.json'); if (file.exists(f)) rows[[length(rows)+1]] <- read_metrics(f, method='piecewise', form='linear_size')

tab <- if (length(rows)) do.call(rbind, rows) else data.frame()

if (have_readr) readr::write_csv(tab, out_csv) else utils::write.csv(tab, out_csv, row.names = FALSE)
cat(sprintf('Wrote main summary: %s (%d rows)\n', out_csv, nrow(tab)))

