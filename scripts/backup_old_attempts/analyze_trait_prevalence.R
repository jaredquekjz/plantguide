#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(data.table)
})

cat('======================================================================\n')
cat('TRAIT PREVALENCE ANALYSIS FOR EIVE TAXA\n')
cat('======================================================================\n\n')

# Define target traits from methodology
trait_definitions <- data.table(
  Category = c(
    rep("Core Leaf", 5),
    rep("Wood", 5),
    rep("Root", 7),
    rep("Mycorrhizal", 2),
    rep("Architecture", 5)
  ),
  TraitID = c(
    # Core Leaf
    3116, 47, 3110, 14, 26,
    # Wood
    4, 282, 287, 163, 159,
    # Root
    1080, 82, 80, 83, 1781, 896, 1401,
    # Mycorrhizal
    1498, NA,
    # Architecture
    18, 2, 368, 59, NA
  ),
  TraitName = c(
    # Core Leaf
    "SLA (leaf area/dry mass)", "LDMC", "Leaf area", "Leaf N", "Seed mass",
    # Wood
    "Wood density", "Vessel diameter", "Conduit density", "P50", "Ks",
    # Root
    "SRL", "Root tissue density", "Root N", "Root diameter", 
    "Fine root density", "Fine root diameter", "Root branching",
    # Mycorrhizal
    "Mycorrhizal colonization", "Mycorrhizal type",
    # Architecture
    "Plant height", "Growth form", "Plant type", "Life history", "Family/Genus"
  ),
  Priority = c(
    # Core Leaf
    "Essential", "Essential", "Essential", "Essential", "Original",
    # Wood
    "Essential", "Essential", "Important", "Important", "Optional",
    # Root
    "Essential", "Essential", "Essential", "Essential", 
    "Important", "Important", "Optional",
    # Mycorrhizal
    "Optional", "Important",
    # Architecture
    "Essential", "Essential", "Original", "Important", "Structure"
  )
)

# Load TRY data
cat('Loading TRY-EIVE merged data...\n')
try_data <- fread('data/output/traits_for_eive_taxa_rtry.tsv', encoding = 'UTF-8')
cat(sprintf('  Loaded %s rows\n\n', format(nrow(try_data), big.mark = ',')))

# Get unique taxa
unique_taxa <- unique(try_data$AccSpeciesName)
unique_taxa <- unique_taxa[!is.na(unique_taxa) & nzchar(unique_taxa)]
n_taxa <- length(unique_taxa)
cat(sprintf('Total unique taxa with data: %d\n\n', n_taxa))

# Analyze trait prevalence
cat('======================================================================\n')
cat('TRAIT PREVALENCE BY CATEGORY\n')
cat('======================================================================\n\n')

# Check if TraitID and TraitName columns exist
if (!'TraitID' %in% names(try_data)) {
  cat('ERROR: TraitID column not found in TRY data!\n')
  cat('Available columns: ', paste(head(names(try_data), 20), collapse = ', '), '\n')
  stop('Cannot proceed without TraitID column')
}

# Get all unique trait IDs in the data
available_traits <- unique(try_data$TraitID)
available_traits <- available_traits[!is.na(available_traits)]
cat(sprintf('Total unique traits in dataset: %d\n\n', length(available_traits)))

# Function to count taxa with a specific trait
count_taxa_with_trait <- function(trait_id) {
  if (is.na(trait_id)) return(NA)
  taxa_with_trait <- unique(try_data[TraitID == trait_id, AccSpeciesName])
  taxa_with_trait <- taxa_with_trait[!is.na(taxa_with_trait) & nzchar(taxa_with_trait)]
  length(taxa_with_trait)
}

# Analyze each trait
trait_definitions[!is.na(TraitID), N_Taxa := sapply(TraitID, count_taxa_with_trait)]
trait_definitions[!is.na(TraitID), Percent := round(100 * N_Taxa / n_taxa, 1)]
trait_definitions[!is.na(TraitID), Available := TraitID %in% available_traits]

