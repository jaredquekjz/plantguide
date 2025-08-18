#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(optparse)
  library(readr)
  library(dplyr)
  library(stringr)
})

fmt_p <- function(p) {
  if (is.na(p)) return("NA")
  if (p < 1e-3) return(formatC(p, format = "e", digits = 2))
  sprintf("%.3f", p)
}

bold_if <- function(txt, p, alpha) {
  if (!is.na(p) && p < alpha) paste0("**", txt, "**") else txt
}

read_eqtest <- function(dir, target) {
  path <- file.path(dir, sprintf("sem_piecewise_%s_claim_logSSD_eqtest.csv", target))
  df <- suppressMessages(readr::read_csv(path, show_col_types = FALSE))
  p <- df$p_overall[1]
  as.numeric(p)
}

read_pergroup <- function(dir, target) {
  path <- file.path(dir, sprintf("sem_piecewise_%s_claim_logSSD_pergroup_pvals.csv", target))
  df <- suppressMessages(readr::read_csv(path, show_col_types = FALSE))
  df %>% mutate(group = as.character(group), p_logSSD = as.numeric(p_logSSD))
}

order_groups <- function(df, groups_type) {
  if (groups_type == "woodiness") {
    lev <- c("non-woody", "woody", "semi-woody")
  } else if (groups_type == "myco") {
    lev <- c("Facultative_AM_NM", "Low_Confidence", "Mixed_Uncertain", "Pure_AM", "Pure_EM", "Pure_NM")
  } else {
    lev <- unique(df$group)
  }
  df$group <- factor(df$group, levels = lev)
  arrange(df, group)
}

summarize_groups <- function(per_target_groups, alpha) {
  # per_target_groups: named list target -> data.frame(group, p_logSSD)
  groups <- sort(unique(unlist(lapply(per_target_groups, function(x) as.character(x$group)))))
  out <- list()
  for (g in groups) {
    sig_axes <- names(Filter(function(df) any(df$group == g & df$p_logSSD < alpha, na.rm = TRUE), per_target_groups))
    out[[g]] <- if (length(sig_axes) > 0) paste(sig_axes, collapse = "/") else "none"
  }
  out
}

make_parser <- function() {
  option_list <- list(
    make_option("--groups_type", type = "character", default = "woodiness", help = "Grouping type: woodiness or myco"),
    make_option("--dir_all", type = "character", default = NA, help = "Directory for all targets (if same)"),
    make_option("--dir_LTR", type = "character", default = NA, help = "Directory for L/T/R targets"),
    make_option("--dir_MN", type = "character", default = NA, help = "Directory for M/N targets"),
    make_option("--targets", type = "character", default = "L,T,M,N,R", help = "Comma-separated targets, e.g., L,T,M,N,R"),
    make_option("--alpha", type = "double", default = 0.05, help = "Significance threshold for bolding")
  )
  OptionParser(option_list = option_list)
}

choose_dir <- function(T, dir_all, dir_LTR, dir_MN) {
  if (!is.na(dir_all)) return(dir_all)
  if (!is.na(dir_MN) && T %in% c("M", "N")) return(dir_MN)
  if (!is.na(dir_LTR) && T %in% c("L", "T", "R")) return(dir_LTR)
  stop(sprintf("No directory provided for target %s", T))
}

main <- function() {
  parser <- make_parser()
  args <- parse_args(parser)

  targets <- strsplit(args$targets, ",")[[1]] %>% trimws()
  alpha <- args$alpha
  dir_all <- args$dir_all; dir_LTR <- args$dir_LTR; dir_MN <- args$dir_MN

  # Collect values
  p_overall <- list()
  per_groups <- list()

  for (T in targets) {
    dirT <- choose_dir(T, dir_all, dir_LTR, dir_MN)
    p_overall[[T]] <- read_eqtest(dirT, T)
    pg <- read_pergroup(dirT, T) %>% order_groups(args$groups_type)
    per_groups[[T]] <- pg
  }

  # Output
  cat("Before (heterogeneity; equality-of-slope p_overall)\n", sep = "")
  for (T in targets) {
    ptxt <- fmt_p(p_overall[[T]])
    ptxt <- bold_if(ptxt, p_overall[[T]], alpha)
    sig_note <- if (!is.na(p_overall[[T]]) && p_overall[[T]] >= alpha) " (ns)" else ""
    cat(sprintf("- %s: %s%s\n", T, ptxt, sig_note))
  }
  cat("\nAfter (per-group p_logSSD)\n", sep = "")
  for (T in targets) {
    df <- per_groups[[T]]
    parts <- c()
    for (i in seq_len(nrow(df))) {
      ptxt <- fmt_p(df$p_logSSD[i])
      ptxt <- bold_if(ptxt, df$p_logSSD[i], alpha)
      parts <- c(parts, sprintf("%s %s", as.character(df$group[i]), ptxt))
    }
    cat(sprintf("- %s: %s\n", T, paste(parts, collapse = "; ")))    
  }

  # Interpretation summary
  justified <- names(Filter(function(x) !is.na(x) && x < alpha, p_overall))
  not_req <- setdiff(targets, justified)
  grp_summary <- summarize_groups(per_groups, alpha)
  cat("\n- Interpretation: Split justified for ", if (length(justified)>0) paste(justified, collapse = "/") else "none",
      if (length(not_req)>0) paste0("; ", paste(not_req, collapse = "/"), " not required") else "",
      ".\n", sep = "")
  for (g in names(grp_summary)) {
    cat(sprintf("  - %s: significant in %s\n", g, grp_summary[[g]]))
  }
}

if (identical(environment(), globalenv())) {
  tryCatch(main(), error = function(e) {
    message("Error: ", e$message)
    quit(status = 1)
  })
}

