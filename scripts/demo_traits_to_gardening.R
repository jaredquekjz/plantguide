#!/usr/bin/env Rscript

# Demo: Transform a sample group of plant traits to gardening requirements
# Uses the real Stage 6 pipeline (calc_gardening_requirements.R).
#
# Usage: Rscript scripts/demo_traits_to_gardening.R [--n 5] [--require "L=high,M=med"] [--thr 0.6] [--presets <csv>] [--topn 3] [--group_col Myco_Group_Final] [--group_ref_csv <csv>] [--group_ref_id_col wfo_accepted_name] [--group_ref_group_col Myco_Group_Final]
#
# Steps printed:
#  1) Initial traits (from results/mag_input_no_eive.csv)
#  2) Intermediate predictions and bins (from results/mag_predictions_no_eive.csv + Stage 6)
#  3) Final gardening requirements per plant (axis recommendations)

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
})

args <- commandArgs(trailingOnly = TRUE)
n_sample <- 5L
req_str <- NULL
presets_csv <- NULL
topn <- 3L
group_col <- NULL
group_ref_csv <- NULL
group_ref_id_col <- NULL
group_ref_group_col <- NULL
thr <- 0.6

# Simple arg parser
i <- 1L
while (i <= length(args)) {
  key <- args[[i]]
  val <- if (i+1 <= length(args)) args[[i+1]] else NULL
  if (key == "--n" && !is.null(val)) {
    n_sample <- suppressWarnings(as.integer(val)); if (is.na(n_sample) || n_sample <= 0) n_sample <- 5L; i <- i + 2L; next
  }
  if (key == "--require" && !is.null(val)) { req_str <- val; i <- i + 2L; next }
  if (key %in% c("--thr","--threshold","--joint_min_prob") && !is.null(val)) {
    thr <- suppressWarnings(as.numeric(val)); if (!is.finite(thr)) thr <- 0.6; i <- i + 2L; next
  }
  if (key == "--presets" && !is.null(val)) { presets_csv <- val; i <- i + 2L; next }
  if (key == "--topn" && !is.null(val)) { topn <- suppressWarnings(as.integer(val)); if (is.na(topn) || topn <= 0) topn <- 3L; i <- i + 2L; next }
  if (key == "--group_col" && !is.null(val)) { group_col <- val; i <- i + 2L; next }
  if (key == "--group_ref_csv" && !is.null(val)) { group_ref_csv <- val; i <- i + 2L; next }
  if (key == "--group_ref_id_col" && !is.null(val)) { group_ref_id_col <- val; i <- i + 2L; next }
  if (key == "--group_ref_group_col" && !is.null(val)) { group_ref_group_col <- val; i <- i + 2L; next }
  i <- i + 1L
}

traits_csv <- "results/mag_input_no_eive.csv"
preds_csv  <- "results/mag_predictions_no_eive.csv"
stage6_calc <- "src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R"
joint_calc  <- "src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R"

if (!file.exists(traits_csv)) stop(sprintf("Traits CSV not found: %s", traits_csv))
if (!file.exists(preds_csv))  stop(sprintf("Predictions CSV not found: %s", preds_csv))
if (!file.exists(stage6_calc)) stop(sprintf("Stage 6 script not found: %s", stage6_calc))
if (!file.exists(joint_calc)) warning(sprintf("Joint suitability script not found: %s (top-N presets will be skipped)", joint_calc))

# If presets not provided, choose a sensible default if available
if (is.null(presets_csv) || !nzchar(presets_csv)) {
  cand1 <- file.path("results","gardening","garden_presets_no_R.csv")
  cand2 <- file.path("results","gardening","garden_joint_presets_defaults.csv")
  if (file.exists(cand1)) presets_csv <- cand1 else if (file.exists(cand2)) presets_csv <- cand2
}

# If group defaults requested (group_col provided but refs omitted), use Myco defaults
if (!is.null(group_col) && nzchar(group_col)) {
  if (is.null(group_ref_csv) || !nzchar(group_ref_csv)) group_ref_csv <- "artifacts/model_data_complete_case_with_myco.csv"
  if (is.null(group_ref_id_col) || !nzchar(group_ref_id_col)) group_ref_id_col <- "wfo_accepted_name"
  if (is.null(group_ref_group_col) || !nzchar(group_ref_group_col)) group_ref_group_col <- group_col
}

