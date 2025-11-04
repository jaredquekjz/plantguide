# ARCHIVED: Stage 4.3 Weighted Framework

**⚠️ DEPRECATED - DO NOT USE ⚠️**

This document represents the old weighted framework that has been superseded.
The current active framework is **Document 4.4** (unified percentile).

**Document:** 4.3 Original Dataset Integration (DEPRECATED)
**Date:** 2025-11-02
**Status:** ARCHIVED - Superseded by 4.4
**Purpose:** Old strategy for integrating climate, CSR, phylogeny using weighted aggregation
**Superseded by:** Document 4.4 (Unified Percentile Framework)

---

## Executive Summary

**CRITICAL DISTINCTION**: Guild compatibility scoring answers: "Can these plants thrive together?" NOT "What ecosystem services do they provide?"

This framework focuses exclusively on compatibility factors:

1. **Climate compatibility** (VETO filter - cannot plant tropical with temperate)
2. **CSR strategy compatibility** (penalize conflicts, modulated by EIVE + height + growth form)
3. **Phylogenetic diversity** (use eigenvectors instead of simple family counting)
4. **Vertical and form stratification** (layered planting with diverse growth forms)
5. **Nitrogen fixation requirement** (guilds need N-fixers or face soil depletion)
6. **Soil pH compatibility** (minor penalty for extreme differences)
7. **Shared pollinators** (support larger pollinator populations)

**Ecosystem services** (NPP, decomposition, carbon storage) are calculated separately as community-weighted means (CWM) for user information, NOT included in compatibility score.

---

## Framework v2 Structure

### FILTERS (Hard Veto):
- **F1**: Climate compatibility (guild-level range check with outlier detection)

### NEGATIVE FACTORS (100%):
- **N1**: Pathogen fungi overlap (35%)
- **N2**: Herbivore overlap (35%)
- **N4**: CSR conflicts modulated by EIVE+height+form (20%)
- **N5**: Absence of nitrogen fixation (5%)
- **N6**: Soil pH incompatibility (5%)

### POSITIVE FACTORS (100%):
- **P1**: Cross-plant biocontrol (25%)
- **P2**: Pathogen antagonists (20%)
- **P3**: Beneficial fungal networks (15%)
- **P4**: Phylogenetic diversity via eigenvectors (20%)
- **P5**: Vertical and form stratification (10%)
- **P6**: Shared pollinators (10%)

### WARNINGS (No score impact):
- **W1**: Tall competitive plants (spacing recommendations)

### SEPARATE OUTPUT:
- **Ecosystem service CWM** (NPP, decomposition, carbon, nitrogen fixation, carbon storage, erosion protection)

---

## Part 1: Climate Compatibility (VETO Filter + Compatibility Score)

### Rationale

Planting sakura (temperate, hardiness zone 5-8) with coconut (tropical, zone 10-12) is impossible. Climate incompatibility should VETO the guild entirely and flag the specific outlier plant(s).

**Sophisticated 3-Level Analysis:**
1. **Level 1**: Tolerance envelope overlap (q05, q95 quantiles define survival range)
2. **Level 2**: Hardiness zone compatibility (calculated from bio_6)
3. **Level 3**: Extreme climate vulnerabilities (ETCCDI indices)
4. **Quantitative score**: Climate compatibility figure [0, 1]

### Data Source

Stage 3 Climate Indicators (408 columns total):
- **Temperature**: bio_1 (annual mean), bio_6 (min temp coldest month)
- **Precipitation**: bio_12 (annual), bio_13 (wettest month), bio_14 (driest month)
- **Growing Season**: GSL (growing season length)
- **Extreme Indices**: CDD (drought), CFD (frost), WSDI (heat), CSDI (cold)
- **Quantiles**: q05 (5th percentile = extreme low survival), q50 (median), q95 (95th percentile = extreme high survival)

### Level 1: Tolerance Envelope Overlap (VETO if no overlap)

**Concept**: Each plant's q05-q95 range defines climate conditions where it can survive. Guild must have a shared climate zone where ALL plants' envelopes overlap.

```python
def check_climate_envelope_overlap(plant_ids, con):
    """
    Level 1: Check if plants' climate tolerance envelopes overlap.
    Uses q05 (extreme low) and q95 (extreme high) to define viable range.
    VETO if no overlap. Flag outlier plants.
    """

    # Get tolerance envelopes for all critical variables
    climate = con.execute(f"""
        SELECT
            plant_wfo_id,
            wfo_scientific_name,
            -- Temperature tolerance envelope (°C)
            bio_1_q05 / 10.0 as temp_annual_min,
            bio_1_q95 / 10.0 as temp_annual_max,
            bio_6_q05 / 10.0 as temp_coldest_min,
            bio_6_q95 / 10.0 as temp_coldest_max,
            -- Precipitation tolerance envelope (mm)
            bio_12_q05 as precip_annual_min,
            bio_12_q95 as precip_annual_max
        FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')
        WHERE plant_wfo_id IN ({plant_ids_str})
    """).fetchdf()

    # ═══════════════════════════════════════════════════════════════
    # CALCULATE GUILD'S SHARED CLIMATE ZONE (intersection of all envelopes)
    # ═══════════════════════════════════════════════════════════════

    # Temperature: shared zone = warmest plant's minimum to coldest plant's maximum
    shared_temp_min = climate['temp_annual_min'].max()  # Warmest plant's minimum
    shared_temp_max = climate['temp_annual_max'].min()  # Coldest plant's maximum
    temp_overlap = shared_temp_max - shared_temp_min

    # Coldest month temperature (hardiness)
    shared_hardiness_min = climate['temp_coldest_min'].max()
    shared_hardiness_max = climate['temp_coldest_max'].min()
    hardiness_overlap = shared_hardiness_max - shared_hardiness_min

    # Precipitation
    shared_precip_min = climate['precip_annual_min'].max()
    shared_precip_max = climate['precip_annual_max'].min()
    precip_overlap = shared_precip_max - shared_precip_min

    # ═══════════════════════════════════════════════════════════════
    # CHECK FOR VETO CONDITIONS
    # ═══════════════════════════════════════════════════════════════

    veto = False
    veto_reasons = []
    outliers = []

    # VETO 1: No temperature overlap
    if temp_overlap < 0:
        veto = True
        veto_reasons.append('No temperature overlap')
        # Find outliers
        temp_median = (climate['temp_annual_min'].median() + climate['temp_annual_max'].median()) / 2
        for idx, row in climate.iterrows():
            plant_median = (row['temp_annual_min'] + row['temp_annual_max']) / 2
            if abs(plant_median - temp_median) > 10.0:  # >10°C from median
                outliers.append({
                    'plant': row['wfo_scientific_name'],
                    'plant_id': row['plant_wfo_id'],
                    'reason': f'Temperature mismatch: {row["temp_annual_min"]:.1f}°C to {row["temp_annual_max"]:.1f}°C (guild median: {temp_median:.1f}°C)',
                    'severity': abs(plant_median - temp_median)
                })

    # VETO 2: No hardiness overlap (coldest month)
    if hardiness_overlap < -5.0:  # Allow 5°C tolerance
        veto = True
        veto_reasons.append('No hardiness overlap')
        hardiness_median = (climate['temp_coldest_min'].median() + climate['temp_coldest_max'].median()) / 2
        for idx, row in climate.iterrows():
            plant_hardiness = (row['temp_coldest_min'] + row['temp_coldest_max']) / 2
            if abs(plant_hardiness - hardiness_median) > 15.0:
                outliers.append({
                    'plant': row['wfo_scientific_name'],
                    'plant_id': row['plant_wfo_id'],
                    'reason': f'Hardiness mismatch: {row["temp_coldest_min"]:.1f}°C to {row["temp_coldest_max"]:.1f}°C (guild median: {hardiness_median:.1f}°C)',
                    'severity': abs(plant_hardiness - hardiness_median)
                })

    # VETO 3: No precipitation overlap
    if precip_overlap < 0:
        veto = True
        veto_reasons.append('No precipitation overlap')
        precip_median = (climate['precip_annual_min'].median() + climate['precip_annual_max'].median()) / 2
        for idx, row in climate.iterrows():
            plant_precip = (row['precip_annual_min'] + row['precip_annual_max']) / 2
            if abs(plant_precip - precip_median) > 800:  # >800mm difference
                outliers.append({
                    'plant': row['wfo_scientific_name'],
                    'plant_id': row['plant_wfo_id'],
                    'reason': f'Precipitation mismatch: {row["precip_annual_min"]:.0f}mm to {row["precip_annual_max"]:.0f}mm (guild median: {precip_median:.0f}mm)',
                    'severity': abs(plant_precip - precip_median)
                })

    if veto:
        # Sort outliers by severity
        outliers_sorted = sorted(outliers, key=lambda x: x['severity'], reverse=True)
        # Remove duplicates
        unique_outliers = {o['plant_id']: o for o in outliers_sorted}.values()

        return {
            'veto': True,
            'level': 1,
            'reason': 'Climate Envelope Incompatibility',
            'veto_details': veto_reasons,
            'message': f'Guild has NO shared climate zone:\n'
                      f'  - Temperature overlap: {temp_overlap:.1f}°C (need >0°C)\n'
                      f'  - Hardiness overlap: {hardiness_overlap:.1f}°C (need >-5°C)\n'
                      f'  - Precipitation overlap: {precip_overlap:.0f}mm (need >0mm)',
            'outliers': list(unique_outliers),
            'recommendation': f'Remove outlier plant(s): {", ".join([o["plant"] for o in list(unique_outliers)[:2]])}'
        }

    # PASS: Return shared climate zone
    return {
        'veto': False,
        'temp_overlap': temp_overlap,
        'hardiness_overlap': hardiness_overlap,
        'precip_overlap': precip_overlap,
        'shared_zone': {
            'temp_range': f'{shared_temp_min:.1f}°C to {shared_temp_max:.1f}°C',
            'hardiness_range': f'{shared_hardiness_min:.1f}°C to {shared_hardiness_max:.1f}°C',
            'precip_range': f'{shared_precip_min:.0f}mm to {shared_precip_max:.0f}mm'
        }
    }
```

