#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(stringr)
  library(tidyr)
  library(ape)
  library(arrow)
})

args <- commandArgs(trailingOnly = TRUE)
get_opt <- function(name, default) {
  pattern <- paste0("^--", name, "=")
  match <- grep(pattern, args, value = TRUE)
  if (length(match) == 0) {
    return(default)
  }
  sub(pattern, "", match[1])
}

normalise_name <- function(x) {
  x %>%
    tolower() %>%
    str_replace_all("[[:space:]]+", " ") %>%
    str_trim() %>%
    str_replace_all(" ", "_") %>%
    str_replace_all("[^a-z0-9_]+", "_")
}

main <- function() {
  traits_csv <- get_opt("traits_csv", "model_data/inputs/traits_model_ready_20251022_shortlist.csv")
  tree_newick <- get_opt("tree_newick", "data/stage1/phlogeny/mixgb_tree_11676_species_20251027.nwk")
  output_base <- get_opt("output_base", "model_data/outputs/p_phylo_proxy_shortlist_20251023")

  message("[info] Loading roster and tree...")
  roster <- read_csv(traits_csv, show_col_types = FALSE)
  if (!"wfo_taxon_id" %in% names(roster)) {
    stop("Traits CSV missing wfo_taxon_id column")
  }
  roster <- roster %>% mutate(
    wfo_taxon_id = as.character(wfo_taxon_id),
    scientific_name = ifelse("wfo_scientific_name" %in% names(roster), wfo_scientific_name,
                             ifelse("canonical_name" %in% names(roster), canonical_name, NA_character_)),
    tip_label_norm = normalise_name(scientific_name)
  )

  tax_map <- read_parquet("data/stage1/stage1_union_canonical.parquet") %>%
    select(wfo_taxon_id = accepted_wfo_id, genus = try_genus, family = try_family)

  roster <- roster %>%
    left_join(tax_map, by = "wfo_taxon_id")

  tree <- read.tree(tree_newick)
  if (inherits(tree, "multiPhylo")) {
    tree <- tree[[1L]]
  }
  tree <- compute.brlen(tree)

  tip_info <- tibble(
    tip_label_raw = tree$tip.label,
    wfo_taxon_id = ifelse(grepl("\\|", tree$tip.label), sub("\\|.*", "", tree$tip.label), NA_character_),
    tip_label_norm = normalise_name(ifelse(grepl("\\|", tree$tip.label), sub("^[^|]+\\|", "", tree$tip.label), tree$tip.label))
  )

  tip_info <- tip_info %>%
    left_join(roster %>% select(wfo_taxon_id, genus, family, tip_label_norm), by = "wfo_taxon_id")

  missing_idx <- which(is.na(tip_info$genus) | tip_info$genus == "")
  if (length(missing_idx)) {
    alt_idx <- match(tip_info$tip_label_norm[missing_idx], roster$tip_label_norm)
    tip_info$genus[missing_idx] <- ifelse(is.na(tip_info$genus[missing_idx]), roster$genus[alt_idx], tip_info$genus[missing_idx])
    tip_info$family[missing_idx] <- ifelse(is.na(tip_info$family[missing_idx]), roster$family[alt_idx], tip_info$family[missing_idx])
    tip_info$wfo_taxon_id[missing_idx] <- ifelse(is.na(tip_info$wfo_taxon_id[missing_idx]), roster$wfo_taxon_id[alt_idx], tip_info$wfo_taxon_id[missing_idx])
  }

  depth_vals <- node.depth.edgelength(tree)[seq_len(length(tree$tip.label))]
  names(depth_vals) <- tree$tip.label
  terminal_edge <- tree$edge.length[match(seq_len(length(tree$tip.label)), tree$edge[, 2])]

  tip_features <- tip_info %>% mutate(
    phylo_depth = depth_vals[tip_label_raw],
    phylo_terminal = terminal_edge
  )

  feature_tbl <- roster %>% select(wfo_taxon_id, genus, family) %>%
    left_join(tip_features %>% select(wfo_taxon_id, phylo_depth, phylo_terminal), by = "wfo_taxon_id")

  numeric_cols <- c("phylo_depth", "phylo_terminal")
  feature_tbl <- feature_tbl %>% mutate(fallback_level = ifelse(!is.na(phylo_depth), "direct", NA_character_))

  feature_tbl <- feature_tbl %>%
    group_by(genus) %>%
    mutate(has_genus_data = any(!is.na(phylo_depth))) %>%
    mutate(across(all_of(numeric_cols), ~ ifelse(is.na(.x) & has_genus_data, mean(.x, na.rm = TRUE), .x))) %>%
    mutate(fallback_level = ifelse(is.na(fallback_level) & has_genus_data, "genus", fallback_level)) %>%
    ungroup() %>%
    select(-has_genus_data)

  feature_tbl <- feature_tbl %>%
    group_by(family) %>%
    mutate(has_family_data = any(!is.na(phylo_depth))) %>%
    mutate(across(all_of(numeric_cols), ~ ifelse(is.na(.x) & has_family_data, mean(.x, na.rm = TRUE), .x))) %>%
    mutate(fallback_level = ifelse(is.na(fallback_level) & has_family_data, "family", fallback_level)) %>%
    ungroup() %>%
    select(-has_family_data)

  global_means <- feature_tbl %>% summarise(across(all_of(numeric_cols), ~ mean(.x, na.rm = TRUE)))
  for (col in numeric_cols) {
    feature_tbl[[col]][is.na(feature_tbl[[col]])] <- global_means[[col]]
  }
  feature_tbl <- feature_tbl %>% mutate(fallback_level = ifelse(is.na(fallback_level), "global", fallback_level))

  feature_tbl <- feature_tbl %>% mutate(
    genus_code = as.integer(factor(genus)),
    family_code = as.integer(factor(family)),
    phylo_proxy_fallback = fallback_level != "direct"
  )

  out_path_csv <- paste0(output_base, ".csv")
  out_path_parquet <- paste0(output_base, ".parquet")

  message("[info] Writing outputs...")
  feature_tbl %>% select(-fallback_level) %>%
    write_csv(out_path_csv)

  feature_tbl %>% select(-fallback_level) %>%
    write_parquet(out_path_parquet)

  message(sprintf("[ok] Proxy features saved to %s.*", output_base))
}

main()
