#!/usr/bin/env Rscript
Suppress <- function(expr) suppressMessages(suppressWarnings(expr))
Suppress({library(jsonlite); library(ggplot2)})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
  stop("Usage: Rscript scripts/plot_L_R2_run7_vs_7c.R RUN7_L_metrics.json RUN7C_L_metrics.json OUT_PNG")
}
in7  <- args[[1]]
in7c <- args[[2]]
out  <- args[[3]]
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)

j7  <- fromJSON(in7)
j7c <- fromJSON(in7c)
r2  <- data.frame(
  version = factor(c("Run 7", "Run 7c"), levels = c("Run 7","Run 7c")),
  R2 = c(j7$metrics$aggregate$R2_mean, j7c$metrics$aggregate$R2_mean),
  SD = c(j7$metrics$aggregate$R2_sd,   j7c$metrics$aggregate$R2_sd)
)

p <- ggplot(r2, aes(x=version, y=R2, fill=version)) +
  geom_col(width=0.55) +
  geom_errorbar(aes(ymin=R2-SD, ymax=R2+SD), width=0.15) +
  scale_y_continuous(limits=c(0, 0.35), expand = expansion(mult = c(0, 0.02))) +
  scale_fill_manual(values=c("#6baed6", "#31a354")) +
  labs(title="Light (L) R² — Run 7 vs 7c", x=NULL, y="CV R² (mean ± SD)") +
  theme_minimal(base_size = 11) + theme(legend.position = "none")
ggsave(out, plot = p, width = 4.5, height = 3.0, dpi = 160)
cat(sprintf("Wrote %s\n", out))

