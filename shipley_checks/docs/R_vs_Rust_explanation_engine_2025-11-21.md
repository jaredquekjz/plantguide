# R vs Rust Explanation Engine Comparison

**Date:** 2025-11-21
**Compared Implementations:**
- R: `/home/olier/ellenberg/shipley_checks/src/Stage_4/explanation_engine_7metric.R`
- R Formatter: `/home/olier/ellenberg/shipley_checks/src/Stage_4/export_explanation_md.R`
- Rust: `/home/olier/ellenberg/shipley_checks/src/Stage_4/guild_scorer_rust/src/explanation/`

## Executive Summary

Both R and Rust explanation engines use **identical calibration JSON files** and share the same core logic for benefit/warning generation. However, there are **significant differences in star rating thresholds, benefit thresholds, warning logic, and M2 CSR conflict detection** that affect user-facing explanations.

## 1. Calibration File Usage

### CRITICAL FINDING: Same Calibration Files

Both implementations load **identical JSON calibration files**:

**R Implementation** (`guild_scorer_v3_modular.R` lines 93-106):
```r
cal_file <- glue("shipley_checks/stage4/normalization_params_{calibration_type}.json")
self$calibration_params <- fromJSON(cal_file)

csr_cal_file <- "shipley_checks/stage4/csr_percentile_calibration_global.json"
self$csr_percentiles <- fromJSON(csr_cal_file)
```

**Rust Implementation** (`scorer.rs` lines 46-58):
```rust
let cal_path = format!("shipley_checks/stage4/normalization_params_{}.json", calibration_type);
let calibration = Calibration::load(cal_path, climate_tier)?;

let csr_path_str = "shipley_checks/stage4/csr_percentile_calibration_global.json";
let csr_calibration = CsrCalibration::load(csr_path)?;
```

**Result:** Both use the **same Rust-generated calibration files**. Score normalization is identical.

## 2. Star Rating Calculation

### MAJOR DIFFERENCE: Thresholds Diverge

**R Implementation** (`explanation_engine_7metric.R` lines 36-40):
```r
stars <- if (overall_score >= 80) "★★★★★"
         else if (overall_score >= 60) "★★★★☆"
         else if (overall_score >= 40) "★★★☆☆"
         else if (overall_score >= 20) "★★☆☆☆"
         else "★☆☆☆☆"
```

**Rust Implementation** (`generator.rs` lines 151-158):
```rust
let (stars, label) = match score {
    s if s >= 90.0 => ("★★★★★", "Exceptional"),
    s if s >= 80.0 => ("★★★★☆", "Excellent"),
    s if s >= 70.0 => ("★★★☆☆", "Good"),
    s if s >= 60.0 => ("★★☆☆☆", "Fair"),
    s if s >= 50.0 => ("★☆☆☆☆", "Poor"),
    _ => ("☆☆☆☆☆", "Unsuitable"),
};
```

**Impact:**

| Score | R Stars | R Label | Rust Stars | Rust Label |
|-------|---------|---------|------------|------------|
| 95 | ★★★★★ | Excellent | ★★★★★ | Exceptional |
| 85 | ★★★★★ | Excellent | ★★★★☆ | Excellent |
| 75 | ★★★★☆ | Good | ★★★☆☆ | Good |
| 65 | ★★★★☆ | Good | ★★☆☆☆ | Fair |
| 55 | ★★★☆☆ | Neutral | ★☆☆☆☆ | Poor |
| 45 | ★★★☆☆ | Neutral | ★☆☆☆☆ | Poor |
| 35 | ★★☆☆☆ | Below Average | ☆☆☆☆☆ | Unsuitable |
| 15 | ★☆☆☆☆ | Poor | ☆☆☆☆☆ | Unsuitable |

**R is MORE LENIENT**: A score of 80 gets 5 stars in R but only 4 in Rust.

**R Formatter Discrepancy** (`export_explanation_md.R` lines 90-96):
```r
get_star_rating <- function(score) {
  if (score >= 90) return("★★★★★")
  if (score >= 80) return("★★★★☆")
  if (score >= 60) return("★★★☆☆")
  if (score >= 40) return("★★☆☆☆")
  if (score >= 20) return("★☆☆☆☆")
  return("☆☆☆☆☆")
}
```

**CRITICAL:** The R markdown exporter (`export_explanation_md.R`) uses **DIFFERENT thresholds** than the R explanation engine:
- Explanation engine: 80/60/40/20 (lines 36-40)
- Markdown formatter: 90/80/60/40/20 (lines 90-96)
- **Rust matches the markdown formatter**, NOT the explanation engine

