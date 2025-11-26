# S2: Growing Requirements Rules

Rules for generating the growing requirements section, combining climate data, soil data, ecological indicators, and agroclimatic indicators.

**Major update (2025-11-26)**: Added 6 high-value agroclimatic variables (FD, CFD, TR, DTR, GSL, WW) for enhanced practical guidance on frost risk, growing season, disease pressure, and pest activity.

## CRITICAL: Understanding the Data

**All climate and soil data come from where plants naturally grow in the wild**, NOT from garden experiments or cultivation trials.

### How We Get This Information

1. **Plant locations**: We collect thousands of records showing where each species has been found (from herbaria, field surveys, biodiversity databases like GBIF)
2. **Extract conditions**: For each location, we look up the climate (temperature, rainfall) and soil (pH, texture, nutrients) at that spot
3. **Summarize the range**: We calculate:
   - **Typical conditions**: Where the plant is most commonly found (the middle of its range)
   - **Extremes**: The coldest/hottest/driest/wettest places where it still survives

### What This Means for Gardeners

**This shows WHERE THE PLANT GROWS IN NATURE, not strict requirements for your garden.**

**Key points**:
- **Typical conditions**: Where the plant is most successful and abundant in the wild
- **Extreme edges**: What the plant can survive, but may not thrive
- **Wide range**: If a plant occurs in many different conditions, it's adaptable
- **Narrow range**: If found only in specific conditions, it's fussy

**Examples**:
- "Coldest winter: -18°C" means populations exist where winter nights average -18°C
- "Driest conditions: 200mm rainfall" means some populations survive on only 200mm per year
- "Typical pH: 6.4" means most populations occur around pH 6.4 soils

**Important**: Just because a plant survives at the extreme edges doesn't mean it will be happy there. It performs best in the typical conditions where it's most common.

---

## Two Perspectives on Growing Conditions

We show **both** types of information together:

1. **Where it grows naturally**: Actual temperature, rainfall, and soil measurements from the wild
2. **Ecological indicators**: Simple 0-10 scores showing what conditions it prefers

**When both agree** → you can be confident. **When they differ** → the plant tolerates a wide range but has preferences.

**Example**: A plant might survive pH 5.0-8.0 (wide tolerance) but prefer acidic soils (ecological score of 3). It will grow in neutral soil but may not outcompete other plants there.

---

## Light Requirements

**Source**: Ecological light indicator only (0-10 scale)

### Light Levels (Ecological Indicator)

Based on where plants are found in natural plant communities:

| Score | Light Level | Relative Light | Where to Plant |
|-------|-------------|----------------|----------------|
| 0-2 | Deep shade | <2% of full sun | Under dense evergreens, north walls |
| 2-4 | Shade | 2-10% of full sun | Under deciduous trees, woodland floor |
| 4-6 | Partial shade | 10-40% of full sun | Dappled light, morning sun only |
| 6-8 | Sun to part shade | 40-80% of full sun | Open borders, tolerates some shade |
| 8-10 | Full sun | >80% of full sun | South-facing, open positions |

**Output format**:
```markdown
**Light**: 6.5/10 - Full sun to part shade
Open borders work well; tolerates some afternoon shade.
```

---

## Temperature

### Understanding Temperature Data

We use different temperature measurements:
- **TNn** (coldest night of the year): The single coldest temperature the plant experiences
- **BIO6** (average winter minimum): The typical overnight low during the coldest month
- **TXx** (hottest day of the year): The single hottest temperature
- **BIO5** (average summer maximum): The typical daytime high during the warmest month

**Why both?** Knowing the coldest **single night** tells you if it will survive a cold snap. Knowing the **average winter** tells you if it needs cold dormancy.

### Data Sources

**Temperature variables**:
- `TNn_q05/q50/q95`: Absolute minimum temperature (coldest night) - **in Kelvin, convert to °C by subtracting 273.15**
- `TXx_q05/q50/q95`: Absolute maximum temperature (hottest day) - **in Kelvin, convert to °C by subtracting 273.15**
- `wc2.1_30s_bio_6_q05/q50/q95`: Min Temperature of Coldest Month - **already in °C** (WorldClim 2.x stores BIO variables in °C; only v1.4 used °C × 10)
- `wc2.1_30s_bio_5_q05/q50/q95`: Max Temperature of Warmest Month - **already in °C** (WorldClim 2.x stores BIO variables in °C; only v1.4 used °C × 10)
- `wc2.1_30s_bio_4_q05/q50/q95`: Temperature Seasonality (standard deviation × 100)

**CRITICAL: TNn and TXx are temporal means from Copernicus AgroClim**:
- Source: Copernicus dekadal (10-day) climate indicators, averaged over 30-year periods
- `TXx` = "Maximum daily temperature per 10-day period", then averaged across ~1080 dekads
- `TNn` = "Minimum daily temperature per 10-day period", then averaged across ~1080 dekads
- **NOT** absolute single-day extremes, but **averages of dekadal extremes**
- See `Stage_0_Raw_Environmental_Data_Preparation.md` for full explanation
- **Consequence**: These may appear lower than WorldClim BIO5/BIO6 values due to different aggregation methods
- **DO NOT directly compare** TXx_mean with BIO5 - they represent different temporal aggregations

**Precipitation variables**:
- `wc2.1_30s_bio_12_q05/q50/q95`: Annual Precipitation (mm)
- `wc2.1_30s_bio_14_q05/q50/q95`: Precipitation of Driest Month (mm)
- `wc2.1_30s_bio_17_q05/q50/q95`: Precipitation of Driest Quarter (mm)
- `wc2.1_30s_bio_18_q05/q50/q95`: Precipitation of Warmest Quarter (mm)
- `CDD_q05/q50/q95`: Consecutive Dry Days (count)

