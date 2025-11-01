# Fungal Symbionts Guild Improvement Analysis

## Executive Summary

After analyzing "Beneficial Fungi in Horticulture and Farming" and comparing it to our current FungalTraits-based Guild Builder fungal classification, we have identified significant gaps that require a comprehensive redesign of fungal guild rules.

**Current System Limitations**:
- Treats fungi in 3 simple categories (pathogens, mycorrhizae, biocontrol)
- Misses functional duality and multi-guild roles
- No endophytic growth promotion tracking
- No saprotroph decomposition benefits
- No crop-specific incompatibilities
- No application method context
- No synergistic network effects

**Recommendation**: Implement a **Multi-Guild Functional Classification System** with context-dependent scoring, crop-specific exclusions, and synergistic multipliers.

## Current Guild Builder Fungal Classification (FungalTraits-Based)

**Category 1: Pathogenic Fungi** (NEGATIVE)
- 1,643 genera (`primary_lifestyle` = 'plant_pathogen')
- Weight: -0.50 (host-specific), -0.30 (generalist), -0.20 (non-host)
- Host-specific matching: 225 genera with plant genus targeting

**Category 2: Beneficial Mycorrhizae** (POSITIVE)
- 378 genera (327 EcM + 51 AMF)
- Weight: +0.20 (high confidence mutualists)
- Function: Nutrient uptake, water relations, soil structure

**Category 3: Biocontrol Fungi** (POSITIVE)
- 359 genera (168 mycoparasites + 191 entomopathogenic)
- Weight: +0.15 (conservative for context-dependent behavior)
- Function: Attack pests/pathogens
- **Excludes dual-role**: 5 genera (Trichoderma, Gonatobotryum, Puttemansia, Stereocrea, Ascopolyporus)

## Key Insights from Beneficial Fungi Document

### 1. Four Primary Functional Guilds (Not Three)

The document identifies FOUR primary guilds, not three:

1. **Mycorrhizal Fungi** - Symbiotic nutrient foragers
   - Arbuscular Mycorrhizae (AMF): 80% of plants, most crops
   - Ectomycorrhizae (EMF): Woody crops, nut trees

2. **Endophytic Fungi** - Internal plant allies (**MISSING FROM OUR SYSTEM**)
   - Plant Growth-Promoting Fungi (PGPF): Phytohormone production, nutrient solubilization
   - Biocontrol Endophytes: ISR (Induced Systemic Resistance), anti-pathogen metabolites

3. **Saprotrophic Fungi** - External decomposers (**MISSING FROM OUR SYSTEM**)
   - Lignin/cellulose breakdown
   - Nutrient mineralization
   - Soil building

4. **Biocontrol Fungi** - Specialized protectors
   - Entomopathogenic (insect-killing)
   - Mycoparasitic (fungus-killing)
   - Nematicidal (nematode-killing)

### 2. Functional Duality - The Critical Concept We're Missing

**"A single fungal species or even strain can, and often does, occupy multiple niches and perform several functions simultaneously. This 'functional duality' is a key component of their value."**

**Examples of Multi-Guild Fungi**:

| Genus | Guild 1 | Guild 2 | Guild 3 | Current Guild Builder Treatment |
|-------|---------|---------|---------|----------------------------------|
| **Trichoderma** | Mycoparasitic (biocontrol) | Saprotroph (decomposer) | Endophyte (PGPF + ISR) | **EXCLUDED** (dual-role plant pathogen) |
| **Beauveria** | Entomopathogenic (biocontrol) | Endophyte (systemic defense) | - | **Included** (biocontrol only) |
| **Metarhizium** | Entomopathogenic (biocontrol) | Endophyte (systemic defense) | - | **Included** (biocontrol only) |
| **Fusarium** | Endophyte (PGPF) | **Plant pathogen** (some species) | - | **EXCLUDED** (pathogen) |
| **Penicillium** | Endophyte (PGPF) | Saprotroph | - | Not explicitly tracked |

**Current Problem**: We're **excluding Trichoderma** from beneficial categories because FungalTraits correctly identifies it as a dual-role plant pathogen. BUT we're **missing its three beneficial roles**:
1. Premier mycoparasitic biocontrol (60% of global fungal biocontrol market)
2. Aggressive saprotroph (soil decomposer)
3. Endophyte (growth promotion + ISR)

