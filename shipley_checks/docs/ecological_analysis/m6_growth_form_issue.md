# M6 Structural Diversity: Growth Form Not Considered in Height Stratification

## Issue Summary

**Severity:** Medium - Incorrect scoring, but doesn't cause crashes

**Problem:** M6 (Structural Diversity) treats all plants identically when calculating vertical stratification, regardless of growth form. A 10m climbing vine is scored the same as a 10m tree, even though they occupy different ecological niches.

**Impact:**
- Climbers/vines penalized incorrectly for "competing" with tall plants they could climb on
- Guilds with complementary growth forms (vine + tree) receive artificially lower stratification scores
- Inconsistent with M2 (Growth Compatibility) which correctly handles growth form complementarity

## Background: How M2 Handles Growth Form

### M2 CSR Conflict Calculation (CORRECT Approach)

**File:** `src/metrics/m2_growth_compatibility.rs`

**Lines 294-312:** Growth form modulation in C-C conflicts

```rust
// Growth form complementarity
let form_a = &plant_a.growth_form;
let form_b = &plant_b.growth_form;

if (form_a.contains("vine") || form_a.contains("liana")) && form_b.contains("tree") {
    conflict *= 0.2; // Vine can climb tree ✅
} else if (form_b.contains("vine") || form_b.contains("liana")) && form_a.contains("tree") {
    conflict *= 0.2; // Vine can climb tree ✅
} else if (form_a.contains("tree") && form_b.contains("herb"))
    || (form_b.contains("tree") && form_a.contains("herb"))
{
    conflict *= 0.4; // Different vertical niches ✅
} else {
    // Height separation (only for similar growth forms)
    let height_diff = (plant_a.height_m - plant_b.height_m).abs();
    if height_diff < 2.0 {
        conflict *= 1.0; // Same canopy layer
    } else if height_diff < 5.0 {
        conflict *= 0.6; // Partial separation
    } else {
        conflict *= 0.3; // Different canopy layers
    }
}
```

**Key insight:** M2 recognizes that:
1. Vines/lianas can climb trees → minimal conflict (0.2× multiplier)
2. Trees + herbs occupy different niches → reduced conflict (0.4× multiplier)
3. Height separation only matters for plants with similar growth forms

## Problem: M6 Ignores Growth Form

### M6 Stratification Calculation (INCORRECT Approach)

**File:** `src/metrics/m6_structural_diversity.rs`

**Lines 118-174:** Height stratification calculation

```rust
let growth_forms = guild_plants.column("try_growth_form")?.str()?;  // ⚠️ Extracted but not used
let orig_heights = guild_plants.column("height_m")?.f64()?;

// ... sorting by height ...

// Analyze all tall-short pairs (Lines 136-174)
for i in 0..n - 1 {
    for j in i + 1..n {
        let short_height_opt = heights.get(i);
        let tall_height_opt = heights.get(j);
        // ... height_diff calculation ...

        if height_diff > 2.0 {
            // ❌ No growth form check here!
            // Treats vine + tree the same as tree + tree

            let short_light = light_prefs.get(i);
            match short_light {
                Some(light) if light < 3.2 => {
                    valid_stratification += height_diff;  // Shade-tolerant
                }
                Some(light) if light > 7.47 => {
                    invalid_stratification += height_diff;  // Sun-loving (penalized)
                }
                Some(_) => {
                    valid_stratification += height_diff * 0.6;  // Flexible
                }
                None => {
                    valid_stratification += height_diff * 0.5;  // Conservative
                }
            }
        }
    }
}
```

**What's wrong:**
1. Growth form is extracted (line 118) but NEVER used in stratification calculation
2. All tall-short pairs are evaluated using only height and light preference
3. A vine reaching 10m by climbing a 15m tree is scored as if both plants need separate vertical space

## Concrete Example

**Guild:**
- Plant A: Oak tree, 20m tall, growth_form="tree"
- Plant B: Clematis vine, 8m tall, growth_form="vine/liana"

### Current M6 Behavior (WRONG):

```
Height difference: 20 - 8 = 12m
If vine has light_pref < 3.2 (shade-tolerant):
  valid_stratification += 12.0

Stratification quality = 12.0 / 12.0 = 1.0 ✅
```

This looks good, but...

**What if vine is NOT shade-tolerant?**
```
If vine has light_pref = 7.0 (flexible):
  valid_stratification += 12.0 * 0.6 = 7.2

Stratification quality = 7.2 / 12.0 = 0.6 ⚠️ Penalized!
```

**The problem:** The vine is being evaluated as if it needs its own vertical space at ground level, competing with the tree. In reality, the vine **climbs the tree** and doesn't compete for ground-level space.

### Correct M6 Behavior (SHOULD BE):