# Print by category
for (cat in unique(trait_definitions$Category)) {
  cat(sprintf('%s TRAITS:\n', toupper(cat)))
  cat(paste(rep('-', 70), collapse = ''), '\n')
  
  sub_traits <- trait_definitions[Category == cat & !is.na(TraitID)]
  
  for (i in 1:nrow(sub_traits)) {
    status <- if (sub_traits$Available[i]) {
      if (sub_traits$N_Taxa[i] > 0) {
        sprintf('✓ %d taxa (%.1f%%)', sub_traits$N_Taxa[i], sub_traits$Percent[i])
      } else {
        '✗ No taxa found'
      }
    } else {
      '✗ Not in dataset'
    }
    
    cat(sprintf('  ID %5d: %-35s [%s] %s\n', 
                sub_traits$TraitID[i],
                sub_traits$TraitName[i],
                sub_traits$Priority[i],
                status))
  }
  cat('\n')
}

# Summary statistics
essential_traits <- trait_definitions[Priority == "Essential" & !is.na(TraitID)]
cat('======================================================================\n')
cat('SUMMARY STATISTICS\n')
cat('======================================================================\n')
cat(sprintf('Essential traits available: %d of %d\n', 
            sum(essential_traits$Available), nrow(essential_traits)))
cat(sprintf('Essential traits with >50%% coverage: %d\n',
            sum(essential_traits$Percent > 50, na.rm = TRUE)))
cat(sprintf('Essential traits with >10%% coverage: %d\n',
            sum(essential_traits$Percent > 10, na.rm = TRUE)))

# Create trait prevalence matrix (taxa x traits)
cat('\n======================================================================\n')
cat('CREATING PLANT-TRAIT MATRIX\n')
cat('======================================================================\n\n')

# Get target trait IDs that are available
target_traits <- trait_definitions[Available == TRUE & N_Taxa > 0, TraitID]