**Document Quote**: "Trichoderma species also exhibit strong nematicidal activity" - it's actually a **FOUR-guild fungus**.

### 3. Application Method Changes Function (Context-Dependent Scoring)

**Critical Insight**: The same fungus performs different functions depending on HOW it's applied.

**Beauveria/Metarhizium Example**:
- **Foliar spray**: Contact pesticide (short-lived, UV-sensitive)
- **Soil drench/seed treatment**: Endophytic colonization (systemic, persistent protection)

**Quote**: "The application method (foliar spray vs. soil drench) fundamentally changes the fungus's function from a temporary contact pesticide to a persistent, systemic bodyguard."

**Our System Doesn't Track**: GloBI has no information on application method, so we can't distinguish these functional modes.

### 4. Crop-Specific Incompatibilities (Major Gap)

**Non-Mycorrhizal Crops** (document section 2.2):

> "A critical consideration for farm management is that a few major crop families do not form mycorrhizal associations. These include the Brassicaceae (e.g., cabbage, broccoli, canola, mustard, and radish) and the Chenopodiaceae (e.g., spinach, beets, and chard). **Applying AMF inoculants to these crops will have no effect.**"

**Current Problem**: Our system assigns +0.20 weight for AMF mycorrhizae to ALL plants. But for Brassicaceae and Chenopodiaceae, the weight should be **ZERO**.

**Example False Positive**:
- Plant A: *Brassica oleracea* (cabbage)
- Plant B: *Lactuca sativa* (lettuce)
- Shared fungus: *Glomus intraradices* (AMF)
- **Current score**: +0.20 compatibility
- **Correct score**: 0.00 (cabbage cannot form AMF associations)

### 5. AMF vs EMF Functional Distinction (Missing)

**Document Quote**: "The choice between AMF and EMF inoculants is not interchangeable; it is entirely crop-dependent."

**Functional Differences**:
- **AMF**: "Foraging" for mineral nutrients in soil solution
- **EMF**: "Mining" nutrients from organic matter (secrete enzymes to decompose)

**Crops**:
- **AMF**: Vegetables, row crops, grasses (most crops)
- **EMF**: Woody plants, nut trees (pecan, hazelnut), forestry

**Current Problem**: We track 378 mycorrhizae genera but don't distinguish AMF vs EMF. For woody crops, EMF should have higher weight; for herbaceous crops, AMF should have higher weight.

### 6. The Synergistic Fungal Network (Missing Completely)

**Document Section 7.1**: "The true power of beneficial fungi in agriculture lies not in any single category, but in the **synergistic and holistic function of the entire fungal network**."

**Four-Stage Synergy**:

1. **Saprotrophs** (Foundation): Decompose residues, build soil structure, mineralize nutrients → "stock the pantry"
2. **Mycorrhizae** (Transport): Access nutrients from saprotrophs, deliver to roots → "logistics network"
3. **Endophytes** (Optimization): Receive nutrients/water, produce phytohormones → "internal managers"
4. **Biocontrol** (Defense): Protect the nutrient-rich plant from pests/pathogens → "bodyguards"

**Quote**: "This holistic system—where saprotrophs build fertility, mycorrhizae enhance uptake, endophytes optimize growth, and biocontrol agents provide protection—creates a resilient, self-sustaining agricultural ecosystem."

**Current Problem**: We score each guild independently with additive weights. We're missing the **multiplicative synergy** when multiple guilds are present together.

### 7. Endophytic Functions We're Completely Missing

**Two Major Endophytic Functions**:

**A. Plant Growth Promotion (PGPF)**:
- Phytohormone production: Auxins (IAA) → root development, Gibberellins (GA) → stem elongation
- Nutrient mobilization: Phosphorus solubilization, siderophores for iron chelation
- **Benefit**: Direct growth enhancement

**B. Abiotic Stress Tolerance**:
- Drought tolerance: 20-30% reduction in water consumption while increasing yield
- Salinity tolerance: Osmotic adjustment, ROS scavenging
- Temperature extremes: Antioxidant system management
- **Benefit**: Climate resilience

**C. Biotic Stress Resistance**:
- Induced Systemic Resistance (ISR): "Vaccination" primes plant defenses
- Direct antagonism: Antifungal/antibacterial metabolites, insect deterrents
- Competition: Physical occupation prevents pathogen colonization
- **Benefit**: Disease/pest resistance

