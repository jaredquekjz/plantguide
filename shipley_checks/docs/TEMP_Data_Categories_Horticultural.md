# Encyclopedia Page: Holistic Horticultural Advice Generation

**Purpose**: Define how to generate readable, actionable horticultural advice for individual plant encyclopedia pages by combining multiple data categories.

**Data Source**: `stage3/bill_with_csr_ecoservices_koppen_11711.csv` (11,711 European plants, 782 columns)

**Architecture**: Static encyclopedia pages with LLM/rule-based advice generation from 10 data categories

---

## Advice Generation Philosophy

### Core Principle: Holistic Data Synthesis

Rather than presenting raw data (e.g., "EIVE-M = 5.2, CSR: C=0.65, S=0.20, R=0.15"), generate **integrated advice** that combines multiple signals:

> "This competitive, fast-growing plant thrives in moist, fertile soils with regular watering. Suitable for productive garden beds but may outcompete slower neighbors. Prune annually to control vigor."

**How this advice was generated**:
- EIVE-M (5.2) = moist soil preference
- EIVE-N (7.5) = high nutrient needs
- CSR (C-dominant) = competitive, fast growth
- Height (1.8m) + Growth form (shrub) = pruning needs

### Three Advice Generation Methods

1. **Rule-Based** (deterministic, fast): Simple if-then rules for basic categories
2. **Template-Based** (semi-structured): Fill templates with plant-specific data
3. **LLM-Based** (flexible, natural): Generate natural language from structured data context

---

## Encyclopedia Page Sections

### 1. Plant Identity Card

**Data sources**: Taxonomic + Functional Traits + Height

**Output format**:
```
Lavandula angustifolia (English Lavender)
Family: Lamiaceae | Genus: Lavandula

Small evergreen shrub (0.3-0.6m)
Needleleaved foliage, woody stems
Drought-adapted (CAM photosynthesis)
```

**Generation method**: Template-based (deterministic)

**Template**:
```
{scientific_name} ({common_name})
Family: {family} | Genus: {genus}

{size_descriptor} {phenology_descriptor} {growth_form} ({height_min}-{height_max}m)
{leaf_type} foliage, {woodiness} stems
{special_adaptations}
```

**Rules**:
- `size_descriptor`: height <0.5m="Dwarf", 0.5-1.5m="Small", 1.5-5m="Medium", >5m="Large"
- `phenology_descriptor`: leaf_phenology="deciduous"/"evergreen"
- `special_adaptations`: if photosynthesis_pathway="CAM" → "Drought-adapted (CAM photosynthesis)"

---

### 2. Growing Requirements (Site Selection)

**Data sources**: EIVE (L, T, M, N, R) + CSR + Köppen Tiers

**Output format**:
```
☀️ Light: Full sun (EIVE-L: 8/9)
   → Plant in open positions, south-facing sites

💧 Water: Moderate moisture (EIVE-M: 5/9)
   → Weekly watering in summer, drought-tolerant once established
   → Avoid waterlogged soils

🌡️ Climate: Mediterranean & Humid Temperate zones
   → USDA Zones 5-9 | RHS Hardiness H5
   → Suitable for UK, Southern Europe, California coastal

🌱 Fertility: Moderate nutrients (EIVE-N: 5/9)
   → Light annual feeding sufficient
   → Avoid over-fertilizing (reduces essential oil content)

⚗️ pH: Neutral to alkaline (EIVE-R: 7/9)
   → Add lime to acid soils | Ideal pH 6.5-8.0
```

**Generation method**: LLM-based with structured context

**LLM Prompt Template**:
```
Generate user-friendly growing requirements for this plant:

EIVE Data:
- Light (L): {eive_l}/9 scale (1=deep shade, 9=full sun)
- Moisture (M): {eive_m}/9 scale (1=very dry, 9=wet/aquatic)
- Temperature (T): {eive_t}/9 scale (1=arctic, 9=subtropical)
- Nutrients (N): {eive_n}/9 scale (1=infertile, 9=highly fertile)
- pH (R): {eive_r}/9 scale (1=acid, 9=alkaline)

Plant Strategy:
- CSR: C={c_score}, S={s_score}, R={r_score}
- Dominant strategy: {dominant_strategy}

Climate Zones:
- Köppen tiers: {tier_list}
- Climate breadth: {n_tier_memberships}/6 tiers

For each requirement (Light, Water, Climate, Fertility, pH), provide:
1. User-friendly descriptor (e.g., "Full sun" not "EIVE-L: 8")
2. Practical planting advice (where to plant, how often to water)
3. Warning if extreme requirements (e.g., "Avoid waterlogged soils")

Use icons: ☀️ Light, 💧 Water, 🌡️ Climate, 🌱 Fertility, ⚗️ pH
Be concise (2-3 lines per requirement). Use imperative voice.
```

**Key Holistic Combinations**:
- High EIVE-M + Low CSR-S → "Requires consistent moisture, not drought-tolerant"
- High CSR-C + High EIVE-N → "Hungry feeder, fertilize monthly"
- Multi-tier Köppen + High EIVE-T → "Highly adaptable to different climates"

---

### 3. Maintenance Profile (Labor Requirements)

**Data sources**: CSR + Growth Form + Height + Leaf Phenology + Decomposition Rate

**Output format**:
```
Maintenance Level: LOW

🌿 Growth Rate: Slow (S-dominant strategy)
   → Minimal pruning needed (every 2-3 years)
   → Compact habit, stays in bounds

🍂 Seasonal Tasks:
   → Spring: Light shaping after frost risk
   → Autumn: Minimal leaf cleanup (evergreen)

♻️ Waste Management:
   → Slow-decomposing foliage (CSR-S)
   → Add to compost in thin layers
   → Good for long-lasting mulch

⏰ Time Commitment: ~15 minutes per year
```

**Generation method**: Rule-based + LLM for natural language

**Rules**:
- Maintenance level: `if CSR-C > 0.6 → HIGH, elif CSR-S > 0.6 → LOW, else MEDIUM`
- Growth rate: `CSR-C > 0.6 → Fast, CSR-S > 0.6 → Slow, else Moderate`
- Pruning frequency: `if growth_form in ['tree', 'shrub'] AND C > 0.6 → 'annually', elif S > 0.6 → 'every 2-3 years'`
- Leaf cleanup: `if phenology='deciduous' → 'Autumn: Rake fallen leaves', else 'Minimal leaf cleanup'`
- Decomposition: `if decomposition_rating > 6 → 'Fast-decomposing', elif < 4 → 'Slow-decomposing'`

**LLM Context for Natural Language**:
```
Generate maintenance profile:
- CSR: C={c}, S={s}, R={r} → {dominant_strategy}
- Growth form: {growth_form}, Height: {height}m
- Phenology: {leaf_phenology}
- Decomposition rate: {decomposition_rating}/10

Rules applied:
- Maintenance level: {maintenance_level}
- Growth rate: {growth_rate}
- Pruning frequency: {pruning_freq}
- Leaf cleanup: {leaf_cleanup}

Write 4 sections: Growth Rate, Seasonal Tasks, Waste Management, Time Commitment.
Be specific and actionable. Use emoji icons.
```

---

### 4. Ecosystem Services (Functional Benefits)

**Data sources**: 10 Ecosystem Service Ratings + Nitrogen Fixation + Pollinator Count

**Output format**:
```
Environmental Benefits:

🌿 Carbon Sequestration: ⭐⭐⭐⭐ High
   Stores 15kg CO₂/year in biomass (medium shrub, woody stems)

🌾 Soil Improvement: ⭐⭐ Low
   Not a nitrogen fixer | Moderate organic matter contribution

🌊 Erosion Control: ⭐⭐⭐⭐⭐ Excellent
   Dense fibrous roots stabilize slopes and banks
   → Ideal for erosion-prone sites, retaining walls

🐝 Pollinator Support: ⭐⭐⭐⭐ High
   Attracts 12 pollinator species including native bees
   → Peak flowering: June-August
   → Plant in groups for maximum pollinator benefit
```

**Generation method**: Hybrid (rules for ratings, LLM for descriptions)

**Rating Rules**:
- Stars: `0-2 → ⭐, 2-4 → ⭐⭐, 4-6 → ⭐⭐⭐, 6-8 → ⭐⭐⭐⭐, 8-10 → ⭐⭐⭐⭐⭐`
- Descriptor: `8-10 → Excellent, 6-8 → High, 4-6 → Medium, 2-4 → Low, 0-2 → Minimal`

**LLM Context for Descriptions**:
```
Generate benefit descriptions for:
- Carbon (biomass): rating={carbon_biomass_rating}/10, height={height}m, woody={woodiness}
- Nitrogen fixation: rating={nf_rating}/10, has_try={has_try_nf_data}
- Erosion control: rating={erosion_rating}/10, growth_form={growth_form}
- Pollinators: rating={npp_rating}/10, pollinator_count={pollinator_count}, flower_visitor_count={fv_count}

For each benefit:
1. Quantify if possible (e.g., "Stores Xkg CO₂/year")
2. Explain mechanism (e.g., "Dense fibrous roots")
3. Give planting advice (e.g., "Plant in groups")

Keep 1-2 sentences per benefit. Use → for planting tips.
```

**Holistic Combinations**:
- High carbon_biomass + High height + Woody → "Excellent carbon storage tree"
- High erosion_protection + Low CSR-R → "Permanent slope stabilization"
- High pollinator_count + High flower_visitor_count → "Wildlife magnet"

---

### 5. Biological Interactions Summary

**Data sources**: Organism Profiles + Fungal Guilds + Predator/Antagonist Networks

