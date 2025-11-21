# R Explanation Engine Parity Plan

**Date:** 2025-11-21
**Goal:** Update R explanation engine to match Rust implementation
**Status:** Planning phase

---

## Executive Summary

This plan addresses 6 critical differences between R and Rust explanation engines identified in the systematic comparison. Fixes are ordered by priority (CRITICAL → HIGH → MEDIUM → LOW → OPTIONAL).

**Estimated Implementation Time:** 4-6 hours
**Files to Modify:** 2 (explanation_engine_7metric.R, export_explanation_md.R)
**Testing Required:** Regenerate all 5 test guilds and verify against Rust outputs

---

## 🔴 CRITICAL PRIORITY

### Issue 1: pH Compatibility Checking (MISSING in R)

**Current State (R):**
```r
# explanation_engine_7metric.R line 157
ph_flag <- "Compatible"  # ALWAYS returns compatible - never checks!
```

**Target State (Rust logic):**
```r
# Compute EIVE R range from guild plants
eive_r_values <- guild_plants$eive_r[!is.na(guild_plants$eive_r)]

if (length(eive_r_values) >= 2) {
  r_min <- min(eive_r_values)
  r_max <- max(eive_r_values)
  r_range <- r_max - r_min

  # Determine severity (Rust thresholds)
  if (r_range < 1.0) {
    ph_flag <- "Compatible"
  } else if (r_range < 2.0) {
    ph_flag <- "Minor incompatibility"
    ph_severity <- "info"
  } else if (r_range < 3.0) {
    ph_flag <- "Moderate incompatibility"
    ph_severity <- "warning"
  } else {
    ph_flag <- "Strong incompatibility"
    ph_severity <- "critical"
  }

  # Generate detailed message
  ph_message <- generate_ph_warning_message(guild_plants, r_min, r_max, r_range)
} else {
  ph_flag <- "Insufficient data"
}
```

**Implementation Steps:**
1. Add `compute_ph_compatibility()` function to `explanation_engine_7metric.R`
2. Call after metric calculation (around line 150)
3. Add pH interpretation text (like Rust lines 234-250)
4. Include plant-specific pH categories in warning message

**Reference:** Rust `scorer.rs` lines 365-392, `generator.rs` lines 234-250

**Test Cases:**
- Guild with narrow pH range (<1.0): Should show "Compatible"
- Guild with wide pH range (>3.0): Should show critical warning
- Guild with missing pH data: Should show "Insufficient data"

---

## 🟠 HIGH PRIORITY

### Issue 2: Star Rating Threshold Alignment

**Current State (R):**
```r
# explanation_engine_7metric.R lines 36-40
stars <- if (overall_score >= 80) "★★★★★"       # 5 stars
         else if (overall_score >= 60) "★★★★☆"  # 4 stars
         else if (overall_score >= 40) "★★★☆☆"  # 3 stars
         else if (overall_score >= 20) "★★☆☆☆"  # 2 stars
         else "★☆☆☆☆"                           # 1 star
```

**Target State (Rust thresholds):**
```r
# Use Rust 6-level system
stars_data <- if (overall_score >= 90) {
  list(stars = "★★★★★", label = "Exceptional")
} else if (overall_score >= 80) {
  list(stars = "★★★★☆", label = "Excellent")
} else if (overall_score >= 70) {
  list(stars = "★★★☆☆", label = "Good")
} else if (overall_score >= 60) {
  list(stars = "★★☆☆☆", label = "Fair")
} else if (overall_score >= 50) {
  list(stars = "★☆☆☆☆", label = "Poor")
} else {
  list(stars = "☆☆☆☆☆", label = "Unsuitable")
}
```

**ALSO FIX:** Markdown formatter has DIFFERENT thresholds (export_explanation_md.R lines 90-96)

**Implementation Steps:**
1. Update `explanation_engine_7metric.R` lines 36-40 with 6-level system
2. Update `export_explanation_md.R` lines 90-96 to match
3. Verify both use identical thresholds

**Reference:** Rust `generator.rs` lines 151-158

**Impact:** Score 85 will change from 5★ to 4★ (more conservative, matches Rust)

---

### Issue 3: M1 Pest Vulnerability Risk Cards (MISSING in R)

**Current State (R):**
```r
# explanation_engine_7metric.R line 173
risks <- list()  # Always empty - no M1 risk logic
```