**Quote**: "The plant 'outsources' critical physiological functions. The endophytes function as an **outsourced endocrine system** by producing growth hormones, an **outsourced stress response system** by managing ROS and stress hormones, and an **outsourced immune system** by providing ISR and producing defensive antibiotics."

**Current Impact**: We're missing an entire category of benefits that applies to **most plant species** (endophytes are ubiquitous).

### 8. Saprotrophic Functions We're Completely Missing

**Three Major Saprotrophic Functions**:

**A. Decomposition & Nutrient Cycling**:
- Break down lignin (almost exclusively by fungi)
- Break down cellulose
- Mineralize organic nutrients → available for plant uptake
- **Benefit**: Soil fertility

**B. Soil Structure Engineering**:
- Mycelial networks bind soil particles → water-stable aggregates
- Improve porosity, aeration, water infiltration
- Reduce crusting and erosion
- **Benefit**: Soil health

**C. Composting & Humus Formation**:
- Fungal succession in compost: mesophilic → thermophilic → maturation
- Create stable humus (nutrient-rich organic matter)
- Spent mushroom compost (SMC) as soil amendment
- **Benefit**: Organic matter

**Quote**: "These fungi are the foundational guild of the soil food web. They are the 'architects' that build the physical soil structure (aggregates) and the 'chefs' that 'cook' the raw, complex ingredients (lignin, cellulose)."

**Current Impact**: We're treating saprotrophs as "excluded" (neutral) when they should be **highly positive** for soil health and fertility.

## Critical Problems with Current Trichoderma Exclusion

**FungalTraits Classification**:
- Primary lifestyle: mycoparasite
- Secondary lifestyle: foliar_endophyte
- Plant pathogenic capacity: leaf/fruit/seed_pathogen
- **Our decision**: EXCLUDE from biocontrol (dual-role)

**Document Evidence**:
- "Trichoderma-based products account for an estimated **60% of the global fungal biocontrol market**"
- "Highly effective against a wide range of devastating soil-borne pathogens, including Pythium, Rhizoctonia, Fusarium, and Sclerotinia"
- Four mechanisms: mycoparasitism, antibiosis, competition, endophytic ISR
- "Trichoderma is an extremely fast-growing and aggressive colonizer of the rhizosphere"
- Also has nematicidal activity

**The Paradox**: We're excluding the **most important commercial biocontrol fungus** because it's also an opportunistic plant pathogen.

**Resolution Strategy**: Need **context-dependent** scoring:
- In presence of target pathogens (Pythium, Rhizoctonia, Fusarium): **HIGH POSITIVE** weight
- In absence of target pathogens: **LOW POSITIVE** or neutral weight
- Risk mitigation: Lower weight than pure biocontrol fungi (Gliocladium)

## Proposed Guild Builder Fungal Classification System V2.0

### Architecture: Multi-Guild Functional System

**Paradigm Shift**: From "single guild per fungus" to "**multiple guilds per fungus with weighted contributions**"

**Five Primary Guilds** (expanded from 3):

| Guild | Function | Current Status | Proposed Weight |
|-------|----------|----------------|-----------------|
| 1. Mycorrhizal | Nutrient/water uptake, soil structure | ✓ Implemented | +0.20 (with crop-specific exclusions) |
| 2. Endophytic | Growth promotion, stress tolerance, ISR | ✗ **MISSING** | +0.15 (new) |
| 3. Biocontrol | Pest/pathogen suppression | ✓ Implemented | +0.15 (context-dependent) |
| 4. Saprotrophic | Decomposition, soil building | ✗ **MISSING** | +0.10 (new) |
| 5. Pathogenic | Plant disease | ✓ Implemented | -0.50 to -0.20 (host-specific) |

### Implementation Strategy

**Phase 1: Add Missing Guilds (Endophytic + Saprotrophic)**

**Endophytic Fungi Extraction** (FungalTraits):
```python
# Step 1: Extract endophytic PGPF
endophytic_fungi = ft_matches[
    (ft_matches['primary_lifestyle'] == 'foliar_endophyte') |
    (ft_matches['primary_lifestyle'] == 'root_endophyte') |
    (ft_matches['Secondary_lifestyle'].str.contains('endophyte', case=False, na=False))
].copy()

# Step 2: Exclude if also plant pathogen (primary only)
pgpf_fungi = endophytic_fungi[
    endophytic_fungi['primary_lifestyle'] != 'plant_pathogen'
]

# Step 3: Extract plant-endophyte relationships
plant_endophytes = pgpf_fungi.groupby('plant_wfo_id').agg(
    endophytic_fungi=('sourceTaxonName', lambda x: list(set(x))),
    endophytic_fungi_count=('sourceTaxonName', 'nunique')
).reset_index()

# Weight: +0.15 (growth promotion + stress tolerance + ISR)
```

