#!/usr/bin/env Rscript

cat("Starting WorldFlora matching for Mabberly dataset\n")
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

input_path <- file.path(repo_root, "data/shipley_checks/wfo_verification/mabberly_names_for_r.csv")
output_dir <- file.path(repo_root, "data/shipley_checks/wfo_verification")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
output_path <- file.path(output_dir, "mabberly_wfo_worldflora.csv")
wfo_path <- file.path(repo_root, "data/classification.csv")

log_msg("Reading Mabberly names from: ", input_path)
mab <- fread(input_path, encoding = "UTF-8", data.table = FALSE)
log_msg("Loaded ", nrow(mab), " name rows")

mab$name_raw <- trimws(mab$Genus)
mab <- mab[!is.na(mab$name_raw) & nchar(mab$name_raw) > 0, ]
log_msg("Retained ", nrow(mab), " rows with non-empty raw names")

log_msg("Preparing names with WFO.prepare()")
prep <- WFO.prepare(
  spec.data = mab,
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
log_msg("WFO backbone rows: ", nrow(wfo))

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
log_msg("Completed WorldFlora matching for Mabberly dataset")
