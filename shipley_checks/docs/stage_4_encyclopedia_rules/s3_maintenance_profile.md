# S3: Maintenance Profile Rules

Rules for generating maintenance requirements based on CSR (Competitor-Stress tolerator-Ruderal) strategy.

## Scientific Foundation

**Theory**: Grime's CSR plant strategy theory classifies plants by their adaptation to:
- **C (Competitor)**: Resource-rich, undisturbed habitats → fast growth, high nutrient demand
- **S (Stress-tolerator)**: Resource-poor or extreme habitats → slow growth, conservative physiology
- **R (Ruderal)**: Frequently disturbed habitats → rapid reproduction, short lifespan

**Data Source**: Pierce et al. (2017) StrateFy global calibration using leaf traits (LA, LDMC, SLA)

**Columns**: `C`, `S`, `R` (percentages summing to 100)

---

## CSR Classification

### Spread-Based Classification (Recommended)

CSR dominance is determined by which axis is **highest** and whether there is clear differentiation between axes.

**Key metric**: `SPREAD = MAX(C,S,R) - MIN(C,S,R)`

| Spread | Classification | Meaning |
|--------|---------------|---------|
| < 20% | Balanced | All three axes similar; no dominant strategy |
| ≥ 20% | X-dominant | Highest axis (X) is the dominant strategy |

**Rationale**: A plant with C=42%, S=55%, R=3% has S as highest (spread=52%). Calling it "C-dominant" because C exceeds some threshold ignores that S is clearly the dominant strategy.

### Distribution in Dataset (11,712 plants)

| Strategy | Count | Percentage |
|----------|-------|------------|
| S-dominant | 5,625 | 48.0% |
| R-dominant | 3,124 | 26.7% |
| C-dominant | 2,305 | 19.7% |
| Balanced | 658 | 5.6% |

**Note**: European flora is naturally S-heavy (stress-tolerant). This reflects ecological reality, not a classification artifact.

### Intensity Levels

For finer granularity, use the highest axis value:

| Highest Axis Value | Intensity | Interpretation |
|-------------------|-----------|----------------|
| ≥ 80% | Extreme | Very strong single-strategy expression |
| 60-79% | Strong | Clear dominant strategy |
| 40-59% | Moderate | Dominant but with secondary influences |
| < 40% | Balanced | No clear dominant strategy |

---

## Legacy: Percentile-Based Thresholds

The previous approach used p75 thresholds per axis:

| Strategy | p75 Threshold | Issue |
|----------|---------------|-------|
| C-dominant | C > 41.3% | Plant with C=42%, S=55% classified as "C-dominant" |
| S-dominant | S > 72.2% | Plant with S=70% (highest) classified as "Balanced" |
| R-dominant | R > 47.6% | Different thresholds per axis create confusion |

**Problem**: 2,456 plants where S is highest (40-72%) were classified as "Balanced" because S didn't exceed 72.2%.

**Recommendation**: Use spread-based classification for encyclopedia and companion planting. Percentile thresholds may still be useful for research comparisons within axes.

---

## CSR to Horticultural Traits

| Property | C-Dominant | S-Dominant | R-Dominant | Balanced |
|----------|-----------|-----------|-----------|----------|
| **Growth Rate** | Fast, vigorous | Slow, steady | Rapid but brief | Moderate |
| **Nutrient Demand** | HIGH | LOW | Moderate | Moderate |
| **Water Demand** | Moderate-high | LOW (drought-tolerant) | Moderate | Moderate |
| **Maintenance** | HIGH (5-7 hrs/yr) | LOW (1-2 hrs/yr) | MEDIUM (replanting) | MEDIUM (3-4 hrs/yr) |
| **Pruning** | Regular shaping | Minimal | Deadheading | Standard |
| **Lifespan** | Variable | Often long-lived | Short (annual-biennial) | Variable |
| **Decomposition** | Variable | Slow (recalcitrant) | Fast (labile) | Moderate |

---

## Maintenance Level Algorithm

### Primary Classification (Spread-Based)

```
1. Calculate SPREAD = MAX(C,S,R) - MIN(C,S,R)
2. IF SPREAD < 20%: Balanced
3. ELSE: Dominant = axis with highest value
```

