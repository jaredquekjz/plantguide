# M3 and M4 Network Profile Enhancement Plan

## Objective

Add qualitative network analysis profiles for M3 (Natural Insect Pest Control) and M4 (Natural Disease Suppression) to match the detailed network information provided for M1, M5, and M7.

## Current State

**M3 Evidence (current):**
```
Biocontrol score: 100.0/100, covering 5 mechanisms
```
*Note: The "5 mechanisms" is a count of pairwise interactions that fired, not mechanism types*

**M4 Evidence (current):**
```
Pathogen control score: 100.0/100, covering 6 mechanisms
```
*Note: The "6 mechanisms" is a count of pairwise interactions that fired, not mechanism types*

**Problem:** These metrics provide quantitative scores but lack the detailed qualitative breakdown available for other metrics.

## Actual Mechanism Types (from code analysis)

### M3 Has 3 Mechanism Types:
1. **Specific animal predators** - Predators known to target specific herbivores (weight 1.0)
2. **Specific entomopathogenic fungi** - Fungi known to parasitize specific herbivores (weight 1.0)
3. **General entomopathogenic fungi** - Any entomopathogenic fungi (weight 0.2)

### M4 Has 2 Mechanism Types:
1. **Specific mycoparasite antagonists** - Mycoparasites known to target specific pathogens (weight 1.0, RARELY FIRES)
2. **General mycoparasites** - Any mycoparasite fungi (weight 1.0, PRIMARY MECHANISM)

## Available Data Sources

### M3 (Insect Pest Control)

**From organisms DataFrame:**
- Columns: `plant_wfo_id`, `herbivores`, `flower_visitors`, `predators_hasHost`, `predators_interactsWith`, `predators_adjacentTo`
- Format: Pipe-separated strings (e.g., "Aphid1|Aphid2|Beetle3")
- Aggregated into plant → organism lists during metric calculation

**From fungi DataFrame:**
- Column: `entomopathogenic_fungi`
- Format: Pipe-separated strings
- Fungi that parasitize/kill insect herbivores

**Lookup tables (hashmaps):**
- `herbivore_predators: HashMap<String, Vec<String>>` - 934 entries
  - Maps herbivore_name → list of predator species that target it
- `insect_parasites: HashMap<String, Vec<String>>` - 1203 entries
  - Maps herbivore_name → list of entomopathogenic fungi that target it

**Key insight:** The lookup tables tell us WHICH predators/fungi target WHICH herbivores. This allows matching specific biocontrol agents to specific pests.

### M4 (Disease Suppression)

**From fungi DataFrame:**
- Columns: `plant_wfo_id`, `pathogenic_fungi`, `mycoparasite_fungi`
- Format: Pipe-separated strings
- `pathogenic_fungi` - pathogens that attack the plant
- `mycoparasite_fungi` - mycoparasites (fungi that parasitize other fungi)

**Lookup table (hashmap):**
- `pathogen_antagonists: HashMap<String, Vec<String>>` - 942 entries
  - Maps pathogen_name → list of mycoparasite species that target it

**Key insight:** The lookup table tells us WHICH mycoparasites target WHICH pathogens. However, this mechanism rarely fires - most control comes from general mycoparasitism.

## Proposed M3 Profile Structure

### BiocontrolNetworkProfile

