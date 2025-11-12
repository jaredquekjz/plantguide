# Pollinator and Fungi Profile Enhancement Plan

## Overview

Currently, M5 (Beneficial Fungi) and M7 (Pollinator Support) only show aggregate counts (e.g., "147 shared mycorrhizal fungal species"). This plan enhances explanations by showing:

1. **Top shared organisms** ranked by interaction strength (plant count or quadratic contribution)
2. **Featured fungi categorization** (AMF, EMF, endophytic, saprotrophic)
3. **Per-plant breakdowns** showing which plants host which organisms

This mirrors the pest profile analysis but with focus on beneficial organisms and their network effects.

---

## Current State Analysis

### M5 Beneficial Fungi (Current Output)
```
147 shared mycorrhizal fungal species connect 5 plants
Network score: 97.7/100, coverage: 71.4%
```

**Missing information:**
- Which fungi are most broadly shared (generalists)?
- What types of fungi dominate (AMF vs EMF vs endophytic vs saprotrophic)?
- Which plants are the most connected network hubs?
- Top 10 most important fungi by network contribution

### M7 Pollinator Support (Current Output)
```
170 shared pollinator species
Pollinator support score: 92.0/100
```

**Missing information:**
- Which pollinators are most broadly shared (keystone species)?
- Top 10 pollinators by quadratic contribution
- Which plants attract the most pollinators?
- Which plants are the most important network hubs?

---

## Data Availability

### M5 Fungi Calculation (Existing)
- **Input DataFrame**: `fungi_df`
- **Columns**: `["amf_fungi", "emf_fungi", "endophytic_fungi", "saprotrophic_fungi"]`
- **Key column**: `plant_wfo_id` for joining
- **Output**: `count_shared_organisms()` → `FxHashMap<String, usize>` (fungus_name → plant_count)

### M7 Pollinator Calculation (Existing)
- **Input DataFrame**: `organisms_df`
- **Columns**: `["pollinators", "flower_visitors"]`
- **Key column**: `plant_wfo_id` for joining
- **Output**: `count_shared_organisms()` → `FxHashMap<String, usize>` (pollinator_name → plant_count)

---

## Proposed Data Structures

### 1. Fungi Network Profile

```rust
/// Detailed fungi network analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FungiNetworkProfile {
    /// Total unique beneficial fungi species
    pub total_unique_fungi: usize,

    /// Shared fungi (connecting 2+ plants)
    pub shared_fungi: Vec<SharedFungus>,

    /// Top 10 fungi by network contribution (plant_count / n_plants)
    pub top_fungi: Vec<TopFungus>,

    /// Featured fungi by category
    pub fungi_by_category: FungiByCategoryProfile,

    /// Plants ranked by fungal connectivity
    pub hub_plants: Vec<PlantFungalHub>,
}

/// A fungus shared by multiple plants
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharedFungus {
    pub fungus_name: String,
    pub plant_count: usize,
    pub plants: Vec<String>,
    pub category: FungusCategory,
    /// Network contribution (plant_count / n_plants)
    pub network_contribution: f64,
}

/// Top fungus by network importance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopFungus {
    pub fungus_name: String,
    pub plant_count: usize,
    pub plants: Vec<String>,
    pub category: FungusCategory,
    pub network_contribution: f64,
}

/// Fungus category
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum FungusCategory {
    AMF,           // Arbuscular Mycorrhizal Fungi
    EMF,           // Ectomycorrhizal Fungi
    Endophytic,    // Endophytic fungi
    Saprotrophic,  // Saprotrophic fungi
}

/// Fungi categorized by type
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FungiByCategoryProfile {
    pub amf_count: usize,
    pub emf_count: usize,
    pub endophytic_count: usize,
    pub saprotrophic_count: usize,
    /// Most connected fungus in each category
    pub top_per_category: Vec<TopFungusInCategory>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopFungusInCategory {
    pub category: FungusCategory,
    pub fungus_name: String,
    pub plant_count: usize,
}

/// Plant ranked by fungal connectivity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlantFungalHub {
    pub plant_name: String,
    pub fungus_count: usize,
    pub amf_count: usize,
    pub emf_count: usize,
    pub endophytic_count: usize,
    pub saprotrophic_count: usize,
}
```

### 2. Pollinator Network Profile