**Output format**:
```
Natural Relationships:

🐝 Pollinators (12 species):
   → Honeybees, bumblebees, mining bees
   → Self-fertile but benefits from bee activity

🐛 Pest Pressure: MODERATE with good natural control
   Aphids (3 species) - Controlled by ladybirds, lacewings
   Whitefly (2 species) - Controlled by parasitic wasps
   → Avoid chemical sprays to preserve beneficial insects

🦠 Disease Risk: LOW
   Susceptible to root rot in waterlogged soils
   Powdery mildew (2 fungal species) - Antagonized by Trichoderma
   → Ensure good drainage and air circulation

🍄 Soil Fungi: Beneficial associations
   Mycorrhizae: Arbuscular (AMF) - enhances drought tolerance
   Endophytes: 8 species - boost disease resistance
   → Avoid fungicides; inoculate with mycorrhizal mix at planting
```

**Generation method**: LLM-based with network data summary

**LLM Prompt Template**:
```
Generate biological interactions summary:

Pollinators:
- Total: {pollinator_count} species
- Top species: {top_3_pollinators}

Pests (Herbivores):
- Total: {herbivore_count} species
- Top pests: {top_3_herbivores}
- Predators available: {predator_count} species for {pests_with_predators} pests
- Entomopathogenic fungi: {entomopath_fungi_count} fungal parasites

Diseases (Pathogens):
- Total: {pathogen_count} species
- Top diseases: {top_3_pathogens}
- Antagonists available: {antagonist_count} species for {pathogens_with_antagonists} pathogens

Beneficial Fungi:
- Mycorrhizae: {mycorrhiza_type} ({amf_count} AMF, {emf_count} EMF)
- Endophytes: {endophyte_count} species
- Biocontrol fungi: {biocontrol_count} species

For each section:
1. Pest Pressure: Calculate overall risk level (LOW/MODERATE/HIGH based on pest:predator ratio)
2. Disease Risk: Calculate overall risk level (LOW/MODERATE/HIGH based on pathogen:antagonist ratio)
3. List top 3 pests/diseases with their natural enemies
4. Provide specific horticultural advice (e.g., "Avoid chemical sprays", "Ensure drainage")

Emphasize biological control and working with natural systems.
Use icons: 🐝 🐛 🦠 🍄
```

**Key Rule-Based Calculations**:
```python
# Pest pressure assessment
pest_control_ratio = predator_diversity / herbivore_count
if pest_control_ratio > 0.5: pest_risk = "LOW with excellent natural control"
elif pest_control_ratio > 0.2: pest_risk = "MODERATE with good natural control"
else: pest_risk = "HIGH - consider companion planting"

# Disease pressure assessment
disease_control_ratio = antagonist_diversity / pathogen_count
if disease_control_ratio > 0.3: disease_risk = "LOW"
elif disease_control_ratio > 0.1: disease_risk = "MODERATE"
else: disease_risk = "HIGH - preventive measures recommended"
```

**Important**: Show only TOP 3-5 species per category. Full network data reserved for GuildBuilder.

---

### 6. Climate Resilience & Adaptation

**Data sources**: Köppen Tier Memberships + Climate Extremes + EIVE-T

**Output format**:
```
Climate Profile:

🌍 Native Climate Zones:
   ✓ Mediterranean (Csa, Csb) - 45% of occurrences
   ✓ Humid Temperate (Cfb) - 35% of occurrences
   ✓ Arid (BSk) - 20% of occurrences

🌡️ Temperature Tolerance:
   Cold: Hardy to -15°C (USDA Zone 5-6)
   Heat: Tolerates 40°C+ summer temperatures
   → Frost dates: {frost_free_days} frost-free days needed
   → Summer days (>25°C): Thrives with {summer_days} hot days

💧 Drought Tolerance: HIGH
   Consecutive dry days: Tolerates up to {CDD_q95} days without rain
   → Xeric landscaping candidate
   → Reduce watering after establishment (year 2+)

🌦️ Climate Change Resilience: ⭐⭐⭐⭐ High (3/6 climate tiers)
   Adapted to warming scenarios (Mediterranean + Arid tiers)
   → Future-proof choice for temperate regions
   → Consider for urban heat island plantings
```

**Generation method**: Rule-based thresholds + LLM for natural language

**Rules**:
```python
# Cold hardiness (from EIVE-T and TNn_q05)
if TNn_q05 < -15: usda_zone = "3-4 (very hardy)"
elif TNn_q05 < -10: usda_zone = "5-6 (hardy)"
elif TNn_q05 < -5: usda_zone = "7-8 (moderately hardy)"
else: usda_zone = "9-11 (tender)"

# Heat tolerance (from TXx_q95 and SU_q95)
if TXx_q95 > 40 and SU_q95 > 90: heat_tolerance = "Excellent - thrives in extreme heat"
elif TXx_q95 > 35 and SU_q95 > 60: heat_tolerance = "Good - handles hot summers"
else: heat_tolerance = "Moderate - prefers cooler conditions"

# Drought tolerance (from CDD_q95 and EIVE-M)
if CDD_q95 > 60 and eive_m < 4: drought_tolerance = "HIGH - xeric candidate"
elif CDD_q95 > 30 and eive_m < 6: drought_tolerance = "MODERATE"
else: drought_tolerance = "LOW - needs consistent moisture"

# Climate resilience score
climate_resilience = n_tier_memberships  # Out of 6
if climate_resilience >= 4: resilience_rating = "⭐⭐⭐⭐⭐ Excellent"
elif climate_resilience == 3: resilience_rating = "⭐⭐⭐⭐ High"
elif climate_resilience == 2: resilience_rating = "⭐⭐⭐ Moderate"
else: resilience_rating = "⭐⭐ Specialist"
```

**LLM Context**:
```
Generate climate resilience profile:

Köppen Distribution:
{for tier in tiers_present:}
   - {tier_name}: {tier_percent}% of occurrences

Temperature Extremes:
- Coldest min: {TNn_q05}°C → USDA Zone {usda_zone}
- Hottest max: {TXx_q95}°C
- Summer days (>25°C): {SU_q50} days/year (median)
- Frost days: {FD_q50} days/year (median)

Drought Metrics:
- Max consecutive dry days: {CDD_q95}
- EIVE Moisture: {eive_m}/9

Climate Breadth:
- Tier memberships: {n_tier_memberships}/6
- Resilience assessment: {resilience_rating}

Write 4 sections: Native Climate Zones, Temperature Tolerance, Drought Tolerance, Climate Change Resilience.
Include specific numbers and actionable planting advice.
Highlight future-proofing potential if high tier diversity.
```

---

### 7. Soil Requirements & Amendments

**Data sources**: Soil Properties (pH, Clay, Sand, SOC, CEC, Nitrogen) + EIVE-R + CSR

**Output format**:
```
Soil Preferences:

⚗️ pH Range: 6.0-8.0 (neutral to alkaline)
   Current soil: Test pH before planting
   Amendments:
   → Acid soil (<6.0): Add 200g lime per m²
   → Alkaline soil (>8.0): No amendment needed

🏜️ Texture: Well-drained loams to sandy soils
   Ideal: 15-30% clay, 40-60% sand
   → Heavy clay: Add 10L grit + 5L compost per m²
   → Pure sand: Add 10L compost to improve water retention

🌱 Fertility: Moderate to high (EIVE-N: 6/9)
   Organic matter: 2-4% SOC optimal
   Nitrogen: Annual feeding required (competitive growth strategy)
   → Spring: Apply 50g general fertilizer per m²
   → Avoid over-feeding (promotes leaf over flower)

💧 Drainage: Critical - avoid waterlogging
   Compaction tolerance: LOW
   → Raised beds recommended for heavy soils
   → Add 30% grit for container growing
```

**Generation method**: Rule-based thresholds + LLM for amendment advice

**Rules**:
```python
# pH recommendations (from phh2o quantiles and EIVE-R)
ph_min = phh2o_0_5cm_q05
ph_max = phh2o_0_5cm_q95
ph_optimal = (ph_min + ph_max) / 2

if eive_r < 3: ph_advice = "Acid-loving (pH 4.5-5.5): Add sulfur to alkaline soils"
elif eive_r > 7: ph_advice = "Alkaline-tolerant (pH 7.0-8.5): Add lime to acid soils"
else: ph_advice = "Neutral (pH 6.0-7.0): Most garden soils suitable"

# Texture (from clay/sand percentiles)
clay_pref = clay_0_5cm_q50
sand_pref = sand_0_5cm_q50

if clay_pref < 15 and sand_pref > 60: texture = "Sandy, well-drained"
elif clay_pref > 35: texture = "Clay-tolerant, heavier soils"
else: texture = "Loamy, well-drained"

# Fertility (from EIVE-N and nitrogen quantiles)
if eive_n > 7: fertility = "High - hungry feeder, fertilize regularly"
elif eive_n < 3: fertility = "Low - thrives in poor soils, avoid feeding"
else: fertility = "Moderate - light annual feeding"

# Organic matter (from SOC quantiles)
soc_pref = soc_0_5cm_q50 / 10  # Convert to %
if soc_pref > 4: om_advice = "High organic matter preferred - add compost annually"
elif soc_pref < 2: om_advice = "Low organic matter preferred - avoid rich soils"
else: om_advice = "Moderate organic matter (2-4%) - mulch with compost"

# Compaction tolerance (from bdod quantiles and CSR)
if csr_s > 0.6 and bdod_q50 > 1.4: compaction = "HIGH - tolerates compacted soils"
elif csr_r > 0.6: compaction = "LOW - needs loose, friable soil"
else: compaction = "MODERATE"
```

