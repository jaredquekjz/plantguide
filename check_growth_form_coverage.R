#!/usr/bin/env Rscript
library(data.table)

cat_data <- fread('data/output/eive_categorical_trait_matrix.csv')
cat('=== CATEGORICAL TRAIT COVERAGE ===\n')
cat(sprintf('Total species: %d\n', nrow(cat_data)))

# Check specific growth-related traits
cat('\nGrowth form related traits:\n')

# Plant growth form (31)
if('Cat_31' %in% names(cat_data)) {
  values <- cat_data[['Cat_31']]
  n_values <- sum(!is.na(values))
  cat(sprintf('  Plant growth form (Cat_31): %d species (%.1f%%)\n', 
              n_values, 100*n_values/nrow(cat_data)))
  if(n_values > 0) {
    value_table <- table(values)
    cat('    Top values: ')
    top_values <- sort(value_table, decreasing=TRUE)[1:min(10, length(value_table))]
    for(v in names(top_values)) {
      cat(sprintf('\n      %s: %d ', v, top_values[v]))
    }
    cat('\n')
  }
}

# Woodiness (5736)
if('Cat_5736' %in% names(cat_data)) {
  values <- cat_data[['Cat_5736']]
  n_values <- sum(!is.na(values))
  cat(sprintf('  Woodiness (Cat_5736): %d species (%.1f%%)\n', 
              n_values, 100*n_values/nrow(cat_data)))
  if(n_values > 0) {
    value_table <- table(values)
    cat('    Values: ')
    for(v in names(value_table)) {
      cat(sprintf('%s(%d) ', v, value_table[v]))
    }
    cat('\n')
  }
}

# Leaf type (153)
if('Cat_153' %in% names(cat_data)) {
  values <- cat_data[['Cat_153']]
  n_values <- sum(!is.na(values))
  cat(sprintf('  Leaf type (Cat_153): %d species (%.1f%%)\n', 
              n_values, 100*n_values/nrow(cat_data)))
  if(n_values > 0) {
    value_table <- table(values)
    cat('    Values: ')
    for(v in names(value_table)) {
      cat(sprintf('%s(%d) ', v, value_table[v]))
    }
    cat('\n')
  }
}

# Leaf phenology (237)
if('Cat_237' %in% names(cat_data)) {
  values <- cat_data[['Cat_237']]
  n_values <- sum(!is.na(values))
  cat(sprintf('  Leaf phenology (Cat_237): %d species (%.1f%%)\n', 
              n_values, 100*n_values/nrow(cat_data)))
  if(n_values > 0) {
    value_table <- table(values)
    cat('    Values: ')
    for(v in names(value_table)) {
      cat(sprintf('%s(%d) ', v, value_table[v]))
    }
    cat('\n')
  }
}

# Check for family information
cat('\n=== TAXONOMIC COVERAGE ===\n')
# Extract family from AccSpeciesName if present
# This would need more processing, but let's check if we have any family data

cat('\nColumn names containing potential taxonomic info:\n')
tax_cols <- grep('family|Family|taxonom|Taxonom', names(cat_data), value=TRUE)
if(length(tax_cols) > 0) {
  for(col in tax_cols) {
    cat(sprintf('  %s\n', col))
  }
} else {
  cat('  No explicit family columns found\n')
}