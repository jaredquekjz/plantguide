#!/usr/bin/env Rscript

# Plot SEM vs XGBoost vs Random Forest (ranger) R² by axis.
# Inputs: results/summaries/model_benchmarks_summary.csv
# Output: results/summaries/sem_vs_blackbox_r2.png

suppressWarnings({
  suppressMessages({
    have_readr  <- requireNamespace("readr",  quietly = TRUE)
    have_ggplot <- requireNamespace("ggplot2", quietly = TRUE)
    have_dplyr  <- requireNamespace("dplyr",  quietly = TRUE)
    have_tidyr  <- requireNamespace("tidyr",  quietly = TRUE)
  })
})

if (!have_ggplot) {
  stop("ggplot2 not installed. Install.packages('ggplot2')")
}

args <- commandArgs(trailingOnly = TRUE)
bench_csv <- "results/summaries/model_benchmarks_summary.csv"
out_png   <- "results/summaries/sem_vs_blackbox_r2.png"
delta_png <- "results/summaries/sem_vs_blackbox_delta.png"
for (a in args) {
  if (grepl("^--bench_csv=", a)) bench_csv <- sub("^--bench_csv=", "", a)
  if (grepl("^--out_png=", a))   out_png   <- sub("^--out_png=",   "", a)
  if (grepl("^--delta_png=", a)) delta_png <- sub("^--delta_png=", "", a)
}

if (!file.exists(bench_csv)) stop(sprintf("Benchmark CSV not found: %s", bench_csv))

read_csv_smart <- function(path) {
  if (have_readr) return(readr::read_csv(path, show_col_types = FALSE, progress = FALSE))
  utils::read.csv(path, check.names = FALSE)
}

bench <- read_csv_smart(bench_csv)

# Ensure expected columns
need <- c("axis","model","r2_mean","r2_sd")
miss <- setdiff(need, names(bench))
if (length(miss)) stop(sprintf("Missing columns in benchmarks CSV: %s", paste(miss, collapse=", "))) 

# Hardcode SEM Run 7 means ± SD from README
sem_means <- c(L=0.237, T=0.234, R=0.155, M=0.415, N=0.424)
sem_sds   <- c(L=0.060, T=0.072, R=0.071, M=0.072, N=0.071)
axes_all  <- c("L","T","M","R","N")

sem_df <- data.frame(
  axis = axes_all,
  model = rep("sem", length(axes_all)),
  r2_mean = as.numeric(sem_means[axes_all]),
  r2_sd   = as.numeric(sem_sds[axes_all]),
  stringsAsFactors = FALSE
)

# Take best-of-best rows per axis/model from the CSV (already consolidated)
bench$model <- tolower(as.character(bench$model))
bench <- bench[bench$model %in% c("xgb","ranger"), c("axis","model","r2_mean","r2_sd")]

plot_df <- rbind(sem_df, bench)
plot_df$axis <- factor(plot_df$axis, levels = axes_all)
plot_df$model_label <- factor(plot_df$model, levels = c("sem","xgb","ranger"),
                              labels = c("SEM (Run 7)", "XGBoost", "Random Forest"))

library(ggplot2)
gg <- ggplot(plot_df, aes(x = axis, y = r2_mean, color = model_label)) +
  geom_point(position = position_dodge(width = 0.5), size = 2.8) +
  geom_errorbar(aes(ymin = pmax(0, r2_mean - r2_sd), ymax = pmin(1, r2_mean + r2_sd)),
                width = 0.15, position = position_dodge(width = 0.5), alpha = 0.6) +
  scale_y_continuous(limits = c(0, 0.5), breaks = seq(0, 0.5, by = 0.1)) +
  labs(title = "Out-of-Fold R² by Axis — SEM vs XGBoost vs Random Forest",
       x = "Axis", y = "R² (mean ± SD)", color = "Model") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom",
        panel.grid.minor = element_blank())

dir.create(dirname(out_png), recursive = TRUE, showWarnings = FALSE)
ggsave(out_png, gg, width = 8, height = 4.2, dpi = 160)
cat(sprintf("Wrote plot: %s\n", out_png))

# Delta plot: model − SEM by axis (for XGB and RF)
bb <- bench
bb_sem <- sem_df
names(bb_sem)[names(bb_sem)=="model"] <- "model_sem"
bb <- merge(bb, bb_sem[, c("axis","r2_mean")], by = "axis", all.x = TRUE, suffixes = c("", "_sem"))
bb$delta <- bb$r2_mean - bb$r2_mean_sem
bb$model_label <- factor(bb$model, levels = c("xgb","ranger"), labels = c("XGBoost − SEM", "Random Forest − SEM"))

ggd <- ggplot(bb, aes(x = factor(axis, levels = axes_all), y = delta, fill = model_label)) +
  geom_col(position = position_dodge(width = 0.6), width = 0.5) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "#666666") +
  scale_y_continuous(limits = c(-0.25, 0.15), breaks = seq(-0.25, 0.15, by = 0.05)) +
  labs(title = "R² Delta vs SEM (Out-of-Fold)", x = "Axis", y = "ΔR² (Model − SEM)", fill = "Delta") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom",
        panel.grid.minor = element_blank())

ggsave(delta_png, ggd, width = 8, height = 4.0, dpi = 160)
cat(sprintf("Wrote delta plot: %s\n", delta_png))
