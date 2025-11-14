#!/usr/bin/env Rscript
# Analyze genera across herbivores, predators, and pollinators
# to design unified taxonomic categorization

library(arrow)
library(dplyr)
library(tidyr)

# Load data
organism_profiles <- read.csv("shipley_checks/validation/organism_profiles_pure_r.csv")
predator_matches <- read_parquet("shipley_checks/validation/herbivore_predators_pure_r.parquet")

# ============================================================================
# HERBIVORES: Extract and count genera
# ============================================================================

cat("\n=== HERBIVORE ANALYSIS ===\n")

# Parse herbivores column (list format)
herbivore_list <- organism_profiles %>%
  filter(!is.na(herbivores) & herbivores != "") %>%
  pull(herbivores) %>%
  strsplit("\\|") %>%
  unlist() %>%
  trimws()

# Extract genus (first word)
herbivore_genera <- sapply(strsplit(herbivore_list, " "), function(x) tolower(x[1]))

# Count occurrences
herbivore_freq <- sort(table(herbivore_genera), decreasing = TRUE)

cat(sprintf("\nTotal herbivore records: %d\n", length(herbivore_list)))
cat(sprintf("Unique herbivore genera: %d\n", length(herbivore_freq)))

cat("\nTop 50 herbivore genera:\n")
print(head(herbivore_freq, 50))

# ============================================================================
# PREDATORS: Extract and count genera
# ============================================================================

cat("\n\n=== PREDATOR ANALYSIS ===\n")

# Parse predators column (list format)
predator_list <- predator_matches %>%
  filter(!is.na(predators) & predators != "") %>%
  pull(predators) %>%
  strsplit("\\|") %>%
  unlist() %>%
  trimws()

# Extract genus from predator names
predator_genera <- sapply(strsplit(predator_list, " "), function(x) tolower(x[1]))

# Count occurrences (match frequency, not species diversity)
predator_freq <- sort(table(predator_genera), decreasing = TRUE)

cat(sprintf("\nTotal predator records: %d\n", length(predator_list)))
cat(sprintf("Unique predator genera: %d\n", length(predator_freq)))

cat("\nTop 50 predator genera:\n")
print(head(predator_freq, 50))

# ============================================================================
# POLLINATORS: Extract and count genera
# ============================================================================

cat("\n\n=== POLLINATOR ANALYSIS ===\n")

# Parse pollinators column (list format)
pollinator_list <- organism_profiles %>%
  filter(!is.na(pollinators) & pollinators != "") %>%
  pull(pollinators) %>%
  strsplit("\\|") %>%
  unlist() %>%
  trimws()

# Extract genus (first word)
pollinator_genera <- sapply(strsplit(pollinator_list, " "), function(x) tolower(x[1]))

# Count occurrences
pollinator_freq <- sort(table(pollinator_genera), decreasing = TRUE)

cat(sprintf("\nTotal pollinator records: %d\n", length(pollinator_list)))
cat(sprintf("Unique pollinator genera: %d\n", length(pollinator_freq)))

cat("\nTop 50 pollinator genera:\n")
print(head(pollinator_freq, 50))

# ============================================================================
# MULTI-ROLE ANALYSIS
# ============================================================================

cat("\n\n=== MULTI-ROLE ORGANISMS ===\n")

# Find genera that appear in multiple roles
all_herbivore_genera <- unique(herbivore_genera)
all_predator_genera <- unique(predator_genera)
all_pollinator_genera <- unique(pollinator_genera)

# Herbivore + Predator
herb_pred <- intersect(all_herbivore_genera, all_predator_genera)
cat(sprintf("\nGenera appearing as BOTH herbivore AND predator: %d\n", length(herb_pred)))
if (length(herb_pred) > 0) {
  cat("Examples:", paste(head(herb_pred, 10), collapse = ", "), "\n")
}

# Herbivore + Pollinator
herb_poll <- intersect(all_herbivore_genera, all_pollinator_genera)
cat(sprintf("\nGenera appearing as BOTH herbivore AND pollinator: %d\n", length(herb_poll)))
if (length(herb_poll) > 0) {
  cat("Examples:", paste(head(herb_poll, 10), collapse = ", "), "\n")
}

# Predator + Pollinator (should be many - hoverflies, wasps, etc.)
pred_poll <- intersect(all_predator_genera, all_pollinator_genera)
cat(sprintf("\nGenera appearing as BOTH predator AND pollinator: %d\n", length(pred_poll)))
if (length(pred_poll) > 0) {
  cat("Examples:", paste(head(pred_poll, 20), collapse = ", "), "\n")
}

# All three roles
all_three <- intersect(herb_pred, all_pollinator_genera)
cat(sprintf("\nGenera appearing in ALL THREE roles: %d\n", length(all_three)))
if (length(all_three) > 0) {
  cat("Examples:", paste(all_three, collapse = ", "), "\n")
}

# ============================================================================
# SAVE RESULTS
# ============================================================================

# Save frequency tables for detailed analysis
write.csv(
  data.frame(genus = names(herbivore_freq), count = as.numeric(herbivore_freq)),
  "shipley_checks/reports/herbivore_genera_frequency.csv",
  row.names = FALSE
)

write.csv(
  data.frame(genus = names(predator_freq), count = as.numeric(predator_freq)),
  "shipley_checks/reports/predator_genera_frequency.csv",
  row.names = FALSE
)

write.csv(
  data.frame(genus = names(pollinator_freq), count = as.numeric(pollinator_freq)),
  "shipley_checks/reports/pollinator_genera_frequency.csv",
  row.names = FALSE
)

cat("\n\nFrequency tables saved to shipley_checks/reports/\n")
