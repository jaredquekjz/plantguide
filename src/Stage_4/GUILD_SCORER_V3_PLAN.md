# Guild Scorer V3 - Implementation Plan

**Goal**: Implement Document 4.3 framework EXACTLY as specified

**Date**: 2025-11-02

---

## Framework Structure (from Document 4.3)

### FINAL SCORE FORMULA:
```
guild_score = positive_benefit_score - negative_risk_score
Range: [-1, +1]
```

Where:
- `negative_risk_score ∈ [0, 1]` (aggregated from N1, N2, N4, N5, N6)
- `positive_benefit_score ∈ [0, 1]` (aggregated from P1, P2, P3, P4, P5, P6)

### FILTERS (Hard Veto):
- **F1**: Climate compatibility (3-level check)

### NEGATIVE FACTORS (weights sum to 100%):
- **N1**: Pathogen fungi overlap (35%)
- **N2**: Herbivore overlap (35%)
- **N4**: CSR conflicts modulated by EIVE+height+form (20%)
- **N5**: Absence of nitrogen fixation (5%)
- **N6**: Soil pH incompatibility (5%)

### POSITIVE FACTORS (weights sum to 100%):
- **P1**: Cross-plant biocontrol (25%)
- **P2**: Pathogen antagonists (20%)
- **P3**: Beneficial fungal networks (15%)
- **P4**: Phylogenetic diversity via eigenvectors (20%)
- **P5**: Vertical and form stratification (10%)
- **P6**: Shared pollinators (10%)

---

## Component Specifications

### F1: Climate Compatibility Filter

**Data Source**:
- Document 4.3, lines 55-254
- Stage 3 climate indicators (408 columns)
- Key columns: `bio_1_q05`, `bio_1_q95`, `bio_6_q05`, `bio_6_q95`, `bio_12_q05`, `bio_12_q95`

**Level 1: Tolerance Envelope Overlap**
```python
# Temperature
shared_temp_min = climate['temp_annual_min'].max()  # Warmest plant's minimum
shared_temp_max = climate['temp_annual_max'].min()  # Coldest plant's maximum
temp_overlap = shared_temp_max - shared_temp_min

# VETO if temp_overlap < 0
```

**Level 2: Hardiness Overlap**
```python
shared_hardiness_min = climate['temp_coldest_min'].max()
shared_hardiness_max = climate['temp_coldest_max'].min()
hardiness_overlap = shared_hardiness_max - shared_hardiness_min

# VETO if hardiness_overlap < -5.0
```

**Level 3: Extreme Vulnerabilities (WARNING only, not VETO)**
```python
# Check CDD (drought), CFD (frost), WSDI (heat), CSDI (cold)
# Return warnings, not vetoes
```

---

### N1: Pathogen Fungi Overlap (35%)

**Data Source**:
- Document 4.2, lines 91-141
- `plant_fungal_guilds_hybrid.parquet`: `pathogenic_fungi`, `pathogenic_fungi_host_specific`

**Formula**:
```python
pathogen_overlap_raw = 0

for fungus, plant_count in shared_pathogenic_fungi.items():
    if plant_count < 2:
        continue

    overlap_ratio = plant_count / total_plants
    overlap_penalty = overlap_ratio ** 2  # Quadratic

    severity = 1.0 if is_host_specific(fungus) else 0.6
    pathogen_overlap_raw += overlap_penalty * severity

# Normalize
pathogen_fungi_norm = tanh(pathogen_overlap_raw / 8.0)
```

**Weight in negative_risk_score**: 35%

---

### N2: Herbivore Overlap (35%)

**Data Source**:
- Document 4.2, lines 144-163
- `plant_organism_profiles.parquet`: `herbivores`
- **CRITICAL**: Exclude `flower_visitors` from herbivores (pollinators are beneficial!)

**Formula**:
```python
# Get all herbivores
all_herbivores = count_shared_organisms(data, 'herbivores')

# Get all pollinators/visitors
all_visitors = count_shared_organisms(data, 'flower_visitors', 'pollinators')

# Herbivores that are NOT visitors = true pests
shared_true_herbivores = {h: count for h, count in all_herbivores.items()
                           if h not in all_visitors}

herbivore_overlap_raw = 0
for herbivore, plant_count in shared_true_herbivores.items():
    if plant_count < 2:
        continue

    overlap_ratio = plant_count / total_plants
    overlap_penalty = overlap_ratio ** 2
    herbivore_overlap_raw += overlap_penalty * 0.5

herbivore_norm = tanh(herbivore_overlap_raw / 4.0)
```

