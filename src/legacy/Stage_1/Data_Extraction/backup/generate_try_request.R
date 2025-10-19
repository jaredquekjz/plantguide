#!/usr/bin/env Rscript
# Generate TRY request for missing essential traits for EIVE species

cat("===============================================\n")
cat("TRY REQUEST GENERATOR FOR MISSING EIVE TRAITS\n")
cat("===============================================\n\n")

# Essential traits we need to request
essential_traits <- list(
  # Leaf area variants (CRITICAL - we have 0 coverage!)
  leaf_area = c(
    3114,  # Leaf area (undefined) - 8,770 species available
    3110,  # Leaf area (petiole included) - 3,990 species
    3112,  # Leaf area (undefined petiole) - 7,467 species
    3108,  # Leaf area (petiole excluded) - 3,284 species
    3115,  # SLA petiole excluded - 8,120 species
    3116   # SLA petiole included - 8,245 species
  ),
  
  # Root traits (we completely missed these!)
  root_traits = c(
    614,   # Fine root SRL - 1,308 species
    896,   # Fine root diameter - 1,147 species
    1781,  # Fine root tissue density - 881 species
    475,   # Fine root nitrogen - 796 species
    80,    # Root tissue density - 1,562 species
    82,    # Root diameter - 1,919 species
    83,    # Root nitrogen - 1,945 species
    1080,  # Root SRL general - 1,421 species
    6      # Rooting depth - 1,635 species
  ),
  
  # Wood hydraulics
  wood_traits = c(
    282,   # Stem conduit diameter - 737 species
    287,   # Stem vessel density - 1,337 species
    319,   # Stem sapwood conductivity - 416 species
    419    # Stem dry mass - 3,024 species
  ),
  
  # Mycorrhizal and other
  other_traits = c(
    1498,  # Mycorrhizal colonization % - ~500 species
    3488,  # Nutritional relationships - 685 species
    93,    # Leaf lifespan - 3,316 species
    368    # Plant growth rate - 2,395 species
  )
)

# Flatten to single vector
all_traits <- unlist(essential_traits)

cat("TRAITS TO REQUEST:\n")
cat("==================\n")
cat(paste(all_traits, collapse = ", "))
cat("\n\n")

# Load EIVE species IDs we already have
species_file <- "data/output/eive_accspecies_ids.txt"
if (file.exists(species_file)) {
  species_ids <- readLines(species_file)
  cat(sprintf("SPECIES TO REQUEST: %d AccSpeciesIDs from EIVE\n", length(species_ids)))
  cat("(Already saved in: data/output/eive_accspecies_ids_comma.txt)\n\n")
} else {
  cat("WARNING: Run extract_eive_species_ids.R first to get species list!\n\n")
}

# Create request template
cat("TRY REQUEST TEMPLATE:\n")
cat("=====================\n")
cat("Dataset: Request #2 for EIVE Multi-Organ Trait Analysis\n")
cat("Purpose: Complete trait coverage for European indicator species modeling\n")
cat("Traits: ", paste(all_traits, collapse = ", "), "\n")
cat("Species: Use previously identified EIVE AccSpeciesIDs\n")
cat("Ancillary data: Yes (all available)\n\n")

# Trait priority summary
cat("TRAIT PRIORITIES:\n")
cat("=================\n")
cat("CRITICAL (>5000 species available):\n")
cat("  - Leaf area variants (3114, 3110, 3112): 3,990-8,770 species\n")
cat("  - Alternative SLA measures (3115, 3116): 8,000+ species\n\n")

cat("ESSENTIAL (>500 species available):\n")
cat("  - Fine root traits (614, 896, 1781, 475): 796-1,308 species\n")
cat("  - General root traits (80, 82, 83, 1080): 1,421-1,945 species\n")
cat("  - Wood hydraulics (282, 287): 737-1,337 species\n\n")

cat("IMPORTANT (valuable for model):\n")
cat("  - Rooting depth (6): 1,635 species\n")
cat("  - Leaf lifespan (93): 3,316 species\n")
cat("  - Growth rate (368): 2,395 species\n\n")

# Expected improvement
cat("EXPECTED COVERAGE IMPROVEMENT:\n")
cat("==============================\n")
cat("Current coverage:\n")
cat("  - Leaf traits: 32% (SLA/LDMC only)\n")
cat("  - Root traits: 0%\n")
cat("  - Wood traits: 6.6%\n\n")

cat("After new request:\n")
cat("  - Leaf traits: ~60% (with leaf area!)\n")
cat("  - Root traits: ~10% (finally have data!)\n")
cat("  - Wood traits: ~15%\n\n")

cat("MODEL IMPACT:\n")
cat("=============\n")
cat("- Can finally test multi-organ coordination\n")
cat("- Root economics spectrum becomes testable\n")
cat("- Wood-water relations can be modeled\n")
cat("- GAM nonlinear models become viable\n\n")

cat("✨ Script complete! Submit request at: https://www.try-db.org/\n")