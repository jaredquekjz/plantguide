# S2a: Suitability Assessment

**Source**: Same as S2 + user-provided local conditions

## Climate Tier Matching

### Tier Definitions (from Köppen)

| Tier | Köppen Codes | Description |
|------|--------------|-------------|
| 1. Tropical | A* | Year-round warmth, no frost |
| 2. Mediterranean | Cs* | Dry summers, mild wet winters |
| 3. Humid Temperate | Cf*, Cw* | Mild, adequate rainfall year-round |
| 4. Continental | Dfa, Dfb, Dsa, Dsb, Dwa, Dwb | Cold winters, warm summers |
| 5. Boreal/Polar | Dfc, Dfd, Dwc, Dwd, E* | Short summers, long cold winters |
| 6. Arid | B* | Low rainfall, high evaporation |

### Adjacent Tiers

| Tier | Adjacent To |
|------|-------------|
| Tropical | (none - isolated) |
| Mediterranean | Humid Temperate, Arid |
| Humid Temperate | Mediterranean, Continental |
| Continental | Humid Temperate, Boreal/Polar |
| Boreal/Polar | Continental |
| Arid | Mediterranean |

### Tier Match → Rating Ceiling

| Match Type | Condition | Ceiling |
|------------|-----------|---------|
| ExactMatch | Plant observed in local tier | Ideal |
| AdjacentMatch | Plant observed in adjacent tier | Good |
| NoMatch | Neither exact nor adjacent | Challenging |

---

## FitLevel Categories

Local conditions are compared against the plant's **occurrence envelope** derived from ~145 million georeferenced GBIF records.

### Percentile Basis

| Percentile | Meaning |
|------------|---------|
| **Q05** | 5th percentile - lower boundary (only 5% of specimens found below) |
| **Q50** | 50th percentile - median (typical conditions) |
| **Q95** | 95th percentile - upper boundary (only 5% of specimens found above) |

The **Q05-Q95 range** captures where 90% of specimens occur - this is the plant's natural comfort zone.

### Tolerance Buffer

To avoid flagging trivial deviations, a **tolerance buffer** extends beyond Q05/Q95. The buffer is the **larger** of:
1. **10% of range width**: Scales with the plant's natural variability
2. **Minimum absolute threshold**: Biologically meaningful floor per parameter

### Minimum Absolute Thresholds

| Parameter | Min Absolute | Rationale |
|-----------|--------------|-----------|
| Frost days | 5 days | Aligns with info-level tip threshold |
| Warm nights | 10 nights | Well below 30-night warning threshold |
| Growing season | 15 days | Aligns with info-level tip threshold |
| Rainfall | 100 mm | ~5% of typical annual range |
| Dry spells | 5 days | Aligns with info-level tip threshold |
| Wet spells | 3 days | Aligns with info-level tip threshold |
| Soil pH | 0.3 units | Below 0.5 warning threshold |
| CEC | 3 cmol/kg | Reasonable measurement tolerance |

### FitLevel Assignment

| Category | Definition | Score | Badge |
|----------|------------|-------|-------|
| **Ideal** | Local value within Q05-Q95 | 90% | Green |
| **Good** | Local value outside Q05-Q95 but within tolerance buffer | 75% | Blue |
| **Marginal** | Local value beyond tolerance but <50% of range width | 50% | Amber |
| **Beyond Range** | Local value ≥50% of range width beyond Q05/Q95 | 25% | Red |
| **Unknown** | No data available | — | Grey |

### Calculation Logic

```rust
fn convert_fit(local_value, q05, q95, min_absolute) -> FitLevel:
    range_width = q95 - q05
    tolerance = max(range_width * 0.10, min_absolute)

    if local_value within [q05, q95]:
        return Ideal
    else:
        distance = abs(local_value - nearest_boundary)
        if distance <= tolerance:
            return Good
        elif distance <= range_width * 0.50:
            return Marginal
        else:
            return Beyond Range
```

### Example: Papaya warm nights in Singapore

Plant range: Q05=1, Q95=363 (range width = 362 nights)
- 10% tolerance = 36.2 nights
- Min absolute = 10 nights
- **Effective tolerance = 36.2 nights** (larger of the two)

| Local Warm Nights | Result | Reason |
|-------------------|--------|--------|
| 200 | **Ideal** | Within Q05-Q95 |
| 364 | **Good** | 1 night beyond Q95, but 1 < 36.2 tolerance |
| 400 | **Marginal** | 37 nights beyond Q95, exceeds tolerance but < 181 (50%) |
| 550 | **Beyond Range** | 187 nights beyond Q95, exceeds 50% of range |

### Example: Soil pH

Plant range: Q05=5.0, Q95=7.3 (range width = 2.3 units)
- 10% tolerance = 0.23 units
- Min absolute = 0.3 units
- **Effective tolerance = 0.3 units** (larger of the two)

