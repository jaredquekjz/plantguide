#!/usr/bin/env Rscript

# Mycorrhiza power test: LM with interactions to detect group-wise SSD effects
# - Fits pooled vs by-group interaction model for logSSD by Myco_Group_Final.
# - Reports AIC comparison, LR p-value, and per-group p-values for logSSD.
# - Outputs CSV summary and per-group table under artifacts/stage4_sem_myco_run3/.

suppressWarnings({
  suppressMessages({
    have_readr <- requireNamespace("readr", quietly = TRUE)
  })
})

args <- commandArgs(trailingOnly = TRUE)
parse_args <- function(args) { out<-list(); for (a in args) if (grepl('^--',a)) {k<-sub('^--','',a); k1<-sub('=.*$','',k); v<-sub('^[^=]*=','',k); out[[k1]]<-v}; out }
`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b
opts <- parse_args(args)

in_csv   <- opts[["input_csv"]]   %||% "artifacts/model_data_complete_case_with_myco.csv"
targets  <- toupper(opts[["targets"]] %||% "R,N")
min_n    <- suppressWarnings(as.integer(opts[["min_group_n"]] %||% "25")); if (is.na(min_n)) min_n <- 25
out_dir  <- opts[["out_dir"]]     %||% "artifacts/stage4_sem_myco_run3"

ensure_dir <- function(p) dir.create(p, recursive = TRUE, showWarnings = FALSE)
ensure_dir(out_dir)

fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }
if (!file.exists(in_csv)) fail(sprintf("Input CSV not found: '%s'", in_csv))

df <- if (have_readr) readr::read_csv(in_csv, show_col_types = FALSE, progress = FALSE) else utils::read.csv(in_csv, check.names = FALSE)

feature_cols <- c("Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
id_col <- "wfo_accepted_name"
myco_col <- "Myco_Group_Final"
miss <- setdiff(c(feature_cols, id_col, myco_col), names(df))
if (length(miss)) fail(sprintf("Missing required columns: %s", paste(miss, collapse=", ")))

compute_offset <- function(x) {
  x <- as.numeric(x); x <- x[is.finite(x) & !is.na(x) & x > 0]
  if (!length(x)) return(1e-6)
  max(1e-6, 1e-3 * stats::median(x))
}

log_vars <- c("Leaf area (mm2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
offsets <- sapply(log_vars, function(v) compute_offset(df[[v]]))

prep <- function(df) {
  work <- df[, c(id_col, myco_col, feature_cols), drop = FALSE]
  names(work)[1:2] <- c("id","myco")
  work$logLA <- log10(work[["Leaf area (mm2)"]] + offsets[["Leaf area (mm2)"]])
  work$logH  <- log10(work[["Plant height (m)"]] + offsets[["Plant height (m)"]])
  work$logSM <- log10(work[["Diaspore mass (mg)"]] + offsets[["Diaspore mass (mg)"]])
  work$logSSD<- log10(work[["SSD used (mg/mm3)"]] + offsets[["SSD used (mg/mm3)"]])
  work$LMA   <- as.numeric(work[["LMA (g/m2)"]])
  work$Nmass <- as.numeric(work[["Nmass (mg/g)"]])
  # Build LES and SIZE composites on full data
  M_LES <- scale(cbind(negLMA = -work$LMA, Nmass = work$Nmass, logLA = work$logLA), center = TRUE, scale = TRUE)
  p_les <- stats::prcomp(M_LES, center = FALSE, scale. = FALSE)
  rot_les <- p_les$rotation[,1]
  if (rot_les["Nmass"] < 0) rot_les <- -rot_les
  work$LES <- as.numeric(M_LES %*% rot_les)
  M_SIZE <- scale(cbind(logH = work$logH, logSM = work$logSM), center = TRUE, scale = TRUE)
  p_size <- stats::prcomp(M_SIZE, center = FALSE, scale. = FALSE)
  rot_size <- p_size$rotation[,1]
  if (rot_size["logH"] < 0) rot_size <- -rot_size
  work$SIZE <- as.numeric(M_SIZE %*% rot_size)
  work
}

analyze <- function(work, target_letter) {
  yname <- paste0("EIVEres-", target_letter)
  if (!(yname %in% names(df))) return(NULL)
  dat <- cbind(work, y = as.numeric(df[[yname]]))
  # keep complete cases and non-missing myco
  dat <- dat[stats::complete.cases(dat[, c("y","LES","SIZE","logSSD","myco")]), , drop = FALSE]
  # drop tiny myco levels
  tab <- sort(table(dat$myco), decreasing = TRUE)
  keep <- names(tab)[tab >= min_n & !is.na(names(tab))]
  dat <- dat[dat$myco %in% keep, , drop = FALSE]
  dat$myco <- droplevels(factor(dat$myco))
  if (nlevels(dat$myco) < 2) return(list(summary = data.frame(target = target_letter, n = nrow(dat), msg = "<2 myco groups after filtering>")))
  m0 <- stats::lm(y ~ LES + SIZE + logSSD + myco, data = dat)
  m1 <- stats::lm(y ~ LES + SIZE + myco + logSSD:myco, data = dat)  # focus on SSD moderation as per recommendation
  a0 <- tryCatch(AIC(m0), error = function(e) NA_real_)
  a1 <- tryCatch(AIC(m1), error = function(e) NA_real_)
  lr <- tryCatch({ anova(m0, m1) }, error = function(e) NULL)
  lr_p <- if (!is.null(lr) && nrow(lr) >= 2) as.numeric(lr$`Pr(>F)`[2]) else NA_real_
  # per-group SSD p-values via per-group fits (simple and robust)
  levs <- levels(dat$myco)
  rows <- list()
  for (lv in levs) {
    sub <- dat[dat$myco == lv, , drop = FALSE]
    if (nrow(sub) < min_n) next
    mg <- stats::lm(y ~ LES + SIZE + logSSD, data = sub)
    co <- summary(mg)$coefficients
    pss <- if ("logSSD" %in% rownames(co)) co["logSSD", 4] else NA_real_
    bss <- if ("logSSD" %in% rownames(co)) co["logSSD", 1] else NA_real_
    rows[[length(rows)+1]] <- data.frame(group = lv, n = nrow(sub), beta_logSSD = bss, p_logSSD = pss, stringsAsFactors = FALSE)
  }
  per_group <- if (length(rows)) do.call(rbind, rows) else data.frame()
  summary <- data.frame(
    target = target_letter,
    n = nrow(dat),
    groups = nlevels(dat$myco),
    AIC_pooled = a0,
    AIC_interaction = a1,
    LR_p = lr_p,
    choose_interaction = is.finite(a1) && is.finite(a0) && (a1 + 2) < a0,
    stringsAsFactors = FALSE
  )
  list(summary = summary, per_group = per_group)
}

work <- prep(df)

ensure_dir(out_dir)
out_sum <- list()
targets_vec <- unlist(strsplit(targets, ","))
for (t in targets_vec) {
  res <- analyze(work, t)
  if (is.null(res)) next
  if (!is.null(res$per_group) && nrow(res$per_group)) {
    pg_path <- file.path(out_dir, sprintf("myco_power_%s_per_group.csv", t))
    if (have_readr) readr::write_csv(res$per_group, pg_path) else utils::write.csv(res$per_group, pg_path, row.names = FALSE)
  }
  if (!is.null(res$summary)) {
    out_sum[[length(out_sum)+1]] <- res$summary
  }
}

sum_df <- if (length(out_sum)) do.call(rbind, out_sum) else data.frame()
sum_path <- file.path(out_dir, "myco_power_summary.csv")
if (have_readr) readr::write_csv(sum_df, sum_path) else utils::write.csv(sum_df, sum_path, row.names = FALSE)
cat(sprintf("Wrote myco power summary: %s (%d rows)\n", sum_path, nrow(sum_df)))