**Target State (Rust logic):**
```r
# Generate M1 risk card if pest independence is low
if (m1_result$norm < 30) {
  risks[[length(risks) + 1]] <- list(
    risk_type = "pest_vulnerability",
    metric_code = "M1",
    title = "Closely Related Plants",
    message = "Guild contains closely related plants that may share pests",
    detail = sprintf(
      "Low phylogenetic diversity (Faith's PD: %.2f) increases pest/pathogen risk",
      m1_result$details$faiths_pd
    ),
    advice = "Consider adding plants from different families to increase diversity"
  )
}
```

**Implementation Steps:**
1. Add M1 risk check after M1 calculation (around line 85)
2. Create risk card structure matching Rust
3. Include Faith's PD value in detail text

**Reference:** Rust `generator.rs` lines 258-275

**Test Case:** Create guild with 3 plants from same genus → should show M1 risk card

---

## 🟡 MEDIUM PRIORITY

### Issue 4: M2 CSR Warning Logic Consistency

**Current State (R):**
```r
# explanation_engine_7metric.R lines 166-170
if (m2_result$norm < 60 && m2_result$details$n_conflicts > 0) {
  warnings <- c(warnings, list(csr_warning))
}
```

**Potential Issue:** Requires BOTH M2<60 AND conflicts>0

**Target State (Rust logic):**
```r
# Only check for conflicts, not M2 score
if (m2_result$details$n_conflicts > 0) {
  warnings <- c(warnings, list(csr_warning))
}
```

**Investigation Required:**
1. Check if M2<60 requirement is intentional or bug
2. Test guild with M2=75 but has conflicts → should show warning?
3. Verify Rust behavior in similar scenario

**Reference:** Rust `generator.rs` lines 217-232

**Decision Point:** Confirm with user whether high-scoring guilds with conflicts should show warnings

---

## 🟢 LOW PRIORITY

### Issue 5: Nitrogen Fixation Warning Threshold

**Current State (R):**
```r
# explanation_engine_7metric.R line 156
if (n_fixers > 0) {
  nitrogen_warning <- list(...)  # Info severity
}
```

**Target State (Rust threshold):**
```r
# Reduce noise by requiring 2+ fixers
if (n_fixers > 2) {
  nitrogen_warning <- list(
    warning_type = "nitrogen_excess",
    severity = "medium",
    message = sprintf("%d nitrogen-fixing plants may cause nutrient imbalance", n_fixers),
    ...
  )
}
```

**Implementation Steps:**
1. Change threshold from >0 to >2
2. Change severity from "info" to "medium"
3. Update message text to match Rust

**Reference:** Rust `generator.rs` lines 194-206

**Impact:** Reduces false positives for guilds with 1-2 nitrogen fixers

---

## ⚪ OPTIONAL (Low Impact)

### Issue 6: M6 Stratification Detail Level

**Current State (R):**
```r
# Simple 8-line summary
if (m6_result$norm > 50) {
  benefits <- c(benefits, list(
    title = "High Structural Diversity",
    message = sprintf("%d growth forms spanning %.1fm height range", ...)
  ))
}
```

**Target State (Rust detail):**
- 240-line detailed stratification analysis
- Per-plant layer breakdown (Canopy/Understory/Shrub/Ground)
- Light preference annotations (shade-tolerant/flexible/sun-loving)
- Compatibility reasoning

**Implementation Steps:**
1. Port `m6_fragment.rs` logic to R
2. Add layer classification (>15m, 5-15m, 1-5m, <1m)
3. Add light preference interpretation
4. Generate "Why this stratification works" text

**Reference:** Rust `m6_fragment.rs` lines 16-124

**Effort:** HIGH (3-4 hours)
**Benefit:** LOW (detail level, not correctness)
**Recommendation:** DEFER unless user specifically requests

---

### Issue 7: Metrics Display Order

**Current State (R):**
```r
# Custom grouping: M1,M6,M2 / M5,M4,M3,M7
```

**Target State (Rust):**
```r
# Sequential: M1,M2,M3,M4 / M5,M6,M7
```

**Implementation Steps:**
1. Reorder metrics breakdown in `export_explanation_md.R`
2. Update benefit card ordering

**Effort:** TRIVIAL (5 minutes)
**Impact:** Cosmetic only
**Recommendation:** Quick fix if desired

---

## Implementation Plan

### Phase 1: Critical Fixes (Day 1 - 2 hours)

**Priority Order:**
1. ✅ **pH Compatibility** (1 hour)
   - Add `compute_ph_compatibility()` function
   - Integrate into explanation engine
   - Test with guilds of varying pH ranges

2. ✅ **Star Rating Alignment** (15 minutes)
   - Update both files with 6-level system
   - Verify consistency