**Saprotrophic Fungi Extraction** (FungalTraits):
```python
# Step 1: Extract saprotrophs
saprotrophic_fungi = ft_matches[
    ft_matches['primary_lifestyle'].isin([
        'wood_saprotroph',
        'litter_saprotroph',
        'soil_saprotroph',
        'unspecified_saprotroph',
        'dung_saprotroph'
    ])
].copy()

# Step 2: No exclusions (saprotrophs are universally beneficial)

# Step 3: Extract plant-saprotroph relationships
plant_saprotrophs = saprotrophic_fungi.groupby('plant_wfo_id').agg(
    saprotrophic_fungi=('sourceTaxonName', lambda x: list(set(x))),
    saprotrophic_fungi_count=('sourceTaxonName', 'nunique')
).reset_index()

# Weight: +0.10 (decomposition + soil structure + nutrient cycling)
```

**Phase 2: Implement Multi-Guild Tracking for Dual-Role Fungi**

**Trichoderma Multi-Guild Classification**:
```python
# Trichoderma: primary=mycoparasite, secondary=foliar_endophyte, pathogen=yes
trichoderma = ft_matches[ft_matches['GENUS'] == 'Trichoderma'].copy()

# Assign to MULTIPLE guilds with differentiated weights
trichoderma_guilds = {
    'biocontrol_mycoparasite': +0.12,  # Lower than pure biocontrol (+0.15)
    'endophyte_isr': +0.08,            # ISR benefit
    'saprotroph_decomposer': +0.05,    # Decomposition benefit
    'pathogen_risk': -0.15             # Opportunistic pathogen (lower than pure pathogen)
}

# NET BENEFIT: +0.10 (cautiously positive)
```

**Beauveria/Metarhizium Multi-Guild Classification**:
```python
# Beauveria/Metarhizium: primary=animal_parasite, NO plant pathogen capacity
beauveria = ft_matches[
    ft_matches['GENUS'].isin(['Beauveria', 'Metarhizium'])
].copy()

beauveria_guilds = {
    'biocontrol_entomopathogenic': +0.15,  # Pure biocontrol (no plant pathogen risk)
    'endophyte_systemic_defense': +0.10    # Endophytic systemic protection
}

# NET BENEFIT: +0.25 (highly positive)
```

**Phase 3: Crop-Specific Mycorrhizae Exclusions**

**Non-Mycorrhizal Crop Families**:
```python
# Step 1: Define non-mycorrhizal families
NON_MYCORRHIZAL_FAMILIES = {
    'Brassicaceae',      # Cabbage, broccoli, canola, mustard, radish
    'Chenopodiaceae',    # Spinach, beets, chard
    'Amaranthaceae'      # (Some sources merge Chenopodiaceae into Amaranthaceae)
}

# Step 2: Extract plant family from WFO
plant_families = wfo_dataset[['wfo_id', 'family']].copy()

# Step 3: Zero AMF weight for non-mycorrhizal crops
def calculate_mycorrhizae_weight(plant_wfo_id, mycorrhizae_type):
    plant_family = plant_families.loc[
        plant_families['wfo_id'] == plant_wfo_id, 'family'
    ].values[0]

    if plant_family in NON_MYCORRHIZAL_FAMILIES:
        return 0.00  # NO BENEFIT for non-mycorrhizal crops
    elif mycorrhizae_type == 'arbuscular_mycorrhizal':
        return +0.20  # AMF benefit for mycorrhizal crops
    elif mycorrhizae_type == 'ectomycorrhizal':
        # Check if woody plant (simplified - would need better logic)
        return +0.20  # EMF benefit
    else:
        return +0.20  # Default mycorrhizae benefit
```

**Phase 4: AMF vs EMF Differentiation**

