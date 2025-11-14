# Unified Taxonomic Categorization Plan

## Problem Statement

Current categorization is inconsistent across ecological roles:
- **Pollinators**: 15 mixed categories (Honey Bees, Hover Flies, Mosquitoes, Other Beetles, Solitary Bees, etc.)
- **Predators**: 14 taxonomic categories (Spiders, Ground Beetles, Hoverflies, Birds, etc.)
- **Herbivores**: 10 functional categories (Aphids, Mites, Caterpillars, etc.)

**Issues:**
1. Same organism categorized differently in different contexts (e.g., "Hover Flies" vs "Hoverflies")
2. Pollinators use mixed taxonomic/functional scheme while predators use pure taxonomic
3. Herbivore pests shown in tables have NO categories displayed
4. Many organisms play multiple roles (hoverflies are both pollinators AND predators) but this isn't clear

## Proposed Solution

Create a **single unified taxonomic categorization system** that:
1. Uses consistent category names across all three roles
2. Shows categories in ALL tables (herbivore pests, predators, pollinators)
3. Makes multi-role organisms obvious (same category name in different contexts)
4. Balances taxonomic precision with ecological interpretation

## Unified Category System

### Design Principles

1. **Taxonomic groupings** where possible (Spiders, Bees, Beetles, etc.)
2. **Functional groupings** only where taxonomically diverse (Aphids, Mites)
3. **Consistent naming** across all three data sources
4. **Coverage-based** - categories should represent frequently-occurring groups

### Data Sources Analysis

Before finalizing categories, analyze actual genus distribution in:

1. **Herbivores** (`organism_profiles_pure_r.csv` herbivores column):
   - Extract top 200 genera by frequency
   - Current categories: Aphids, Mites, Leaf Miners, Scale Insects, Caterpillars, Thrips, Whiteflies, Beetles, Leafhoppers, Other

2. **Predators** (`herbivore_predators_pure_r.parquet`):
   - Top 200 genera already analyzed (14,282 matches)
   - Current categories: Spiders, Ground Beetles, Rove Beetles, Soldier Beetles, Bats, Birds, Hoverflies, Ladybugs, Predatory Bugs, Predatory Wasps, Harvestmen, Earwigs, Centipedes, Soft-bodied Beetles

3. **Pollinators** (`organism_profiles_pure_r.csv` pollinators column):
   - Top 200 genera already analyzed
   - Current categories: Honey Bees, Hover Flies, Mosquitoes, Solitary Bees, Wasps, Other Beetles, Other Flies, Other, etc.

### Proposed Unified Categories (Draft)

Based on existing analysis, propose these **cross-role categories**:

#### Insects - Hymenoptera (Bees, Wasps, Ants)
- **Honey Bees** (Apis) - primarily pollinators
- **Bumblebees** (Bombus) - primarily pollinators
- **Solitary Bees** (Andrena, Lasioglossum, Osmia, etc.) - primarily pollinators
- **Wasps** (Vespidae, Sphecidae, etc.) - pollinators + predators
- **Parasitoid Wasps** (Ichneumonidae, Braconidae) - predators only
- **Ants** (Formicidae) - predators + occasional pollinators

#### Insects - Coleoptera (Beetles)
- **Ladybugs** (Coccinellidae) - predators
- **Ground Beetles** (Carabidae) - predators
- **Rove Beetles** (Staphylinidae) - predators
- **Soldier Beetles** (Cantharidae) - predators + pollinators
- **Soft-bodied Beetles** (Melyridae) - predators
- **Leaf Beetles** (Chrysomelidae) - herbivores
- **Weevils** (Curculionidae) - herbivores
- **Other Beetles** - all roles

#### Insects - Diptera (Flies)
- **Hoverflies** (Syrphidae) - predators (larvae) + pollinators (adults)
- **Mosquitoes** (Culicidae) - pollinators (males)
- **Other Flies** - all roles

#### Insects - Lepidoptera (Butterflies & Moths)
- **Butterflies** - pollinators (adults) + herbivores (larvae)
- **Moths** - pollinators (adults) + herbivores (larvae)
- **Caterpillars** - herbivores (when shown as pests)

#### Insects - Hemiptera (True Bugs)
- **Aphids** (Aphididae) - herbivores
- **Scale Insects** (Coccoidea) - herbivores
- **Whiteflies** (Aleyrodidae) - herbivores
- **Leafhoppers** (Cicadellidae) - herbivores
- **Predatory Bugs** (Anthocoridae, Nabidae, etc.) - predators

