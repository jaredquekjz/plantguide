# Report Review Findings - Format & Ecological Issues

**Date:** 2025-11-21
**Analysis:** Final report review before production release

## Summary

Reviewed 4 explanation reports for formatting issues and ecological red flags.

**Critical Issues Found:** 2
**Medium Issues Found:** 1
**Minor Issues Found:** 1

---

## 🔴 CRITICAL ISSUE 1: Pathogenic Fungi Classified as Beneficial (ALL REPORTS)

### Problem

Well-known plant pathogens are appearing in the "Beneficial Fungi Network" section, classified as "Saprotrophic" or "Endophytic" fungi. These fungi cause diseases and should be in the pathogenic_fungi category, NOT the beneficial fungi category.

### Affected Fungi

**Across all 5 reports:**

1. **Colletotrichum** - Anthracnose pathogen (causes leaf spots, fruit rot, stem cankers)
   - forest_garden: Rank 4, "Saprotrophic", 3 plants
   - biocontrol_powerhouse: Rank 3, "Saprotrophic", 5 plants
   - competitive_clash: Rank 8, "Saprotrophic", 2 plants
   - entomopathogen_powerhouse: Rank 1, "Saprotrophic", 7 plants
   - stress-tolerant: Rank 3, "Saprotrophic", 1 plant

2. **Alternaria** - Early blight pathogen (causes leaf spots, fruit rot)
   - forest_garden: Rank 8, "Saprotrophic", 2 plants
   - biocontrol_powerhouse: Rank 7, "Saprotrophic", 4 plants
   - competitive_clash: Rank 3, "Saprotrophic", 2 plants
   - entomopathogen_powerhouse: Rank 5, "Saprotrophic", 5 plants

3. **Botrytis** - Gray mold pathogen (causes fruit rot, flower blight)
   - forest_garden: Rank 10, "Saprotrophic", 2 plants
   - competitive_clash: Rank 7, "Saprotrophic", 2 plants

4. **Botryosphaeria** - Canker and dieback pathogen
   - forest_garden: Rank 9, "Saprotrophic", 2 plants

5. **Mycosphaerella** - Leaf spot pathogen
   - forest_garden: Rank 2, "Saprotrophic", 4 plants

6. **Phyllosticta** - Leaf spot and fruit rot pathogen
   - forest_garden: Rank 3, "Saprotrophic", 4 plants

7. **Septoria** - Leaf blotch pathogen
   - forest_garden: Rank 7, "Saprotrophic", 3 plants

### Example from forest_garden.md (lines 156-170)

```markdown
**Top Network Fungi (by connectivity):**

| Rank | Fungus Species | Category | Plants Connected | Network Contribution |
|------|----------------|----------|------------------|----------------------|
| 1 | leptosphaeria | Saprotrophic | 4 plants | 57.1% |
| 2 | mycosphaerella | Saprotrophic | 4 plants | 57.1% | ❌ PATHOGEN
| 3 | phyllosticta | Saprotrophic | 4 plants | 57.1% | ❌ PATHOGEN
| 4 | colletotrichum | Saprotrophic | 3 plants | 42.9% | ❌ PATHOGEN
...
| 8 | alternaria | Saprotrophic | 2 plants | 28.6% | ❌ PATHOGEN
| 9 | botryosphaeria | Saprotrophic | 2 plants | 28.6% | ❌ PATHOGEN
| 10 | botrytis | Saprotrophic | 2 plants | 28.6% | ❌ PATHOGEN
```

### Root Cause

**CONFIRMED: Data handling issue in Rust code, NOT a data classification error**

The parquet data is CORRECT - these fungi are dual-lifestyle organisms that are BOTH pathogenic AND saprotrophic:

**Investigation findings:**

1. **Parquet columns are correct**: Script `03_extract_fungal_guilds_hybrid.R` correctly uses FungalTraits to identify dual-lifestyle fungi
   - Colletotrichum: 802 plants have it in BOTH pathogenic_fungi AND saprotrophic_fungi (100% dual-lifestyle)
   - Alternaria: 623 plants, 100% dual-lifestyle
   - Botrytis: 349 plants, 100% dual-lifestyle
   - Botryosphaeria: 238 plants, 100% dual-lifestyle
   - Mycosphaerella: 947 plants, 100% dual-lifestyle
   - Phyllosticta: 993 plants, 100% dual-lifestyle
   - Septoria: 1201 plants, 100% dual-lifestyle