```rust
/// Detailed pollinator network analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PollinatorNetworkProfile {
    /// Total unique pollinator species
    pub total_unique_pollinators: usize,

    /// Shared pollinators (visiting 2+ plants)
    pub shared_pollinators: Vec<SharedPollinator>,

    /// Top 10 pollinators by quadratic contribution
    pub top_pollinators: Vec<TopPollinator>,

    /// Plants ranked by pollinator attraction
    pub hub_plants: Vec<PlantPollinatorHub>,
}

/// A pollinator visiting multiple plants
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharedPollinator {
    pub pollinator_name: String,
    pub plant_count: usize,
    pub plants: Vec<String>,
    /// Quadratic contribution (plant_count/n_plants)²
    pub quadratic_contribution: f64,
}

/// Top pollinator by quadratic importance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopPollinator {
    pub pollinator_name: String,
    pub plant_count: usize,
    pub plants: Vec<String>,
    pub quadratic_contribution: f64,
}

/// Plant ranked by pollinator attraction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlantPollinatorHub {
    pub plant_name: String,
    pub pollinator_count: usize,
}
```

---

## Implementation Steps

### Phase 1: Update M5Result and M7Result

**Modify M5Result** in `metrics/m5_beneficial_fungi.rs`:
```rust
pub struct M5Result {
    pub raw: f64,
    pub norm: f64,
    pub network_score: f64,
    pub coverage_ratio: f64,
    pub n_shared_fungi: usize,
    pub plants_with_fungi: usize,
    // NEW: detailed organism map for profile analysis
    pub fungi_counts: FxHashMap<String, usize>,
}
```

**Modify M7Result** in `metrics/m7_pollinator_support.rs`:
```rust
pub struct M7Result {
    pub raw: f64,
    pub norm: f64,
    pub n_shared_pollinators: usize,
    // NEW: detailed organism map for profile analysis
    pub pollinator_counts: FxHashMap<String, usize>,
}
```

**Return organism maps** from calculations:
- `calculate_m5()` should return `beneficial_counts` in M5Result
- `calculate_m7()` should return `shared_pollinators` in M7Result

### Phase 2: Create Analysis Modules

**Create `explanation/fungi_network_analysis.rs`:**
```rust
pub fn analyze_fungi_network(
    m5: &M5Result,
    guild_plants: &DataFrame,
    fungi_df: &DataFrame,
    n_plants: usize,
) -> Result<Option<FungiNetworkProfile>>
```

**Implementation:**
1. Extract fungi-to-plants mapping from `m5.fungi_counts`
2. For each fungus, determine category (AMF/EMF/endophytic/saprotrophic) by checking which column it came from
3. Calculate network contribution: `plant_count / n_plants`
4. Build SharedFungus and TopFungus lists with deterministic sorting
5. Categorize fungi by type, count each category
6. Find top fungus per category (most connected)
7. Build per-plant fungal counts by querying fungi_df for each guild plant

**Create `explanation/pollinator_network_analysis.rs`:**
```rust
pub fn analyze_pollinator_network(
    m7: &M7Result,
    guild_plants: &DataFrame,
    organisms_df: &DataFrame,
    n_plants: usize,
) -> Result<Option<PollinatorNetworkProfile>>
```

**Implementation:**
1. Extract pollinator-to-plants mapping from `m7.pollinator_counts`
2. Calculate quadratic contribution: `(plant_count / n_plants)²`
3. Build SharedPollinator and TopPollinator lists sorted by quadratic contribution desc
4. Build per-plant pollinator counts by querying organisms_df for each guild plant

### Phase 3: Extend Explanation Type

**Modify `explanation/types.rs`:**
```rust
pub struct Explanation {
    pub overall: OverallExplanation,
    pub climate: ClimateExplanation,
    pub benefits: Vec<BenefitCard>,
    pub warnings: Vec<WarningCard>,
    pub risks: Vec<RiskCard>,
    pub metrics_display: MetricsDisplay,
    pub pest_profile: Option<PestProfile>,
    // NEW
    pub fungi_network_profile: Option<FungiNetworkProfile>,
    pub pollinator_network_profile: Option<PollinatorNetworkProfile>,
}
```

### Phase 4: Update Fragments

**Enhance M5 fragment** (`fragments/m5_fragment.rs`):
- Add detailed breakdown showing top 10 fungi with categories and plant counts
- Show categorization: "X AMF, Y EMF, Z endophytic, W saprotrophic"
- Highlight top fungus per category
- Add to `evidence` field

**Example enhanced detail:**
```
**Top Network Contributors:**
1. Rhizophagus irregularis (AMF): connects 5/7 plants (71%)
2. Glomus mosseae (AMF): connects 4/7 plants (57%)
3. Laccaria bicolor (EMF): connects 3/7 plants (43%)
...

**Fungal Diversity:**
- 85 AMF species (58%)
- 40 EMF species (27%)
- 15 endophytic species (10%)
- 7 saprotrophic species (5%)

**Network Hubs:**
- Fraxinus excelsior: 62 fungal associations (42 AMF, 20 EMF)
- Diospyros kaki: 48 fungal associations (40 AMF, 8 EMF)
```