**Crop-Type Specific Weighting**:
```python
# Step 1: Classify crops by growth form
def get_crop_growth_form(plant_wfo_id, plant_dataset):
    # Simplified - would need woodiness trait or growth form from TRY database
    # For now, use family as proxy
    plant_family = plant_families.loc[
        plant_families['wfo_id'] == plant_wfo_id, 'family'
    ].values[0]

    WOODY_FAMILIES = {
        'Fagaceae',      # Oaks
        'Juglandaceae',  # Walnuts, pecans
        'Betulaceae',    # Birches, hazelnuts
        'Pinaceae',      # Pines
        'Rosaceae'       # (Some woody: apples, cherries)
    }

    if plant_family in WOODY_FAMILIES:
        return 'woody'
    else:
        return 'herbaceous'

# Step 2: Weight AMF vs EMF by crop type
def calculate_mycorrhizae_weight_v2(plant_wfo_id, mycorrhizae_genus, ft_mycorrhizae_type):
    crop_type = get_crop_growth_form(plant_wfo_id, plant_dataset)

    if ft_mycorrhizae_type == 'arbuscular_mycorrhizal':
        if crop_type == 'herbaceous':
            return +0.20  # HIGH: AMF optimal for herbaceous crops
        else:
            return +0.10  # MEDIUM: AMF can work with some woody plants

    elif ft_mycorrhizae_type == 'ectomycorrhizal':
        if crop_type == 'woody':
            return +0.25  # VERY HIGH: EMF optimal for woody crops (includes N mining)
        else:
            return 0.00   # ZERO: EMF don't work with herbaceous crops

    return +0.15  # Default
```

**Phase 5: Synergistic Network Multipliers**

**Multi-Guild Synergy Bonus**:
```python
# Step 1: Count number of beneficial guild categories present
def calculate_guild_synergy_multiplier(plant_wfo_id, guild_data):
    present_guilds = []

    if guild_data['mycorrhizae_count'] > 0:
        present_guilds.append('mycorrhizae')
    if guild_data['endophytic_fungi_count'] > 0:
        present_guilds.append('endophyte')
    if guild_data['biocontrol_fungi_count'] > 0:
        present_guilds.append('biocontrol')
    if guild_data['saprotrophic_fungi_count'] > 0:
        present_guilds.append('saprotroph')

    num_guilds = len(present_guilds)

    # Synergy multiplier based on number of guilds
    if num_guilds >= 4:
        return 1.30  # 30% bonus for complete fungal network
    elif num_guilds == 3:
        return 1.20  # 20% bonus for 3 guilds
    elif num_guilds == 2:
        return 1.10  # 10% bonus for 2 guilds
    else:
        return 1.00  # No bonus for single guild

# Step 2: Apply multiplier to total fungal benefit
total_fungal_benefit = (
    mycorrhizae_weight +
    endophyte_weight +
    biocontrol_weight +
    saprotroph_weight
) * guild_synergy_multiplier
```

**Example Synergy**:
- Plant A: Has AMF (+0.20) + endophytes (+0.15) + saprotrophs (+0.10) + biocontrol (+0.15)
- Base benefit: 0.20 + 0.15 + 0.10 + 0.15 = +0.60
- Synergy multiplier: 1.30 (4 guilds present)
- **Final benefit: 0.60 × 1.30 = +0.78**

## Summary of Proposed Changes

### New Guilds to Add

**1. Endophytic Fungi** (+0.15 weight)
- FungalTraits extraction: `primary_lifestyle` IN ('foliar_endophyte', 'root_endophyte')
- Exclude if primary = 'plant_pathogen'
- Benefits: Growth promotion, stress tolerance, ISR
- Expected genera: ~500-1000 (FungalTraits has foliar_endophyte: 99, but many have endophyte in secondary_lifestyle)

**2. Saprotrophic Fungi** (+0.10 weight)
- FungalTraits extraction: `primary_lifestyle` IN ('wood_saprotroph', 'litter_saprotroph', 'soil_saprotroph')
- No exclusions (universally beneficial)
- Benefits: Decomposition, soil structure, nutrient cycling
- Expected genera: 2,108 wood + 1,227 litter + 612 soil = ~3,947 genera

### Multi-Guild Tracking

**Trichoderma**: biocontrol + endophyte + saprotroph + pathogen (NET: +0.10)
**Beauveria/Metarhizium**: biocontrol + endophyte (NET: +0.25)

### Crop-Specific Exclusions

**Non-mycorrhizal families**: Brassicaceae, Chenopodiaceae → AMF weight = 0.00

