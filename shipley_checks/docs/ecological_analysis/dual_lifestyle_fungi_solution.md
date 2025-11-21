# Dual-Lifestyle Fungi: Revised Solution

**Date:** 2025-11-21
**Issue:** Pathogenic fungi appearing as "beneficial" without indicating dual-lifestyle nature

## Problem Statement

The current issue is NOT that dual-lifestyle fungi are included in M5 calculations - that's scientifically valid. The issue is that the **report doesn't show they're ALSO pathogenic**, creating a misleading impression.

## Current State

**M5 Calculation:**
- Correctly includes dual-lifestyle fungi in beneficial counts
- Saprotrophic decomposition IS a beneficial function
- Scores are scientifically valid

**Report Display:**
```markdown
| colletotrichum | Saprotrophic | 3 plants | 42.9% |
| alternaria     | Saprotrophic | 2 plants | 28.6% |
```

**Problem:** User sees "Saprotrophic" and assumes beneficial, doesn't realize these are ALSO plant pathogens.

## Proposed Solution: Annotate Dual-Lifestyle Status

### Option 1: Inline Category Annotation (RECOMMENDED)

Show dual lifestyle in the category column:

```markdown
| Fungus Species | Category | Plants Connected | Network Contribution |
|----------------|----------|------------------|----------------------|
| colletotrichum | Saprotrophic ⚠ Pathogen | 3 plants | 42.9% |
| alternaria     | Saprotrophic ⚠ Pathogen | 2 plants | 28.6% |
| trichoderma    | Saprotrophic | 4 plants | 57.1% |
```

Add explanatory note below table:
```markdown
⚠ **Dual-Lifestyle Fungi**: Some fungi have both beneficial (saprotrophic) and
pathogenic roles. While they contribute to decomposition and nutrient cycling,
they may also cause disease under certain conditions.
```

**Benefits:**
- M5 scores unchanged (calculation integrity)
- Full scientific transparency
- User immediately sees dual nature
- Simple implementation

### Option 2: Separate Dual-Lifestyle Section

Keep main table clean, add dedicated section:

```markdown
**Top Network Fungi (by connectivity):**

| Rank | Fungus Species | Category | Plants Connected |
|------|----------------|----------|------------------|
| 1 | trichoderma | Saprotrophic | 4 plants |
| 2 | colletotrichum† | Saprotrophic | 3 plants |
| 3 | alternaria† | Saprotrophic | 2 plants |

**† Dual-Lifestyle Fungi in This Guild:**

The following fungi provide beneficial saprotrophic functions but are also
known plant pathogens:

- **colletotrichum** (Anthracnose): Decomposes plant material but can cause
  leaf spots, fruit rot, and stem cankers
- **alternaria** (Early blight): Saprotrophic decomposer but causes leaf
  spots and fruit diseases
```

**Benefits:**
- Clean main table
- Educational detail about each pathogen
- Clear risk communication

### Option 3: Add "Lifestyle" Column

Extend table structure:

```markdown
| Fungus | Category | Lifestyle | Plants | Network % |
|--------|----------|-----------|--------|-----------|
| colletotrichum | Saprotrophic | Dual (Pathogen) | 3 | 42.9% |
| trichoderma | Saprotrophic | Single | 4 | 57.1% |
```

**Benefits:**
- Structured data
- Easy to scan
- Could add filtering later

## Implementation Details

### Data Flow

1. **M5 Calculation** (no changes)
   - Continues to count dual-lifestyle fungi as beneficial
   - Scores remain unchanged

2. **Fungi Network Analysis** (modify)
   - When building category map, check `pathogenic_fungi` column
   - Flag fungi that appear in both beneficial AND pathogenic columns
   - Store dual-lifestyle status alongside category

3. **Report Generation** (modify)
   - Format category string to include dual-lifestyle indicator
   - Add explanatory text about dual-lifestyle fungi
   - Optional: List specific dual-lifestyle genera with disease info

### Code Changes Required

**File:** `src/explanation/fungi_network_analysis.rs`

**Step 1:** Update `SharedFungus` and `TopFungus` structs:
```rust
pub struct SharedFungus {
    pub fungus_name: String,
    pub plant_count: usize,
    pub plants: Vec<String>,
    pub category: FungusCategory,
    pub is_dual_lifestyle: bool,  // NEW: Also appears in pathogenic_fungi
    pub network_contribution: f64,
}
```

