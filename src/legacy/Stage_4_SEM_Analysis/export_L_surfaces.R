#!/usr/bin/env Rscript

# Export 2-D smooth surfaces for the final L GAM (Run 7c candidate)
# Terms exported: ti(logLA,logH) and ti(logH,logSSD)
# Outputs: CSV grids and PNG heatmaps

suppressPackageStartupMessages({
  library(readr)
  library(ggplot2)
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
out_dir <- opts[["out_dir"]]    %||% "artifacts/stage4_sem_pwsem_run7c_surfaces"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

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

# Composites: SIZE not used here; deconstruct for L (use logH)
dat <- work[stats::complete.cases(work[, c("y","LMA","logSSD","logH","logLA","Nmass")]), , drop = FALSE]

# Final L 7c candidate: rf_plus with s(logH) and two 2-D surfaces
rhs_txt <- "y ~ s(LMA, k=5) + s(logSSD, k=5) + s(logH, k=5) + s(logLA, k=5) + Nmass + LMA:logLA + t2(LMA, logSSD, k=c(5,5)) + ti(logLA, logH, bs=c('ts','ts'), k=c(5,5)) + ti(logH, logSSD, bs=c('ts','ts'), k=c(5,5))"
gm <- mgcv::gam(stats::as.formula(rhs_txt), data = dat, method = "REML")

# Helper to get term contribution on a grid
term_surface <- function(gam, term_label, grid) {
  tt <- try(predict(gam, newdata = grid, type = "terms", terms = term_label), silent = TRUE)
  if (inherits(tt, "try-error")) {
    # fallback: full prediction minus baseline with term excluded
    y_all <- as.numeric(predict(gam, newdata = grid, type = "link"))
    y_ex  <- as.numeric(predict(gam, newdata = grid, type = "iterms"))
    return(data.frame(yhat_term = y_all - y_ex))
  }
  data.frame(yhat_term = as.numeric(tt))
}

# Grids
mk_seq <- function(x, n=60) seq(min(x, na.rm=TRUE), max(x, na.rm=TRUE), length.out = n)

# ti(logLA,logH)
g1 <- expand.grid(
  logLA = mk_seq(dat$logLA),
  logH  = mk_seq(dat$logH)
)
g1$LMA <- median(dat$LMA, na.rm = TRUE)
g1$logSSD <- median(dat$logSSD, na.rm = TRUE)
g1$Nmass <- median(dat$Nmass, na.rm = TRUE)
s1 <- term_surface(gm, "ti(logLA,logH)", g1)
out1 <- cbind(g1[,c("logLA","logH")], yhat = s1$yhat_term)
readr::write_csv(out1, file.path(out_dir, "surface_ti_logLA_logH.csv"))
ggplot(out1, aes(x=logLA, y=logH, fill=yhat)) + geom_raster() + scale_fill_viridis_c() +
  labs(title="ti(logLA, logH) contribution", x="log10(Leaf area)", y="log10(Height)", fill="effect") +
  theme_minimal()
ggsave(filename = file.path(out_dir, "surface_ti_logLA_logH.png"), width = 6, height = 4, dpi = 160)

# ti(logH,logSSD)
g2 <- expand.grid(
  logH   = mk_seq(dat$logH),
  logSSD = mk_seq(dat$logSSD)
)
g2$LMA <- median(dat$LMA, na.rm = TRUE)
g2$logLA <- median(dat$logLA, na.rm = TRUE)
g2$Nmass <- median(dat$Nmass, na.rm = TRUE)
s2 <- term_surface(gm, "ti(logH,logSSD)", g2)
out2 <- cbind(g2[,c("logH","logSSD")], yhat = s2$yhat_term)
readr::write_csv(out2, file.path(out_dir, "surface_ti_logH_logSSD.csv"))
ggplot(out2, aes(x=logH, y=logSSD, fill=yhat)) + geom_raster() + scale_fill_viridis_c() +
  labs(title="ti(logH, logSSD) contribution", x="log10(Height)", y="log10(SSD)", fill="effect") +
  theme_minimal()
ggsave(filename = file.path(out_dir, "surface_ti_logH_logSSD.png"), width = 6, height = 4, dpi = 160)

cat(sprintf("Wrote surfaces to %s\n", out_dir))