### Guild Differentiation

**AMF vs EMF**: Herbaceous crops prefer AMF, woody crops prefer EMF

### Synergistic Multipliers

**4 guilds present**: 1.30× multiplier
**3 guilds present**: 1.20× multiplier
**2 guilds present**: 1.10× multiplier

## Expected Impact on Guild Builder

**Before (Current System)**:
- 3 fungal categories: pathogens, mycorrhizae, biocontrol
- Additive scoring: max +0.35 benefit (0.20 + 0.15)
- Trichoderma excluded
- No crop-specific adjustments
- No synergy effects

**After (Proposed System)**:
- 5 fungal categories: pathogens, mycorrhizae, endophytes, biocontrol, saprotrophs
- Synergistic scoring: max +0.78 benefit (0.60 × 1.30 multiplier)
- Trichoderma included with cautious positive weight (+0.10)
- Crop-specific exclusions (Brassicaceae, Chenopodiaceae)
- AMF/EMF differentiation by growth form
- Multi-guild synergy bonuses

**Example Plant Compatibility Improvement**:

**Plant A + Plant B** sharing:
- 2 AMF genera (*Glomus*, *Rhizophagus*)
- 1 endophyte (*Penicillium*)
- 1 mycoparasite (*Trichoderma*)
- 2 saprotrophs (*Agaricus*, *Coprinus*)

**Current score**:
- AMF: +0.20
- Mycoparasite: 0.00 (Trichoderma excluded)
- **Total: +0.20**

**Proposed score**:
- AMF: +0.20 (2 genera)
- Endophyte: +0.15 (1 genus)
- Biocontrol: +0.10 (Trichoderma multi-guild)
- Saprotroph: +0.10 (2 genera)
- Base: 0.55
- Synergy (4 guilds): ×1.30
- **Total: +0.715** (+257% improvement)

## Implementation Priority

### Phase 1: High Priority (Immediate Impact)
1. **Add Endophytic Guild** (4 hours)
   - Extract from FungalTraits `primary_lifestyle` = 'foliar_endophyte'
   - Weight: +0.15
   - Impact: ~100-500 genera, major beneficial category

2. **Add Crop-Specific Mycorrhizae Exclusions** (2 hours)
   - Brassicaceae, Chenopodiaceae → AMF weight = 0.00
   - Impact: Prevents false positives for ~50+ crop species

3. **Add Trichoderma Multi-Guild** (2 hours)
   - Cautiously positive weight: +0.10
   - Impact: Includes most important commercial biocontrol genus

### Phase 2: Medium Priority (Enhanced Accuracy)
4. **Add Saprotrophic Guild** (4 hours)
   - Extract from FungalTraits saprotroph lifestyles
   - Weight: +0.10
   - Impact: ~3,947 genera, foundation of soil food web

5. **Implement AMF vs EMF Differentiation** (6 hours)
   - Requires woodiness trait or growth form classification
   - Impact: More accurate mycorrhizae weighting for woody vs herbaceous crops

### Phase 3: Advanced (Synergistic Effects)
6. **Implement Synergy Multipliers** (4 hours)
   - Multi-guild presence bonuses
   - Impact: Rewards complete fungal networks

7. **Add Beauveria/Metarhizium Multi-Guild** (2 hours)
   - Endophyte + biocontrol
   - Impact: Higher weights for dual-function biocontrol fungi

**Total implementation time**: ~24 hours (3 days)

## Conclusion

The current Guild Builder fungal classification system captures only **~40% of beneficial fungal functions** by tracking mycorrhizae and biocontrol while missing:
- Endophytic growth promotion and stress tolerance
- Saprotrophic decomposition and soil building
- Multi-guild synergistic effects
- Crop-specific incompatibilities
- The most important commercial biocontrol genus (Trichoderma)

**The proposed Multi-Guild Functional Classification System V2.0** addresses these gaps with:
- 5 functional guilds (vs 3)
- Multi-guild tracking for dual-role fungi
- Crop-specific exclusions and differentiation
- Synergistic network multipliers
- Expected **+257% improvement** in beneficial fungal compatibility scoring

**Recommendation**: Implement Phase 1 immediately (8 hours) to capture endophytic benefits, fix crop-specific false positives, and include Trichoderma. This alone will dramatically improve Guild Builder accuracy for fungal symbionts.
