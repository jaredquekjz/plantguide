#!/usr/bin/env Rscript

# Tiny lmer smoke test
# Goal: verify mixed-models via lme4::lmer run without sandbox interference.
# - Uses local library path ./.Rlib if present (repo ships packages there).
# - Simulates a small dataset and fits y ~ x + (1 | g).
# - Writes minimal outputs to artifacts/test_lmer_access/.

suppressWarnings(suppressMessages({
  args <- commandArgs(trailingOnly = TRUE)
}))

parse_args <- function(args) {
  out <- list()
  for (a in args) if (grepl('^--', a)) {
    k <- sub('^--', '', a)
    k1 <- sub('=.*$', '', k)
    v <- sub('^[^=]*=', '', k)
    out[[k1]] <- v
  }
  out
}

opts <- parse_args(args)
`%||%` <- function(a, b) if (!is.null(a) && nzchar(a)) a else b

out_dir <- opts[["out_dir"]] %||% "artifacts/test_lmer_access"
ensure_dir <- function(p) dir.create(p, recursive = TRUE, showWarnings = FALSE)
ensure_dir(out_dir)

# Prefer local repo library first if available
repo_lib <- file.path(getwd(), ".Rlib")
if (dir.exists(repo_lib)) {
  .libPaths(c(repo_lib, .libPaths()))
}

have_lme4 <- requireNamespace("lme4", quietly = TRUE)
if (!have_lme4) {
  msg <- "lme4 not installed or not found in library paths; skipping test."
  writeLines(msg)
  writeLines(paste0(".libPaths=", paste(.libPaths(), collapse = ";")))
  quit(status = 2, save = "no")
}

set.seed(42)
n_group <- 10L
n_per   <- 30L
n       <- n_group * n_per
g       <- factor(rep(seq_len(n_group), each = n_per))
x       <- rnorm(n)
u_grp   <- rnorm(n_group, sd = 1.0)
y       <- 2 + 0.5 * x + u_grp[as.integer(g)] + rnorm(n, sd = 1.0)

# Fit mixed model
fit <- lme4::lmer(y ~ x + (1 | g))

# Extract minimal diagnostics
fixef <- lme4::fixef(fit)
vc    <- as.data.frame(lme4::VarCorr(fit))
sigma <- sigma(fit)

# Write outputs
summary_txt <- capture.output(summary(fit))
writeLines(summary_txt, file.path(out_dir, "lmer_summary.txt"))

coef_df <- data.frame(term = names(fixef), estimate = as.numeric(fixef), row.names = NULL)
utils::write.csv(coef_df, file.path(out_dir, "fixed_effects.csv"), row.names = FALSE)

utils::write.csv(vc, file.path(out_dir, "var_components.csv"), row.names = FALSE)

# Print concise success line for CLI checks
cat(sprintf(
  "OK: lmer ran. beta0=%.3f beta1=%.3f var_u=%.3f sigma=%.3f\n",
  fixef[["(Intercept)"]], fixef[["x"]], vc$vcov[vc$grp == "g" & vc$var1 == "(Intercept)"], sigma
))

invisible(TRUE)
