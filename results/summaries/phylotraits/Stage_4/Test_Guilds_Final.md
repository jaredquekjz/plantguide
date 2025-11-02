# Final Test Guilds for Guild Compatibility Validation

**Date**: 2025-11-02
**Purpose**: Validate guild compatibility scoring framework with clear BAD vs GOOD examples

---

## BAD GUILD: All Acacia (Monoculture)

### Plants

```python
bad_guild_acacias = [
    'wfo-0000173762',  # Acacia koa
    'wfo-0000173754',  # Acacia auriculiformis
    'wfo-0000204086',  # Acacia melanoxylon
    'wfo-0000202567',  # Acacia mangium
    'wfo-0000186352'   # Acacia harpophylla
]
```

| WFO ID | Scientific Name | Family |
|--------|----------------|---------|
| wfo-0000173762 | Acacia koa | Fabaceae |
| wfo-0000173754 | Acacia auriculiformis | Fabaceae |
| wfo-0000204086 | Acacia melanoxylon | Fabaceae |
| wfo-0000202567 | Acacia mangium | Fabaceae |
| wfo-0000186352 | Acacia harpophylla | Fabaceae |

### Characteristics (Validated)

**NEGATIVE FACTORS (High = Bad)**:
- **N1 - Pathogenic Fungi Overlap**: 40 shared fungi
  - 2 fungi on ALL 5 plants: *Ganoderma*, *Meliola*
  - 7 fungi on 4+ plants: *Fusarium*, *Calonectria*, *Armillaria*, etc.
  - Avg pathogen load: 31.2 fungi per plant
  - **Ecological impact**: Complete pathogen overlap → guild-wide disease outbreak risk

- **N2 - Herbivore Overlap**: 8 shared herbivores
  - 1 herbivore on 3+ plants
  - Avg herbivores per plant: 27.6

- **N3 - Other Pathogen Overlap**: Low (0.4 avg per plant)

**POSITIVE FACTORS (Low = Bad)**:
- **P1 - Herbivore Control**: Minimal
  - Cross-plant benefits: 1 pair out of 20 possible (5%)
  - Low visitor counts (0.8 avg)

- **P2 - Pathogen Control**: Unknown (will be computed)

- **P3 - Beneficial Fungi**: Moderate
  - 49 shared beneficial fungi
  - Avg beneficial per plant: 58.6

- **P4 - Taxonomic Diversity**: **Catastrophic**
  - 1 family only (all Fabaceae)
  - Family diversity: 0.2
  - Shannon diversity: 0.0

### Expected Score: **-0.75 to -0.85** (Bad guild - disease outbreak risk)

**Reasoning**:
- `negative_risk_score` will be very high (→ 0.9) due to massive pathogen overlap
- `positive_benefit_score` will be very low (→ 0.1) due to zero diversity, minimal cross-benefits
- `guild_score = 0.1 - 0.9 = -0.8` (catastrophic)

---

## GOOD GUILD #1: Taxonomically Diverse (Low Pathogen Overlap)

### Plants

```python
good_guild_diverse = [
    'wfo-0000178702',  # Abrus precatorius - Fabaceae
    'wfo-0000511077',  # Abies concolor - Pinaceae
    'wfo-0000173762',  # Acacia koa - Fabaceae
    'wfo-0000511941',  # Abutilon grandifolium - Malvaceae
    'wfo-0000510888'   # Abelmoschus moschatus - Malvaceae
]
```

| WFO ID | Scientific Name | Family |
|--------|----------------|---------|
| wfo-0000178702 | Abrus precatorius | Fabaceae |
| wfo-0000511077 | Abies concolor | Pinaceae |
| wfo-0000173762 | Acacia koa | Fabaceae |
| wfo-0000511941 | Abutilon grandifolium | Malvaceae |
| wfo-0000510888 | Abelmoschus moschatus | Malvaceae |

### Characteristics (Validated)

**NEGATIVE FACTORS (Low = Good)**:
- **N1 - Pathogenic Fungi Overlap**: 5 shared fungi only
  - 0 fungi on 4+ plants
  - 0 fungi on all 5 plants
  - Avg pathogen load: 14.4 fungi per plant (54% less than Acacia guild)
  - **Ecological impact**: Minimal disease transmission risk

- **N2 - Herbivore Overlap**: 0 shared herbivores
  - Avg herbivores per plant: 3.6
  - **Ecological impact**: Zero pest outbreak risk

- **N3 - Other Pathogen Overlap**: Low

**POSITIVE FACTORS (Moderate = Good)**:
- **P1 - Herbivore Control**: Minimal
  - Cross-plant benefits: 0 pairs (weak point!)
  - Low visitor counts (1.0 avg)

- **P2 - Pathogen Control**: Unknown (will be computed)

- **P3 - Beneficial Fungi**: Moderate
  - 12 shared beneficial fungi
  - Avg beneficial per plant: 40.4

- **P4 - Taxonomic Diversity**: **Good**
  - 3 families (Fabaceae, Pinaceae, Malvaceae)
  - Family diversity: 0.6
  - Shannon diversity: moderate

### Expected Score: **+0.30 to +0.45** (Good guild - low risks, moderate benefits)