### Level 2: Winter Cold Tolerance Compatibility (VETO if incompatible)

**Concept**: Use bio_6 (min temp coldest month) from occurrence locations to determine each plant's cold tolerance RANGE. No mapping to USDA zones - just raw temperatures.

**Critical Understanding**: We're using **observed natural distribution climate data**:
- `bio_6_q05` = Min temp at COLDEST 5% of occurrence locations (extreme cold tolerance)
- `bio_6_q50` = Min temp at MEDIAN occurrence locations (typical habitat)
- `bio_6_q95` = Min temp at WARMEST 5% of occurrence locations (warmest limit)

**Example**:
- **Acer saccharum** (Sugar Maple) naturally occurs across a cold tolerance gradient:
  - q05 = -25°C (coldest occurrence locations - northern populations)
  - q50 = -12°C (typical habitat)
  - q95 = -5°C (warmest occurrence locations - southern limit)
  - **Cold Tolerance Range**: -25°C to -5°C winter minimum

- **Citrus × limon** (Lemon) naturally occurs in frost-free to mild winter regions:
  - q05 = 2°C (coldest occurrence locations)
  - q50 = 8°C (typical habitat)
  - q95 = 15°C (warmest occurrence locations)
  - **Cold Tolerance Range**: 2°C to 15°C winter minimum

**How Compatibility is Determined**:

Guild compatibility = intersection of all plant cold tolerance ranges.

**Step-by-step example**:

1. **Plant A** (Acer saccharum): -25°C to -5°C
   - q05 = -25°C: "I survive winters as cold as -25°C at my coldest locations"
   - q95 = -5°C: "I survive winters as warm as -5°C at my warmest locations"
   - **Interpretation**: Sugar maple naturally occurs where winter minimums range from -25°C to -5°C

2. **Plant B** (Citrus × limon): 2°C to 15°C
   - q05 = 2°C: "I survive winters as cold as 2°C at my coldest locations"
   - q95 = 15°C: "I survive winters as warm as 15°C at my warmest locations"
   - **Interpretation**: Lemon naturally occurs where winter minimums range from 2°C to 15°C

3. **Guild Calculation**:
   - Guild's coldest survivable temp = MAX(-25°C, 2°C) = **2°C** (warmest plant's minimum)
   - Guild's warmest survivable temp = MIN(-5°C, 15°C) = **-5°C** (coldest plant's maximum)
   - **Overlap**: 2°C to -5°C → **NEGATIVE** → NO OVERLAP → **VETO**

**Why this VETO is correct**:
- Sugar maple's warmest locations (-5°C winter min) are COLDER than lemon's coldest locations (2°C winter min)
- There is NO climate where BOTH naturally occur
- This is fundamental climate incompatibility, not fixable with care

**Alternative Example - Compatible Plants**:

1. **Plant A** (Quercus alba - White Oak): -30°C to -7°C
   - Coldest locations: -30°C winter minimum
   - Warmest locations: -7°C winter minimum

2. **Plant B** (Cornus florida - Flowering Dogwood): -23°C to -4°C
   - Coldest locations: -23°C winter minimum
   - Warmest locations: -4°C winter minimum

3. **Guild Calculation**:
   - Guild's coldest temp = MAX(-30°C, -23°C) = **-23°C**
   - Guild's warmest temp = MIN(-7°C, -4°C) = **-7°C**
   - **Overlap**: -23°C to -7°C → **16°C range → COMPATIBLE**
   - **Shared climate**: Locations with winter minimums from -23°C to -7°C

**Temperature Range Quality Score**:
- **Narrow range** (<5°C overlap): All plants need very specific winters → 0.2-0.4 score
- **Moderate range** (5-15°C overlap): Good compatibility → 0.5-0.8 score
- **Wide range** (15°C+ overlap): Excellent adaptability → 0.9-1.0 score

**Why use q05-q95 instead of q50?**
- q50 only tells us typical habitat, not tolerance limits
- q05/q95 tell us the EXTREMES where plant actually survives in nature
- Conservative approach: if no overlap at extremes, plants likely incompatible

```python
def check_winter_cold_compatibility(plant_ids, con):
    """
    Level 2: Check winter cold tolerance compatibility using bio_6.
    VETO if no temperature overlap.
    """

    climate = con.execute(f"""
        SELECT
            plant_wfo_id,
            wfo_scientific_name,
            bio_6_q05 / 10.0 as winter_min_coldest,
            bio_6_q50 / 10.0 as winter_min_median,
            bio_6_q95 / 10.0 as winter_min_warmest
        FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')
        WHERE plant_wfo_id IN ({plant_ids_str})
    """).fetchdf()

    # Calculate guild's shared winter temperature range (intersection)
    guild_winter_min = climate['winter_min_coldest'].max()  # Warmest plant's coldest limit
    guild_winter_max = climate['winter_min_warmest'].min()  # Coldest plant's warmest limit

    winter_overlap = guild_winter_max - guild_winter_min

    if winter_overlap < -2.0:  # Allow 2°C tolerance for measurement uncertainty
        # No overlap - VETO
        return {
            'veto': True,
            'level': 2,
            'reason': 'Winter Cold Tolerance Incompatibility',
            'message': f'No shared winter temperature range. Guild needs {guild_winter_min:.1f}°C to {guild_winter_max:.1f}°C (impossible - negative overlap of {winter_overlap:.1f}°C)',
            'plants': climate[['wfo_scientific_name', 'winter_min_coldest', 'winter_min_warmest']].to_dict('records')
        }

    return {
        'veto': False,
        'guild_winter_min': guild_winter_min,
        'guild_winter_max': guild_winter_max,
        'winter_temp_range': winter_overlap,
        'plants': climate[['wfo_scientific_name', 'winter_min_coldest', 'winter_min_warmest']].to_dict('records')
    }
```

### Level 3: Extreme Climate Vulnerabilities (WARNING only)

**Concept**: Use ETCCDI extreme indices to identify if guild shares vulnerabilities. Plants are vulnerable when they've only experienced MILD extremes in nature (low q95 values).

**CRITICAL - Correct Interpretation**:
- **q95 = worst conditions survived at occurrence locations** (95th percentile = extreme end of distribution)
- **LOW q95** → Only survived MILD extremes → **SENSITIVE/VULNERABLE**
- **HIGH q95** → Survived SEVERE extremes → **TOLERANT**

**Example - Drought Sensitivity**:
- Plant A: `CDD_q95 = 15 days` → Even at driest locations, only 15 consecutive dry days → **DROUGHT-SENSITIVE** (needs moisture)
- Plant B: `CDD_q95 = 120 days` → Survived 120 consecutive dry days at driest locations → **DROUGHT-TOLERANT**