**Weight in negative_risk_score**: 35%

---

### N4: CSR Conflicts (20%)

**Data Source**:
- Document 4.3, lines 681-979
- Columns: `C`, `S`, `R`, `"EIVEres-L"`, `height_m`, `try_growth_form`

**Conflict Types**:
| Type | Base Conflict | Modulation |
|------|---------------|------------|
| High-C + High-C | 1.0 | Height separation, growth form |
| High-C + High-S | 0.6 | EIVE-L (shade adaptation!) |
| High-C + High-R | 0.8 | Height separation |
| High-R + High-R | 0.3 | None |

**Thresholds**:
- High-C: C > 60
- High-S: S > 60
- High-R: R > 50

**Modulation Rules**:

1. **Growth Form** (first priority):
   - Vine + Tree: ×0.2 (symbiotic)
   - Tree + Herb: ×0.4 (different strategies)

2. **Height Separation** (if same form):
   - < 2m: ×1.0 (intense)
   - 2-5m: ×0.6 (moderate)
   - > 5m: ×0.3 (low)

3. **EIVE-L** (for C+S conflicts):
   - S plant L < -0.5: ×0.0 (shade-adapted, compatible!)
   - S plant L > +0.5: ×1.5 (sun-loving, high conflict!)

**Normalization**:
```python
max_conflicts = n_plants * (n_plants - 1) / 2
csr_conflict_norm = min(conflicts / max_conflicts, 1.0) if max_conflicts > 0 else 0
```

**Weight in negative_risk_score**: 20%

---

### N5: Nitrogen Fixation Absence (5%)

**Data Source**:
- Document 4.3, lines 1204-1244
- Column: `n_fixation` (TRUE/FALSE)

**Formula**:
```python
n_fixers = plants['n_fixation'].sum()

if n_fixers == 0:
    n_fix_penalty = 1.0  # No N-fixers = maximum penalty
elif n_fixers >= 2:
    n_fix_penalty = 0.0  # 2+ N-fixers = no penalty
else:
    n_fix_penalty = 0.5  # 1 N-fixer = partial penalty
```

**Weight in negative_risk_score**: 5%

---

### N6: Soil pH Incompatibility (5%)

**Data Source**:
- Document 4.3, lines 1246-1286
- Column: `pH_mean`

**Formula**:
```python
pH_range = plants['pH_mean'].max() - plants['pH_mean'].min()

if pH_range > 2.5:
    pH_penalty = 1.0  # Extreme incompatibility
elif pH_range > 1.5:
    pH_penalty = 0.5  # Moderate incompatibility
else:
    pH_penalty = 0.0  # Compatible
```

**Weight in negative_risk_score**: 5%

---

### NEGATIVE AGGREGATION:
```python
negative_risk_score = (
    0.35 * pathogen_fungi_norm +
    0.35 * herbivore_norm +
    0.20 * csr_conflict_norm +
    0.05 * n_fix_penalty +
    0.05 * pH_penalty
)
# Result: [0, 1]
```

---

## POSITIVE FACTORS

### P1: Cross-Plant Biocontrol (25%)

**Data Source**:
- Document 4.2, lines 210-259
- Requires: `herbivore_predators.parquet`, `insect_fungal_parasites.parquet`

**Formula** (PAIRWISE):
```python
biocontrol_raw = 0

for plant_a in guild:
    for plant_b in guild:
        if plant_a == plant_b:
            continue

        herbivores_a = profiles[plant_a]['herbivores']
        visitors_b = profiles[plant_b]['flower_visitors']

        # Mechanism 1: Specific animal predators
        for herbivore in herbivores_a:
            if herbivore in herbivore_predators:
                predators = herbivore_predators[herbivore]['predators']
                matching = visitors_b.intersection(predators)
                biocontrol_raw += len(matching) * 1.0

        # Mechanism 2: Specific entomopathogenic fungi
        # ... (similar)

        # Mechanism 3: General entomopathogenic fungi
        entomo_b = fungal[plant_b]['entomopathogenic_fungi']
        if len(herbivores_a) > 0 and len(entomo_b) > 0:
            biocontrol_raw += len(entomo_b) * 0.2

max_pairs = n_plants * (n_plants - 1)
herbivore_control_norm = tanh(biocontrol_raw / max_pairs * 20) if max_pairs > 0 else 0
```