**LLM Context**:
```
Generate soil requirements and amendment advice:

Soil Chemistry:
- pH range: {ph_min}-{ph_max} (median {ph_q50})
- EIVE pH: {eive_r}/9 (1=acid, 9=alkaline)
- CEC: {cec_q50} (nutrient holding capacity)
- Nitrogen: {nitrogen_q50} g/kg

Soil Physics:
- Clay: {clay_q50}%
- Sand: {sand_q50}%
- Organic carbon: {soc_q50}%
- Bulk density: {bdod_q50} g/cm³

Plant Strategy:
- CSR: C={c}, S={s}, R={r}
- EIVE Nutrients: {eive_n}/9

Write 4 sections: pH Range, Texture, Fertility, Drainage.
For each, provide:
1. Ideal conditions
2. Tolerance ranges
3. Specific amendments with quantities (e.g., "Add 200g lime per m²")
4. Container growing advice if relevant

Be practical and specific. Avoid jargon.
```

---

### 8. Planting & Propagation Guidance

**Data sources**: Seed Mass + Growth Form + Life Form + CSR-R + GSL (Growing Season Length)

**Output format**:
```
Establishment:

🌱 Propagation Method: SEED (small seed mass)
   Seed size: 1.2mg - handle carefully
   Germination: Sow on surface, do not cover (light-required)
   → Spring sowing: After last frost
   → Germination time: 14-21 days at 15-20°C

🌿 Alternative: Softwood cuttings (summer)
   Take 10cm tip cuttings in June-July
   Root in perlite mix with bottom heat

📅 Planting Season:
   Best: Spring (April-May) for summer establishment
   Avoid: Autumn planting in cold zones (frost heave risk)
   Growing season: {gsl_q50} days - needs full season to establish

💧 Establishment Care:
   Year 1: Weekly watering, keep weed-free
   Year 2+: Drought-tolerant, reduce watering
   → Mulch 5cm deep to suppress weeds
   → Expect flowering in year 2

📏 Spacing: 30-45cm (mature spread)
```

**Generation method**: Rule-based propagation method + LLM for specific guidance

**Rules**:
```python
# Propagation method (from seed_mass and life_form)
if seed_mass < 1:
    propagation = "SEED (tiny, surface sow)"
elif seed_mass < 100:
    propagation = "SEED (standard, cover lightly)"
else:
    propagation = "SEED (large, bury 2× seed diameter)"

if woodiness == "woody" and growth_form in ["shrub", "tree"]:
    propagation += " or CUTTINGS (softwood/hardwood)"

# Planting season (from GSL and frost tolerance)
if gsl_q50 < 150:
    season = "Spring only (short growing season)"
elif gsl_q50 < 250:
    season = "Spring or autumn (moderate season)"
else:
    season = "Spring, summer, or autumn (long season)"

# Establishment time (from CSR-R)
if csr_r > 0.6:
    establishment = "Fast - flowers year 1, short-lived"
elif csr_c > 0.6:
    establishment = "Moderate - establishes year 1, vigorous year 2+"
else:  # S-dominant
    establishment = "Slow - takes 2-3 years to establish"
```

**LLM Context**:
```
Generate planting guidance:

Seed Traits:
- Seed mass: {seed_mass} mg
- Life form: {life_form_simple}
- Growth form: {growth_form}
- Woodiness: {woodiness}

Phenology:
- Growing season length: {gsl_q50} days (median)
- Frost days: {fd_q50} days/year

Strategy:
- CSR: C={c}, S={s}, R={r}
- R-dominant plants are fast, short-lived
- S-dominant plants are slow, long-lived

Write 5 sections: Propagation Method, Alternative Methods, Planting Season, Establishment Care, Spacing.
Include specific numbers (seed size, germination time, spacing).
Give year-by-year care guide (Year 1, Year 2+).
```

---

### 9. Design & Aesthetics

**Data sources**: Height + Growth Form + Leaf Type + Phenology + Woodiness + EIVE-L

**Output format**:
```
Garden Design:

🎨 Visual Character:
   Form: Compact mounded shrub
   Height: 0.3-0.6m | Spread: 0.4-0.8m
   Texture: Fine (needleleaved foliage)
   Color: Silver-grey foliage, purple flower spikes

📅 Seasonal Interest:
   Spring: New silver growth
   Summer: Peak flowering (June-August)
   Autumn: Seed heads persist
   Winter: Evergreen structure (architectural value)
   → Year-round interest: ⭐⭐⭐⭐

🌳 Planting Position:
   Light: Full sun (front of border)
   Vertical layer: Ground cover to low shrub
   → Edge plantings, path borders
   → Rock gardens, gravel gardens

🏡 Design Styles:
   ✓ Mediterranean garden (drought-adapted)
   ✓ Cottage garden (informal, pollinator-friendly)
   ✓ Sensory garden (aromatic foliage)
   ✓ Low-maintenance / Xeriscape

🎯 Plant 3-5 in drifts for maximum impact
```

**Generation method**: LLM-based with structured aesthetic rules

**Rules**:
```python
# Vertical layer (from height and growth_form)
if height < 0.3: layer = "Ground cover"
elif height < 1.0: layer = "Low shrub / Herbaceous"
elif height < 3.0: layer = "Medium shrub"
elif height < 8.0: layer = "Small tree / Large shrub"
else: layer = "Canopy tree"

# Light position (from EIVE-L)
if eive_l > 7: light_position = "Full sun (front of border)"
elif eive_l > 5: light_position = "Sun to partial shade (mid-border)"
else: light_position = "Shade (back of border, under canopy)"

# Texture (from leaf_type and LA)
if leaf_type == "needleleaved" or LA < 10: texture = "Fine"
elif LA < 100: texture = "Medium"
else: texture = "Bold"

# Seasonal interest (from phenology)
if phenology == "evergreen":
    year_round = "⭐⭐⭐⭐⭐ Excellent"
    winter_interest = "Evergreen structure"
elif phenology == "deciduous":
    year_round = "⭐⭐⭐ Good"
    winter_interest = "Architectural stems/bark"
```

**LLM Context**:
```
Generate garden design guidance:

Physical Traits:
- Height: {height}m (range {height_q05}-{height_q95})
- Growth form: {growth_form}
- Leaf type: {leaf_type}
- Phenology: {leaf_phenology}
- Woodiness: {woodiness}

Site Preferences:
- Light (EIVE-L): {eive_l}/9
- Vertical layer: {layer}

Plant Strategy:
- CSR: {dominant_strategy}

Köppen Tiers:
{tier_list}

Write 5 sections: Visual Character, Seasonal Interest, Planting Position, Design Styles, Planting Advice.
Be inspirational and visual. Suggest specific design styles (cottage, Mediterranean, etc.).
Give practical layout advice (front/mid/back border, spacing, grouping).
```

**Holistic Combinations**:
- Mediterranean tier + Drought-tolerant + Aromatic → "Xeriscape / Mediterranean garden"
- Evergreen + Low maintenance → "Low-effort structural planting"
- High pollinator support → "Wildlife / cottage garden"

---

### 10. Warnings & Special Considerations

**Data sources**: All categories (identify edge cases, extreme values, special care needs)

**Output format**:
```
⚠️ Important Considerations:

🌊 Drainage Critical
   This plant is highly susceptible to root rot in waterlogged soils.
   → Ensure excellent drainage or plant on slopes
   → Raised beds recommended for heavy clay
   → Avoid low-lying frost pockets

🐝 Pollinator Dependence
   Requires bee activity for good fruit/seed set (not fully self-fertile).
   → Plant in groups of 3+ for cross-pollination
   → Flowering period: Ensure other plants flowering simultaneously

❄️ Frost Sensitivity
   Young growth damaged by late spring frosts (<-5°C).
   → Delay planting until after last frost date
   → Protect with fleece if late frost forecast
   → Site away from frost pockets

🍂 Competitive Growth
   Fast-growing with vigorous root system (C-dominant strategy).
   → May outcompete slower neighbors
   → Annual root pruning recommended near paths
   → Avoid planting near foundations (invasive roots)
```

**Generation method**: Rule-based triggers + LLM for explanation

**Trigger Rules**:
```python
warnings = []

# Drainage issues (from EIVE-M and pathogen risk)
if eive_m < 3 and pathogen_count > 20:
    warnings.append({
        'icon': '🌊',
        'title': 'Drainage Critical',
        'trigger': 'Low moisture tolerance + high pathogen load',
        'advice': 'Root rot risk in waterlogged soils'
    })

# Pollination needs
if pollinator_count > 10 and fruit_set_requirement == "insect":
    warnings.append({
        'icon': '🐝',
        'title': 'Pollinator Dependence',
        'trigger': 'High pollinator diversity requirement',
        'advice': 'Plant in groups for cross-pollination'
    })

# Frost sensitivity (from TNn_q05 and phenology)
if TNn_q05 > -5 and phenology == "deciduous":
    warnings.append({
        'icon': '❄️',
        'title': 'Frost Sensitivity',
        'trigger': 'Limited cold hardiness',
        'advice': 'Delay planting until frost risk passes'
    })

# Competitive/invasive (from CSR-C and root spread)
if csr_c > 0.7 and height > 2:
    warnings.append({
        'icon': '🍂',
        'title': 'Competitive Growth',
        'trigger': 'Fast growth, vigorous root system',
        'advice': 'May outcompete neighbors, needs management'
    })

# Pest-prone (from herbivore:predator ratio)
if herbivore_count > 30 and pest_control_ratio < 0.2:
    warnings.append({
        'icon': '🐛',
        'title': 'Pest Susceptibility',
        'trigger': 'High pest pressure, limited natural control',
        'advice': 'Monitor regularly, companion plant for biocontrol'
    })

# Disease-prone (from pathogen:antagonist ratio)
if pathogen_count > 50 and disease_control_ratio < 0.1:
    warnings.append({
        'icon': '🦠',
        'title': 'Disease Susceptibility',
        'trigger': 'High pathogen load, limited antagonists',
        'advice': 'Ensure air circulation, avoid overhead watering'
    })
```