**Guild Vulnerability**: If >60% of guild has same sensitivity, entire guild at risk.

**Pre-Calculated Sensitivity Ratings** (to be added during Phase 1 data preparation):

These categorical ratings should be computed ONCE and stored in the dataset:

```python
# In data preparation script (Phase 1)
def calculate_climate_sensitivity_ratings(climate_df):
    """
    Pre-calculate drought, frost, and heat sensitivity ratings.
    Store as categorical variables: High / Medium / Low
    """

    # DROUGHT SENSITIVITY (based on CDD_q95)
    # Logic: Low CDD_q95 = only experienced short droughts = drought-SENSITIVE
    def classify_drought_sensitivity(cdd_q95):
        if cdd_q95 < 30:
            return 'High'      # Needs reliable moisture
        elif cdd_q95 < 60:
            return 'Medium'    # Moderate drought tolerance
        else:
            return 'Low'       # Drought-tolerant

    climate_df['drought_sensitivity'] = climate_df['CDD_q95'].apply(classify_drought_sensitivity)

    # FROST SENSITIVITY (based on CFD_q95)
    # Logic: Low CFD_q95 = only experienced brief frosts = frost-SENSITIVE
    def classify_frost_sensitivity(cfd_q95):
        if cfd_q95 < 10:
            return 'High'      # Frost-sensitive (needs frost-free conditions)
        elif cfd_q95 < 30:
            return 'Medium'    # Some frost tolerance
        else:
            return 'Low'       # Frost-tolerant (can handle prolonged frost)

    climate_df['frost_sensitivity'] = climate_df['CFD_q95'].apply(classify_frost_sensitivity)

    # HEAT SENSITIVITY (based on WSDI_q95)
    # Logic: Low WSDI_q95 = only experienced short warm spells = heat-SENSITIVE
    def classify_heat_sensitivity(wsdi_q95):
        if wsdi_q95 < 20:
            return 'High'      # Heat-sensitive (prefers cool climates)
        elif wsdi_q95 < 50:
            return 'Medium'    # Moderate heat tolerance
        else:
            return 'Low'       # Heat-tolerant (handles extended heat)

    climate_df['heat_sensitivity'] = climate_df['WSDI_q95'].apply(classify_heat_sensitivity)

    return climate_df
```

**Guild Vulnerability Analysis** (uses pre-calculated ratings):

```python
def analyze_extreme_climate_vulnerabilities(plant_ids, con):
    """
    Level 3: Identify shared vulnerabilities using pre-calculated ratings.
    WARNING only - does not veto.
    """

    extremes = con.execute(f"""
        SELECT
            plant_wfo_id,
            wfo_scientific_name,
            drought_sensitivity,
            frost_sensitivity,
            heat_sensitivity,
            CDD_q95 as drought_max_days,
            CFD_q95 as frost_max_days,
            WSDI_q95 as heat_spell_max_days
        FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')
        WHERE plant_wfo_id IN ({plant_ids_str})
    """).fetchdf()

    n_plants = len(extremes)
    warnings = []

    # Check if >60% of guild shares HIGH sensitivity (vulnerable guild)

    # Drought Vulnerability
    high_drought_sensitive = len(extremes[extremes['drought_sensitivity'] == 'High'])
    if high_drought_sensitive / n_plants > 0.6:
        avg_max_drought = extremes[extremes['drought_sensitivity'] == 'High']['drought_max_days'].mean()
        warnings.append({
            'type': 'Drought Vulnerability',
            'severity': 'High',
            'affected': high_drought_sensitive,
            'total': n_plants,
            'message': f'{high_drought_sensitive}/{n_plants} plants are drought-sensitive (naturally occur only where droughts <30 days). Average max drought survived: {avg_max_drought:.0f} days. Entire guild at risk during extended dry periods.',
            'recommendation': 'Add drought-tolerant species or plan irrigation system'
        })

    # Frost Vulnerability
    high_frost_sensitive = len(extremes[extremes['frost_sensitivity'] == 'High'])
    if high_frost_sensitive / n_plants > 0.6:
        avg_max_frost = extremes[extremes['frost_sensitivity'] == 'High']['frost_max_days'].mean()
        warnings.append({
            'type': 'Frost Vulnerability',
            'severity': 'High',
            'affected': high_frost_sensitive,
            'total': n_plants,
            'message': f'{high_frost_sensitive}/{n_plants} plants are frost-sensitive (naturally occur only in mostly frost-free conditions). Average max frost period: {avg_max_frost:.0f} days. Entire guild at risk during cold snaps.',
            'recommendation': 'Avoid frost-prone locations or provide frost protection'
        })

    # Heat Sensitivity
    high_heat_sensitive = len(extremes[extremes['heat_sensitivity'] == 'High'])
    if high_heat_sensitive / n_plants > 0.6:
        avg_max_heat = extremes[extremes['heat_sensitivity'] == 'High']['heat_spell_max_days'].mean()
        warnings.append({
            'type': 'Heat Stress Vulnerability',
            'severity': 'Medium',
            'affected': high_heat_sensitive,
            'total': n_plants,
            'message': f'{high_heat_sensitive}/{n_plants} plants are heat-sensitive (naturally occur only in cooler climates). Average max heat spell: {avg_max_heat:.0f} days. Guild may struggle during heatwaves.',
            'recommendation': 'Provide shade, mulching, or irrigation during hot periods'
        })

    return {
        'warnings': warnings,
        'vulnerability_count': len(warnings),
        'sensitivity_summary': {
            'drought_high': high_drought_sensitive,
            'frost_high': high_frost_sensitive,
            'heat_high': high_heat_sensitive
        }
    }
```

**Interpretation Examples**:

**Example 1 - Drought-Vulnerable Guild**:
```
Plant A: CDD_q95 = 18 days → drought_sensitivity = 'High'
Plant B: CDD_q95 = 22 days → drought_sensitivity = 'High'
Plant C: CDD_q95 = 28 days → drought_sensitivity = 'High'
Plant D: CDD_q95 = 85 days → drought_sensitivity = 'Low'
Plant E: CDD_q95 = 25 days → drought_sensitivity = 'High'

→ 4/5 plants (80%) have HIGH drought sensitivity
→ WARNING: Guild vulnerable to drought (most plants only survived <30 day droughts in nature)
→ RECOMMENDATION: Add drought-tolerant species or plan irrigation
```

**Example 2 - Frost-Vulnerable Guild**:
```
Plant A: CFD_q95 = 5 days → frost_sensitivity = 'High' (frost-tender)
Plant B: CFD_q95 = 8 days → frost_sensitivity = 'High'
Plant C: CFD_q95 = 12 days → frost_sensitivity = 'Medium'
Plant D: CFD_q95 = 3 days → frost_sensitivity = 'High'
Plant E: CFD_q95 = 6 days → frost_sensitivity = 'High'

→ 4/5 plants (80%) have HIGH frost sensitivity
→ WARNING: Guild vulnerable to frost (most plants occur only in nearly frost-free zones)
→ RECOMMENDATION: Plant in frost-protected microclimate or avoid frost-prone areas
```

**Example 3 - Resilient Guild (No Warnings)**:
```
Plant A: CDD_q95 = 75 days → drought_sensitivity = 'Low'
Plant B: CDD_q95 = 45 days → drought_sensitivity = 'Medium'
Plant C: CDD_q95 = 90 days → drought_sensitivity = 'Low'
Plant D: CFD_q95 = 40 days → frost_sensitivity = 'Medium'
Plant E: WSDI_q95 = 65 days → heat_sensitivity = 'Low'

→ No shared HIGH sensitivities
→ Guild is climatically resilient (plants have survived diverse extremes)
```

### Quantitative Climate Compatibility Score

**Concept**: If guild passes all veto checks, calculate quality score [0, 1] based on how well envelopes overlap.