| Dominant Strategy | Highest Value | Maintenance Level | Time Estimate |
|------------------|---------------|-------------------|---------------|
| S-dominant | ≥ 80% | LOW | 1-2 hrs/yr |
| S-dominant | 60-79% | LOW | 1-2 hrs/yr |
| S-dominant | 40-59% | LOW-MEDIUM | 2-3 hrs/yr |
| C-dominant | ≥ 80% | HIGH | 5-7 hrs/yr |
| C-dominant | 60-79% | HIGH | 5-7 hrs/yr |
| C-dominant | 40-59% | MEDIUM-HIGH | 4-5 hrs/yr |
| R-dominant | any | MEDIUM | 3-4 hrs/yr |
| Balanced | (spread < 20%) | MEDIUM | 3-4 hrs/yr |

### Size Scaling

Multiply base time by size factor:
- Height < 1m: ×0.5
- Height 1-2m: ×1.0
- Height 2-4m: ×1.5
- Height > 4m: ×2.0

---

## Composite Maintenance Matrix (CSR × Height × Growth Form)

Maintenance advice depends on the interaction of strategy, height, and growth form.

### Trees (height > 5m)

| CSR Profile | Maintenance Focus | Key Tasks |
|-------------|-------------------|-----------|
| C-dominant | Containment, shaping | Annual pruning to control spread; may overshadow garden; thinning for light penetration |
| S-dominant | Minimal intervention | Formative pruning only in youth; avoid fertiliser; long establishment period |
| Balanced | Moderate structure | Periodic structural pruning; standard seasonal care |

### Shrubs (height 1-5m)

| CSR Profile | Maintenance Focus | Key Tasks |
|-------------|-------------------|-----------|
| C-dominant | Regular pruning | Hard prune annually; may sucker or spread aggressively; contain root spread |
| S-dominant | Minimal pruning | Shape only if needed; drought-tolerant once established |
| R-dominant | Succession planning | May self-seed or die back; remove spent growth; allow regeneration |
| Balanced | Standard care | Annual light pruning; feed as needed |

### Herbs/Ground covers (height < 1m)

| CSR Profile | Maintenance Focus | Key Tasks |
|-------------|-------------------|-----------|
| C-dominant | Spreading control | May outcompete neighbours; division or edging required; vigorous feeders |
| S-dominant | Near-zero maintenance | Avoid overwatering; no fertiliser needed; leave undisturbed |
| R-dominant | Replanting cycles | Short-lived; collect seed; allow self-sowing or replant annually |
| Balanced | Light seasonal care | Deadhead, tidy, occasional feed |

### Vines/Climbers

| CSR Profile | Maintenance Focus | Key Tasks |
|-------------|-------------------|-----------|
| C-dominant | Aggressive training | Regular cutting back; will smother supports if unchecked; may damage structures |
| S-dominant | Occasional guidance | Slow establishment; train in youth, then minimal intervention |
| R-dominant | Annual regrowth | May die back in winter; cut to base; fast spring growth |
| Balanced | Moderate training | Annual tidy; tie in new growth; manageable vigour |

---

## Strategy-Specific Advice

### C-Dominant (Competitors)

**Trees (>5m)**:
- Annual thinning to allow light below; may cast dense shade
- Monitor for structural dominance; neighbours may struggle
- High nutrient uptake; nearby plants may need supplemental feeding

**Shrubs (1-5m)**:
- Hard prune annually to control spread; suckering common
- Give wide spacing; aggressive root competition likely
- Contain with root barriers if space is limited

**Herbs (<1m)**:
- Division every 1-2 years to control spread
- Edge beds to prevent invasion of adjacent areas
- Heavy feeders; enrich soil annually

**Vines**:
- Aggressive growers; may damage supports or smother host plants
- Regular cutting back (2-3 times per growing season)
- Do not plant near buildings without robust control measures

---

### S-Dominant (Stress-tolerators)

**Trees (>5m)**:
- Long establishment period (5-10 years); patience required
- Avoid fertiliser; naturally conservative nutrient cycling
- Formative pruning in youth only; minimal intervention thereafter

**Shrubs (1-5m)**:
- Drought-tolerant once established; minimal watering
- Shape only if aesthetically needed; avoid hard pruning
- Slow recovery from damage; protect during establishment

**Herbs (<1m)**:
- Near-zero maintenance; leave undisturbed
- Avoid overwatering; adapted to poor soils
- May decline if conditions become too rich