#### Insects - Other Orders
- **Thrips** (Thysanoptera) - herbivores
- **Earwigs** (Dermaptera) - predators
- **Lacewings** (Neuroptera) - predators

#### Arachnids
- **Spiders** (Araneae) - predators
- **Mites** (Acari) - herbivores (mostly)
- **Harvestmen** (Opiliones) - predators

#### Other Arthropods
- **Centipedes** (Chilopoda) - predators
- **Millipedes** (Diplopoda) - herbivores/detritivores

#### Vertebrates
- **Birds** (Aves) - predators + pollinators
- **Bats** (Chiroptera) - predators + pollinators

#### Specialized Categories
- **Leaf Miners** (various orders) - functional group, herbivores
- **Other Herbivores** - uncategorized herbivores
- **Other Predators** - uncategorized predators
- **Other Pollinators** - uncategorized pollinators

## Implementation Plan

### Phase 1: Data Analysis (30 min)

1. Extract and analyze top 200 genera from each data source:
   ```r
   # Herbivores
   herbivore_genera <- extract_top_genera(organism_profiles, "herbivores", n=200)

   # Predators (already have this)
   predator_genera <- read_parquet("herbivore_predators_pure_r.parquet")

   # Pollinators
   pollinator_genera <- extract_top_genera(organism_profiles, "pollinators", n=200)
   ```

2. Create frequency tables for each role showing:
   - Genus name
   - Frequency/match count
   - Current category assignment
   - Proposed unified category

3. Identify multi-role organisms (appear in 2+ datasets)

### Phase 2: Category Refinement (15 min)

1. Based on frequency analysis, finalize category list
2. Ensure each category represents meaningful % of each dataset
3. Create comprehensive genus pattern lists for each category
4. Document expected coverage (% of organisms categorized vs "Other")

### Phase 3: Implementation (1 hour)

#### Update R Code

1. **Create unified categorization module** (`shipley_checks/src/Stage_4/explanation/unified_taxonomy.R`):
   ```r
   #' Unified taxonomic categorization for all organism roles
   #' @param name Organism scientific name
   #' @param role One of: "herbivore", "predator", "pollinator" (for context)
   #' @return Category string
   categorize_organism <- function(name, role = NULL) {
     name_lower <- tolower(name)

     # Honey Bees
     if (grepl("apis", name_lower)) return("Honey Bees")

     # Bumblebees
     if (grepl("bombus", name_lower)) return("Bumblebees")

     # Solitary Bees (50+ genera)
     if (grepl("andrena|lasioglossum|osmia|...", name_lower)) {
       return("Solitary Bees")
     }

     # Hoverflies
     if (grepl("syrphus|platycheirus|episyrphus|...", name_lower)) {
       return("Hoverflies")
     }

     # ... etc for all categories

     # Default fallback based on role
     if (!is.null(role)) {
       if (role == "herbivore") return("Other Herbivores")
       if (role == "predator") return("Other Predators")
       if (role == "pollinator") return("Other Pollinators")
     }

     return("Other")
   }
   ```

2. **Update biocontrol analysis** (`biocontrol_network_analysis.R`):
   - Replace `categorize_predator()` → use `categorize_organism(name, "predator")`
   - Replace `categorize_herbivore()` → use `categorize_organism(name, "herbivore")`
   - Update matched pairs table to show unified categories

3. **Update pollinator analysis** (`pollinator_network_analysis.R`):
   - Replace existing categorization → use `categorize_organism(name, "pollinator")`
   - Update network tables to show unified categories

4. **Update herbivore pest tables** (M1 section):
   - Add category column to "Top 10 Herbivore Pests" table
   - Add category column to "Most Vulnerable Plants" breakdown

#### Update Rust Code

1. **Create unified categorization module** (`src/explanation/unified_taxonomy.rs`):
   ```rust
   /// Unified organism category across all ecological roles
   #[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
   pub enum OrganismCategory {
       // Hymenoptera
       HoneyBees,
       Bumblebees,
       SolitaryBees,
       Wasps,
       ParasitoidWasps,
       Ants,

       // Coleoptera
       Ladybugs,
       GroundBeetles,
       RoveBeetles,
       // ... etc

       // Fallbacks
       OtherHerbivores,
       OtherPredators,
       OtherPollinators,
       Other,
   }

   impl OrganismCategory {
       pub fn from_name(name: &str, role: Option<&str>) -> Self {
           let name_lower = name.to_lowercase();

           // Unified categorization logic
           if name_lower.contains("apis") {
               return OrganismCategory::HoneyBees;
           }
           // ... etc
       }

       pub fn display_name(&self) -> &str {
           match self {
               OrganismCategory::HoneyBees => "Honey Bees",
               OrganismCategory::Hoverflies => "Hoverflies",
               // ... etc
           }
       }
   }
   ```