```python
def calculate_climate_quality_score(level1_result, level2_result, level3_result):
    """
    Calculate quantitative climate compatibility score [0, 1].
    Only called if guild passes all veto checks.
    """

    # Temperature overlap quality (0-1)
    temp_quality = min(level1_result['temp_overlap'] / 10.0, 1.0)

    # Precipitation overlap quality (0-1)
    precip_quality = min(level1_result['precip_overlap'] / 500.0, 1.0)

    # Winter temperature range quality (0-1)
    winter_temp_range = level2_result['winter_temp_range']
    winter_quality = min(winter_temp_range / 15.0, 1.0)  # 15°C+ range = perfect

    # Penalty for shared vulnerabilities
    vulnerability_penalty = level3_result['vulnerability_count'] * 0.1

    # Weighted score (3 components: temp, precip, winter)
    climate_score = (
        0.35 * temp_quality +
        0.25 * precip_quality +
        0.40 * winter_quality -
        vulnerability_penalty
    )

    climate_score = max(climate_score, 0.0)  # Floor at 0

    return {
        'climate_quality_score': climate_score,
        'components': {
            'temperature_overlap_quality': temp_quality,
            'precipitation_overlap_quality': precip_quality,
            'winter_temp_range_quality': winter_quality,
            'vulnerability_penalty': vulnerability_penalty
        }
    }
```

### Complete Climate Check (All Levels + Score)

```python
def check_climate_compatibility_complete(plant_ids, con):
    """
    Complete 3-level climate analysis with outlier detection and compatibility score.
    """

    # Level 1: Envelope overlap (VETO if no overlap)
    level1 = check_climate_envelope_overlap(plant_ids, con)
    if level1['veto']:
        return level1

    # Level 2: Winter cold tolerance (VETO if incompatible)
    level2 = check_winter_cold_compatibility(plant_ids, con)
    if level2['veto']:
        return level2

    # Level 3: Extreme vulnerabilities (WARNING only)
    level3 = analyze_extreme_climate_vulnerabilities(plant_ids, con)

    # Calculate quality score
    score = calculate_climate_quality_score(level1, level2, level3)

    return {
        'veto': False,
        'climate_quality_score': score['climate_quality_score'],
        'score_components': score['components'],
        'shared_climate_zone': level1['shared_zone'],
        'winter_temp_range': f"{level2['guild_winter_min']:.1f}°C to {level2['guild_winter_max']:.1f}°C",
        'extreme_vulnerabilities': level3['warnings'],
        'sensitivity_summary': level3['sensitivity_summary'],
        'message': f'✅ Climate compatible (score: {score["climate_quality_score"]:.2f}/1.0)'
    }
```

### Example Output (VETO - Level 1)

```
❌ GUILD VETOED: Climate Envelope Incompatibility

Guild has NO shared climate zone:
  - Temperature overlap: -8.3°C (need >0°C)
  - Hardiness overlap: -12.5°C (need >-5°C)
  - Precipitation overlap: -200mm (need >0mm)

OUTLIER PLANTS DETECTED:
  1. Cocos nucifera (Coconut)
     → Temperature mismatch: 24.0°C to 28.5°C (guild median: 12.5°C)
     → Precipitation mismatch: 1800mm to 3200mm (guild median: 900mm)
     → SEVERITY: Extreme outlier (15.5°C from median)

  2. Picea abies (Norway Spruce)
     → Hardiness mismatch: -28.0°C to -12.0°C (guild median: 2.0°C)
     → SEVERITY: Extreme cold-adapted (14.0°C from median)

RECOMMENDATION: Remove Cocos nucifera and Picea abies. Keep remaining temperate plants.
```

### Example Output (VETO - Level 2)

```
❌ GUILD VETOED: Winter Cold Tolerance Incompatibility

No shared winter temperature range. Guild needs 2.0°C to -5.0°C (impossible - negative overlap of -7.0°C)

PLANTS:
  - Citrus × limon: 2.0°C to 15.0°C winter minimum (frost-sensitive)
  - Acer saccharum: -25.0°C to -5.0°C winter minimum (needs cold winters)

Lemon's coldest locations (2°C) are WARMER than maple's warmest locations (-5°C).
One plant needs frost-free conditions, the other requires freezing winters.
```

### Example Output (PASS with Warnings)

```
✅ CLIMATE COMPATIBLE (Score: 0.78 / 1.0)

SHARED CLIMATE ZONE:
  - Temperature: 8.5°C to 18.2°C
  - Winter minimum: -8.0°C to 2.5°C (10.5°C range)
  - Precipitation: 600mm to 1200mm

SCORE BREAKDOWN:
  - Temperature overlap quality: 0.98 (excellent)
  - Precipitation overlap quality: 1.00 (excellent)
  - Winter temp range quality: 0.70 (good)
  - Vulnerability penalty: -0.10 (1 shared vulnerability)

⚠️  EXTREME CLIMATE VULNERABILITIES:
  1. Drought Vulnerability (High)
     → 4/5 plants are drought-sensitive (naturally occur only where droughts <30 days)
     → Average max drought survived: 22 days
     → Entire guild at risk during extended dry periods
     → RECOMMENDATION: Add drought-tolerant species or plan irrigation system
```

### Example Output (PERFECT)

```
✅ CLIMATE COMPATIBLE (Score: 0.95 / 1.0)

SHARED CLIMATE ZONE:
  - Temperature: 10.0°C to 16.5°C
  - Winter minimum: -23.0°C to -7.0°C (16°C range)
  - Precipitation: 750mm to 1100mm

SCORE BREAKDOWN:
  - Temperature overlap quality: 0.65 (moderate)
  - Precipitation overlap quality: 0.70 (good)
  - Winter temp range quality: 1.00 (excellent - 16°C range!)
  - Vulnerability penalty: 0.00 (no shared vulnerabilities)

SENSITIVITY SUMMARY:
  - Drought-sensitive: 1/5 plants (20%) - resilient
  - Frost-sensitive: 0/5 plants (0%) - frost-tolerant guild
  - Heat-sensitive: 2/5 plants (40%) - moderate diversity

No extreme climate vulnerabilities detected. Guild is climatically resilient.
```

---

## Part 2: CSR Strategy Compatibility (N4 - Negative Factor, 20%)

### Rationale

CSR strategies represent resource use and competitive ability:
- **C (Competitor)**: Fast-growing, high resource demand, outcompetes neighbors
- **S (Stress-tolerator)**: Slow-growing, low resource demand, tolerates poor conditions
- **R (Ruderal)**: Fast reproduction, colonizes disturbed areas, short-lived

**Bad combinations create conflicts** - BUT conflicts can be modulated by:
1. **EIVE light preference** (shade-adapted S plants can coexist with C)
2. **Height separation** (tall C + low R = different layers = low conflict)
3. **Growth form** (vine + tree = symbiotic, not conflict)

### Data Source

- Stage 3 CSR Scores: `C`, `S`, `R` (percentages, sum to 100)
- Stage 3 EIVE: `EIVEres-L` (light preference)
- Stage 3 Traits: `height_m`, `try_growth_form`

### CSR Conflict Types

| Combination | Base Conflict | Why? |
|-------------|---------------|------|
| **High-C + High-C** | 1.0 | Both compete for same resources |
| **High-C + High-S** | 0.6 | C may outcompete/shade S |
| **High-C + High-R** | 0.8 | C smothers R before it reproduces |
| **High-R + High-R** | 0.3 | Short-lived annuals compete briefly |
| **High-S + High-S** | 0.0 | Both slow, low competition |

**Thresholds:**
- High-C: C > 60%
- High-S: S > 60%
- High-R: R > 50%

### Conflict Modulation Rules

#### Modulation 1: Growth Form

| Form Combination | Effect | Multiplier |
|------------------|--------|------------|
| **Vine + Tree** | Vine climbs tree (symbiotic) | ×0.2 (reduce conflict) |
| **Tree + Herb** | Different strategies | ×0.4 |
| **Same form** | Check height instead | → Modulation 2 |

#### Modulation 2: Height Separation

**Why height matters**: Vertical resource partitioning

```
Height Difference     Light Zone Overlap    Competition Multiplier
───────────────────────────────────────────────────────────────────
< 2m                  SAME LAYER            1.0 (full competition)
2-5m                  OVERLAPPING           0.6 (moderate)
> 5m                  DIFFERENT LAYERS      0.3 (low competition)
```

**Ecological basis:**
- Same height → same light zone, similar root depth → **full competition**
- 5m+ separation → different canopy layers, different water access → **minimal competition**

#### Modulation 3: EIVE Light Preference (for High-C + High-S conflicts)

```
S Plant Light (EIVE-L)    Interpretation                Conflict Adjustment
─────────────────────────────────────────────────────────────────────────────
< -0.5                    Shade-adapted (wants shade)   × 0.0 (NO conflict!)
-0.5 to +0.5              Moderate (can adapt)          × 1.0 (base conflict)
> +0.5                    Sun-loving (needs sun)        × 1.5 (HIGH conflict!)
```

