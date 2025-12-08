# S4: Ecosystem Services

**Source**: `stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet` (Dec 6 2024)

## Data Columns

### Pre-calculated Ratings (5-level: Very High / High / Moderate / Low / Very Low)

| Column | Service |
|--------|---------|
| `npp_rating` | Net Primary Productivity |
| `decomposition_rating` | Decomposition rate |
| `nutrient_cycling_rating` | Nutrient cycling efficiency |
| `nutrient_retention_rating` | Nutrient retention |
| `nutrient_loss_rating` | Nutrient loss risk |
| `carbon_storage_rating` | Carbon storage (height-based) |
| `leaf_carbon_recalcitrant_rating` | Long-term carbon in leaves |
| `erosion_protection_rating` | Erosion protection |
| `nitrogen_fixation_rating` | Nitrogen fixation |

---

## Derivation Formulas (Shipley 2025)

### Height-Based Services (Niklas & Enquist 2001)

| Service | Formula | Interpretation |
|---------|---------|----------------|
| NPP | H^2.837 | Taller plants produce more biomass per year |
| Carbon Storage | H^3.788 | Taller plants store more carbon in woody tissue |

### CSR-Based Services (Pierce et al. 2017)

| Service | Score | Interpretation |
|---------|-------|----------------|
| Decomposition | max(R, C) | Fast-growing strategies decompose quickly |
| Nutrient Cycling | max(R, C) | Same as decomposition |
| Nutrient Retention | C-score | Competitors retain nutrients |
| Nutrient Loss Risk | R-score | Ruderals release nutrients quickly |
| Recalcitrant Carbon | S-score | Stress-tolerators have tough, persistent tissues |
| Erosion Protection | C-score | Competitors have dense root systems |

### Nitrogen Fixation

Based on TRY Database TraitID 8 (nitrogen fixation capacity). Each TRY record is classified as YES/NO, then aggregated per species.

#### Raw TRY Ratings → Display Labels

| Raw Rating | % Yes in TRY | Display Label | Color |
|------------|--------------|---------------|-------|
| High | ≥75% | **Yes** | Emerald |
| Moderate-High | 50-74% | **Likely** | Emerald |
| Moderate-Low | 25-49% | **Uncertain** | Amber |
| Low | <25% | **No** | Grey |
| (missing) | — | **Unknown** | Grey |

#### Descriptions by Label

| Label | Description |
|-------|-------------|
| Yes | Active nitrogen fixer—natural fertilizer factory that enriches soil for neighbouring plants |
| Likely | Probable nitrogen fixer—likely enriches soil through bacterial partnerships |
| Uncertain | Conflicting evidence on nitrogen fixation—may have some capacity |
| No | Does not fix atmospheric nitrogen. Benefits from nitrogen-fixing companion plants |
| Unknown | No data on nitrogen fixation ability |

Special case: If `family == "Fabaceae"` → "Fabaceae family - partners with rhizobia bacteria to capture atmospheric nitrogen"

---

## Quantile Methodology

Ratings assigned using **20/40/60/80 percentile thresholds** across all 11,711 species:

| Rating | Percentile Range | Interpretation |
|--------|------------------|----------------|
| Very High | > 80th percentile | Top 20% of species |
| High | 60th - 80th percentile | Above average |
| Moderate | 40th - 60th percentile | Average |
| Low | 20th - 40th percentile | Below average |
| Very Low | < 20th percentile | Bottom 20% of species |

---

## Classification Rules

### Rating to Score

| Rating | Score |
|--------|-------|
| Very High | 5.0 |
| High | 4.0 |
| Moderate | 3.0 |
| Low | 2.0 |
| Very Low | 1.0 |

### Nitrogen Fixer Flag

`nitrogen_fixer = true` if display label is "Yes" or "Likely" (raw rating: High or Moderate-High)

Used in:
- Garden Value Summary highlights
- S6 Companion "Provides" section

---

## Garden Value Summary

Highlights shown when rating is "Very High" or "High" (or "Yes"/"Likely" for nitrogen fixation):

| Condition | Highlight |
|-----------|-----------|
| `nitrogen_fixation` Yes or Likely | "improves soil fertility through nitrogen fixation" |
| `carbon_storage_rating` High+ | "good carbon storage for climate-conscious planting" |
| `npp_rating` High+ | "fast-growing for quick establishment" |
| `erosion_protection_rating` High+ | "excellent for slopes and erosion-prone areas" |

If no highlights: "Standard ecosystem contribution"

---

## Service Cards

Visual cards displayed for specific ecosystem services. Uses `ecoserv_*` columns (0-1 scale).

### Pollination Support

| Column | `ecoserv_pollination` |
|--------|----------------------|
| Threshold | Description |
| > 0.7 | "Strong pollinator magnet - attracts bees, butterflies, and other pollinators" |
| > 0.4 | "Moderate pollinator support" |
| ≤ 0.4 | "Limited pollinator value" |

### Carbon Storage

| Column | `ecoserv_carbon` |
|--------|-----------------|
| Threshold | Description |
| > 0.7 | "Excellent carbon capture - large woody biomass stores significant carbon" |
| > 0.4 | "Good carbon contribution" |
| ≤ 0.4 | "Modest carbon storage" |

### Soil Health

| Column | `ecoserv_soil_health` |
|--------|----------------------|
| Description | "Improves soil structure and biology" |

### Nitrogen Fixation Card

Shown only when display label is "Yes" or "Likely".

---

## Confidence Levels

Each service card has an associated confidence column:

| Service | Confidence Column | Default |
|---------|-------------------|---------|
| Pollination | `ecoserv_pollination_conf` | "Medium" |
| Carbon | `ecoserv_carbon_conf` | "Medium" |
| Soil Health | `ecoserv_soil_conf` | "Medium" |
| Nitrogen Fixation | (none) | "High" |