| Local pH | Result | Reason |
|----------|--------|--------|
| 6.0 | **Ideal** | Within Q05-Q95 |
| 4.9 | **Good** | 0.1 below Q05, but 0.1 < 0.3 tolerance |
| 4.5 | **Marginal** | 0.5 below Q05, exceeds tolerance but < 1.15 (50%) |
| 3.5 | **Beyond Range** | 1.5 below Q05, exceeds 50% of range |

---

## Climate Tier Override

**Key rule**: If a plant occurs in the **same climate tier** as the location (ExactMatch), the severity for any category is **capped at Marginal** (never Beyond Range).

### Rationale

The plant demonstrably grows in this climate type based on occurrence records. Minor envelope deviations within the same climate shouldn't override that fundamental compatibility.

### Example: Papaya in Singapore

- Singapore: Tropical climate, 364 warm nights/year
- Papaya: Tropical plant, envelope Q95 = 363 warm nights
- **Without override**: 1 night beyond Q95 → "Beyond Range" → 25% score
- **With override**: Climate is ExactMatch (both Tropical) → capped at "Marginal" → 50% score

### Implementation

```rust
if climate_tier_match == ExactMatch {
    if category_fit == Outside {
        category_fit = Marginal  // Cap at Marginal, never Outside
    }
}
```

This applies to Temperature, Moisture, and Soil categories before overall aggregation.

---

## Overall Suitability

Calculated as the **worst-case** fit across Temperature, Moisture, and Soil categories (after climate tier override is applied).

```
1. Compute raw category fits from envelope comparisons
2. Apply climate tier override (ExactMatch → cap at Marginal)
3. overall_fit = worst(temperature_fit, moisture_fit, soil_fit)
```

Each category's fit is itself the worst-case across its comparisons:
- **Temperature**: frost days, tropical nights, growing season
- **Moisture**: rainfall, dry spells, wet spells
- **Soil**: pH, CEC, texture

### Score Mapping

| Overall Fit | Score | Verdict |
|-------------|-------|---------|
| Optimal | 90% | "Ideal conditions" |
| Good | 75% | "Good match" |
| Marginal | 50% | "Marginal - some challenges likely" |
| Beyond Range | 25% | "Beyond typical range - significant intervention needed" |
| Unknown | 50% | "Insufficient data" |

**Note**: With climate tier override, "Beyond Range" (25%) only occurs when the plant is NOT observed in the local climate tier.

---

## Overall Rating Calculation

```
1. worst_category = worst(temperature_fit, moisture_fit, soil_fit)
2. base_score = score_from_fit(worst_category)
3. Generate growing tips with severity levels
4. Apply tips severity veto:
   - Any critical tip → cap at 25% (Not Recommended)
   - Any warning tip → cap at 50% (Challenging)
5. final_score = min(base_score, severity_cap)
```

### Rating Hierarchy

| Rating | Score | Description |
|--------|-------|-------------|
| Ideal | 90% | Conditions match where plant thrives |
| Good | 75% | Good with minor adaptations |
| Challenging | 50% | Significant intervention needed |
| Not Recommended | 25% | Conditions differ significantly |

---

## Tips Severity Veto

The headline score is capped based on growing tips severity. This ensures consistency - if tips recommend greenhouses or daily irrigation, the headline shouldn't say "Good".

| Tips Severity | Score Cap | Rationale |
|---------------|-----------|-----------|
| Any `critical` | 25% (Not Recommended) | Major infrastructure needed |
| Any `warning` | 50% (Challenging) | Significant intervention |
| Info only | No cap | Minor adjustments |

### Critical Tip Thresholds

| Parameter | Condition | Tip |
|-----------|-----------|-----|
| Frost days | > 50 days beyond q95 | "Overwinter indoors" |
| Tropical nights | > 100 days beyond q95 | "Heat stress likely" |
| Rainfall | < 50% of q05 | "Drip irrigation required" |
| Rainfall | > 200% of q95 | "Raised bed with grit essential" |

### Warning Tip Thresholds

| Parameter | Condition | Tip |
|-----------|-----------|-----|
| Frost days | > 20 days beyond q95 | "Protect in winter" |
| Tropical nights | > 30 days beyond q95 | "Provide afternoon shade" |
| Growing season | > 40 days below q05 | "Start early under cover" |
| Rainfall | < 80% of q05 | "Supplemental watering needed" |
| Rainfall | > 130% of q95 | "Improve drainage" |

**Implementation note**: Frost days and tropical nights are stored as dekadal means; the code converts to annual (×36) before threshold comparison.

---

## Growing Tips

Tips are generated from envelope comparisons (local vs q05-q95) with severity levels:
- **critical**: Major intervention needed (greenhouse, daily irrigation)
- **warning**: Moderate intervention (fleece, mulch, drainage)
- **info**: Minor consideration (occasional care)
