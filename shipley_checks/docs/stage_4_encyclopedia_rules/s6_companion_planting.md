# S6: Companion Planting Rules

Rules for generating companion planting recommendations based on guild synergies.

## Scientific Foundation

**Theory**: Ecological guild assembly based on:
- Niche complementarity (different resource use patterns)
- Facilitation (one species benefits another)
- CSR strategy compatibility
- EIVE requirement matching

---

## Guild Compatibility Principles

### CSR Strategy Synergies

| Combination | Compatibility | Rationale |
|-------------|--------------|-----------|
| S + S | High | Similar low maintenance, drought tolerance |
| C + S | Moderate | C provides quick cover, S for long-term |
| C + C | Low | Competition for resources |
| R + any | Variable | Short-lived; succession planning needed |

### EIVE Matching Rules

Plants sharing similar EIVE values (±1 point) are likely compatible:

| Factor | Match Importance | Consequence of Mismatch |
|--------|-----------------|------------------------|
| M (Moisture) | Critical | Watering conflicts |
| L (Light) | High | Shading issues |
| R (pH) | High | Nutrient availability |
| N (Nitrogen) | Moderate | Feeding regime conflicts |
| T (Temperature) | Moderate | Hardiness differences |

---

## Beneficial Combinations

### Nitrogen-Fixers with Heavy Feeders

| N-Fixer (EIVE-N low) | + | Heavy Feeder (EIVE-N high) |
|---------------------|---|---------------------------|
| Legumes (Fabaceae) | + | Brassicas, leafy vegetables |
| Lupinus, Trifolium | + | Helianthus, Cucurbita |

**Output**:
```markdown
**Beneficial Pairing**: Nitrogen-fixer
Pairs well with heavy-feeding plants that benefit from soil nitrogen enrichment.
```

### Structural Guilds

| Layer | Role | Example Traits |
|-------|------|---------------|
| Canopy | Shade provision | Tree, H > 5m |
| Understory | Filtered light | Shrub, shade-tolerant (EIVE-L < 5) |
| Ground cover | Soil protection | Herb, H < 0.5m, spreading |

---

## Incompatibility Flags

### Resource Competition

```markdown
**Competition Warning**: C-dominant (C > 60%)
May outcompete slower-growing neighbours. Provide adequate spacing.
```

### Allelopathy Considerations

Some species produce allelopathic compounds. Flag known allelopaths:

```markdown
**Allelopathy Note**: May inhibit germination of nearby plants.
Consider as specimen or isolated planting.
```

### Water Requirement Conflicts

```markdown
**Moisture Mismatch Warning**: EIVE-M = 2 (drought-tolerant)
Incompatible with moisture-loving plants. Avoid pairing with bog plants.
```

---

## Output Format

```markdown
## Companion Planting

### Good Companions
Based on similar growing requirements (EIVE-M: 5, EIVE-L: 6, EIVE-R: 5):
- Other plants preferring moderate moisture, full sun to part shade
- Neutral to slightly acidic soil preferences

### Beneficial Associations
- **Nitrogen fixation**: Enriches soil for neighbouring plants
- **Pollinator support**: High - benefits pollination of nearby crops

### Avoid Planting With
- **Drought-tolerant plants**: Different watering needs (this plant EIVE-M: 7)
- **Calcifuges**: Soil pH mismatch (this plant prefers alkaline)

### Guild Suggestions
- **Food forest understory**: Shade-tolerant, pairs with fruit trees
- **Pollinator border**: Combines well with other nectar-rich perennials
```

---

## Data Requirements

Guild compatibility is calculated using:

| Data | Purpose |
|------|---------|
| CSR scores | Strategy compatibility |
| EIVE values (L, M, T, R, N) | Growing requirement matching |
| Height | Layer assignment |
| Nitrogen fixation rating | Beneficial pairing identification |
| Pollinator support | Ecosystem service synergies |

---

## Implementation Notes

The companion planting section is generated algorithmically based on:
1. EIVE similarity scores with other plants in the database
2. CSR compatibility rules
3. Known beneficial interactions (N-fixers, pollinators)
4. Known incompatibilities (allelopathy database, extreme requirement mismatches)

**Coverage**: Full recommendations available for species with complete EIVE and CSR data.
