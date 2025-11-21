# Report Presentation Issues Analysis

## Summary

After fixing list column reading bugs, several presentation issues were discovered in generated explanation reports. These are all in the markdown formatting layer, not in data processing.

## Issues Found

### Issue 1: Extra Pipe in Table Separator ⚠️ Minor

**Location:** `src/explanation/formatters/markdown.rs:683`

**Problem:** Pathogen Control Network Hubs table has double pipe at end of separator row

**Current Code:**
```rust
md.push_str("|-------|---------------|-----------||\n");
```

**Should be:**
```rust
md.push_str("|-------|---------------|-----------|\n");
```

**Impact:** Renders incorrectly in some markdown parsers

**Example in report (line 127):**
```markdown
| Plant | Mycoparasites | Pathogens |
|-------|---------------|-----------||
```

---

### Issue 2: WFO IDs Showing Instead of Plant Names 🔴 Critical

**Location:** `src/explanation/formatters/markdown.rs:239-243`

**Problem:** Fungi network "Plants Connected" column shows raw WFO IDs when there are ≤3 plants

**Current Code:**
```rust
let plant_list = if fungus.plants.len() > 3 {
    format!("{} plants", fungus.plants.len())
} else {
    fungus.plants.join(", ")  // ❌ Joins WFO IDs directly
};
```

**Impact:** Unreadable technical IDs shown to end users

**Example in report (lines 163-166):**
```markdown
| 4 | colletotrichum | Saprotrophic | wfo-0000649136, wfo-0000690499, wfo-0000832453 | 42.9% |
| 5 | phoma | Saprotrophic | wfo-0000241769, wfo-0000649136, wfo-0000832453 | 42.9% |
```

**Should show:**
```markdown
| 4 | colletotrichum | Saprotrophic | 3 plants | 42.9% |
| 5 | phoma | Saprotrophic | 3 plants | 42.9% |
```

**Root Cause:** The `fungus.plants` field contains WFO IDs, not readable plant names. The code incorrectly tries to join them for display.

**Correct Approach:** Always use `"{} plants"` format when showing multiple plants. If we want to show plant names, we need to look them up from the WFO ID → name mapping.

---

### Issue 3: Grammar Error - "1 plants" 🟡 Medium

**Location:** `src/explanation/formatters/markdown.rs:404`

**Problem:** Always uses plural "plants" even for count=1

**Current Code:**
```rust
md.push_str(&format!(
    "| {} | {} | {} | {} plants | {:.1}% |\n",  // ❌ Always "plants"
    i + 1,
    pollinator.pollinator_name,
    pollinator.category.display_name(),
    pollinator.plant_count,
    pollinator.network_contribution * 100.0
));
```

**Impact:** Grammatically incorrect "1 plants" throughout pollinator network tables

**Example in report (lines 244-251):**
```markdown
| 3 | Aedes impiger | Flies | 1 plants | 14.3% |
| 4 | Aedes nigripes | Flies | 1 plants | 14.3% |
| 5 | Andrena carlini | Solitary Bees | 1 plants | 14.3% |
```

**Fix:**
```rust
let plant_text = if pollinator.plant_count == 1 {
    "1 plant".to_string()
} else {
    format!("{} plants", pollinator.plant_count)
};

md.push_str(&format!(
    "| {} | {} | {} | {} | {:.1}% |\n",
    i + 1,
    pollinator.pollinator_name,
    pollinator.category.display_name(),
    plant_text,  // ✅ Conditional
    pollinator.network_contribution * 100.0
));
```

---

### Issue 4: Multiple Vernacular Names Showing 🔴 Critical

**Location:** Multiple files - `build_plant_display_map()` functions

**Problem:** Vernacular name field contains ALL vernacular names separated by semicolons, but code uses it directly without extracting just the first one

**Example in report (lines 92, 96):**
```markdown
| Fraxinus excelsior (Golden Ash; European ash; Ash) | 0 | 2 | 2 |
| Maianthemum racemosum (Pacific Solomon's seal; Solomon's plume; false Solomon's seal; Trackle-berries) ⚠️ | 0 | 0 | 0 |
```

**Should show:**
```markdown
| Fraxinus excelsior (Golden Ash) | 0 | 2 | 2 |
| Maianthemum racemosum (Pacific Solomon's seal) ⚠️ | 0 | 0 | 0 |
```