**LLM Context for Each Warning**:
```
Generate warning section:
- Title: {warning_title}
- Trigger: {trigger_reason}
- Advice: {base_advice}

Plant data:
{relevant_data_for_this_warning}

Expand the advice into:
1. Specific symptoms or risks
2. Preventive measures (with quantities/timing)
3. Site selection advice
4. Ongoing management needs

Be clear and practical. Use imperative voice. Max 3-4 lines.
```

---

## Holistic Advice Combination Patterns

### Pattern 1: Site Matching Algorithm

**Input**: EIVE (L, T, M, N, R) + Köppen Tiers + Climate Extremes

**Output**: "Ideal site descriptor"

**Example**:
- EIVE: L=8, M=3, N=5, R=7 + Mediterranean tier + High CDD
- → "Full sun, well-drained neutral-alkaline soil, drought-tolerant once established. Ideal for Mediterranean-climate gardens, gravel gardens, and xeriscape plantings."

### Pattern 2: Maintenance Prediction

**Input**: CSR + Growth Form + Phenology + Decomposition

**Output**: "Maintenance level + annual time commitment"

**Example**:
- CSR: C=0.7, S=0.2, R=0.1 + Shrub + Deciduous
- → "HIGH maintenance: Annual pruning required (1-2 hours), weekly watering in summer, autumn leaf cleanup (30 mins). Competitive growth needs control. Total: ~10 hours/year."

### Pattern 3: Biological Control Potential

**Input**: Herbivore Count + Predator Diversity + Pathogen Count + Antagonist Diversity

**Output**: "Pest/disease risk + natural control feasibility"

**Example**:
- Herbivores: 15, Predators: 8 (ratio 0.53) + Pathogens: 12, Antagonists: 4 (ratio 0.33)
- → "MODERATE pest pressure with GOOD natural control. LOW disease risk. Suitable for low-spray gardening. Encourage beneficial insects by avoiding broad-spectrum pesticides."

### Pattern 4: Climate Resilience Scoring

**Input**: Köppen Tier Diversity + Climate Extreme Tolerance + CSR-S

**Output**: "Adaptability rating + future-proofing assessment"

**Example**:
- Tiers: 4/6 + High CDD tolerance + High SU tolerance + S=0.6
- → "EXCELLENT climate resilience (4/6 climate tiers). Stress-tolerant strategy makes it adaptable to variable conditions. Future-proof choice for warming temperate climates."

### Pattern 5: Ecosystem Service Valuation

**Input**: 10 Ecosystem Service Ratings + Height + Growth Form

**Output**: "Top 3 benefits + planting recommendations"

**Example**:
- Carbon: 8.5, Erosion: 9.0, NPP: 7.5 + Height: 5m + Tree
- → "Top benefits: 1) Erosion control (excellent), 2) Carbon storage (high), 3) Biomass production (high). Ideal for slope stabilization, carbon sequestration projects, and windbreaks."

---

## Implementation Architecture

### Recommended Approach: R Rules Engine (90%) + Optional LLM Polish (10%)

**Rationale**: With 782 structured data columns, most advice can be deterministically generated using lookup tables and threshold rules. LLM is optional enhancement, not dependency.

---

## Phase 1: R Rules-Based Engine (Core Implementation)

**Coverage**: Sections 1-8, 10 (90% of encyclopedia content)
**Technology**: Pure R with text templates and lookup tables
**Cost**: $0 (no API calls)
**Speed**: <1 second per plant page

### Architecture

```
Plant Data CSV (782 columns)
    ↓
R Encyclopedia Generator
    │
    ├─ Lookup Tables (R data.frames)
    │   ├─ eive_light_descriptions.csv (1-9 → "Full sun", "Partial shade", etc.)
    │   ├─ koppen_zone_mappings.csv (Köppen → USDA zones, RHS hardiness)
    │   ├─ csr_maintenance_rules.csv (C/S/R thresholds → maintenance levels)
    │   └─ climate_descriptors.csv (tier combinations → garden styles)
    │
    ├─ Threshold Rules (R functions)
    │   ├─ categorize_light(eive_l) → "Full sun" | "Partial shade" | "Full shade"
    │   ├─ calculate_maintenance(csr_c, csr_s, csr_r) → "LOW" | "MEDIUM" | "HIGH"
    │   ├─ assess_pest_risk(herbivore_count, predator_count) → "LOW" | "MODERATE" | "HIGH"
    │   └─ detect_warnings(plant_data) → list of warning objects
    │
    └─ Text Templates (glue::glue syntax)
        ├─ template_identity_card.txt
        ├─ template_growing_requirements.txt
        ├─ template_maintenance_profile.txt
        ├─ template_ecosystem_services.txt
        ├─ template_biological_interactions.txt
        ├─ template_climate_resilience.txt
        ├─ template_soil_requirements.txt
        ├─ template_planting_propagation.txt
        └─ template_warnings.txt
    ↓
Markdown Encyclopedia Page
    ↓
Pandoc/rmarkdown → HTML
```

### Example: Growing Requirements Section (Pure R)

**Lookup table** (`eive_translations.csv`):
```
eive_value,category,light_advice,water_advice,fertility_advice,ph_advice
1,Very low,"Deep shade under dense canopy","Constantly waterlogged","Extremely infertile soils","Strongly acidic (pH 3-4)"
2,Low,"Deep shade","Very wet soils","Infertile, poor soils","Acidic (pH 4-5)"
3,Low-moderate,"Shade","Moist to wet soils","Low fertility","Moderately acidic (pH 5-6)"
4,Moderate,"Partial shade","Moist soils","Moderate fertility","Slightly acidic (pH 6-6.5)"
5,Moderate,"Light shade to sun","Moderate moisture","Moderate fertility","Neutral (pH 6.5-7)"
6,Moderate-high,"Sun to light shade","Moderate to dry","Moderate-high fertility","Slightly alkaline (pH 7-7.5)"
7,High,"Full sun preferred","Dry to moderate","High fertility","Alkaline (pH 7.5-8)"
8,High,"Full sun required","Dry, well-drained","Very high fertility","Strongly alkaline (pH 8-8.5)"
9,Very high,"Full sun only","Very dry/xeric","Extremely fertile","Very alkaline (pH 8.5+)"
```

**R function**:
```r
generate_growing_requirements <- function(plant_data, eive_translations, koppen_mappings) {

  # Lookup EIVE categories
  light_desc <- eive_translations %>%
    filter(eive_value == round(plant_data$`EIVEres-L`)) %>%
    pull(light_advice)

  water_desc <- eive_translations %>%
    filter(eive_value == round(plant_data$`EIVEres-M`)) %>%
    pull(water_advice)

  fertility_desc <- eive_translations %>%
    filter(eive_value == round(plant_data$`EIVEres-N`)) %>%
    pull(fertility_advice)

  ph_desc <- eive_translations %>%
    filter(eive_value == round(plant_data$`EIVEres-R`)) %>%
    pull(ph_advice)

  # Map Köppen tiers to regional zones
  climate_zones <- koppen_mappings %>%
    filter(tier_1_tropical == plant_data$tier_1_tropical,
           tier_2_mediterranean == plant_data$tier_2_mediterranean,
           tier_3_humid_temperate == plant_data$tier_3_humid_temperate) %>%
    pull(usda_zones) %>%
    first()

  # Adjust watering advice based on CSR-S (stress tolerance)
  if (plant_data$S > 0.6) {
    water_advice <- paste(water_desc, "| Drought-tolerant once established (stress-tolerant strategy)")
  } else if (plant_data$C > 0.6) {
    water_advice <- paste(water_desc, "| Regular watering needed (competitive growth strategy)")
  } else {
    water_advice <- water_desc
  }

  # Adjust fertility advice based on CSR-C (competitor)
  if (plant_data$C > 0.6 && plant_data$`EIVEres-N` > 6) {
    fertility_advice <- paste(fertility_desc, "| Hungry feeder - monthly fertilization during growing season")
  } else if (plant_data$S > 0.6 && plant_data$`EIVEres-N` < 4) {
    fertility_advice <- paste(fertility_desc, "| Avoid over-fertilizing (adapted to poor soils)")
  } else {
    fertility_advice <- fertility_desc
  }

  # Generate text using template
  glue::glue("
  ☀️ Light: {light_desc} (EIVE-L: {round(plant_data$`EIVEres-L`)}/9)
     → {get_light_planting_advice(plant_data$`EIVEres-L`)}

  💧 Water: {water_advice} (EIVE-M: {round(plant_data$`EIVEres-M`)}/9)
     → {get_watering_schedule(plant_data$`EIVEres-M`, plant_data$S)}

  🌡️ Climate: {climate_zones}
     → Suitable for {get_regional_names(plant_data)}

  🌱 Fertility: {fertility_advice} (EIVE-N: {round(plant_data$`EIVEres-N`)}/9)
     → {get_fertilizer_advice(plant_data$`EIVEres-N`, plant_data$C)}

  ⚗️ pH: {ph_desc} (EIVE-R: {round(plant_data$`EIVEres-R`)}/9)
     → {get_ph_amendment_advice(plant_data$`EIVEres-R`)}
  ")
}
```

