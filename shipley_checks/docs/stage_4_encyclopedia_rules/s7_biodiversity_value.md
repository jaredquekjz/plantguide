# S7: Biodiversity Value Rules

Rules for generating the biodiversity value summary section.

## Purpose

Synthesise data from multiple sources into actionable biodiversity assessments for gardeners and land managers.

---

## Component Scores

### Pollinator Value (from M7)

| Rating | Score | Label |
|--------|-------|-------|
| Very High | 5 | Major pollinator plant |
| High | 4 | Important for pollinators |
| Moderate | 3 | Some pollinator value |
| Low | 2 | Limited pollinator interest |
| Very Low | 1 | Not a pollinator plant |

### Wildlife Food Value

Derived from interaction data (herbivores as food web indicator):

| Herbivore Taxa | Score | Label |
|----------------|-------|-------|
| > 20 | 5 | Major wildlife food source |
| 11-20 | 4 | Good wildlife value |
| 5-10 | 3 | Moderate wildlife value |
| 1-4 | 2 | Limited wildlife value |
| 0 | 1 | Minimal recorded wildlife use |

### Ecosystem Service Value

Weighted average of M8-M17 scores:

| Average Score | Label |
|---------------|-------|
| ≥ 4.0 | High ecosystem value |
| 3.0-4.0 | Moderate ecosystem value |
| < 3.0 | Limited ecosystem value |

### Native Status Bonus

| Status | Bonus |
|--------|-------|
| Native to region | +1 |
| Naturalised | 0 |
| Introduced/exotic | 0 |

---

## Overall Biodiversity Rating

### Calculation

```
Biodiversity Score = (Pollinator + Wildlife + Ecosystem + Native Bonus) / 4
```

### Interpretation

| Score | Rating | Garden Recommendation |
|-------|--------|----------------------|
| ≥ 4.0 | Excellent | Priority for wildlife gardens |
| 3.0-4.0 | Good | Valuable addition for biodiversity |
| 2.0-3.0 | Moderate | Some wildlife benefits |
| < 2.0 | Limited | Primarily ornamental value |

---

## Threshold-Based Flags

### Pollinator Champion

```
IF pollinator_count > 20 THEN flag "Pollinator Champion"
```

Output:
```markdown
**Pollinator Champion**: Major nectar/pollen source for 20+ pollinator species
```

### Carbon Champion

```
IF carbon_total_rating == "Very High" THEN flag "Carbon Champion"
```

Output:
```markdown
**Carbon Champion**: Significant long-term carbon storage
```

### Soil Builder

```
IF nitrogen_fixation_rating IN ("Very High", "High") THEN flag "Soil Builder"
```

Output:
```markdown
**Soil Builder**: Active nitrogen fixer; improves soil fertility
```

### Erosion Fighter

```
IF erosion_protection_rating IN ("Very High", "High") THEN flag "Erosion Fighter"
```

Output:
```markdown
**Erosion Fighter**: Excellent for stabilising slopes and banks
```

### Wildlife Magnet

```
IF (pollinator_count + herbivore_count) > 30 THEN flag "Wildlife Magnet"
```

Output:
```markdown
**Wildlife Magnet**: Supports diverse wildlife community
```

---

## Output Format

```markdown
## Biodiversity Value

**Overall Rating**: Good (3.5/5)

### Highlights
- **Pollinator Champion**: Supports 25+ pollinator species
- **Soil Builder**: Active nitrogen fixer

### Component Scores
| Category | Score | Notes |
|----------|-------|-------|
| Pollinator value | 5/5 | Very High - 25 taxa documented |
| Wildlife value | 3/5 | Moderate - 8 herbivore taxa |
| Ecosystem services | 4/5 | High carbon storage, N-fixation |
| Native status | +1 | Native to Europe |

### Garden Recommendation
Excellent choice for wildlife-friendly gardens. Prioritise for:
- Pollinator borders
- Wildlife hedgerows
- Food forest systems
- Soil improvement plantings
```

---

## Special Cases

### RHS Perfect for Pollinators Equivalent

Plants meeting these criteria can be highlighted:

```
IF pollinator_count >= 15
AND native_status == "Native"
AND EIVE-L >= 5 (not deep shade)
THEN "Excellent for pollinators - consider for wildlife planting schemes"
```

### Invasive Risk Warning

```
IF C > 70%
AND climate_tolerance_breadth > median
THEN "Vigorous grower; may become invasive in favourable conditions"
```

---

## Data Column Reference

| Column | Purpose |
|--------|---------|
| `pollinators` | Pollinator value score |
| `herbivores_*` | Wildlife food value |
| `carbon_total_rating` | Carbon storage assessment |
| `nitrogen_fixation_rating` | Soil building potential |
| `erosion_protection_rating` | Erosion control value |
| `C`, `S`, `R` | Invasive potential assessment |

---

## Integration with Other Sections

The biodiversity value section synthesises information presented in detail elsewhere:

| Summary Item | Detailed In |
|--------------|------------|
| Pollinator value | S5: Biological Interactions |
| Ecosystem services | S4: Ecosystem Services |
| Growing requirements | S2: Growing Requirements |
| Maintenance implications | S3: Maintenance Profile |