2. **FungalTraits logic is correct**: Lines 63-71 of R script correctly allow fungi to have BOTH:
   - `is_pathogen = TRUE` (primary_lifestyle = 'plant_pathogen')
   - `is_saprotrophic = TRUE` (primary_lifestyle = various saprotroph types OR secondary_lifestyle contains 'saprotroph')

3. **Rust code ignores pathogenic column**: The issue is in `fungi_network_analysis.rs` (lines 240-245, 307):
   ```rust
   let columns = ["amf_fungi", "emf_fungi", "endophytic_fungi", "saprotrophic_fungi"];
   ```
   - Loads beneficial fungi from these 4 columns ONLY
   - NEVER checks if a fungus also appears in `pathogenic_fungi` column
   - Result: Dual-lifestyle pathogens are treated as beneficial without any filtering

### Impact

- **Ecological misrepresentation:** Reports claim beneficial fungal networks when some fungi are actually harmful
- **Misleading scoring:** M5 (Beneficial Fungi) scores may be artificially inflated
- **User confusion:** Gardeners might think colletotrichum is beneficial when it's a disease-causing fungus

### Recommended Fix

**Update Rust code to filter out dual-lifestyle pathogens from beneficial fungi**

Modify `fungi_network_analysis.rs` to:

1. **First pass**: Load all `pathogenic_fungi` for guild plants into a set
2. **Second pass**: When processing beneficial fungi columns (AMF, EMF, Endophytic, Saprotrophic), exclude any fungus that appears in the pathogen set

**Implementation location:**
- `categorize_fungi()` function (line 220): Add pathogen filtering before categorizing
- `build_fungus_to_plants_mapping()` function (line 291): Add pathogen filtering before mapping

**Example logic:**
```rust
// Step 0: Build pathogen exclusion set
let mut pathogen_set: FxHashSet<String> = FxHashSet::default();
for idx in 0..fungi_df.height() {
    if let Some(plant_id) = fungi_plant_col.get(idx) {
        if guild_plant_set.contains(plant_id) {
            if let Ok(col) = fungi_df.column("pathogenic_fungi") {
                if let Ok(list_col) = col.list() {
                    // Extract all pathogens into set
                }
            }
        }
    }
}

// Step 1: Process beneficial columns, skip if in pathogen_set
for col_name in &["amf_fungi", "emf_fungi", "endophytic_fungi", "saprotrophic_fungi"] {
    // ... existing code ...
    if !pathogen_set.contains(fungus) {
        // Include in beneficial fungi
    }
}
```

This approach:
- Preserves the correct FungalTraits dual-lifestyle classification in parquet
- Correctly prioritizes pathogenic behavior over saprotrophic for reporting
- No hardcoded genus lists (data-driven filtering)
- Respects per-plant associations (a fungus may be pathogenic on one plant, beneficial on another - though data shows 100% overlap for these genera)

---

## ✅ CRITICAL ISSUE 2: Contradictory Biocontrol Match Counts - RESOLVED

### Problem (Original)

The biocontrol network profile showed contradictory counts for predator/parasite matches.

**Example from forest_garden.md:**
```markdown
**Mechanism Summary:**
- 5 Specific predator/parasite matches (herbivore → known natural enemy, weight 1.0)
- 2 General entomopathogenic fungi (broad-spectrum biocontrol, weight 0.2)

**11 Herbivore → Predator matches found:**
```

**Contradiction:** Summary said **5 specific matches**, but table showed **11 matches**

### Root Cause

Code used two different counts:
- Line 492 (summary): `specific_predator_matches` - inflated count from pairwise analysis loop
- Line 499 (table header): `matched_predator_pairs.len()` - deduplicated unique pairs

The `specific_predator_matches` variable counted match instances during pairwise plant comparisons, which could count the same herbivore-predator relationship multiple times if they appeared on multiple plants.

### Fix Applied (Commit 65f4cd1)

**Updated markdown.rs formatter to:**
1. Calculate actual unique herbivore species from matched pairs
2. Show total pair count with species count as clarifying context
3. Format: "N specific herbivore → predator/parasite matches (covering X pest species, weight 1.0)"

**Result:** Numbers are now consistent and clearly explained
- biocontrol_powerhouse: "9 specific matches (covering 9 pest species)"
- forest_garden: "11 specific matches (covering 5 pest species)"

Both the mechanism summary and table header now show the same count (deduplicated pairs), with unique species count provided as additional context.

---

## 🟡 MEDIUM ISSUE: Duplicate Evidence Line (forest_garden.md)

### Problem