**Enhance M7 fragment** (`fragments/m7_fragment.rs`):
- Add detailed breakdown showing top 10 pollinators with quadratic contributions
- Show which plants each pollinator visits
- Highlight keystone pollinators (highest quadratic contribution)

**Example enhanced detail:**
```
**Top Pollinators (by network importance):**
1. Apis mellifera: visits 6/7 plants (73.5% quadratic contribution)
2. Bombus terrestris: visits 5/7 plants (51.0% quadratic contribution)
3. Lasioglossum malachurum: visits 4/7 plants (32.7% quadratic contribution)
...

**Pollinator Attraction Hubs:**
- Fraxinus excelsior: 95 pollinator species
- Diospyros kaki: 58 pollinator species
- Deutzia scabra: 42 pollinator species
```

### Phase 5: Update Formatters

**Markdown formatter** (`formatters/markdown.rs`):
- Add "## Fungi Network Profile" section after Benefits
- Add "## Pollinator Network Profile" section after Fungi
- Both placed before Pest Vulnerability Profile

**JSON formatter**: Already auto-serializes new fields

**HTML formatter**: Add styled sections for networks

### Phase 6: Update Scorer

**Modify `scorer.rs::score_guild_with_explanation_parallel()`:**
- Already returns `guild_plants` DataFrame
- Need to pass `fungi_df` and `organisms_df` to explanation generator
- Or: join relevant columns from these DataFrames into `guild_plants_with_organisms`

**Option A** (simpler): Pass DataFrames to generator:
```rust
pub fn generate(
    guild_score: &GuildScore,
    guild_plants: &DataFrame,
    fungi_df: &DataFrame,        // NEW
    organisms_df: &DataFrame,     // NEW
    climate_tier: &str,
    fragments: Vec<MetricFragment>,
    m5_result: &M5Result,         // NEW
    m7_result: &M7Result,         // NEW
) -> Result<Explanation>
```

**Option B** (cleaner): Join all needed columns upfront in scorer

---

## Example Output

### Forest Garden - Enhanced M5 Output

```markdown
### Beneficial Mycorrhizal Network [M5]

147 shared fungal species connect 5 plants (71% coverage)

**Fungal Community Composition:**
- 85 AMF species (Arbuscular Mycorrhizal) - 58%
- 40 EMF species (Ectomycorrhizal) - 27%
- 15 Endophytic species - 10%
- 7 Saprotrophic species - 5%

**Top Network Fungi (by connectivity):**

| Rank | Fungus Species | Category | Plants Connected | Contribution |
|------|----------------|----------|------------------|--------------|
| 1 | Rhizophagus irregularis | AMF | 5 plants (Fraxinus, Diospyros, Deutzia, Anaphalis, Mercurialis) | 71% |
| 2 | Glomus mosseae | AMF | 4 plants (Fraxinus, Diospyros, Deutzia, Mercurialis) | 57% |
| 3 | Laccaria bicolor | EMF | 3 plants (Fraxinus, Deutzia, Mercurialis) | 43% |
| 4 | Glomus intraradices | AMF | 3 plants | 43% |
| 5 | Paxillus involutus | EMF | 3 plants | 43% |
| 6-10 | ... | ... | ... | ... |

**Network Hubs (most connected plants):**

| Plant | Total Fungi | AMF | EMF | Endophytic | Saprotrophic |
|-------|-------------|-----|-----|------------|--------------|
| Fraxinus excelsior | 62 | 42 | 18 | 2 | 0 |
| Diospyros kaki | 48 | 40 | 6 | 2 | 0 |
| Deutzia scabra | 35 | 28 | 5 | 2 | 0 |
| Mercurialis perennis | 22 | 15 | 7 | 0 | 0 |
| Anaphalis margaritacea | 18 | 12 | 4 | 2 | 0 |

*Evidence:* Network score: 97.7/100, coverage: 71.4%
```

### Forest Garden - Enhanced M7 Output

```markdown
### Robust Pollinator Support [M7]

170 shared pollinator species

**Top Pollinators (by quadratic network contribution):**

| Rank | Pollinator Species | Plants Visited | Quadratic Contribution |
|------|-------------------|----------------|------------------------|
| 1 | Apis mellifera | 6 plants (Fraxinus, Diospyros, Deutzia, Anaphalis, Rubus, Maianthemum) | 0.735 (73.5%) |
| 2 | Bombus terrestris | 5 plants (Fraxinus, Diospyros, Deutzia, Rubus, Maianthemum) | 0.510 (51.0%) |
| 3 | Lasioglossum malachurum | 4 plants | 0.327 (32.7%) |
| 4 | Andrena haemorrhoa | 4 plants | 0.327 (32.7%) |
| 5 | Osmia bicornis | 4 plants | 0.327 (32.7%) |
| 6-10 | ... | ... | ... |

**Pollinator Attraction Hubs:**

| Plant | Pollinator Count |
|-------|------------------|
| Fraxinus excelsior | 95 |
| Diospyros kaki | 58 |
| Deutzia scabra | 42 |
| Rubus moorei | 38 |
| Anaphalis margaritacea | 32 |

*Evidence:* Pollinator support score: 92.0/100
```

