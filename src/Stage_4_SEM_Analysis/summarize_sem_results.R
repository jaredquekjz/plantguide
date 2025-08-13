#!/usr/bin/env Rscript

suppressWarnings({
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
    have_jsonlite <- requireNamespace("jsonlite", quietly = TRUE)
    have_tools    <- TRUE
  })
})

args <- commandArgs(trailingOnly = TRUE)
parse_args <- function(args) {
  out <- list()
  for (a in args) {
    if (!grepl("^--[A-Za-z0-9_]+=", a)) next
    kv <- sub("^--", "", a)
    k <- sub("=.*$", "", kv)
    v <- sub("^[^=]*=", "", kv)
    out[[k]] <- v
  }
  out
}
opts <- parse_args(args)
`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b

lavaan_dir   <- opts[["lavaan_dir"]]   %||% "artifacts/stage4_sem_lavaan"
piecewise_dir<- opts[["piecewise_dir"]]%||% "artifacts/stage4_sem_piecewise"
out_csv      <- opts[["out_csv"]]      %||% "artifacts/stage4_sem_summary/sem_metrics_summary.csv"

ensure_dir <- function(path) dir.create(path, recursive = TRUE, showWarnings = FALSE)
ensure_dir(dirname(out_csv))

read_metrics <- function(path, method) {
  if (!file.exists(path)) return(NULL)
  x <- try(jsonlite::fromJSON(path), silent = TRUE)
  if (inherits(x, "try-error")) return(NULL)
  tgt <- as.character(x$target)
  tletter <- sub("^EIVEres-", "", tgt)
  agg <- x$metrics$aggregate
  data.frame(
    method = method,
    target = tletter,
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

g <- list()
for (f in list.files(lavaan_dir, pattern = "_metrics.json$", full.names = TRUE)) {
  g[[length(g)+1]] <- read_metrics(f, method = "lavaan_composite")
}
for (f in list.files(piecewise_dir, pattern = "_metrics.json$", full.names = TRUE)) {
  g[[length(g)+1]] <- read_metrics(f, method = "piecewise")
}

tab <- do.call(rbind, g)
tab <- tab[order(tab$target, tab$method), , drop = FALSE]

if (have_readr) readr::write_csv(tab, out_csv) else utils::write.csv(tab, out_csv, row.names = FALSE)

cat(sprintf("Wrote summary: %s (%d rows)\n", out_csv, nrow(tab)))

