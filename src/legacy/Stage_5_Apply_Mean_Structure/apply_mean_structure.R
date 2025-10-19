#!/usr/bin/env Rscript
# Applies DAG mean-structure equations to new trait inputs.
# Not a MAG (Mixed Acyclic Graph) or m-sep implementation; residual
# dependence across axes (bidirected edges) is handled downstream via
# copulas. Inputs: mag_equations.json (mean equations), composite_recipe.json.
suppressPackageStartupMessages({
  library(jsonlite)
  library(readr)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(stringr)
  suppressWarnings(suppressMessages(requireNamespace("ape", quietly = TRUE)))
})

args <- commandArgs(trailingOnly = TRUE)

parse_args <- function(args) {
  # simple flag parser: --key value
  kv <- list(
    input_csv = NULL,
    output_csv = NULL,
    equations_json = "results/mag_equations.json",
    composites_json = "results/composite_recipe.json",
    gam_L_rds = "",  # optional: path to mgcv::gam RDS for non-linear L predictions
    # Optional phylo blending
    blend_with_phylo = "false",
    alpha_per_axis = "",
    alpha = "0.25",
    phylogeny_newick = "",
    reference_eive_csv = "",
    reference_species_col = "wfo_accepted_name",
    target_species_col = "wfo_accepted_name",
    x = "2",
    k_trunc = "0"
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

  # Optional: load GAM model for L if provided
  gam_L <- NULL
  if (nzchar(opt$gam_L_rds)) {
    if (!requireNamespace("mgcv", quietly = TRUE)) {
      warning("mgcv not available; ignoring --gam_L_rds")
    } else if (file.exists(opt$gam_L_rds)) {
      gam_L <- tryCatch(readRDS(opt$gam_L_rds), error = function(e) NULL)
      if (is.null(gam_L)) warning("Failed to read GAM RDS for L; falling back to linear L from equations")
    } else {
      warning(sprintf("GAM RDS not found: %s; falling back to linear L", opt$gam_L_rds))
    }
  }

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
      # If GAM for L is present, prefer it for L (Run 7c); build mgcv feature frame using log10
      if (t == "L" && !is.null(gam_L)) {
        new_mg <- data.frame(
          LMA   = as.numeric(row$LMA),
          Nmass = as.numeric(row$Nmass),
          logLA = log10(as.numeric(row$LeafArea) + off_LA),
          logH  = log10(as.numeric(row$PlantHeight) + off_H),
          logSSD= log10(as.numeric(row$SSD) + off_SSD)
        )
        mu <- tryCatch(as.numeric(stats::predict(gam_L, newdata = new_mg, type = "link")), error = function(e) NA_real_)
        out[["L_pred"]] <- mu
        next
      }
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

  # Optional: phylogenetic neighbor blending
  to_bool <- function(x) tolower(x) %in% c("1","true","yes","y")
  if (to_bool(opt$blend_with_phylo)) {
    # Validate required inputs for blending
    if (!nzchar(opt$phylogeny_newick) || !file.exists(opt$phylogeny_newick)) stop("--phylogeny_newick is required and must exist when --blend_with_phylo is true")
    if (!nzchar(opt$reference_eive_csv) || !file.exists(opt$reference_eive_csv)) stop("--reference_eive_csv is required and must exist when --blend_with_phylo is true")
    target_species_col <- opt$target_species_col
    if (!target_species_col %in% names(result)) stop(sprintf("Target species column '%s' not found in input", target_species_col))

    # Load donors and tree
    ref <- suppressWarnings(readr::read_csv(opt$reference_eive_csv, show_col_types = FALSE, progress = FALSE))
    ref <- as.data.frame(ref)
    ref_species_col <- opt$reference_species_col
    if (!ref_species_col %in% names(ref)) stop(sprintf("Reference species column '%s' not found in reference CSV", ref_species_col))
    eive_cols <- c("EIVEres-L","EIVEres-T","EIVEres-M","EIVEres-R","EIVEres-N")
    miss_e <- setdiff(eive_cols, names(ref))
    if (length(miss_e) > 0) stop(sprintf("Reference CSV missing EIVE columns: %s", paste(miss_e, collapse=",")))

    tree <- tryCatch(ape::read.tree(opt$phylogeny_newick), error = function(e) NULL)
    if (is.null(tree)) stop("Failed to read Newick tree")

    # Build union of donors and targets present on tree
    donors <- unique(ref[[ref_species_col]])
    targets_sp <- unique(result[[target_species_col]])
    donors_tips <- gsub(" ", "_", donors, fixed = TRUE)
    targets_tips <- gsub(" ", "_", targets_sp, fixed = TRUE)
    tips <- tree$tip.label
    keep_d <- donors_tips %in% tips
    keep_t <- targets_tips %in% tips
    donors_tips <- donors_tips[keep_d]
    targets_tips <- targets_tips[keep_t]
    donors_keep <- donors[keep_d]
    targets_keep <- targets_sp[keep_t]
    union_tips <- unique(c(donors_tips, targets_tips))
    tree2 <- ape::keep.tip(tree, union_tips)
    cop <- ape::cophenetic.phylo(tree2)

    # Donor indices and target indices in cophenetic matrix
    donor_pos <- match(donors_tips, rownames(cop))
    names(donor_pos) <- donors_keep
    # Precompute donor EIVE maps aligned to cop columns
    donors_map <- setNames(donors_keep, donors_tips)
    donor_E <- lapply(eive_cols, function(col) {
      vals <- ref[[col]][match(donors_keep, ref[[ref_species_col]])]
      names(vals) <- donors_tips
      vals
    })
    names(donor_E) <- eive_cols

    # Helper to compute p_k for a vector of target species (length nrows)
    xexp <- suppressWarnings(as.numeric(opt$x)); if (!is.finite(xexp)) xexp <- 2
    k_trunc <- suppressWarnings(as.integer(opt$k_trunc)); if (!is.finite(k_trunc)) k_trunc <- 0L
    compute_p_for_axis <- function(axis_col) {
      p <- rep(NA_real_, nrow(result))
      # Map each target row to tree tip pos; compute weights against donors
      targ_names <- result[[target_species_col]]
      targ_tips <- gsub(" ", "_", targ_names, fixed = TRUE)
      targ_pos <- match(targ_tips, rownames(cop))
      Ek <- donor_E[[axis_col]]
      Ek <- Ek[intersect(names(Ek), colnames(cop))]
      if (!length(Ek)) return(p)
      for (j in which(!is.na(targ_pos))) {
        tj <- targ_pos[j]
        dists <- cop[tj, names(Ek)]
        w <- rep(0, length(dists))
        ok <- is.finite(dists) & dists > 0
        if (any(ok)) {
          w[ok] <- 1 / (dists[ok]^xexp)
          # Exclude self if target exists among donors (same tip)
          self_idx <- which(names(Ek) == rownames(cop)[tj])
          if (length(self_idx)) w[self_idx] <- 0
          if (k_trunc > 0 && sum(w > 0) > k_trunc) {
            ord <- order(dists, na.last = NA)
            keep <- head(ord[dists[ord] > 0], k_trunc)
            mask <- rep(FALSE, length(w)); mask[keep] <- TRUE
            w[!mask] <- 0
          }
          den <- sum(w)
          if (den > .Machine$double.eps) {
            p[j] <- sum(w * Ek) / den
          } else {
            p[j] <- mean(Ek, na.rm = TRUE)
          }
        } else {
          p[j] <- mean(Ek, na.rm = TRUE)
        }
      }
      p
    }

    # Compute phylo predictions per axis
    pL <- compute_p_for_axis("EIVEres-L")
    pT <- compute_p_for_axis("EIVEres-T")
    pM <- compute_p_for_axis("EIVEres-M")
    pR <- compute_p_for_axis("EIVEres-R")
    pN <- compute_p_for_axis("EIVEres-N")

    result$L_pred_phylo <- pL
    result$T_pred_phylo <- pT
    result$M_pred_phylo <- pM
    result$R_pred_phylo <- pR
    result$N_pred_phylo <- pN

    # Alphas
    alpha_map <- list(L = NA_real_, T = NA_real_, M = NA_real_, R = NA_real_, N = NA_real_)
    if (nzchar(opt$alpha_per_axis)) {
      parts <- unlist(strsplit(opt$alpha_per_axis, ","))
      for (p in parts) {
        kv <- unlist(strsplit(p, "=", fixed = TRUE))
        if (length(kv) == 2) {
          k <- toupper(trimws(kv[[1]])); v <- suppressWarnings(as.numeric(kv[[2]]))
          if (k %in% names(alpha_map) && is.finite(v)) alpha_map[[k]] <- max(0, min(1, v))
        }
      }
    }
    # Fill missing with global alpha
    a_global <- suppressWarnings(as.numeric(opt$alpha)); if (!is.finite(a_global)) a_global <- 0.25
    for (nm in names(alpha_map)) if (!is.finite(alpha_map[[nm]])) alpha_map[[nm]] <- a_global
    message(sprintf("Blending with alphas: L=%.2f,T=%.2f,M=%.2f,R=%.2f,N=%.2f",
                    alpha_map$L, alpha_map$T, alpha_map$M, alpha_map$R, alpha_map$N))

    # Preserve SEM-only predictions
    for (t in c("L","T","M","R","N")) {
      sem_col <- paste0(t, "_pred")
      if (!(sem_col %in% names(result))) next
      result[[paste0(t, "_pred_sem")]] <- result[[sem_col]]
    }
    # Blend with fallback when either term is NA
    blend_fun <- function(sem, phy, a) {
      ifelse(is.na(sem) & !is.na(phy), phy,
        ifelse(!is.na(sem) & is.na(phy), sem,
          (1 - a) * sem + a * phy))
    }
    result$L_pred_blend <- blend_fun(result$L_pred, result$L_pred_phylo, alpha_map$L)
    result$T_pred_blend <- blend_fun(result$T_pred, result$T_pred_phylo, alpha_map$T)
    result$M_pred_blend <- blend_fun(result$M_pred, result$M_pred_phylo, alpha_map$M)
    result$R_pred_blend <- blend_fun(result$R_pred, result$R_pred_phylo, alpha_map$R)
    result$N_pred_blend <- blend_fun(result$N_pred, result$N_pred_phylo, alpha_map$N)

    # Overwrite primary preds with blended values
    result$L_pred <- result$L_pred_blend
    result$T_pred <- result$T_pred_blend
    result$M_pred <- result$M_pred_blend
    result$R_pred <- result$R_pred_blend
    result$N_pred <- result$N_pred_blend
  }

  # Write output
  readr::write_csv(result, opt$output_csv)
  message(sprintf("Wrote predictions: %s", opt$output_csv))
}

`%||%` <- function(a, b) if (is.null(a)) b else a

main()