**Step 2:** Modify `categorize_fungi()` to detect dual-lifestyle:
```rust
fn categorize_fungi(
    fungi_df: &DataFrame,
    guild_plants: &DataFrame,
) -> Result<(FxHashMap<String, FungusCategory>, FxHashSet<String>)> {
    let mut category_map = FxHashMap::default();
    let mut pathogen_set = FxHashSet::default();  // NEW

    // First pass: Build pathogen set
    for idx in 0..fungi_df.height() {
        if let Some(plant_id) = fungi_plant_col.get(idx) {
            if guild_plant_set.contains(plant_id) {
                if let Ok(col) = fungi_df.column("pathogenic_fungi") {
                    if let Ok(list_col) = col.list() {
                        // Extract all pathogens for this guild
                        // Add to pathogen_set
                    }
                }
            }
        }
    }

    // Second pass: Categorize beneficial fungi (existing logic)
    // Return BOTH category_map AND pathogen_set

    Ok((category_map, pathogen_set))
}
```

**Step 3:** Update `analyze_fungi_network()`:
```rust
pub fn analyze_fungi_network(
    m5: &M5Result,
    guild_plants: &DataFrame,
    fungi_df: &DataFrame,
) -> Result<Option<FungiNetworkProfile>> {
    // Get both category map AND pathogen set
    let (category_map, pathogen_set) = categorize_fungi(fungi_df, guild_plants)?;

    // When building SharedFungus/TopFungus:
    let shared_fungi: Vec<SharedFungus> = fungus_to_plants
        .iter()
        .filter(|(_, (plants, _))| plants.len() >= 2)
        .map(|(fungus_name, (plants, category))| SharedFungus {
            fungus_name: fungus_name.clone(),
            plant_count: plants.len(),
            plants: plants.clone(),
            category: category.clone(),
            is_dual_lifestyle: pathogen_set.contains(fungus_name),  // NEW
            network_contribution: plants.len() as f64 / n_plants as f64,
        })
        .collect();
}
```

**Step 4:** Update markdown formatter:
```rust
// In formatters/markdown.rs
fn format_fungus_category(fungus: &TopFungus) -> String {
    if fungus.is_dual_lifestyle {
        format!("{} ⚠ Pathogen", fungus.category)
    } else {
        format!("{}", fungus.category)
    }
}
```

## Recommended Approach

**Option 1 (Inline Annotation)** is recommended because:

1. **No calculation changes** - M5 scores remain identical
2. **Scientific accuracy** - Dual lifestyle explicitly shown
3. **User clarity** - Warning visible at point of information
4. **Minimal code changes** - Extends existing structures
5. **Maintains table structure** - No layout redesign needed

The key insight: These fungi DO provide beneficial saprotrophic functions (decomposition, nutrient cycling). The issue is not including them in beneficial counts, but failing to communicate the disease risk alongside the benefit.

## Example Report Output

```markdown
### Beneficial Mycorrhizal Network [M5 - 100.0/100]

385 shared beneficial fungal species connect 7 plants

**Top Network Fungi (by connectivity):**

| Rank | Fungus Species | Category | Plants Connected | Network Contribution |
|------|----------------|----------|------------------|----------------------|
| 1 | leptosphaeria | Saprotrophic | 4 plants | 57.1% |
| 2 | mycosphaerella | Saprotrophic ⚠ Pathogen | 4 plants | 57.1% |
| 3 | phyllosticta | Saprotrophic ⚠ Pathogen | 4 plants | 57.1% |
| 4 | colletotrichum | Saprotrophic ⚠ Pathogen | 3 plants | 42.9% |

⚠ **Dual-Lifestyle Fungi**: Some fungi (mycosphaerella, phyllosticta, colletotrichum)
have both saprotrophic (beneficial decomposition) and pathogenic (disease-causing) roles.
While they contribute to nutrient cycling in the M5 score, they may cause leaf spots,
fruit rot, or other diseases under favorable conditions.
```

This approach:
- Honors the scientific validity of dual-lifestyle classification
- Maintains metric consistency (M5 unchanged)
- Provides full transparency to users
- Allows informed decision-making about guild composition