M6 (Structural Diversity) section has duplicate evidence statements.

**Location:** forest_garden.md, lines 208-210

```markdown
*Evidence:* Structural diversity score: 100.0/100, stratification quality: 1.00

*Evidence:* Stratification quality: 1.00
```

**Issue:** Line 210 duplicates the stratification quality already shown in line 208

### Impact

- Minor redundancy in report
- Slightly unprofessional presentation

### Recommended Fix

Remove line 210 or combine into a single evidence statement.

---

## ⚪ MINOR ISSUE: Grammar - "1 plant(s)" (multiple reports)

### Problem

Some reports show "1 plant(s)" with plural parentheses when count is singular.

**Location:** forest_garden.md, line 206

```markdown
1 plant(s) are shade-tolerant (EIVE-L <3.2) and thrive under canopy.
6 plant(s) are flexible...
```

### Analysis

This is grammatically awkward. Should be:
- "1 plant is shade-tolerant..." (singular verb)
- "6 plants are flexible..." (plural verb, no parentheses)

### Impact

- Very minor stylistic issue
- Doesn't affect understanding

### Recommended Fix

Use conditional grammar in text generation:
```python
if count == 1:
    text = f"{count} plant is {description}"
else:
    text = f"{count} plants are {description}"
```

---

## Issues NOT Found (User-Acknowledged)

### Wind-Pollinated Trees Showing Pollinators

**Example:** Fraxinus excelsior (ash) showing pollinators despite being primarily wind-pollinated

**Status:** User acknowledged this is a known GloBI data issue - IGNORED as requested

---

## Summary Table

| Issue | Severity | Status | Reports Affected | Fix Priority |
|-------|----------|--------|-----------------|--------------|
| Pathogenic fungi as beneficial | 🔴 Critical | Open | All 5 reports | High - Data quality |
| Biocontrol count contradiction | 🔴 Critical | ✅ Resolved (65f4cd1) | All reports | Complete |
| Duplicate evidence line | 🟡 Medium | Open | forest_garden | Low - Formatting |
| "plant(s)" grammar | ⚪ Minor | Open | Multiple | Very Low - Style |

---

## Recommended Actions

### Immediate (Critical Fixes)

1. **Investigate pathogenic fungi classification**
   - Check source data in fungal guilds parquet
   - Determine if these fungi appear in both beneficial AND pathogenic columns
   - Implement filtering logic to exclude known pathogens from beneficial fungi

2. ✅ **Clarify biocontrol match counting** - COMPLETE (Commit 65f4cd1)
   - Fixed contradictory counts between mechanism summary and table header
   - Now shows deduplicated pair count with unique species count for context
   - Consistent across all reports

### Short-Term (Quality Improvements)

3. **Fix duplicate evidence line**
   - Update M6 fragment generation to show single evidence statement

4. **Fix plural/singular grammar**
   - Add conditional text generation for counts

### Investigation Required

- ✅ **Source data audit:** COMPLETE - FungalTraits correctly classifies dual-lifestyle fungi; parquet data is correct
- ⚠️ **M3 scoring audit:** Verify which biocontrol count is actually used in calculations (5 vs 11 matches)
- ⚠️ **Cross-report consistency check:** Ensure all reports follow same format/logic

---

## Files to Review/Modify

**For pathogenic fungi issue:**
- **Rust code**: `src/Stage_4/guild_scorer_rust/src/explanation/fungi_network_analysis.rs` (lines 220-288, 291-367)
- Functions to update: `categorize_fungi()` and `build_fungus_to_plants_mapping()`
- Source data: `phase0_output/fungal_guilds_hybrid_11711.parquet` (CORRECT - no changes needed)
- Extraction logic: `src/Stage_4/Phase_0_extraction/03_extract_fungal_guilds_hybrid.R` (CORRECT - no changes needed)

**For biocontrol contradiction:**
- M3 metric: `src/metrics/m3_insect_control.rs`
- Biocontrol profile: `src/explanation/biocontrol_network_analysis.rs`
- Report formatter: `src/explanation/formatters/markdown.rs`

**For formatting issues:**
- M6 fragment: `src/explanation/fragments/m6_fragment.rs`
- Stratification text generation

---

## Notes

- All reports reviewed: forest_garden, biocontrol_powerhouse, competitive_clash, entomopathogen_powerhouse, stress-tolerant
- Focus was on ecological red flags and formatting issues
- Wind-pollination issue acknowledged and ignored as requested
- Pathogenic fungi issue is the most serious ecological misrepresentation found
