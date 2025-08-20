#!/usr/bin/env Rscript

# Simple DAG comparison: piecewiseSEM vs pwSEM
# - DAG: E1 -> M -> Y and E2 -> Y; E1, E2 exogenous
# - Default piecewiseSEM omits the exogenous-pair claim (E1 ⫫ E2)
# - pwSEM (per docs) includes exogenous-pair claims in the basis set

suppressWarnings({
  # Allow injecting extra library paths via env or local .Rlib
  extra_libs <- Sys.getenv("R_EXTRA_LIBS")
  lib_candidates <- character()
  if (nzchar(extra_libs)) lib_candidates <- c(lib_candidates, unlist(strsplit(extra_libs, "[,:;]", perl = TRUE)))
  if (dir.exists(".Rlib")) lib_candidates <- c(normalizePath(".Rlib"), lib_candidates)
  lib_candidates <- unique(lib_candidates[nzchar(lib_candidates)])
  if (length(lib_candidates)) .libPaths(c(lib_candidates, .libPaths()))
  suppressMessages({
    have_piecewiseSEM <- requireNamespace("piecewiseSEM", quietly = TRUE)
    have_mgcv         <- requireNamespace("mgcv",         quietly = TRUE)
    have_pwSEM_pkg    <- requireNamespace("pwSEM",        quietly = TRUE)
  })
})