**Output** (deterministic, instant):
```
☀️ Light: Full sun required (EIVE-L: 8/9)
   → Plant in open positions, south-facing sites

💧 Water: Dry, well-drained | Drought-tolerant once established (EIVE-M: 3/9)
   → Weekly watering first year, monthly thereafter

🌡️ Climate: USDA Zones 5-9 | RHS Hardiness H5
   → Suitable for UK, Southern Europe, California coastal

🌱 Fertility: Moderate fertility | Avoid over-fertilizing (EIVE-N: 5/9)
   → Light annual feeding in spring sufficient

⚗️ pH: Neutral to alkaline (pH 6.5-8.0) (EIVE-R: 7/9)
   → Add lime to acid soils if pH <6.5
```

### R Modular Architecture

Following the Stage 4 guild scorer modularization pattern:

```
shipley_checks/src/encyclopedia/
├── encyclopedia_generator.R              # Main coordinator (R6 class)
│   └── EncyclopediaGenerator$new()
│       ├── load_plant_data()
│       ├── generate_page()
│       └── batch_generate()
│
├── sections/                             # Independent section generators
│   ├── s1_identity_card.R                # Taxonomic + functional traits → identity card
│   ├── s2_growing_requirements.R         # EIVE + CSR + Köppen → site requirements
│   ├── s3_maintenance_profile.R          # CSR + phenology → labor estimates
│   ├── s4_ecosystem_services.R           # 10 service ratings → environmental benefits
│   ├── s5_biological_interactions.R      # Network data → pest/disease/pollinator summary
│   ├── s6_climate_resilience.R           # Köppen + extremes → climate adaptation
│   ├── s7_soil_requirements.R            # Soil data + EIVE-R → amendments
│   ├── s8_planting_propagation.R         # Seed + GSL → establishment guidance
│   ├── s9_design_aesthetics.R            # Height + form + phenology → garden design
│   └── s10_warnings.R                    # Edge case detection → special considerations
│
├── utils/                                # Shared functionality
│   ├── lookup_tables.R                   # Load and cache CSV lookups
│   ├── categorization.R                  # Threshold-based categorization functions
│   ├── text_formatting.R                 # Markdown/HTML formatting utilities
│   └── validation.R                      # Data completeness checks
│
├── data/                                 # Lookup tables
│   ├── eive_translations.csv             # EIVE 1-9 → user-friendly text
│   ├── koppen_zone_mappings.csv          # Köppen tiers → USDA/RHS zones
│   ├── csr_maintenance_rules.csv         # CSR thresholds → maintenance levels
│   ├── climate_descriptors.csv           # Tier combinations → garden styles
│   ├── growth_form_descriptions.csv      # Growth forms → visual descriptors
│   ├── ecosystem_service_templates.csv   # Ratings → benefit descriptions
│   ├── warning_triggers.csv              # Edge case thresholds → warnings
│   └── soil_amendment_advice.csv         # pH/texture → amendment quantities
│
└── tests/
    ├── test_individual_sections.R        # Test each section in isolation
    ├── test_sample_plants.R              # End-to-end test (5 diverse plants)
    └── test_parallel_execution.R         # Verify parallel processing
```

### Module Structure Pattern

Each section module follows this template (from Stage 4 scorer pattern):

```r
# sections/s2_growing_requirements.R

# ==============================================================================
# SECTION 2: GROWING REQUIREMENTS (SITE SELECTION)
# ==============================================================================
#
# PURPOSE:
#   Translate EIVE indicators and Köppen climate data into user-friendly
#   site selection advice for individual plants.
#
# DATA SOURCES:
#   - EIVE-L (Light): 1-9 scale, 100% coverage
#   - EIVE-M (Moisture): 1-9 scale, 100% coverage
#   - EIVE-T (Temperature): 1-9 scale, 100% coverage
#   - EIVE-N (Nutrients): 1-9 scale, 100% coverage
#   - EIVE-R (pH/Reaction): 1-9 scale, 100% coverage
#   - CSR strategy: C, S, R scores (99.88% coverage)
#   - Köppen tiers: 6 boolean flags (100% coverage)
#
# OUTPUT FORMAT:
#   Markdown text with 5 subsections:
#   - Light (emoji: ☀️)
#   - Water (emoji: 💧)
#   - Climate (emoji: 🌡️)
#   - Fertility (emoji: 🌱)
#   - pH (emoji: ⚗️)
#
# DEPENDENCIES:
#   - utils/lookup_tables.R: get_eive_translation()
#   - utils/categorization.R: map_koppen_to_usda()
#
# ==============================================================================

generate_section_2_growing_requirements <- function(plant_data, lookup_tables) {

  # STEP 1: Lookup base EIVE translations
  light_desc <- get_eive_translation(plant_data$`EIVEres-L`, "light", lookup_tables)
  water_desc <- get_eive_translation(plant_data$`EIVEres-M`, "water", lookup_tables)
  fertility_desc <- get_eive_translation(plant_data$`EIVEres-N`, "fertility", lookup_tables)
  ph_desc <- get_eive_translation(plant_data$`EIVEres-R`, "ph", lookup_tables)

  # STEP 2: Adjust water advice based on CSR-S (stress tolerance)
  # RATIONALE: S-dominant plants are adapted to low-resource environments,
  # often developing drought tolerance mechanisms (deep roots, water storage)
  if (plant_data$S > 0.6) {
    water_advice <- paste(water_desc,
                          "| Drought-tolerant once established (stress-tolerant strategy)")
  } else if (plant_data$C > 0.6) {
    water_advice <- paste(water_desc,
                          "| Regular watering needed (competitive growth strategy)")
  } else {
    water_advice <- water_desc
  }

  # STEP 3: Adjust fertility advice based on CSR-C (competitor)
  # RATIONALE: C-dominant plants have high resource acquisition rates,
  # requiring consistent nutrient availability for optimal growth
  if (plant_data$C > 0.6 && plant_data$`EIVEres-N` > 6) {
    fertility_advice <- paste(fertility_desc,
                              "| Hungry feeder - monthly fertilization during growing season")
  } else if (plant_data$S > 0.6 && plant_data$`EIVEres-N` < 4) {
    fertility_advice <- paste(fertility_desc,
                              "| Avoid over-fertilizing (adapted to poor soils)")
  } else {
    fertility_advice <- fertility_desc
  }

  # STEP 4: Map Köppen tiers to regional climate zones
  climate_zones <- map_koppen_to_usda(plant_data, lookup_tables)
  regional_names <- get_regional_names(plant_data)

  # STEP 5: Generate subsection text using glue templates
  light_section <- glue::glue("
  ☀️ Light: {light_desc} (EIVE-L: {round(plant_data$`EIVEres-L`)}/9)
     → {get_light_planting_advice(plant_data$`EIVEres-L`, lookup_tables)}
  ")

  water_section <- glue::glue("
  💧 Water: {water_advice} (EIVE-M: {round(plant_data$`EIVEres-M`)}/9)
     → {get_watering_schedule(plant_data$`EIVEres-M`, plant_data$S, lookup_tables)}
  ")

  climate_section <- glue::glue("
  🌡️ Climate: {climate_zones}
     → Suitable for {regional_names}
  ")

  fertility_section <- glue::glue("
  🌱 Fertility: {fertility_advice} (EIVE-N: {round(plant_data$`EIVEres-N`)}/9)
     → {get_fertilizer_advice(plant_data$`EIVEres-N`, plant_data$C, lookup_tables)}
  ")

  ph_section <- glue::glue("
  ⚗️ pH: {ph_desc} (EIVE-R: {round(plant_data$`EIVEres-R`)}/9)
     → {get_ph_amendment_advice(plant_data$`EIVEres-R`, lookup_tables)}
  ")

  # STEP 6: Combine into full section
  paste(light_section, water_section, climate_section,
        fertility_section, ph_section, sep = "\n\n")
}
```

### Main Coordinator (R6 Class)

