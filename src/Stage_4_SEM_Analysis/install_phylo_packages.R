#!/usr/bin/env Rscript

# Simple installer for phylogeny-related packages used to build a Newick tree
# Installs: V.PhyloMaker2, ape, readr, tibble, tidyr
# Usage:
#   Rscript src/Stage_4_SEM_Analysis/install_phylo_packages.R \
#     --lib=/path/to/Rlibs --repos=https://cloud.r-project.org --quiet=true
# Notes:
# - If --lib is omitted, uses R_LIBS_USER if set, else default user lib.
# - Honors R_EXTRA_LIBS (prepends to .libPaths) for package discovery.

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

# Library paths handling
extra_libs <- Sys.getenv("R_EXTRA_LIBS")
if (nzchar(extra_libs)) {
  paths <- unlist(strsplit(extra_libs, "[,:;]", perl = TRUE))
  paths <- paths[nzchar(paths)]
  if (length(paths)) .libPaths(c(paths, .libPaths()))
}

lib_dir <- opts[["lib"]]
if (is.null(lib_dir) || !nzchar(lib_dir)) {
  lib_dir <- Sys.getenv("R_LIBS_USER")
  if (!nzchar(lib_dir)) lib_dir <- .libPaths()[1]
}
if (!dir.exists(lib_dir)) dir.create(lib_dir, recursive = TRUE, showWarnings = FALSE)

repos <- opts[["repos"]]
if (is.null(repos) || !nzchar(repos)) repos <- "https://cloud.r-project.org"
quiet <- tolower(opts[["quiet"]] %||% "true") %in% c("1","true","yes","y")

`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b

# V.PhyloMaker2 is on github, not CRAN. Others are on CRAN.
# remotes is needed for github install
pkgs_cran <- c("remotes", "ape", "readr", "tibble", "tidyr")
pkgs_gh <- c("V.PhyloMaker2")
gh_repo <- c("jinyizju/V.PhyloMaker2")
names(gh_repo) <- pkgs_gh

pkgs_all <- c(pkgs_cran, pkgs_gh)

cat(sprintf("Installing packages to lib='%s' using repos='%s'\n", lib_dir, repos))
cat(sprintf("Requested: %s\n", paste(pkgs_all, collapse=", ")))

installed <- rownames(installed.packages(lib.loc = .libPaths()))
need_all <- setdiff(pkgs_all, installed)

if (!length(need_all)) {
  cat("All packages already installed.\n")
  quit(status = 0)
}

# Install CRAN packages
need_cran <- intersect(need_all, pkgs_cran)
ok <- logical(length(pkgs_all))
names(ok) <- pkgs_all
ok[setdiff(pkgs_all, need_all)] <- TRUE

if (length(need_cran)) {
  cat(sprintf("Installing from CRAN: %s\n", paste(need_cran, collapse=", ")))
  tryCatch({
    utils::install.packages(need_cran, lib = lib_dir, repos = repos, quiet = quiet,
                            dependencies = c("Depends","Imports"))
    cran_installed <- need_cran %in% rownames(installed.packages(lib.loc = lib_dir))
    ok[need_cran] <- cran_installed
    if (any(!cran_installed)) {
        cat(sprintf("  -> FAILED: %s\n", paste(need_cran[!cran_installed], collapse=", ")))
    }
  }, error = function(e) {
    cat(sprintf("  -> FAILED to install from CRAN: %s\n", conditionMessage(e)))
  })
}

# Install GitHub packages
need_gh <- intersect(need_all, pkgs_gh)
if (length(need_gh)) {
    # Ensure remotes is loaded from the correct lib path
    if (!requireNamespace("remotes", quietly = TRUE, lib.loc = lib_dir)) {
        cat("Could not load 'remotes' package, cannot install from GitHub.\n")
        ok[need_gh] <- FALSE
    } else {
        cat(sprintf("Installing from GitHub: %s\n", paste(need_gh, collapse=", ")))
        for (p in need_gh) {
            cat(sprintf("Installing '%s'...\n", p))
            tryCatch({
                remotes::install_github(gh_repo[p], lib = lib_dir, quiet = quiet,
                                        dependencies = c("Depends","Imports"),
                                        force = TRUE) # Force install to get from GH
                ok[p] <- p %in% rownames(installed.packages(lib.loc = lib_dir))
                cat(sprintf("  -> %s\n", if (ok[p]) "OK" else "FAILED"))
            }, error = function(e) {
                cat(sprintf("  -> FAILED: %s\n", conditionMessage(e)))
            })
        }
    }
}


fail <- names(ok)[!ok]
if (length(fail)) {
  cat(sprintf("[warn] Failed to install: %s\n", paste(fail, collapse=", ")))
  quit(status = 1)
}
cat("All requested packages installed successfully.\n")

