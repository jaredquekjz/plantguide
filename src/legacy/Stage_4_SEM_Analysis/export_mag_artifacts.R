#!/usr/bin/env Rscript

suppressWarnings({
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
    have_jsonlite <- requireNamespace("jsonlite", quietly = TRUE)
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

in_csv  <- opts[["input_csv"]] %||% "artifacts/model_data_complete_case_with_myco.csv"
out_dir <- opts[["out_dir"]]   %||% "results"

ensure_dir <- function(path) dir.create(path, recursive = TRUE, showWarnings = FALSE)
ensure_dir(out_dir)

fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }
if (!file.exists(in_csv)) fail(sprintf("Input CSV not found: '%s'", in_csv))

df <- if (have_readr) readr::read_csv(in_csv, show_col_types = FALSE, progress = FALSE) else utils::read.csv(in_csv, check.names = FALSE)

# Required columns
targets <- c("L","T","M","R","N")
feature_cols <- c("Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
miss <- setdiff(c(paste0("EIVEres-", targets), feature_cols), names(df))
if (length(miss)) fail(sprintf("Missing required columns: %s", paste(miss, collapse=", ")))

# Complete cases for predictors and each target when fitting
compute_offset <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x) & !is.na(x) & x > 0]
  if (!length(x)) return(1e-6)
  max(1e-6, 1e-3 * stats::median(x))
}

