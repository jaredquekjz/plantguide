#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  .libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))
  library(data.table)
  library(optparse)
})
opt_list <- list(
  make_option(c("--soil_summary"), type = "character",
              default = "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary.csv"),
  make_option(c("--nitrogen_summary"), type = "character",
              default = "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_nitrogen_summary.csv"),
  make_option(c("--backup"), type = "character",
              default = "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary.bak.csv")
)
opt <- parse_args(OptionParser(option_list = opt_list))
cat("Patching soil species summary with nitrogen-only columns...\n")
ss <- fread(opt$soil_summary)
ns <- fread(opt$nitrogen_summary)
if (!"species" %in% names(ss) || !"species" %in% names(ns)) stop("species column missing")
# Keep nitrogen *_mean/*_sd/*_n_valid columns from nitrogen summary
ncols <- grep("^nitrogen_.*_(mean|sd|n_valid)$", names(ns), value = TRUE)
if (length(ncols) == 0) stop("No nitrogen columns found in nitrogen summary")
# Merge
setkey(ss, species); setkey(ns, species)
ss2 <- merge(ss, ns[, c("species", ncols), with = FALSE], by = "species", all.x = TRUE, suffixes = c("", ".nitro"))
# Overlay nitrogen columns
for (col in ncols) {
  col_n <- paste0(col, ".nitro")
  if (col_n %in% names(ss2)) {
    # Coerce to numeric to handle columns read as all-NA logical
    suppressWarnings({ ss2[[col]] <- as.numeric(ss2[[col]]) })
    suppressWarnings({ ss2[[col_n]] <- as.numeric(ss2[[col_n]]) })
    # Overlay nitrogen summary values where available
    v <- ss2[[col]]; vn <- ss2[[col_n]]
    idx <- !is.na(vn)
    v[idx] <- vn[idx]
    ss2[[col]] <- v
    ss2[[col_n]] <- NULL
  }
}
# Backup and write
fwrite(ss, opt$backup)
fwrite(ss2, opt$soil_summary)
cat("Patched. Backup written to:", opt$backup, "\n")
# Coverage report for nitrogen layers
nitros <- grep("^nitrogen_.*_mean$", names(ss2), value = TRUE)
if (length(nitros) > 0) {
  cov <- sapply(nitros, function(nm) mean(!is.na(ss2[[nm]])))
  cat("Nitrogen mean coverage after patch:\n")
  print(round(cov, 3))
}
