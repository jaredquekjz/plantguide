#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(jsonlite)
  library(readr)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(stringr)
})

args <- commandArgs(trailingOnly = TRUE)

parse_args <- function(args) {
  # simple flag parser: --key value
  kv <- list(
    input_csv = NULL,
    output_csv = NULL,
    equations_json = "results/mag_equations.json",
    composites_json = "results/composite_recipe.json"
  )
  if (length(args) %% 2 != 0) {
    stop("Invalid arguments. Use --input_csv <path> --output_csv <path> [--equations_json <path>] [--composites_json <path>]")
  }
  for (i in seq(1, length(args), by = 2)) {
    key <- gsub("^--", "", args[[i]])
    val <- args[[i + 1]]
    if (!key %in% names(kv)) stop(sprintf("Unknown flag: --%s", key))
    kv[[key]] <- val
  }
  if (is.null(kv$input_csv) || is.null(kv$output_csv)) {
    stop("Missing required flags: --input_csv and --output_csv")
  }
  kv
}

log_transform <- function(x, offset) {
  ifelse(is.na(x), NA_real_, log(as.numeric(x) + as.numeric(offset)))
}

zscore <- function(x, mean, sd) {
  (x - mean) / sd
}

compute_composite <- function(df, comp_def, std) {
  vars <- comp_def$variables
  loads <- comp_def$loadings
  if (length(vars) != length(loads)) stop("Composite variables and loadings length mismatch")

  # Build matrix of standardized variables (apply sign if var starts with '-')
  Z <- map_dfc(seq_along(vars), function(j) {
    v <- vars[[j]]
    sign <- 1
    if (startsWith(v, "-")) {
      sign <- -1
      v <- substring(v, 2)
    }
    if (!v %in% names(df)) stop(sprintf("Missing variable for composite: %s", v))
    if (!v %in% names(std)) stop(sprintf("Missing standardization for variable: %s", v))
    m <- std[[v]][["mean"]]
    s <- std[[v]][["sd"]]
    sign * zscore(df[[v]], m, s)
  })
  # Weighted sum (assumes loadings normalized)
  comp <- as.matrix(Z) %*% matrix(unlist(loads), ncol = 1)
  as.numeric(comp)
}

main <- function() {
  opt <- parse_args(args)

  eq <- fromJSON(opt$equations_json, simplifyVector = TRUE)
  comp <- fromJSON(opt$composites_json, simplifyVector = TRUE)

  schema <- comp$input_schema$columns
  offsets <- comp$log_offsets
  standardization <- comp$standardization
  composites <- comp$composites

  # Read input
  message(sprintf("Reading input: %s", opt$input_csv))
  df <- suppressMessages(readr::read_csv(opt$input_csv, show_col_types = FALSE, progress = FALSE))

  # Normalize column keys: map schema keys to expected names
  # Expected raw columns per schema keys: LMA, Nmass, LeafArea, PlantHeight, DiasporeMass, SSD
  required_cols <- c("LMA", "Nmass", "LeafArea", "PlantHeight", "DiasporeMass", "SSD")
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0) {
    stop(sprintf("Missing required input columns: %s", paste(missing_cols, collapse = ", ")))
  }

  # Compute logged predictors with offsets
  off_LA <- offsets[["Leaf area (mm2)"]] %||% 0
  off_H  <- offsets[["Plant height (m)"]] %||% 0
  off_SM <- offsets[["Diaspore mass (mg)"]] %||% 0
  off_SSD<- offsets[["SSD used (mg/mm3)"]] %||% 0

  df <- df %>% mutate(
    logLA = log_transform(LeafArea, off_LA),
    logH = log_transform(PlantHeight, off_H),
    logSM = log_transform(DiasporeMass, off_SM),
    logSSD = log_transform(SSD, off_SSD)
  )

  # Standardization requires raw: LMA, Nmass, logH, logSM
  # Compute composites
  # LES_core from -LMA, Nmass
  if (!is.null(composites$LES_core)) {
    df$LES_core <- compute_composite(
      df %>% select(LMA, Nmass),
      composites$LES_core,
      standardization
    )
  } else {
    stop("Composite LES_core definition missing in composites JSON")
  }
  # SIZE from logH, logSM
  if (!is.null(composites$SIZE)) {
    # Ensure standardization is defined for logH/logSM
    if (is.null(standardization$logH) || is.null(standardization$logSM)) {
      stop("Standardization for logH/logSM missing; cannot compute SIZE")
    }
    df$SIZE <- compute_composite(
      df %>% select(logH, logSM),
      composites$SIZE,
      standardization
    )
  }

  # Alias used in equations
  df$LES <- df$LES_core

  # Prepare prediction function per target
  predict_target <- function(target, terms_map, data_row) {
    # terms_map: named numeric vector of coefs, names include (Intercept) and variables like LES, SIZE, logSSD, logLA, and interactions like LES:logSSD
    y <- 0
    for (nm in names(terms_map)) {
      beta <- terms_map[[nm]]
      if (nm == "(Intercept)") {
        y <- y + beta
      } else if (grepl(":", nm)) {
        parts <- strsplit(nm, ":", fixed = TRUE)[[1]]
        val <- prod(map_dbl(parts, ~ as.numeric(data_row[[.x]])))
        y <- y + beta * val
      } else {
        val <- as.numeric(data_row[[nm]])
        y <- y + beta * val
      }
    }
    y
  }

  # Determine required predictors per target from equation terms
  eqs <- eq$equations
  targets <- names(eqs)

  # Make predictions row-wise
  preds <- df %>% mutate(row_id = row_number()) %>% group_by(row_id) %>% group_map(~ {
    row <- .x
    out <- list()
    for (t in targets) {
      terms <- eqs[[t]]$terms
      needed <- setdiff(names(terms), "(Intercept)")
      # expand interactions
      needed_vars <- unique(unlist(strsplit(needed, ":", fixed = TRUE)))
      # missing policy: if any needed var is NA, return NA
      if (any(is.na(row[, needed_vars, drop = TRUE]))) {
        out[[paste0(t, "_pred")]] <- NA_real_
      } else {
        out[[paste0(t, "_pred")]] <- predict_target(t, terms, row)
      }
    }
    as_tibble(out)
  }) %>% bind_rows()

  result <- bind_cols(df, preds)

  # Write output
  readr::write_csv(result, opt$output_csv)
  message(sprintf("Wrote predictions: %s", opt$output_csv))
}

`%||%` <- function(a, b) if (is.null(a)) b else a

main()