**Example**: Fern (S=80%, L=-1.2) under Oak (C=75%) → **0.0 conflict** (fern wants shade!)

### Method

```python
def detect_csr_conflicts_modulated(plant_ids, con):
    """
    Detect CSR conflicts with EIVE + height + growth form modulation.
    Returns conflict score [0, 1].
    """

    # Get all relevant data
    plants = con.execute(f"""
        SELECT
            plant_wfo_id,
            wfo_scientific_name,
            C, S, R,
            "EIVEres-L" as light_pref,
            height_m,
            try_growth_form
        FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')
        WHERE plant_wfo_id IN ({plant_ids_str})
          AND C IS NOT NULL
    """).fetchdf()

    conflicts = 0
    conflict_details = []

    HIGH_C = 60
    HIGH_S = 60
    HIGH_R = 50

    # ═══════════════════════════════════════════════════════════════
    # CONFLICT 1: High-C + High-C
    # ═══════════════════════════════════════════════════════════════

    high_c_plants = plants[plants['C'] > HIGH_C]

    if len(high_c_plants) >= 2:
        for i in range(len(high_c_plants)):
            for j in range(i+1, len(high_c_plants)):
                plant_a = high_c_plants.iloc[i]
                plant_b = high_c_plants.iloc[j]

                conflict = 1.0  # Base

                # MODULATION: Growth Form
                form_a = str(plant_a['try_growth_form']).lower()
                form_b = str(plant_b['try_growth_form']).lower()

                if ('vine' in form_a or 'liana' in form_a) and 'tree' in form_b:
                    conflict *= 0.2
                    reason = f"Low: {plant_a['wfo_scientific_name']} (vine) climbs {plant_b['wfo_scientific_name']} (tree)"
                elif ('vine' in form_b or 'liana' in form_b) and 'tree' in form_a:
                    conflict *= 0.2
                    reason = f"Low: {plant_b['wfo_scientific_name']} (vine) climbs {plant_a['wfo_scientific_name']} (tree)"
                elif ('tree' in form_a and 'herb' in form_b) or ('tree' in form_b and 'herb' in form_a):
                    conflict *= 0.4
                    reason = f"Moderate: Tree vs herb (different strategies)"
                else:
                    # MODULATION: Height
                    height_diff = abs(plant_a['height_m'] - plant_b['height_m'])
                    if height_diff < 2.0:
                        conflict *= 1.0
                        reason = f"INTENSE: Both ~{plant_a['height_m']:.1f}m (same layer)"
                    elif height_diff < 5.0:
                        conflict *= 0.6
                        reason = f"Moderate: {plant_a['height_m']:.1f}m vs {plant_b['height_m']:.1f}m (overlapping)"
                    else:
                        conflict *= 0.3
                        reason = f"Low: {plant_a['height_m']:.1f}m vs {plant_b['height_m']:.1f}m (different layers)"

                conflicts += conflict

                if conflict > 0.2:
                    conflict_details.append({
                        'type': 'Competitor-Competitor',
                        'severity': 'High' if conflict >= 0.7 else ('Moderate' if conflict >= 0.4 else 'Low'),
                        'plants': [plant_a['wfo_scientific_name'], plant_b['wfo_scientific_name']],
                        'conflict_score': conflict,
                        'description': reason
                    })

    # ═══════════════════════════════════════════════════════════════
    # CONFLICT 2: High-C + High-S
    # ═══════════════════════════════════════════════════════════════

    high_s_plants = plants[plants['S'] > HIGH_S]

    for idx_c, plant_c in plants[plants['C'] > HIGH_C].iterrows():
        for idx_s, plant_s in high_s_plants.iterrows():
            if idx_c != idx_s:
                conflict = 0.6  # Base

                # MODULATION: Light Preference (CRITICAL!)
                s_light = plant_s['light_pref']

                if s_light < -0.5:
                    # S is SHADE-ADAPTED - wants to be under C!
                    conflict = 0.0
                    reason = f"✅ COMPATIBLE: {plant_s['wfo_scientific_name']} is shade-adapted (L={s_light:.2f}), thrives under {plant_c['wfo_scientific_name']}"
                elif s_light > 0.5:
                    # S is SUN-LOVING - C will shade it!
                    conflict = 0.9
                    reason = f"❌ HIGH CONFLICT: {plant_s['wfo_scientific_name']} needs sun (L={s_light:.2f}) but {plant_c['wfo_scientific_name']} will shade it"
                else:
                    # MODULATION: Height
                    height_diff = abs(plant_c['height_m'] - plant_s['height_m'])
                    if height_diff > 8.0:
                        conflict *= 0.3
                        reason = f"Low: {plant_s['wfo_scientific_name']} ({plant_s['height_m']:.1f}m) under {plant_c['wfo_scientific_name']} ({plant_c['height_m']:.1f}m)"
                    else:
                        reason = f"Moderate: {plant_c['wfo_scientific_name']} may outcompete {plant_s['wfo_scientific_name']}"

                conflicts += conflict

                if conflict > 0.2:
                    conflict_details.append({
                        'type': 'Competitor-Stress-tolerator',
                        'severity': 'High' if conflict >= 0.7 else 'Low',
                        'plants': [plant_c['wfo_scientific_name'], plant_s['wfo_scientific_name']],
                        'conflict_score': conflict,
                        'description': reason
                    })

    # ═══════════════════════════════════════════════════════════════
    # CONFLICT 3: High-C + High-R
    # ═══════════════════════════════════════════════════════════════

    high_r_plants = plants[plants['R'] > HIGH_R]

    for idx_c, plant_c in plants[plants['C'] > HIGH_C].iterrows():
        for idx_r, plant_r in high_r_plants.iterrows():
            if idx_c != idx_r:
                conflict = 0.8  # Base

                # MODULATION: Height + Growth Form
                height_diff = abs(plant_c['height_m'] - plant_r['height_m'])
                form_r = str(plant_r['try_growth_form']).lower()

                if plant_r['height_m'] < 0.5 and plant_c['height_m'] > 10.0:
                    conflict *= 0.2
                    reason = f"Low: {plant_r['wfo_scientific_name']} is ground cover ({plant_r['height_m']:.1f}m) under {plant_c['wfo_scientific_name']} ({plant_c['height_m']:.1f}m)"
                elif 'vine' in form_r or 'liana' in form_r:
                    conflict *= 0.1
                    reason = f"Minimal: {plant_r['wfo_scientific_name']} (vine) climbs {plant_c['wfo_scientific_name']}"
                elif height_diff < 3.0:
                    conflict *= 1.2
                    reason = f"HIGH: {plant_c['wfo_scientific_name']} ({plant_c['height_m']:.1f}m) smothers {plant_r['wfo_scientific_name']} ({plant_r['height_m']:.1f}m)"
                else:
                    reason = f"Moderate: {plant_c['wfo_scientific_name']} may outcompete {plant_r['wfo_scientific_name']}"

                # MODULATION: Light tolerance
                if plant_r['light_pref'] < 0 and conflict > 0.3:
                    conflict *= 0.6
                    reason += f" (but {plant_r['wfo_scientific_name']} is shade-tolerant)"

                conflicts += conflict

                if conflict > 0.2:
                    conflict_details.append({
                        'type': 'Competitor-Ruderal',
                        'severity': 'High' if conflict >= 0.7 else 'Low',
                        'plants': [plant_c['wfo_scientific_name'], plant_r['wfo_scientific_name']],
                        'conflict_score': conflict,
                        'description': reason
                    })

    # ═══════════════════════════════════════════════════════════════
    # CONFLICT 4: High-R + High-R
    # ═══════════════════════════════════════════════════════════════

    if len(high_r_plants) >= 2:
        for i in range(len(high_r_plants)):
            for j in range(i+1, len(high_r_plants)):
                plant_a = high_r_plants.iloc[i]
                plant_b = high_r_plants.iloc[j]

                conflict = 0.3  # Low - short-lived annuals
                reason = f"Low: Both ruderals (boom-bust cycle, short-lived)"

                conflicts += conflict
                conflict_details.append({
                    'type': 'Ruderal-Ruderal',
                    'severity': 'Low',
                    'plants': [plant_a['wfo_scientific_name'], plant_b['wfo_scientific_name']],
                    'conflict_score': conflict,
                    'description': reason
                })

    # Normalize
    n_plants = len(plants)
    max_conflicts = n_plants * (n_plants - 1) / 2
    conflict_score = min(conflicts / max_conflicts, 1.0) if max_conflicts > 0 else 0

    return {
        'conflict_score': conflict_score,
        'conflict_details': conflict_details,
        'raw_conflicts': conflicts,
        'max_possible': max_conflicts
    }
```