## 3. Benefit Card Generation

### Threshold Comparison

All thresholds are **identical** except for minor differences:

| Metric | R Threshold | Rust Threshold | Match? |
|--------|-------------|----------------|--------|
| M1 (Phylogenetic) | >50 | >50.0 | ✓ |
| M3 (Insect Control) | >30 | >30.0 | ✓ |
| M4 (Disease Control) | >30 | >30.0 | ✓ |
| M5 (Beneficial Fungi) | >30 | >30.0 | ✓ |
| M6 (Structural Diversity) | >50 | >50.0 | ✓ |
| M7 (Pollinator Support) | >30 | >30.0 | ✓ |

**R Implementation** (`explanation_engine_7metric.R`):
```r
# M1: Lines 111
if (!is.na(m1_score) && m1_score > 50)

# M5: Lines 124
if (!is.na(m5_score) && m5_score > 30)

# M6: Lines 138
if (!is.na(m6_score) && m6_score > 50)

# M7: Lines 154
if (!is.na(m7_score) && m7_score > 30)
```

**Rust Implementation** (fragment files):
```rust
// M1: m1_fragment.rs line 11
if display_score > 50.0 { ... }

// M5: m5_fragment.rs line 9
if display_score > 30.0 { ... }

// M6: m6_fragment.rs line 9
if display_score > 50.0 { ... }

// M7: m7_fragment.rs line 9
if display_score > 30.0 { ... }
```

**Result:** Benefit thresholds are **IDENTICAL**.

## 4. Warning Generation

### M2 CSR Conflicts: DIFFERENT LOGIC

**R Implementation** (`explanation_engine_7metric.R` lines 192-221):
```r
m2_score <- guild_result$metrics$m2
m2_conflicts <- details$m2$n_conflicts

if (!is.na(m2_score) && !is.na(m2_conflicts) && m2_score < 60 && m2_conflicts > 0) {
  # Only warn if BOTH:
  # - M2 score < 60
  # - n_conflicts > 0
}
```

**Rust Implementation** (`m2_fragment.rs` lines 9-56):
```rust
pub fn generate_m2_fragment(m2: &M2Result, _display_score: f64) -> MetricFragment {
    if m2.total_conflicts > 0.0 {
        // Warn if ANY conflicts (no score threshold check!)
        // ...
    }
}
```

**CRITICAL DIFFERENCE:**
- **R**: Requires **both** M2 < 60 **AND** conflicts > 0
- **Rust**: Only requires conflicts > 0 (ignores M2 score)

**Impact:** Rust will show CSR warnings more frequently than R.

### Nitrogen Fixation: DIFFERENT THRESHOLDS

**R Flag Generation** (`guild_scorer_v3_shipley.R` lines 941-948):
```r
if ("n_fixer" %in% colnames(guild_plants)) {
  n_fixers <- sum(!is.na(guild_plants$n_fixer) & guild_plants$n_fixer == TRUE, na.rm = TRUE)
  nitrogen_flag <- if (n_fixers > 0) glue("{n_fixers} legumes") else "None"
} else {
  # Check family for known N-fixers (Fabaceae)
  n_fixers <- sum(guild_plants$family == "Fabaceae", na.rm = TRUE)
  nitrogen_flag <- if (n_fixers > 0) glue("{n_fixers} Fabaceae") else "None"
}
```

**R Warning Display** (`explanation_engine_7metric.R` lines 224-234):
```r
nitrogen_flag <- if (is.null(flags$nitrogen)) "None" else flags$nitrogen
if (!is.na(nitrogen_flag) && nitrogen_flag != "None") {
  # Shows info warning for ANY nitrogen fixers (n_fixers > 0)
  warnings[[length(warnings) + 1]] <- list(
    type = "nitrogen_fixation",
    severity = "info",
    icon = "ℹ",
    message = glue("Nitrogen-Fixing Plants Present: {nitrogen_flag}"),
  )
}
```

**Rust Implementation** (`nitrogen.rs` lines 8-25):
```rust
pub fn check_nitrogen_fixation(guild_plants: &DataFrame) -> Result<Option<WarningCard>> {
    if let Ok(col) = guild_plants.column("nitrogen_fixation") {
        let n_fixers = col
            .str()?
            .into_iter()
            .filter(|opt| opt.map_or(false, |s| s == "Yes" || s == "yes" || s == "Y"))
            .count();

        if n_fixers > 2 {
            Ok(Some(WarningCard {
                warning_type: "nitrogen_excess".to_string(),
                severity: Severity::Medium,
                icon: "⚠️".to_string(),
                message: format!("{} nitrogen-fixing plants may over-fertilize", n_fixers),
            }))
        } else {
            Ok(None)
        }
    } else {
        Ok(None)
    }
}
```