3. ✅ **M1 Risk Cards** (45 minutes)
   - Add M1<30 check
   - Generate risk card structure
   - Test with low-diversity guild

### Phase 2: High-Medium Fixes (Day 1 - 1 hour)

4. ✅ **M2 CSR Warning Logic** (30 minutes)
   - Investigate current behavior
   - Update condition if needed
   - Test edge cases

5. ✅ **Nitrogen Threshold** (15 minutes)
   - Change >0 to >2
   - Update severity and message

### Phase 3: Testing & Validation (Day 2 - 1-2 hours)

6. ✅ **Regenerate Test Guilds**
   - Run all 5 test guilds through updated R engine
   - Compare outputs with Rust side-by-side
   - Verify all differences are resolved

7. ✅ **Edge Case Testing**
   - Single plant guild
   - Missing pH data
   - Zero conflicts
   - Low M1 scores

### Phase 4: Optional Enhancements (Deferred)

8. ⏸️ **M6 Detailed Stratification** (3-4 hours if requested)
9. ⏸️ **Metrics Display Order** (5 minutes if requested)

---

## Testing Strategy

### Test Guilds

Use existing 5 test guilds with known characteristics:

1. **biocontrol_powerhouse** - High M3, should show benefit
2. **entomopathogen_powerhouse** - High M4, should show benefit
3. **forest_garden** - Multiple metrics high, check star rating
4. **competitive_clash** - M2 conflicts, test CSR warning logic
5. **stress-tolerant** - Low scores, test risk cards and unsuitable rating

### Verification Checklist

For each test guild, compare R vs Rust outputs:

- [ ] Star rating matches (same stars and label)
- [ ] pH compatibility warning matches (or both absent)
- [ ] M1 risk card matches (or both absent)
- [ ] M2 CSR warning matches
- [ ] Nitrogen warning matches (or both absent)
- [ ] Benefit card thresholds match
- [ ] Overall score identical

### Success Criteria

**Phase 1-2 Complete:**
- All CRITICAL and HIGH priority issues resolved
- Test guilds show identical warnings and risk cards
- Star ratings aligned

**Full Parity Achieved:**
- R explanation output matches Rust output character-for-character (except optional M6 detail)
- No functional differences in user-facing text

---

## File Modification Summary

### Primary Files

**1. `explanation_engine_7metric.R` (Main engine)**
- Lines 36-40: Update star rating thresholds (Issue 2)
- Line 85+: Add M1 risk card logic (Issue 3)
- Line 150+: Add pH compatibility function (Issue 1)
- Line 156: Update nitrogen threshold (Issue 5)
- Lines 166-170: Update M2 CSR condition (Issue 4)

**2. `export_explanation_md.R` (Formatter)**
- Lines 90-96: Update star rating thresholds (Issue 2)
- Add pH warning formatting
- Add M1 risk card formatting

### Helper Functions to Add

```r
# Add to explanation_engine_7metric.R

compute_ph_compatibility <- function(guild_plants) {
  # Extract EIVE R values
  # Calculate range
  # Determine severity
  # Generate warning message
  # Return list(flag, severity, message, r_min, r_max, r_range)
}

generate_ph_warning_message <- function(guild_plants, r_min, r_max, r_range) {
  # Map EIVE R to pH categories
  # List plants with their pH preferences
  # Generate advice text
  # Return formatted message
}

generate_m1_risk_card <- function(m1_result) {
  # Check if M1 < 30
  # Extract Faith's PD
  # Generate risk card structure
  # Return risk card list or NULL
}
```

---

## Rollout Plan

### Pre-Implementation

1. Create feature branch: `explanation-engine-parity`
2. Backup current test guild outputs for comparison
3. Document current R behavior for regression testing

### Implementation

1. Implement Phase 1 (Critical) - commit after each fix
2. Run test suite after each commit
3. Implement Phase 2 (High-Medium) - commit together
4. Run full test suite

### Testing

1. Regenerate all 5 test guilds
2. Side-by-side comparison with Rust outputs
3. Document any remaining differences
4. Get user approval

### Deployment

1. Merge to main after approval
2. Update documentation to reflect parity
3. Archive old test outputs
4. Update R_vs_Rust_explanation_engine report with "RESOLVED" status

---

## Risk Assessment

### Low Risk Changes

- Star rating thresholds: Simple logic change, well-tested
- Nitrogen threshold: Threshold change, minimal impact
- M2 CSR condition: Conditional logic, easy to verify

### Medium Risk Changes