if (length(target_traits) > 0) {
  cat(sprintf('Creating matrix for %d traits with data...\n', length(target_traits)))
  
  # Create presence/absence matrix
  trait_matrix <- data.table(Species = unique_taxa)
  
  for (tid in target_traits) {
    trait_name <- trait_definitions[TraitID == tid, TraitName]
    col_name <- sprintf('T%d', tid)
    
    # Get taxa with this trait
    taxa_with <- unique(try_data[TraitID == tid, AccSpeciesName])
    trait_matrix[, (col_name) := Species %in% taxa_with]
    
    if (which(target_traits == tid) %% 5 == 0) {
      cat(sprintf('  Processed %d of %d traits...\n', 
                  which(target_traits == tid), length(target_traits)))
    }
  }
  
  # Calculate trait coverage per species
  trait_cols <- grep('^T[0-9]+', names(trait_matrix), value = TRUE)
  trait_matrix[, N_Traits := rowSums(.SD), .SDcols = trait_cols]
  
  # Save full matrix
  fwrite(trait_matrix, 'data/output/plant_trait_matrix.csv')
  cat(sprintf('\nFull matrix saved to: data/output/plant_trait_matrix.csv\n'))
  cat(sprintf('  Dimensions: %d taxa × %d traits\n', nrow(trait_matrix), length(trait_cols)))
  
  # Create economical sparse representation
  cat('\nCreating sparse representation...\n')
  
  # Melt to long format (only TRUE values)
  sparse_matrix <- melt(trait_matrix, 
                        id.vars = c('Species', 'N_Traits'),
                        measure.vars = trait_cols,
                        variable.name = 'TraitCode',
                        value.name = 'Present')
  
  # Keep only present traits
  sparse_matrix <- sparse_matrix[Present == TRUE]
  sparse_matrix[, Present := NULL]
  
  # Add trait names
  sparse_matrix[, TraitID := as.integer(gsub('^T', '', TraitCode))]
  sparse_matrix <- merge(sparse_matrix, 
                         trait_definitions[, .(TraitID, TraitName, Category)],
                         by = 'TraitID')
  
  # Sort by species and trait
  setorder(sparse_matrix, Species, Category, TraitID)
  
  # Save sparse representation
  fwrite(sparse_matrix[, .(Species, TraitID, TraitName, Category)], 
         'data/output/plant_trait_sparse.csv')
  cat(sprintf('Sparse representation saved to: data/output/plant_trait_sparse.csv\n'))
  cat(sprintf('  Size: %d entries (%.1f%% of full matrix)\n', 
              nrow(sparse_matrix),
              100 * nrow(sparse_matrix) / (n_taxa * length(trait_cols))))
  
  # Species coverage statistics
  cat('\n======================================================================\n')
  cat('SPECIES TRAIT COVERAGE\n')
  cat('======================================================================\n')
  
  coverage_stats <- trait_matrix[, .(N_Species = .N), by = N_Traits]
  setorder(coverage_stats, -N_Traits)
  
  cat('\nSpecies by number of traits:\n')
  for (i in 1:min(10, nrow(coverage_stats))) {
    cat(sprintf('  %2d traits: %d species\n', 
                coverage_stats$N_Traits[i], 
                coverage_stats$N_Species[i]))
  }
  
  cat(sprintf('\nMean traits per species: %.1f\n', mean(trait_matrix$N_Traits)))
  cat(sprintf('Median traits per species: %d\n', median(trait_matrix$N_Traits)))
  
  # Find well-covered species
  well_covered <- trait_matrix[N_Traits >= quantile(N_Traits, 0.9)]
  cat(sprintf('\nTop 10%% best-covered species have ≥%d traits\n', min(well_covered$N_Traits)))
  
  # Sample of best-covered species
  cat('\nExamples of well-covered species:\n')
  setorder(well_covered, -N_Traits)
  for (i in 1:min(10, nrow(well_covered))) {
    cat(sprintf('  %s: %d traits\n', 
                well_covered$Species[i], 
                well_covered$N_Traits[i]))
  }
  
  # Essential trait combinations
  cat('\n======================================================================\n')
  cat('ESSENTIAL TRAIT COMBINATIONS\n')
  cat('======================================================================\n')
  
  essential_ids <- essential_traits[Available == TRUE & N_Taxa > 0, TraitID]
  if (length(essential_ids) > 0) {
    essential_cols <- paste0('T', essential_ids)
    essential_cols <- essential_cols[essential_cols %in% names(trait_matrix)]
    
    if (length(essential_cols) > 0) {
      # Count species with all essential traits
      trait_matrix[, Has_All_Essential := rowSums(.SD) == length(essential_cols), 
                   .SDcols = essential_cols]
      n_complete <- sum(trait_matrix$Has_All_Essential)
      
      cat(sprintf('\nSpecies with ALL %d essential traits: %d (%.1f%%)\n',
                  length(essential_cols), n_complete, 100 * n_complete / n_taxa))
      
      # Count by number of essential traits
      trait_matrix[, N_Essential := rowSums(.SD), .SDcols = essential_cols]
      essential_coverage <- trait_matrix[, .(N_Species = .N), by = N_Essential]
      setorder(essential_coverage, -N_Essential)
      
      cat('\nSpecies by essential trait coverage:\n')
      for (i in 1:nrow(essential_coverage)) {
        cat(sprintf('  %d of %d essential traits: %d species (%.1f%%)\n',
                    essential_coverage$N_Essential[i],
                    length(essential_cols),
                    essential_coverage$N_Species[i],
                    100 * essential_coverage$N_Species[i] / n_taxa))
      }
    }
  }
  
} else {
  cat('No traits with data found!\n')
}

cat('\n======================================================================\n')
cat('ANALYSIS COMPLETE!\n')
cat('======================================================================\n')
cat('\nOutput files created:\n')
cat('  - data/output/plant_trait_matrix.csv (full presence/absence matrix)\n')
cat('  - data/output/plant_trait_sparse.csv (economical sparse format)\n')
cat('\nSparse format columns:\n')
cat('  Species: species name\n')
cat('  TraitID: TRY trait ID\n')
cat('  TraitName: human-readable trait name\n')
cat('  Category: trait category (Core Leaf, Wood, Root, etc.)\n')