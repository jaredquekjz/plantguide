# Implementation Plan: Zero-Interaction Data Quality Flags

## Problem Statement

Currently, plants with zero interactions in a specific dimension (fungi, pollinators, predators, pathogens) are **excluded** from network hub tables. This creates ambiguity:
- Does zero mean "no ecological associations"?
- Or does it mean "no data available in GloBI"?

Users cannot distinguish between data gaps and true ecological patterns.

## Solution

Add explicit data quality flags for plants with zero interactions, displaying them in network hub tables with:
1. Scientific name + vernacular name (English and/or Chinese)
2. Visual indicator for "no data available"

## Scope

Apply to all 4 network profile types:
- **M5**: Beneficial Fungi Network
- **M7**: Pollinator Network
- **M3**: Biocontrol Network (predators + entomopathogenic fungi)
- **M4**: Pathogen Control Network (mycoparasites + pathogens)

## Implementation Steps

### Phase 1: Update Data Structures

#### 1.1 Modify PlantHub Structs

Add fields to each hub struct in their respective analysis modules:

**File:** `src/explanation/fungi_network_analysis.rs`
```rust
pub struct PlantFungalHub {
    pub plant_name: String,           // Scientific name (existing)
    pub plant_vernacular: String,     // NEW: Vernacular name (EN/ZH)
    pub fungus_count: usize,
    pub amf_count: usize,
    pub emf_count: usize,
    pub endophytic_count: usize,
    pub saprotrophic_count: usize,
    pub has_data: bool,               // NEW: false if all counts are zero
}
```

**File:** `src/explanation/pollinator_network_analysis.rs`
```rust
pub struct PollinatorPlantHub {
    pub plant_name: String,
    pub plant_vernacular: String,     // NEW
    pub pollinator_count: usize,
    // ... (all pollinator category counts)
    pub has_data: bool,               // NEW
}
```

**File:** `src/explanation/biocontrol_network_analysis.rs`
```rust
pub struct BiocontrolPlantHub {
    pub plant_name: String,
    pub plant_vernacular: String,     // NEW
    pub total_predators: usize,
    pub total_entomo_fungi: usize,
    pub total_biocontrol_agents: usize,
    pub has_data: bool,               // NEW
}
```

**File:** `src/explanation/pathogen_control_network_analysis.rs`
```rust
pub struct PathogenControlPlantHub {
    pub plant_name: String,
    pub plant_vernacular: String,     // NEW
    pub mycoparasite_count: usize,
    pub pathogen_count: usize,
    pub has_data: bool,               // NEW
}
```

#### 1.2 Extract Vernacular Names

Add helper function to extract vernacular names from guild DataFrame:

```rust
/// Build plant display map (WFO ID -> (scientific, vernacular))
fn build_plant_display_map(guild_plants: &DataFrame) -> Result<FxHashMap<String, (String, String)>> {
    let plant_id_col = guild_plants.column("wfo_taxon_id")?.str()?;
    let scientific_col = guild_plants.column("wfo_scientific_name")?.str()?;

    // Try display_name_en first, fall back to display_name_zh, then empty string
    let vernacular_col = if let Ok(col) = guild_plants.column("display_name_en") {
        col.str()?.clone()
    } else if let Ok(col) = guild_plants.column("display_name_zh") {
        col.str()?.clone()
    } else {
        return Ok(FxHashMap::default()); // No vernacular columns available
    };

    let mut map = FxHashMap::default();
    for idx in 0..guild_plants.height() {
        if let (Some(id), Some(sci), Some(vern)) = (
            plant_id_col.get(idx),
            scientific_col.get(idx),
            vernacular_col.get(idx)
        ) {
            map.insert(
                id.to_string(),
                (sci.to_string(), vern.to_string())
            );
        }
    }
    Ok(map)
}
```

### Phase 2: Update Analysis Functions

#### 2.1 Fungi Network Analysis

**File:** `src/explanation/fungi_network_analysis.rs`

Modify `build_plant_fungal_hubs` function:

```rust
fn build_plant_fungal_hubs(
    guild_plants: &DataFrame,
    fungi_df: &DataFrame,
    category_map: &FxHashMap<String, FungusCategory>,
) -> Result<Vec<PlantFungalHub>> {
    // Get plant display map (scientific + vernacular)
    let plant_display_map = build_plant_display_map(guild_plants)?;

    // Get all guild plant IDs
    let plant_ids = guild_plants.column("wfo_taxon_id")?.str()?;
    let all_guild_plants: Vec<String> = plant_ids
        .into_iter()
        .filter_map(|opt| opt.map(|s| s.to_string()))
        .collect();

    // Count fungi for plants WITH data
    let mut plant_fungi_counts: FxHashMap<String, (usize, usize, usize, usize, usize)> =
        FxHashMap::default();

    // ... (existing counting logic) ...

    // Build hubs for ALL guild plants (including zeros)
    let mut hubs: Vec<PlantFungalHub> = all_guild_plants
        .into_iter()
        .map(|plant_id| {
            let (total, amf, emf, endo, sapro) = plant_fungi_counts
                .get(&plant_id)
                .cloned()
                .unwrap_or((0, 0, 0, 0, 0));

            let (scientific, vernacular) = plant_display_map
                .get(&plant_id)
                .cloned()
                .unwrap_or_else(|| (plant_id.clone(), String::new()));

            PlantFungalHub {
                plant_name: scientific,
                plant_vernacular: vernacular,
                fungus_count: total,
                amf_count: amf,
                emf_count: emf,
                endophytic_count: endo,
                saprotrophic_count: sapro,
                has_data: total > 0,
            }
        })
        .collect();

    // Sort by total count desc, then name asc
    hubs.sort_by(|a, b| {
        b.fungus_count
            .cmp(&a.fungus_count)
            .then_with(|| a.plant_name.cmp(&b.plant_name))
    });

    Ok(hubs)
}
```