# 1) Load inputs and choose a small sample
traits <- suppressMessages(readr::read_csv(traits_csv, show_col_types = FALSE))
preds_full <- suppressMessages(readr::read_csv(preds_csv, show_col_types = FALSE))

# Choose first n_sample species present in both tables
key <- intersect(traits$species, preds_full$species)
if (length(key) == 0) stop("No overlapping species between traits and predictions.")
sel <- head(key, n_sample)
traits_sel <- traits %>% filter(species %in% sel)
preds_sel <- preds_full %>% filter(species %in% sel)

cat("\n=== Initial Traits (sample) ===\n")
print(traits_sel %>% select(species, LMA, Nmass, LeafArea, PlantHeight, DiasporeMass, SSD))

# 2) Run Stage 6 to compute bins/confidence/recommendations
dir.create("results/gardening", recursive = TRUE, showWarnings = FALSE)
tmp_preds <- tempfile("demo_preds_", tmpdir = "results/gardening", fileext = ".csv")
tmp_out   <- tempfile("demo_recs_",  tmpdir = "results/gardening", fileext = ".csv")
readr::write_csv(preds_sel, tmp_preds)

cat("\n=== Running Stage 6: calc_gardening_requirements.R ===\n")
cmd <- c(stage6_calc,
         "--predictions_csv", tmp_preds,
         "--output_csv", tmp_out,
         "--bins", "0:3.5,3.5:6.5,6.5:10")
if (!is.null(req_str) && nzchar(req_str)) {
  cmd <- c(cmd, "--joint_requirement", req_str, "--joint_min_prob", as.character(thr))
}
if (!is.null(presets_csv) && nzchar(presets_csv) && file.exists(presets_csv)) {
  cmd <- c(cmd, "--joint_presets_csv", presets_csv)
}
if (!is.null(group_col) && nzchar(group_col)) {
  cmd <- c(cmd, "--group_col", group_col)
  if (!is.null(group_ref_csv) && nzchar(group_ref_csv)) cmd <- c(cmd, "--group_ref_csv", group_ref_csv)
  if (!is.null(group_ref_id_col) && nzchar(group_ref_id_col)) cmd <- c(cmd, "--group_ref_id_col", group_ref_id_col)
  if (!is.null(group_ref_group_col) && nzchar(group_ref_group_col)) cmd <- c(cmd, "--group_ref_group_col", group_ref_group_col)
}
status <- system2("Rscript", args = cmd, stdout = TRUE, stderr = TRUE)
cat(paste(status, collapse = "\n"), "\n")
if (!file.exists(tmp_out)) stop("Stage 6 did not produce output.")

recs <- suppressMessages(readr::read_csv(tmp_out, show_col_types = FALSE))

cat("\n=== Intermediate: Predictions and Bins ===\n")
print(recs %>% select(species, L_pred, T_pred, M_pred, R_pred, N_pred,
                      L_bin, T_bin, M_bin, R_bin, N_bin,
                      L_confidence, T_confidence, M_confidence, R_confidence, N_confidence))

# 2c) Best preset scenario per plant (if annotated)
if (all(c("best_scenario_label","best_scenario_prob","best_scenario_ok") %in% names(recs))) {
  cat("\n=== Best Preset Scenario (per plant) ===\n")
  print(recs %>% select(species, best_scenario_label, best_scenario_prob, best_scenario_ok))
}