```
Height difference: 20 - 8 = 12m
Growth forms: vine + tree
→ Complementary growth forms! Vine climbs tree.
→ No vertical space competition

valid_stratification += 12.0 * 1.0  ✅ (full credit regardless of light preference)

Stratification quality = 12.0 / 12.0 = 1.0 ✅
```

## Comparison Table

| Metric | Growth Form Handling | Vine + Tree Logic | Tree + Herb Logic |
|--------|---------------------|-------------------|-------------------|
| **M2 (Growth Compatibility)** | ✅ Explicit | Conflict × 0.2 (complementary) | Conflict × 0.4 (different niches) |
| **M6 (Structural Diversity)** | ❌ None | Treated same as tree + tree | Treated same as tree + tree |

## Proposed Fix

### Approach 1: Add Growth Form Modulation (Recommended)

Modify M6 stratification calculation to match M2's logic:

```rust
// Inside the tall-short pair loop (after line 148):
let short_form = growth_forms.get(i).unwrap_or("");
let tall_form = growth_forms.get(j).unwrap_or("");

// Check for complementary growth forms
let is_complementary =
    (short_form.contains("vine") || short_form.contains("liana")) && tall_form.contains("tree")
    || (tall_form.contains("vine") || tall_form.contains("liana")) && short_form.contains("tree")
    || (short_form.contains("herb") && tall_form.contains("tree"))
    || (tall_form.contains("herb") && short_form.contains("tree"));

if height_diff > 2.0 {
    let short_light = light_prefs.get(i);

    let height_contribution = if is_complementary {
        // Complementary growth forms: full credit regardless of light
        height_diff
    } else {
        // Same growth form: evaluate based on light preference
        match short_light {
            Some(light) if light < 3.2 => height_diff,  // Shade-tolerant
            Some(light) if light > 7.47 => {
                invalid_stratification += height_diff;
                continue;
            }
            Some(_) => height_diff * 0.6,  // Flexible
            None => height_diff * 0.5,  // Conservative
        }
    };

    valid_stratification += height_contribution;
}
```

### Approach 2: Exclude Climbers from Height Calculation (Alternative)

Treat climbers as "height-neutral" - they don't contribute to or detract from stratification:

```rust
// Before the tall-short pair loop:
let non_climber_indices: Vec<usize> = (0..n)
    .filter(|&i| {
        let form = growth_forms.get(i).unwrap_or("");
        !form.contains("vine") && !form.contains("liana")
    })
    .collect();

// Only analyze pairs where both plants are non-climbers
for i in 0..non_climber_indices.len() - 1 {
    for j in i + 1..non_climber_indices.len() {
        // ... existing logic ...
    }
}
```

**Trade-offs:**
- **Approach 1** (Recommended): More ecologically accurate, consistent with M2
- **Approach 2**: Simpler code but loses information about vertical diversity

## Impact Assessment

### Affected Guilds

Guilds with climbing/vining plants will be most affected:
- Vitis (grape vines)
- Clematis (climbing vines)
- Wisteria (woody vines)
- Lonicera (honeysuckle vines)
- Hedera (ivy)

**Example:** A "forest garden" guild with oak tree + grape vine currently receives a lower M6 score than it should because the vine is treated as competing with the tree for vertical space.

### Severity by Growth Form Distribution

**High impact:**
- Guilds with vines/lianas + tall trees
- Traditional "three sisters" guilds (corn + beans climbing corn + squash)

**Medium impact:**
- Guilds with herbs + trees (already partially handled by light preference)

**Low impact:**
- Guilds with only trees or only herbs (no growth form complementarity)

## Testing Plan

1. **Create test guild with known complementary forms:**
   - 1 tall tree (20m, tree form)
   - 1 climbing vine (8m, vine form, flexible light)
   - Expected: High stratification score (should NOT be penalized)

2. **Compare current vs fixed behavior:**
   - Run M6 on test guild with current code
   - Apply fix
   - Run M6 again
   - Verify stratification_quality improves

3. **Regenerate all reports:**
   - Check for guilds with vines/lianas
   - Verify M6 scores increase appropriately

## Recommendations

1. **Priority:** Medium (fix in next development cycle)
2. **Approach:** Use Approach 1 (growth form modulation) for consistency with M2
3. **Testing:** Add unit tests for vine + tree and herb + tree scenarios
4. **Documentation:** Update M6 comments to explain growth form handling

## Related Files

- `src/metrics/m6_structural_diversity.rs` - Needs fix (lines 136-174)
- `src/metrics/m2_growth_compatibility.rs` - Reference implementation (lines 284-315)
- `src/explanation/fragments/m6_fragment.rs` - May need updated messaging

## References

- M2 Growth Compatibility: Correctly handles vine + tree as complementary (conflict × 0.2)
- M6 Structural Diversity: Currently ignores growth form in stratification calculation
- CSR conflict logic: Established pattern for growth form complementarity in this codebase