**Climate classification**:
- `top_zone_code`: Köppen-Geiger climate zone (e.g., "Csb", "Cfb")

**Ecological indicators**:
- `EIVEres-T_complete`: Temperature preference (0-10)
- `EIVEres-M_complete`: Moisture preference (0-10)

---

### Köppen Climate Zones

**Data**: `top_zone_code` - the climate type where the plant is most commonly found

**What it means**: Köppen-Geiger codes combine temperature, rainfall, and seasonality into climate types. This shows the overall climate where the plant typically grows.

**Output format**:
```markdown
**Köppen Zones**: Csb (Mediterranean warm summer)
```

See S1 Identity section for full climate type descriptions.

---

### 1. Cold Hardiness (Coldest Night of the Year)

**Data**: `TNn_q05` - the coldest night temperatures where the plant occurs (**Kelvin → °C**: subtract 273.15)

**What it measures**: The absolute coldest temperature populations have survived. This answers "will it survive my coldest winter night?"

**Range meaning**:
- **Coldest edge**: The coldest places where populations exist → maximum cold hardiness
- **Typical**: The typical coldest night the plant experiences
- **Warmest edge**: Mild winter populations (frost-free or nearly so)

**USDA Hardiness Zones**: We convert the coldest edge to standard zone numbers:
- Zone 5 = -28°C to -23°C
- Zone 6 = -23°C to -17°C
- Zone 7 = -17°C to -12°C
- Zone 8 = -12°C to -7°C
- Zone 9 = -7°C to -1°C
- Zone 10 = -1°C to 4°C

**Classification**:

| Coldest Night | Zone | Hardiness Level | What It Means |
|---------------|------|-----------------|---------------|
| Below -40°C | 2-3 | Extremely hardy | Survives severe continental winters |
| -40°C to -25°C | 4 | Very hardy | Reliable in cold climates |
| -25°C to -15°C | 5-6 | Cold-hardy | Survives hard frosts |
| -15°C to -5°C | 7-8 | Moderately hardy | Needs mulch in very cold areas |
| -5°C to 0°C | 9 | Half-hardy | Protect from hard frost |
| Above 0°C | 10+ | Frost-tender | Needs frost protection |

**Output format**:
```markdown
**Hardiness**: Zone 6 (-23°C) - Cold-hardy
```

This shows the zone, actual coldest temperature recorded, and simple hardiness description.

---

### 2. Average Winter Cold (Min Temperature of Coldest Month)

**Data**: `wc2.1_30s_bio_6_q05/q50/q95` - average overnight lows during winter (**°C × 10 → divide by 10**)

**What it measures**: The typical minimum temperature throughout the coldest month, NOT the coldest single night.

**Why it matters**: Shows if a plant needs prolonged cold for dormancy vs just surviving occasional frosts.

**Example**: A plant might survive -25°C cold snaps (coldest night) but typically experiences winters averaging -8°C (average coldest month). This tells you it's adapted to moderate winters but can handle occasional severe cold.

**Range meaning**:
- **Coldest edge**: Coldest average winter conditions where populations exist
- **Typical**: Most common winter regime
- **Warmest edge**: Mildest winter populations

**Typical winter regime**:

| Average Winter Low | Winter Type |
|--------------------|-------------|
| Below -20°C | Severe winters (nights average below -20°C all month) |
| -20°C to -10°C | Cold winters |
| -10°C to 0°C | Mild winters |
| 0°C to 5°C | Cool winters (frost occasional) |
| Above 5°C | Frost-free winters |

**Tolerance from coldest edge**:

| Coldest Winter Found | Cold Tolerance |
|----------------------|----------------|
| Below -25°C | Tolerates prolonged severe cold |
| -25°C to -15°C | Tolerates prolonged hard frost |
| -15°C to -5°C | Tolerates prolonged moderate frost |
| -5°C to 0°C | Tolerates prolonged light frost |
| Above 0°C | Limited frost tolerance |

**Optional output** (for detailed profiles):
```markdown
**Winter cold tolerance**: Average -18°C to -2°C (typical -8°C)
Typical winter: Mild winters with occasional frosts
Tolerance: Can handle winters averaging -15°C overnight
Note: For coldest single night, see Hardiness above
```

**Current implementation**: Not shown (hardiness zone covers most needs).

---

## Agroclimatic Indicators: Interpreting the Quantiles

For all agroclimatic variables below (FD, CFD, TR, DTR, GSL, WW), the quantiles show the range of conditions where the plant naturally occurs:

- **q05** (5th percentile): Lower edge - conditions in the mildest locations where the plant is found
- **q50** (50th percentile/median): Typical conditions - where most populations are found
- **q95** (95th percentile): Upper edge - conditions in the most extreme locations where the plant is found

**Key principle**: These values show **where the plant occurs in nature**, not strict requirements. The typical value (q50) shows the most common conditions, while the extremes (q05, q95) show the range of tolerance.

**Example**: GSL q50 = 210 days means the plant is typically found in locations with 210-day growing seasons. GSL q95 = 270 days shows it also occurs in locations with longer seasons (mild climates).

---

### 2a. Frost Days (Annual Frost Count)

**Data**: `FD_q05/q50/q95` - count of days per year with minimum temperature < 0°C

**What it measures**: How many days per year experience frost where the plant naturally occurs.

**Why it matters**: More intuitive than hardiness zones for understanding frost frequency. A plant might tolerate -20°C (zone 6) but the question is "how many frost days per year?"

**Range meaning**:
- **Fewest frost days** (q05): Populations in mildest locations
- **Typical** (q50): Where most populations are found
- **Most frost days** (q95): Populations in coldest locations

