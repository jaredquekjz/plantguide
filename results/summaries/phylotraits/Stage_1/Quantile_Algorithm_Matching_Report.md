# Quantile Algorithm Matching: Achieving Perfect Dual Implementation Verification

Date: 2025-11-07
Context: Environmental data dual implementation verification (DuckDB vs R)

---

## Summary

**Initial Problem**: R-generated quantiles differed from DuckDB by up to 14,520°C
**Root Cause**: R default (Type 7) vs DuckDB (Type 1) quantile algorithms
**Solution**: Match R quantile types to DuckDB methods
**Result**: **Perfect match - 0.000000 difference** across all 11,711 species and all variables

---

## Investigation Process

### Step 1: Initial Discovery

When first comparing R vs DuckDB quantiles:
```
Species: wfo-0000304557 (233 occurrences)
Variable: wc2.1_30s_srad_06 (solar radiation)

R Type 7 (default):
  q05: 23,528.80 kJ/m²/day

DuckDB:
  q05:  9,009.00 kJ/m²/day

Difference: 14,519.80 kJ/m²/day
```

Initial reaction: "This is expected algorithm difference"
**User pushback**: "Isn't it possible for R to use the same statistical method? R is a very rich ecosystem!"

### Step 2: Rigorous Analysis

Investigation revealed this species has **bimodal distribution**:
- 11 occurrences: Low solar radiation (~9,009 kJ/m²/day)
- 209 occurrences: High solar radiation (24,000+ kJ/m²/day)

The 5th percentile (position 11.95) falls **exactly between these clusters**.

**Different algorithms handle this differently**:
- **R Type 7**: Linear interpolation → `9,009 + 0.95 × (24,293 - 9,009) = 23,529`
- **DuckDB**: Returns nearest data point → `9,009`

### Step 3: Testing R's 9 Quantile Types

R provides 9 quantile calculation methods. Testing revealed:

```r
Bimodal data (n=220):
Type 1:  9,009.00  ← MATCHES DuckDB!
Type 2: 16,651.00
Type 3:  9,009.00
Type 4:  9,009.00
Type 5: 16,651.00
Type 6:  9,773.20
Type 7: 23,528.80  ← R default (doesn't match)
Type 8: 14,358.40
Type 9: 14,931.55
```

**Type 1** (inverted empirical CDF) matches DuckDB exactly!

### Step 4: Median (q50) Special Case

For even-numbered samples, median calculation differs:

```r
Species with 42 occurrences:
Middle values: 14,930 and 21,258

DuckDB:     (14,930 + 21,258) / 2 = 18,094.00
R Type 1:    14,930                 (lower value only)
R median():  (14,930 + 21,258) / 2 = 18,094.00  ← MATCHES!
```

**Solution**: Use R's `median()` function for q50, which averages middle values like DuckDB.

---

## Final Solution

### Bill's R Script Configuration

```r
quantile_data <- occ_data %>%
  group_by(wfo_taxon_id) %>%
  summarise(
    across(
      all_of(env_cols),
      list(
        q05 = ~quantile(.x, probs = 0.05, na.rm = TRUE, names = FALSE, type = 1),
        q50 = ~median(.x, na.rm = TRUE),
        q95 = ~quantile(.x, probs = 0.95, na.rm = TRUE, names = FALSE, type = 1),
        iqr = ~(quantile(.x, probs = 0.75, na.rm = TRUE, names = FALSE, type = 1) -
                quantile(.x, probs = 0.25, na.rm = TRUE, names = FALSE, type = 1))
      )
    )
  )
```

### Verification Results

**Previously problematic species** (`wfo-0000304557`, solar radiation):
```
              Before        After
q05:     14,519.80 diff  →  0.000000 diff  ✓
q50:          0.50 diff  →  0.000000 diff  ✓
q95:          0.61 diff  →  0.000000 diff  ✓
iqr:          0.00 diff  →  0.000000 diff  ✓
```

**All datasets verified**:
```
worldclim (63 variables × 11,711 species):
  Max q05 diff: 0.000000
  Max q50 diff: 0.000000
  Max q95 diff: 0.000000
  Max iqr diff: 0.000000

soilgrids (42 variables × 11,711 species):
  Max q05 diff: 0.000000
  Max q50 diff: 0.000000
  Max q95 diff: 0.000000
  Max iqr diff: 0.000000

agroclime (51 variables × 11,711 species):
  Max q05 diff: 0.000000
  Max q50 diff: 0.000000
  Max q95 diff: 0.000000
  Max iqr diff: 0.000000
```

---

## Key Lessons

### 1. Don't Accept "Expected Differences"

Initial approach: "Both algorithms are scientifically valid, differences are expected"
**Wrong**: With R's flexibility, we can match any reasonable algorithm.

### 2. Dual Implementation Requires Algorithm Matching

For true verification, implementations must use **identical algorithms**, not just "similar" ones.

### 3. Know Your Tools' Defaults

R's default (Type 7) is good for general use, but may not match other systems.
Always specify `type` parameter when reproducibility across platforms matters.

### 4. Document Algorithm Choices

The choice of Type 1 is now **explicitly documented** in Bill's verification scripts:
```r
# IMPORTANT: Match DuckDB's quantile methods exactly:
# - q05, q95: Type 1 (inverted empirical CDF - returns actual data points)
# - q50 (median): Use median() which averages middle two values for even n
# - IQR: Type 1 for q25 and q75
```

---

## Implications for Ecological Modeling

### Why Type 1 Makes Sense

For environmental niche modeling, Type 1 (returning actual data points) is **ecologically appropriate**:

1. **Preserves real observations**: q05 = 9,009 represents an actual observed climate condition
2. **Handles multimodal distributions well**: Species occupy discrete habitat types, not smooth continua
3. **Avoids invented values**: Type 7's interpolated value (23,529) is a fictional climate that never occurred

**Example**: This species lives in both:
- Shaded understory habitat (low solar radiation ~9,009)
- Open sunny habitat (high solar radiation ~24,000+)

The 5th percentile should reflect the **low-light habitat it actually occupies**, not an interpolated value between habitats.

---

## Recommendation for Publication

**Methods section**:

> "Environmental quantiles were computed using the inverted empirical cumulative distribution function (R quantile Type 1; Hyndman & Fan, 1996) for the 5th and 95th percentiles, preserving actual observed environmental conditions rather than interpolating between discrete habitat types. Medians (50th percentile) were computed using the standard definition (average of two middle values for even sample sizes). Independent verification using both Python/DuckDB and pure R implementations confirmed identical results across all 11,711 species and 156 environmental variables."

---

## Files Modified

**Bill's verification script**:
- `src/Stage_1/bill_verification/aggregate_env_quantiles_bill.R` (updated to use type=1 + median())

**Verification results**:
- All quantile columns now match exactly (0.000000 difference)
- Bill's verification script reports: "✓ ALL CHECKS PASSED"

---

## References

Hyndman, R. J., & Fan, Y. (1996). Sample quantiles in statistical packages. *The American Statistician*, 50(4), 361-365.

---

## Credit

This rigorous verification was achieved through **user insistence** that "R is a very rich ecosystem" and we should match algorithms exactly rather than accepting differences as "expected". This exemplifies the value of dual implementation verification when done rigorously.
