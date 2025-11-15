#!/usr/bin/env Rscript

library(taxizedb)
library(duckdb)
library(arrow)
library(DBI)

cat("=== Building Taxonomy Enrichment WITH Vernacular Names ===\n\n")

# Load organisms
all_organisms <- arrow::read_parquet("data/taxonomy/all_organisms.parquet")
cat(sprintf("Loaded %d organisms\n\n", nrow(all_organisms)))

# Connect to local taxonomy databases
cat("Connecting to local taxonomy databases...\n")
src_ncbi <- src_ncbi()

# Function to get taxonomy AND common names from NCBI
get_ncbi_data <- function(organism_name) {
  tryCatch({
    result <- classification(organism_name, db = "ncbi")[[1]]
    if (is.data.frame(result) && nrow(result) > 0) {
      # Get taxonomic hierarchy
      tax_data <- list(
        kingdom = result$name[result$rank == "kingdom"][1],
        phylum = result$name[result$rank == "phylum"][1],
        class = result$name[result$rank == "class"][1],
        order = result$name[result$rank == "order"][1],
        family = result$name[result$rank == "family"][1],
        tax_id = result$id[nrow(result)]  # Species-level tax_id
      )

      # Get common/vernacular names
      if (!is.na(tax_data$tax_id)) {
        names_query <- sprintf("SELECT name_txt, name_class FROM names WHERE tax_id = %s", tax_data$tax_id)
        names_result <- dbGetQuery(src_ncbi$con, names_query)

        # Extract common names
        common_names <- names_result$name_txt[names_result$name_class == "common name"]
        tax_data$common_names <- if(length(common_names) > 0) paste(common_names, collapse = "; ") else NA
      } else {
        tax_data$common_names <- NA
      }

      return(tax_data)
    }
  }, error = function(e) NULL)
  return(NULL)
}

# Process organisms in batches
batch_size <- 100
n_organisms <- nrow(all_organisms)
n_batches <- ceiling(n_organisms / batch_size)

enriched_data <- list()

cat(sprintf("Processing %d organisms in %d batches...\n", n_organisms, n_batches))

for (batch_idx in 1:n_batches) {
  start_idx <- (batch_idx - 1) * batch_size + 1
  end_idx <- min(batch_idx * batch_size, n_organisms)

  cat(sprintf("Batch %d/%d (%d-%d)...\n", batch_idx, n_batches, start_idx, end_idx))

  for (i in start_idx:end_idx) {
    organism <- all_organisms$organism_name[i]

    # Get NCBI taxonomy + common names
    tax_data <- get_ncbi_data(organism)

    enriched_data[[i]] <- data.frame(
      organism_name = organism,
      genus = all_organisms$genus[i],
      is_herbivore = all_organisms$is_herbivore[i],
      is_pollinator = all_organisms$is_pollinator[i],
      is_predator = all_organisms$is_predator[i],
      kingdom = if(!is.null(tax_data)) tax_data$kingdom else NA,
      phylum = if(!is.null(tax_data)) tax_data$phylum else NA,
      class = if(!is.null(tax_data)) tax_data$class else NA,
      order = if(!is.null(tax_data)) tax_data$order else NA,
      family = if(!is.null(tax_data)) tax_data$family else NA,
      common_names = if(!is.null(tax_data)) tax_data$common_names else NA,
      stringsAsFactors = FALSE
    )
  }

  # Save progress every 10 batches
  if (batch_idx %% 10 == 0) {
    progress_df <- do.call(rbind, enriched_data[1:end_idx])
    arrow::write_parquet(progress_df, "data/taxonomy/taxonomy_enrichment_progress.parquet")
    cat(sprintf("  Progress saved (%d%% complete)\n", round(100 * end_idx / n_organisms)))
  }
}

# Combine all results
cat("\nCombining results...\n")
final_data <- do.call(rbind, enriched_data)

# Calculate statistics
n_with_family <- sum(!is.na(final_data$family))
n_with_common <- sum(!is.na(final_data$common_names))
pct_with_family <- 100 * n_with_family / nrow(final_data)
pct_with_common <- 100 * n_with_common / nrow(final_data)

cat(sprintf("\n=== Results ===\n"))
cat(sprintf("Total organisms: %d\n", nrow(final_data)))
cat(sprintf("With family data: %d (%.1f%%)\n", n_with_family, pct_with_family))
cat(sprintf("With common names: %d (%.1f%%)\n", n_with_common, pct_with_common))
cat(sprintf("Unique families: %d\n", length(unique(final_data$family[!is.na(final_data$family)]))))

# Show sample common names
cat("\nSample common names:\n")
with_common <- final_data[!is.na(final_data$common_names), ]
print(head(with_common[, c("organism_name", "family", "common_names")], 20))

# Save final result
arrow::write_parquet(final_data, "data/taxonomy/organism_taxonomy_enriched.parquet")
cat("\n✓ Saved to: data/taxonomy/organism_taxonomy_enriched.parquet\n")