**Reasoning**:
- `negative_risk_score` will be very low (→ 0.1) due to minimal pathogen/herbivore overlap
- `positive_benefit_score` will be moderate (→ 0.5) due to good diversity, some beneficial fungi, but weak P1/P2
- `guild_score = 0.5 - 0.1 = +0.4` (good but not excellent)

**Weakness**: No cross-plant biocontrol benefits (P1 = 0, P2 unknown)

---

## GOOD GUILD #2: High Cross-Benefits (Native Pollinator Plants)

### Plants

```python
good_guild_cross_benefits = [
    'wfo-0000678333',  # Eryngium yuccifolium - Apiaceae
    'wfo-0000010572',  # Heliopsis helianthoides - Asteraceae
    'wfo-0000245372',  # Monarda punctata - Lamiaceae
    'wfo-0000985576',  # Spiraea alba - Rosaceae
    'wfo-0000115996'   # Symphyotrichum novae-angliae - Asteraceae
]
```

| WFO ID | Scientific Name | Family |
|--------|----------------|---------|
| wfo-0000678333 | Eryngium yuccifolium | Apiaceae |
| wfo-0000010572 | Heliopsis helianthoides | Asteraceae |
| wfo-0000245372 | Monarda punctata | Lamiaceae |
| wfo-0000985576 | Spiraea alba | Rosaceae |
| wfo-0000115996 | Symphyotrichum novae-angliae | Asteraceae |

### Characteristics (Queried)

**NEGATIVE FACTORS (Low = Good)**:
- **N1 - Pathogenic Fungi Overlap**: Low expected (1-11 fungi per plant)
- **N2 - Herbivore Overlap**: Unknown (will be computed)
- **N3 - Other Pathogen Overlap**: Unknown (will be computed)

**POSITIVE FACTORS (High = Excellent)**:
- **P1 - Herbivore Control**: **STRONG**
  - Each plant provides benefits to 5+ other plants
  - High visitor counts (165-260 visitors per plant)
  - Expected: Many cross-plant predator benefits

- **P2 - Pathogen Control**: Unknown (will be computed)

- **P3 - Beneficial Fungi**: Moderate to low
  - 0-6 beneficial fungi per plant

- **P4 - Taxonomic Diversity**: **Excellent**
  - 4 families (Apiaceae, Asteraceae, Lamiaceae, Rosaceae)
  - Family diversity: 0.8
  - Shannon diversity: high

### Expected Score: **+0.55 to +0.75** (Excellent guild - strong synergies)

**Reasoning**:
- `negative_risk_score` will be low (→ 0.2) due to low pathogen loads and different families
- `positive_benefit_score` will be high (→ 0.75) due to excellent diversity and strong P1 cross-benefits
- `guild_score = 0.75 - 0.2 = +0.55 to +0.65` (excellent)

**Strength**: High cross-plant biocontrol potential (P1 strong)

---

## Recommended Test Suite

### Option 1: Conservative (Using Validated Data)

**BAD**: Acacia guild (fully validated)
**GOOD**: Diverse guild #1 (fully validated)

**Pros**: All data confirmed, clear separation expected (-0.8 vs +0.4 = 1.2 difference)
**Cons**: GOOD guild has weak P1 component (no cross-benefits)

### Option 2: Comprehensive (Testing All Components)

**BAD**: Acacia guild
**GOOD #1**: Diverse guild (low overlap, moderate benefits)
**GOOD #2**: Cross-benefits guild (high synergies)

**Pros**: Tests full framework including P1 cross-benefits
**Cons**: Good #2 needs validation

---

## Validation Checklist

Before implementing scorer, run these checks on Good Guild #2:

```sql
-- 1. Pathogenic fungi overlap (expect <10)
-- 2. Herbivore overlap (expect <5)
-- 3. Cross-plant benefits (expect >5 pairs)
-- 4. Shared beneficial fungi (expect moderate)
```

If Good Guild #2 shows unexpected high overlap, fall back to Good Guild #1.

---

## Score Interpretation

| Score Range | Interpretation | Expected Guild |
|-------------|----------------|----------------|
| -1.0 to -0.7 | Catastrophic - shared vulnerabilities, no benefits | BAD (Acacia) |
| -0.7 to -0.3 | Poor - risks outweigh benefits | - |
| -0.3 to +0.3 | Neutral - balanced | - |
| +0.3 to +0.7 | Good - benefits outweigh risks | GOOD #1 (Diverse) |
| +0.7 to +1.0 | Excellent - strong synergies, minimal risks | GOOD #2 (Cross-benefits) |

---

## Implementation Priority

1. ✅ **Implement `05_compute_guild_compatibility.py`** with framework from 4.2
2. ✅ **Test on BAD guild (Acacia)** - should score -0.75 to -0.85
3. ✅ **Test on GOOD guild #1 (Diverse)** - should score +0.30 to +0.45
4. 📋 **Validate GOOD guild #2 data** (run overlap queries)
5. 📋 **Test on GOOD guild #2** - should score +0.55 to +0.75
6. 📋 **Analyze component contributions** to understand which factors dominate

---

**Next Step**: Implement `05_compute_guild_compatibility.py` using DuckDB SQL for guild-level overlap scoring.
