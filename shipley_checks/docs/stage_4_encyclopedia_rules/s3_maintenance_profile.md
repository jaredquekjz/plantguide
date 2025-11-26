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

### Percentile-Based Thresholds (GuildBuilder)

CSR dominance is determined by **percentile ranking** across all 11,711 plants, not absolute values.

| Strategy | p75 Raw Value | Meaning |
|----------|---------------|---------|
| C (Competitor) | 41.3% | Top 25% of plants by C score |
| S (Stress-tolerator) | 72.2% | Top 25% of plants by S score |
| R (Ruderal) | 47.6% | Top 25% of plants by R score |

A plant is classified as "C-dominant" if its C percentile > 75 (i.e., raw C > 41.3%), not if C > 60%.

### Absolute Thresholds (Ecosystem Services)

The ecosystem services module (Stage 3) uses simpler absolute thresholds for rating classification:

| Threshold | Used For |
|-----------|----------|
| C/S/R ≥ 60% | "Very High" ecosystem service ratings |
| C/S/R ≥ 45% | "High" ecosystem service ratings |

**Note**: The CSR percentile classification is more ecologically meaningful for companion planting decisions. Absolute thresholds are used for ecosystem service ratings due to their direct interpretation.

---

## CSR to Horticultural Traits

| Property | C-Dominant (p75+) | S-Dominant (p75+) | R-Dominant (p75+) |
|----------|-------------------|-------------------|-------------------|
| **Growth Rate** | Fast, vigorous | Slow, steady | Rapid but brief |
| **Nutrient Demand** | HIGH | LOW | Moderate |
| **Water Demand** | Moderate-high | LOW (drought-tolerant) | Moderate |
| **Maintenance** | HIGH (5-7 hrs/yr) | LOW (1-2 hrs/yr) | MEDIUM (replanting) |
| **Pruning** | Regular shaping | Minimal | Deadheading |
| **Lifespan** | Variable | Often long-lived | Short (annual-biennial) |
| **Decomposition** | Variable | Slow (recalcitrant) | Fast (labile) |

---

## Maintenance Level Algorithm

### Primary Classification (Percentile-Based)

| Condition | Maintenance Level | Time Estimate |
|-----------|------------------|---------------|
| S percentile > 90 | LOW | 1-2 hrs/yr |
| S percentile > 75 | LOW-MEDIUM | 2-3 hrs/yr |
| C percentile > 90 | HIGH | 5-7 hrs/yr |
| C percentile > 75 | MEDIUM-HIGH | 4-5 hrs/yr |
| R percentile > 75 | MEDIUM | 3-4 hrs/yr |
| Balanced (no p75+) | MEDIUM | 3-4 hrs/yr |

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

Use CSR percentile + climate envelope to flag invasive risk:

| Pattern | Risk | Flag |
|---------|------|------|
| C percentile > 90 + wide climate tolerance | HIGH | "Vigorous; may become invasive in mild climates" |
| R percentile > 75 + prolific seeding | MODERATE | "Self-seeds freely; may need containment" |
| S percentile > 75 | LOW | "Unlikely to spread aggressively" |

---

## Output Format

```markdown
## Maintenance Profile

**CSR Strategy**: C 45% / S 35% / R 20% (C-leaning)
**Growth Form**: Shrub
**Height**: 2.5m
**Maintenance Level**: MEDIUM-HIGH (~4-5 hrs/yr)

**Growth Characteristics**:
- Moderately vigorous grower (C-leaning shrub)
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
1. Determine CSR classification (percentile-based):
   - C percentile > 75: C-dominant (raw C > 41.3%)
   - S percentile > 75: S-dominant (raw S > 72.2%)
   - R percentile > 75: R-dominant (raw R > 47.6%)
   - else: Balanced

2. Determine growth form category:
   - IF try_growth_form CONTAINS "tree" AND height > 5m: Tree
   - ELSE IF try_growth_form CONTAINS "vine" OR "liana": Vine
   - ELSE IF height > 1m: Shrub
   - ELSE: Herb/Ground cover

3. Look up advice from:
   - Composite Maintenance Matrix (CSR × Growth Form)
   - Strategy-Specific Advice (CSR × Growth Form)
   - Size Scaling (Height)

4. Generate output combining all three factors
```

---

## Data Column Reference

| Column | Description |
|--------|-------------|
| `C` | Competitor score (0-1 or 0-100) |
| `S` | Stress-tolerator score (0-1 or 0-100) |
| `R` | Ruderal score (0-1 or 0-100) |
| `height_m` | Plant height for size scaling |
| `try_growth_form` | Growth form (tree/shrub/herb) |
| `decomposition_rating` | Litter decomposition rate |