**Classification**:

| Annual Frost Days | Frost Regime | What It Means |
|-------------------|--------------|---------------|
| 0-10 days | Frost-free to occasional | Mediterranean/coastal climate |
| 10-30 days | Light frost season | Short, mild winters |
| 30-60 days | Moderate frost season | Typical temperate winter |
| 60-100 days | Long frost season | Cold temperate climate |
| 100-150 days | Very long frost season | Continental/boreal winter |
| Above 150 days | Extreme frost exposure | Alpine/arctic conditions |

**Garden interpretation**:

| Typical Frost Days | Winter Protection Needs |
|--------------------|------------------------|
| Below 20 | Minimal; survives most UK/European winters |
| 20-60 | Moderate; mulch in cold areas |
| 60-100 | Hardy; no protection needed in most regions |
| Above 100 | Extremely hardy; thrives in severe winters |

**Output format**:
```markdown
**Frost exposure**: 40-80 days/year (typical 60) - Moderate frost season
```

Shows typical frost day count and brief regime description.

---

### 2b. Consecutive Frost Days (Cold Spell Duration)

**Data**: `CFD_q05/q50/q95` - longest continuous frost period (days with Tmin < 0°C)

**What it measures**: The longest unbroken stretch of frost that populations experience, not just individual cold nights.

**Why it matters**: Shows tolerance for prolonged cold spells vs just individual frosts. Some plants survive occasional frosts but struggle with 2+ weeks of continuous freezing.

**Range meaning**:
- **Shortest cold spell** (q05): Populations with intermittent frost
- **Typical** (q50): Where most populations are found
- **Longest cold spell** (q95): Populations experiencing longest cold spells

**Classification**:

| Longest Cold Spell | Cold Spell Tolerance | Winter Type |
|--------------------|---------------------|-------------|
| 0-3 days | No prolonged frost | Intermittent frost only |
| 3-7 days | Short cold snaps | Brief cold spells |
| 7-14 days | 1-2 week freezes | Typical winter cold spells |
| 14-30 days | Extended freezing | Prolonged cold periods |
| 30-60 days | Long winter freeze | Continental deep winter |
| Above 60 days | Extreme prolonged cold | Arctic/alpine winters |

**Garden interpretation**:

| Maximum Cold Spell | Tolerance Level |
|-------------------|----------------|
| Below 7 days | Limited cold spell tolerance |
| 7-14 days | Handles typical winter cold snaps |
| 14-30 days | Tolerates extended freezing periods |
| Above 30 days | Extreme cold spell hardiness |

**Output format**:
```markdown
**Cold spell tolerance**: Up to 14 consecutive frost days - Typical winter cold snaps
```

---

### 3. Heat Tolerance (Hottest Day of the Year)

**Data**: `TXx_q95` - the hottest day temperatures where the plant occurs (**Kelvin → °C**: subtract 273.15)

**What it measures**: The absolute hottest temperature populations have survived. This answers "will it survive my hottest summer day?"

**Range meaning**:
- **Hottest edge**: The hottest places where populations exist → maximum heat tolerance
- **Typical**: The typical hottest day the plant experiences
- **Coolest edge**: Cool-summer populations

**Classification**:

| Hottest Day | Heat Tolerance | What It Means |
|-------------|----------------|---------------|
| Above 45°C | Extreme heat | Thrives in desert conditions |
| 40-45°C | Very heat-tolerant | Survives prolonged hot spells |
| 35-40°C | Heat-tolerant | Handles hot summers |
| 30-35°C | Moderate | Needs shade in extreme heat |
| Below 30°C | Cool-climate | Struggles in hot summers |

**Output format**:
```markdown
**Heat Tolerance**: Moderate (35°C max)
```

Shows the heat category and actual hottest temperature recorded.

---

### 3a. Tropical Nights (Warm Night Count)

**Data**: `TR_q05/q50/q95` - count of nights per year with minimum temperature > 20°C

**What it measures**: How many nights per year stay warm (above 20°C) where the plant occurs.

**Why it matters**: Warm nights affect plant respiration, pest pressure, and disease risk. High tropical night counts indicate:
- **Pest pressure**: Aphids, whiteflies, spider mites thrive in warm nights
- **Disease risk**: Combined with humidity, increases fungal/bacterial issues
- **Heat stress**: Plants can't cool down overnight

**Range meaning**:
- **Fewest tropical nights** (q05): Populations in coolest locations
- **Typical** (q50): Where most populations are found
- **Most tropical nights** (q95): Populations in warmest locations

**Classification**:

| Annual Tropical Nights | Night Temperature Regime | What It Means |
|------------------------|-------------------------|---------------|
| 0 days | Cool nights year-round | Temperate/boreal climate |
| 1-10 days | Occasional warm nights | Brief summer heat waves |
| 10-30 days | Regular warm nights | Warm temperate summer |
| 30-60 days | Frequent warm nights | Mediterranean/subtropical |
| 60-100 days | Hot summer nights | Subtropical climate |
| Above 100 days | Year-round warmth | Tropical/subtropical year-round |

**Garden implications**:

| Typical Tropical Nights | Pest/Disease Considerations |
|------------------------|----------------------------|
| 0-10 | Low pest pressure; cool-adapted |
| 10-30 | Moderate summer pest activity |
| 30-60 | High summer pest/disease pressure |
| Above 60 | Requires heat; high tropical pest/disease risk |

**Output format**:
```markdown
**Warm night exposure**: 15-40 nights/year (typical 25) - Moderate summer heat
*Note: Expect increased aphid/whitefly activity during warm spells*
```

