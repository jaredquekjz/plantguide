#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(data.table)
})

cat('======================================================================\n')
cat('TRAIT PREVALENCE ANALYSIS FOR EIVE TAXA (FROM SUCCESSFUL EXTRACTION)\n')
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
    1498, 1030,  # Using 1030 (Mycorrhizal infection intensity) as found
    # Architecture
    18, 2, 368, 59, 3106  # Added 3106 (Plant height vegetative) as found
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
    "Mycorrhizal colonization", "Mycorrhizal infection intensity",
    # Architecture
    "Plant height", "Growth form", "Plant type", "Life history", "Plant height vegetative"
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
    "Optional", "Found",
    # Architecture
    "Essential", "Essential", "Original", "Important", "Found"
  )
)

# Load the extracted EIVE trait data
cat('Loading extracted EIVE trait data...\n')
eive_data <- readRDS('data/output/eive_all_traits_by_id.rds')
cat(sprintf('  Loaded %s rows\n', format(nrow(eive_data), big.mark = ',')))

# Filter for trait records only
traits_only <- eive_data[!is.na(TraitID) & TraitID != ""]
cat(sprintf('  Trait records: %s\n\n', format(nrow(traits_only), big.mark = ',')))

# Get unique taxa and traits
unique_taxa <- unique(traits_only$AccSpeciesName)
unique_taxa <- unique_taxa[!is.na(unique_taxa) & nzchar(unique_taxa)]
n_taxa <- length(unique_taxa)

available_traits <- unique(traits_only$TraitID)
available_traits <- available_traits[!is.na(available_traits)]

cat(sprintf('Total unique taxa: %d\n', n_taxa))
cat(sprintf('Total unique traits in dataset: %d\n\n', length(available_traits)))

# Check for alternative trait IDs that might be relevant
cat('======================================================================\n')
cat('SEARCHING FOR RELEVANT TRAITS\n')
cat('======================================================================\n\n')

# Look for SLA variants (3116 is standard, but 3117 is also SLA)
sla_variants <- c(3116, 3117, 3086, 3087)
cat('SLA variants found:\n')
for (id in sla_variants) {
  if (id %in% available_traits) {
    trait_data <- traits_only[TraitID == id]
    if (nrow(trait_data) > 0) {
      n_species <- length(unique(trait_data$AccSpeciesName))
      trait_name <- trait_data$TraitName[1]
      cat(sprintf('  ID %d: %s (%d species)\n', id, 
                  substr(trait_name, 1, 60), n_species))
    }
  }
}

# Look for leaf area variants
cat('\nLeaf area variants:\n')
leaf_area_ids <- c(3110, 147, 148, 149, 150, 3111, 3112, 3113)
for (id in leaf_area_ids) {
  if (id %in% available_traits) {
    trait_data <- traits_only[TraitID == id]
    if (nrow(trait_data) > 0) {
      n_species <- length(unique(trait_data$AccSpeciesName))
      trait_name <- trait_data$TraitName[1]
      cat(sprintf('  ID %d: %s (%d species)\n', id, 
                  substr(trait_name, 1, 60), n_species))
    }
  }
}

# Look for height variants
cat('\nHeight variants:\n')
height_ids <- c(18, 3106, 3107, 3108, 3109)
for (id in height_ids) {
  if (id %in% available_traits) {
    trait_data <- traits_only[TraitID == id]
    if (nrow(trait_data) > 0) {
      n_species <- length(unique(trait_data$AccSpeciesName))
      trait_name <- trait_data$TraitName[1]
      cat(sprintf('  ID %d: %s (%d species)\n', id, 
                  substr(trait_name, 1, 60), n_species))
    }
  }
}

# Function to count taxa with a specific trait
count_taxa_with_trait <- function(trait_id) {
  if (is.na(trait_id)) return(NA)
  if (!(trait_id %in% available_traits)) return(0)
  
  taxa_with_trait <- unique(traits_only[TraitID == trait_id, AccSpeciesName])
  taxa_with_trait <- taxa_with_trait[!is.na(taxa_with_trait) & nzchar(taxa_with_trait)]
  length(taxa_with_trait)
}

