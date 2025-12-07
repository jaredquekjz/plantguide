# S3: Maintenance Profile

**Source**: `stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet` (Dec 6 2024)

## Data Columns

| Column | Variable | Source |
|--------|----------|--------|
| `C` | Competitor score | CSR (0-100%) |
| `S` | Stress-tolerator score | CSR (0-100%) |
| `R` | Ruderal score | CSR (0-100%) |
| `height_m` | Mature height | TRY Global Spectrum |
| `try_growth_form` | Growth form | TRY |
| `try_leaf_phenology` | Deciduous/Evergreen | TRY |
| `LA` | Leaf area | TRY Global Spectrum (mm²) |
| `logSM` | Seed mass | TRY Global Spectrum (log mg) |

---

## Classification Rules

### CSR Strategy

**Spread** = MAX(C,S,R) - MIN(C,S,R)

| Condition | Strategy |
|-----------|----------|
| Spread < 20% | Balanced |
| C highest | C-dominant (Competitor) |
| S highest | S-dominant (Stress-tolerator) |
| R highest | R-dominant (Ruderal) |

**Note**: No overall "maintenance level" is calculated. Real maintenance effort depends on climate suitability, garden aims, placement, and many context-specific factors that cannot be reduced to a simple CSR-derived score.

---

## Maintenance Tasks

### Pruning (by height)

| Height | Task | Frequency | Importance |
|--------|------|-----------|------------|
| ≥ 15m | Professional pruning | Every 3-5 years | Essential |
| 6-15m | Ladder pruning | Annually | Recommended |
| 2.5-6m | Formative pruning | Annually | Recommended |
| < 2.5m | Light trimming | As needed | Optional |

### Seedling Control (by seed mass)

| Seed Mass | Task | Frequency | Importance |
|-----------|------|-----------|------------|
| < 10mg | Seedling control | Monthly in growing season | Essential |
| < 100mg OR R-dominant | Self-sown seedling removal | Seasonally | Recommended |

### Leaf Cleanup (deciduous only, by leaf area)

| Leaf Area (cm²) | Task | Frequency | Importance |
|-----------------|------|-----------|------------|
| > 50 | Leaf cleanup | Weekly in autumn | Essential |
| 15-50 | Leaf raking | Bi-weekly in autumn | Recommended |
| < 15 | Light debris clearing | Monthly in autumn | Optional |

### Strategy-Specific Tasks

| Strategy | Growth Form | Task | Frequency | Importance |
|----------|-------------|------|-----------|------------|
| C-dominant | Vine | Vigorous growth control | 2-3 times/season | Essential |
| C-dominant | Shrub | Hard pruning for spread control | Annually | Essential |
| C-dominant | Herb | Division to control spread | Every 1-2 years | Recommended |
| R-dominant | Any | Plan replacement or allow self-seeding | Every 1-3 years | Recommended |

---

## Seasonal Notes

| Season | Strategy/Condition | Note |
|--------|-------------------|------|
| Spring | C-dominant | Watch for aggressive early growth; may shade out neighbours |
| Spring | R-dominant | Check for self-sown seedlings; thin or transplant |
| Summer | C-dominant + Vine | Peak growth; regular training and cutting back needed |
| Autumn | Deciduous | Clear fallen leaves to prevent disease |
| Winter | S-dominant | Dormant period; minimal intervention needed |
| Winter | R-dominant + Vine | May die back completely; regrows from base in spring |