---

### 3b. Diurnal Temperature Range (Day-Night Variation)

**Data**: `DTR_q05/q50/q95` - average difference between daily maximum and minimum temperatures (°C)

**What it measures**: How much temperature varies between day and night where the plant occurs.

**Why it matters**:
- **Growing conditions**: Wide swings (desert) vs stable (oceanic/tropical)
- **Climate type indicator**: Continental (large swings) vs maritime (small swings)
- **Stress tolerance**: Some plants need cool nights despite warm days

**Range meaning**:
- **Smallest swing** (q05): Populations in stable climates (maritime/tropical)
- **Typical** (q50): Where most populations are found
- **Largest swing** (q95): Populations in variable climates (continental/desert)

**Classification**:

| Diurnal Range | Climate Stability | Climate Type |
|---------------|------------------|--------------|
| Below 5°C | Very stable | Tropical/equatorial |
| 5-8°C | Stable | Oceanic/maritime |
| 8-12°C | Moderate variation | Temperate |
| 12-15°C | Large variation | Continental interior |
| Above 15°C | Extreme variation | Desert/high elevation |

**Stress implications**:

| Typical Range | Growing Conditions |
|--------------|-------------------|
| Below 8°C | Needs stable temperatures; struggles with rapid changes |
| 8-12°C | Tolerates typical temperate variation |
| Above 12°C | Adapted to large swings; may need cool nights |

**Output format**:
```markdown
**Temperature stability**: 8-12°C day-night swing (typical 10°C) - Temperate variation
```

---

### 3c. Growing Season Length

**Data**: `GSL_q05/q50/q95` - number of days per year with temperature suitable for growth

**What it measures**: The annual period when temperatures allow active growth. Typically calculated as consecutive days with temperature above 5°C (temperate species).

**Why it matters**: Critical for gardening success:
- **Planting window**: When to start seeds/plant out
- **Maturity timing**: Whether annuals can complete lifecycle
- **Perennial growth**: How much growing time for establishment

**Range meaning**:
- **Shortest season** (q05): Populations in coldest climates
- **Typical** (q50): Where most populations are found
- **Longest season** (q95): Populations in mildest climates

**Classification**:

| Growing Season Length | Season Type | What It Means |
|-----------------------|-------------|---------------|
| Below 90 days | Very short (alpine) | Only tough alpines; very limited growth |
| 90-150 days | Short (boreal/mountain) | Short season; quick-maturing varieties only |
| 150-210 days | Moderate (temperate) | Typical UK/Northern Europe season |
| 210-270 days | Long (warm temperate) | Extended season; good for most plants |
| 270-330 days | Very long (Mediterranean) | Nearly year-round growth possible |
| Above 330 days | Year-round (subtropical) | Continuous growth; frost-free |

**Garden timing implications**:

| Typical Growing Season | Planting Window |
|-----------------------|----------------|
| Below 120 days | Very late spring start; frost by early autumn |
| 120-180 days | April-October in UK; typical temperate season |
| 180-240 days | March-November; extended season |
| Above 240 days | Year-round or near year-round growth |

**Output format**:
```markdown
**Growing season**: 180-240 days (typical 210) - Long temperate season
*Active growth from April through October in typical UK conditions*
```

---

### 4. Average Summer Heat (Max Temperature of Warmest Month)

**Data**: `wc2.1_30s_bio_5_q05/q50/q95` - average daytime highs during summer (**°C × 10 → divide by 10**)

**What it measures**: The typical maximum temperature throughout the warmest month, NOT the hottest single day.

**Why it matters**: Shows adaptation to sustained summer heat vs just surviving heat waves.

**Example**: A plant might survive 38°C heat waves (hottest day) but typically experiences summers averaging 28°C (average warmest month). This tells you it's adapted to warm but not extreme conditions.

**Typical summer regime**:

| Average Summer High | Summer Type |
|---------------------|-------------|
| Above 35°C | Hot summers (days average above 35°C all month) |
| 28-35°C | Warm summers |
| 22-28°C | Mild summers |
| 15-22°C | Cool summers |
| Below 15°C | Cold summers (alpine/arctic) |

**Tolerance from hottest edge**:

| Hottest Summer Found | Heat Tolerance |
|----------------------|----------------|
| Above 38°C | Tolerates sustained high heat |
| Above 32°C | Tolerates sustained warm conditions |
| Above 26°C | Tolerates sustained mild heat |
| Above 20°C | Limited heat tolerance |
| Below 20°C | Cool-climate specialist |

**Optional output** (for detailed profiles):
```markdown
**Summer heat tolerance**: Average 22°C to 32°C (typical 28°C)
Typical summer: Warm summer days
Tolerance: Can handle summers averaging 32°C daytime
```

**Current implementation**: Not shown (hottest day covers most needs).

---

### 5. Temperature Preference (Ecological Indicator)

**Data**: `EIVEres-T_complete` (0-10 scale)

**What it means**: Where the plant is most competitive and successful in natural plant communities, based on vegetation science.

**Difference from climate data**:
- **Climate range**: The actual temperatures where it can survive
- **Ecological indicator**: Where it performs best and outcompetes other plants

**Scale**:

| Score | Climate Type |
|-------|--------------|
| 0-2 | Arctic-alpine; needs cool summers |
| 2-4 | Boreal/mountain; cool temperate |
| 4-6 | Temperate; typical UK/Northern Europe |
| 6-8 | Warm temperate; Mediterranean margin |
| 8-10 | Subtropical; needs warm conditions |

**How to interpret together**: Compare the ecological score with the actual temperature range. If they match → high confidence. If the score is warmer than the range → the plant can survive cold but prefers warmth.