```r
# encyclopedia_generator.R

# Source all section modules
source("shipley_checks/src/encyclopedia/sections/s1_identity_card.R")
source("shipley_checks/src/encyclopedia/sections/s2_growing_requirements.R")
source("shipley_checks/src/encyclopedia/sections/s3_maintenance_profile.R")
source("shipley_checks/src/encyclopedia/sections/s4_ecosystem_services.R")
source("shipley_checks/src/encyclopedia/sections/s5_biological_interactions.R")
source("shipley_checks/src/encyclopedia/sections/s6_climate_resilience.R")
source("shipley_checks/src/encyclopedia/sections/s7_soil_requirements.R")
source("shipley_checks/src/encyclopedia/sections/s8_planting_propagation.R")
source("shipley_checks/src/encyclopedia/sections/s9_design_aesthetics.R")
source("shipley_checks/src/encyclopedia/sections/s10_warnings.R")

# Source utils
source("shipley_checks/src/encyclopedia/utils/lookup_tables.R")
source("shipley_checks/src/encyclopedia/utils/categorization.R")
source("shipley_checks/src/encyclopedia/utils/text_formatting.R")
source("shipley_checks/src/encyclopedia/utils/validation.R")

EncyclopediaGenerator <- R6::R6Class("EncyclopediaGenerator",
  public = list(

    # Initialize with data sources
    initialize = function(plant_data_path, organisms_path, fungi_path) {
      cat("Loading plant dataset...\n")
      private$plants_df <- arrow::read_parquet(plant_data_path)

      cat("Loading organism profiles...\n")
      private$organisms_df <- arrow::read_parquet(organisms_path)

      cat("Loading fungal guilds...\n")
      private$fungi_df <- arrow::read_parquet(fungi_path)

      cat("Loading lookup tables...\n")
      private$lookup_tables <- load_all_lookup_tables()

      cat(sprintf("✓ Encyclopedia generator ready for %d plants\n",
                  nrow(private$plants_df)))
    },

    # Generate single encyclopedia page
    generate_page = function(wfo_taxon_id, use_llm_polish = FALSE) {

      # Load plant data
      plant_data <- private$plants_df %>%
        filter(wfo_taxon_id == !!wfo_taxon_id)

      if (nrow(plant_data) == 0) {
        stop(glue::glue("Plant {wfo_taxon_id} not found in dataset"))
      }

      # Load organism data (optional, not all plants have networks)
      organism_data <- private$organisms_df %>%
        filter(plant_wfo_id == !!wfo_taxon_id)

      fungi_data <- private$fungi_df %>%
        filter(plant_wfo_id == !!wfo_taxon_id)

      # Generate sections (each module is independent)
      sections <- list(
        identity = generate_section_1_identity_card(
          plant_data, private$lookup_tables),

        growing = generate_section_2_growing_requirements(
          plant_data, private$lookup_tables),

        maintenance = generate_section_3_maintenance_profile(
          plant_data, private$lookup_tables),

        ecosystem = generate_section_4_ecosystem_services(
          plant_data, private$lookup_tables),

        interactions = generate_section_5_biological_interactions(
          plant_data, organism_data, fungi_data, private$lookup_tables),

        climate = generate_section_6_climate_resilience(
          plant_data, private$lookup_tables),

        soil = generate_section_7_soil_requirements(
          plant_data, private$lookup_tables),

        planting = generate_section_8_planting_propagation(
          plant_data, private$lookup_tables),

        design = generate_section_9_design_aesthetics(
          plant_data, private$lookup_tables, use_llm = FALSE),

        warnings = generate_section_10_warnings(
          plant_data, organism_data, fungi_data, private$lookup_tables)
      )

      # Optional LLM naturalizing pass (Phase 2)
      if (use_llm_polish) {
        sections <- purrr::imap(sections, private$naturalize_with_llm)
      }

      # Assemble and format
      private$assemble_page(wfo_taxon_id, plant_data, sections)
    },

    # Batch generate with optional parallel processing
    batch_generate = function(wfo_taxon_ids = NULL,
                              parallel = TRUE,
                              n_workers = 8,
                              use_llm_polish = FALSE) {

      # Default: all plants
      if (is.null(wfo_taxon_ids)) {
        wfo_taxon_ids <- private$plants_df$wfo_taxon_id
      }

      n_plants <- length(wfo_taxon_ids)
      cat(sprintf("Generating encyclopedia pages for %d plants...\n", n_plants))

      if (parallel && n_plants > 100) {
        cat(sprintf("Using %d parallel workers\n", n_workers))
        private$batch_generate_parallel(wfo_taxon_ids, n_workers, use_llm_polish)
      } else {
        cat("Using sequential processing\n")
        private$batch_generate_sequential(wfo_taxon_ids, use_llm_polish)
      }

      cat("✓ Batch generation complete\n")
    }
  ),

  private = list(
    plants_df = NULL,
    organisms_df = NULL,
    fungi_df = NULL,
    lookup_tables = NULL,

    # Sequential batch generation (simple, reliable)
    batch_generate_sequential = function(wfo_taxon_ids, use_llm_polish) {
      pb <- progress::progress_bar$new(
        format = "[:bar] :current/:total (:percent) eta: :eta",
        total = length(wfo_taxon_ids)
      )

      purrr::walk(wfo_taxon_ids, function(id) {
        tryCatch({
          self$generate_page(id, use_llm_polish)
          pb$tick()
        }, error = function(e) {
          warning(glue::glue("Failed to generate page for {id}: {e$message}"))
          pb$tick()
        })
      })
    },

    # Parallel batch generation (faster for large batches)
    batch_generate_parallel = function(wfo_taxon_ids, n_workers, use_llm_polish) {
      # Set up parallel backend
      future::plan(future::multisession, workers = n_workers)

      # Split plants into chunks for each worker
      chunks <- split(wfo_taxon_ids, cut(seq_along(wfo_taxon_ids), n_workers))

      # Process chunks in parallel
      # NOTE: Each worker needs its own copy of data (overhead)
      results <- furrr::future_map(chunks, function(chunk) {
        purrr::map(chunk, function(id) {
          tryCatch({
            self$generate_page(id, use_llm_polish)
            list(id = id, status = "success")
          }, error = function(e) {
            list(id = id, status = "error", message = e$message)
          })
        })
      }, .progress = TRUE)

      # Reset to sequential
      future::plan(future::sequential)

      # Report errors
      all_results <- unlist(results, recursive = FALSE)
      errors <- purrr::keep(all_results, ~.x$status == "error")
      if (length(errors) > 0) {
        cat(sprintf("✗ %d errors occurred:\n", length(errors)))
        purrr::walk(errors, ~cat(sprintf("  - %s: %s\n", .x$id, .x$message)))
      }
    },

    # Assemble sections into final page
    assemble_page = function(wfo_taxon_id, plant_data, sections) {
      # Combine all sections
      full_content <- paste(
        sections$identity,
        "\n## Growing Requirements\n", sections$growing,
        "\n## Maintenance Profile\n", sections$maintenance,
        "\n## Ecosystem Services\n", sections$ecosystem,
        "\n## Biological Interactions\n", sections$interactions,
        "\n## Climate Resilience\n", sections$climate,
        "\n## Soil Requirements\n", sections$soil,
        "\n## Planting & Propagation\n", sections$planting,
        "\n## Garden Design\n", sections$design,
        "\n## Important Considerations\n", sections$warnings,
        sep = "\n"
      )

      # Write markdown file
      output_path <- glue::glue("output/encyclopedia/{wfo_taxon_id}.md")
      dir.create(dirname(output_path), showWarnings = FALSE, recursive = TRUE)
      writeLines(full_content, output_path)

      # Optional: Convert to HTML
      # rmarkdown::render(output_path, output_format = "html_document",
      #                   output_file = glue::glue("{wfo_taxon_id}.html"))
    },

    # Optional LLM naturalizing
    naturalize_with_llm = function(section_text, section_name) {
      # Feature flag check
      if (!exists("USE_LLM_POLISH") || !USE_LLM_POLISH) {
        return(section_text)
      }

      # Call LLM API (implement based on chosen provider)
      # ... LLM API call here ...

      section_text  # Return original for now
    }
  )
)
```

### Parallel Processing Strategy

**Approach**: Section-level parallelism per plant (not plant-level parallelism)

**Rationale** (from Stage 4 scorer experience):
- R parallelism requires forking/serializing entire datasets
- For 11,711 plants × 782 columns, data copying overhead is significant
- Plant-level parallelism: 8 workers × ~50MB data = 400MB memory overhead
- Section-level parallelism: No data copying, sections run in parallel per plant

**Implementation**:

```r
# Option A: Section-level parallelism (RECOMMENDED)
# Generate all sections in parallel for each plant
generate_page_parallel_sections <- function(wfo_taxon_id) {

  # Load data once
  plant_data <- load_plant_data(wfo_taxon_id)
  organism_data <- load_organism_data(wfo_taxon_id)
  fungi_data <- load_fungi_data(wfo_taxon_id)

  # Set up parallel plan for sections
  future::plan(future::multisession, workers = 8)

  # Generate sections in parallel
  sections <- furrr::future_map(1:10, function(i) {
    switch(i,
      `1` = generate_section_1_identity_card(plant_data, lookup_tables),
      `2` = generate_section_2_growing_requirements(plant_data, lookup_tables),
      `3` = generate_section_3_maintenance_profile(plant_data, lookup_tables),
      `4` = generate_section_4_ecosystem_services(plant_data, lookup_tables),
      `5` = generate_section_5_biological_interactions(plant_data, organism_data,
                                                       fungi_data, lookup_tables),
      `6` = generate_section_6_climate_resilience(plant_data, lookup_tables),
      `7` = generate_section_7_soil_requirements(plant_data, lookup_tables),
      `8` = generate_section_8_planting_propagation(plant_data, lookup_tables),
      `9` = generate_section_9_design_aesthetics(plant_data, lookup_tables),
      `10` = generate_section_10_warnings(plant_data, organism_data,
                                          fungi_data, lookup_tables)
    )
  })

  # Reset to sequential
  future::plan(future::sequential)

  # Assemble page
  assemble_page(wfo_taxon_id, plant_data, sections)
}

# Batch loop (sequential across plants, parallel per plant)
purrr::walk(wfo_taxon_ids, generate_page_parallel_sections)
```

**Performance Estimates**:

| Approach | Time per Plant | Total (11,711 plants) | Memory Overhead |
|----------|---------------|----------------------|-----------------|
| Sequential sections | ~2 seconds | ~6.5 hours | Minimal |
| Parallel sections (8 workers) | ~0.5 seconds | ~1.6 hours | ~50MB per plant |
| Parallel plants (8 workers) | ~2 seconds | ~1 hour | ~400MB total |

**Recommendation**:
- **Development**: Sequential (simple, easier debugging)
- **Production**: Parallel sections (4× speedup, minimal overhead)
- **Avoid**: Parallel plants (complex, high memory, marginal speedup)

---