**Current Code Pattern** (appears in 4 files):
```rust
// In fungi_network_analysis.rs:370-394
fn build_plant_display_map(guild_plants: &DataFrame) -> Result<FxHashMap<String, (String, String)>> {
    let vernacular_col = if let Ok(col) = guild_plants.column("vernacular_name_en") {
        Some(col.str()?.clone())
    } else if let Ok(col) = guild_plants.column("vernacular_name_zh") {
        Some(col.str()?.clone())
    } else {
        None
    };

    let vern = if let Some(ref v_col) = vernacular_col {
        v_col.get(idx).unwrap_or("").to_string()  // ❌ Uses entire string
    } else {
        String::new()
    };
    // ...
}
```

**Fix Required:**
```rust
let vern = if let Some(ref v_col) = vernacular_col {
    let full_name = v_col.get(idx).unwrap_or("");
    // Extract first name only (split by semicolon, take first, trim)
    full_name
        .split(';')
        .next()
        .unwrap_or("")
        .trim()
        .to_string()
} else {
    String::new()
};
```

**Files Affected:**
1. `src/explanation/fungi_network_analysis.rs:370` - `build_plant_display_map()`
2. `src/explanation/pollinator_network_analysis.rs` - `build_plant_display_map_pollinator()`
3. `src/explanation/biocontrol_network_analysis.rs` - `build_plant_display_map_biocontrol()`
4. `src/explanation/pathogen_control_network_analysis.rs:257` - `build_plant_display_map_pathogen()`

---

## Data Source Investigation

The vernacular name columns (`vernacular_name_en`, `vernacular_name_zh`) in the guild plant DataFrames contain semicolon-separated lists of ALL known vernacular names for each plant.

**Example data:**
- Fraxinus excelsior: "Golden Ash; European ash; Ash"
- Maianthemum racemosum: "Pacific Solomon's seal; Solomon's plume; false Solomon's seal; Trackle-berries"
- Anaphalis margaritacea: "whitemargin pussytoes; pearly everlasting"

This is correct data structure for storing multiple names, but the display logic needs to extract only the first name for presentation.

---

## Priority for Fixes

1. **Critical - Issue 4 (Multiple vernacular names)** - Affects readability across all network hub tables
2. **Critical - Issue 2 (WFO IDs showing)** - Technical IDs completely unusable for end users
3. **Medium - Issue 3 ("1 plants" grammar)** - Unprofessional but doesn't affect understanding
4. **Minor - Issue 1 (Extra pipe)** - Cosmetic markdown rendering issue

---

## Fix Strategy

### Phase 1: Create Helper Function
Create a centralized `format_vernacular_name()` helper function:

```rust
/// Extract first vernacular name from semicolon-separated list
fn format_vernacular_name(full_vernacular: &str) -> String {
    full_vernacular
        .split(';')
        .next()
        .unwrap_or("")
        .trim()
        .to_string()
}
```

### Phase 2: Update All 4 `build_plant_display_map` Functions
Replace direct string usage with `format_vernacular_name()` call in:
- fungi_network_analysis.rs
- pollinator_network_analysis.rs
- biocontrol_network_analysis.rs
- pathogen_control_network_analysis.rs

### Phase 3: Fix Markdown Formatting Issues
Update `formatters/markdown.rs`:
- Line 683: Remove extra pipe
- Lines 239-243: Always use "{} plants" format (never show WFO IDs)
- Line 404: Add conditional singular/plural logic

### Phase 4: Test
Regenerate all reports and verify:
- Single vernacular names shown
- No WFO IDs in fungi network tables
- Correct "1 plant" vs "N plants" grammar
- Table separators render correctly

---

## Expected Outcome

**Before (current):**
```markdown
| Fraxinus excelsior (Golden Ash; European ash; Ash) | 99 | 1 | 1 | 20 | 77 |
| colletotrichum | Saprotrophic | wfo-0000649136, wfo-0000690499, wfo-0000832453 | 42.9% |
| Aedes impiger | Flies | 1 plants | 14.3% |
```

**After (fixed):**
```markdown
| Fraxinus excelsior (Golden Ash) | 99 | 1 | 1 | 20 | 77 |
| colletotrichum | Saprotrophic | 3 plants | 42.9% |
| Aedes impiger | Flies | 1 plant | 14.3% |
```

Clean, professional, readable presentation with no technical artifacts.