**CRITICAL DIFFERENCE:**
- **R Threshold**: n_fixers > 0 (ANY nitrogen fixers trigger info warning)
- **Rust Threshold**: n_fixers > 2 (only >2 fixers trigger medium severity warning)

**R Severity**: Info (ℹ)
**Rust Severity**: Medium (⚠️)

**Impact:** R shows more nitrogen warnings (lower threshold) but with lower severity; Rust only warns for potential over-fertilization (>2 fixers).

### pH Incompatibility: PLACEHOLDER IN R

**R Flag Generation** (`guild_scorer_v3_shipley.R` lines 950-951):
```r
# N6: pH compatibility (placeholder)
ph_flag <- "Compatible"
```

**R Warning Display** (`explanation_engine_7metric.R` lines 237-246):
```r
ph_flag <- if (is.null(flags$soil_ph)) "Compatible" else flags$soil_ph
if (!is.na(ph_flag) && ph_flag != "Compatible") {
  # This condition NEVER fires because ph_flag is always "Compatible"
  warnings[[length(warnings) + 1]] <- list(
    type = "ph_incompatible",
    severity = "high",
    icon = "⚠",
    message = "pH Incompatibility Detected",
  )
}
```

**Rust Implementation** (`soil_ph.rs` lines 90-182):
```rust
pub fn check_ph_compatibility(guild_plants: &DataFrame) -> Result<Option<PhCompatibilityWarning>> {
    if let Ok(r_col) = guild_plants.column("soil_reaction_eive") {
        let r_values = r_col.f64()?;

        // Calculate range
        let min_r = plant_categories.iter().map(|p| p.r_value).fold(f64::INFINITY, f64::min);
        let max_r = plant_categories.iter().map(|p| p.r_value).fold(f64::NEG_INFINITY, f64::max);
        let r_range = max_r - min_r;

        // Check if range > 1.0 EIVE unit
        if r_range > 1.0 {
            let severity = if r_range > 3.0 {
                Severity::High
            } else if r_range > 2.0 {
                Severity::Medium
            } else {
                Severity::Low
            };

            // Warning with detailed pH categories and EIVE semantic binning
            Ok(Some(PhCompatibilityWarning { ... }))
        } else {
            Ok(None)
        }
    }
}
```

**CRITICAL DIFFERENCE:**
- **R**: pH flag is **HARDCODED to "Compatible"** - pH warnings **NEVER shown**
- **Rust**: Computes EIVE R range, warns if >1.0 with severity based on range magnitude (Low/Medium/High)

**Impact:** Rust provides actionable pH warnings with detailed semantic binning; R completely lacks pH compatibility checking.

## 5. Risk Card Generation

**R Implementation** (`explanation_engine_7metric.R` lines 84-100):
```r
generate_risks_explanation <- function(guild_result) {
  risks <- list()

  # Default: No specific risks detected
  risks[[1]] <- list(
    type = "none",
    severity = "none",
    icon = "✓",
    title = "No Specific Risk Factors Detected",
    message = "Guild metrics show generally compatible plants",
    detail = "Review individual metrics and observed organisms for optimization opportunities",
    advice = "Check metric breakdown for specific guidance"
  )

  return(risks)
}
```

**Rust Implementation** (`m1_fragment.rs` lines 26-38):
```rust
} else if display_score < 30.0 {
    MetricFragment::with_risk(RiskCard {
        risk_type: "pest_vulnerability".to_string(),
        severity: Severity::from_score(display_score),
        icon: "🦠".to_string(),
        title: "Closely Related Plants".to_string(),
        message: "Guild contains closely related plants that may share pests".to_string(),
        detail: format!(
            "Low phylogenetic diversity (Faith's PD: {:.2}) increases pest/pathogen risk",
            m1.faiths_pd
        ),
        advice: "Consider adding plants from different families to increase diversity".to_string(),
    })
}
```

**CRITICAL DIFFERENCE:**
- **R**: **NEVER generates risk cards** - always returns "No specific risks" placeholder
- **Rust**: Generates risk cards for M1 < 30 (pest vulnerability)

