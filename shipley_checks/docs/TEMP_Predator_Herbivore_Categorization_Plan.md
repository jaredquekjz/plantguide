# Predator and Herbivore Categorization Expansion Plan

## Executive Summary

Expand taxonomic categorization for predators and herbivores from generic "Other" to specific ecological guilds based on analysis of 794 predator species and 2,895 herbivore species.

## Data Analysis Results

### Predator Taxonomy (from herbivore_predators_pure_r.parquet)

**Total unique predators analyzed: 794 species**

**Major taxonomic groups identified:**

1. **Spiders (Araneae)** - 68+ occurrences
   - Dominant: Aculepeira (68), Agalenatea (44), Argiope (10), Araneus (7)
   - Pattern: "aculepeira", "agalenatea", "argiope", "araneus", "araneae", "spider"

2. **Bats (Chiroptera)** - 50+ occurrences
   - Dominant: Myotis (20), Eptesicus (16), Corynorhinus (14), Miniopterus (10)
   - Pattern: "myotis", "eptesicus", "corynorhinus", "miniopterus", "pipistrellus", "rhinolophus", "lasiurus", "barbastella", "plecotus", "bat", "chiroptera"

3. **Birds (Aves)** - 40+ occurrences
   - Dominant: Anthus (12), Agelaius (12), Vireo (11), Cyanistes (5), Empidonax (5), Setophaga (5)
   - Pattern: "anthus", "agelaius", "vireo", "cyanistes", "empidonax", "setophaga", "bird", "aves"

4. **Ladybugs (Coccinellidae)** - 17 occurrences
   - Genera: Adalia (9), Coccinella (5), Hippodamia (2), Harmonia (1)
   - Pattern: "adalia", "coccinella", "hippodamia", "harmonia", "coccinellidae", "ladybug"

5. **Ground/Rove Beetles (Carabidae/Staphylinidae)** - 7 occurrences
   - Genera: Carabus (4), Pterostichus (2), Abax (1)
   - Pattern: "carabus", "pterostichus", "abax", "carabidae", "staphylinidae"

6. **Predatory Bugs (Hemiptera)** - 4 occurrences
   - Genera: Anthocoris (2), Orius (1), Nabis (1)
   - Pattern: "anthocoris", "orius", "nabis", "geocoris"

7. **Predatory Wasps (Hymenoptera)** - 9 occurrences
   - Genera: Vespula (3), Polistes (2), Vespa (1)
   - Pattern: "vespula", "polistes", "vespa", "dolichovespula"

8. **Other Predators** - All remaining species

### Herbivore Taxonomy (from organism_profiles_pure_r.csv - herbivores column)

**Total unique herbivores analyzed: 2,895 species**

**Major taxonomic groups identified:**

1. **Aphids (Aphididae)** - 234 occurrences
   - Dominant: Aphis (103), Acyrthosiphon (23), Myzus (9), Macrosiphum (7)
   - Pattern: "aphis", "aphid", "myzus", "macrosiphum", "rhopalosiphum", "acyrthosiphon", "aulacorthum", "brachycaudus", "hyperomyzus", "hyadaphis", "aphididae"

2. **Herbivorous Mites (Tetranychidae/Eriophyidae)** - 63 occurrences
   - Dominant: Aceria (61), Tetranychus (2)
   - Pattern: "aceria", "tetranychus", "panonychus", "tetranychidae", "eriophyidae", "eriophyes"

3. **Leaf Miners (Agromyzidae)** - 56 occurrences
   - Dominant: Phytomyza (27), Liriomyza (20), Chromatomyia (2)
   - Pattern: "phytomyza", "liriomyza", "agromyza", "chromatomyia", "agromyzidae", "phytoliriomyza"

4. **Scale Insects (Coccoidea)** - 40 occurrences
   - Dominant: Aspidiotus (26), various Diaspididae
   - Pattern: "aspidiotus", "aonidiella", "diaspidiotus", "pseudococcus", "coccus", "diaspididae", "coccidae", "pseudococcidae", "scale"

5. **Caterpillars (Lepidoptera larvae)** - 23 occurrences
   - Dominant: Heliothis (5), Agrotis (5), Abagrotis (5), Spodoptera (4)
   - Pattern: "spodoptera", "helicoverpa", "heliothis", "plutella", "mamestra", "agrotis"

6. **Thrips (Thysanoptera)** - 22 occurrences
   - Dominant: Akainothrips (7), Heliothrips (2), Frankliniella (1)
   - Pattern: "thrips", "frankliniella", "thysanoptera"

7. **Whiteflies (Aleyrodidae)** - 12 occurrences
   - Dominant: Bemisia (11), Trialeurodes (1)
   - Pattern: "bemisia", "trialeurodes", "aleurodidae", "whitefly"

8. **Herbivorous Beetles** - Low occurrence
   - Pattern: "phyllotreta", "chrysomelidae", "diabrotica", "leptinotarsa", "psylliodes", "cassida", "chrysolina"

9. **Leafhoppers (Cicadellidae)** - Low occurrence
   - Pattern: "empoasca", "cicadellidae", "leafhopper", "erythroneura"

10. **Other Herbivores** - All remaining species

## Proposed Categorization Schemes

### Predators: 8 Categories
1. Spiders (Araneae)
2. Bats (Chiroptera)
3. Birds (Aves)
4. Ladybugs (Coccinellidae)
5. Ground Beetles (Carabidae/Staphylinidae)
6. Predatory Bugs (Hemiptera)
7. Predatory Wasps (Hymenoptera)
8. Other Predators