- pH compatibility: New feature, needs thorough testing with edge cases
- M1 risk cards: New feature, needs verification against Rust

### Mitigation Strategies

- Incremental commits (one fix per commit)
- Test suite run after each change
- Side-by-side comparison with Rust for each guild
- Regression testing with existing guilds

---

## Dependencies

### Required Data
- Guild plants with EIVE R values (pH compatibility)
- M1 Faith's PD values (risk cards)
- M2 conflict details (CSR warnings)

### Required Functions (Already Exist)
- Metric calculation functions (M1-M7)
- Percentile normalization
- Calibration file loading

### No External Dependencies
- All changes are self-contained within explanation engine
- No new R packages needed
- No data format changes required

---

## Expected Outcomes

### After Phase 1-2 (Critical + High)

**User-Facing Changes:**
- pH incompatibility warnings now appear (critical for user experience)
- More conservative star ratings (85 → 4★ instead of 5★)
- Pest vulnerability warnings for low-diversity guilds
- More accurate CSR conflict warnings

**Technical Changes:**
- R explanation engine matches Rust logic for all warnings
- Consistent star rating across R API and markdown output
- Complete parity in user-facing text (except optional M6 detail)

### After Full Implementation

**Achievement:**
- ✅ R and Rust generate identical explanations
- ✅ Same calibration files used
- ✅ Same warning thresholds
- ✅ Same benefit thresholds
- ✅ Same risk detection logic

**Remaining Optional Differences:**
- M6 detail level (R simple, Rust verbose) - cosmetic only
- Metrics display order - cosmetic only

---

## Appendix A: Code References

### Rust Reference Files

**Core Logic:**
- `src/explanation/generator.rs` - Main explanation generator
- `src/explanation/fragments/m6_fragment.rs` - M6 detailed stratification
- `src/scorer.rs` - pH compatibility calculation

**Key Line Numbers:**
- Star rating: `generator.rs` lines 151-158
- pH compatibility: `scorer.rs` lines 365-392
- M1 risk cards: `generator.rs` lines 258-275
- M2 CSR warnings: `generator.rs` lines 217-232
- Nitrogen warnings: `generator.rs` lines 194-206

### R Reference Files

**Core Logic:**
- `explanation_engine_7metric.R` - Main explanation generator
- `export_explanation_md.R` - Markdown formatter
- `guild_scorer_v3_modular.R` - Metric scoring wrapper

**Key Line Numbers:**
- Star rating: `explanation_engine_7metric.R` lines 36-40
- pH (missing): Would go around line 150
- M1 risks (missing): Would go around line 85
- M2 CSR: Lines 166-170
- Nitrogen: Line 156

---

## Appendix B: Testing Examples

### Example 1: pH Compatibility

**Test Guild:** Plants with EIVE R values 5.2 (acidic), 6.5 (neutral), 7.8 (alkaline)

**Expected R Output (After Fix):**
```
⚡ Soil pH incompatibility detected

EIVE R range: 5.2-7.8 (difference: 2.6 units)

Plant pH preferences:
- Quercus robur: Slightly Acidic (pH 5-6)
- Fragaria vesca: Neutral (pH 6-7)
- Vitis vinifera: Alkaline (pH 7-8)

Advice: Moderate pH incompatibility. Use soil amendments to adjust pH for different zones.
```

### Example 2: M1 Risk Card

**Test Guild:** 3 plants from Rosaceae family, low PD

**Expected R Output (After Fix):**
```
🦠 Closely Related Plants

Guild contains closely related plants that may share pests
Low phylogenetic diversity (Faith's PD: 245.52) increases pest/pathogen risk

Advice: Consider adding plants from different families to increase diversity
```

### Example 3: Star Rating Change

**Test Score:** 85/100

**Current R Output:**
```
★★★★★ - Excellent
```

**Expected R Output (After Fix):**
```
★★★★☆ - Excellent
```

(Matches Rust - more conservative threshold)

---

## Next Steps

1. **User Review:** Approve this plan and prioritize Phase 1-2 implementation
2. **Implementation:** Execute Phase 1-2 fixes (estimated 3 hours)
3. **Testing:** Regenerate test guilds and verify parity (1-2 hours)
4. **Decision:** Determine if Phase 4 (M6 detail) is desired
5. **Documentation:** Update comparison report to mark issues as RESOLVED

---

**Total Estimated Time:** 4-6 hours for full parity (excluding optional M6 detail)
**Priority:** High - affects user experience and scientific accuracy
**Complexity:** Medium - mostly threshold and logic changes, well-defined scope
