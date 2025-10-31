# CSR Edge Case Analysis: 30 Species Outside Calibration Range

**Date:** 2025-10-30
**Issue:** 30 species (0.26%) produce NaN CSR scores
**Status:** Root cause identified, solution required

---

## Problem Summary

30 species fail CSR calculation with C=NaN, S=NaN, R=NaN due to division by zero in the StrateFy algorithm. All proportions (propC, propS, propR) become exactly 0.0, causing the normalization step to fail.

---

## Root Cause

These species have extreme trait combinations that cause them to hit **all three boundaries simultaneously** in the StrateFy calibration space:

| Boundary | Condition | Ecological Interpretation |
|----------|-----------|--------------------------|
| **minC** (C_raw ≤ 0) | Very small leaves (LA: 1-24 mm²) | Low competitive ability |
| **minS** (S_raw ≤ -0.756) | Very low LDMC (6.94-16.52% vs population mean 24.6%) | Low tissue investment |
| **maxR** (R_raw ≥ 1.108) | Low SLA (3-9 mm²/mg) inverted → Low ruderality | Slow growth |

**Mathematical Issue:**
```
When all boundaries hit:
  valorC = 0 + 0 = 0           → propC = (0/57.4) * 100 = 0
  valorS = 0.756 + (-0.756) = 0 → propS = (0/6.55) * 100 = 0
  valorR = 11.35 + 1.108 = 12.45 → propR = 100 - (12.45/12.45)*100 = 0

  sum = 0 + 0 + 0 = 0
  conv = 100 / 0 = NaN
  C = S = R = NaN
```

---

## Affected Species (30 total)

### Functional Groups

**Conifers (21 species):**
- Thuja occidentalis, Juniperus pseudosabina, Tsuga canadensis, Abies magnifica
- Pilgerodendron uviferum, Athrotaxis selaginoides, Austrocedrus chilensis
- Calocedrus decurrens, Chamaecyparis obtusa, Cupressus sempervirens
- Fitzroya cupressoides, Callitropsis nootkatensis, Juniperus communis
- Juniperus oxycedrus, Sequoia sempervirens, Thuja plicata, Tsuga heterophylla
- Abies alba, Juniperus thurifera, Thujopsis dolabrata, Widdringtonia wallichii

**Halophytes/Chenopods (8 species):**
- Suaeda vera, Sclerolaena brachyptera, Sclerolaena tricuspis, Sclerolaena diacantha
- Sclerolaena muricata, Atriplex lindleyi, Chenopodium desertorum, Dissocarpus biflorus
- Dissocarpus paradoxus, Enchylaena tomentosa, Maireana pyramidata

**Other (1 species):**
- Ulex europaeus, Arctostaphylos crustacea, Cassiope tetragona
- Phyllachne colensoi, Scleranthus biflorus, Paronychia pulvinata
- Petrosedum sediforme

### Trait Characteristics

| Trait | Failing Species Mean | Population Mean | Interpretation |
|-------|---------------------|-----------------|----------------|
| LA | 10.7 mm² | 2,759.6 mm² | Extremely small leaves/needles |
| LDMC | 13.3% | 24.6% | Very low tissue density |
| SLA | 5.6 mm²/mg | 16.9 mm²/mg | Very low area per mass (thick/dense) |

**Unusual combination:** Low LDMC + Low SLA
- Typical pattern: Low LDMC → thin, soft leaves → high SLA
- These species: Low LDMC + low SLA → specialized tissue structure outside normal leaf economics spectrum

---

## Ecological Context

**Reality:** Most of these species ARE stress-tolerators
- **Conifers:** Adapted to cold climates, nutrient-poor soils, slow-growing, long-lived needles
- **Halophytes:** Adapted to saline conditions, specialized water/salt regulation

**StrateFy calibration:** 3,068 species, primarily herbaceous/woody **angiosperms**
- Conifers (gymnosperms) have fundamentally different leaf/needle structure
- Halophytes have specialized succulent/salt-storing tissues
- These functional groups fall outside the angiosperm-based calibration space

---

## Solution Options

### Option 1: Document as Limitation (Recommended)
**Action:** Keep CSR = NaN, document as known limitation

**Pros:**
- Scientifically transparent
- No arbitrary assumptions
- Honest about method boundaries

