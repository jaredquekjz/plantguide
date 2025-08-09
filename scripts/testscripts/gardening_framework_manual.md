# Trait-Based Gardening Advisor: Framework Manual

## Overview

This project provides a Python-based **Gardening Advisor** that generates practical, science-based care recommendations for plants. It translates complex eco-physiological principles from the **`medfate` forest simulator** into actionable advice on light, water, soil, and overall plant care.

The core of this advisor is the principle that a plant's observable and measurable biological traits can accurately predict its ecological strategy and, therefore, its needs in a garden setting.

## Scientific Foundation: The `medfate` Bridge

This advisor is a direct application of the theories and validated models within the [`medfate` R package](https://emf-creaf.github.io/medfate/), a sophisticated tool for simulating forest dynamics. `medfate` is not just a collection of traits; it's a dynamic simulator where these traits drive processes that lead to real-world outcomes like growth, stress, and mortality. Our advisor leverages these direct causal links.

### 1. Turgor → Growth & Vigor

*   **What `medfate` Directly Models:** The model calculates cell turgor pressure from the balance of plant water potential (`Ψ`) and osmotic potential (`π0_stem`). This turgor is explicitly used as a **sink limitation for growth**; without sufficient turgor, the model halts the formation of new leaves and wood.
*   **The Bridge to Gardening:** Plant growth is the physical expansion of cells driven by water pressure (turgor). A wilted plant is one with zero turgor and, therefore, zero growth.
*   **Our Logical Extension:** When our advisor recommends "consistent moisture" for a fast-growing plant, it's a direct application of this principle. The goal is to maintain the high turgor pressure that `medfate` identifies as essential for achieving vigorous growth.

### 2. Hydraulic Failure → Desiccation & Death

*   **What `medfate` Directly Models:** The model uses a plant's P50 (`d_stem`) to define its vulnerability to xylem embolism. As water stress increases, the model calculates the Percentage of Lost Conductivity (PLC). High PLC leads to a drop in the plant's Relative Water Content (RWC), and the model triggers **desiccation mortality** when RWC falls below a critical threshold.
*   **The Bridge to Gardening:** P50 is a direct measure of a plant's risk of catastrophic death during a dry spell.
*   **Our Logical Extension:** The advisor's watering recommendations are designed to keep a plant's water potential safely above its P50, directly preventing the modeled mortality pathway. The link between P50 and "Drought Tolerance" is therefore a direct and validated application.

### 3. Carbon Balance → Resilience & Starvation

*   **What `medfate` Directly Models:** The model performs a daily carbon balance, tracking photosynthetic gains against respiration and growth costs. A persistent negative balance depletes stored labile carbon, and the model triggers **starvation mortality** when these reserves are exhausted.
*   **The Bridge to Gardening:** This is a direct simulation of plant **vigor and resilience**. A positive carbon balance provides the energy for growth, defense, and recovery from stress.
*   **Our Logical Extension:** The advisor's light and fertility recommendations are aimed at ensuring the plant can maintain a positive carbon balance. Our advice on "Pruning Response" is a direct extension of this: "acquisitive" plants (high photosynthetic capacity) can more easily afford the carbon cost of regrowing tissue.

### 4. Phenology → Seasonal Resource Demand

*   **What `medfate` Directly Models:** The model explicitly tracks leaf phenology states (bud burst, maturity, senescence) driven by temperature and photoperiod. These states fundamentally alter a plant's water use, carbon gain, and nutrient demand throughout the year. Deciduous plants cease leaf respiration when leafless, preventing carbon starvation.
*   **The Bridge to Gardening:** A plant's care requirements change dramatically with its phenological state. A dormant plant needs minimal water and no fertilizer; feeding it would be wasteful or harmful.
*   **Our Logical Extension:** The advisor generates season-specific care routines that align with the plant's phenological cycle. This ensures interventions (watering, feeding, pruning) occur when the plant can best utilize them, directly applying `medfate`'s phenological modeling.

### 5. Light Competition → Spacing & Compatibility

*   **What `medfate` Directly Models:** The model uses vertical canopy layers and light extinction coefficients (`k_PAR`) to calculate light interception by height order. Taller plants with high `k_PAR` values cast deep shade, directly reducing light available to shorter neighbors. This asymmetric competition drives understory mortality in the model.
*   **The Bridge to Gardening:** Garden plants compete for light exactly as modeled in forests. A fast-growing tree will shade out sun-loving shrubs planted too close.
*   **Our Logical Extension:** The advisor calculates competitive strategies and spacing recommendations based on height, growth rate, and shade-casting ability. This prevents the light-limitation mortality that `medfate` predicts in overcrowded stands.

### 6. Shade Carbon Economics → True Shade Tolerance

*   **What `medfate` Directly Models:** In low light, the model reduces photosynthetic rates while maintaining temperature-dependent respiration. Plants can only survive shade if their reduced photosynthesis still exceeds their maintenance costs. High-Nleaf plants have both higher photosynthetic capacity AND higher respiration rates.
*   **The Bridge to Gardening:** This explains why some "shade plants" fail in deep shade - their carbon balance becomes negative despite shade-adapted leaves.
*   **Our Logical Extension:** The advisor calculates shade tolerance as a carbon balance equation, not just leaf traits. It identifies plants that require fertile soil in shade (to maximize photosynthesis) versus those that survive through low respiration. This nuanced approach directly applies `medfate`'s carbon balance logic.

---

## The Recommendation Framework

The following sections detail how the advisor translates plant traits into specific, actionable gardening advice. All thresholds and logic are implemented directly in the `GardeningAdvisor` class.

### 1. Light Requirements

Determined by the Leaf Economics Spectrum, which balances the cost of leaf construction against its photosynthetic return.

| SLA Category (m²/kg) | Nleaf Category (mmol/g) | Light Strategy | Garden Implication |
|---|---|---|---|
| High (`> 15`) | High (`> 25`) | **Full sun acquisitive** | Fast growers needing abundant resources. |
| High (`> 15`) | Low (`< 25`) | **Shade tolerant** | Efficient light capture in understory. |
| Low (`< 15`) | High (`> 25`) | **Full sun demanding** | Dense, costly leaves requiring high light. |
| Low (`< 15`) | Low (`< 25`) | **Full sun stress-tolerant** | Adapted to high radiation and stress. |

### 2. Water Requirements

A three-dimensional analysis of drought tolerance (survival), water use rate (volume), and hydraulic strategy (frequency).

#### A. Drought Tolerance (P50)

This directly predicts mortality risk during drought. P50 (`d_stem`) is the water potential (in MPa) at which the plant loses 50% of its hydraulic conductivity.

| P50 (`d_stem`) Range (MPa) | Drought Tolerance | Watering Frequency |
|---|---|---|
| `> -1.5` | Drought Intolerant | Very Frequently |
| `-1.5` to `-2.5` | Low Tolerance | Frequently |
| `-2.5` to `-4.0` | Moderate Tolerance | Regularly |
| `-4.0` to `-6.0` | High Tolerance | Infrequently |
| `< -6.0` | Extreme Tolerance | Very Rarely |

#### B. Water Use Rate (`gswmax`)

Maximum stomatal conductance (`gswmax`) determines the plant's peak water usage. This modifies the *volume* of water needed.

| `gswmax` Range (mol/m²/s) | Water Use Rate | Volume Modifier |
|---|---|---|
| `< 0.15` | Low | 0.7x standard |
| `0.15` - `0.25` | Moderate | 1.0x standard |
| `> 0.25` | High | 1.3x standard |

#### C. Irrigation Style (Hydraulic Safety Margin)

The Hydraulic Safety Margin (HSM = `psi_extract` - `d_stem`) determines *how* a plant responds to drying soil and dictates the best irrigation style.

| HSM (MPa) | Strategy | Behavior & Recommendation |
|---|---|---|
| `> 2.0` | **Isohydric (Cautious)** | Closes stomata early. May wilt but recovers well. **Prefers frequent, shallow watering.** |
| `1.0 - 2.0` | **Intermediate** | Balanced response. **Prefers moderate frequency and depth.** |
| `< 1.0` | **Anisohydric (Risky)** | Continues transpiring near its limits. Can collapse suddenly. **Needs infrequent, deep watering.** |

### 3. Soil Requirements

Root traits and leaf economics are combined to predict soil preferences.

#### A. Drainage (SRL)

Specific Root Length (`srl`) indicates root thickness and strategy. Thin roots (high SRL) are efficient explorers but are sensitive to waterlogging.

| `srl` Range (cm/g) | Drainage Requirement | Recommended Texture |
|---|---|---|
| `> 5000` | Excellent drainage essential | Sandy to sandy loam |
| `3000 - 5000` | Good drainage required | Sandy loam to loam |
| `< 3000` | Moderate drainage acceptable | Loam to clay loam |

#### B. Fertility

Fertility needs are inferred from the plant's overall growth strategy.

| Condition | Fertility Need |
|---|---|
| `(SLA < 10 AND Nleaf > 25) OR (SLA > 20 AND Nleaf > 30)` | **High** (Heavy feeder) |
| `SLA > 15 AND Nleaf < 20` | **Low** (Adapted to poor soils) |
| *Otherwise* | **Moderate** |

#### C. Structure & Depth

Rooting depth (`z95`) determines the required volume of uncompacted soil.

| `z95` Range (mm) | Structure Requirement |
|---|---|
| `> 2000` | Deep, uncompacted soil essential |
| `1000 - 2000` | Moderately deep soil preferred |
| `< 1000` | Can tolerate shallower soils |

### 4. Establishment & Garden Care

#### Establishment Needs

A plant's hydraulic strategy (HSM) is the best predictor of how difficult it will be to establish.

*   **Isohydric (HSM > 2.0):** Easy & Forgiving. Wilts visibly when thirsty, providing a clear watering cue.
*   **Anisohydric (HSM < 1.0):** Difficult & Unforgiving. Shows no warning signs before catastrophic failure. Requires vigilant soil moisture monitoring.

#### Mulching Benefit

Mulching is most beneficial for shallow-rooted plants (`z95 < 1000mm`) and high-water-use, isohydric plants (`gswmax > 0.25` and `HSM > 2.0`).

#### Pruning Response

Response to pruning is predicted by an "acquisitive score" based on `SLA`, `Nleaf`, and `wood_density`. Fast-growing, acquisitive plants with low-density wood recover vigorously, while conservative plants recover slowly and should only be pruned lightly.

### 5. Seasonal Care Routines (Phenology-Based)

Care requirements change dramatically throughout the year based on a plant's phenological strategy. The advisor generates season-specific instructions aligned with `medfate`'s phenology modeling.

#### Phenological Types & Annual Cycles

| Phenology Type | Winter | Spring | Summer | Fall |
|---|---|---|---|
| **Evergreen** | Minimal water, no fertilizer | Begin feeding with growth flush | Peak water & nutrient demand | Reduce feeding for hardening |
| **Winter-deciduous** | Dormant - ideal for pruning | Resume water/feed after leaf-out | Maximum activity | Prepare for dormancy |
| **Summer-deciduous** | ACTIVE GROWTH - water & feed | Prepare for dormancy | DORMANT - reduce water | Resume with cooling |

#### Key Timing by Phenology

| Operation | Evergreen | Winter-deciduous | Summer-deciduous |
|---|---|---|---|
| **Best Planting** | Early fall or spring | Dormant season (winter) | Fall as growth resumes |
| **Major Pruning** | Late winter to early spring | Late winter when dormant | Winter during active growth |
| **Fertilizer Start** | Early spring growth flush | After leaf expansion | Fall with growth resumption |
| **Fertilizer Stop** | Late summer/early fall | Midsummer for hardening | Late spring before dormancy |

**Special Note:** Anisohydric plants (HSM < 1.0) require extra vigilance during their active seasons - their watering notes are marked as "CRITICAL" to prevent sudden collapse.

### 6. Light Competition & Spacing

Based on `medfate`'s asymmetric light competition model, the advisor predicts competitive strategies and spacing needs.

#### Competitive Strategies

| Height Score | Growth Rate | Strategy | Description | Spacing Factor |
|---|---|---|---|---|
| High (>2/3) | Fast | **Dominant Competitor** | Quickly overtops neighbors | 1.5x |
| High (>2/3) | Slow-Moderate | **Structural Dominant** | Height advantage over time | 1.2x |
| Low (<1/3) | Any | **Understory Specialist** | Thrives beneath canopy | 0.5x |
| Moderate | Fast | **Gap Opportunist** | Quick growth in openings | 0.8x |
| Moderate | Slow | **Moderate Competitor** | Average competitive ability | 1.0x |

#### Spacing Calculations

- **Trees:** Base spacing = Height(m) × 0.5 × spacing factor
- **Shrubs:** Base spacing = Height(m) × 0.3 × spacing factor
- **Crown diameter** = Base spacing × 0.8 (trees) or 1.2 (shrubs)

#### Canopy Layering

Plants naturally stratify into layers based on traits:
- **Overstory:** Trees > 10m height
- **Midstory:** Trees 5-10m height  
- **Understory:** High SLA + Low Nleaf (shade specialists)
- **Shrub layer:** All shrubs regardless of height

### 7. Enhanced Shade Tolerance Analysis

Moving beyond simple leaf traits, the advisor calculates true shade tolerance using `medfate`'s carbon balance approach.

#### Carbon Balance in Shade

The core calculation: `Shade Carbon Balance = (Photosynthetic Capacity × 0.6 × 0.1) - (Leaf Respiration × 0.05)`

Where:
- Photosynthetic capacity ≈ Nleaf
- 0.6 = Shade photosynthetic efficiency  
- 0.1 = 10% light scenario
- 0.05 = Respiration rate factor

#### Shade Tolerance Categories

| Carbon Balance | Resilience | Minimum Light | Description |
|---|---|---|---|
| > 0.5 | **High** | 5-8% | Maintains positive balance in deep shade |
| 0 to 0.5 | **Moderate** | 8-15% | Survives but growth limited |
| -0.5 to 0 | **Low** | 15-30% | Requires excellent conditions |
| < -0.5 | **Very Low** | >30% | Cannot survive in shade |

#### Critical Insight: Fertility in Shade

High-Nleaf plants (>25) have high metabolic costs that become critical in shade:
- **Nleaf > 25:** "CRITICAL: Requires fertile soil in shade to support high metabolism"
- **Nleaf 15-25:** "Moderate fertility needed for shade survival"
- **Nleaf < 15:** "Can tolerate low fertility even in shade"

This explains why some traditionally "sun-loving" plants can survive in shade with rich soil, while some "shade plants" fail in deep shade with poor nutrition.

---

## Data Requirements & TRY Database Mapping

The advisor uses the following traits from the `PlantTraits` dataclass, with corresponding TRY database trait numbers for bulk processing.

### Essential Traits (Required)

| Parameter | Description | Units | TRY Trait # | TRY Name | Data Availability |
|---|---|---|---|---|---|
| `species_name` | Species identifier | - | - | Species name from TRY | Universal |
| `growth_form` | Plant growth form | "Tree"/"Shrub" | 42 | Plant growth form | 48,041 species ✓ |
| `leaf_type` | Leaf morphology | "Broad"/"Needle"/"Scale" | 43 | Leaf type | 29,515 species ✓ |
| `height` | Plant height | cm | 18 | Plant height | 268,607 species ✓✓ |
| `sla` | Specific leaf area | m²/kg | 3117 | Leaf area per leaf dry mass (SLA): undefined if petiole is in- or excluded | 206,176 species ✓✓ |
| `d_stem` | Stem P50 (xylem vulnerability) | MPa | 719 | Xylem hydraulic vulnerability (P20, P50, P88) | 921 species ⚠️ |
| `psi_extract` | Stomatal closure point | MPa | 3468 | Leaf water potential at turgor loss point (proxy) | 80 species ⚠️ |

**Data availability:** ✓✓ Excellent (>100k species), ✓ Good (10-100k), ⚠️ Limited (<10k)

#### Proxies and Estimation Methods for Essential Traits

**For missing hydraulic traits (d_stem/P50):**
```python
# Functional group defaults (Maherali et al. 2004)
p50_defaults = {
    'Angiosperm': -2.0,
    'Gymnosperm': -4.0,
    'Angiosperm_deciduous': -2.34,
    'Gymnosperm_evergreen': -3.46,
    'Broad': -2.5,
    'Needle': -4.5,
    'Shrub': -3.5
}
```

**Alternative hydraulic traits with better coverage:**
- Trait 3479: Xylem vulnerability curve (342 species) - may contain P50 values
- Trait 983: Leaf water potential (181 species) - can indicate stress thresholds
- Trait 3542: Leaf water potential midday (122 species) - operational water stress

**For missing stomatal closure point (psi_extract):**
```python
# medfate method: From turgor loss point with 10% stomatal conductance assumption
# This is medfate's primary estimation method
if turgor_loss_point is available:
    psi_extract = turgor_loss_point  # Direct use as proxy

# Alternative: From P50 (conservative)
else:
    psi_extract = d_stem * 0.5  # Conservative estimate

# Or from midday water potential (if available)
psi_extract = midday_water_potential * 0.7  # Plants typically close stomata before reaching midday minimum
```

**medfate default value:**
- `psi_extract`: -1.5 MPa (if no other data available)

### Beneficial Traits (With Defaults)

| Parameter | Description | Units | Default | TRY Trait # | TRY Name | Data Availability |
|---|---|---|---|---|---|---|
| `nleaf` | Leaf nitrogen content | mg/g | 20.088 | 14 | Leaf nitrogen content per leaf dry mass | 22,316 species ✓ |
| `gswmax` | Max stomatal conductance | mol/m²/s | 0.200 | 45 | Stomata conductance per leaf area | 48,056 species ✓ |
| `srl` | Specific root length | cm/g | 3870 | 614 | Fine root length per fine root dry mass | 1,308 species ⚠️ |
| `z95` | 95% rooting depth | mm | Hmax*2.0 | 6 | Root rooting depth | 4,032 species ⚠️ |
| `wood_density` | Wood specific gravity | g/cm³ | 0.652 | 4 | Stem specific density (SSD) or wood density | 12,460 species ✓ |
| `pi0_stem` | Osmotic potential at full turgor | MPa | See formula | 188 | Leaf osmotic potential at full turgor | 204 species ⚠️ |
| `n_sapwood` | Sapwood nitrogen content | mg/g | 3.98 | 3453 | Wood (sapwood) nitrogen content per dry mass | Limited ⚠️ |
| `n_fineroot` | Fine root nitrogen content | mg/g | 12.2 | 741 | Fine root nitrogen content per dry mass | Limited ⚠️ |
| `leaf_phenology` | Deciduous strategy | Category | "Evergreen" | 37 | Plant phenology: leaf persistence | Good ✓ |

#### Proxies and Estimation Methods for Beneficial Traits

**For missing osmotic traits (from wood density):**
```python
# Christoffersen et al. 2016
pi0_stem = 0.52 - 4.16 * wood_density
eps_stem = sqrt(1.02 * exp(8.5 * wood_density) - 2.89)
```

**For missing rooting depth (medfate method from plant size):**
```python
# medfate uses height-based scaling
z50 = Hmax * 0.5  # 50% rooting depth (Hmax = species maximum height)
z95 = Hmax * 2.0  # 95% rooting depth

# If only current height available:
z50 = height * 0.5
z95 = height * 2.0
```

**For missing SRL:**
Use family/genus averages or growth form defaults:
- Trees: 2500-3500 cm/g (coarse roots)
- Shrubs: 3500-5000 cm/g (intermediate)
- Herbs: 5000-10000 cm/g (fine roots)

### Additional TRY Traits for Enhanced Analysis

| TRY Trait # | Name | Use in Advisor | Data Availability |
|---|---|---|---|
| 773 | Crown height | Calculate crown_ratio with trait 18 | Good |
| 21 | Stem diameter | DBH for trees | Good |
| 480 | Crown cover | Cover percentage for shrubs | Limited |
| 10 | Leaf absorptance | Refine k_PAR if available | Limited |
| 489 | Crown radiation extinction | Alternative k_PAR source | Limited |
| 741 | Fine root nitrogen content | Refine root respiration | Limited |
| 134 | Water use efficiency | Direct WUE measurement (default: 7.9 g C/mm H₂O) | Limited |
| 190 | Leaf bulk modulus of elasticity | Calculate eps_stem | Limited |
| 2029 | Used incorrectly - this is fraction data | Not z95 itself | N/A |

### Summary of Trait Availability & Estimation Strategy

**Well-covered traits (usually available):**
- Height, SLA, growth form, leaf type → Direct from TRY
- Leaf nitrogen, stomatal conductance → Often available
- Wood density → Frequently available, enables many proxies

**Poorly-covered traits (usually need estimation):**
- **P50 (d_stem):** Use functional group defaults or literature
- **psi_extract:** Estimate from turgor loss point or P50
- **Root traits:** Use allometric relationships with height
- **Osmotic traits:** Calculate from wood density

**Estimation priority:**
1. Try to obtain wood density - it unlocks multiple hydraulic proxies
2. Use functional group P50 values if species-specific unavailable
3. Apply allometric scaling for root traits
4. Default to growth form averages as last resort

### medfate-Specific Default Values

Based on the medfate forest simulator, these defaults have been validated for Mediterranean ecosystems:

**Critical Parameters:**
- `c_extract`: 1.3 (shape parameter for water stress response)
- `c_stem`: 3.0 (shape parameter for vulnerability curve)
- `wue_max`: 7.9 g C/mm H₂O (intrinsic water use efficiency)
- `psi_extract`: -1.5 MPa (if no TLP data available)

**Nitrogen Content (mg/g):**
- `n_leaf`: 20.088 (family average → global default)
- `n_sapwood`: 3.98 (much lower than leaves)
- `n_fineroot`: 12.2 (intermediate)

**Crown & Light:**
- `crown_ratio`: 0.5 (Trees), 0.8 (Shrubs)
- `k_par`: 0.55 (Broad), 0.50 (Needle/Scale)

**Key medfate Insights:**
1. Wood density is the master trait - it predicts osmotic adjustment capacity
2. Turgor loss point can directly substitute for psi_extract
3. Height-based rooting depth scaling is robust across species
4. Default nitrogen values are family-specific when possible

---

This framework enables systematic generation of science-based gardening advice for thousands of species using standardized trait data from TRY, incorporating the validated approximations from the medfate forest simulator.