**Goal:** Show which plants attract beneficial predators and entomopathogenic fungi, and which biocontrol agents are most connected.

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BiocontrolNetworkProfile {
    // Summary statistics
    pub total_unique_predators: usize,              // Animal predators found
    pub total_unique_entomo_fungi: usize,           // Entomopathogenic fungi found

    // Mechanism breakdown
    pub specific_predator_matches: usize,           // Herbivore → known predator matches
    pub specific_fungi_matches: usize,              // Herbivore → known fungus matches
    pub general_entomo_fungi_count: usize,          // Total entomopathogenic fungi (general)

    // Top biocontrol agents by connectivity (visiting multiple plants)
    pub top_predators: Vec<BiocontrolAgent>,        // Top 10 predators by plant count
    pub top_entomo_fungi: Vec<BiocontrolAgent>,     // Top 10 fungi by plant count

    // Network hubs (plants attracting most biocontrol agents)
    pub hub_plants: Vec<PlantBiocontrolHub>,        // Top 10 plants
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BiocontrolAgent {
    pub agent_name: String,
    pub agent_type: String,                         // "Predator" or "Entomopathogenic Fungus"
    pub plant_count: usize,                         // How many guild plants have this agent
    pub plants: Vec<String>,                        // Plant names (limited to 5 for display)
    pub network_contribution: f64,                  // plant_count / n_plants
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlantBiocontrolHub {
    pub plant_name: String,
    pub total_predators: usize,                     // Predators visiting this plant
    pub total_entomo_fungi: usize,                  // Entomopathogenic fungi on this plant
    pub total_biocontrol_agents: usize,             // Combined total
}
```

**Note:** We won't track individual herbivore → predator/fungus relationships in the profile (too complex). We'll show:
1. How many agents of each type are present
2. Which agents are most connected (generalists)
3. Which plants are biocontrol hubs

## Proposed M4 Profile Structure

### PathogenControlNetworkProfile

**Goal:** Show which plants harbor mycoparasite fungi that can suppress pathogens, and which mycoparasites are most connected.

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PathogenControlNetworkProfile {
    // Summary statistics
    pub total_unique_mycoparasites: usize,          // Total mycoparasite species found
    pub total_unique_pathogens: usize,              // Total pathogen species in guild

    // Mechanism breakdown (only 2 types)
    pub specific_antagonist_matches: usize,         // Pathogen → known mycoparasite matches
    pub general_mycoparasite_count: usize,          // All mycoparasites (primary mechanism)

    // Top mycoparasites by connectivity (visiting multiple plants)
    pub top_mycoparasites: Vec<MycoparasiteAgent>,  // Top 10 by plant count

    // Network hubs (plants harboring most mycoparasites)
    pub hub_plants: Vec<PlantPathogenControlHub>,   // Top 10 plants
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MycoparasiteAgent {
    pub mycoparasite_name: String,
    pub plant_count: usize,                         // How many guild plants harbor this mycoparasite
    pub plants: Vec<String>,                        // Plant names (limited to 5 for display)
    pub network_contribution: f64,                  // plant_count / n_plants
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlantPathogenControlHub {
    pub plant_name: String,
    pub mycoparasite_count: usize,                  // Mycoparasites on this plant
    pub pathogen_count: usize,                      // Pathogens attacking this plant
}
```

**Note:** Since mycoparasitism is the only mechanism (specific or general), we won't break down by mechanism type. We'll show:
1. How many mycoparasites and pathogens are present
2. Which mycoparasites are most connected (generalists)
3. Which plants are mycoparasite hubs (providing protection to others)

## Implementation Approach

### Phase 1: Data Exploration

1. **Examine datasets:**
   ```bash
   # Check column structure
   duckdb -c "DESCRIBE SELECT * FROM read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_11711.parquet')"

   # Sample predator data
   duckdb -c "SELECT plant_wfo_id, predator_name, pest_target FROM read_parquet('...') WHERE predator_name IS NOT NULL LIMIT 20"

   # Sample parasite data
   duckdb -c "SELECT plant_wfo_id, parasite_name, pest_target FROM read_parquet('...') WHERE parasite_name IS NOT NULL LIMIT 20"

   # Sample antagonist data
   duckdb -c "SELECT plant_wfo_id, antagonist_name, pathogen_target, mechanism FROM read_parquet('...') WHERE antagonist_name IS NOT NULL LIMIT 20"
   ```

2. **Understand interaction format:**
   - Are interactions stored as comma-separated lists?
   - How are mechanisms encoded?
   - What are the possible mechanism values?

### Phase 2: M3 Implementation

1. **Create module:** `src/explanation/biocontrol_network_analysis.rs`
   - Define all structs
   - Implement `analyze_biocontrol_network()` function
   - Parse predator and parasitoid data
   - Build network mappings
   - Identify shared agents and hubs

2. **Update M3Result:** `src/metrics/m3_insect_control.rs`
   - Add `predator_counts: FxHashMap<String, usize>`
   - Add `parasitoid_counts: FxHashMap<String, usize>`
   - Store during metric calculation

3. **Update Explanation type:** `src/explanation/types.rs`
   - Add `biocontrol_network_profile: Option<BiocontrolNetworkProfile>`

4. **Update ExplanationGenerator:** `src/explanation/generator.rs`
   - Accept M3Result and predators/parasites DataFrames
   - Call `analyze_biocontrol_network()`
   - Include in Explanation

5. **Update Scorer:** `src/scorer.rs`
   - Return M3Result (with counts)
   - Pass to generator

6. **Add formatter:** `src/explanation/formatters/markdown.rs`
   - Create `format_biocontrol_profile()` helper
   - Insert after M3 benefit card

### Phase 3: M4 Implementation

1. **Create module:** `src/explanation/pathogen_control_network_analysis.rs`
   - Define all structs
   - Implement `analyze_pathogen_control_network()` function
   - Parse antagonist data
   - Categorize by mechanism
   - Build network mappings
   - Identify shared antagonists and hubs

2. **Update M4Result:** `src/metrics/m4_disease_suppression.rs`
   - Add `antagonist_counts: FxHashMap<String, usize>`
   - Add `mechanism_counts: FxHashMap<String, usize>`
   - Store during metric calculation

3. **Update Explanation type:** `src/explanation/types.rs`
   - Add `pathogen_control_profile: Option<PathogenControlNetworkProfile>`

4. **Update ExplanationGenerator:** `src/explanation/generator.rs`
   - Accept M4Result and antagonists DataFrame
   - Call `analyze_pathogen_control_network()`
   - Include in Explanation

5. **Update Scorer:** `src/scorer.rs`
   - Return M4Result (with counts)
   - Pass to generator

6. **Add formatter:** `src/explanation/formatters/markdown.rs`
   - Create `format_pathogen_control_profile()` helper
   - Insert after M4 benefit card

### Phase 4: Testing and Validation

1. **Unit tests:** Test parsing and categorization logic
2. **Integration tests:** Run 3-guild test suite
3. **Verify output:** Check markdown formatting
4. **Performance:** Ensure minimal overhead (<2ms per guild)

## Expected Markdown Output Format

### M3 Biocontrol Network Profile

```markdown
#### Biocontrol Network Profile

*Qualitative information about insect pest control (influences M3 scoring)*

**Total unique biocontrol agents:** 247
- 142 Animal predators
- 105 Entomopathogenic fungi

**Mechanism Summary:**
- 23 Specific predator matches (herbivore → known predator)
- 17 Specific fungi matches (herbivore → known entomopathogenic fungus)
- 105 General entomopathogenic fungi interactions

**Top Animal Predators (by connectivity):**

| Rank | Predator Species | Plants Visited | Network Contribution |
|------|------------------|----------------|----------------------|
| 1 | Coccinella septempunctata | 8 plants | 80.0% |
| 2 | Chrysoperla carnea | 7 plants | 70.0% |
...

**Top Entomopathogenic Fungi (by connectivity):**

| Rank | Fungus Species | Plants Hosting | Network Contribution |
|------|----------------|----------------|----------------------|
| 1 | Beauveria bassiana | 9 plants | 90.0% |
| 2 | Metarhizium anisopliae | 7 plants | 70.0% |
...

**Network Hubs (plants attracting most biocontrol):**

| Plant | Total Predators | Total Fungi | Combined |
|-------|----------------|-------------|----------|
| Solanum lycopersicum | 28 | 17 | 45 |
...
```

### M4 Pathogen Control Profile

```markdown
#### Pathogen Control Network Profile

*Qualitative information about disease suppression (influences M4 scoring)*

**Summary:**
- 89 unique mycoparasite species (fungi that parasitize other fungi)
- 134 unique pathogen species in guild

**Mechanism Summary:**
- 8 Specific antagonist matches (pathogen → known mycoparasite)
- 89 General mycoparasite fungi (primary mechanism)

**Top Mycoparasites (by connectivity):**

| Rank | Mycoparasite Species | Plants Hosting | Network Contribution |
|------|---------------------|----------------|----------------------|
| 1 | Trichoderma harzianum | 9 plants | 90.0% |
| 2 | Trichoderma viride | 8 plants | 80.0% |
| 3 | Clonostachys rosea | 7 plants | 70.0% |
...

**Network Hubs (plants harboring most mycoparasites):**

| Plant | Mycoparasites | Pathogens |
|-------|---------------|-----------|
| Solanum lycopersicum | 32 | 18 |
| Brassica oleracea | 28 | 15 |
...
```

## Data Confirmed from Code Analysis

**M3 data structure (verified from m3_insect_control.rs):**
- **organisms DataFrame columns:** `plant_wfo_id`, `herbivores`, `flower_visitors`, `predators_hasHost`, `predators_interactsWith`, `predators_adjacentTo`
- **fungi DataFrame column:** `entomopathogenic_fungi`
- **Format:** Pipe-separated strings (e.g., "Aphid1|Beetle2|Fly3")
- **Lookup tables:** Already loaded as HashMaps in GuildData

**M4 data structure (verified from m4_disease_control.rs):**
- **fungi DataFrame columns:** `plant_wfo_id`, `pathogenic_fungi`, `mycoparasite_fungi`
- **Format:** Pipe-separated strings
- **Lookup table:** Already loaded as HashMap in GuildData

**Plant matching:**
- Use `plant_wfo_id` column (consistent across all DataFrames)
- WFO IDs are strings matching the guild plant IDs

## Success Criteria

1. **Completeness:** All guilds show biocontrol and pathogen control profiles when agents are present
2. **Accuracy:** Network statistics correctly calculated (shared agents, hubs, mechanisms)
3. **Parity:** R and Rust maintain perfect parity (profiles don't affect scores)
4. **Performance:** <2ms overhead per profile analysis
5. **Clarity:** Markdown output is clear, well-formatted, and informative
6. **Consistency:** Follows same pattern as M1/M5/M7 profiles

## Files to Create/Modify

**New files:**
- `src/explanation/biocontrol_network_analysis.rs` (~500 lines)
- `src/explanation/pathogen_control_network_analysis.rs` (~500 lines)

**Modified files:**
- `src/metrics/m3_insect_control.rs` - Add counts to M3Result
- `src/metrics/m4_disease_suppression.rs` - Add counts to M4Result
- `src/explanation/types.rs` - Add profile fields
- `src/explanation/generator.rs` - Call analysis functions
- `src/explanation/mod.rs` - Export new modules
- `src/scorer.rs` - Return M3/M4 results and datasets
- `src/explanation/formatters/markdown.rs` - Add two helper functions
- `src/bin/test_explanations_3_guilds.rs` - Update destructuring

## Estimated Effort

- M3 implementation: 1.5 hours (simpler than originally planned)
- M4 implementation: 1 hour (simpler than originally planned)
- Testing and refinement: 30 minutes
- **Total: ~3 hours**

(Faster than original estimate because data structure is well-understood and simpler than initially thought)

## Implementation Summary

**What we're building:**
1. Extract predator and entomopathogenic fungus lists from organisms/fungi DataFrames
2. Count unique agents and identify which plants harbor them
3. Find "generalist" agents that visit/protect multiple plants
4. Identify "hub" plants that attract many biocontrol agents or mycoparasites
5. Display this qualitative information after M3 and M4 benefit cards

**What we're NOT building:**
- Complex mechanism categorization (only 3 types for M3, 2 for M4)
- Individual herbivore → predator/fungus tracking (too complex for profile display)
- New scoring logic (this is purely qualitative display)

**Key insight:**
These profiles will help users understand:
- M3: "Which plants attract beneficial predators and fungi?"
- M4: "Which plants harbor disease-suppressing mycoparasites?"

This makes the guild scoring more actionable by showing WHICH organisms provide the benefits.

## Next Steps

1. Implement M3 profile module (biocontrol_network_analysis.rs)
2. Implement M4 profile module (pathogen_control_network_analysis.rs)
3. Update M3/M4 metric results to store counts
4. Wire up to explanation generator
5. Add markdown formatters
6. Test with 3-guild suite
7. Verify parity maintained (profiles don't affect scores)
8. Commit changes