**Output format**:
```markdown
**Temperature preference**: 5.2/10 - Temperate climate
```

---

## Moisture and Rainfall

### 6. Annual Rainfall (Where It Grows)

**Data**: `wc2.1_30s_bio_12_q05/q50/q95` - Annual Precipitation (mm)

**What it measures**: The total yearly rainfall where the plant naturally occurs.

**Range meaning**:
- **Driest edge**: Driest places where populations exist → drought tolerance
- **Typical**: Most common rainfall amount
- **Wettest edge**: Wettest places → tolerance for wet conditions

**Rainfall types** (from typical conditions):

| Annual Rainfall | Climate Type |
|-----------------|--------------|
| Below 250mm | Arid (desert) |
| 250-500mm | Semi-arid (steppe) |
| 500-1000mm | Temperate (most European climates) |
| 1000-1500mm | Moist |
| Above 1500mm | Wet (tropical/oceanic) |

**Drought tolerance** (from driest edge):

| Driest Conditions | Drought Tolerance |
|-------------------|-------------------|
| Below 200mm | Drought-tolerant (survives very dry conditions) |
| 200-400mm | Moderate drought tolerance |
| 400-600mm | Limited drought tolerance |
| Above 600mm | Needs consistent moisture |

**Output format**:
```markdown
- Annual rainfall: 600-1200mm (typical 850mm)
```

Shows the range of rainfall where it occurs, with typical amount.

---

### 7. Drought Tolerance (Longest Dry Spells)

**Data**: `CDD_q05/q50/q95` - Consecutive Dry Days (count of days with no rain)

**What it measures**: The longest continuous period without rain that populations experience.

**Why it matters**: More relevant than yearly totals for understanding drought stress. A plant might get 1000mm annually but struggle if it all comes in winter.

**Range meaning**:
- **Longest dry spell**: Maximum drought period where populations exist → dry spell tolerance
- **Typical**: Most common dry spell length
- **Shortest**: Always-moist populations

**Classification**:

| Longest Dry Spell | Drought Tolerance | Watering Needs |
|-------------------|-------------------|----------------|
| Above 60 days | High (>2 months dry) | Deep watering occasionally once established |
| 30-60 days | Moderate (1-2 months) | Water during extended dry spells |
| 14-30 days | Limited (2-4 weeks) | Regular watering in dry weather |
| Below 14 days | Low (needs regular moisture) | Keep soil moist; don't let dry out |

**Output format**:
```markdown
- Drought tolerance: Limited (needs summer moisture)
```

Simple drought category based on longest dry spell tolerated.

---

### 7a. Warm-Wet Days (Disease Risk Indicator)

**Data**: `WW_q05/q50/q95` - count of days per year with both warm temperatures (>10°C) AND wet conditions (rainfall)

**What it measures**: How many days combine warmth and moisture where the plant occurs.

**Why it matters**: Warm-wet conditions are critical for:
- **Fungal diseases**: Powdery mildew, rust, blight thrive in warm-humid conditions
- **Bacterial diseases**: Soft rot, bacterial spot spread rapidly
- **Pest activity**: Slugs, snails, aphids peak during warm-wet periods
- **Plant adaptation**: High WW populations may have disease resistance

**Range meaning**:
- **Fewest warm-wet days** (q05): Populations in drier or cooler locations
- **Typical** (q50): Where most populations are found
- **Most warm-wet days** (q95): Populations in warm-humid locations (may have disease resistance)

**Classification**:

| Annual Warm-Wet Days | Disease Pressure | What It Means |
|---------------------|------------------|---------------|
| Below 50 days | Very low | Arid/continental dry climate |
| 50-100 days | Low | Mediterranean/dry temperate |
| 100-150 days | Moderate | Typical temperate (UK/Northern Europe) |
| 150-200 days | High | Oceanic/humid temperate |
| 200-250 days | Very high | Wet oceanic/subtropical |
| Above 250 days | Extreme | Tropical/monsoon conditions |

**Garden disease implications**:

| Typical Warm-Wet Days | Disease Risk | Prevention Needs |
|----------------------|--------------|-----------------|
| Below 80 | Low disease pressure | Minimal; good air circulation |
| 80-150 | Moderate risk | Standard spacing; remove debris |
| 150-200 | High disease pressure | Wide spacing; preventive sprays; resistant varieties |
| Above 200 | Very high risk | Must have disease resistance; aggressive prevention |

**Adaptation indicator**:
- **Plant from high WW areas**: Likely has evolved disease resistance; good for humid gardens
- **Plant from low WW areas**: May be disease-prone in humid climates; needs dry conditions or protection

**Output format**:
```markdown
- Warm-wet exposure: 120-180 days/year (typical 150) - Moderate to high disease pressure
*Ensure good air circulation; monitor for powdery mildew and rust during humid periods*
```

---

### 8. Moisture Preference (Ecological Indicator)

**Data**: `EIVEres-M_complete` (0-10 scale)

**What it means**: The soil moisture level where the plant is most competitive, based on vegetation science.

**Difference from rainfall data**:
- **Rainfall data**: Actual precipitation where it survives
- **Ecological indicator**: Soil moisture preference where it thrives

**Scale**:

| Score | Moisture Level | Where It Grows Best | Watering |
|-------|----------------|---------------------|----------|
| 1-2 | Extreme drought tolerance | Very dry sites | Minimal; allow to dry completely |
| 3-4 | Dry conditions | Dry sites | Sparse; weekly in drought |
| 5-6 | Moderate moisture | Average garden soil | Regular; 1-2 times weekly |
| 7-8 | Moist conditions | Damp soil | Frequent; keep moist |
| 9-11 | Wet/waterlogged | Bog, pond margin | Constant moisture needed |