#### 2.2 Apply Same Pattern to Other Networks

Repeat the pattern for:
- `pollinator_network_analysis.rs` → `build_pollinator_plant_hubs`
- `biocontrol_network_analysis.rs` → `build_biocontrol_plant_hubs`
- `pathogen_control_network_analysis.rs` → `build_pathogen_control_plant_hubs`

### Phase 3: Update Markdown Formatters

**File:** `src/explanation/formatters/markdown.rs`

#### 3.1 Fungi Profile (M5)

Modify lines 257-273:

```rust
// Network hubs
if !fungi_profile.hub_plants.is_empty() {
    md.push_str("**Network Hubs (most connected plants):**\n\n");
    md.push_str("| Plant | Total Fungi | AMF | EMF | Endophytic | Saprotrophic |\n");
    md.push_str("|-------|-------------|-----|-----|------------|---------------|\n");
    for hub in fungi_profile.hub_plants.iter().take(10) {
        // Format display name
        let display_name = if !hub.plant_vernacular.is_empty() {
            format!("{} ({})", hub.plant_name, hub.plant_vernacular)
        } else {
            hub.plant_name.clone()
        };

        // Add ⚠️ flag if no data
        let display_name = if !hub.has_data {
            format!("{} ⚠️", display_name)
        } else {
            display_name
        };

        md.push_str(&format!(
            "| {} | {} | {} | {} | {} | {} |\n",
            display_name,
            hub.fungus_count,
            hub.amf_count,
            hub.emf_count,
            hub.endophytic_count,
            hub.saprotrophic_count
        ));
    }
    md.push_str("\n");

    // Add footnote if any plants have no data
    if fungi_profile.hub_plants.iter().any(|h| !h.has_data) {
        md.push_str("⚠️ **Data Completeness Note:** Plants marked with ⚠️ have no interaction data in this dimension. This likely indicates a data gap rather than true ecological absence.\n\n");
    }
}
```

#### 3.2 Apply Same Pattern to Other Profiles

Update formatting in:
- `format_pollinator_profile` (lines 396-424)
- `format_biocontrol_profile` (lines 528-542)
- `format_pathogen_control_profile` (lines 623-636)

### Phase 4: Testing

#### 4.1 Unit Tests

Add tests to each analysis module:

```rust
#[test]
fn test_zero_interaction_plants_included() {
    // Create guild with 3 plants
    // Only 1 plant has fungi data
    // Verify all 3 plants appear in hub_plants
    // Verify zero-count plants have has_data = false
}

#[test]
fn test_vernacular_names_extracted() {
    // Create guild with vernacular names
    // Verify plant_vernacular field populated correctly
}
```

#### 4.2 Integration Test

Run test guild generation:
```bash
cd shipley_checks/src/Stage_4/guild_scorer_rust
cargo build
cargo run --bin test_3_guilds_parallel
```

Verify in generated reports:
- All guild plants appear in network hub tables
- Zero-interaction plants show ⚠️ flag
- Vernacular names display correctly (scientific + vernacular format)
- Data completeness footnote appears when relevant

## Expected Output Example

### Before (Current):
```markdown
**Network Hubs (most connected plants):**

| Plant | Total Fungi | AMF | EMF | Endophytic | Saprotrophic |
|-------|-------------|-----|-----|------------|--------------|
| Fraxinus excelsior | 99 | 1 | 1 | 20 | 77 |
| Diospyros kaki | 45 | 0 | 0 | 7 | 38 |
```

### After (Proposed):
```markdown
**Network Hubs (most connected plants):**

| Plant | Total Fungi | AMF | EMF | Endophytic | Saprotrophic |
|-------|-------------|-----|-----|------------|--------------|
| Fraxinus excelsior (Golden ash) | 99 | 1 | 1 | 20 | 77 |
| Diospyros kaki (Japanese persimmon) | 45 | 0 | 0 | 7 | 38 |
| Mercurialis perennis (Dog's mercury) | 22 | 0 | 1 | 0 | 21 |
| Deutzia scabra (Deutzia) ⚠️ | 0 | 0 | 0 | 0 | 0 |
| Rubus moorei (Bush lawyer) ⚠️ | 0 | 0 | 0 | 0 | 0 |

⚠️ **Data Completeness Note:** Plants marked with ⚠️ have no interaction data in this dimension. This likely indicates a data gap rather than true ecological absence.
```

## Files to Modify

### Core Analysis Modules (4 files):
1. `src/explanation/fungi_network_analysis.rs`
2. `src/explanation/pollinator_network_analysis.rs`
3. `src/explanation/biocontrol_network_analysis.rs`
4. `src/explanation/pathogen_control_network_analysis.rs`

### Formatter (1 file):
5. `src/explanation/formatters/markdown.rs`

### JSON Formatter (1 file):
6. `src/explanation/formatters/json.rs` - Update to include new fields

### HTML Formatter (1 file):
7. `src/explanation/formatters/html.rs` - Update to include new fields

## Estimated Changes

- **Lines of code added:** ~200-300
- **Lines of code modified:** ~100-150
- **New tests:** 8-12 unit tests
- **Build time:** 10-20 seconds (debug mode)
- **Regeneration time:** 1-2 minutes for 4 test guilds

## Rollout

1. Implement Phase 1-2 for fungi network only
2. Test with single guild
3. Verify output quality
4. Apply pattern to other 3 networks
5. Full test with 4 guilds
6. Commit and regenerate production reports
