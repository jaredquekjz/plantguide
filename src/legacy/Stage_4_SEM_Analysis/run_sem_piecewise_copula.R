#!/usr/bin/env Rscript

# Stage 4 — SEM (piecewise) + Copula augmentation (Run 8)
# - Reuses the finalized MAG mean structure (Run 7 forms) to compute residuals per target.
# - Auto-detects residual dependence pairs (districts) via residual correlations with FDR control.
# - Fits Gaussian copulas for selected districts using rank PIT pseudo-observations.
# - Outputs copula metadata JSON and diagnostics for Run 8.

suppressWarnings({
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
    have_jsonlite <- requireNamespace("jsonlite", quietly = TRUE)
    have_stats    <- requireNamespace("stats",    quietly = TRUE)
    have_mgcv     <- requireNamespace("mgcv",     quietly = TRUE)
  })
})

args <- commandArgs(trailingOnly = TRUE)

# Parser supporting both --k=v and "--k v" as well as repeated --district
parse_args <- function(args) {
  out <- list()
  out$district <- character(0)
  i <- 1
  while (i <= length(args)) {
    a <- args[[i]]
    if (grepl("^--[A-Za-z0-9_]+=", a)) {
      kv <- sub("^--", "", a)
      k <- sub("=.*$", "", kv)
      v <- sub("^[^=]*=", "", kv)
      if (k == "district") out$district <- c(out$district, v) else out[[k]] <- v
      i <- i + 1
    } else if (grepl("^--[A-Za-z0-9_]+$", a)) {
      k <- sub("^--", "", a)
      v <- if (i < length(args)) args[[i+1]] else ""
      if (nzchar(v) && !startsWith(v, "--")) {
        if (k == "district") out$district <- c(out$district, v) else out[[k]] <- v
        i <- i + 2
      } else {
        # boolean flag with no following value
        out[[k]] <- "true"
        i <- i + 1
      }
    } else {
      i <- i + 1
    }
  }
  out
}

opts <- parse_args(args)

`%||%` <- function(a,b) if (!is.null(a) && length(a) > 0 && all(nzchar(a))) a else b

# Inputs / flags (defaults aligned to proposal)
in_csv    <- opts[["input_csv"]]  %||% "artifacts/model_data_complete_case_with_myco.csv"
out_dir   <- opts[["out_dir"]]    %||% "results"
version   <- opts[["version"]]    %||% "Run 8"
auto_det  <- tolower(opts[["auto_detect_districts"]] %||% "true") %in% c("1","true","yes","y")
rho_min   <- suppressWarnings(as.numeric(opts[["rho_min"]] %||% "0.15")); if (is.na(rho_min)) rho_min <- 0.15
fdr_q     <- suppressWarnings(as.numeric(opts[["fdr_q"]]   %||% "0.05")); if (is.na(fdr_q))   fdr_q   <- 0.05
copulas   <- tolower(opts[["copulas"]] %||% "gaussian")
select_by <- toupper(opts[["select_by"]] %||% "AIC")
districts_cli <- opts$district
group_col <- opts[["group_col"]] %||% ""   # optional: compute per-group correlations/copulas
min_group_n <- suppressWarnings(as.integer(opts[["min_group_n"]] %||% "20")); if (is.na(min_group_n)) min_group_n <- 20
shrink_k <- suppressWarnings(as.numeric(opts[["shrink_k"]] %||% "100")); if (!is.finite(shrink_k)) shrink_k <- 100
# Optional: use a non-linear GAM for L residualization (path to a saved mgcv::gam RDS)
gam_L_rds <- opts[["gam_L_rds"]] %||% ""

ensure_dir <- function(path) dir.create(path, recursive = TRUE, showWarnings = FALSE)
ensure_dir(out_dir)

fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }

if (!file.exists(in_csv)) fail(sprintf("Input CSV not found: '%s'", in_csv))

# Load data
df <- if (have_readr) readr::read_csv(in_csv, show_col_types = FALSE, progress = FALSE) else utils::read.csv(in_csv, check.names = FALSE)

