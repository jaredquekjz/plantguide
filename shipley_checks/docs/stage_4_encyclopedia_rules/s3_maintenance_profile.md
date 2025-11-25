# S3: Maintenance Profile Rules

Rules for generating maintenance requirements based on CSR (Competitor-Stress tolerator-Ruderal) strategy.

## Scientific Foundation

**Theory**: Grime's CSR plant strategy theory classifies plants by their adaptation to:
- **C (Competitor)**: Resource-rich, undisturbed habitats → fast growth, high nutrient demand
- **S (Stress-tolerator)**: Resource-poor or extreme habitats → slow growth, conservative physiology
- **R (Ruderal)**: Frequently disturbed habitats → rapid reproduction, short lifespan

**Data Source**: Pierce et al. (2017) StrateFy global calibration using leaf traits (LA, LDMC, SLA)

**Columns**: `C`, `S`, `R` (proportions summing to 1.0 or percentages summing to 100)

---

## CSR to Horticultural Traits

| Property | C-Dominant (>60%) | S-Dominant (>60%) | R-Dominant (>60%) |
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

### Primary Classification

| Condition | Maintenance Level | Time Estimate |
|-----------|------------------|---------------|
| S > 60% | LOW | 1-2 hrs/yr |
| S > 50% | LOW-MEDIUM | 2-3 hrs/yr |
| C > 60% | HIGH | 5-7 hrs/yr |
| C > 50% | MEDIUM-HIGH | 4-5 hrs/yr |
| R > 60% | MEDIUM | 3-4 hrs/yr |
| Balanced | MEDIUM | 3-4 hrs/yr |

### Size Scaling

Multiply base time by size factor:
- Height < 1m: ×0.5
- Height 1-2m: ×1.0
- Height 2-4m: ×1.5
- Height > 4m: ×2.0

---

## Strategy-Specific Advice

### C-Dominant (Competitors)

```
**Growth Rate**: Fast (C strategy)
- Vigorous grower; benefits from rich soil
- Regular pruning to maintain shape
- May outcompete neighbors; give adequate space
- Annual feeding recommended

**Maintenance Tasks**:
- Spring: Hard prune if needed, feed generously
- Summer: Shape pruning, water in dry spells
- Autumn: Tidy, mulch
- Monitor for: Excessive spread, shading neighbors
```

### S-Dominant (Stress-tolerators)

```
**Growth Rate**: Slow (S strategy)
- Steady, conservative growth
- Minimal pruning needed
- Drought-tolerant once established
- Avoid overwatering and overfeeding

**Maintenance Tasks**:
- Spring: Light tidy only
- Summer: Water only in extended drought
- Autumn: Minimal intervention
- Monitor for: Overwatering damage, nutrient toxicity
```

### R-Dominant (Ruderals)

```
**Growth Rate**: Rapid establishment (R strategy)
- Quick to establish from seed
- May self-seed prolifically
- Short-lived; plan for succession
- Deadhead to control spread

**Maintenance Tasks**:
- Spring: Allow self-sown seedlings or replant
- Summer: Deadhead regularly
- Autumn: Collect seed, remove spent plants
- Monitor for: Excessive self-seeding, weediness
```

### Balanced CSR

```
**Growth Rate**: Moderate (balanced CSR)
- Adaptable growth habit
- Moderate requirements
- Standard garden care appropriate

**Maintenance Tasks**:
- Standard seasonal care
- Annual feed and mulch
- Prune as needed for shape
```

---

## Invasive Potential

Use CSR + climate envelope to flag invasive risk:

| Pattern | Risk | Flag |
|---------|------|------|
| C > 70% + wide climate tolerance | HIGH | "Vigorous; may become invasive in mild climates" |
| R > 60% + prolific seeding | MODERATE | "Self-seeds freely; may need containment" |
| S > 60% | LOW | "Unlikely to spread aggressively" |

---

## Output Format

```markdown
## Maintenance Profile

**CSR Strategy**: C 45% / S 35% / R 20% (C-leaning)
**Maintenance Level**: MEDIUM-HIGH (~4-5 hrs/yr for 2m plant)

**Growth Characteristics**:
- Moderately vigorous grower
- Benefits from annual feeding
- Prune to shape in late winter

**Seasonal Tasks**:
- Spring: Feed, shape if needed
- Summer: Water in dry spells
- Autumn: Mulch, tidy
- Winter: Protect if borderline hardy

**Watch For**:
- May outcompete slower neighbors
- Give adequate space for mature spread
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