### Examples

**Example 1: Oak + Fern (NO CONFLICT)**
- Oak: C=75%, height=15m, L=+0.8
- Fern: S=80%, height=0.3m, L=-1.2 (shade-adapted!)
- Base conflict: 0.6
- Modulation: Fern L=-1.2 → ×0.0
- **Final: 0.0** (compatible - fern wants shade under oak!)

**Example 2: Two Oaks (HIGH CONFLICT)**
- Oak A: C=75%, height=15m
- Oak B: C=70%, height=14m
- Base conflict: 1.0
- Modulation: height_diff=1m → ×1.0
- **Final: 1.0** (intense competition - same canopy layer)

**Example 3: Oak + Grape Vine (LOW CONFLICT)**
- Oak: C=75%, height=15m, form=tree
- Grape: C=65%, height=10m, form=vine
- Base conflict: 1.0
- Modulation: vine+tree → ×0.2
- **Final: 0.2** (low - vine climbs tree)

---

## Part 3: Phylogenetic Diversity (P4 - Positive Factor, 20%)

### Rationale

Current P4 uses simple family counting: `n_families / n_plants`. This is crude.

**Better**: Use phylogenetic eigenvectors (92 columns: `phylo_ev1` through `phylo_ev92`).

Plants that are phylogenetically distant are less likely to share:
- Pathogens (host specificity)
- Herbivores (feeding preferences)
- Resource requirements (niche conservatism)

### Data Source

Stage 3 Phylogenetic Eigenvectors: `phylo_ev1` through `phylo_ev92`

### Method

```python
def compute_phylogenetic_diversity(plant_ids, con):
    """
    Compute phylogenetic diversity using eigenvector distances.
    Returns diversity score [0, 1].
    """

    # Get first 10 eigenvectors (capture most variance)
    phylo = con.execute(f"""
        SELECT
            plant_wfo_id,
            phylo_ev1, phylo_ev2, phylo_ev3, phylo_ev4, phylo_ev5,
            phylo_ev6, phylo_ev7, phylo_ev8, phylo_ev9, phylo_ev10
        FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')
        WHERE plant_wfo_id IN ({plant_ids_str})
    """).fetchdf()

    # Compute pairwise phylogenetic distances
    from scipy.spatial.distance import pdist
    ev_cols = [f'phylo_ev{i}' for i in range(1, 11)]
    ev_matrix = phylo[ev_cols].values
    distances = pdist(ev_matrix, metric='euclidean')

    # Mean pairwise distance
    mean_distance = np.mean(distances) if len(distances) > 0 else 0

    # Normalize (typical range: 0-5 for 10 eigenvectors)
    diversity_score = np.tanh(mean_distance / 3)

    return diversity_score
```

### Comparison: Eigenvectors vs Family Counting

**5 Acacias (same genus):**
- Old: 1 family / 5 plants = 0.20
- New: mean_phylo_distance ≈ 0.8 → tanh(0.8/3) = **0.26**

**Diverse guild (Fabaceae, Pinaceae, Malvaceae):**
- Old: 3 families / 5 plants = 0.60
- New: mean_phylo_distance ≈ 3.5 (conifers vs angiosperms) → tanh(3.5/3) = **0.85**

**Improvement**: Captures deeper evolutionary divergence.

---

## Part 4: Vertical and Form Stratification (P5 - Positive Factor, 10%)

### Rationale

Layered planting with diverse growth forms reduces competition and creates habitat structure.

**Two components:**
1. **Height layers** (60% of P5): Ground cover → shrub → tree
2. **Growth form diversity** (40% of P5): Tree, vine, shrub, herb, grass

### Data Source

- Stage 3: `height_m` (from `exp(logH)`)
- Stage 3: `try_growth_form`

### Height Layers

```
Layer            Height Range    Example
─────────────────────────────────────────────
Ground cover     0-0.5m          Moss, clover
Low herb         0.5-2m          Ferns, grasses
Shrub            2-5m            Blueberry, rose
Small tree       5-15m           Dogwood, redbud
Large tree       15m+            Oak, maple
```

### Growth Forms

```
Form         Description                  Example
──────────────────────────────────────────────────────
Tree         Woody, single trunk          Oak, pine
Shrub        Woody, multi-stem            Blueberry, rose
Vine/Liana   Climbing plant               Grape, wisteria
Herb/Forb    Non-woody broadleaf          Fern, wildflower
Grass        Graminoid                    Switchgrass, sedge
Succulent    Fleshy water-storing         Cactus, sedum
```

### Method

```python
def compute_vertical_and_form_stratification(plant_ids, con):
    """
    Reward guilds with multiple height layers AND diverse growth forms.
    Returns stratification score [0, 1].
    """

    plants = con.execute(f"""
        SELECT
            plant_wfo_id,
            wfo_scientific_name,
            height_m,
            try_growth_form
        FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')
        WHERE plant_wfo_id IN ({plant_ids_str})
          AND height_m IS NOT NULL
    """).fetchdf()

    # ═══════════════════════════════════════════════════════════════
    # COMPONENT 1: Height Layers (60%)
    # ═══════════════════════════════════════════════════════════════

    def assign_height_layer(height):
        if height < 0.5:
            return 'ground_cover'
        elif height < 2.0:
            return 'low_herb'
        elif height < 5.0:
            return 'shrub'
        elif height < 15.0:
            return 'small_tree'
        else:
            return 'large_tree'

    plants['height_layer'] = plants['height_m'].apply(assign_height_layer)

    n_height_layers = plants['height_layer'].nunique()
    height_diversity = (n_height_layers - 1) / 4  # 0-1 (5 layers max)

    height_range = plants['height_m'].max() - plants['height_m'].min()
    height_range_norm = np.tanh(height_range / 10)

    height_score = 0.6 * height_diversity + 0.4 * height_range_norm

    # ═══════════════════════════════════════════════════════════════
    # COMPONENT 2: Growth Form Diversity (40%)
    # ═══════════════════════════════════════════════════════════════

    def categorize_growth_form(form_str):
        form = str(form_str).lower()
        if 'tree' in form:
            return 'tree'
        elif 'shrub' in form:
            return 'shrub'
        elif 'vine' in form or 'liana' in form or 'climber' in form:
            return 'vine'
        elif 'herb' in form or 'forb' in form:
            return 'herb'
        elif 'grass' in form or 'graminoid' in form:
            return 'grass'
        elif 'succulent' in form:
            return 'succulent'
        else:
            return 'other'

    plants['growth_form_category'] = plants['try_growth_form'].apply(categorize_growth_form)

    n_growth_forms = plants['growth_form_category'].nunique()
    form_diversity = (n_growth_forms - 1) / 5  # 0-1 (6 forms max)

    # Bonuses for specific beneficial combinations
    forms_present = set(plants['growth_form_category'])
    form_bonus = 0.0

    if 'tree' in forms_present and 'vine' in forms_present:
        form_bonus += 0.2  # Vine climbs tree
    if 'tree' in forms_present and len(plants[plants['height_m'] < 0.5]) > 0:
        form_bonus += 0.2  # Tree + ground cover
    if len(plants[(plants['height_m'] > 2) & (plants['height_m'] < 5)]) > 0 and \
       len(plants[plants['height_m'] > 10]) > 0:
        form_bonus += 0.2  # Shrub + tree layers

    form_score = min(form_diversity + form_bonus, 1.0)

    # ═══════════════════════════════════════════════════════════════
    # COMBINED SCORE
    # ═══════════════════════════════════════════════════════════════

    stratification_score = 0.6 * height_score + 0.4 * form_score

    return {
        'stratification_score': stratification_score,
        'n_height_layers': n_height_layers,
        'height_layers': plants['height_layer'].unique().tolist(),
        'height_range_m': height_range,
        'n_growth_forms': n_growth_forms,
        'growth_forms': plants['growth_form_category'].unique().tolist()
    }
```

### Examples

