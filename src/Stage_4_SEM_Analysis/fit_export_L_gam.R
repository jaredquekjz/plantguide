#!/usr/bin/env Rscript

# Fit and export the locked non-linear Light (L) GAM used in pwSEM Run 7
# Spec (rf_plus + logH:logSSD):
#   y ~ s(LMA, k=5) + s(logSSD, k=5) + s(SIZE, k=5) + s(logLA, k=5)
#       + Nmass + LMA:logLA + t2(LMA, logSSD, k=c(5,5)) + logH:logSSD
# Inputs are aligned with export_mag_artifacts.R (pure LES, SIZE) and Run 8.

suppressPackageStartupMessages({
  library(readr)
  library(jsonlite)
})

`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b

args <- commandArgs(trailingOnly = TRUE)
opts <- list()
for (i in seq(1, length(args), by = 2)) {
  k <- gsub("^--", "", args[[i]])
  v <- if (i+1 <= length(args)) args[[i+1]] else ""
  opts[[k]] <- v
}

in_csv  <- opts[["input_csv"]]  %||% "artifacts/model_data_complete_case_with_myco.csv"
out_rds <- opts[["out_rds"]]    %||% "results/MAG_Run8/sem_pwsem_L_full_model.rds"

dir.create(dirname(out_rds), recursive = TRUE, showWarnings = FALSE)

if (!file.exists(in_csv)) stop(sprintf("Input CSV not found: %s", in_csv))
if (!requireNamespace("mgcv", quietly = TRUE)) stop("mgcv package is required")

compute_offset <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x) & !is.na(x) & x > 0]
  if (!length(x)) return(1e-6)
  max(1e-6, 1e-3 * stats::median(x))
}
zscore <- function(x) {
  m <- mean(x, na.rm=TRUE); s <- stats::sd(x, na.rm=TRUE); if (!is.finite(s) || s == 0) s <- 1
  list(x=(as.numeric(x)-m)/s, mean=m, sd=s)
}

df <- suppressMessages(readr::read_csv(in_csv, show_col_types = FALSE))

log_vars <- c("Leaf area (mm2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
offs <- sapply(log_vars, function(v) compute_offset(df[[v]]))

work <- data.frame(
  id    = df[["wfo_accepted_name"]],
  logLA = log10(df[["Leaf area (mm2)"]] + offs[["Leaf area (mm2)"]]),
  Nmass = as.numeric(df[["Nmass (mg/g)"]]),
  LMA   = as.numeric(df[["LMA (g/m2)"]]),
  logH  = log10(df[["Plant height (m)"]] + offs[["Plant height (m)"]]),
  logSM = log10(df[["Diaspore mass (mg)"]] + offs[["Diaspore mass (mg)"]]),
  logSSD= log10(df[["SSD used (mg/mm3)"]] + offs[["SSD used (mg/mm3)"]]),
  y     = as.numeric(df[["EIVEres-L"]])
)

# Composites: LES (not used in GAM), SIZE = PC1(logH, logSM) for completeness
zs_logH  <- zscore(work$logH)
zs_logSM <- zscore(work$logSM)
M_SIZE   <- cbind(logH = zs_logH$x, logSM = zs_logSM$x)
p_size   <- stats::prcomp(M_SIZE, center = FALSE, scale. = FALSE)
rot_size <- p_size$rotation[,1]; if (rot_size["logH"] < 0) rot_size <- -rot_size
work$SIZE <- as.numeric(M_SIZE %*% rot_size)

# Keep complete cases for variables used in the GAM
req <- c("y","LMA","logSSD","SIZE","logLA","Nmass","logH")
dat <- work[stats::complete.cases(work[, req]), , drop = FALSE]

rhs_txt <- "y ~ s(LMA, k = 5) + s(logSSD, k = 5) + s(SIZE, k = 5) + s(logLA, k = 5) + Nmass + LMA:logLA + t2(LMA, logSSD, k=c(5,5)) + logH:logSSD"
gm <- mgcv::gam(stats::as.formula(rhs_txt), data = dat, method = "REML")

saveRDS(gm, out_rds)
cat(sprintf("Wrote %s\n", out_rds))