2. **Update all analysis modules**:
   - Replace role-specific enums (PredatorCategory, PollinatorCategory, etc.)
   - Use unified OrganismCategory throughout
   - Update serialization/deserialization

### Phase 4: Testing (30 min)

1. **Generate test reports** for 3 guilds in both R and Rust
2. **Verify category consistency**:
   - Same organism → same category in all contexts
   - Multi-role organisms clearly visible
   - All tables show categories
3. **Check coverage**:
   - Herbivores: % categorized vs "Other Herbivores"
   - Predators: % categorized vs "Other Predators"
   - Pollinators: % categorized vs "Other Pollinators"

### Phase 5: Documentation (15 min)

1. Update category documentation in TEMP file with final categories
2. Document multi-role organisms (e.g., Hoverflies appear as both predators and pollinators)
3. Add coverage statistics

## Expected Outcomes

1. **Consistency**: Same organism always has same category name
2. **Clarity**: Easy to see which organisms play multiple roles
3. **Completeness**: All organism tables show categories
4. **Coverage**: >95% of frequent organisms categorized (not "Other")

## Example Output

### Before (Inconsistent)

**M3 Biocontrol:**
| Herbivore | Known Predator | Predator Category |
|-----------|----------------|-------------------|
| Aphis | Platycheirus scutatus | Hoverflies |

**M7 Pollinators:**
| Pollinator | Category |
|------------|----------|
| Platycheirus scutatus | Hover Flies |

→ Same organism, different category names!

### After (Unified)

**M1 Pest Vulnerability:**
| Herbivore Pest | Herbivore Category | Plants Attacked |
|----------------|-------------------|-----------------|
| Aphis fabae | Aphids | 3 plants |
| Adoxophyes orana | Caterpillars | 1 plant |

**M3 Biocontrol:**
| Herbivore | Herbivore Category | Known Predator | Predator Category |
|-----------|-------------------|----------------|-------------------|
| Aphis fabae | Aphids | Platycheirus scutatus | Hoverflies |
| Aphis fabae | Aphids | Adalia bipunctata | Ladybugs |

**M7 Pollinators:**
| Pollinator | Pollinator Category | Plants Connected |
|------------|---------------------|------------------|
| Platycheirus scutatus | Hoverflies | 2 plants |
| Apis mellifera | Honey Bees | 5 plants |

→ **Insight**: Platycheirus scutatus plays dual role as BOTH predator (of Aphids) AND pollinator!

## User Decisions

1. **Functional categories**: Keep functional naming (Aphids, Mites, Caterpillars) for gardeners/farmers. Taxonomic orders are implicit for those with knowledge.
2. **Life stage handling**:
   - Butterflies/Moths/Hoverflies = shown as pollinators (adults)
   - Caterpillars = shown as herbivores (butterfly/moth larvae)
   - Hoverfly larvae = predators (aphid eaters), not herbivores
3. **"Other" categories**: Use role-specific (Other Herbivores, Other Predators, Other Pollinators)
4. **Rare but important groups**: Include if ecologically significant

## Frequency Analysis Results

### Herbivores (16,800 records, 3,030 genera)
Top: Aphis (532), Myzus (267), Hemiberlesia (169), Orgyia (133), Acronicta (129), Spodoptera (124), Phytomyza (116), Liriomyza (96), Aceria (89)

### Predators (14,282 records, 2,961 genera)
Top: Amara (484), Myotis (196), Pterostichus (190), Xysticus (172), Carabus (158), Harpalus (158), Philonthus (156), Cantharis (116)

### Pollinators (29,319 records, 3,057 genera)
Top: Bombus (3,527), Andrena (1,364), Lasioglossum (1,207), Apis (626), Eristalis (532), Platycheirus (438), Halictus (380), Empis (332)

### Multi-Role Organisms
- **Predator + Pollinator**: 196 genera (e.g., Cantharis, Amara, Vespula, Forficula)
- **All three roles**: 45 genera (e.g., Platycheirus, Amara, Vanessa, Vespa)

## Finalized Unified Categories

Based on frequency analysis, here are the **functional categories** to use:

