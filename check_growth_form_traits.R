#!/usr/bin/env Rscript
library(data.table)

cat_data <- fread('data/output/eive_categorical_trait_matrix.csv')

# Check for Plant growth form traits based on TRY IDs
growth_form_cols <- c('Cat_42', 'Cat_3400', 'Cat_3401', 'Cat_343', 'Cat_38')
trait_names <- c('Plant growth form (42)', 
                'Plant growth form simple (3400)', 
                'Plant growth form detailed (3401)', 
                'Raunkiaer life form (343)', 
                'Plant woodiness (38)')

cat('=== GROWTH FORM TRAIT COVERAGE ===\n')
cat(sprintf('Total species in categorical matrix: %d\n\n', nrow(cat_data)))

for(i in 1:length(growth_form_cols)) {
  col <- growth_form_cols[i]
  if(col %in% names(cat_data)) {
    values <- cat_data[[col]]
    non_na <- sum(!is.na(values))
    cat(sprintf('%s: %d species (%.1f%%)\n', 
                trait_names[i], non_na, 100*non_na/nrow(cat_data)))
    
    if(non_na > 0) {
      value_table <- table(values)
      cat('  Values found:\n')
      # Sort by frequency
      sorted_values <- sort(value_table, decreasing=TRUE)
      n_to_show <- min(15, length(sorted_values))
      for(j in 1:n_to_show) {
        cat(sprintf('    %-30s: %4d species\n', 
                   names(sorted_values)[j], sorted_values[j]))
      }
      if(length(sorted_values) > 15) {
        cat(sprintf('    ... and %d more categories\n', length(sorted_values) - 15))
      }
    }
  } else {
    cat(sprintf('%s: NOT FOUND\n', trait_names[i]))
  }
  cat('\n')
}

# Save species with growth form data for wood density approximation
if('Cat_42' %in% names(cat_data) || 'Cat_38' %in% names(cat_data)) {
  cat('=== PREPARING GROWTH FORM DATA FOR WOOD DENSITY ===\n')
  
  growth_form_data <- cat_data[, .(AccSpeciesID, AccSpeciesName)]
  
  if('Cat_42' %in% names(cat_data)) {
    growth_form_data$plant_growth_form <- cat_data$Cat_42
  }
  
  if('Cat_38' %in% names(cat_data)) {
    growth_form_data$plant_woodiness <- cat_data$Cat_38
  }
  
  if('Cat_343' %in% names(cat_data)) {
    growth_form_data$raunkiaer_life_form <- cat_data$Cat_343
  }
  
  # Count coverage
  has_any <- rowSums(!is.na(growth_form_data[, -c(1:2)])) > 0
  cat(sprintf('Species with any growth form data: %d (%.1f%%)\n', 
              sum(has_any), 100*sum(has_any)/nrow(growth_form_data)))
  
  # Save
  output_file <- 'data/output/species_growth_forms.csv'
  fwrite(growth_form_data, output_file)
  cat(sprintf('Saved to: %s\n', output_file))
}