**How to interpret together**: A plant with rainfall 400-1200mm (wide tolerance) but moisture score 4 (dry preference) can survive moderate rainfall but competes best in drier conditions.

**Output format**:
```markdown
- Moisture preference: 5.5/10 - Moderate moisture needs
- Watering: Regular in dry spells; don't let dry out completely
```

---

## Soil

### Understanding Soil Data

**All soil data come from where plants naturally grow**, extracted from SoilGrids database at each occurrence location.

**Depth**: We use topsoil (0-5cm deep) - most relevant for gardening. Deeper layers available for trees if needed.

**Range meaning**: Same as climate - typical conditions where most common, extremes showing tolerance limits.

---

### 9. Soil pH (Acidity/Alkalinity)

**Data**: `phh2o_0_5cm_q05/q50/q95` - soil pH (**×10 in data; divide by 10 for actual pH**)

**What it measures**: How acidic or alkaline the soil is (pH scale 0-14).

**Why it matters**: Some plants (like rhododendrons) need acid soil and die in alkaline conditions. Others (like clematis) prefer alkaline soil.

**Range meaning**:
- **Most acidic**: Most acidic soils where populations exist → acid tolerance
- **Typical**: Most common pH (ecological optimum)
- **Most alkaline**: Most alkaline soils → alkaline tolerance
- **Range width**: How fussy it is (wide = adaptable, narrow = specific needs)

**Typical pH regime**:

| Typical pH | Soil Type |
|-----------|-----------|
| Below 5.0 | Strongly acidic (calcifuge plants only) |
| 5.0-5.5 | Moderately acidic |
| 5.5-6.5 | Slightly acidic |
| 6.5-7.5 | Neutral |
| 7.5-8.0 | Slightly alkaline |
| Above 8.0 | Alkaline/chalky (calcicole plants) |

**Acid tolerance** (from most acidic edge):

| Most Acidic | Acid Tolerance |
|-------------|----------------|
| Below 4.5 | Tolerates very acidic soils |
| 4.5-5.0 | Tolerates strongly acidic |
| 5.0-5.5 | Tolerates moderately acidic |
| 5.5-6.0 | Tolerates slightly acidic |
| Above 6.0 | Limited acid tolerance |

**Alkaline tolerance** (from most alkaline edge):

| Most Alkaline | Alkaline Tolerance |
|---------------|-------------------|
| Above 8.5 | Tolerates strongly alkaline |
| 8.0-8.5 | Tolerates alkaline/chalky soils |
| 7.5-8.0 | Tolerates slightly alkaline |
| 7.0-7.5 | Tolerates neutral to slightly alkaline |
| Below 7.0 | Limited alkaline tolerance |

**pH flexibility**:

| pH Range | Flexibility |
|----------|-------------|
| Above 2.0 units | Wide tolerance; adaptable to most gardens |
| 1.0-2.0 units | Moderate flexibility |
| Below 1.0 units | Narrow preference; match pH carefully |

**Output format**:
```markdown
**pH**: 5.8-7.2 (typical 6.4) - Slightly acidic to neutral
```

---

### 10. pH Preference (Ecological Indicator)

**Data**: `EIVEres-R_complete` (0-10 scale, "R" = Reaction)

**What it means**: The soil pH where the plant is most competitive.

**Difference from pH range**:
- **pH range**: What pH it can survive in
- **Ecological indicator**: What pH it prefers and thrives in

**Scale**:

| Score | pH Preference | Compost Type |
|-------|---------------|--------------|
| 1-2 | Strongly acidic (calcifuge) | Ericaceous compost required; avoid lime |
| 3-4 | Moderately acidic | Acidic to neutral compost |
| 5-6 | Slightly acidic to neutral | Standard multi-purpose compost |
| 7 | Neutral | Any compost; very adaptable |
| 8-9 | Alkaline (calcicole) | Lime-loving; add chalk if needed |

**How to interpret together**: A plant with pH range 4.5-8.0 (wide tolerance) but indicator score 3 (acid preference) CAN survive in neutral soil but will be outcompeted by plants that prefer those conditions. Best performance in acidic soil.

**Output format**:
```markdown
**pH preference**: 5.8/10 - Slightly acidic to neutral
*Standard multipurpose compost works well.*
```

---

### 11. Soil Fertility (Nutrient-Holding Capacity)

**Data**: `cec_0_5cm_q05/q50/q95` - CEC (Cation Exchange Capacity) in cmol(+)/kg

**What it measures**: How well the soil holds onto nutrients:
- **High CEC** (clay, organic-rich soil): Holds nutrients well
- **Low CEC** (sandy soil): Nutrients wash away quickly

**Range meaning**:
- **Lowest**: Poorest soils where populations exist
- **Typical**: Most common fertility level
- **Highest**: Richest soils tolerated

**Fertility levels** (from typical):

| CEC Value | Fertility Level |
|-----------|-----------------|
| Below 5 | Very low (very sandy or leached) |
| 5-10 | Low (sandy soils) |
| 10-20 | Moderate (typical garden soil) |
| 20-30 | Fertile (clay loam, good organic matter) |
| Above 30 | Very fertile (heavy clay, peat) |

**Output format**:
```markdown
**Fertility**: Moderate (CEC 15 cmol/kg)
```

---

### 12. Nutrient Preference (Ecological Indicator)

**Data**: `EIVEres-N_complete` (0-10 scale, "N" = Nitrogen/nutrients)

**What it means**: The soil fertility level where the plant is most competitive.

**Difference from CEC**:
- **CEC**: Actual nutrient-holding capacity of soil
- **Ecological indicator**: Fertility preference for growth