---

## Technical Considerations

### 1. Performance
- Analysis happens AFTER scoring (not in parallel metrics)
- Only triggered when explanation is generated
- Uses existing HashMap data, minimal overhead
- Expected time: ~5-10ms per guild

### 2. Fungus Category Detection
Need to determine which column each fungus came from:
- Parse `fungi_df` with filter to guild plants
- For each fungus name, check which column(s) it appears in
- If appears in multiple columns, categorize by first occurrence
- Cache category mapping for performance

**Implementation approach:**
```rust
fn categorize_fungi(
    fungi_df: &DataFrame,
    plant_ids: &[String],
) -> Result<FxHashMap<String, FungusCategory>> {
    let mut category_map = FxHashMap::default();
    let columns = [
        ("amf_fungi", FungusCategory::AMF),
        ("emf_fungi", FungusCategory::EMF),
        ("endophytic_fungi", FungusCategory::Endophytic),
        ("saprotrophic_fungi", FungusCategory::Saprotrophic),
    ];

    // Filter to guild plants
    // For each column, parse fungi and map to category
    // Return HashMap<fungus_name, category>
}
```

### 3. Quadratic Contribution Display
For M7, contribution = `(plant_count / n_plants)²`
- Display both as fraction (0.735) and percentage (73.5%)
- Sort by quadratic contribution descending
- This reflects actual scoring mechanism

### 4. Data Joining Strategy
**Recommended: Option A** (pass DataFrames)
- Cleaner separation of concerns
- Analysis functions can query full DataFrames
- No need to pre-join all columns (memory efficient)

### 5. Test Data Availability
Verify that:
- `fungi_df` has category columns populated for test guilds
- `organisms_df` has pollinators/flower_visitors for test guilds
- Can extract per-plant fungal/pollinator counts

---

## Testing Strategy

### Unit Tests
1. **Fungi categorization**: Verify correct category assignment
2. **Network contribution calculation**: Test arithmetic
3. **Sorting**: Verify deterministic ordering (contribution desc, name asc)
4. **Hub plant ranking**: Verify count aggregation

### Integration Tests
Run on 3 test guilds:
1. **Forest Garden**: Expect high fungi diversity, high pollinator overlap
2. **Competitive Clash**: Expect moderate diversity
3. **Stress-Tolerant**: Expect low diversity, sparse networks

### Validation
- Cross-check M5 raw score with sum of network contributions
- Cross-check M7 raw score with sum of quadratic contributions
- Verify coverage ratio matches plants_with_fungi count

---

## Dependencies

No new external dependencies needed. Uses existing:
- `rustc_hash::FxHashMap`
- `serde::{Serialize, Deserialize}`
- `polars::prelude::*`

---

## Timeline Estimate

1. **Phase 1** (Update Results): 30 minutes
2. **Phase 2** (Analysis modules): 2-3 hours
3. **Phase 3** (Extend Explanation): 30 minutes
4. **Phase 4** (Update fragments): 1 hour
5. **Phase 5** (Update formatters): 1-2 hours
6. **Phase 6** (Update scorer/generator): 1 hour
7. **Testing & refinement**: 1-2 hours

**Total: 7-10 hours**

---

## Open Questions

1. **Fungi column availability**: Are category columns (AMF, EMF, etc.) populated in parquet files?
2. **Display limits**: Show top 10 or top 20 organisms?
3. **Hub plant threshold**: Show all plants or only top 5 most connected?
4. **Placement**: Should network profiles be in Benefits detail or separate sections?
5. **Unique pollinators**: Should we also show pollinators visiting only 1 plant (specialists)?

---

## Success Criteria

1. ✅ M5 explanation shows fungal diversity by category
2. ✅ M5 explanation shows top 10 network fungi with categories
3. ✅ M5 explanation shows hub plants with per-category counts
4. ✅ M7 explanation shows top 10 pollinators with quadratic contributions
5. ✅ M7 explanation shows hub plants by pollinator attraction
6. ✅ All tests pass with deterministic output
7. ✅ Explanations generated for 3 test guilds show meaningful differences
8. ✅ Output is readable and actionable for gardeners