## Phase 2: Optional LLM Enhancement (10%)

**Purpose**: Natural language polish and creative content
**When to use**: After Phase 1 is working, if rules-based text feels too rigid

### Use Case A: "Naturalizing" Pass (Post-Processing)

**Process**:
1. Generate entire page with R rules engine
2. Pass completed text through LLM with prompt: "Make this more natural while preserving all facts and numbers"
3. LLM smooths transitions, varies sentence structure, adds connecting phrases

**Example**:
- **Rules output**: "Full sun required. Plant in open positions. USDA Zones 5-9. Drought-tolerant once established."
- **LLM naturalized**: "This plant requires full sun and thrives in open positions. Hardy in USDA Zones 5-9, it becomes drought-tolerant once established after the first year."

**Cost**: ~$0.001 per plant (cheaper than generating from scratch)
**Speed**: ~2-3 seconds per plant with API call

**R Implementation**:
```r
naturalize_with_llm <- function(rules_based_text, section_name) {
  if (!USE_LLM_POLISH) return(rules_based_text)  # Feature flag

  prompt <- glue::glue("
  Improve the natural language flow of this {section_name} while preserving ALL facts, numbers, and advice:

  {rules_based_text}

  Requirements:
  - Keep all numerical values exact
  - Preserve all practical advice
  - Maintain emoji icons and formatting
  - Make transitions smoother
  - Vary sentence structure
  - Keep concise (max 10% longer)
  ")

  api_call_claude(prompt)
}

generate_encyclopedia_page <- function(wfo_taxon_id, use_llm_polish = FALSE) {
  plant_data <- load_plant_data(wfo_taxon_id)

  sections <- list(
    identity = generate_section_1_identity_card(plant_data),
    growing = generate_section_2_growing_requirements(plant_data),
    maintenance = generate_section_3_maintenance_profile(plant_data),
    # ... etc
  )

  # Optional LLM naturalizing pass
  if (use_llm_polish) {
    sections <- purrr::imap(sections, naturalize_with_llm)
  }

  assemble_page(sections)
}
```

### Use Case B: Design & Aesthetics Section Only (LLM-Native)

**Rationale**: This section is creative/inspirational, benefits from LLM's language flexibility

**Process**:
1. Sections 1-8, 10: Pure R rules engine
2. Section 9 (Design & Aesthetics): LLM generation from structured context

**R Implementation**:
```r
generate_section_9_design_aesthetics <- function(plant_data, use_llm = TRUE) {

  if (!use_llm) {
    # Fallback to rules-based template
    return(generate_design_template(plant_data))
  }

  # Prepare structured context for LLM
  context <- list(
    height = plant_data$height_m,
    growth_form = plant_data$try_growth_form,
    leaf_type = plant_data$try_leaf_type,
    phenology = plant_data$try_leaf_phenology,
    eive_l = plant_data$`EIVEres-L`,
    csr_strategy = get_dominant_strategy(plant_data$C, plant_data$S, plant_data$R),
    koppen_tiers = get_tier_names(plant_data),
    pollinator_count = plant_data$pollinator_count %||% 0
  )

  prompt <- glue::glue("
  Generate an inspiring 'Garden Design' section for this plant:

  Physical traits:
  - Height: {context$height}m
  - Form: {context$growth_form}
  - Foliage: {context$leaf_type}, {context$phenology}
  - Light needs: {categorize_light(context$eive_l)}
  - Plant strategy: {context$csr_strategy}

  Climate: {paste(context$koppen_tiers, collapse=', ')}
  Pollinators: {context$pollinator_count} species

  Write 4 sections:
  1. Visual Character (form, texture, color)
  2. Seasonal Interest (spring, summer, autumn, winter)
  3. Planting Position (light, vertical layer, garden locations)
  4. Design Styles (Mediterranean, cottage, xeriscape, etc. - based on climate/traits)

  Be inspirational but practical. Use emoji icons. Max 150 words.
  ")

  api_call_claude(prompt)
}
```

---

## Recommended Implementation Sequence

### Phase 1A: Setup (Day 1)

**Create directory structure**:
```bash
mkdir -p shipley_checks/src/encyclopedia/{sections,utils,data,tests}
mkdir -p output/encyclopedia
```

**Create lookup tables** (8 CSV files):
```r
# 1. eive_translations.csv (9 rows × 5 columns)
# 2. koppen_zone_mappings.csv (64 combinations × 3 columns)
# 3. csr_maintenance_rules.csv (rule definitions)
# 4. climate_descriptors.csv (tier combos → styles)
# 5. growth_form_descriptions.csv (visual descriptors)
# 6. ecosystem_service_templates.csv (ratings → text)
# 7. warning_triggers.csv (thresholds)
# 8. soil_amendment_advice.csv (pH/texture → amendments)
```

### Phase 1B: Utils Layer (Days 2-3)

**Build shared utilities** (4 files, ~300 lines total):

```r
# utils/lookup_tables.R (~80 lines)
load_all_lookup_tables() → list of data.frames
get_eive_translation(value, type, tables) → character
get_climate_zones(tiers, tables) → character

# utils/categorization.R (~100 lines)
categorize_light(eive_l) → "Full sun" | "Partial shade" | "Full shade"
categorize_moisture(eive_m) → "Dry" | "Moist" | "Wet"
calculate_maintenance_level(C, S, R) → "LOW" | "MEDIUM" | "HIGH"
assess_pest_risk(herb_count, pred_count) → "LOW" | "MODERATE" | "HIGH"
map_koppen_to_usda(tier_flags) → "USDA Zones X-Y"

# utils/text_formatting.R (~80 lines)
format_star_rating(value) → "⭐⭐⭐" (1-5 stars)
format_temperature(celsius) → "X°C (Y°F)"
format_list(vector, max_items = 3) → "item1, item2, item3"

# utils/validation.R (~40 lines)
validate_plant_data(plant_row) → TRUE | error message
check_completeness(value, field_name) → warning if NA
```

**Test utilities**:
```r
# tests/test_utils.R
test_that("EIVE translation works", {
  expect_equal(categorize_light(8), "Full sun required")
  expect_equal(categorize_light(4), "Partial shade")
})

test_that("Köppen mapping works", {
  tiers <- c(TRUE, FALSE, TRUE, FALSE, FALSE, FALSE)
  expect_match(map_koppen_to_usda(tiers), "USDA Zone")
})
```

### Phase 1C: Section Modules (Days 4-8)

**Build one section per day** (10 sections, ~150 lines each):

**Priority order** (simplest → most complex):
1. **Day 4**: s1_identity_card.R (template-based, ~100 lines)
2. **Day 5**: s2_growing_requirements.R (EIVE lookups, ~150 lines)
3. **Day 5**: s3_maintenance_profile.R (CSR rules, ~120 lines)
4. **Day 6**: s6_climate_resilience.R (Köppen + extremes, ~180 lines)
5. **Day 6**: s7_soil_requirements.R (soil data lookups, ~160 lines)
6. **Day 7**: s8_planting_propagation.R (seed + GSL, ~130 lines)
7. **Day 7**: s4_ecosystem_services.R (10 ratings, ~140 lines)
8. **Day 8**: s5_biological_interactions.R (network summary, ~200 lines)
9. **Day 8**: s9_design_aesthetics.R (aesthetic rules, ~150 lines)
10. **Day 8**: s10_warnings.R (edge cases, ~170 lines)

**Test each module independently**:
```r
# tests/test_individual_sections.R
test_that("Section 2 generates valid output", {
  plant_data <- load_test_plant("wfo-0000832453")
  output <- generate_section_2_growing_requirements(plant_data, lookup_tables)

  expect_true(grepl("☀️ Light:", output))
  expect_true(grepl("💧 Water:", output))
  expect_true(grepl("EIVE-L:", output))
})
```

### Phase 1D: Coordinator (Day 9)

**Build main coordinator** (encyclopedia_generator.R, ~250 lines):

```r
# R6 class with:
# - initialize() - Load datasets and lookup tables
# - generate_page() - Orchestrate section generation
# - batch_generate() - Sequential or parallel processing
```

**Test end-to-end**:
```r
# tests/test_sample_plants.R (5 test plants)
gen <- EncyclopediaGenerator$new(
  "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet",
  "shipley_checks/stage4/plant_organism_profiles_11711.parquet",
  "shipley_checks/stage4/plant_fungal_guilds_hybrid_11711.parquet"
)

# Test diverse plants
test_plants <- c(
  "wfo-0000832453",  # Fagus sylvatica (S-dominant tree)
  "wfo-0000649136",  # Buddleja davidii (C-dominant shrub)
  "wfo-0000642673",  # Papaver rhoeas (R-dominant herb)
  "wfo-0000984977",  # Lavandula angustifolia (stress-tolerant)
  "wfo-0000241769"   # Plantago lanceolata (generalist)
)

for (id in test_plants) {
  gen$generate_page(id)
  cat(sprintf("✓ Generated page for %s\n", id))
}
```

### Phase 1E: Batch Generation (Day 10)

**Generate all 11,711 pages**:

```r
# Load generator
gen <- EncyclopediaGenerator$new(
  "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet",
  "shipley_checks/stage4/plant_organism_profiles_11711.parquet",
  "shipley_checks/stage4/plant_fungal_guilds_hybrid_11711.parquet"
)

# Option 1: Sequential (simple, reliable)
gen$batch_generate(parallel = FALSE)
# Estimated time: ~6.5 hours

# Option 2: Parallel plants (faster)
gen$batch_generate(parallel = TRUE, n_workers = 8)
# Estimated time: ~1.5 hours
```