**Impact:** Rust provides actionable risk warnings; R does not.

## 6. Metrics Display Formatting

**R Implementation** (`explanation_engine_7metric.R` lines 254-271):
```r
format_metrics_display <- function(metrics) {
  universal <- list(
    list(name = "Pest Pathogen Indep (M1)", score = metrics$m1, code = "m1"),
    list(name = "Structural Diversity (M6)", score = metrics$m6, code = "m6"),
    list(name = "Growth Compatibility (M2)", score = metrics$m2, code = "m2")
  )

  bonus <- list(
    list(name = "Beneficial Fungi (M5)", score = metrics$m5, code = "m5"),
    list(name = "Disease Control (M4)", score = metrics$m4, code = "m4"),
    list(name = "Insect Control (M3)", score = metrics$m3, code = "m3"),
    list(name = "Pollinator Support (M7)", score = metrics$m7, code = "m7")
  )
}
```

**Rust Implementation** (`generator.rs` lines 189-227):
```rust
fn format_metrics_display(guild_score: &GuildScore) -> MetricsDisplay {
    let metric_names = [
        "Pest & Pathogen Independence",
        "Growth Compatibility",
        "Insect Pest Control",
        "Disease Suppression",
        "Beneficial Fungi",
        "Structural Diversity",
        "Pollinator Support",
    ];

    // Universal: M1-M4
    // Bonus: M5-M7
    for (i, (name, score)) in metric_names.iter().zip(&guild_score.metrics).enumerate() {
        if i < 4 {
            universal.push(card);
        } else {
            bonus.push(card);
        }
    }
}
```

**DIFFERENCE:**
- **R Universal**: M1, M6, M2 (out of order)
- **Rust Universal**: M1, M2, M3, M4 (sequential order)

**R Bonus**: M5, M4, M3, M7 (M4/M3 out of order)
**Rust Bonus**: M5, M6, M7 (sequential order)

**Impact:** Display order differs - Rust uses logical sequential ordering, R has custom grouping.

## 7. Text Formatting Differences

### Benefit Card Detail Text

**R** (`explanation_engine_7metric.R` line 117):
```r
detail = "Phylogenetically distant plants reduce shared pest/pathogen risk"
```

**Rust** (`m1_fragment.rs` line 20):
```rust
detail: "Distant relatives typically share fewer pests and pathogens, reducing disease spread in the guild.".to_string(),
```

**Difference:** Rust has slightly more verbose explanations ("typically share fewer" vs "reduce shared").

### M6 Structural Diversity Detail

**R** (`export_explanation_md.R` lines 400-406):
```r
md <- "### High Structural Diversity [M6]\n\n"
md <- paste0(md, sprintf("%d growth forms spanning vertical layers  \n", n_forms))
md <- paste0(md, "Different plant heights create vertical stratification, maximizing light capture and supporting diverse wildlife.  \n\n")
md <- paste0(md, sprintf("*Evidence:* Structural diversity score: %.1f/100\n\n", m6_score))
```

**Rust** (`m6_fragment.rs` lines 134-150):
```rust
// Detailed stratification analysis with:
// - Vertical layers (Canopy >15m, Understory 5-15m, Shrub 1-5m, Ground <1m)
// - Light preference classification (shade-tolerant <3.2, flexible 3.2-7.47, sun-loving >7.47)
// - Explanation of why stratification works or has issues
// - Plant-by-plant breakdown with height and EIVE-L values
```

**CRITICAL DIFFERENCE:**
- **R**: Simple summary text (8 lines total)
- **Rust**: Comprehensive stratification analysis with per-plant details, layer breakdown, and compatibility reasoning (240+ lines of logic)

**Impact:** Rust M6 benefit cards are **significantly more informative** than R.

## 8. Network Profile Analysis

Both R and Rust generate network profiles (pest, fungi, pollinator, biocontrol, pathogen control), but:

**R Markdown Exporter** (`export_explanation_md.R`):
- Includes network profile tables in markdown output
- Pest profile: Top 10 pests, vulnerable plants
- Fungi profile: Top fungi by connectivity, network hubs
- Pollinator profile: Top pollinators, hub plants
- Biocontrol profile: Matched predator/fungi pairs
- Pathogen profile: Matched antagonist pairs

**Rust Explanation Generator** (`generator.rs`):
- Stores network profiles in `Explanation` struct
- Profiles available for downstream formatting
- **MarkdownFormatter** would need to render these (not examined in this comparison)

