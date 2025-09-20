#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(tidyverse)
})

in_path <- "artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv"
out_path <- "artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2_pcs.csv"

cat("[pc-data] Loading", in_path, "...\n")
if (!file.exists(in_path)) stop("Input file not found: ", in_path)

df <- readr::read_csv(in_path, show_col_types = FALSE)
cat(sprintf("[pc-data] Rows: %d, Cols: %d\n", nrow(df), ncol(df)))

trait_cols <- c("logLA", "LES_core", "logSM", "LMA", "SIZE", "logH", "logSSD", "LDMC")
missing <- setdiff(trait_cols, names(df))
if (length(missing)) stop("Missing trait columns: ", paste(missing, collapse = ", "))

trait_mat <- df %>% select(all_of(trait_cols)) %>% mutate(across(everything(), as.numeric))

if (anyNA(trait_mat)) {
  trait_mat <- trait_mat %>% mutate(across(everything(), ~ replace_na(., mean(., na.rm = TRUE))))
  cat("[pc-data] Filled missing trait values with column means before PCA\n")
}

pca <- prcomp(trait_mat, center = TRUE, scale. = TRUE)
cumvar <- summary(pca)$importance[3,]
keep <- which(cumvar >= 0.90)[1]
if (is.na(keep)) keep <- min(4, ncol(pca$x))

scores <- as_tibble(pca$x[, seq_len(keep), drop = FALSE])
names(scores) <- paste0("pc_trait_", seq_len(keep))
cat(sprintf("[pc-data] Retaining %d PCs (%.1f%% variance)\n", keep, cumvar[keep] * 100))

df_out <- bind_cols(df %>% select(-all_of(trait_cols)), scores)

readr::write_csv(df_out, out_path)
cat("[pc-data] Wrote", out_path, "with", ncol(df_out), "columns\n")
