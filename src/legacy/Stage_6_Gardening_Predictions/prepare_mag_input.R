#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
})

parse_args <- function(args) {
  opt <- list(
    source_csv = NULL,
    output_csv = "results/mag_input_no_eive.csv",
    drop_if_has_eive = TRUE,
    species_col = NULL
  )
  if (length(args) %% 2 != 0) stop("Usage: --source_csv <path> --output_csv <path> [--drop_if_has_eive true|false] [--species_col <name>]")
  for (i in seq(1, length(args), by = 2)) {
    key <- gsub("^--", "", args[[i]])
    val <- args[[i+1]]
    if (!key %in% names(opt)) stop(sprintf("Unknown flag: --%s", key))
    if (key == "drop_if_has_eive") opt[[key]] <- tolower(val) %in% c("true","1","yes") else opt[[key]] <- val
  }
  if (is.null(opt$source_csv)) stop("Missing --source_csv")
  opt
}

find_species_col <- function(df, override = NULL) {
  if (!is.null(override) && override %in% names(df)) return(override)
  cands <- c("species", "wfo_accepted_name", "Species name standardized against TPL", "Species")
  for (c in cands) if (c %in% names(df)) return(c)
  return(NULL)
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  opt <- parse_args(args)
  message(sprintf("Reading: %s", opt$source_csv))
  df <- suppressMessages(readr::read_csv(opt$source_csv, show_col_types = FALSE))

  species_col <- find_species_col(df, opt$species_col)
  if (is.null(species_col)) species_col <- NA_character_

  # Columns expected in artifacts
  colmap <- list(
    LeafArea = "Leaf area (mm2)",
    Nmass = "Nmass (mg/g)",
    LMA = "LMA (g/m2)",
    PlantHeight = "Plant height (m)",
    DiasporeMass = "Diaspore mass (mg)",
    SSD = "SSD used (mg/mm3)"
  )
  missing <- setdiff(unlist(colmap), names(df))
  if (length(missing) > 0) stop(sprintf("Missing required trait columns: %s", paste(missing, collapse=", ")))

  # Identify EIVE columns if present
  eive_cols <- c(L = "EIVEres-L", T = "EIVEres-T", M = "EIVEres-M", R = "EIVEres-R", N = "EIVEres-N")
  has_eive_cols <- all(eive_cols %in% names(df))

  if (!is.na(species_col)) {
    out <- df %>% transmute(
      species = .data[[species_col]],
      LMA = .data[[colmap$LMA]],
      Nmass = .data[[colmap$Nmass]],
      LeafArea = .data[[colmap$LeafArea]],
      PlantHeight = .data[[colmap$PlantHeight]],
      DiasporeMass = .data[[colmap$DiasporeMass]],
      SSD = .data[[colmap$SSD]]
    )
  } else {
    out <- df %>% transmute(
      LMA = .data[[colmap$LMA]],
      Nmass = .data[[colmap$Nmass]],
      LeafArea = .data[[colmap$LeafArea]],
      PlantHeight = .data[[colmap$PlantHeight]],
      DiasporeMass = .data[[colmap$DiasporeMass]],
      SSD = .data[[colmap$SSD]]
    )
  }

  if (opt$drop_if_has_eive && has_eive_cols) {
    # keep rows where at least one EIVE axis is NA (i.e., lacking EIVE)
    mask <- df %>% mutate(has_all = if_all(all_of(unname(eive_cols)), ~ !is.na(.))) %>% pull(has_all)
    keep <- !mask
    out <- out[keep, , drop = FALSE]
  }

  # Tag source and drop rows missing any required predictor
  out <- out %>% mutate(source = "MAG") %>% tidyr::drop_na(LMA, Nmass, LeafArea, PlantHeight, DiasporeMass, SSD)

  readr::write_csv(out, opt$output_csv)
  message(sprintf("Wrote MAG input: %s (rows=%d, cols=%d)", opt$output_csv, nrow(out), ncol(out)))
}

main()
