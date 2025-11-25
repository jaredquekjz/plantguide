# S2: Growing Requirements Rules

Rules for generating the growing requirements section, integrating climate envelope, soil envelope, and EIVE indicators.

## Principle: Triangulation

Present **both** occurrence-based perspectives together:
- **Environmental envelope** (WorldClim/SoilGrids): Quantitative tolerance limits
- **EIVE indicators**: Competitive optimum on 0-10 scale

When sources agree → high confidence. When they diverge → plant survives broadly but thrives in preferred conditions.

---

## Light Requirements

**Primary source**: EIVE-L only (no environmental envelope equivalent)

### EIVE-L Translation (`EIVEres-L`)

| EIVE-L | Category | Garden Advice |
|--------|----------|---------------|
| 0-2 | Deep shade | North-facing, woodland floor, shade garden |
| 2-4 | Shade | Under tree canopy, north/east-facing borders |
| 4-6 | Partial shade | Dappled light, morning sun, woodland edge |
| 6-8 | Full sun to part shade | Open borders, some afternoon shade acceptable |
| 8-10 | Full sun | South-facing, open positions, no shade |

**Output format**:
```
**Light**: {EIVE-L value}/10 - {category}
{garden_advice}
```

---

## Climate Conditions

### Temperature

#### Cold Hardiness (TNn_q05 - absolute minimum)

| TNn_q05 (°C) | USDA Zone | Advice |
|--------------|-----------|--------|
| < -40 | 2-3 | Extremely hardy; survives severe continental winters |
| -40 to -25 | 4 | Very hardy; reliable in cold temperate |
| -25 to -15 | 5-6 | Cold-hardy; survives hard frosts |
| -15 to -5 | 7-8 | Moderately hardy; mulch roots in cold areas |
| -5 to 0 | 9 | Half-hardy; protect from hard frost |
| > 0 | 10+ | Frost-tender; requires frost protection |

#### Chronic Cold Exposure (BIO_6 - monthly average)

| BIO_6_q05 (°C) | Interpretation |
|----------------|----------------|
| < -25 | Tolerates prolonged severe cold |
| -25 to -15 | Tolerates prolonged hard frost |
| -15 to -5 | Tolerates prolonged moderate frost |
| -5 to 0 | Tolerates prolonged light frost |
| > 0 | Limited frost tolerance |

#### Heat Tolerance (TXx_q95 - absolute maximum)

| TXx_q95 (°C) | Category | Advice |
|--------------|----------|--------|
| > 45 | Extreme heat | Thrives in desert conditions |
| 40-45 | Very heat-tolerant | Survives prolonged hot spells |
| 35-40 | Heat-tolerant | Tolerates hot summers |
| 30-35 | Moderate | Shade in extreme heat |
| < 30 | Cool-climate | Struggles in hot summers; shade essential |

#### EIVE-T Integration

| EIVE-T | Climate Type |
|--------|--------------|
| 0-2 | Arctic-alpine; cool summers essential |
| 2-4 | Boreal/montane; cool temperate |
| 4-6 | Temperate; typical UK/NW Europe |
| 6-8 | Warm temperate; Mediterranean margin |
| 8-10 | Subtropical; warm conditions preferred |

**Triangulation**: Compare EIVE-T with actual temperature ranges. Agreement = confidence.

### Moisture/Precipitation

#### Annual Precipitation (BIO_12)

| BIO_12_q05 (mm) | Drought Tolerance |
|-----------------|-------------------|
| < 200 | Drought-tolerant (survives arid conditions) |
| 200-400 | Moderate drought tolerance |
| 400-600 | Limited drought tolerance |
| > 600 | Requires consistent moisture |

#### Drought Spell Duration (CDD_q95)

| CDD_q95 (days) | Interpretation |
|----------------|----------------|
| > 60 | Tolerates extended drought (>2 months) |
| 30-60 | Tolerates moderate dry spells |
| 14-30 | Limited drought tolerance |
| < 14 | Requires regular moisture |

#### EIVE-M Integration

| EIVE-M | Moisture Regime | Watering Advice |
|--------|-----------------|-----------------|
| 0-2 | Extreme drought tolerance | Water sparingly; overwatering harmful |
| 2-4 | Dry conditions preferred | Deep infrequent watering |
| 4-6 | Moderate moisture | Regular watering in dry spells |
| 6-8 | Moist conditions preferred | Keep soil moist; don't let dry out |
| 8-10 | Wet/waterlogged tolerance | Bog garden, pond margins, wet soil |

**Triangulation**: EIVE-M shows competitive optimum; envelope shows survival range.

### Seasonality (BIO_4)

| BIO_4_q50 | Climate Type | Advice |
|-----------|--------------|--------|
| < 200 | Oceanic/tropical | May struggle with extreme seasons |
| 200-400 | Maritime temperate | Suits coastal/mild gardens |
| 400-600 | Transitional | Adaptable to moderate seasons |
| 600-800 | Continental | Tolerates hot summers, cold winters |
| > 800 | Extreme continental | Adapted to wide temperature swings |

---

## Soil Conditions

### pH/Reaction

#### Environmental Envelope (phh2o_0_5cm)

| pH_q50 | Typical Regime |
|--------|----------------|
| < 5.0 | Strongly acid soils (calcifuge) |
| 5.0-5.5 | Moderately acid |
| 5.5-6.5 | Slightly acid |
| 6.5-7.5 | Neutral |
| 7.5-8.0 | Slightly alkaline |
| > 8.0 | Calcareous/alkaline (calcicole) |