**Weight in positive_benefit_score**: 25%

---

### P2: Pathogen Antagonists (20%)

**Data Source**:
- Document 4.2, lines 287-333
- Requires: `pathogen_antagonists.parquet`

**Formula** (PAIRWISE):
```python
pathogen_control_raw = 0

for plant_a in guild:
    for plant_b in guild:
        if plant_a == plant_b:
            continue

        pathogens_a = fungal[plant_a]['pathogenic_fungi']
        mycoparasites_b = fungal[plant_b]['mycoparasite_fungi']

        # Mechanism 1: Specific antagonist matches
        for pathogen in pathogens_a:
            if pathogen in pathogen_antagonists:
                antagonists = pathogen_antagonists[pathogen]['antagonists']
                matching = mycoparasites_b.intersection(antagonists)
                pathogen_control_raw += len(matching) * 1.0

        # Mechanism 2: General mycoparasites
        if len(pathogens_a) > 0 and len(mycoparasites_b) > 0:
            pathogen_control_raw += len(mycoparasites_b) * 0.3

max_pairs = n_plants * (n_plants - 1)
pathogen_control_norm = tanh(pathogen_control_raw / max_pairs * 10) if max_pairs > 0 else 0
```

**Weight in positive_benefit_score**: 20%

---

### P3: Beneficial Fungal Networks (15%)

**Data Source**:
- Document 4.2, lines 336-389
- Columns: `amf_fungi`, `emf_fungi`, `endophytic_fungi`, `saprotrophic_fungi`

**Formula**:
```python
shared_beneficial = count_shared_organisms(
    fungal,
    'amf_fungi',
    'emf_fungi',
    'endophytic_fungi',
    'saprotrophic_fungi'
)

network_raw = 0
for fungus, plant_count in shared_beneficial.items():
    if plant_count >= 2:
        coverage = plant_count / total_plants
        network_raw += coverage  # Linear, not quadratic!

# Coverage bonus
plants_with_beneficial = count_plants_with_any_beneficial_fungi()
coverage_ratio = plants_with_beneficial / total_plants

beneficial_fungi_raw = network_raw * 0.6 + coverage_ratio * 0.4
beneficial_fungi_norm = tanh(beneficial_fungi_raw / 3.0)
```

**Weight in positive_benefit_score**: 15%

---

### P4: Phylogenetic Diversity (20%)

**Data Source**:
- Document 4.3, lines 980-1042
- Columns: `phylo_ev1` through `phylo_ev10` (first 10 eigenvectors)

**Formula**:
```python
from scipy.spatial.distance import pdist

# Get first 10 eigenvectors
ev_cols = [f'phylo_ev{i}' for i in range(1, 11)]
ev_matrix = phylo[ev_cols].values

# Compute pairwise phylogenetic distances
distances = pdist(ev_matrix, metric='euclidean')

# Mean pairwise distance
mean_distance = np.mean(distances) if len(distances) > 0 else 0

# Normalize (typical range: 0-5 for 10 eigenvectors)
phylo_diversity_norm = np.tanh(mean_distance / 3)
```

**Weight in positive_benefit_score**: 20%

---

### P5: Vertical and Form Stratification (10%)

**Data Source**:
- Document 4.3, lines 1045-1203
- Columns: `height_m`, `try_growth_form`

**Height Layers**:
- Ground cover: 0-0.5m
- Low herb: 0.5-2m
- Shrub: 2-5m
- Small tree: 5-15m
- Large tree: 15m+

**Formula**:
```python
# COMPONENT 1: Height diversity (60%)
n_height_layers = plants['height_layer'].nunique()
height_diversity = (n_height_layers - 1) / 4  # 5 layers max

height_range = plants['height_m'].max() - plants['height_m'].min()
height_range_norm = np.tanh(height_range / 10)

height_score = 0.6 * height_diversity + 0.4 * height_range_norm

# COMPONENT 2: Form diversity (40%)
n_forms = plants['try_growth_form'].nunique()
form_diversity = (n_forms - 1) / 5  # 6 forms max

# Combined
stratification_norm = 0.6 * height_score + 0.4 * form_diversity
```

**Weight in positive_benefit_score**: 10%

---

