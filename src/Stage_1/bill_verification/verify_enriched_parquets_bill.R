#!/usr/bin/env Rscript
# verify_enriched_parquets_bill.R - Verify WFO merge with original datasets
suppressPackageStartupMessages({library(arrow)})
check_pass <- function(cond, msg) { stat <- if (cond) "✓" else "✗"; cat(sprintf("  %s %s\n", stat, msg)); return(cond) }

cat("========================================================================\n")
cat("VERIFICATION: Enriched Parquets\n")
cat("========================================================================\n\n")

FILES <- c("duke"=14030, "eive"=14835, "mabberly"=13489, "tryenhanced"=46047)
DIR <- "data/shipley_checks/wfo_verification"
all_pass <- TRUE

for (ds in names(FILES)) {
  file <- sprintf("%s/%s_worldflora_enriched.parquet", DIR, ds)
  all_pass <- check_pass(file.exists(file), sprintf("%s: File exists", ds)) && all_pass
  
  if (file.exists(file)) {
    df <- read_parquet(file)
    expected <- FILES[[ds]]
    all_pass <- check_pass(abs(nrow(df) - expected) <= 10, sprintf("%s: %d rows [expected %d ± 10]", ds, nrow(df), expected)) && all_pass
    all_pass <- check_pass(!any(is.na(df$wfo_taxon_id)), sprintf("%s: wfo_taxon_id complete", ds)) && all_pass
  }
}

cat("\n========================================================================\n")
if (all_pass) { cat("✓ VERIFICATION PASSED\n========================================================================\n\n"); quit(status = 0)
} else { cat("✗ VERIFICATION FAILED\n========================================================================\n\n"); quit(status = 1) }
