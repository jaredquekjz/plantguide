#!/usr/bin/env Rscript
# Benchmark R picante (gold standard) on 1000 random guilds

library(ape)
library(picante)

# Load tree (UPDATED: Nov 7, 2025 tree with 11,711 species)
cat("Loading tree...\n")
tree <- read.tree("data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk")
cat("Tree loaded:", length(tree$tip.label), "tips\n")

# Load guilds
cat("Loading guilds...\n")
guilds_df <- read.csv("shipley_checks/stage4/test_guilds_1000.csv", stringsAsFactors = FALSE)
cat("Loaded", nrow(guilds_df), "guilds\n")

# Function to calculate Faith's PD for one guild
calculate_faiths_pd_one <- function(species_str) {
    species <- strsplit(species_str, ";;")[[1]]
    # Filter species that exist in tree
    species <- species[species %in% tree$tip.label]
    # Remove duplicates
    species <- unique(species)
    if (length(species) < 2) return(0.0)

    # Calculate Faith's PD using picante
    # Format: rows are species (community members), columns are sites
    # Create a presence-absence matrix: species as columns, site as row
    comm_matrix <- matrix(1, nrow = 1, ncol = length(species))
    colnames(comm_matrix) <- species
    rownames(comm_matrix) <- c("site1")

    pd_result <- pd(comm_matrix, tree, include.root = FALSE)
    return(pd_result$PD[1])
}

# Warm-up (3 iterations)
cat("\nWarm-up...\n")
for (i in 1:3) {
    calculate_faiths_pd_one(guilds_df$species[1])
}

# Benchmark all 1000 guilds
cat("\nBenchmarking 1000 guilds...\n")
start_time <- Sys.time()
results <- sapply(guilds_df$species, calculate_faiths_pd_one)
end_time <- Sys.time()

total_time_sec <- as.numeric(difftime(end_time, start_time, units = "secs"))
mean_time_ms <- (total_time_sec / length(results)) * 1000

# Save results
results_df <- data.frame(
    guild_id = guilds_df$guild_id,
    guild_size = guilds_df$guild_size,
    faiths_pd = results
)
write.csv(results_df, "shipley_checks/stage4/picante_results_1000.csv", row.names = FALSE)

# Print summary
cat("\n=== R PICANTE BENCHMARK (GOLD STANDARD) ===\n")
cat("Guilds processed:", length(results), "\n")
cat("Total time:", round(total_time_sec, 2), "seconds\n")
cat("Mean time per guild:", round(mean_time_ms, 3), "ms\n")
cat("Throughput:", round(length(results) / total_time_sec, 1), "guilds/second\n")
cat("\nResults saved to: shipley_checks/stage4/picante_results_1000.csv\n")