**Scale**:

| Score | Fertility Preference | Feeding Schedule |
|-------|---------------------|------------------|
| 1-2 | Very low (oligotrophic) | No feeding; fertilizer causes weak growth |
| 3-4 | Low | Light annual feed; avoid excess nitrogen |
| 5-6 | Moderate | Standard annual feeding in spring |
| 7-8 | High | Heavy feeder; monthly feed in growing season |
| 9 | Very high (eutrophic) | Very heavy feeder; weekly liquid feed |

**Output format**:
```markdown
**Nutrient preference**: 5.0/10 - Moderate
*Standard annual feeding in spring.*
```

---

### 13. Soil Texture (Clay and Sand)

**Data**: `clay_0_5cm_q05/q50/q95` and `sand_0_5cm_q05/q50/q95` - percentages

**What it measures**: The physical structure of soil:
- **Sand**: Drains fast, low nutrients
- **Clay**: Drains slowly, holds nutrients, heavy
- **Loam**: Mix of both - ideal

**Effects of texture**:
- **Drainage**: Sandy fast, clay slow
- **Aeration**: Sandy well-aerated, clay can be airless when wet
- **Nutrients**: Clay holds, sand loses
- **Workability**: Loam easy, heavy clay difficult

**Typical texture** (from typical clay percentage):

| Clay % | Typical Texture |
|--------|-----------------|
| Above 35 | Heavy clay |
| 25-35 | Clay loam |
| 15-25 | Loam |
| Below 15 | Sandy loam/sand |

**Heavy soil tolerance** (from highest clay):

| Highest Clay | Heavy Soil Tolerance |
|--------------|----------------------|
| Above 45% | Tolerates heavy clay |
| 35-45% | Tolerates clay soils |
| 25-35% | Moderate clay tolerance |
| Below 25% | Limited clay tolerance |

**Light soil tolerance** (from highest sand):

| Highest Sand | Light Soil Tolerance |
|--------------|---------------------|
| Above 80% | Tolerates very sandy soils |
| 65-80% | Tolerates sandy soils |
| 50-65% | Moderate sand tolerance |
| Below 50% | Limited sand tolerance |

**Output format**:
```markdown
**Texture**: Loam preferred; tolerates clay
```

---

## Encyclopedia Output Format

**Standard format** (what gets displayed):

```markdown
## Growing Requirements

### Light
**Light**: 6.5/10 - Full sun to part shade
Open borders work well; tolerates some afternoon shade.

### Climate
**Köppen Zones**: Cfb (Temperate oceanic)
**Hardiness**: Zone 6 (-23°C) - Cold-hardy
**Frost exposure**: 40-80 days/year (typical 60) - Moderate frost season
**Cold spell tolerance**: Up to 14 consecutive frost days - Typical winter cold snaps
**Heat Tolerance**: Moderate (35°C max)
**Warm night exposure**: 15-40 nights/year (typical 25) - Moderate summer heat
*Note: Expect increased aphid/whitefly activity during warm spells*
**Temperature stability**: 8-12°C day-night swing (typical 10°C) - Temperate variation
**Growing season**: 180-240 days (typical 210) - Long temperate season
*Active growth from April through October in typical UK conditions*
**Temperature preference**: 5.2/10 - Temperate climate

**Moisture**:
- Annual rainfall: 600-1200mm (typical 850mm)
- Drought tolerance: Limited (needs summer moisture)
- Warm-wet exposure: 120-180 days/year (typical 150) - Moderate to high disease pressure
  *Ensure good air circulation; monitor for powdery mildew and rust during humid periods*
- Moisture preference: 5.5/10 - Moderate moisture needs
- Watering: Regular in dry spells; don't let dry out completely

### Soil
**pH**: 5.8-7.2 (typical 6.4) - Slightly acidic to neutral
**pH preference**: 5.8/10 - Slightly acidic to neutral
*Standard multipurpose compost works well.*
**Fertility**: Moderate (CEC 15 cmol/kg)
**Nutrient preference**: 5.0/10 - Moderate
*Standard annual feeding in spring.*
**Texture**: Loam preferred; tolerates clay
```

**Concise format** (for briefer profiles, omit some details):
- Can omit: Cold spell tolerance, Warm night exposure, Temperature stability if space is limited
- Always include: Hardiness, Heat tolerance, Growing season, Drought tolerance, Warm-wet exposure

This enriched format provides comprehensive practical information for gardeners.

---

## Data Column Reference

**Climate**:
- `TNn_q05/q50/q95` - Coldest night temperatures (**Kelvin → °C**: subtract 273.15)
- `TXx_q05/q50/q95` - Hottest day temperatures (**Kelvin → °C**: subtract 273.15)
- `wc2.1_30s_bio_1_q05/q50/q95` - Annual Mean Temperature (**°C × 10**: divide by 10)
- `wc2.1_30s_bio_4_q05/q50/q95` - Temperature Seasonality (std dev × 100)
- `wc2.1_30s_bio_5_q05/q50/q95` - Max Temperature of Warmest Month (**°C × 10**: divide by 10)
- `wc2.1_30s_bio_6_q05/q50/q95` - Min Temperature of Coldest Month (**°C × 10**: divide by 10)
- `wc2.1_30s_bio_12_q05/q50/q95` - Annual Precipitation (mm)
- `wc2.1_30s_bio_14_q05/q50/q95` - Precipitation of Driest Month (mm)
- `wc2.1_30s_bio_17_q05/q50/q95` - Precipitation of Driest Quarter (mm)
- `wc2.1_30s_bio_18_q05/q50/q95` - Precipitation of Warmest Quarter (mm)
- `top_zone_code` - Köppen-Geiger climate zone

