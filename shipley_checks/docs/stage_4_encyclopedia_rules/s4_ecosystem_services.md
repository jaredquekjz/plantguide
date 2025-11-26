# S4: Ecosystem Services Rules

Rules for generating the ecosystem services section using pre-calculated categorical ratings.

## Scientific Foundation

**Theory**: Ecosystem services derived from CSR strategy theory (Pierce et al. 2017) and functional trait relationships.

**Data Source**: Pre-calculated ratings from Stage 3 pipeline based on:
- CSR scores → productivity, decomposition, nutrient dynamics
- Growth form and biomass → carbon storage
- Family-level nitrogen fixation data from TRY database

**Rating Scale**: Categorical (Very High, High, Moderate, Low, Very Low)

---

## Services Definitions

### M8: NPP (Net Primary Productivity)

**What it measures**: Rate of biomass production

| Rating | Interpretation | CSR Association |
|--------|---------------|-----------------|
| Very High | Very rapid growth | C > 70% |
| High | Rapid growth | C 50-70% |
| Moderate | Moderate growth | Balanced CSR |
| Low | Slow growth | S 50-70% |
| Very Low | Very slow growth | S > 70% |

**Garden relevance**: Higher NPP = faster establishment, more vigorous growth, may need more pruning

### M9: Decomposition Rate

**What it measures**: Speed at which plant litter breaks down

| Rating | Interpretation | CSR Association |
|--------|---------------|-----------------|
| Very High | Very fast breakdown | R-dominant |
| High | Fast breakdown | C-leaning |
| Moderate | Moderate breakdown | Balanced |
| Low | Slow breakdown | S-leaning |
| Very Low | Very slow breakdown | S > 70% |

**Garden relevance**: Higher decomposition = less persistent mulch, faster nutrient cycling

### M10: Nutrient Cycling

**What it measures**: Rate of nutrient turnover through plant-soil system

| Rating | Interpretation |
|--------|---------------|
| Very High | Rapid nutrient turnover |
| High | Active cycling |
| Moderate | Moderate cycling |
| Low | Slow cycling |
| Very Low | Minimal cycling |

**Garden relevance**: Higher cycling benefits soil fertility over time

### M11: Nutrient Retention

**What it measures**: Ability to hold nutrients in biomass/soil

| Rating | Interpretation |
|--------|---------------|
| Very High | Excellent nutrient storage |
| High | Good retention |
| Moderate | Moderate retention |
| Low | Limited retention |
| Very Low | Poor retention (leaching risk) |

**Garden relevance**: Higher retention = less need for repeated fertilisation

### M12: Nutrient Loss

**What it measures**: Potential for nutrient leaching or export

| Rating | Interpretation |
|--------|---------------|
| Very High | High loss potential |
| High | Elevated loss |
| Moderate | Moderate loss |
| Low | Limited loss |
| Very Low | Minimal loss |

**Garden relevance**: Higher loss = may need more frequent feeding, runoff considerations

### M13-15: Carbon Storage (Biomass, Recalcitrant, Total)

**What it measures**:
- M13 (Biomass): Carbon held in living plant tissue
- M14 (Recalcitrant): Carbon in slow-decomposing structural material
- M15 (Total): Combined carbon storage capacity

| Rating | Interpretation | Typical Plants |
|--------|---------------|----------------|
| Very High | Major carbon store | Large trees |
| High | Significant storage | Medium trees, large shrubs |
| Moderate | Moderate storage | Small trees, shrubs |
| Low | Limited storage | Herbaceous perennials |
| Very Low | Minimal storage | Annuals, small herbs |

**Garden relevance**: Climate-conscious planting; trees and long-lived shrubs store most carbon

### M16: Soil Erosion Protection

**What it measures**: Ability to stabilise soil

| Rating | Interpretation | Typical Plants |
|--------|---------------|----------------|
| Very High | Excellent stabilisation | Dense groundcovers, fibrous roots |
| High | Good stabilisation | Spreading habit, good root density |
| Moderate | Moderate protection | Most perennials |
| Low | Limited protection | Deep-rooted but sparse |
| Very Low | Poor protection | Sparse/shallow rooted |

**Garden relevance**: Important for slopes, banks, erosion-prone areas

### M17: Nitrogen Fixation

**What it measures**: Biological nitrogen fixation via rhizobium symbiosis

| Rating | Interpretation | Typical Plants |
|--------|---------------|----------------|
| Very High | Active N-fixer | Legumes (Fabaceae) |
| High | Moderate fixation | Some legumes |
| Moderate | Limited fixation | Non-legume associations |
| Low | Minimal fixation | - |
| Very Low / No Info | Not an N-fixer | Most non-legumes |

**Data source**: TRY database family-level classification (40.3% coverage)

**Garden relevance**: N-fixers improve soil fertility; excellent companions for heavy feeders

---

## Rating Conversion

For community-weighted means (guild scoring):

| Categorical | Numeric |
|-------------|---------|
| Very High | 5.0 |
| High | 4.0 |
| Moderate | 3.0 |
| Low | 2.0 |
| Very Low | 1.0 |
| Unable to Classify | NaN (excluded) |

### Numeric to Categorical Thresholds

| Score Range | Rating |
|-------------|--------|
| ≥ 4.5 | Very High |
| 3.5 - 4.5 | High |
| 2.5 - 3.5 | Moderate |
| 1.5 - 2.5 | Low |
| < 1.5 | Very Low |

---

## Confidence Levels

Each ecosystem service has an associated confidence column:

| Confidence | Meaning |
|------------|---------|
| High | Direct measurement or strong trait correlation |
| Medium | Inferred from related traits |
| Low | Extrapolated from family/genus patterns |
| Unable to Classify | Insufficient data |

---

## Output Format

```markdown
## Ecosystem Services

### Productivity
- **NPP**: High (4.0) - Rapid growth rate
- **Decomposition**: Moderate (3.0) - Moderate litter breakdown

### Nutrient Dynamics
- **Nutrient Cycling**: Moderate (3.0)
- **Nutrient Retention**: High (4.0) - Good nutrient storage
- **Nutrient Loss**: Low (2.0) - Limited leaching risk

### Carbon Storage
- **Biomass Carbon**: High (4.0) - Significant living carbon
- **Recalcitrant Carbon**: Moderate (3.0) - Some long-term storage
- **Total Carbon**: High (4.0)

### Soil Services
- **Erosion Protection**: Moderate (3.0)
- **Nitrogen Fixation**: Very High (5.0) - Active N-fixer (Fabaceae)

**Garden Value**: Good choice for improving soil fertility; fast-growing with good carbon storage.
```

---

## Data Column Reference

**Source file:** `shipley_checks/bill_foundational_data/stage3/bill_with_csr_ecoservices_11711.csv`

| Column | Description |
|--------|-------------|
| `npp_rating` | Net Primary Productivity rating |
| `decomposition_rating` | Decomposition rate rating |
| `nutrient_cycling_rating` | Nutrient cycling rating |
| `nutrient_retention_rating` | Nutrient retention rating |
| `nutrient_loss_rating` | Nutrient loss rating |
| `carbon_biomass_rating` | Carbon storage (biomass) rating |
| `carbon_recalcitrant_rating` | Carbon storage (recalcitrant) rating |
| `carbon_total_rating` | Carbon storage (total) rating |
| `erosion_protection_rating` | Erosion protection rating |
| `nitrogen_fixation_rating` | Nitrogen fixation rating |

All ratings have corresponding `*_confidence` columns (e.g., `npp_confidence`, `decomposition_confidence`).