# Validate columns
targets <- c("L","T","M","R","N")
feature_cols <- c("Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
miss <- setdiff(c(paste0("EIVEres-", targets), feature_cols, "wfo_accepted_name"), names(df))
if (length(miss)) fail(sprintf("Missing required columns: %s", paste(miss, collapse=", ")))

# Helpers
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

# Transforms and composites — LES_core from [-LMA, Nmass]; SIZE from [logH, logSM]
log_vars <- c("Leaf area (mm2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
offsets <- sapply(log_vars, function(v) compute_offset(df[[v]]))

work <- data.frame(
  id    = df[["wfo_accepted_name"]],
  logLA = log10(df[["Leaf area (mm2)"]] + offsets[["Leaf area (mm2)"]]),
  Nmass = as.numeric(df[["Nmass (mg/g)"]]),
  LMA   = as.numeric(df[["LMA (g/m2)"]]),
  logH  = log10(df[["Plant height (m)"]] + offsets[["Plant height (m)"]]),
  logSM = log10(df[["Diaspore mass (mg)"]] + offsets[["Diaspore mass (mg)"]]),
  logSSD= log10(df[["SSD used (mg/mm3)"]] + offsets[["SSD used (mg/mm3)"]])
)

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

# Fit OLS per target (forms from recommendation) and compute residuals
fit_target <- function(letter) {
  y <- df[[paste0("EIVEres-", letter)]]
  dat <- cbind(work, y = as.numeric(y))
  if (letter %in% c("L","T","R")) {
    req <- c("y","LES","SIZE","logSSD","logLA")
    dat <- dat[stats::complete.cases(dat[, req]), , drop = FALSE]
    if (letter == "L" && nzchar(gam_L_rds) && file.exists(gam_L_rds) && have_mgcv) {
      # Use GAM model for L; compute residuals as y - predict(gam)
      gm <- tryCatch(readRDS(gam_L_rds), error = function(e) NULL)
      if (!is.null(gm)) {
        mu <- tryCatch(as.numeric(stats::predict(gm, newdata = dat, type = "link")), error = function(e) NULL)
        if (!is.null(mu) && length(mu) == nrow(dat)) {
          resid <- dat$y - mu
          return(list(model = gm, n = nrow(dat), resid = resid, id = dat$id, method = "gam"))
        }
      }
      # Fallback to linear if GAM predict failed
      fm <- stats::lm(y ~ LES + SIZE + logSSD + logLA, data = dat)
    } else {
      fm <- stats::lm(y ~ LES + SIZE + logSSD + logLA, data = dat)
    }
  } else if (letter == "M") {
    req <- c("y","LES","logH","logSM","logSSD","logLA")
    dat <- dat[stats::complete.cases(dat[, req]), , drop = FALSE]
    fm <- stats::lm(y ~ LES + logH + logSM + logSSD + logLA, data = dat)
  } else if (letter == "N") {
    req <- c("y","LES","logH","logSM","logSSD","logLA")
    dat <- dat[stats::complete.cases(dat[, req]), , drop = FALSE]
    fm <- stats::lm(y ~ LES + logH + logSM + logSSD + logLA + LES:logSSD, data = dat)
  } else stop("Unknown target letter")
  resid <- stats::residuals(fm)
  list(model = fm, n = nrow(dat), resid = resid, id = dat$id, method = "lm")
}

fits <- lapply(targets, fit_target)
names(fits) <- targets

# Gather residuals into wide form by id
merge_resids <- function(fits) {
  frames <- list()
  for (letter in names(fits)) {
    frames[[letter]] <- data.frame(id = fits[[letter]]$id, residual = fits[[letter]]$resid, stringsAsFactors = FALSE)
    names(frames[[letter]])[2] <- paste0("resid_", letter)
  }
  out <- Reduce(function(a,b) merge(a,b, by = "id", all = TRUE), frames)
  out
}

res_wide <- merge_resids(fits)

# Attach group column if requested and available
group_map <- NULL
if (nzchar(group_col) && (group_col %in% names(df))) {
  group_map <- df[, c("wfo_accepted_name", group_col), drop = FALSE]
  names(group_map) <- c("id", "group")
  # Keep the most frequent label per id if duplicates
  group_tab <- aggregate(list(n = rep(1L, nrow(group_map))), by = list(id = group_map$id, group = group_map$group), FUN = length)
  ord <- order(group_tab$id, -group_tab$n)
  group_tab <- group_tab[ord, ]
  group_tab <- group_tab[!duplicated(group_tab$id), c("id","group")]
  res_wide <- merge(res_wide, group_tab, by = "id", all.x = TRUE, sort = FALSE)
}

# Residual correlation matrix and FDR screening
letters <- names(fits)
pairs <- combn(letters, 2, simplify = FALSE)
rows <- list()
for (pr in pairs) {
  a <- pr[1]; b <- pr[2]
  va <- res_wide[[paste0("resid_", a)]]
  vb <- res_wide[[paste0("resid_", b)]]
  ok <- is.finite(va) & is.finite(vb)
  na <- sum(ok)
  if (na >= 10) {
    r <- suppressWarnings(stats::cor(va[ok], vb[ok], method = "pearson"))
    ct <- try(stats::cor.test(va[ok], vb[ok], method = "pearson"), silent = TRUE)
    p <- if (!inherits(ct, "try-error")) ct$p.value else NA_real_
    rows[[length(rows)+1]] <- data.frame(A=a, B=b, n=na, rho=r, pval=p, stringsAsFactors = FALSE)
  } else {
    rows[[length(rows)+1]] <- data.frame(A=a, B=b, n=na, rho=NA_real_, pval=NA_real_, stringsAsFactors = FALSE)
  }
}

corr_df <- do.call(rbind, rows)
if (nrow(corr_df)) {
  corr_df$qval <- stats::p.adjust(corr_df$pval, method = "BH")
} else {
  corr_df$qval <- numeric(0)
}

# Determine districts
selected_edges <- list()
if (!is.null(districts_cli) && length(districts_cli) > 0) {
  for (d in districts_cli) {
    parts <- unlist(strsplit(d, "[:,]"))
    parts <- toupper(trimws(parts))
    parts <- parts[nzchar(parts)]
    if (length(parts) >= 2) selected_edges[[length(selected_edges)+1]] <- parts[1:2]
  }
} else if (auto_det && nrow(corr_df)) {
  # Greedy maximum matching by |rho| with thresholds
  cand <- corr_df[stats::complete.cases(corr_df$rho) & abs(corr_df$rho) >= rho_min & corr_df$qval <= fdr_q, , drop = FALSE]
  if (nrow(cand)) {
    cand <- cand[order(-abs(cand$rho), cand$pval), ]
    used <- character(0)
    for (i in seq_len(nrow(cand))) {
      a <- cand$A[i]; b <- cand$B[i]
      if (!(a %in% used) && !(b %in% used)) {
        selected_edges[[length(selected_edges)+1]] <- c(as.character(a), as.character(b))
        used <- c(used, a, b)
      }
    }
  }
}

if (!length(selected_edges)) {
  # Default to proposal seed if no auto-detected pair passes thresholds
  selected_edges <- list(c("L","T"), c("M","R"))
}

# Fit Gaussian copula for each selected pair using pseudo-observations
rank_pobs <- function(x) {
  r <- rank(x, ties.method = "average", na.last = "keep")
  n <- sum(is.finite(x))
  u <- (r - 0.5)/n
  as.numeric(u)
}

gauss_copula_fit <- function(u, v) {
  ok <- is.finite(u) & is.finite(v)
  u <- u[ok]; v <- v[ok]
  if (length(u) < 10) return(list(n=length(u), rho=NA_real_, loglik=NA_real_, AIC=NA_real_))
  # avoid boundaries
  u <- pmin(pmax(u, 1e-6), 1-1e-6)
  v <- pmin(pmax(v, 1e-6), 1-1e-6)
  z1 <- stats::qnorm(u); z2 <- stats::qnorm(v)
  rho <- suppressWarnings(stats::cor(z1, z2, method = "pearson"))
  rho <- max(min(rho, 0.999), -0.999)
  n <- length(z1)
  s11 <- sum(z1*z1); s22 <- sum(z2*z2); s12 <- sum(z1*z2)
  denom <- (1 - rho^2)
  logc_sum <- (-n/2) * log(denom) + (rho * s12)/denom - 0.5 * (rho^2) * (s11 + s22)/denom
  AIC <- 2*1 - 2*logc_sum
  list(n=n, rho=rho, loglik=logc_sum, AIC=AIC)
}

fit_rows <- list()
districts_out <- list()
for (edge in selected_edges) {
  a <- edge[1]; b <- edge[2]
  ua <- rank_pobs(res_wide[[paste0("resid_", a)]])
  vb <- rank_pobs(res_wide[[paste0("resid_", b)]])
  fit <- gauss_copula_fit(ua, vb)
  fit_rows[[length(fit_rows)+1]] <- data.frame(A=a, B=b, n=fit$n, family="gaussian", rho=fit$rho, loglik=fit$loglik, AIC=fit$AIC, stringsAsFactors = FALSE)
  districts_out[[length(districts_out)+1]] <- list(members = list(a, b), family = "gaussian", params = list(rho = unname(fit$rho)), n = unname(fit$n))
}

fit_df <- do.call(rbind, fit_rows)

# Optional: per-group residual correlations and copula fits for selected edges
by_group <- NULL
diag_rows <- list()
if (!is.null(group_map)) {
  levs <- unique(res_wide$group)
  levs <- levs[!is.na(levs) & nzchar(as.character(levs))]
  if (length(levs)) {
    by_group <- list()
    # helper to compute corr df within a group
    corr_for_group <- function(df_sub) {
      rows <- list()
      for (pr in pairs) {
        a <- pr[1]; b <- pr[2]
        va <- df_sub[[paste0("resid_", a)]]
        vb <- df_sub[[paste0("resid_", b)]]
        ok <- is.finite(va) & is.finite(vb)
        na <- sum(ok)
        if (na >= 10) {
          r <- suppressWarnings(stats::cor(va[ok], vb[ok], method = "pearson"))
          ct <- try(stats::cor.test(va[ok], vb[ok], method = "pearson"), silent = TRUE)
          p <- if (!inherits(ct, "try-error")) ct$p.value else NA_real_
          rows[[length(rows)+1]] <- data.frame(A=a, B=b, n=na, rho=r, pval=p, stringsAsFactors = FALSE)
        } else {
          rows[[length(rows)+1]] <- data.frame(A=a, B=b, n=na, rho=NA_real_, pval=NA_real_, stringsAsFactors = FALSE)
        }
      }
      out <- do.call(rbind, rows)
      if (nrow(out)) out$qval <- stats::p.adjust(out$pval, method = "BH") else out$qval <- numeric(0)
      out
    }
    # Global rho map for shrinkage
    rho_global_map <- list()
    if (exists("fit_df") && is.data.frame(fit_df) && nrow(fit_df)>0) {
      for (i in seq_len(nrow(fit_df))) {
        key <- paste0(fit_df$A[i], "|", fit_df$B[i])
        rho_global_map[[key]] <- as.numeric(fit_df$rho[i])
      }
    }
    key_of <- function(a,b) paste0(a, "|", b)

    for (g in levs) {
      sub <- res_wide[which(res_wide$group == g), , drop = FALSE]
      if (nrow(sub) < min_group_n) next
      corr_g <- corr_for_group(sub)
      # Fit same selected edges within group
      fit_rows_g <- list(); districts_out_g <- list()
      for (edge in selected_edges) {
        a <- edge[1]; b <- edge[2]
        ua <- rank_pobs(sub[[paste0("resid_", a)]])
        vb <- rank_pobs(sub[[paste0("resid_", b)]])
        fitg <- gauss_copula_fit(ua, vb)
        # Shrink rho toward global by weight w = n/(n+shrink_k)
        rho_raw <- as.numeric(fitg$rho)
        rho_glob <- rho_global_map[[ key_of(a,b) ]] %||% rho_raw
        w <- if (is.finite(shrink_k) && shrink_k > 0) (fitg$n / (fitg$n + shrink_k)) else 1.0
        if (!is.finite(w) || w < 0) w <- 0
        if (w > 1) w <- 1
        rho_use <- w * rho_raw + (1 - w) * rho_glob
        fit_rows_g[[length(fit_rows_g)+1]] <- data.frame(A=a, B=b, n=fitg$n, family="gaussian", rho=rho_use, rho_raw=rho_raw, rho_global=rho_glob, weight=w, stringsAsFactors = FALSE)
        districts_out_g[[length(districts_out_g)+1]] <- list(members = list(a, b), family = "gaussian", params = list(rho = unname(rho_use), rho_raw = unname(rho_raw), weight = unname(w)), n = unname(fitg$n))
        # Diagnostics: Kendall tau, implied tau from rho_use, normal-score correlation
        ok <- is.finite(ua) & is.finite(vb)
        tu <- try(stats::cor(sub[[paste0("resid_", a)]][ok], sub[[paste0("resid_", b)]][ok], method = "kendall"), silent = TRUE)
        tau_samp <- if (!inherits(tu, "try-error")) as.numeric(tu) else NA_real_
        z1 <- stats::qnorm(pmin(pmax(ua[ok], 1e-6), 1-1e-6))
        z2 <- stats::qnorm(pmin(pmax(vb[ok], 1e-6), 1-1e-6))
        rho_z <- suppressWarnings(stats::cor(z1, z2, method = "pearson"))
        tau_from_rho <- if (is.finite(rho_use)) (2/pi) * asin(rho_use) else NA_real_
        diag_rows[[length(diag_rows)+1]] <- data.frame(group=as.character(g), A=a, B=b, n=fitg$n, rho_raw=rho_raw, rho_shrunk=rho_use, rho_global=rho_glob, weight=w, tau_sample=tau_samp, tau_from_rho=tau_from_rho, tau_delta=tau_samp - tau_from_rho, rho_z=rho_z, stringsAsFactors = FALSE)
      }
      by_group[[as.character(g)]] <- list(
        residual_correlation = corr_g,
        districts = districts_out_g
      )
    }
  }
}

# Persist outputs
cop_json <- list(
  version = list(run = version, date = format(Sys.time(), "%Y-%m-%d"), git_commit = tryCatch(system("git rev-parse --short HEAD", intern = TRUE)[1], error = function(e) NA_character_)),
  selection = list(criterion = select_by, auto_detect = auto_det, thresholds = list(rho_min = rho_min, fdr_q = fdr_q)),
  residual_correlation = corr_df,
  districts = districts_out,
  by_group = by_group
)

json_path <- file.path(out_dir, "mag_copulas.json")
if (have_jsonlite) {
  cat(jsonlite::toJSON(cop_json, pretty = TRUE, dataframe = "rows", auto_unbox = TRUE, na = "null"), file = json_path)
} else {
  dput(cop_json, file = json_path)
}

diag_corr_path <- file.path(out_dir, "stage_sem_run8_residual_corr.csv")
if (have_readr) readr::write_csv(corr_df, diag_corr_path) else utils::write.csv(corr_df, diag_corr_path, row.names = FALSE)

fit_path <- file.path(out_dir, "stage_sem_run8_copula_fits.csv")
if (have_readr) readr::write_csv(fit_df, fit_path) else utils::write.csv(fit_df, fit_path, row.names = FALSE)

# Group diagnostics (if any)
if (length(diag_rows)) {
  diag_df <- do.call(rbind, diag_rows)
  diag_path <- file.path(out_dir, "stage_sem_run8_copula_group_diagnostics.csv")
  if (have_readr) readr::write_csv(diag_df, diag_path) else utils::write.csv(diag_df, diag_path, row.names = FALSE)
}

cat(sprintf("Wrote %s, %s, %s\n", json_path, diag_corr_path, fit_path))
