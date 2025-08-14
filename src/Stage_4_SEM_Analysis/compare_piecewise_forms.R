#!/usr/bin/env Rscript

suppressWarnings({
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
    have_jsonlite <- requireNamespace("jsonlite", quietly = TRUE)
    have_dplyr    <- requireNamespace("dplyr",    quietly = TRUE)
    have_tibble   <- requireNamespace("tibble",   quietly = TRUE)
  })
})

args <- commandArgs(trailingOnly = TRUE)
parse_args <- function(args) { out<-list(); for (a in args) if (grepl('^--',a)) {k<-sub('^--','',a); k1<-sub('=.*$','',k); v<-sub('^[^=]*=','',k); out[[k1]]<-v}; out }
`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b
opts <- parse_args(args)

dir_linear   <- opts[["dir_linear"]]   %||% "artifacts/stage4_sem_piecewise_run2"
dir_decon    <- opts[["dir_decon"]]    %||% "artifacts/stage4_sem_piecewise_run2_deconstructed"
dir_nonlinear<- opts[["dir_nonlinear"]]%||% "artifacts/stage4_sem_piecewise_run2_nonlinear"
out_csv      <- opts[["out_csv"]]      %||% "artifacts/stage4_sem_summary_run2/piecewise_form_comparison.csv"

ensure_dir <- function(p) dir.create(p, recursive = TRUE, showWarnings = FALSE)
ensure_dir(dirname(out_csv))

read_metrics <- function(path, form) {
  x <- try(jsonlite::fromJSON(path), silent = TRUE)
  if (inherits(x, 'try-error')) return(NULL)
  tgt <- as.character(x$target)
  tletter <- sub('^EIVEres-', '', tgt)
  agg <- x$metrics$aggregate
  per <- x$metrics$per_fold
  aic_mean <- NA_real_
  edf_mean <- NA_real_
  if (!is.null(per) && 'AIC_train' %in% names(per)) {
    aic_mean <- suppressWarnings(mean(as.numeric(per$AIC_train), na.rm = TRUE))
  }
  if (!is.null(per) && 'edf_s_logH' %in% names(per)) {
    edf_mean <- suppressWarnings(mean(as.numeric(per$edf_s_logH), na.rm = TRUE))
  }
  data.frame(
    target = tletter,
    form = form,
    n = as.integer(x$n),
    R2_mean = as.numeric(agg$R2_mean), R2_sd = as.numeric(agg$R2_sd),
    RMSE_mean = as.numeric(agg$RMSE_mean), RMSE_sd = as.numeric(agg$RMSE_sd),
    MAE_mean = as.numeric(agg$MAE_mean), MAE_sd = as.numeric(agg$MAE_sd),
    AIC_train_mean = aic_mean,
    edf_s_logH_mean = edf_mean,
    stringsAsFactors = FALSE
  )
}

collect_dir <- function(d, form) {
  if (!dir.exists(d)) return(NULL)
  files <- list.files(d, pattern = '^sem_piecewise_.*_metrics.json$', full.names = TRUE)
  rows <- lapply(files, function(f) read_metrics(f, form))
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (!length(rows)) return(NULL)
  do.call(rbind, rows)
}

tab <- rbind(
  collect_dir(dir_linear, 'linear_size'),
  collect_dir(dir_decon,  'linear_deconstructed'),
  collect_dir(dir_nonlinear, 'semi_nonlinear_slogH')
)

if (is.null(tab)) tab <- data.frame(target=character(), form=character(), n=integer(), R2_mean=double(), R2_sd=double(), RMSE_mean=double(), RMSE_sd=double(), MAE_mean=double(), MAE_sd=double(), AIC_train_mean=double(), edf_s_logH_mean=double(), stringsAsFactors = FALSE)

if (have_readr) readr::write_csv(tab, out_csv) else utils::write.csv(tab, out_csv, row.names = FALSE)
cat(sprintf('Wrote piecewise form comparison: %s (%d rows)\n', out_csv, nrow(tab)))

