#!/usr/bin/env Rscript

# Export standardized OLS "structural" paths using composite proxies (LES, SIZE) and logSSD.
# - Builds composites on FULL DATA (no CV) for interpretability, then fits z-scored model
#   y_z ~ LES_z + SIZE_z + logSSD_z and outputs standardized betas with SE, t, p, R^2.

suppressWarnings({
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
    have_jsonlite <- requireNamespace("jsonlite", quietly = TRUE)
    have_sandwich <- requireNamespace("sandwich", quietly = TRUE)
    have_lmtest   <- requireNamespace("lmtest",   quietly = TRUE)
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

in_csv  <- opts[["input_csv"]]   %||% "artifacts/model_data_complete_case.csv"
target  <- toupper(opts[["target"]] %||% "L")
out_dir <- opts[["out_dir"]]      %||% "artifacts/stage4_sem_structural"

ensure_dir <- function(path) dir.create(path, recursive = TRUE, showWarnings = FALSE)
ensure_dir(out_dir)

fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }

if (!file.exists(in_csv)) fail(sprintf("Input CSV not found: '%s'", in_csv))

df <- if (have_readr) readr::read_csv(in_csv, show_col_types = FALSE, progress = FALSE) else utils::read.csv(in_csv, check.names = FALSE)

target_name <- paste0("EIVEres-", target)
feature_cols <- c("Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
miss <- setdiff(c(target_name, feature_cols), names(df))
if (length(miss)) fail(sprintf("Missing required columns: %s", paste(miss, collapse=", ")))

df <- df[stats::complete.cases(df[, c(target_name, feature_cols)]), , drop = FALSE]
if (nrow(df) < 10) fail("Too few rows for structural path estimation.")

compute_offset <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x) & !is.na(x) & x > 0]
  if (!length(x)) return(1e-6)
  max(1e-6, 1e-3 * stats::median(x))
}
zscore <- function(x) {
  m <- mean(x, na.rm=TRUE); s <- stats::sd(x, na.rm=TRUE); if (!is.finite(s) || s == 0) s <- 1
  (x - m)/s
}

log_vars <- c("Leaf area (mm2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
offsets <- sapply(log_vars, function(v) compute_offset(df[[v]]))

work <- data.frame(
  y = df[[target_name]],
  logLA = log10(df[["Leaf area (mm2)"]] + offsets[["Leaf area (mm2)"]]),
  Nmass = df[["Nmass (mg/g)"]],
  LMA   = df[["LMA (g/m2)"]],
  logH  = log10(df[["Plant height (m)"]] + offsets[["Plant height (m)"]]),
  logSM = log10(df[["Diaspore mass (mg)"]] + offsets[["Diaspore mass (mg)"]]),
  logSSD= log10(df[["SSD used (mg/mm3)"]] + offsets[["SSD used (mg/mm3)"]])
)

# Build composites on full data
M_LES  <- scale(cbind(negLMA = -work$LMA, Nmass = work$Nmass, logLA = work$logLA), center = TRUE, scale = TRUE)
p_les  <- stats::prcomp(M_LES, center = FALSE, scale. = FALSE)
rot_les <- p_les$rotation[,1]
if (rot_les["Nmass"] < 0) rot_les <- -rot_les
work$LES  <- as.numeric(M_LES %*% rot_les)

M_SIZE <- scale(cbind(logH = work$logH, logSM = work$logSM), center = TRUE, scale = TRUE)
p_size <- stats::prcomp(M_SIZE, center = FALSE, scale. = FALSE)
rot_size <- p_size$rotation[,1]
if (rot_size["logH"] < 0) rot_size <- -rot_size
work$SIZE <- as.numeric(M_SIZE %*% rot_size)

# Standardize to get standardized betas
work$y_z     <- zscore(work$y)
work$LES_z   <- zscore(work$LES)
work$SIZE_z  <- zscore(work$SIZE)
work$logSSD_z<- zscore(work$logSSD)

m <- stats::lm(y_z ~ LES_z + SIZE_z + logSSD_z, data = work)

coef_tab <- summary(m)$coefficients
if (have_sandwich && have_lmtest) {
  rob <- sandwich::vcovHC(m, type = "HC3")
  ct <- lmtest::coeftest(m, vcov. = rob)
  coef_tab <- as.matrix(ct)
}

coefs <- data.frame(
  term = rownames(coef_tab),
  estimate = coef_tab[,1],
  std_error = coef_tab[,2],
  statistic = coef_tab[,3],
  p_value = coef_tab[,4],
  stringsAsFactors = FALSE
)

R2 <- summary(m)$r.squared

base <- file.path(out_dir, paste0("sem_structural_", target))
coef_path <- paste0(base, "_ols_paths.csv")
info_path <- paste0(base, "_info.json")

if (have_readr) readr::write_csv(coefs, coef_path) else utils::write.csv(coefs, coef_path, row.names = FALSE)

info <- list(
  target = target,
  n = nrow(work),
  R2 = R2,
  offsets = as.list(offsets),
  composites = list(LES_loadings = as.numeric(rot_les), LES_vars = names(rot_les), SIZE_loadings = as.numeric(rot_size), SIZE_vars = names(rot_size)),
  formula = "y_z ~ LES_z + SIZE_z + logSSD_z"
)
if (have_jsonlite) cat(jsonlite::toJSON(info, pretty = TRUE), file = info_path) else cat(paste(capture.output(str(info)), collapse="\n"), file = info_path)

cat(sprintf("Exported structural paths for %s to %s\n", target, coef_path))

