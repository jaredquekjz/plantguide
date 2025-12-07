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

## Category Ratings

Each category (temperature, moisture, soil, texture) has a rating:

| Rating | Meaning |
|--------|---------|
| WithinRange | Local value within q05-q95 |
| Marginal | Issues present but not severe |
| OutOfRange | Severe mismatch |

---

## Severe Issues (Auto → NotRecommended)

**Note**: Temperature data is stored in dekadal (36/year) format. Growing tips use annual conversions (×36), but severe issue checks use raw dekadal `distance_from_range` values.

| Category | Condition | Threshold (annual) | Code threshold (dekadal distance) |
|----------|-----------|-------------------|-----------------------------------|
| Temperature | Extra tropical nights | > 100 days/year | `distance_from_range > 100.0` |
| Temperature | Extra frost days | > 50 days/year | `distance_from_range > 50.0` |
| Temperature | Growing season too short | > 60 days below q05 | `distance_from_range > 60.0` |
| Climate | NoMatch + Temperature OutOfRange | Combined veto | — |
| Climate | NoMatch + Moisture OutOfRange | Combined veto | — |

---

## Overall Rating Calculation

```
1. ceiling = rating_ceiling(climate_tier_match)
2. if has_severe_issues → NotRecommended
3. issue_count = count(categories != WithinRange)
4. computed =
     issue_count >= 3 → Challenging
     issue_count >= 1 → Good
     issue_count == 0 → Ideal
5. return min(ceiling, computed)
```

### Rating Hierarchy

| Rating | Score | Description |
|--------|-------|-------------|
| Ideal | 90% | Conditions match where plant thrives |
| Good | 70% | Good with minor adaptations |
| Challenging | 40% | Significant intervention needed |
| NotRecommended | 20% | Conditions differ significantly |

---

## Issue Counting

Categories counted:
- Temperature (frost, tropical nights, growing season)
- Moisture (rainfall, dry/wet spells)
- Soil (pH, CEC)
- Texture (USDA class mismatch)

Each category contributes 0 or 1 to issue count.

---

## Growing Tips

See **S2 § Growing Tips** for threshold rules.

Tips are generated from envelope comparisons (local vs q05-q95) with severity levels:
- **critical**: Major intervention needed
- **warning**: Moderate intervention
- **info**: Minor consideration
