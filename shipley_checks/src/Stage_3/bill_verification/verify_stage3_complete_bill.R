#!/usr/bin/env Rscript
################################################################################
# Master Stage 3 Verification (Bill's Verification)
#
# Purpose: Run all Stage 3 verification checks in sequence
# Orchestrates: CSR calculation, ecosystem services, life form stratification
################################################################################

suppressPackageStartupMessages({
  library(readr)
})

cat(strrep('=', 80), '\n')
cat('STAGE 3 VERIFICATION SUITE\n')
cat(strrep('=', 80), '\n\n')

# Configuration
R_LIBS <- Sys.getenv('R_LIBS_USER', '/home/olier/ellenberg/.Rlib')
SCRIPT_DIR <- 'src/Stage_3/bill_verification'
SCRIPTS <- c(
  'verify_csr_calculation_bill.R',
  'verify_ecoservices_bill.R',
  'verify_lifeform_stratification_bill.R'
)

all_passed <- TRUE

for (i in seq_along(SCRIPTS)) {
  script <- SCRIPTS[i]
  cat(sprintf('[%d/%d] Running %s...\n', i, length(SCRIPTS), script))
  cat(strrep('-', 80), '\n')

  script_path <- file.path(SCRIPT_DIR, script)

  if (!file.exists(script_path)) {
    cat(sprintf('✗ ERROR: Script not found: %s\n\n', script_path))
    all_passed <- FALSE
    next
  }

  # Run script and capture exit status
  result <- system2(
    'env',
    args = c(
      sprintf('R_LIBS_USER=%s', R_LIBS),
      '/usr/bin/Rscript',
      script_path
    ),
    stdout = TRUE,
    stderr = TRUE
  )

  exit_code <- attr(result, 'status')
  if (is.null(exit_code)) exit_code <- 0

  # Print output
  cat(paste(result, collapse = '\n'), '\n\n')

  if (exit_code != 0) {
    cat(sprintf('✗ FAILED (exit code: %d)\n\n', exit_code))
    all_passed <- FALSE
  } else {
    cat(sprintf('✓ PASSED\n\n'))
  }
}

# Final summary
cat(strrep('=', 80), '\n')
cat('STAGE 3 VERIFICATION COMPLETE\n')
cat(strrep('=', 80), '\n\n')

if (all_passed) {
  cat('✓ CSR calculation: PASSED\n')
  cat('✓ Ecosystem services: PASSED\n')
  cat('✓ Life form stratification: PASSED\n')
  cat('\nAll verification checks passed.\n')
  quit(status = 0)
} else {
  cat('✗ Some checks failed. Review output above.\n')
  quit(status = 1)
}