### Universal Categories (appear in multiple roles)

1. **Bumblebees** (Bombus) - pollinators, occasional predators
2. **Honey Bees** (Apis) - pollinators
3. **Solitary Bees** (Andrena, Lasioglossum, Halictus, Osmia, Megachile, Ceratina, Hylaeus, Colletes, Eucera, Anthophora, Xylocopa, Nomada, etc.) - pollinators
4. **Hoverflies** (Syrphus, Platycheirus, Episyrphus, Eupeodes, Sphaerophoria, Melanostoma, Eristalis, Cheilosia, Helophilus, Syritta, Volucella, Rhingia, etc.) - predators (larvae) + pollinators (adults)
5. **Butterflies** (Papilio, Pieris, Vanessa, Danaus, Euploea, etc.) - pollinators (adults), herbivores as larvae
6. **Moths** (Orgyia, Acronicta, Spodoptera, Lymantria, Malacosoma, Hyalophora, Attacus, Automeris, Biston, Ectropis, etc.) - pollinators (adults), herbivores as larvae
7. **Wasps** (Vespula, Vespa, Polistes, Ammophila, etc.) - predators + pollinators
8. **Parasitoid Wasps** (Aleiodes, Ichneumon, Braconidae, etc.) - predators only
9. **Ants** (Formica, Lasius, Camponotus, Monomorium, Oecophylla, etc.) - predators + occasional pollinators
10. **Soldier Beetles** (Cantharis, Rhagonycha) - predators + pollinators
11. **Flies** (Empis, Sarcophaga, Delia, Phaonia, Lucilia, Pollenia, Calliphora, Bombylius, Rhamphomyia, etc.) - various roles

### Herbivore-Specific Categories

12. **Aphids** (Aphis, Myzus, Macrosiphum, Aulacorthum, Uroleucon, etc.)
13. **Scale Insects** (Hemiberlesia, Aspidiotus, Parlatoria, Lindingaspis, Leucaspis, Coccus, Saissetia, Lepidosaphes, Pseudaulacaspis, Aonidiella, etc.)
14. **Mites** (Aceria, Tetranychus, Eriophyes, Panonychus, etc.)
15. **Leaf Miners** (Phytomyza, Liriomyza, Agromyza, Chromatomyia, etc.)
16. **Caterpillars** (when shown as herbivore pests - moth/butterfly larvae)
17. **Thrips** (Thrips, Frankliniella, Scirtothrips, etc.)
18. **Whiteflies** (Bemisia, Trialeurodes, Aleurodicus, etc.)
19. **Leafhoppers** (Empoasca, Graphocephala, Erythroneura, etc.)
20. **Weevils** (Curculio, Anthonomus, Phyllobius, etc.)
21. **Leaf Beetles** (Chrysomela, Phyllotreta, Cassida, etc.)

### Predator-Specific Categories

22. **Spiders** (Xysticus, Robertus, Araniella, Tetragnatha, Porrhomma, Pardosa, Mangora, Pisaura, Larinioides, Agalenatea, Allagelena, etc.)
23. **Ground Beetles** (Amara, Pterostichus, Carabus, Harpalus, Calathus, Pseudophonus, Notiophilus, Agonum, Poecilus, etc.)
24. **Rove Beetles** (Philonthus, Ocypus, Quedius, Tasgius, Platydracus, Tachyporus, etc.)
25. **Ladybugs** (Adalia, Hippodamia, Coccinella, Harmonia, Chilocorus, Scymnus, etc.)
26. **Predatory Bugs** (Nabis, Anthocoris, Orius, etc.)
27. **Lacewings** (Chrysoperla, Chrysopa, Hemerobius, etc.)
28. **Bats** (Myotis, Rhinolophus, Eptesicus, Nyctalus, Pipistrellus, Plecotus, etc.)
29. **Birds** (Vireo, Setophaga, Turdus, Parus, Fringilla, etc.)
30. **Harvestmen** (Opilio, Phalangium, Leiobunum, etc.)
31. **Earwigs** (Forficula, Apterygida, etc.)
32. **Centipedes** (Lithobius, Scolopendra, etc.)

### Catch-All Categories

33. **Other Herbivores**
34. **Other Predators**
35. **Other Pollinators**

## Next Steps

1. ✅ User approved plan with clarifications
2. ✅ Phase 1: Analyzed actual genera in each dataset
3. ✅ Finalized unified category list based on real data
4. Implement in R and Rust
5. Test and verify
6. Commit changes
