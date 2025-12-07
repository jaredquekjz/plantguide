# S6: Guild Potential / Companion Planting

**Sources**:
- `stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet` - CSR, height, growth form, EIVE
- `stage4/phase7_output/organisms_flat.parquet` - Herbivores, predators, pollinators
- `stage4/phase7_output/fungi_flat.parquet` - AMF, EMF, mycoparasites, entomopathogens

## Data Columns

| Column | Variable |
|--------|----------|
| `family`, `genus` | Taxonomy |
| `C`, `S`, `R` | CSR scores (0-100%) |
| `height_m` | Mature height |
| `try_growth_form` | Growth form |
| `EIVEres-L` | Light preference (0-10) |

---

## Classification Rules

### Structural Layer (by height)

| Height | Layer |
|--------|-------|
| > 10m | Canopy |
| 5-10m | Sub-canopy |
| 2-5m | Tall shrub |
| 0.5-2m | Understory |
| < 0.5m | Ground cover |

### Guild Role (by CSR)

| CSR | Role | Strength |
|-----|------|----------|
| C-dominant | Competitor | Strong |
| S-dominant | Stress-tolerator | Strong |
| R-dominant | Pioneer/Gap filler | Moderate |
| Balanced | Generalist | Moderate |

### Structural Role (by growth form)

| Form | Role |
|------|------|
| Tree | Canopy provider |
| Shrub | Mid-layer structure |
| Herb | Ground layer |
| Vine | Vertical space user |

### Pest Control Role

| Condition | Role | Strength |
|-----------|------|----------|
| Predators ≥ 29 | Pest control habitat | Strong |
| Predators ≥ 9 OR entomopathogens > 0 | Pest control habitat | Moderate |

### Disease Fighter Role

| Condition | Role |
|-----------|------|
| Mycoparasites > 0 | Disease fighter host |

### Pollinator Role

| Pollinators | Role | Strength |
|-------------|------|----------|
| ≥ 45 | Pollinator attractor | Strong |
| 20-44 | Pollinator attractor | Moderate |
| 6-19 | Pollinator attractor | Weak |
| < 6 | (no role) | - |

### Mycorrhizal Network Role

| Type | Role | Strength |
|------|------|----------|
| Dual | Network participant | Strong |
| AMF or EMF | Network participant | Moderate |
| Non-mycorrhizal | (no role) | - |

---

## Avoid-With Rules

| Condition | Avoid |
|-----------|-------|
| Always | Multiple plants from same family clustered together |
| C-dominant | Other C-dominant plants at same height |
| EIVE-L > 7.47 | Planting under dense canopy (sun-loving) |
| EIVE-L < 3.2 | Full sun exposure without shade (shade-adapted) |

---

## Light Preference Thresholds

| EIVE-L | Interpretation |
|--------|----------------|
| > 7.47 | Sun-demanding |
| < 3.2 | Shade-tolerant |
| 3.2-7.47 | Flexible |

---

## Planting Notes Rules

| Condition | Note |
|-----------|------|
| C-dominant | Vigorous grower - needs space management |
| S-dominant | Low maintenance - reliable guild backbone |
| R-dominant | Short-lived - plan for succession or self-seeding |
| Balanced | Adaptable - fits well in most positions |
| Vine | Needs vertical support structure |
| Mycorrhizal (any) | Minimize soil disturbance to preserve fungal networks |

---

## Understory Recommendations

| Layer | Recommended understory |
|-------|------------------------|
| Canopy | Shade-tolerant plants (EIVE-L < 5) |
| Sub-canopy | Ground covers, shade-tolerant shrubs |
| Tall shrub | Low herbs, ground covers |
| Understory/Ground cover | N/A - low growing |

---

## Pest Recommendation Thresholds

| Herbivores | Recommendation |
|------------|----------------|
| ≥ 16 | High pest diversity (top 10%). Benefits from predator companions |
| 6-15 | Above-average pests. Diverse plantings help |
| < 6 | Standard companion planting |

| Predators | Recommendation |
|-----------|----------------|
| ≥ 29 | Excellent predator habitat (top 10%) |
| 9-28 | Good predator habitat |
