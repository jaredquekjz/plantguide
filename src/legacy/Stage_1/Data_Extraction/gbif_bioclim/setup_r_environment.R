#!/usr/bin/env Rscript

# =============================================================================
# R Environment Setup for GBIF Cleaning Pipeline
# =============================================================================
# This script ensures all required packages are installed in the local library

# Set local library path
local_lib <- "/home/olier/ellenberg/.Rlib"
dir.create(local_lib, showWarnings = FALSE, recursive = TRUE)
.libPaths(c(local_lib, .libPaths()))

cat("========================================\n")
cat("R Environment Setup\n")
cat("========================================\n")
cat("Library path:", local_lib, "\n\n")

# Required packages for the pipeline
required_packages <- c(
  # Data manipulation
  "tidyverse",      # Comprehensive data science toolkit
  "data.table",     # High-performance data manipulation
  
  # Spatial and cleaning
  "CoordinateCleaner",  # GBIF coordinate cleaning
  "bdc",               # Biodiversity data cleaning
  "terra",             # Raster operations (successor to raster)
  "sf",                # Spatial features
  "rnaturalearth",     # Natural Earth map data
  "rnaturalearthdata", # Natural Earth data
  
  # Utilities
  "cli",         # Command line interface
  "progressr",   # Progress bars
  "parallel",    # Parallel processing (usually comes with R)
  "jsonlite"     # JSON handling
)

# Check which packages are already installed
installed_packages <- installed.packages(lib.loc = local_lib)[, "Package"]
missing_packages <- required_packages[!required_packages %in% installed_packages]

if (length(missing_packages) == 0) {
  cat("✓ All required packages are already installed\n")
} else {
  cat("Missing packages:", paste(missing_packages, collapse = ", "), "\n\n")
  
  # Install missing packages
  cat("Installing missing packages...\n")
  
  # Set CRAN mirror
  options(repos = c(CRAN = "https://cloud.r-project.org/"))
  
  for (pkg in missing_packages) {
    cat("\nInstalling", pkg, "...\n")
    tryCatch({
      install.packages(pkg, lib = local_lib, dependencies = TRUE, quiet = TRUE)
      cat("✓", pkg, "installed successfully\n")
    }, error = function(e) {
      cat("✗ Failed to install", pkg, ":", e$message, "\n")
      
      # Special handling for certain packages
      if (pkg == "terra") {
        cat("  Note: terra requires GDAL library. Install with: sudo apt-get install gdal-bin libgdal-dev\n")
      }
      if (pkg == "sf") {
        cat("  Note: sf requires GEOS, GDAL, and PROJ. Install with:\n")
        cat("  sudo apt-get install libudunits2-dev libgdal-dev libgeos-dev libproj-dev\n")
      }
    })
  }
}

# Verify installation
cat("\n========================================\n")
cat("Verification\n")
cat("========================================\n")

# Check all packages can be loaded
all_ok <- TRUE
for (pkg in required_packages) {
  cat("Checking", pkg, "... ")
  suppressWarnings({
    if (require(pkg, character.only = TRUE, lib.loc = local_lib, quietly = TRUE)) {
      cat("✓\n")
    } else {
      cat("✗ Not available\n")
      all_ok <- FALSE
    }
  })
}

cat("\n========================================\n")
if (all_ok) {
  cat("✓ R environment setup complete!\n")
  cat("All required packages are available.\n")
} else {
  cat("⚠ Some packages are missing.\n")
  cat("Please install system dependencies and re-run this script.\n")
  cat("\nCommon system dependencies:\n")
  cat("Ubuntu/Debian:\n")
  cat("  sudo apt-get update\n")
  cat("  sudo apt-get install -y \\\n")
  cat("    gdal-bin libgdal-dev \\\n")
  cat("    libgeos-dev \\\n")
  cat("    libproj-dev \\\n")
  cat("    libudunits2-dev \\\n")
  cat("    libcurl4-openssl-dev \\\n")
  cat("    libssl-dev \\\n")
  cat("    libxml2-dev\n")
}
cat("========================================\n")