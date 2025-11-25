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

### Mycorrhizal Network Sharing

**Data source**: `fungi_searchable.parquet` mycorrhizal associations

Plants sharing the same mycorrhizal fungi can exchange nutrients and chemical signals underground.

| Mycorrhizal Type | Compatible Plants | Benefit |
|------------------|------------------|---------|
| AMF network | Most herbaceous plants, many shrubs | Shared phosphorus, carbon |
| EMF network | Oaks, birches, pines, beeches | Shared nutrients, pathogen warning signals |

**Algorithm**:
```
IF plant_A.mycorrhizal_fungi INTERSECT plant_B.mycorrhizal_fungi > 0
THEN "May share beneficial mycorrhizal network"
```

**Output**:
```markdown
**Mycorrhizal Synergy**: Shares ectomycorrhizal fungi with oaks and beeches
Consider planting together for underground nutrient sharing
```

### Biocontrol Habitat Guilds

**Data source**: `organisms_searchable.parquet` biocontrol organisms

Plants that attract overlapping beneficial predators create robust pest control zones.

| Biocontrol Guild | Plants to Combine | Shared Benefits |
|-----------------|-------------------|-----------------|
| Ladybird habitat | Umbellifer family, yarrow | Aphid control across plantings |
| Hoverfly habitat | Open-faced flowers | Multiple pest predation |
| Parasitoid habitat | Small-flowered plants | Caterpillar parasitism |

**Algorithm**:
```
IF plant_A.biocontrol_organisms INTERSECT plant_B.biocontrol_organisms > 3
THEN "Creates beneficial insect habitat together"
```

### Pollinator Guild Synergies

**Data source**: `pollinators` column

Plants sharing pollinators benefit from each other's attraction effects.

| Pollinator Guild | Benefit |
|-----------------|---------|
| Bumblebee plants | Longer flowering season when combined |
| Hoverfly plants | Dual pollination + biocontrol |
| Specialist plants | Support rare/important pollinators |

**Algorithm**:
```
IF plant_A.pollinators INTERSECT plant_B.pollinators >= 5
THEN "Mutually supports pollinator community"
```

### Entomopathogen Sharing

**Data source**: `insect_fungal_parasites_11711.parquet`

Plants whose herbivores share fungal enemies can create pest suppression zones.

**Concept**: If Plant A's caterpillars are killed by Beauveria, and Plant B's caterpillars are also killed by Beauveria, planting together may amplify the fungal pathogen population.

**Algorithm**:
```
FOR herbivores on plant_A:
  GET entomopathogenic_fungi
FOR herbivores on plant_B:
  GET entomopathogenic_fungi
IF INTERSECT > 0:
  "Shared biocontrol fungi may suppress pests on both plants"
```

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

| Data Source | Data | Purpose |
|-------------|------|---------|
| Phase 0 parquet | CSR scores (C, S, R) | Strategy compatibility |
| Phase 0 parquet | EIVE values (L, M, T, R, N) | Growing requirement matching |
| Phase 0 parquet | `height_m`, `try_growth_form` | Layer assignment |
| Phase 0 parquet | `nitrogen_fixation_rating` | Beneficial pairing identification |
| organisms_searchable | `is_pollinator`, pollinator list | Pollinator guild synergies |
| organisms_searchable | `is_biocontrol`, biocontrol list | Biocontrol habitat guilds |
| fungi_searchable | `is_mycorrhizal`, `is_amf`, `is_emf` | Mycorrhizal network matching |
| fungi_searchable | `is_entomopathogen` | Entomopathogen sharing |
| insect_fungal_parasites | herbivore → fungi mapping | Cross-plant pest suppression |

---

## Implementation Ideas

### Implemented (Current)

1. **EIVE similarity** - plants with similar L, M, T, R, N values (±1)
2. **CSR compatibility** - strategy-based pairing rules
3. **N-fixer identification** - flag Fabaceae and nitrogen-fixation-positive plants
4. **Structural layering** - height-based guild assignment

### Future Development Ideas

5. **Mycorrhizal network matching**
   - Query fungi_searchable for plants with overlapping `is_amf` or `is_emf` fungi
   - Group plants by shared mycorrhizal partners
   - Flag "may share underground network"

6. **Biocontrol habitat guilds**
   - Cluster plants by shared `is_biocontrol` organisms
   - Identify "IPM garden" combinations
   - Flag plants that together attract diverse beneficial insects

7. **Pollinator community synergies**
   - Calculate pollinator overlap between plants
   - Identify "pollinator corridor" combinations
   - Flag complementary flowering times (if phenology data added)

8. **Entomopathogen amplification zones**
   - Map herbivores per plant to their fungal enemies
   - Identify plant pairs whose pest communities share entomopathogenic fungi
   - Flag "natural biocontrol zone" combinations

9. **Succession planning**
   - Use CSR to plan temporal sequences (R → C → S)
   - Identify nurse plant combinations
   - Flag gap-filler species

10. **Pest deterrence guilds**
    - Identify plants with strong herbivore deterrent properties
    - Suggest trap-crop combinations
    - Flag allelopathic protection possibilities

### Algorithm Complexity

| Feature | Complexity | Data Size |
|---------|------------|-----------|
| EIVE matching | O(1) per plant | 11,711 plants |
| CSR compatibility | O(1) per plant | 11,711 plants |
| Mycorrhizal overlap | O(n²) pairwise | 1,381 mycorrhizal fungi |
| Biocontrol overlap | O(n²) pairwise | 50,259 biocontrol records |
| Entomopathogen chains | O(n²) via herbivore | 620 entomopathogens |

**Recommendation**: Pre-compute similarity matrices for expensive operations.

---

## Output Format (Expanded)

```markdown
## Companion Planting

### Growing Compatibility (EIVE Match)
Based on similar requirements (EIVE-M: 5, EIVE-L: 6, EIVE-R: 5, EIVE-N: 4):
- Compatible with: moderate moisture, full sun to part shade, slightly acid soil
- Good companions: other plants in the 4-6 range for all EIVE factors

### Functional Synergies
- **Nitrogen fixation**: This plant enriches soil (Fabaceae)
- **Mycorrhizal network**: Shares AMF fungi with most herbaceous perennials
- **Pollinator support**: Attracts bumblebees, hoverflies - benefits neighbours

### Biocontrol Synergies
- **Beneficial insects**: Attracts ladybirds, parasitic wasps
- **IPM value**: Creates habitat for natural pest control
- **Entomopathogen zone**: Shares Beauveria-susceptible herbivores with roses

### Structural Guild
- **Layer**: Understory shrub (1.5m)
- **Pairs with**: Canopy trees, ground cover plants
- **Food forest role**: Mid-layer, partial shade provider

### Avoid Planting With
- **C-dominant competitors**: May be outcompeted
- **EIVE-M > 7 plants**: Moisture requirement mismatch
- **Known allelopaths**: Black walnut, eucalyptus
```

**Coverage**: Full recommendations require EIVE, CSR, and organism/fungi data.
