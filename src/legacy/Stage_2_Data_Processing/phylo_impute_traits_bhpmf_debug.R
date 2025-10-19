#!/usr/bin/env Rscript

suppressWarnings({
  suppressMessages({
    library(data.table)
    library(dplyr)
    library(stringr)
  })
})

lib_user <- Sys.getenv("R_LIBS_USER")
if (nzchar(lib_user)) {
  .libPaths(lib_user)
} else {
  .libPaths("/home/olier/ellenberg/.Rlib")
}

cat("[debug] Starting BHPMF script\n")
args <- commandArgs(trailingOnly = TRUE)
cat("[debug] Raw args:", paste(args, collapse=" "), "\n")

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
`%||%` <- function(a, b) if (!is.null(a) && nzchar(a)) a else b

in_csv  <- opts[["input_csv"]] %||% "model_data/inputs/trait_imputation_input_shortlist_20251021.csv"
out_csv <- opts[["out_csv"]]  %||% "model_data/outputs/trait_imputation_bhpmf_shortlist_debug.csv"

cat("[debug] Loading:", in_csv, "\n")
if (!file.exists(in_csv)) stop("input not found")
dt <- fread(in_csv)
cat("[debug] nrows:", nrow(dt), "ncols:", ncol(dt), "\n")

stop("debug halt")
