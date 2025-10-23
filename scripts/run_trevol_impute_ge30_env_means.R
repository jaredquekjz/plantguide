#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(TrEvol)
  library(readr)
  library(dplyr)
  library(ape)
})

args <- commandArgs(trailingOnly = TRUE)
iterations <- if (length(args) >= 1) as.integer(args[[1]]) else 5L
clusters   <- if (length(args) >= 2) as.integer(args[[2]]) else 6L

message(sprintf("[TrEvol] Starting imputeTraits (iterations = %d, clusters = %d)", iterations, clusters))

traits_path <- "model_data/inputs/trait_imputation_input_modelling_ge30_20251022.csv"
env_path    <- "model_data/inputs/env_features_ge30_20251022_means.csv"
tree_path   <- "data/phylogeny/eive_try_tree_20251021.nwk"
output_dir  <- "model_data/outputs/trevol"

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

traits <- read_csv(traits_path, show_col_types = FALSE)
env    <- read_csv(env_path, show_col_types = FALSE)

drop_cols <- intersect(c("wfo_taxon_id", "Genus", "Family", "species"), names(env))
if (length(drop_cols) > 0) {
  message("[TrEvol] Dropping non-numeric environment columns: ", paste(drop_cols, collapse = ", "))
  env <- env %>% select(-all_of(drop_cols))
}

na_env_cols <- names(env)[vapply(env, function(col) any(is.na(col)), logical(1))]
if (length(na_env_cols) > 0) {
  message("[TrEvol] Dropping environment columns with NA: ", paste(na_env_cols, collapse = ", "))
  env <- env %>% select(-all_of(na_env_cols))
}

if (!"wfo_accepted_name" %in% names(env)) {
  stop("Environment table is missing 'wfo_accepted_name'")
}

predictors_original <- setdiff(names(env), "wfo_accepted_name")
if (length(predictors_original) == 0) {
  stop("No environment predictors remain after filtering; aborting.")
}

merged <- traits %>%
  inner_join(env, by = "wfo_accepted_name") %>%
  mutate(animal = gsub(" ", "_", wfo_accepted_name))

if (anyDuplicated(merged$animal) > 0) {
  dups <- merged$wfo_accepted_name[duplicated(merged$animal)]
  stop("Duplicated species labels after underscore conversion: ",
       paste(head(dups, 10), collapse = ", "))
}

merged_df <- as.data.frame(merged)

original_names <- names(merged_df)
sanitised_names <- make.names(original_names, unique = TRUE)
name_map <- setNames(sanitised_names, original_names)
reverse_map <- setNames(original_names, sanitised_names)
names(merged_df) <- sanitised_names

vars_original <- c("Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)",
                   "Plant height (m)", "Diaspore mass (mg)", "LDMC")

missing_vars <- setdiff(vars_original, names(name_map))
if (length(missing_vars) > 0) {
  stop("Trait columns missing from dataset: ", paste(missing_vars, collapse = ", "))
}

vars_safe <- unname(name_map[vars_original])
predictors_safe <- unname(name_map[predictors_original])
predictors_safe <- predictors_safe[!is.na(predictors_safe)]

if (length(predictors_safe) == 0) {
  stop("No predictors available after sanitising column names.")
}

phy <- read.tree(tree_path)
phy$node.label <- NULL

missing_species <- setdiff(merged_df$animal, phy$tip.label)
if (length(missing_species) > 0) {
  stop("Phylogeny missing species: ", paste(head(missing_species, 10), collapse = ", "))
}

phy <- keep.tip(phy, merged_df$animal)

message(sprintf("[TrEvol] Dataset rows: %d, predictors: %d", nrow(merged_df), length(predictors_safe)))

impute_res <- imputeTraits(
  variables_to_impute = vars_safe,
  dataset = merged_df,
  terminal_taxa = "animal",
  phylogeny = phy,
  predictors = predictors_safe,
  proportion_NAs = 0,
  number_iterations = iterations,
  number_clusters = clusters
)

round3 <- impute_res[["round3"]]
if (is.null(round3)) {
  stop("TrEvol did not return round3 results.")
}

rename_back <- function(df, mapping) {
  if (is.null(df)) return(NULL)
  cols <- names(df)
  names(df) <- ifelse(cols %in% names(mapping), mapping[cols], cols)
  df
}

ximp_out   <- rename_back(round3$ximp, reverse_map)
ximp_sd_out <- rename_back(round3$ximp_sd, reverse_map)
perf_out   <- round3$predictivePerformance
if (!is.null(perf_out)) {
  perf_out$Variable <- ifelse(perf_out$Variable %in% names(reverse_map),
                              reverse_map[perf_out$Variable],
                              perf_out$Variable)
}

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")

out_base <- file.path(output_dir, sprintf("trait_imputation_trevol_ge30_20251022_env_means_round3_%s", timestamp))
write_csv(ximp_out, paste0(out_base, ".csv"))

if (!is.null(ximp_sd_out)) {
  write_csv(ximp_sd_out, paste0(out_base, "_sd.csv"))
}
if (!is.null(perf_out)) {
  write_csv(perf_out, file.path(output_dir, sprintf("trevol_ge30_env_means_round3_performance_%s.csv", timestamp)))
}

message("[TrEvol] Imputation completed successfully.")