# Analyze each trait
trait_definitions[!is.na(TraitID), N_Taxa := sapply(TraitID, count_taxa_with_trait)]
trait_definitions[!is.na(TraitID), Percent := round(100 * N_Taxa / n_taxa, 1)]
trait_definitions[!is.na(TraitID), Available := TraitID %in% available_traits]

# Update with actual found traits
trait_definitions[TraitID == 3116, `:=`(
  N_Taxa = 0,  # 3116 not found
  Available = FALSE
)]
trait_definitions[TraitID == 3116, `:=`(
  Alternative_ID = 3117,
  Alternative_N = count_taxa_with_trait(3117),
  Note = "Use 3117 instead (same trait, different ID)"
)]

# Print by category
cat('\n======================================================================\n')
cat('TRAIT AVAILABILITY BY CATEGORY\n')
cat('======================================================================\n\n')

for (cat in unique(trait_definitions$Category)) {
  cat(sprintf('%s TRAITS:\n', toupper(cat)))
  cat(paste(rep('-', 70), collapse = ''), '\n')
  
  sub_traits <- trait_definitions[Category == cat & !is.na(TraitID)]
  
  for (i in 1:nrow(sub_traits)) {
    if (sub_traits$Available[i] && sub_traits$N_Taxa[i] > 0) {
      status <- sprintf('✓ %d taxa (%.1f%%)', sub_traits$N_Taxa[i], sub_traits$Percent[i])
    } else if (!is.na(sub_traits$Alternative_N[i]) && sub_traits$Alternative_N[i] > 0) {
      status <- sprintf('→ Use ID %d: %d taxa (%.1f%%)', 
                       sub_traits$Alternative_ID[i],
                       sub_traits$Alternative_N[i],
                       100 * sub_traits$Alternative_N[i] / n_taxa)
    } else if (sub_traits$Available[i]) {
      status <- '✗ No taxa found'
    } else {
      status <- '✗ Not in dataset'
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

# Count considering alternatives
essential_available <- sum(essential_traits$Available | 
                          (!is.na(essential_traits$Alternative_N) & essential_traits$Alternative_N > 0))
essential_with_coverage <- sum(essential_traits$N_Taxa > n_taxa * 0.1 | 
                               (!is.na(essential_traits$Alternative_N) & essential_traits$Alternative_N > n_taxa * 0.1))

cat('======================================================================\n')
cat('SUMMARY STATISTICS\n')
cat('======================================================================\n')
cat(sprintf('Essential traits available: %d of %d\n', 
            essential_available, nrow(essential_traits)))
cat(sprintf('Essential traits with >50%% coverage: %d\n',
            sum(essential_traits$Percent > 50 | 
                (!is.na(essential_traits$Alternative_N) & essential_traits$Alternative_N > n_taxa * 0.5), 
                na.rm = TRUE)))
cat(sprintf('Essential traits with >10%% coverage: %d\n', essential_with_coverage))

# Create implementation summary
cat('\n======================================================================\n')
cat('IMPLEMENTATION FEASIBILITY\n')
cat('======================================================================\n\n')

cat('STRONG COVERAGE (>30% of taxa):\n')
strong_traits <- traits_only[, .(N_species = length(unique(AccSpeciesName))), by = .(TraitID, TraitName)]
strong_traits <- strong_traits[N_species > n_taxa * 0.3]
setorder(strong_traits, -N_species)

for (i in 1:min(15, nrow(strong_traits))) {
  cat(sprintf('  ID %5s: %s (%d species, %.1f%%)\n',
              strong_traits$TraitID[i],
              substr(strong_traits$TraitName[i], 1, 50),
              strong_traits$N_species[i],
              100 * strong_traits$N_species[i] / n_taxa))
}

cat('\nMODERATE COVERAGE (10-30% of taxa):\n')
moderate_traits <- traits_only[, .(N_species = length(unique(AccSpeciesName))), by = .(TraitID, TraitName)]
moderate_traits <- moderate_traits[N_species > n_taxa * 0.1 & N_species <= n_taxa * 0.3]
setorder(moderate_traits, -N_species)

for (i in 1:min(10, nrow(moderate_traits))) {
  cat(sprintf('  ID %5s: %s (%d species, %.1f%%)\n',
              moderate_traits$TraitID[i],
              substr(moderate_traits$TraitName[i], 1, 50),
              moderate_traits$N_species[i],
              100 * moderate_traits$N_species[i] / n_taxa))
}

# Model viability assessment
cat('\n======================================================================\n')
cat('MODEL VIABILITY BY TRAIT GROUP\n')
cat('======================================================================\n\n')

cat('1. LEAF ECONOMICS MODEL:\n')
sla_coverage <- count_taxa_with_trait(3117)  # Using 3117 as found
ldmc_coverage <- count_taxa_with_trait(47)
leaf_n_coverage <- count_taxa_with_trait(14)
leaf_area_coverage <- count_taxa_with_trait(147)

cat(sprintf('   SLA (3117): %d species (%.1f%%)\n', sla_coverage, 100*sla_coverage/n_taxa))
cat(sprintf('   LDMC (47): %d species (%.1f%%)\n', ldmc_coverage, 100*ldmc_coverage/n_taxa))
cat(sprintf('   Leaf N (14): %d species (%.1f%%)\n', leaf_n_coverage, 100*leaf_n_coverage/n_taxa))
cat(sprintf('   Leaf area (147): %d species (%.1f%%)\n', leaf_area_coverage, 100*leaf_area_coverage/n_taxa))

leaf_complete <- length(unique(traits_only[TraitID %in% c(3117, 47, 14), AccSpeciesName]))
cat(sprintf('   → Species with ANY leaf trait: %d (%.1f%%)\n', leaf_complete, 100*leaf_complete/n_taxa))

cat('\n2. PLANT SIZE MODEL:\n')
height_coverage <- count_taxa_with_trait(18)
height_veg_coverage <- count_taxa_with_trait(3106)
height_gen_coverage <- count_taxa_with_trait(3107)
seed_mass_coverage <- count_taxa_with_trait(26)

cat(sprintf('   Height (18): %d species (%.1f%%)\n', height_coverage, 100*height_coverage/n_taxa))
cat(sprintf('   Height vegetative (3106): %d species (%.1f%%)\n', height_veg_coverage, 100*height_veg_coverage/n_taxa))
cat(sprintf('   Seed mass (26): %d species (%.1f%%)\n', seed_mass_coverage, 100*seed_mass_coverage/n_taxa))

size_complete <- length(unique(traits_only[TraitID %in% c(18, 3106, 3107, 26), AccSpeciesName]))
cat(sprintf('   → Species with ANY size trait: %d (%.1f%%)\n', size_complete, 100*size_complete/n_taxa))

cat('\n3. WOOD TRAITS MODEL:\n')
wood_density_coverage <- count_taxa_with_trait(4)
cat(sprintf('   Wood density (4): %d species (%.1f%%)\n', wood_density_coverage, 100*wood_density_coverage/n_taxa))
cat('   Note: Limited to woody species only\n')

cat('\n4. ELLENBERG INDICATOR VALUES:\n')
ellenberg_ids <- c(1130, 1131, 1132, 1133, 1134, 1135, 1136)
for (id in ellenberg_ids) {
  if (id %in% available_traits) {
    n_sp <- count_taxa_with_trait(id)
    trait_name <- traits_only[TraitID == id, TraitName[1]]
    cat(sprintf('   ID %d: %d species (%.1f%%)\n', id, n_sp, 100*n_sp/n_taxa))
  }
}

# Save summary
cat('\n======================================================================\n')
cat('SAVING ANALYSIS RESULTS\n')
cat('======================================================================\n')

# Create summary table
summary_table <- traits_only[, .(
  N_species = length(unique(AccSpeciesName)),
  N_records = .N,
  Mean_value = mean(as.numeric(StdValue), na.rm = TRUE),
  SD_value = sd(as.numeric(StdValue), na.rm = TRUE)
), by = .(TraitID, TraitName)]

setorder(summary_table, -N_species)

# Save
output_file <- 'data/output/eive_trait_prevalence_analysis.csv'
fwrite(summary_table, output_file)
cat(sprintf('\nTrait prevalence saved to: %s\n', output_file))

cat('\n======================================================================\n')
cat('ANALYSIS COMPLETE!\n')
cat('======================================================================\n')