# Optional: compute and print top-N presets per plant using joint_suitability_with_copulas.R
if (!is.null(presets_csv) && nzchar(presets_csv) && file.exists(presets_csv) && file.exists(joint_calc)) {
  tmp_sum <- tempfile("demo_summary_", tmpdir = "results/gardening", fileext = ".csv")
  cat("\n=== Computing per-scenario probabilities (top-N presets) ===\n")
  cmd2 <- c(joint_calc,
            "--predictions_csv", tmp_preds,
            "--presets_csv", presets_csv,
            "--nsim", "20000",
            "--summary_csv", tmp_sum)
  if (!is.null(group_col) && nzchar(group_col)) {
    cmd2 <- c(cmd2, "--group_col", group_col)
    if (!is.null(group_ref_csv) && nzchar(group_ref_csv)) cmd2 <- c(cmd2, "--group_ref_csv", group_ref_csv)
    if (!is.null(group_ref_id_col) && nzchar(group_ref_id_col)) cmd2 <- c(cmd2, "--group_ref_id_col", group_ref_id_col)
    if (!is.null(group_ref_group_col) && nzchar(group_ref_group_col)) cmd2 <- c(cmd2, "--group_ref_group_col", group_ref_group_col)
  }
  status2 <- system2("Rscript", args = cmd2, stdout = TRUE, stderr = TRUE)
  cat(paste(status2, collapse = "\n"), "\n")
  if (file.exists(tmp_sum)) {
    sumdf <- suppressMessages(readr::read_csv(tmp_sum, show_col_types = FALSE))
    if (all(c("species","label","joint_prob") %in% names(sumdf))) {
      cat(sprintf("\n=== Top %d Presets (per plant) ===\n", topn))
      for (sp in sel) {
        rows <- sumdf %>% filter(.data$species == sp) %>% arrange(desc(.data$joint_prob)) %>% head(topn)
        cat(sprintf("\n- %s\n", sp))
        for (j in seq_len(nrow(rows))) {
          lab <- rows$label[j]; p <- rows$joint_prob[j]; thrj <- if ("threshold" %in% names(rows)) rows$threshold[j] else thr; passj <- if ("pass" %in% names(rows)) rows$pass[j] else !is.na(p) && p >= thrj
          status <- if (isTRUE(passj)) "PASS" else "FAIL"
          cat(sprintf("  %d) %s — p=%.3f @ thr=%.2f → %s\n", j, lab, p, thrj, status))
        }
      }
    }
  }
}

# 2b) Joint requirement summary (when requested)
if (!is.null(req_str) && nzchar(req_str) && all(c("joint_requirement","joint_prob","joint_ok") %in% names(recs))) {
  cat("\n=== Joint Requirement Gate ===\n")
  cat(sprintf("Requirement: %s\n", unique(recs$joint_requirement)[1]))
  cat(sprintf("Threshold:  %.2f\n", thr))
  pass_n <- sum(recs$joint_ok, na.rm = TRUE)
  cat(sprintf("Pass: %d/%d species\n", pass_n, nrow(recs)))
}

# 3) Final: Axis recommendations per plant (concise)
cat("\n=== Final Gardening Requirements (per plant) ===\n")
for (i in seq_len(nrow(recs))) {
  row <- recs[i,]
  cat(sprintf("\n- %s\n", row[["species"]]))
  cat(sprintf("  • Light (L=%.2f): %s\n", as.numeric(row[["L_pred"]]), row[["L_recommendation"]]))
  cat(sprintf("  • Temperature (T=%.2f): %s\n", as.numeric(row[["T_pred"]]), row[["T_recommendation"]]))
  cat(sprintf("  • Moisture (M=%.2f): %s\n", as.numeric(row[["M_pred"]]), row[["M_recommendation"]]))
  cat(sprintf("  • Soil pH (R=%.2f): %s\n", as.numeric(row[["R_pred"]]), row[["R_recommendation"]]))
  cat(sprintf("  • Fertility (N=%.2f): %s\n", as.numeric(row[["N_pred"]]), row[["N_recommendation"]]))
  if (!is.null(req_str) && nzchar(req_str) && all(c("joint_prob","joint_ok") %in% names(row))) {
    jp <- as.numeric(row[["joint_prob"]])
    ok <- isTRUE(as.logical(row[["joint_ok"]]))
    status <- if (ok) "PASS" else "FAIL"
    cat(sprintf("  • Joint suitability: p=%.3f @ thr=%.2f → %s\n", jp, thr, status))
  }
  if (all(c("best_scenario_label","best_scenario_prob","best_scenario_ok") %in% names(row))) {
    bl <- as.character(row[["best_scenario_label"]])
    bp <- as.numeric(row[["best_scenario_prob"]])
    bok <- isTRUE(as.logical(row[["best_scenario_ok"]]))
    bstatus <- if (bok) "PASS" else "FAIL"
    cat(sprintf("  • Best preset: %s (p=%.3f) → %s\n", bl, bp, bstatus))
  }
}

cat("\nDemo complete.\n")
