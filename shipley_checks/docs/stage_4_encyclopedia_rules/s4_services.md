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

Based on TRY Database family-level classification. Fabaceae (legumes) partner with rhizobia bacteria to fix atmospheric nitrogen.

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

`nitrogen_fixer = true` if `nitrogen_fixation_rating` is "Very High" or "High"

Special case: If `family == "Fabaceae"` → legume-specific description

---

## Garden Value Summary

Highlights shown when rating is "Very High" or "High":

| Condition | Highlight |
|-----------|-----------|
| `nitrogen_fixation_rating` High+ | "improves soil fertility through nitrogen fixation" |
| `carbon_storage_rating` High+ | "good carbon storage for climate-conscious planting" |
| `npp_rating` High+ | "fast-growing for quick establishment" |
| `erosion_protection_rating` High+ | "excellent for slopes and erosion-prone areas" |

If no highlights: "Standard ecosystem contribution"