| pH_q05 | Acid Tolerance |
|--------|----------------|
| < 4.5 | Tolerates very acid soils |
| 4.5-5.0 | Tolerates strongly acid soils |
| 5.0-5.5 | Tolerates moderately acid soils |
| > 5.5 | Limited acid tolerance |

| pH_q95 | Alkaline Tolerance |
|--------|-------------------|
| > 8.5 | Tolerates strongly alkaline |
| 8.0-8.5 | Tolerates alkaline/calcareous |
| 7.5-8.0 | Tolerates slightly alkaline |
| < 7.5 | Limited alkaline tolerance |

#### EIVE-R Integration

| EIVE-R | Soil Reaction | Compost Advice |
|--------|---------------|----------------|
| 0-2 | Strongly acidic (calcifuge) | Ericaceous compost required; avoid lime |
| 2-4 | Moderately acidic | Acidic to neutral compost |
| 4-6 | Slightly acidic to neutral | Standard multipurpose compost |
| 6-8 | Neutral to slightly alkaline | Tolerates some lime |
| 8-10 | Calcareous/alkaline (calcicole) | Lime-loving; add chalk if needed |

**Triangulation**: Strong agreement (both show acid preference) = high confidence for ericaceous requirement.

### Nitrogen/Fertility

#### Environmental Envelope (nitrogen_0_5cm, cec_0_5cm)

| N_q50 (g/kg) | Typical Regime |
|--------------|----------------|
| < 1.0 | Very low nitrogen |
| 1.0-2.0 | Low nitrogen |
| 2.0-4.0 | Moderate nitrogen |
| 4.0-8.0 | Nitrogen-rich |
| > 8.0 | Very high nitrogen |

| CEC_q50 (cmol/kg) | Soil Fertility |
|-------------------|----------------|
| < 5 | Very low fertility |
| 5-10 | Low fertility |
| 10-20 | Moderate fertility |
| 20-30 | Fertile |
| > 30 | Very fertile |

#### EIVE-N Integration

| EIVE-N | Fertility Preference | Feeding Advice |
|--------|---------------------|----------------|
| 0-2 | Oligotrophic (infertile) | Light feeding only; excess N harmful |
| 2-4 | Low nutrient | Minimal feeding; balanced NPK |
| 4-6 | Moderate nutrient | Standard annual feeding |
| 6-8 | High nutrient | Benefits from generous feeding |
| 8-10 | Eutrophic (manure-rich) | Heavy feeder; responds well to manure |

### Texture (clay/sand percentages)

| Clay_q50 (%) | Typical Texture |
|--------------|-----------------|
| > 35 | Heavy clay |
| 25-35 | Clay loam |
| 15-25 | Loam |
| < 15 | Sandy loam/sand |

| Sand_q95 (%) | Light Soil Tolerance |
|--------------|---------------------|
| > 80 | Tolerates very sandy |
| 65-80 | Tolerates sandy |
| 50-65 | Moderate sand tolerance |
| < 50 | Prefers heavier soils |

### Organic Matter (SOC)

| SOC_q50 (g/kg) | Organic Preference |
|----------------|-------------------|
| < 10 | Mineral soils (lean) |
| 10-20 | Low-moderate organic |
| 20-40 | Humus-rich |
| 40-100 | Highly organic |
| > 100 | Peaty/organic |

---

## Output Format

```markdown
## Growing Requirements

### Light
**EIVE-L**: 6.5/10 - Full sun to part shade
Open borders work well; tolerates some afternoon shade.

### Climate
**Köppen Zones**: Cfb (Temperate oceanic)
**Hardiness**: Zone 6 (-23°C) - Cold-hardy
**Heat Tolerance**: Moderate (35°C max)
**EIVE-T**: 5.2/10 - Temperate climate preference

**Moisture**:
- Annual rainfall: 600-1200mm (median 850mm)
- Drought tolerance: Limited (needs summer moisture)
- EIVE-M: 5.5/10 - Moderate moisture needs
- Watering: Regular in dry spells; don't let dry out completely

### Soil
**pH**: 5.8-7.2 (median 6.4) - Slightly acidic to neutral
**EIVE-R**: 5.8/10 - Standard compost suitable
**Fertility**: Moderate (CEC 15 cmol/kg)
**EIVE-N**: 5.0/10 - Standard annual feeding
**Texture**: Loam preferred; tolerates clay
```

---

## Data Column Reference

**Climate envelope**:
- `TNn_q05/q50/q95` - Absolute minimum temperature
- `TXx_q05/q50/q95` - Absolute maximum temperature
- `wc2.1_30s_bio_5_*` - Max temp warmest month
- `wc2.1_30s_bio_6_*` - Min temp coldest month
- `wc2.1_30s_bio_4_*` - Temperature seasonality
- `wc2.1_30s_bio_12_*` - Annual precipitation
- `wc2.1_30s_bio_14_*` - Precipitation driest month
- `CDD_q05/q50/q95` - Consecutive dry days

**Soil envelope** (0-5cm depth):
- `phh2o_0_5cm_q05/q50/q95` - Soil pH (×10 in raw data)
- `clay_0_5cm_q05/q50/q95` - Clay percentage
- `sand_0_5cm_q05/q50/q95` - Sand percentage
- `cec_0_5cm_q05/q50/q95` - Cation exchange capacity
- `soc_0_5cm_q05/q50/q95` - Soil organic carbon
- `nitrogen_0_5cm_q05/q50/q95` - Soil nitrogen

**EIVE**:
- `EIVEres-L` - Light (0-10)
- `EIVEres-M` - Moisture (0-10)
- `EIVEres-T` - Temperature (0-10)
- `EIVEres-R` - Reaction/pH (0-10)
- `EIVEres-N` - Nitrogen (0-10)
