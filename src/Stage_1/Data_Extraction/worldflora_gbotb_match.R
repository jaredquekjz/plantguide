#!/usr/bin/env Rscript

cat("Starting WorldFlora matching for GBOTB phylogeny dataset\n")
flush.console()

suppressPackageStartupMessages({
  library(data.table)
  library(WorldFlora)
})

log_msg <- function(...) {
  cat(..., "\n", sep = "")
  flush.console()
}

args <- commandArgs(trailingOnly = FALSE)
file_arg_idx <- grep("^--file=", args)
if (length(file_arg_idx) == 0) {
  script_dir <- getwd()
} else {
  script_path <- sub("^--file=", "", args[file_arg_idx[length(file_arg_idx)]])
  script_dir <- dirname(normalizePath(script_path))
}
repo_root <- normalizePath(file.path(script_dir, "..", "..", ".."), winslash = "/", mustWork = TRUE)

input_path <- file.path(repo_root, "data/phylogeny/gbotb_names_for_wfo.csv")
output_path <- file.path(repo_root, "data/phylogeny/gbotb_wfo_worldflora.csv")
wfo_path <- file.path(repo_root, "data/classification.csv")

log_msg("Reading GBOTB names from: ", input_path)
gbotb <- fread(input_path, encoding = "UTF-8", data.table = FALSE)
log_msg("Loaded ", nrow(gbotb), " species rows")

# GBOTB uses scientific_name column (converted from Genus_species format)
gbotb$name_raw <- trimws(gbotb$scientific_name)
gbotb <- gbotb[!is.na(gbotb$name_raw) & nchar(gbotb$name_raw) > 0, ]
log_msg("Retained ", nrow(gbotb), " rows with non-empty scientific names")

log_msg("Preparing names with WFO.prepare()")
prep <- WFO.prepare(
  spec.data = gbotb,
  spec.full = "name_raw",
  squish = TRUE,
  spec.name.nonumber = TRUE,
  spec.name.sub = TRUE,
  verbose = FALSE
)
log_msg("Prepared names; resulting rows: ", nrow(prep))

log_msg("Loading WFO backbone from: ", wfo_path)
wfo <- fread(
  wfo_path,
  sep = "\t",
  encoding = "Latin-1",
  data.table = FALSE,
  showProgress = TRUE
)
wfo_rows <- nrow(wfo)
log_msg("WFO backbone rows: ", wfo_rows)

log_msg("Running WFO.match() with exact matching (Fuzzy = 0)")
matches <- WFO.match(
  spec.data = prep,
  WFO.data = wfo,
  acceptedNameUsageID.match = TRUE,
  Fuzzy = 0,
  Fuzzy.force = FALSE,
  Fuzzy.two = TRUE,
  Fuzzy.one = TRUE,
  verbose = TRUE,
  counter = 1000
)
log_msg("Matched rows: ", nrow(matches))

log_msg("Writing results to: ", output_path)
fwrite(matches, output_path)
log_msg("Completed WorldFlora matching for GBOTB phylogeny dataset")