### Herbivores: 10 Categories
1. Aphids (Aphididae)
2. Mites (Tetranychidae/Eriophyidae)
3. Leaf Miners (Agromyzidae)
4. Scale Insects (Coccoidea)
5. Caterpillars (Lepidoptera larvae)
6. Thrips (Thysanoptera)
7. Whiteflies (Aleyrodidae)
8. Beetles (Chrysomelidae, etc.)
9. Leafhoppers (Cicadellidae)
10. Other Herbivores

## Implementation Plan

### Where Categorization Should Be Implemented

Based on code analysis, categorization should be added to **explanation/analysis modules** ONLY, not to core metrics:

#### R Implementation Files:

1. **`shipley_checks/src/Stage_4/explanation/biocontrol_network_analysis.R`**
   - Add `categorize_predator()` function
   - Add `categorize_herbivore()` function
   - Update `analyze_biocontrol_network()` to use categorization
   - Store categories in network profile output

#### Rust Implementation Files:

1. **`shipley_checks/src/Stage_4/guild_scorer_rust/src/explanation/biocontrol_network_analysis.rs`**
   - Add `PredatorCategory` enum with 8 variants
   - Add `HerbivoreCategory` enum with 10 variants
   - Implement `from_name()` methods for both enums
   - Update `BiocontrolNetworkProfile` struct to include category distributions
   - Update analysis functions to categorize organisms

2. **`shipley_checks/src/Stage_4/guild_scorer_rust/src/explanation/formatters/markdown.rs`**
   - Update biocontrol network formatting to display category breakdowns
   - Add category columns to "Network Hubs" tables

### What Should NOT Be Changed

**DO NOT modify:**
- Core metric calculations (M3, M4 files)
- Scoring logic
- Normalization parameters
- Any parquet/CSV data files
- Database lookup tables (herbivore_predators, etc.)

Categorization is for **qualitative reporting only** to help users understand their guild's biocontrol composition.

## Implementation Details

### Pattern Matching Strategy

Use same approach as pollinator categorization:
- Convert organism name to lowercase
- Check patterns in order from most specific to most general
- First match wins
- Use word boundaries where needed to avoid false matches

### Example R Categorization Function

```r
categorize_predator <- function(name) {
  name_lower <- tolower(name)

  # Spiders - check first (most common)
  if (grepl("aculepeira|agalenatea|argiope|araneus|araneae|spider", name_lower)) {
    return("Spiders")
  }
  # Bats
  if (grepl("myotis|eptesicus|corynorhinus|miniopterus|pipistrellus|bat|chiroptera", name_lower)) {
    return("Bats")
  }
  # Birds
  if (grepl("anthus|agelaius|vireo|bird|aves", name_lower)) {
    return("Birds")
  }
  # ... continue for all categories

  return("Other Predators")
}
```

### Example Rust Categorization Enum

```rust
pub enum PredatorCategory {
    Spiders,
    Bats,
    Birds,
    Ladybugs,
    GroundBeetles,
    PredatoryBugs,
    PredatoryWasps,
    Other,
}

impl PredatorCategory {
    pub fn from_name(name: &str) -> Self {
        let name_lower = name.to_lowercase();

        if name_lower.contains("aculepeira") || name_lower.contains("spider") {
            return PredatorCategory::Spiders;
        }
        // ... continue
    }
}
```

## Expected Output Changes

### Biocontrol Network Profile Section

**Before:**
```markdown
**Total unique biocontrol agents:** 17
- 17 Animal predators
- 0 Entomopathogenic fungi
```

**After:**
```markdown
**Total unique biocontrol agents:** 17
- 17 Animal predators
- 0 Entomopathogenic fungi

**Predator Community Composition:**
- 2 Bats - 11.8%
- 2 Birds - 11.8%
- 1 Ladybugs - 5.9%
- 12 Other Predators - 70.5%

**Herbivore Pest Composition:**
- 3 Aphids - 25.0%
- 2 Caterpillars - 16.7%
- 1 Mites - 8.3%
- 6 Other Herbivores - 50.0%
```

### Matched Pairs Table

**Before:**
```markdown
| Herbivore (Pest) | Known Predator | Match Type |
|------------------|----------------|------------|
| Aphis | Adalia bipunctata | Specific (weight 1.0) |
```

**After:**
```markdown
| Herbivore (Pest) | Herbivore Category | Known Predator | Predator Category | Match Type |
|------------------|-------------------|----------------|-------------------|------------|
| Aphis | Aphids | Adalia bipunctata | Ladybugs | Specific (weight 1.0) |
```

### Network Hubs Table (UNCHANGED)

```markdown
| Plant | Total Predators | Total Fungi | Combined |
|-------|----------------|-------------|----------|
| Fraxinus excelsior | 13 | 0 | 13 |
```

**Note:** Network hubs table remains simple - category breakdowns shown in composition summary above.

## Testing Strategy

1. Run Rust explanations test: `cargo run --bin test_explanations_3_guilds`
2. Verify categorization appears correctly in markdown output
3. Check parity between R and Rust implementations
4. Verify no changes to metric scores (M3/M4 should remain identical)

## Approved Approach

**USER APPROVED:** Implement categorization with:
1. Composition summaries (percentages for each category)
2. Category columns in matched pairs table
3. Keep network hubs table simple (no category columns)
4. Show both predator AND herbivore category compositions

## Implementation Steps

1. ✅ Create and approve plan
2. Implement R categorization functions (`categorize_predator`, `categorize_herbivore`)
3. Implement Rust categorization enums and methods
4. Update R biocontrol network analysis to include categories
5. Update Rust biocontrol network analysis to include categories
6. Update formatters (R and Rust) to display category breakdowns
7. Test explanations and verify output
8. Commit and push changes