**Note:** Network profile logic is identical (both use same data sources), but R markdown exporter has more comprehensive table rendering implemented.

## 9. Summary of Logic Differences

| Component | R Behavior | Rust Behavior | Impact |
|-----------|-----------|---------------|--------|
| **Calibration Files** | `normalization_params_{type}.json` | Same JSON files | ✓ Identical |
| **Star Rating (engine)** | 80/60/40/20 thresholds | 90/80/70/60/50 thresholds | R more lenient |
| **Star Rating (formatter)** | 90/80/60/40/20 thresholds | 90/80/70/60/50 thresholds | R formatter ≈ Rust |
| **Benefit Thresholds** | M1>50, M5>30, M6>50, M7>30 | Identical | ✓ Match |
| **M2 CSR Warning** | M2<60 AND conflicts>0 | conflicts>0 only | Rust warns more |
| **Nitrogen Warning** | >0 fixers (info) | >2 fixers (medium) | R shows more warnings |
| **pH Warning** | HARDCODED "Compatible" | >1.0 EIVE range (tiered) | R NEVER warns |
| **Risk Cards** | NEVER generated (placeholder) | M1<30 pest risk | Rust only |
| **Metrics Display Order** | M1,M6,M2 / M5,M4,M3,M7 | M1,M2,M3,M4 / M5,M6,M7 | Different grouping |
| **M6 Detail Level** | Simple text summary | Detailed stratification analysis | Rust much richer |

## 10. Recommendations

### Critical Issues

1. **pH Compatibility COMPLETELY MISSING in R**
   - R hardcodes `ph_flag <- "Compatible"` (line 951)
   - Rust computes EIVE R range and warns if >1.0 with tiered severity
   - **Recommendation:** Implement pH checking in R flag generation (copy Rust logic)
   - **Impact:** Users miss critical soil incompatibility warnings in R

2. **Star Rating Inconsistency in R**
   - `explanation_engine_7metric.R` uses 80/60/40/20
   - `export_explanation_md.R` uses 90/80/60/40/20
   - **Recommendation:** Align R explanation engine with formatter (use 90/80/60/40/20)
   - **Impact:** Same guild gets different stars in API vs markdown output

3. **Risk Cards Missing in R**
   - R always returns "No specific risks" placeholder
   - Rust generates actionable M1 pest vulnerability risks
   - **Recommendation:** Implement M1<30 risk logic in R
   - **Impact:** Users don't see pest vulnerability warnings for low-diversity guilds

4. **M2 CSR Warning Logic Divergence**
   - R requires M2<60 AND conflicts>0
   - Rust only requires conflicts>0
   - **Recommendation:** Verify intended behavior - likely Rust is correct (conflicts alone indicate incompatibility)
   - **Impact:** R may suppress legitimate CSR conflict warnings for guilds with M2 60-100

### Minor Improvements

5. **Nitrogen Warning Threshold**
   - R warns for ANY nitrogen fixers (>0) with info severity
   - Rust warns only for >2 fixers with medium severity
   - **Recommendation:** Align on Rust threshold (>2) to reduce noise - "any fixers" is too sensitive
   - **Impact:** R shows many low-value info warnings for single legumes

6. **M6 Stratification Detail**
   - Rust provides rich per-plant stratification analysis (240 lines of logic)
   - R provides simple summary (8 lines)
   - **Recommendation:** Consider porting Rust's detailed M6 logic to R if richer explanations are desired
   - **Impact:** Users get much more actionable M6 guidance in Rust

7. **Metrics Display Order**
   - R uses non-sequential grouping (M1,M6,M2 / M5,M4,M3,M7)
   - Rust uses sequential order (M1-M4 / M5-M7)
   - **Recommendation:** Standardize on sequential order for clarity
   - **Impact:** Minor UI inconsistency between R and Rust outputs

## 11. Verification Completed

1. **R Flag Generation Logic** ✓
   - Examined `guild_scorer_v3_shipley.R` lines 939-957
   - Nitrogen: >0 threshold (ANY fixers), severity info
   - pH: HARDCODED "Compatible" (no actual checking)

2. **Network Profile Rendering** (Pending)
   - Need to examine Rust `MarkdownFormatter` to verify it renders network profiles like R
   - R markdown exporter has comprehensive tables - Rust may need similar implementation

3. **Integration Testing** (Recommended)
   - Generate reports for same guilds in R and Rust
   - Compare side-by-side to identify any additional runtime differences
   - Priority: Verify M2 CSR logic behavior in practice