**Cons:**
- Incomplete dataset (99.74% coverage instead of 100%)
- Cannot predict ecosystem services for these 30 species

**Implementation:**
- Add warning in documentation about 0.26% failure rate
- List functional groups excluded (conifers, halophytes)
- Mark as "unable to classify" in outputs

---

### Option 2: Taxonomy-Based Fallback
**Action:** Assign CSR based on functional group ecology
- Conifers → S=70, C=20, R=10 (stress-tolerator dominant)
- Halophytes → S=60, C=20, R=20 (stress-tolerator with some competition)

**Pros:**
- Ecologically informed
- Complete dataset
- Based on known life history strategies

**Cons:**
- Arbitrary values not from trait data
- Inconsistent with data-driven approach
- Requires taxonomic rules for edge cases

---

### Option 3: Epsilon Prevention
**Action:** Add small epsilon (e.g., 0.1) to any proportion that equals 0

**Pros:**
- Simple fix
- Allows calculation to proceed
- Maintains data-driven approach

**Cons:**
- Arbitrary threshold
- Produces potentially misleading CSR values (e.g., C=0.1, S=0.1, R=99.8)
- Still doesn't reflect actual ecology

---

### Option 4: Alternative CSR Method
**Action:** Use different CSR calculation method for edge cases
- E.g., Hodgson et al. (1999) method, or direct trait-to-strategy rules

**Pros:**
- Data-driven
- Potentially better for specialized functional groups

**Cons:**
- Inconsistent methodology within dataset
- Requires additional implementation and validation
- May still fail for these extreme cases

---

### Option 5: Exclude from Analysis
**Action:** Remove 30 species from final dataset entirely

**Pros:**
- Clean dataset with no NaN values
- No arbitrary assumptions

**Cons:**
- Loses rare functional groups
- Biases dataset toward angiosperms
- Not transparent about exclusions

---

## Recommendation

**Adopt Option 1** (document as limitation) for scientific rigor:

1. Keep CSR = NaN for these 30 species
2. Add documentation section:
   - "Known Limitations: StrateFy Calibration Boundaries"
   - List 0.26% failure rate
   - Identify functional groups affected
   - Explain that these species fall outside the angiosperm-based calibration
3. For ecosystem services:
   - Mark as "Unable to Classify" with confidence level "Not Applicable"
   - Document that predictions require valid CSR scores
4. In analysis workflows:
   - Filter out NaN CSR before community-weighted calculations
   - Report completeness statistics (99.74% coverage)

**Alternative:** If complete dataset is required, use **Option 2** (taxonomy-based fallback) with:
- Clear documentation that these are ecology-based assignments, not trait-derived
- Separate confidence level: "Low - Taxonomic Assignment"
- Flagged in output with `csr_method = "taxonomy_fallback"`

---

## Implementation

### If choosing Option 1 (Recommended):
1. Update `STAGE3_SUMMARY.md`: Add limitation section
2. Update `CSR_methodology_and_ecosystem_services.md`: Document edge cases
3. Update `validate_shipley_part2.py`: Report % with valid CSR
4. No code changes needed

### If choosing Option 2 (Taxonomy-based):
1. Create function in `calculate_stratefy_csr.py`:
```python
def assign_csr_taxonomy_fallback(family, life_form):
    """Assign CSR for species outside StrateFy calibration"""
    # Conifers
    if family in ['Pinaceae', 'Cupressaceae', 'Taxaceae', 'Podocarpaceae']:
        return 20.0, 70.0, 10.0  # S-dominant
    # Halophytes
    if family == 'Amaranthaceae':  # includes Chenopodioideae
        return 20.0, 60.0, 20.0  # S-dominant with R
    # Default fallback
    return 33.3, 33.3, 33.3  # Neutral
```
2. Modify normalization to detect division by zero and call fallback
3. Add `csr_method` column to output
4. Update documentation

---

## Data Quality Impact

**Current Status:**
- Total species: 11,680
- Valid CSR: 11,650 (99.74%)
- Failed CSR: 30 (0.26%)

**Option 1 Impact:**
- 99.74% complete for CSR-based ecosystem services
- High-quality, scientifically defensible results

**Option 2 Impact:**
- 100% complete
- 30 species (0.26%) flagged as taxonomy-based assignments