log_vars <- c("Leaf area (mm2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
offsets <- sapply(log_vars, function(v) compute_offset(df[[v]]))

# Derived columns
work <- data.frame(
  id    = df[["wfo_accepted_name"]],
  logLA = log10(df[["Leaf area (mm2)"]] + offsets[["Leaf area (mm2)"]]),
  Nmass = df[["Nmass (mg/g)"]],
  LMA   = df[["LMA (g/m2)"]],
  logH  = log10(df[["Plant height (m)"]] + offsets[["Plant height (m)"]]),
  logSM = log10(df[["Diaspore mass (mg)"]] + offsets[["Diaspore mass (mg)"]]),
  logSSD= log10(df[["SSD used (mg/mm3)"]] + offsets[["SSD used (mg/mm3)"]])
)

zscore <- function(x) {
  m <- mean(x, na.rm=TRUE); s <- stats::sd(x, na.rm=TRUE); if (!is.finite(s) || s == 0) s <- 1
  list(x=(x-m)/s, mean=m, sd=s)
}

# Build composites on FULL DATA consistent with Run 7
# LES_core = PC1 of [-LMA, Nmass] from z-scored inputs, oriented to positive Nmass loading
zs_LMA   <- zscore(work$LMA)
zs_Nmass <- zscore(work$Nmass)
M_LES    <- cbind(negLMA = -zs_LMA$x, Nmass = zs_Nmass$x)
p_les    <- stats::prcomp(M_LES, center = FALSE, scale. = FALSE)
rot_les  <- p_les$rotation[,1]
if (rot_les["Nmass"] < 0) rot_les <- -rot_les
work$LES <- as.numeric(M_LES %*% rot_les)

# SIZE = PC1 of [logH, logSM] from z-scored inputs, oriented to positive logH
zs_logH  <- zscore(work$logH)
zs_logSM <- zscore(work$logSM)
M_SIZE   <- cbind(logH = zs_logH$x, logSM = zs_logSM$x)
p_size   <- stats::prcomp(M_SIZE, center = FALSE, scale. = FALSE)
rot_size <- p_size$rotation[,1]
if (rot_size["logH"] < 0) rot_size <- -rot_size
work$SIZE <- as.numeric(M_SIZE %*% rot_size)

# Fit OLS per target with final forms (full data; returns intercept)
fit_target <- function(letter) {
  y <- df[[paste0("EIVEres-", letter)]]
  dat <- cbind(work, y = y)
  # Drop rows with any NA in required columns per target
  if (letter %in% c("L","T","R")) {
    req <- c("y","LES","SIZE","logSSD","logLA")
    dat <- dat[stats::complete.cases(dat[, req]), , drop = FALSE]
    fm <- stats::lm(y ~ LES + SIZE + logSSD + logLA, data = dat)
  } else if (letter == "M") {
    req <- c("y","LES","logH","logSM","logSSD","logLA")
    dat <- dat[stats::complete.cases(dat[, req]), , drop = FALSE]
    fm <- stats::lm(y ~ LES + logH + logSM + logSSD + logLA, data = dat)
  } else if (letter == "N") {
    req <- c("y","LES","logH","logSM","logSSD","logLA")
    dat <- dat[stats::complete.cases(dat[, req]), , drop = FALSE]
    fm <- stats::lm(y ~ LES + logH + logSM + logSSD + logLA + LES:logSSD, data = dat)
  } else stop("Unknown target letter")
  list(model = fm, n = nrow(dat))
}

fits <- lapply(targets, fit_target)
names(fits) <- targets

# Build equations export (JSON + CSV)
mk_row <- function(letter, term, estimate) data.frame(target = letter, term = term, estimate = as.numeric(estimate), stringsAsFactors = FALSE)
rows <- list()
eqs  <- list()
for (letter in targets) {
  fm <- fits[[letter]]$model
  cf <- stats::coef(fm)
  r2 <- summary(fm)$r.squared
  terms <- names(cf)
  eq <- list(
    target = letter,
    n = fits[[letter]]$n,
    r2_in_sample = unname(r2),
    terms = as.list(cf)
  )
  eqs[[letter]] <- eq
  for (i in seq_along(cf)) {
    rows[[length(rows)+1]] <- mk_row(letter, terms[i], cf[i])
  }
}

equations_json <- list(
  version = list(
    sem_stage = "Stage 2",
    run = "Run 7 (rerun aligned)",
    date = format(Sys.time(), "%Y-%m-%d"),
    git_commit = tryCatch(system("git rev-parse --short HEAD", intern = TRUE)[1], error = function(e) NA_character_)
  ),
  data = list(
    source_csv = in_csv,
    missing_policy = "return_no_prediction_if_any_required_predictor_is_missing"
  ),
  equations = eqs
)

# Composite recipe export
schema <- list(
  columns = list(
    list(name = "LMA (g/m2)",          key = "LMA",    type = "number", units = "g/m2"),
    list(name = "Nmass (mg/g)",         key = "Nmass",  type = "number", units = "mg/g"),
    list(name = "Leaf area (mm2)",      key = "LeafArea", type = "number", units = "mm2"),
    list(name = "Plant height (m)",     key = "PlantHeight", type = "number", units = "m"),
    list(name = "Diaspore mass (mg)",   key = "DiasporeMass", type = "number", units = "mg"),
    list(name = "SSD used (mg/mm3)",    key = "SSD", type = "number", units = "mg/mm3")
  )
)

composite_recipe <- list(
  version = equations_json$version,
  input_schema = schema,
  log_offsets = as.list(offsets),
  standardization = list(
    LMA   = list(mean = unname(mean(work$LMA, na.rm=TRUE)),   sd = unname(stats::sd(work$LMA, na.rm=TRUE))),
    Nmass = list(mean = unname(mean(work$Nmass, na.rm=TRUE)), sd = unname(stats::sd(work$Nmass, na.rm=TRUE))),
    logH  = list(mean = unname(mean(work$logH, na.rm=TRUE)),  sd = unname(stats::sd(work$logH, na.rm=TRUE))),
    logSM = list(mean = unname(mean(work$logSM, na.rm=TRUE)), sd = unname(stats::sd(work$logSM, na.rm=TRUE)))
  ),
  composites = list(
    LES_core = list(variables = c("-LMA", "Nmass"), loadings = as.list(unname(rot_les)), orientation = "positive_Nmass"),
    SIZE     = list(variables = c("logH", "logSM"), loadings = as.list(unname(rot_size)), orientation = "positive_logH")
  ),
  missing_policy = equations_json$data$missing_policy
)

# Write files
eq_json_path <- file.path(out_dir, "mag_equations.json")
eq_csv_path  <- file.path(out_dir, "mag_equations.csv")
recipe_path  <- file.path(out_dir, "composite_recipe.json")

if (have_jsonlite) cat(jsonlite::toJSON(equations_json, pretty = TRUE, auto_unbox = TRUE), file = eq_json_path) else dput(equations_json, file = eq_json_path)
utils::write.csv(do.call(rbind, rows), eq_csv_path, row.names = FALSE)
if (have_jsonlite) cat(jsonlite::toJSON(composite_recipe, pretty = TRUE, auto_unbox = TRUE), file = recipe_path) else dput(composite_recipe, file = recipe_path)

cat(sprintf("Wrote %s, %s, %s\n", eq_json_path, eq_csv_path, recipe_path))