### P6: Shared Pollinators (10%)

**Data Source**:
- Document 4.3, lines 1287-1347
- Column: `flower_visitors` from `plant_organism_profiles.parquet`

**Formula**:
```python
shared_pollinators = count_shared_organisms(data, 'flower_visitors', 'pollinators')

overlap_score = 0
for pollinator, plant_count in shared_pollinators.items():
    if plant_count >= 2:
        overlap_ratio = plant_count / total_plants
        overlap_score += overlap_ratio ** 2  # Quadratic benefit

shared_pollinator_norm = np.tanh(overlap_score / 5.0)
```

**Weight in positive_benefit_score**: 10%

---

### POSITIVE AGGREGATION:
```python
positive_benefit_score = (
    0.25 * herbivore_control_norm +
    0.20 * pathogen_control_norm +
    0.15 * beneficial_fungi_norm +
    0.20 * phylo_diversity_norm +
    0.10 * stratification_norm +
    0.10 * shared_pollinator_norm
)
# Result: [0, 1]
```

---

## Data Requirements

### Required Parquet Files:
1. **Main dataset**: `perm2_11680_with_climate_sensitivity_20251102.parquet`
   - Plant traits, climate, CSR, EIVE, phylo eigenvectors

2. **Organisms**: `plant_organism_profiles.parquet`
   - herbivores, flower_visitors, pollinators

3. **Fungi**: `plant_fungal_guilds_hybrid.parquet`
   - pathogenic_fungi, pathogenic_fungi_host_specific
   - amf_fungi, emf_fungi, endophytic_fungi, saprotrophic_fungi
   - mycoparasite_fungi, entomopathogenic_fungi

4. **Relationships** (for P1, P2):
   - `herbivore_predators.parquet` (herbivore → predators)
   - `insect_fungal_parasites.parquet` (herbivore → parasitic fungi)
   - `pathogen_antagonists.parquet` (pathogen → antagonistic fungi)

---

## Implementation Strategy

### Phase 1: Core Structure
1. Create `GuildScorerV3` class
2. Implement data loading with DuckDB
3. Implement helper functions (`count_shared_organisms`, etc.)

### Phase 2: Climate Filter
1. F1 Level 1: Tolerance envelope overlap
2. F1 Level 2: Hardiness compatibility
3. F1 Level 3: Extreme vulnerabilities (warnings)

### Phase 3: Negative Factors
1. N1: Pathogen fungi overlap (35%)
2. N2: Herbivore overlap (35%)
3. N4: CSR conflicts with modulation (20%)
4. N5: N-fixation absence (5%)
5. N6: pH incompatibility (5%)

### Phase 4: Positive Factors
1. P1: Cross-plant biocontrol (25%)
2. P2: Pathogen antagonists (20%)
3. P3: Beneficial fungi networks (15%)
4. P4: Phylogenetic eigenvectors (20%)
5. P5: Vertical/form stratification (10%)
6. P6: Shared pollinators (10%)

### Phase 5: Testing
1. Test with original three guilds
2. Verify score range [-1, +1]
3. Verify both positive and negative reach [0, 1]
4. Check realistic calibration

---

## Key Differences from V2

| Component | V2 (WRONG) | V3 (CORRECT) |
|-----------|------------|--------------|
| Negative weights | 40%, 30%, 30% | 35%, 35%, 20%, 5%, 5% |
| Positive weights | 30%, 30%, 20%, 10%, 10% | 25%, 20%, 15%, 20%, 10%, 10% |
| CSR placement | Separate penalty after | N4 (20% of negative) |
| Phylo placement | Separate bonus after | P4 (20% of positive) |
| Phylo calculation | None (used family count) | Eigenvector distances |
| Drought sensitivity | Affects score | Warning only |
| Pollinator counting | Bug (6/5 plants) | Fixed |
| Missing | N5, N6, P5 | All included |

---

## Success Criteria

1. ✓ Negative and positive both in [0, 1]
2. ✓ Final score in [-1, +1]
3. ✓ All weights sum to 100%
4. ✓ No pollinator counting bugs
5. ✓ Drought is warning only
6. ✓ CSR is part of negative (N4: 20%)
7. ✓ Phylo is part of positive (P4: 20%)
8. ✓ All 6 negative factors implemented
9. ✓ All 6 positive factors implemented
10. ✓ Climate filter follows Document 4.3 exactly