### Phase 1F: Quality Check (Days 11-12)

**Read 50 random sample pages**:
```r
# Sample plants across different categories
samples <- list(
  trees_s = sample_by_strategy("tree", "S"),
  shrubs_c = sample_by_strategy("shrub", "C"),
  herbs_r = sample_by_strategy("herb", "R"),
  mediterranean = sample_by_climate("tier_2_mediterranean"),
  arid = sample_by_climate("tier_6_arid")
)

# Review checklist for each:
# - [ ] EIVE values correctly translated
# - [ ] CSR strategy matches maintenance advice
# - [ ] Köppen zones mapped correctly
# - [ ] Network data summaries accurate (if present)
# - [ ] Warnings triggered appropriately
# - [ ] No missing sections
# - [ ] Formatting consistent
```

**Identify issues**:
- Awkward phrasing → note for LLM polish
- Missing data handling → add validation
- Factual errors → fix lookup tables/rules

### Phase 2: Optional LLM Enhancement (Days 13-14)

**If rules-based text is acceptable**:
- Skip LLM entirely, proceed to web integration
- Total time: 12 days
- Total cost: $0

**If naturalizing is desired**:

**Approach A: Full naturalizing pass**
```r
gen$batch_generate(parallel = TRUE, n_workers = 8, use_llm_polish = TRUE)
```
- Cost: ~$12 for 11,711 pages
- Time: ~6-8 hours (with API rate limiting)

**Approach B: Section 9 only (Design & Aesthetics)**
```r
# Regenerate only s9 with LLM
regenerate_section_9_with_llm(all_wfo_ids)
```
- Cost: ~$6 for 11,711 pages
- Time: ~3-4 hours

---

## Time & Cost Summary

### Phase 1: R Rules Engine (12 days)

| Stage | Days | Lines of Code | Cost |
|-------|------|---------------|------|
| Setup + lookup tables | 1 | ~200 | $0 |
| Utils layer | 2 | ~300 | $0 |
| Section modules (10) | 5 | ~1,500 | $0 |
| Coordinator | 1 | ~250 | $0 |
| Batch generation | 0.3 | - | $0 |
| Quality check | 2 | - | $0 |
| **Total** | **12** | **~2,250** | **$0** |

### Phase 2: Optional LLM (2 days)

| Option | Pages | Cost | Time |
|--------|-------|------|------|
| None (rules only) | 11,711 | $0 | 0 hours |
| Full naturalizing | 11,711 | ~$12 | 6-8 hours |
| Section 9 only | 11,711 | ~$6 | 3-4 hours |

### Performance Targets

| Metric | Sequential | Parallel (8 workers) |
|--------|-----------|---------------------|
| Time per plant | ~2 seconds | ~0.5 seconds |
| Total time (11,711) | ~6.5 hours | ~1.6 hours |
| Memory usage | ~100MB | ~500MB |
| Complexity | Low | Medium |

**Recommendation**: Start with sequential for first 1000 plants, switch to parallel if time permits.

---

## Testing Strategy

### Test Plants (Diverse Sample)

**Tree** (S-dominant, shade-tolerant):
- Fagus sylvatica (European beech)
- Expected: LOW maintenance, slow growth, evergreen structure

**Shrub** (C-dominant, competitive):
- Buddleja davidii (Butterfly bush)
- Expected: HIGH maintenance, fast growth, annual pruning

**Herb** (R-dominant, ruderal):
- Papaver rhoeas (Corn poppy)
- Expected: MEDIUM maintenance, short-lived, self-seeding

**Stress-tolerant specialist**:
- Lavandula angustifolia (English lavender)
- Expected: LOW water, HIGH drought tolerance, xeriscape

**Generalist** (multi-tier Köppen):
- Plantago lanceolata (Ribwort plantain)
- Expected: Climate resilient, adaptable

### Validation Checks

For each test plant, verify:
- [ ] EIVE values correctly translated to categories
- [ ] CSR strategy matches maintenance advice
- [ ] Köppen tiers mapped to correct USDA/RHS zones
- [ ] Warnings triggered for edge cases
- [ ] Ecosystem services aligned with functional traits
- [ ] Network data summaries accurate (top 3 species)
- [ ] All numerical values preserved
- [ ] No missing sections
- [ ] HTML renders correctly

---

## Data Coverage & Completeness

All 11,711 species have:
- ✅ 100% complete functional traits (via mixgb imputation)
- ✅ 100% complete EIVE values (site requirements fully characterized)
- ✅ 99.88% valid CSR scores (maintenance predictions available)
- ✅ 100% climate tolerance data (Köppen tiers, climate extremes)
- ✅ 100% soil preference data (pH, texture, nutrients)

**Network data coverage** (partial, supplement with GuildBuilder link):
- 61.6% have pathogenic fungi data (7,210 plants)
- 27.6% have herbivore data (3,234 plants)
- 63.1% have pathogen data (7,394 plants)
- 13.4% have pollinator data (1,564 plants)

**Implication**: Core advice (Sections 1-3, 6-10) can be generated for ALL plants. Network interactions (Section 5) should acknowledge data gaps and link to GuildBuilder for guild-level analysis.

---

## Quality Control Checklist

For each encyclopedia page generated:

- [ ] All EIVE values translated to user-friendly language (no "5/9" without context)
- [ ] Maintenance advice reflects CSR strategy accurately
- [ ] Climate zones mapped to user's regional system (USDA, RHS, etc.)
- [ ] Warnings present for edge cases (frost sensitivity, drainage issues, etc.)
- [ ] Network data caveats stated if coverage <50%
- [ ] Call-to-action for GuildBuilder present
- [ ] Seasonal timing advice included (planting, pruning, flowering)
- [ ] Quantitative advice where possible (amounts, frequencies, spacings)
- [ ] No jargon without explanation
- [ ] Mobile-friendly format (short paragraphs, emoji icons)

---

## Architecture Summary

### Key Design Principles (from Stage 4 Modularization)

1. **Separation of Concerns**
   - **Sections:** Each encyclopedia section has its own module file
   - **Utils:** Shared functionality extracted (lookups, categorization, formatting)
   - **Coordinator:** R6 class orchestrates but delegates to modules

2. **Comprehensive Documentation**
   - **PURPOSE** block: What the module does
   - **DATA SOURCES** block: Input data with coverage statistics
   - **OUTPUT FORMAT** block: Structure of generated text
   - **DEPENDENCIES** block: Required utils and lookups
   - **STEP comments**: Inline documentation of algorithm

3. **Modularity Benefits**
   - **Easier debugging:** Find section-specific code immediately
   - **Clearer testing:** Test individual sections in isolation
   - **Better maintainability:** Update one section without affecting others
   - **Parallel processing:** Sections can run concurrently per plant

4. **Performance Strategy**
   - **Development:** Sequential processing (simple, reliable)
   - **Production:** Optional parallel sections (4× speedup)
   - **Avoid:** Plant-level parallelism (high overhead in R)

### Comparison with Stage 4 Guild Scorer

| Aspect | Guild Scorer | Encyclopedia Generator |
|--------|-------------|------------------------|
| **Main coordinator** | guild_scorer_v3_modular.R | encyclopedia_generator.R |
| **Module count** | 7 metrics | 10 sections |
| **Module size** | 90-447 lines | 100-200 lines |
| **Utils** | normalization.R, shared_organism_counter.R | lookup_tables.R, categorization.R, text_formatting.R, validation.R |
| **Lookup tables** | normalization_params JSON | 8 CSV lookup tables |
| **Parallelism** | Not implemented (Rust for speed) | Optional (per plant or per section) |
| **Output** | JSON + markdown report | Markdown → HTML |
| **Documentation** | Ecological rationale + parity requirements | Data sources + output format |

### Why R Rules Engine > LLM

**Data characteristics favor deterministic generation**:
- 782 structured columns per plant
- 100% EIVE coverage (1-9 scales with clear meanings)
- 100% CSR scores (well-studied strategy framework)
- 100% climate data (Köppen + WorldClim quantiles)

**Benefits of rules-based approach**:
1. **Zero cost** - No API fees
2. **Fast** - <1 second per plant vs 2-3 seconds with LLM
3. **Deterministic** - Same input = same output (reproducible)
4. **Testable** - Lookup tables easily validated
5. **Offline** - No API dependency
6. **Transparent** - Users can audit rules/thresholds

**When LLM adds value** (optional Phase 2):
- Naturalizing text flow (smoothing transitions)
- Design & Aesthetics section (creative/inspirational)
- Handling edge cases not in lookup tables

## Next Steps

### Immediate (Days 1-3)
1. Create directory structure
2. Build 8 lookup tables (CSV files)
3. Implement utils layer (4 files, ~300 lines)
4. Test utils with 5 diverse plants

### Short-term (Days 4-9)
5. Build 10 section modules (~1,500 lines total)
6. Test each section independently
7. Build R6 coordinator class (~250 lines)
8. End-to-end test with 5 plants

### Medium-term (Days 10-12)
9. Batch generate all 11,711 pages (~1.5-6.5 hours)
10. Quality check 50 random samples
11. Fix any issues in lookup tables or rules

### Optional (Days 13-14)
12. If needed: Add LLM naturalizing pass
13. If needed: Implement Section 9 with LLM

### Future
14. **SEO optimization**: Meta descriptions, structured data, internal linking
15. **GuildBuilder integration**: "Add to Guild" buttons, session management
16. **Web deployment**: Static site generator (Hugo, Jekyll, or custom)
17. **User testing**: Readability, actionability, accuracy feedback
