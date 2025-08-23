#!/usr/bin/env Rscript

# Quick Gaussian-copula adequacy check for Run 8
# - Rebuild residuals from finalized mean forms
# - Compare empirical Kendall's tau to Gaussian-implied tau
# - Check tail co-occurrence vs Gaussian prediction (MC)
# - Do simple 2-fold CV log-copula score vs independence

suppressWarnings({
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
    have_jsonlite <- requireNamespace("jsonlite", quietly = TRUE)
    have_mgcv     <- requireNamespace("mgcv",     quietly = TRUE)
  })
})

`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b

args <- commandArgs(trailingOnly = TRUE)
opts <- list()
for (i in seq(1, length(args), by = 2)) {
  k <- gsub("^--", "", args[[i]])
  v <- if (i+1 <= length(args)) args[[i+1]] else ""
  opts[[k]] <- v
}

in_csv   <- opts[["input_csv"]]   %||% "artifacts/model_data_complete_case_with_myco.csv"
cop_json <- opts[["copulas_json"]] %||% "results/MAG_Run8/mag_copulas.json"
out_md   <- opts[["out_md"]]       %||% "results/stage_sem_run8_copula_diagnostics.md"
mc_n     <- suppressWarnings(as.integer(opts[["nsim"]] %||% "100000")); if (is.na(mc_n) || mc_n < 10000) mc_n <- 100000
# Optional: GAM for L residualization
gam_L_rds <- opts[["gam_L_rds"]] %||% ""

ensure_dir <- function(path) dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
ensure_dir(out_md)

fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }
if (!file.exists(in_csv))  fail(sprintf("Input CSV not found: '%s'", in_csv))
if (!file.exists(cop_json)) fail(sprintf("Copulas JSON not found: '%s'", cop_json))

df <- if (have_readr) readr::read_csv(in_csv, show_col_types = FALSE, progress = FALSE) else utils::read.csv(in_csv, check.names = FALSE)
cop <- if (have_jsonlite) jsonlite::fromJSON(cop_json) else dget(cop_json)

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

# Derived cols
log_vars <- c("Leaf area (mm2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
offsets <- sapply(log_vars, function(v) compute_offset(df[[v]]))
work <- data.frame(
  id    = df[["wfo_accepted_name"]],
  logLA = log10(df[["Leaf area (mm2)"]] + offsets[["Leaf area (mm2)"]]),
  Nmass = as.numeric(df[["Nmass (mg/g)"]]),
  LMA   = as.numeric(df[["LMA (g/m2)"]]),
  logH  = log10(df[["Plant height (m)"]] + offsets[["Plant height (m)"]]),
  logSM = log10(df[["Diaspore mass (mg)"]] + offsets[["Diaspore mass (mg)"]]),
  logSSD= log10(df[["SSD used (mg/mm3)"]] + offsets[["SSD used (mg/mm3)"]]),
  yL = df[["EIVEres-L"]], yT = df[["EIVEres-T"]], yM = df[["EIVEres-M"]], yR = df[["EIVEres-R"]], yN = df[["EIVEres-N"]]
)

# Composites (Run 7): LES_core = PC1(-LMA, Nmass); SIZE = PC1(logH, logSM)
zs_LMA   <- zscore(work$LMA)
zs_Nmass <- zscore(work$Nmass)
M_LES    <- cbind(negLMA = -zs_LMA$x, Nmass = zs_Nmass$x)
p_les    <- stats::prcomp(M_LES, center = FALSE, scale. = FALSE)
rot_les  <- p_les$rotation[,1]; if (rot_les["Nmass"] < 0) rot_les <- -rot_les
work$LES <- as.numeric(M_LES %*% rot_les)

zs_logH  <- zscore(work$logH)
zs_logSM <- zscore(work$logSM)
M_SIZE   <- cbind(logH = zs_logH$x, logSM = zs_logSM$x)
p_size   <- stats::prcomp(M_SIZE, center = FALSE, scale. = FALSE)
rot_size <- p_size$rotation[,1]; if (rot_size["logH"] < 0) rot_size <- -rot_size
work$SIZE <- as.numeric(M_SIZE %*% rot_size)

# Fit marginals and residuals per target
fit_resid <- function(letter) {
  dat <- work
  if (letter %in% c("L","T","R")) {
    dat$y <- dat[[paste0("y", letter)]]
    dat <- dat[stats::complete.cases(dat[, c("y","LES","SIZE","logSSD","logLA")]), , drop = FALSE]
    if (letter == "L" && nzchar(gam_L_rds) && file.exists(gam_L_rds) && have_mgcv) {
      gm <- tryCatch(readRDS(gam_L_rds), error = function(e) NULL)
      if (!is.null(gm)) {
        mu <- tryCatch(as.numeric(stats::predict(gm, newdata = dat, type = "link")), error = function(e) NULL)
        if (!is.null(mu) && length(mu) == nrow(dat)) {
          res <- dat$y - mu
          return(data.frame(id = dat$id, resid = res, stringsAsFactors = FALSE))
        }
      }
      # fallback
      fm <- stats::lm(y ~ LES + SIZE + logSSD + logLA, data = dat)
    } else {
      fm <- stats::lm(y ~ LES + SIZE + logSSD + logLA, data = dat)
    }
  } else if (letter == "M") {
    dat$y <- dat$yM
    dat <- dat[stats::complete.cases(dat[, c("y","LES","logH","logSM","logSSD","logLA")]), , drop = FALSE]
    fm <- stats::lm(y ~ LES + logH + logSM + logSSD + logLA, data = dat)
  } else if (letter == "N") {
    dat$y <- dat$yN
    dat <- dat[stats::complete.cases(dat[, c("y","LES","logH","logSM","logSSD","logLA")]), , drop = FALSE]
    fm <- stats::lm(y ~ LES + logH + logSM + logSSD + logLA + LES:logSSD, data = dat)
  } else stop("bad letter")
  data.frame(id = dat$id, resid = stats::residuals(fm), stringsAsFactors = FALSE)
}

letters <- c("L","T","M","R","N")
res_map <- list()
for (L in letters) res_map[[L]] <- fit_resid(L)

res_wide <- Reduce(function(a,b) merge(a,b, by="id", all=FALSE),
                   list(
                     setNames(res_map[["L"]], c("id","resid_L")),
                     setNames(res_map[["T"]], c("id","resid_T")),
                     setNames(res_map[["M"]], c("id","resid_M")),
                     setNames(res_map[["R"]], c("id","resid_R")),
                     setNames(res_map[["N"]], c("id","resid_N"))
                   ))

pobs <- function(x) {
  r <- rank(x, ties.method = "average")
  n <- sum(is.finite(x))
  (r - 0.5)/n
}

districts <- cop$districts
if (is.data.frame(districts)) {
  nD <- nrow(districts)
} else if (is.list(districts)) {
  nD <- length(districts)
} else {
  nD <- 0
}
rows <- list()

for (d in seq_len(nD)) {
  if (is.data.frame(districts)) {
    mem <- toupper(unlist(districts$members[[d]]))
    family <- districts$family[d]
    rho_hat <- as.numeric(districts$params$rho[d])
  } else {
    mem <- toupper(unlist(districts[[d]]$members))
    family <- districts[[d]]$family
    rho_hat <- as.numeric(districts[[d]]$params$rho)
  }
  a <- mem[1]; b <- mem[2]
  ua <- pobs(res_wide[[paste0("resid_", a)]])
  vb <- pobs(res_wide[[paste0("resid_", b)]])
  ok <- is.finite(ua) & is.finite(vb)
  ua <- ua[ok]; vb <- vb[ok]
  n <- length(ua)
  # Kendall's tau empirical
  tau_emp <- suppressWarnings(stats::cor(ua, vb, method = "kendall"))
  tau_g <- (2/pi) * asin(rho_hat)
  # Tail co-occurrence vs Gaussian MC
  z <- stats::rnorm(2*mc_n)
  z <- matrix(z, ncol=2)
  z[,2] <- rho_hat * z[,1] + sqrt(1 - rho_hat^2) * z[,2]
  U <- stats::pnorm(z)
  q <- 0.9
  emp_hi <- mean(ua > q & vb > q)
  emp_lo <- mean(ua < 1-q & vb < 1-q)
  sim_hi <- mean(U[,1] > q & U[,2] > q)
  sim_lo <- mean(U[,1] < 1-q & U[,2] < 1-q)
  # 2-fold CV log-copula score improvement vs independence
  idx <- sample.int(n)
  mid <- floor(n/2)
  i1 <- idx[1:mid]; i2 <- idx[(mid+1):n]
  qn <- function(u) pmin(pmax(u, 1e-6), 1-1e-6)
  z1 <- stats::qnorm(qn(ua)); z2 <- stats::qnorm(qn(vb))
  fit_rho <- function(i) {
    r <- suppressWarnings(stats::cor(z1[i], z2[i], method = "pearson"))
    max(min(r, 0.999), -0.999)
  }
  rho_1 <- fit_rho(i1); rho_2 <- fit_rho(i2)
  logc <- function(i, rho) {
    z1i <- z1[i]; z2i <- z2[i]
    denom <- (1 - rho^2)
    S11 <- sum(z1i*z1i); S22 <- sum(z2i*z2i); S12 <- sum(z1i*z2i)
    (-length(i)/2)*log(denom) + (rho*S12)/denom - 0.5*(rho^2)*(S11+S22)/denom
  }
  ll_1 <- logc(i2, rho_1)  # train on i1, test on i2
  ll_2 <- logc(i1, rho_2)  # train on i2, test on i1
  ll_cv <- (ll_1 + ll_2)/n
  rows[[length(rows)+1]] <- data.frame(pair=paste0(a,":",b), n=n, rho=rho_hat,
                                       tau_emp=tau_emp, tau_gauss=tau_g,
                                       tail_hi_emp=emp_hi, tail_hi_mc=sim_hi,
                                       tail_lo_emp=emp_lo, tail_lo_mc=sim_lo,
                                       cv_logc_per_obs=ll_cv, stringsAsFactors = FALSE)
}

tab <- do.call(rbind, rows)

lines <- c(
  "# Run 8 — Gaussian Copula Adequacy (Quick Check)",
  "", "Pairs checked: from results/MAG_Run8/mag_copulas.json", "",
  "| Pair | n | rho | tau_emp | tau_gauss | hi_emp | hi_mc | lo_emp | lo_mc | CV logc/obs |",
  "|------|---:|----:|--------:|----------:|-------:|------:|-------:|------:|------------:|"
)
for (i in seq_len(nrow(tab))) {
  r <- tab[i,]
  lines <- c(lines, sprintf("| %s | %d | %.3f | %.3f | %.3f | %.4f | %.4f | %.4f | %.4f | %.4f |",
                            r$pair, r$n, r$rho, r$tau_emp, r$tau_gauss, r$tail_hi_emp, r$tail_hi_mc, r$tail_lo_emp, r$tail_lo_mc, r$cv_logc_per_obs))
}
lines <- c(lines, "", "Heuristics:",
           "- tau alignment within ~0.05 and tail co-occurrence within ~20% relative indicate Gaussian copula is adequate for joint gardening usage.",
           "- Positive CV log-copula per-observation implies generalization over independence.")

writeLines(lines, con = out_md)
cat(sprintf("Wrote %s\n", out_md))