**Agroclimatic indicators** (NEW - high-value additions):
- `FD_q05/q50/q95` - Frost Days per year (count, Tmin < 0°C)
- `CFD_q05/q50/q95` - Consecutive Frost Days (longest cold spell, days)
- `TR_q05/q50/q95` - Tropical Nights per year (count, Tmin > 20°C)
- `DTR_q05/q50/q95` - Diurnal Temperature Range (°C day-night variation)
- `GSL_q05/q50/q95` - Growing Season Length (days per year)
- `CDD_q05/q50/q95` - Consecutive Dry Days (drought spell, count)
- `WW_q05/q50/q95` - Warm-Wet Days per year (count, disease risk indicator)

**Additional agroclimatic variables** (available but lower priority):
- `ID_q05/q50/q95` - Ice Days per year (count, Tmax < 0°C) - extreme frost
- `SU_q05/q50/q95` - Summer Days per year (count, Tmax > 25°C) - heat stress
- `CSDI_q05/q50/q95` - Cold-Spell Duration Index (prolonged cold stress)
- `WSDI_q05/q50/q95` - Warm-Spell Duration Index (prolonged heat stress)
- `CSU_q05/q50/q95` - Consecutive Summer Days (hot spell duration)
- `CWD_q05/q50/q95` - Consecutive Wet Days (waterlogging risk)
- `BEDD_q05/q50/q95` - Biologically Effective Degree Days (growth rate)
- `R10mm_q05/q50/q95` - Heavy precipitation days (>10mm, count)
- `R20mm_q05/q50/q95` - Very heavy precipitation days (>20mm, count)
- `SDII_q05/q50/q95` - Simple Daily Intensity Index (precipitation intensity)

**Soil** (0-5cm topsoil):
- `phh2o_0_5cm_q05/q50/q95` - Soil pH (**×10**: divide by 10)
- `clay_0_5cm_q05/q50/q95` - Clay percentage (%)
- `sand_0_5cm_q05/q50/q95` - Sand percentage (%)
- `cec_0_5cm_q05/q50/q95` - Cation Exchange Capacity (cmol/kg)
- `soc_0_5cm_q05/q50/q95` - Soil Organic Carbon (g/kg)
- `nitrogen_0_5cm_q05/q50/q95` - Total Soil Nitrogen (g/kg)

**Ecological indicators**:
- `EIVEres-L_complete` - Light (0-10)
- `EIVEres-M_complete` - Moisture (0-10)
- `EIVEres-T_complete` - Temperature (0-10)
- `EIVEres-R_complete` - Reaction/pH (0-10)
- `EIVEres-N_complete` - Nitrogen/Fertility (0-10)

---

## Code Implementation Notes

### Temperature Conversions (CRITICAL)

Different variables use different units:

1. **TNn, TXx**: Stored as **Kelvin** → subtract 273.15 for Celsius
2. **BIO variables**: Stored as **°C × 10** → divide by 10
3. **pH**: Stored as **pH × 10** → divide by 10

**Example**:
```rust
// Coldest night: Kelvin to Celsius
let tnn_k = get_f64(data, "TNn_q05"); // 248.15 K
let tnn_c = tnn_k.map(|k| k - 273.15); // -25.0 °C

// Winter average: °C × 10 to °C
let bio6 = get_f64(data, "wc2.1_30s_bio_6_q05"); // -180.0
let bio6_c = bio6.map(|v| v / 10.0); // -18.0 °C

// pH: pH × 10 to actual pH
let ph = get_f64(data, "phh2o_0_5cm_q50"); // 64.0
let ph_actual = ph.map(|v| v / 10.0); // 6.4
```

### Current Implementation Status

**Already implemented** (Phase 1):
- Köppen zones
- Hardiness zones with simple descriptions (TNn_q05)
- Heat tolerance categories (TXx_q95)
- Drought tolerance (CDD_q95)
- Ecological indicators (EIVE-L, T, M, R, N)
- Annual precipitation (BIO12)
- pH and fertility ranges
- Soil texture

**High-priority additions** (Phase 2 - NEW in this spec):
- **FD** (Frost Days) - More intuitive than hardiness zones
- **CFD** (Consecutive Frost Days) - Cold spell risk
- **TR** (Tropical Nights) - Pest pressure indicator
- **DTR** (Diurnal Temperature Range) - Climate stability
- **GSL** (Growing Season Length) - Critical planting window info
- **WW** (Warm-Wet Days) - Disease risk indicator

**Lower priority** (Phase 3 - optional enhancements):
- Average winter cold (BIO6) - less intuitive than hardiness
- Average summer heat (BIO5) - less intuitive than TXx
- ID (Ice Days) - extreme frost metric
- SU (Summer Days) - heat stress metric
- CSDI/WSDI (Cold/Warm Spell Indices) - advanced metrics
- CSU/CWD (Consecutive Summer/Wet Days) - specialized metrics
- BEDD (Biologically Effective Degree Days) - technical metric
- R10mm/R20mm/SDII (Precipitation intensity) - advanced rainfall metrics

### Implementation Priority Rationale

**Why Phase 2 variables are high-value**:
1. **FD** - "60 frost days/year" is clearer than "Zone 6" for most gardeners
2. **GSL** - "210-day growing season" directly answers "when can I plant?"
3. **WW** - Directly predicts disease pressure (mildew, rust, blight)
4. **TR** - Predicts pest pressure (aphids, whiteflies)
5. **CFD** - Shows cold spell endurance vs just single-night tolerance
6. **DTR** - Maritime (stable) vs continental (variable) climate

**These 6 variables add significant practical value with minimal complexity.**
