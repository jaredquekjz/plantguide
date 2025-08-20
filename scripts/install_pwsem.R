#!/usr/bin/env Rscript
# Install pwSEM into a project-local library (.Rlib) with CRAN-first strategy
# Usage examples:
#   Rscript scripts/install_pwsem.R                         # auto (CRAN if available; else GitHub)
#   Rscript scripts/install_pwsem.R --method=cran           # force CRAN
#   Rscript scripts/install_pwsem.R --method=github         # force GitHub
#   Rscript scripts/install_pwsem.R --libdir=/path/to/lib   # custom library location
#   Rscript scripts/install_pwsem.R --build_vignettes=yes   # build vignettes (needs LaTeX)

args <- commandArgs(trailingOnly = TRUE)

get_flag <- function(name, default = NULL) {
  m <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(m)) {
    sub(paste0("^--", name, "="), "", m[1])
  } else default
}

fail <- function(msg, status = 1L) {
  message("Error: ", msg)
  quit(save = "no", status = status)
}

safe_bool <- function(x, default = FALSE) {
  if (is.null(x)) return(default)
  tolower(as.character(x)) %in% c("1", "true", "yes", "y")
}

# Parse flags
method <- tolower(get_flag("method", "auto"))             # auto|cran|github
libdir <- get_flag("libdir", file.path(getwd(), ".Rlib"))
build_vignettes <- safe_bool(get_flag("build_vignettes", "no"))
force_install <- safe_bool(get_flag("force", "no"))

op <- options(
  repos = c(CRAN = "https://cloud.r-project.org"),
  warn = 1
)
on.exit(options(op), add = TRUE)

# Library path and environment
libdir <- normalizePath(libdir, mustWork = FALSE)
if (!dir.exists(libdir)) dir.create(libdir, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(libdir, .libPaths()))
Sys.setenv(R_REMOTES_NO_ERRORS_FROM_WARNINGS = "true")

message(".libPaths():\n", paste0(" - ", .libPaths(), collapse = "\n"))
message("Install method: ", method)

# System dependency checks ---------------------------------------------------
check_gsl <- function() {
  has <- nzchar(Sys.which("gsl-config"))
  if (has) return(invisible(TRUE))
  os <- Sys.info()[["sysname"]]
  message("\nSystem dependency missing: gsl-config (GNU Scientific Library).\n",
          "The R packages 'gsl' and 'copula' require GSL headers and libs.\n",
          "Install GSL using your OS package manager, then re-run this script.\n")
  if (identical(os, "Linux")) {
    message("Debian/Ubuntu:    sudo apt-get update && sudo apt-get install -y libgsl-dev build-essential gfortran\n",
            "Fedora/RHEL/CentOS: sudo dnf install -y gsl-devel gcc gcc-c++ gcc-gfortran make\n",
            "Arch Linux:        sudo pacman -S --needed gsl base-devel gcc-fortran\n",
            "Alpine:            sudo apk add gsl-dev build-base gfortran\n")
  } else if (identical(os, "Darwin")) {
    message("macOS (Homebrew):  brew install gsl\n",
            "If Homebrew is not in PATH at build time, set:\n",
            "  export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"\n")
  } else if (identical(os, "Windows")) {
    message("Windows: Use the precompiled CRAN binary for 'gsl'. Ensure Rtools is installed.\n",
            "If compiling from source via MSYS2, install GSL via pacman and ensure gsl-config is in PATH.\n")
  }
  fail("Missing gsl-config. Install GSL and try again.", status = 2L)
}

# Decide method if auto
if (method == "auto") {
  available_on_cran <- FALSE
  try({
    ap <- available.packages()
    available_on_cran <- "pwSEM" %in% rownames(ap)
  }, silent = TRUE)
  method <- if (available_on_cran) "cran" else "github"
  message("Auto-selected method: ", method)
}

install_if_missing <- function(pkgs) {
  for (p in pkgs) {
    if (!requireNamespace(p, quietly = TRUE)) {
      message("Installing dependency: ", p)
      install.packages(p, lib = libdir, dependencies = TRUE)
    }
  }
}

install_github_pwsem <- function() {
  # Preinstall system-backed deps first
  check_gsl()
  # Preinstall core R deps (including Imports)
  install_if_missing(c("mgcv", "gsl", "copula", "gamm4", "igraph", "poolr", "devtools", "BiocManager"))
  if (!requireNamespace("graph", quietly = TRUE)) {
    message("Installing Bioconductor package: graph")
    BiocManager::install("graph", ask = FALSE, update = FALSE, lib = libdir)
  }
  # ggm depends on Bioc 'graph'; install after 'graph'
  install_if_missing(c("ggm"))
  message("Installing pwSEM from GitHub (BillShipley/pwSEM)")
  devtools::install_github(
    "BillShipley/pwSEM",
    dependencies = TRUE,
    build_vignettes = build_vignettes,
    upgrade = "never",
    force = force_install
  )
}

install_cran_pwsem <- function() {
  message("Pre-installing dependencies for CRAN build")
  check_gsl()
  install_if_missing(c("mgcv", "gsl", "copula", "gamm4", "igraph", "poolr", "BiocManager"))
  if (!requireNamespace("graph", quietly = TRUE)) {
    message("Installing Bioconductor package: graph")
    BiocManager::install("graph", ask = FALSE, update = FALSE, lib = libdir)
  }
  install_if_missing(c("ggm"))
  message("Installing pwSEM from CRAN")
  install.packages("pwSEM", lib = libdir, dependencies = TRUE)
}

# Perform installation
if (method == "cran") {
  tryCatch(install_cran_pwsem(), error = function(e) fail(conditionMessage(e)))
} else if (method == "github") {
  tryCatch(install_github_pwsem(), error = function(e) fail(conditionMessage(e)))
} else {
  fail("Unknown --method=; use auto|cran|github")
}

"\n# Verify and diagnose\n"
ok <- FALSE
load_err <- NULL
pkg_path <- NA_character_
ver <- NA_character_
try({
  pkg_path <- suppressWarnings(tryCatch(find.package("pwSEM"), error = function(e) NA_character_))
  suppressPackageStartupMessages(library(pwSEM))
  ok <- TRUE
  ver <- as.character(utils::packageVersion("pwSEM"))
}, silent = TRUE)
if (!ok) {
  load_err <- tryCatch({
    library(pwSEM)
    NULL
  }, error = function(e) conditionMessage(e))
  message("pwSEM failed to load. Details:\n- find.package: ", pkg_path,
          "\n- error: ", if (is.null(load_err)) "<unknown>" else load_err,
          "\n- .libPaths():\n", paste0("  * ", .libPaths(), collapse = "\n"))
  fail("pwSEM did not load after installation.")
}

cat("pwSEM version:", ver, "\n")
cat("Installed at:", normalizePath(find.package("pwSEM")), "\n")
cat("Library search paths:\n", paste0(" - ", .libPaths(), collapse = "\n"), "\n", sep = "")

invisible(NULL)