**Vines**:
- Slow to establish; train carefully in first years
- Once established, minimal intervention required
- Avoid fertiliser; will not respond well to rich conditions

---

### R-Dominant (Ruderals)

**Shrubs (1-5m)**:
- Often short-lived (3-5 years); plan for replacement
- Self-seeding may require management
- Remove spent growth promptly; encourages new growth

**Herbs (<1m)**:
- Annuals or short-lived perennials; replant each year or allow self-sowing
- Deadhead to extend flowering or allow seeding depending on preference
- Collect seed before removal for next season

**Vines**:
- May die back completely in winter; cut to base
- Rapid spring regrowth from base or seed
- Short-lived perennials or tender; protect or replant annually

---

### Balanced CSR

All growth forms:
- Standard garden care applies
- Adaptable to range of conditions
- Moderate vigour; manageable with annual attention
- Responsive to feeding but not demanding

---

## Invasive Potential

Use CSR classification + climate envelope to flag invasive risk:

| Pattern | Risk | Flag |
|---------|------|------|
| C-dominant (highest ≥ 60%) + wide climate tolerance | HIGH | "Vigorous; may become invasive in mild climates" |
| R-dominant + prolific seeding | MODERATE | "Self-seeds freely; may need containment" |
| S-dominant | LOW | "Unlikely to spread aggressively" |

---

## Output Format

```markdown
## Maintenance Profile

**CSR Strategy**: C 45% / S 35% / R 20% (C-dominant)
**Growth Form**: Shrub
**Height**: 2.5m
**Maintenance Level**: MEDIUM-HIGH (~4-5 hrs/yr)

**Growth Characteristics**:
- Moderately vigorous grower (C-dominant shrub)
- Benefits from annual feeding
- Prune to shape in late winter

**Form-Specific Notes**:
- {advice from Composite Maintenance Matrix based on growth form + CSR}

**Seasonal Tasks**:
- Spring: Feed, shape if needed
- Summer: Water in dry spells
- Autumn: Mulch, tidy
- Winter: Protect if borderline hardy

**Watch For**:
- May outcompete slower neighbours (C tendency)
- Give adequate space for mature spread
```

### Decision Tree for Output Generation

```
1. Determine CSR classification (spread-based):
   - SPREAD = MAX(C,S,R) - MIN(C,S,R)
   - IF SPREAD < 20%: Balanced
   - ELSE: Dominant = highest of C, S, R

2. Determine intensity:
   - Highest axis ≥ 80%: Extreme
   - Highest axis 60-79%: Strong
   - Highest axis 40-59%: Moderate
   - Highest axis < 40%: Balanced

3. Determine growth form category:
   - IF try_growth_form CONTAINS "tree" AND height > 5m: Tree
   - ELSE IF try_growth_form CONTAINS "vine" OR "liana": Vine
   - ELSE IF height > 1m: Shrub
   - ELSE: Herb/Ground cover

4. Look up advice from:
   - Composite Maintenance Matrix (CSR × Growth Form)
   - Strategy-Specific Advice (CSR × Growth Form)
   - Size Scaling (Height)

5. Generate output combining all factors
```

---

## Data Column Reference

**Source file:** `shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet`

| Column | Description |
|--------|-------------|
| `C` | Competitor score (0-100%) |
| `S` | Stress-tolerator score (0-100%) |
| `R` | Ruderal score (0-100%) |
| `height_m` | Plant height for size scaling |
| `try_growth_form` | Growth form (tree/shrub/herb/vine/etc.) |
| `life_form_simple` | Simplified life form (woody/non-woody) |
| `decomposition_rating` | Litter decomposition rate |

---

## Summary: Spread-Based vs Percentile-Based

| Aspect | Spread-Based (Recommended) | Percentile-Based (Legacy) |
|--------|---------------------------|--------------------------|
| Definition | Highest axis is dominant if spread ≥ 20% | Axis exceeds its p75 threshold |
| Balanced | 658 plants (5.6%) | 3,342 plants (28.5%) |
| S-dominant | 5,625 plants (48.0%) | 2,922 plants (24.9%) |
| Ecological validity | High - reflects actual dominant strategy | Moderate - identifies unusual values per axis |
| Use case | Encyclopedia, gardening advice | Research, within-axis comparisons |