args <- commandArgs(trailingOnly = TRUE)
parse_args <- function(args) { out<-list(); for (a in args) if (grepl('^--',a)) {k<-sub('^--','',a); k1<-sub('=.*$','',k); v<-sub('^[^=]*=','',k); out[[k1]]<-v}; out }
`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b
safe_bool <- function(x, default = FALSE) { if (is.null(x)) return(default); tolower(as.character(x)) %in% c('1','true','yes','y') }

opts <- parse_args(args)
n   <- suppressWarnings(as.integer(opts[["n"]]   %||% "500")); if (is.na(n) || n < 50) n <- 500
rho <- suppressWarnings(as.numeric(opts[["rho"]] %||% "0.6")); if (!is.finite(rho) || abs(rho) >= 0.99) rho <- 0.6
try_install <- safe_bool(opts[["try_install"]], FALSE)
seed <- suppressWarnings(as.integer(opts[["seed"]] %||% "12345")); if (is.na(seed)) seed <- 12345

need_pkg <- function(p) {
  if (requireNamespace(p, quietly = TRUE)) return(TRUE)
  if (!try_install) return(FALSE)
  message("Installing missing package: ", p)
  try(install.packages(p, dependencies = TRUE), silent = TRUE)
  requireNamespace(p, quietly = TRUE)
}

have_piecewise <- have_piecewiseSEM || need_pkg("piecewiseSEM")
if (!have_piecewise) stop("piecewiseSEM is required. Install with install.packages('piecewiseSEM').")
have_pwsem <- have_pwSEM_pkg

set.seed(seed)

# Simulate data; intentionally correlate E2 with E1 to violate E1 ⫫ E2
e1 <- rnorm(n)
z  <- rnorm(n)
e2 <- rho*e1 + sqrt(1 - rho^2) * z
M  <- 0.8*e1 + rnorm(n, sd = 1.0)
Y  <- 0.5*M + 0.4*e2 + rnorm(n, sd = 1.0)
dat <- data.frame(E1 = e1, E2 = e2, M = M, Y = Y)

# piecewiseSEM default: build psem for endogenous equations only
m_M <- stats::lm(M ~ E1, data = dat)
m_Y <- stats::lm(Y ~ M + E2, data = dat)
P   <- piecewiseSEM::psem(m_M, m_Y)

dsep_tab <- try(piecewiseSEM::dSep(P), silent = TRUE)
fish     <- try(piecewiseSEM::fisherC(P), silent = TRUE)

dsep_n <- if (!inherits(dsep_tab, 'try-error')) nrow(as.data.frame(dsep_tab)) else 0L
C_def <- NA_real_; df_def <- NA_real_; p_def <- NA_real_
if (!inherits(fish, 'try-error')) {
  fdf <- try(as.data.frame(fish), silent = TRUE)
  if (!inherits(fdf, 'try-error')) {
    nml <- tolower(names(fdf))
    getv <- function(keys) { idx <- which(nml %in% keys)[1]; if (is.na(idx)) NA_real_ else suppressWarnings(as.numeric(fdf[[idx]][1])) }
    C_def  <- getv(c('c','c.stat','fisher.c','fisherc'))
    df_def <- getv(c('df','d.f.','dof'))
    p_def  <- getv(c('p','p.value','pvalue','pr(>c)'))
  } else if (is.numeric(fish) && length(fish) >= 3) {
    C_def  <- unname(fish[[1]]); df_def <- unname(fish[[2]]); p_def <- unname(fish[[3]])
  }
}

# Manually add the exogenous-pair claim E1 ⫫ E2 and recompute Fisher's C
add_p <- try({
  s <- summary(stats::lm(E1 ~ E2, data = dat))
  as.numeric(s$coefficients["E2", "Pr(>|t|)"])
}, silent = TRUE)

C_fix <- NA_real_; df_fix <- NA_real_; p_fix <- NA_real_
if (!inherits(add_p, 'try-error') && !inherits(dsep_tab, 'try-error')) {
  ddf <- as.data.frame(dsep_tab)
  nml <- tolower(names(ddf))
  idx <- match(c('p.value','pvalue','pr(>c)','p'), nml)
  idx <- idx[!is.na(idx)][1]
  if (is.na(idx)) {
    # Fallback: choose first numeric column with values in (0,1]
    for (j in seq_along(ddf)) {
      v <- suppressWarnings(as.numeric(ddf[[j]]))
      if (any(is.finite(v))) {
        v2 <- v[is.finite(v)]
        if (length(v2) && all(v2 > 0 & v2 <= 1, na.rm = TRUE)) { idx <- j; break }
      }
    }
  }
  if (!is.na(idx)) {
    pv <- suppressWarnings(as.numeric(ddf[[idx]]))
    pv <- pv[is.finite(pv) & pv > 0 & pv <= 1]
    if (length(pv) >= 0 && is.finite(add_p) && add_p > 0 && add_p <= 1) {
      pv_all <- c(pv, add_p)
      C_fix <- -2 * sum(log(pv_all))
      df_fix <- 2 * length(pv_all)
      p_fix <- 1 - stats::pchisq(C_fix, df = df_fix)
    }
  }
}

# pwSEM per docs: provide sem.functions list INCLUDING exogenous vars
pw <- NULL; pw_C <- NA_real_; pw_df <- NA_real_; pw_p <- NA_real_; pw_claims <- NA_integer_
if (have_pwsem && have_mgcv) {
  try({
    sem.list <- list(
      mgcv::gam(E1 ~ 1,      data = dat, family = gaussian()),
      mgcv::gam(E2 ~ 1,      data = dat, family = gaussian()),
      mgcv::gam(M  ~ E1,     data = dat, family = gaussian()),
      mgcv::gam(Y  ~ M + E2, data = dat, family = gaussian())
    )
    pw <- pwSEM::pwSEM(
      sem.functions = sem.list,
      marginalized.latents = NULL,
      conditioned.latents  = NULL,
      data = dat,
      use.permutations = FALSE,
      do.smooth = FALSE
    )
    if (is.list(pw)) {
      if (!is.null(pw$C.statistic))      pw_C <- suppressWarnings(as.numeric(pw$C.statistic))
      if (!is.null(pw$prob.C.statistic)) pw_p <- suppressWarnings(as.numeric(pw$prob.C.statistic))
      if (!is.null(pw$dsep.probs))       pw_df <- 2 * length(pw$dsep.probs)
      if (!is.null(pw$basis.set))        pw_claims <- suppressWarnings(tryCatch(nrow(as.data.frame(pw$basis.set)), error = function(e) NA_integer_))
      if (is.na(pw_claims) && !is.null(pw$dsep.probs)) pw_claims <- length(pw$dsep.probs)
    }
  }, silent = TRUE)
}

fmt <- function(x) ifelse(is.na(x), "NA", sprintf("%.6f", x))

cat("\n=== Simple DAG comparison (n=", n, ", rho=", rho, ") ===\n", sep = "")

cat("\n[piecewiseSEM] Defaults:\n")
cat("- claims tested:", dsep_n, "\n")
cat("- Fisher's C:", fmt(C_def), " df:", fmt(df_def), " p:", fmt(p_def), "\n")

cat("\n[piecewiseSEM] + exogenous-pair claim (E1 ⫫ E2):\n")
cat("- Fisher's C:", fmt(C_fix), " df:", fmt(df_fix), " p:", fmt(p_fix), "\n")

if (!have_pwsem) {
  cat("\n[pwSEM] Not installed; to install, run: Rscript scripts/install_pwsem.R\n")
} else if (!is.null(pw)) {
  cat("\n[pwSEM] Per docs:\n")
  cat("- claims tested:", ifelse(is.na(pw_claims), "NA", pw_claims), "\n")
  cat("- Fisher's C:", fmt(pw_C), " df:", fmt(pw_df), " p:", fmt(pw_p), "\n")
} else {
  cat("\n[pwSEM] Installed but fit did not complete (check sem.functions inputs).\n")
}

cat("\nNote: pwSEM docs specify sem.functions list must include models for exogenous variables; this script follows that pattern.\n")