**Perfect Guild** (Oak + Wisteria + Blueberry + Fern + Moss):
- Height layers: 5/5 = 1.0
- Height range: 15m → 0.99
- Growth forms: tree, vine, shrub, herb = 4/6
- Bonuses: tree+vine, tree+ground, shrub+tree = +0.6
- **P5 = 0.998** (perfect!)

**Monoculture** (5 similar Acacias):
- Height layers: 1/5 = 0.0
- Height range: 2m → 0.20
- Growth forms: 1/6 = 0.0
- **P5 = 0.048** (terrible!)

---

## Part 5: Nitrogen Fixation (N5 - Negative Factor, 5%)

### Rationale

Guilds without nitrogen-fixing plants deplete soil nitrogen over time, requiring fertilizer or amendments.

**Ceteris paribus**: Guild with N-fixers > Guild without N-fixers.

### Data Source

Stage 3: `nitrogen_fixation_rating` (High / Moderate-High / Moderate-Low / Low)

### Method

```python
def check_nitrogen_fixation(plant_ids, con):
    """
    Penalize guilds without nitrogen-fixing plants.
    Returns penalty [0, 1].
    """

    nfix = con.execute(f"""
        SELECT
            plant_wfo_id,
            wfo_scientific_name,
            nitrogen_fixation_rating
        FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')
        WHERE plant_wfo_id IN ({plant_ids_str})
    """).fetchdf()

    n_fixers = len(nfix[nfix['nitrogen_fixation_rating'].isin(['High', 'Moderate-High'])])

    if n_fixers == 0:
        return {'penalty': 0.3, 'n_fixers': 0, 'message': 'No N-fixers - needs fertilizer'}
    elif n_fixers == 1:
        return {'penalty': 0.1, 'n_fixers': 1, 'message': 'One N-fixer present'}
    else:
        return {'penalty': 0.0, 'n_fixers': n_fixers, 'message': f'{n_fixers} N-fixers - good fertility'}
```

---

## Part 6: Soil pH Compatibility (N6 - Negative Factor, 5%)

### Rationale

Soil can be amended (lime/sulfur), so incompatibility is minor.

**Ceteris paribus**: Narrow pH range > Wide pH range (less amendment needed).

### Data Source

Stage 3: `phh2o_0-5cm_q50` (surface pH, stored as pH × 10)

### Method

```python
def compute_soil_incompatibility(plant_ids, con):
    """
    Slight penalty for extreme pH differences.
    Returns incompatibility [0, 1].
    """

    soil = con.execute(f"""
        SELECT "phh2o_0-5cm_q50" as soil_ph
        FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')
        WHERE plant_wfo_id IN ({plant_ids_str})
    """).fetchdf()

    ph_range = soil['soil_ph'].max() - soil['soil_ph'].min()

    if ph_range > 20:  # >2 pH units
        incompatibility = np.tanh((ph_range - 20) / 20)
        message = f'Wide pH range ({ph_range/10:.1f} units) - needs amendments'
    else:
        incompatibility = 0.0
        message = f'Compatible pH range ({ph_range/10:.1f} units)'

    return {'incompatibility': incompatibility, 'ph_range': ph_range/10, 'message': message}
```

---

## Part 7: Shared Pollinators (P6 - Positive Factor, 10%)

### Rationale

**Pollinators ≠ Biocontrol**

- **P1 (Biocontrol)**: Plant A's visitors eat Plant B's pests
- **P6 (Pollinators)**: Plants share pollinators → larger pollinator populations → better reproduction

**Example:**
- Lavender + Rosemary + Thyme all attract bees
- More bee-attracting plants → more bees → better pollination for all

### Data Source

Stage 4: `flower_visitors` from `plant_organism_profiles.parquet`

### Method

```python
def compute_shared_pollinator_benefit(plant_ids, con):
    """
    Reward guilds where plants share pollinators.
    """

    pollinators = con.execute(f"""
        WITH plant_pollinators AS (
            SELECT
                plant_wfo_id,
                UNNEST(flower_visitors) as pollinator
            FROM read_parquet('data/stage4/plant_organism_profiles.parquet')
            WHERE plant_wfo_id IN ({plant_ids_str})
              AND visitor_count > 0
        )
        SELECT
            pollinator,
            COUNT(DISTINCT plant_wfo_id) as plant_count
        FROM plant_pollinators
        GROUP BY pollinator
        HAVING plant_count >= 2
    """).fetchdf()

    if len(pollinators) == 0:
        return {'score': 0.0, 'shared': 0}

    # Score overlap (opposite of pathogen penalty!)
    overlap_score = 0
    n_plants = len(plant_ids)

    for _, row in pollinators.iterrows():
        overlap_ratio = row['plant_count'] / n_plants
        overlap_score += overlap_ratio ** 2

    shared_pollinator_norm = np.tanh(overlap_score / 5.0)

    return {
        'score': shared_pollinator_norm,
        'shared': len(pollinators),
        'message': f'{len(pollinators)} shared pollinators'
    }
```

---

## Part 8: Tall Competitive Plant Detection (W1 - Warning)

### Rationale

Tall plants with high C scores can smother neighbors. Flag but don't penalize (gardeners may want canopy trees).

### Method

```python
def detect_tall_competitive_plants(plant_ids, con):
    """
    Flag tall competitive plants.
    """

    plants = con.execute(f"""
        SELECT
            plant_wfo_id,
            wfo_scientific_name,
            height_m,
            C as competitor_score
        FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')
        WHERE plant_wfo_id IN ({plant_ids_str})
          AND height_m > 10.0
          AND C > 60
    """).fetchdf()

    warnings = []
    for idx, plant in plants.iterrows():
        warnings.append({
            'plant': plant['wfo_scientific_name'],
            'height': plant['height_m'],
            'C': plant['competitor_score'],
            'warning': f'{plant["wfo_scientific_name"]} is tall ({plant["height_m"]:.1f}m) and competitive (C={plant["competitor_score"]:.0f}%). Ensure adequate spacing.',
            'recommendation': 'Place on north side, allow 5-8m spacing'
        })

    return warnings
```

---

## Part 9: Ecosystem Services (Separate CWM Output)

### Rationale

Services measure what the guild DOES, not compatibility.

### Method

```python
def compute_ecosystem_service_cwm(plant_ids, con):
    """
    Calculate community-weighted mean for ecosystem services.
    Does NOT affect guild score.
    """

    rating_map = {
        'Very Low': 1, 'Low': 2, 'Moderate': 3,
        'Moderate-Low': 2.5, 'Moderate-High': 3.5,
        'High': 4, 'Very High': 5
    }

    services = con.execute(f"""
        SELECT
            npp_rating,
            decomposition_rating,
            nutrient_cycling_rating,
            carbon_total_rating,
            nitrogen_fixation_rating,
            erosion_protection_rating
        FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')
        WHERE plant_wfo_id IN ({plant_ids_str})
    """).fetchdf()

    # Convert to numeric and calculate CWM
    cwm = {}
    for col in services.columns:
        services[col + '_numeric'] = services[col].map(rating_map)
        cwm[col.replace('_rating', '')] = services[col + '_numeric'].mean()

    return cwm
```

### Display

```
═══════════════════════════════════════════════════════════════════
ECOSYSTEM SERVICES PROVIDED BY THIS GUILD
═══════════════════════════════════════════════════════════════════

Net Primary Productivity:     ████████░░ 4.2 / 5.0 (High)
Decomposition Rate:           ██████░░░░ 3.1 / 5.0 (Moderate)
Nutrient Cycling:             ███████░░░ 3.5 / 5.0 (Moderate-High)
Carbon Storage:               █████████░ 4.5 / 5.0 (Very High)
Nitrogen Fixation:            ████░░░░░░ 2.0 / 5.0 (Low)
Erosion Protection:           ███████░░░ 3.8 / 5.0 (High)
```

---

## Part 10: Complete Scoring Algorithm (v2)

```python
def compute_guild_score_v2(plant_ids, con):
    """
    Complete v2 guild compatibility scorer.
    """

    # ═══════════════════════════════════════════════════════════════
    # STEP 1: CLIMATE VETO (3-Level Analysis)
    # ═══════════════════════════════════════════════════════════════

    climate_check = check_climate_compatibility_complete(plant_ids, con)

    if climate_check['veto']:
        return {
            'guild_score': -999,
            'veto': True,
            'veto_level': climate_check['level'],
            'veto_reason': climate_check['reason'],
            'message': climate_check['message'],
            'outliers': climate_check.get('outliers', []),
            'recommendation': climate_check.get('recommendation', 'Remove incompatible plants')
        }

    # Store climate quality score for later use
    climate_quality_score = climate_check['climate_quality_score']

    # ═══════════════════════════════════════════════════════════════
    # STEP 2: NEGATIVE FACTORS (100%)
    # ═══════════════════════════════════════════════════════════════

    # Existing (Stage 4)
    N1 = compute_pathogen_fungi_overlap(plant_ids, con)
    N2 = compute_herbivore_overlap(plant_ids, con)

    # New (Stage 3)
    N4 = detect_csr_conflicts_modulated(plant_ids, con)['conflict_score']
    N5 = check_nitrogen_fixation(plant_ids, con)['penalty']
    N6 = compute_soil_incompatibility(plant_ids, con)['incompatibility']

    # Normalize N1, N2
    N1_norm = np.tanh(N1 / 50)
    N2_norm = np.tanh(N2 / 100)

    negative_risk_score = (
        0.35 * N1_norm +
        0.35 * N2_norm +
        0.20 * N4 +
        0.05 * N5 +
        0.05 * N6
    )

    # ═══════════════════════════════════════════════════════════════
    # STEP 3: POSITIVE FACTORS (100%)
    # ═══════════════════════════════════════════════════════════════

    # Existing (Stage 4)
    P1 = compute_biocontrol(plant_ids, con)
    P2 = compute_pathogen_control(plant_ids, con)
    P3 = compute_beneficial_fungi(plant_ids, con)

    # Improved/New (Stage 3)
    P4 = compute_phylogenetic_diversity(plant_ids, con)
    P5 = compute_vertical_and_form_stratification(plant_ids, con)['stratification_score']
    P6 = compute_shared_pollinator_benefit(plant_ids, con)['score']

    positive_benefit_score = (
        0.25 * P1 +
        0.20 * P2 +
        0.15 * P3 +
        0.20 * P4 +
        0.10 * P5 +
        0.10 * P6
    )

    # ═══════════════════════════════════════════════════════════════
    # STEP 4: COMBINED SCORE
    # ═══════════════════════════════════════════════════════════════

    guild_score = positive_benefit_score - negative_risk_score

    # ═══════════════════════════════════════════════════════════════
    # STEP 5: WARNINGS
    # ═══════════════════════════════════════════════════════════════

    warnings = detect_tall_competitive_plants(plant_ids, con)

    # ═══════════════════════════════════════════════════════════════
    # STEP 6: ECOSYSTEM SERVICES (SEPARATE)
    # ═══════════════════════════════════════════════════════════════

    ecosystem_services = compute_ecosystem_service_cwm(plant_ids, con)

    return {
        'guild_score': guild_score,
        'veto': False,
        'positive_benefit_score': positive_benefit_score,
        'negative_risk_score': negative_risk_score,
        'climate_quality_score': climate_quality_score,
        'climate_details': {
            'shared_zone': climate_check['shared_climate_zone'],
            'winter_temp_range': climate_check['winter_temp_range'],
            'score_components': climate_check['score_components'],
            'extreme_vulnerabilities': climate_check['extreme_vulnerabilities'],
            'sensitivity_summary': climate_check['sensitivity_summary']
        },
        'components': {
            'N1_pathogen_fungi': N1_norm,
            'N2_herbivores': N2_norm,
            'N4_csr_conflicts': N4,
            'N5_no_nitrogen_fixation': N5,
            'N6_soil_incompatibility': N6,
            'P1_biocontrol': P1,
            'P2_pathogen_control': P2,
            'P3_beneficial_fungi': P3,
            'P4_phylogenetic_diversity': P4,
            'P5_vertical_form_stratification': P5,
            'P6_shared_pollinators': P6
        },
        'warnings': warnings,
        'ecosystem_services_cwm': ecosystem_services
    }
```

---

## Part 11: Implementation Roadmap

### Phase 1: Data Preparation (Week 1)

**Script:** `src/Stage_4/06_prepare_stage3_integration.py`

Extract from Stage 3 and compute derived variables:

**Climate Data**:
- Temperature: bio_1 (q05, q50, q95), bio_6 (q05, q50, q95)
- Precipitation: bio_12 (q05, q50, q95)
- Extreme indices: CDD_q95, CFD_q95, WSDI_q95

**Pre-Calculate Climate Sensitivity Ratings**:
- `drought_sensitivity` (High/Medium/Low) from CDD_q95
  - High: CDD_q95 < 30 days (needs reliable moisture)
  - Medium: 30-60 days
  - Low: >60 days (drought-tolerant)
- `frost_sensitivity` (High/Medium/Low) from CFD_q95
  - High: CFD_q95 < 10 days (frost-tender)
  - Medium: 10-30 days
  - Low: >30 days (frost-tolerant)
- `heat_sensitivity` (High/Medium/Low) from WSDI_q95
  - High: WSDI_q95 < 20 days (prefers cool climates)
  - Medium: 20-50 days
  - Low: >50 days (heat-tolerant)

**Other Data**:
- Soil: phh2o (0-5cm q50)
- CSR: C, S, R
- EIVE: EIVEres-L, EIVEres-M
- Phylogeny: phylo_ev1 through phylo_ev10
- Traits: height_m, try_growth_form
- Services: All 10 ratings

Save as:
- `data/stage4/plant_climate_profiles.parquet` (includes pre-calculated sensitivity ratings)
- `data/stage4/plant_csr_profiles.parquet`
- `data/stage4/plant_phylo_profiles.parquet`
- `data/stage4/plant_service_profiles.parquet`

### Phase 2: Climate Compatibility Matrix (Week 1)

**Script:** `src/Stage_4/07_compute_climate_compatibility.py`

Precompute climate compatibility for all 11,680 plants.

### Phase 3: Scorer v2 Implementation (Week 2)

**Script:** `src/Stage_4/08_compute_guild_compatibility_v2.py`

Implement all new components:
- `check_climate_veto_guild_range()`
- `detect_csr_conflicts_modulated()`
- `compute_phylogenetic_diversity()`
- `compute_vertical_and_form_stratification()`
- `check_nitrogen_fixation()`
- `compute_soil_incompatibility()`
- `compute_shared_pollinator_benefit()`
- `detect_tall_competitive_plants()`
- `compute_ecosystem_service_cwm()`

### Phase 4: Enhanced Explanations (Week 2)

**Script:** `src/Stage_4/08b_explain_guild_score_v2.py`

Add explanations for all new components.

### Phase 5: Testing (Week 3)

**Script:** `src/Stage_4/test_guild_scorer_v2.py`

Test guilds:
1. CLIMATE_VETO: Coconut + Apple
2. CSR_CONFLICT: Multiple high-C trees
3. PERFECT_LAYERING: Oak + Vine + Shrub + Fern
4. NO_NFIX: All non-legumes
5. SHADE_COMPATIBLE: Oak + shade-loving fern

### Phase 6: Documentation (Week 3)

Update all framework docs with v2.

---

## Part 12: Expected Impact on Test Guilds

### BAD Guild (5 Acacias)

**v1 score:** -0.159

**v2 components:**
- Climate: PASS ✅
- N4: 0.40 (all high-C competing) ❌
- N5: 0.0 (legumes) ✅
- N6: 0.0 ✅
- P4: 0.26 (same genus) ⚠️
- P5: 0.05 (no stratification) ❌
- P6: 0.3 (some shared pollinators) ⚠️

**v2 score:** -0.22 (worse - correctly penalized for CSR conflicts)

### GOOD Guild #1 (Diverse)

**v1 score:** +0.322

**v2 components:**
- Climate: PASS ✅
- N4: 0.10 ✓
- N5: 0.10 ✓
- N6: 0.0 ✅
- P4: 0.85 (high phylo diversity) ✅
- P5: 0.70 (3 layers) ✅
- P6: 0.4 ✓

**v2 score:** +0.40 (better - rewarded for diversity)

### GOOD Guild #2 (Pollinator)

**v1 score:** +0.028

**v2 components:**
- Climate: PASS ✅
- N4: 0.15 ⚠️
- N5: 0.30 (no legumes) ⚠️
- N6: 0.0 ✅
- P4: 0.75 ✅
- P5: 0.60 ✓
- P6: 0.85 (many shared pollinators!) ✅

**v2 score:** +0.18 (better - rewarded for pollinators!)

---

**End of Document 4.3 (FINAL REVISION)**
