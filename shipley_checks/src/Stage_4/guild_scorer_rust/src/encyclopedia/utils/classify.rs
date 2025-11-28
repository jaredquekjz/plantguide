//! Classification functions for encyclopedia generation.
//!
//! Implements thresholds and classification logic from planning docs.

use crate::encyclopedia::types::*;

// ============================================================================
// CSR Classification (Spread-based)
// ============================================================================

/// CSR spread threshold for balanced classification.
/// Plants with SPREAD < 20% are considered balanced (no dominant strategy).
pub const CSR_SPREAD_THRESHOLD: f64 = 20.0;

/// Classify CSR strategy using SPREAD-based approach.
/// SPREAD = MAX(C,S,R) - MIN(C,S,R)
/// - If SPREAD < 20%: Balanced (no clear dominant strategy)
/// - Otherwise: Dominant = axis with highest value
pub fn classify_csr_spread(c: f64, s: f64, r: f64) -> CsrStrategy {
    let max_val = c.max(s).max(r);
    let min_val = c.min(s).min(r);
    let spread = max_val - min_val;

    if spread < CSR_SPREAD_THRESHOLD {
        CsrStrategy::Balanced
    } else if c >= s && c >= r {
        CsrStrategy::CDominant
    } else if s >= c && s >= r {
        CsrStrategy::SDominant
    } else {
        CsrStrategy::RDominant
    }
}

/// Get descriptive CSR label using spread-based classification.
/// Returns labels like "C-dominant", "S-dominant", "R-dominant", or "Balanced".
pub fn csr_spread_label(c: f64, s: f64, r: f64) -> &'static str {
    let max_val = c.max(s).max(r);
    let min_val = c.min(s).min(r);
    let spread = max_val - min_val;

    if spread < CSR_SPREAD_THRESHOLD {
        "Balanced"
    } else if c >= s && c >= r {
        "C-dominant"
    } else if s >= c && s >= r {
        "S-dominant"
    } else {
        "R-dominant"
    }
}

// ============================================================================
// Legacy CSR Classification (Percentile-based) - Kept for Reference
// ============================================================================

/// CSR percentile thresholds (p75) from csr_percentile_calibration_global.json
/// Plants above these raw values are in the top 25% for that strategy.
/// NOTE: Legacy approach - use classify_csr_spread for new code.
pub const CSR_P75_C: f64 = 41.3;  // C percentile > 75
pub const CSR_P75_S: f64 = 72.2;  // S percentile > 75
pub const CSR_P75_R: f64 = 47.6;  // R percentile > 75

/// Classify CSR strategy using PERCENTILE thresholds (legacy approach).
/// NOTE: Use classify_csr_spread instead - percentile approach has known issues
/// where plants with S=55% (highest) can be classified as "C-dominant" if C=42%.
#[allow(dead_code)]
pub fn classify_csr_percentile(c: f64, s: f64, r: f64) -> CsrStrategy {
    // Percentile-based: compare against p75 thresholds
    let c_dom = c > CSR_P75_C;
    let s_dom = s > CSR_P75_S;
    let r_dom = r > CSR_P75_R;

    // If multiple are dominant, prioritize C > S > R
    if c_dom {
        CsrStrategy::CDominant
    } else if s_dom {
        CsrStrategy::SDominant
    } else if r_dom {
        CsrStrategy::RDominant
    } else {
        CsrStrategy::Balanced
    }
}

// ============================================================================
// Growth Form Classification
// ============================================================================

/// Classify growth form from height and growth_form string.
/// Decision tree from S3 doc:
/// - IF try_growth_form CONTAINS "vine" OR "liana": Vine
/// - ELSE IF height > 5m: Tree
/// - ELSE IF height > 1m: Shrub
/// - ELSE: Herb
pub fn classify_growth_form(growth_form: Option<&str>, height_m: Option<f64>) -> GrowthFormCategory {
    // Check for vine/liana first
    if let Some(form) = growth_form {
        let form_lower = form.to_lowercase();
        if form_lower.contains("vine") || form_lower.contains("liana") || form_lower.contains("climber") {
            return GrowthFormCategory::Vine;
        }
        // Explicit tree classification
        if form_lower.contains("tree") {
            if height_m.unwrap_or(0.0) > 5.0 {
                return GrowthFormCategory::Tree;
            }
        }
    }

    // Height-based classification
    match height_m {
        Some(h) if h > 5.0 => GrowthFormCategory::Tree,
        Some(h) if h > 1.0 => GrowthFormCategory::Shrub,
        _ => GrowthFormCategory::Herb,
    }
}

// ============================================================================
// Structural Layer Classification
// ============================================================================

/// Classify structural layer from height.
/// From S6 doc:
/// - > 10m: Canopy
/// - 5-10m: Sub-canopy
/// - 2-5m: Tall shrub
/// - 0.5-2m: Understory
/// - < 0.5m: Ground cover
pub fn classify_structural_layer(height_m: Option<f64>) -> StructuralLayer {
    match height_m {
        Some(h) if h > 10.0 => StructuralLayer::Canopy,
        Some(h) if h > 5.0 => StructuralLayer::SubCanopy,
        Some(h) if h > 2.0 => StructuralLayer::TallShrub,
        Some(h) if h > 0.5 => StructuralLayer::Understory,
        _ => StructuralLayer::GroundCover,
    }
}

// ============================================================================
// Mycorrhizal Classification
// ============================================================================

/// Classify mycorrhizal type from AMF/EMF counts.
/// From S6 doc:
/// - AMF + EMF = Dual
/// - AMF only = AMF
/// - EMF only = EMF
/// - Neither = Non-mycorrhizal
pub fn classify_mycorrhizal(amf_count: usize, emf_count: usize) -> MycorrhizalType {
    match (amf_count > 0, emf_count > 0) {
        (true, true) => MycorrhizalType::Dual,
        (true, false) => MycorrhizalType::AMF,
        (false, true) => MycorrhizalType::EMF,
        (false, false) => MycorrhizalType::NonMycorrhizal,
    }
}

// ============================================================================
// Maintenance Level Classification
// ============================================================================

/// Calculate maintenance level from CSR strategy using spread-based classification.
/// From S3 doc spread-based classification:
///
/// | Dominant Strategy | Highest Value | Maintenance Level |
/// |------------------|---------------|-------------------|
/// | S-dominant       | ≥ 60%         | LOW               |
/// | S-dominant       | 40-59%        | LOW-MEDIUM        |
/// | C-dominant       | ≥ 60%         | HIGH              |
/// | C-dominant       | 40-59%        | MEDIUM-HIGH       |
/// | R-dominant       | any           | MEDIUM            |
/// | Balanced         | (spread < 20%)| MEDIUM            |
pub fn classify_maintenance_level(c: f64, s: f64, r: f64) -> MaintenanceLevel {
    let strategy = classify_csr_spread(c, s, r);
    let max_val = c.max(s).max(r);

    match strategy {
        CsrStrategy::SDominant => {
            if max_val >= 60.0 {
                MaintenanceLevel::Low
            } else {
                MaintenanceLevel::LowMedium
            }
        }
        CsrStrategy::CDominant => {
            if max_val >= 60.0 {
                MaintenanceLevel::High
            } else {
                MaintenanceLevel::MediumHigh
            }
        }
        CsrStrategy::RDominant => MaintenanceLevel::Medium,
        CsrStrategy::Balanced => MaintenanceLevel::Medium,
    }
}

/// Size scaling multiplier for maintenance time.
/// From S3 doc:
/// - Height < 1m: ×0.5
/// - Height 1-2m: ×1.0
/// - Height 2-4m: ×1.5
/// - Height > 4m: ×2.0
pub fn size_scaling_multiplier(height_m: Option<f64>) -> f64 {
    match height_m {
        Some(h) if h > 4.0 => 2.0,
        Some(h) if h > 2.0 => 1.5,
        Some(h) if h > 1.0 => 1.0,
        _ => 0.5,
    }
}

// ============================================================================
// Height Classification
// ============================================================================

/// Height category for display.
/// From S1 doc.
pub fn classify_height_category(height_m: Option<f64>) -> &'static str {
    match height_m {
        Some(h) if h > 20.0 => "Large tree (>20m)",
        Some(h) if h > 10.0 => "Medium tree (10-20m)",
        Some(h) if h > 3.0 => "Tall shrub/Small tree (3-10m)",
        Some(h) if h > 1.0 => "Medium (1-3m)",
        Some(h) if h > 0.3 => "Low (0.3-1m)",
        Some(_) => "Ground cover (<0.3m)",
        None => "Unknown height",
    }
}

// ============================================================================
// USDA Hardiness Zone
// ============================================================================

/// Derive USDA hardiness zone from absolute minimum temperature (TNn_q05).
/// From S1/S2 docs.
pub fn classify_hardiness_zone(tnn_q05: Option<f64>) -> Option<(u8, &'static str)> {
    tnn_q05.map(|t| {
        if t < -45.6 { (1, "Zone 1 - Extreme arctic") }
        else if t < -40.0 { (2, "Zone 2 - Subarctic") }
        else if t < -34.4 { (3, "Zone 3 - Very cold") }
        else if t < -28.9 { (4, "Zone 4 - Cold") }
        else if t < -23.3 { (5, "Zone 5 - Cold temperate") }
        else if t < -17.8 { (6, "Zone 6 - Cool temperate") }
        else if t < -12.2 { (7, "Zone 7 - Mild temperate") }
        else if t < -6.7 { (8, "Zone 8 - Warm temperate") }
        else if t < -1.1 { (9, "Zone 9 - Subtropical") }
        else if t < 4.4 { (10, "Zone 10 - Tropical margin") }
        else { (11, "Zone 11+ - Tropical") }
    })
}

// ============================================================================
// EIVE Semantic Labels
// ============================================================================

/// Light preference label from EIVE-L.
pub fn eive_light_label(eive_l: Option<f64>) -> &'static str {
    match eive_l {
        Some(l) if l < 2.0 => "Deep shade",
        Some(l) if l < 4.0 => "Shade",
        Some(l) if l < 6.0 => "Partial shade",
        Some(l) if l < 8.0 => "Full sun to part shade",
        Some(_) => "Full sun",
        None => "Unknown",
    }
}

/// Moisture preference label from EIVE-M.
pub fn eive_moisture_label(eive_m: Option<f64>) -> &'static str {
    match eive_m {
        Some(m) if m < 2.0 => "Extreme drought tolerance",
        Some(m) if m < 4.0 => "Dry conditions preferred",
        Some(m) if m < 6.0 => "Moderate moisture",
        Some(m) if m < 8.0 => "Moist conditions preferred",
        Some(_) => "Wet/waterlogged tolerance",
        None => "Unknown",
    }
}

/// Temperature preference label from EIVE-T.
pub fn eive_temperature_label(eive_t: Option<f64>) -> &'static str {
    match eive_t {
        Some(t) if t < 2.0 => "Arctic-alpine; cool summers essential",
        Some(t) if t < 4.0 => "Boreal/montane; cool temperate",
        Some(t) if t < 6.0 => "Temperate; typical UK/NW Europe",
        Some(t) if t < 8.0 => "Warm temperate; Mediterranean margin",
        Some(_) => "Subtropical; warm conditions preferred",
        None => "Unknown",
    }
}

/// Soil pH preference label from EIVE-R.
pub fn eive_reaction_label(eive_r: Option<f64>) -> &'static str {
    match eive_r {
        Some(r) if r < 2.0 => "Strongly acidic (calcifuge)",
        Some(r) if r < 4.0 => "Moderately acidic",
        Some(r) if r < 6.0 => "Slightly acidic to neutral",
        Some(r) if r < 8.0 => "Neutral to slightly alkaline",
        Some(_) => "Calcareous/alkaline (calcicole)",
        None => "Unknown",
    }
}

/// Nitrogen preference label from EIVE-N.
pub fn eive_nitrogen_label(eive_n: Option<f64>) -> &'static str {
    match eive_n {
        Some(n) if n < 2.0 => "Oligotrophic (infertile)",
        Some(n) if n < 4.0 => "Low nutrient",
        Some(n) if n < 6.0 => "Moderate nutrient",
        Some(n) if n < 8.0 => "High nutrient",
        Some(_) => "Eutrophic (manure-rich)",
        None => "Unknown",
    }
}

// ============================================================================
// Pollinator Level Classification (S5/S6)
// ============================================================================

/// Pollinator level from count (S5 doc thresholds).
pub fn classify_pollinator_level(count: usize) -> (&'static str, &'static str) {
    match count {
        45.. => ("Exceptional", "Major pollinator resource (top 10%)"),
        20..=44 => ("Very High", "Strong pollinator magnet"),
        6..=19 => ("Typical", "Average pollinator observations"),
        2..=5 => ("Low", "Few pollinators observed"),
        _ => ("Minimal/No data", "Not documented (may still be visited)"),
    }
}

/// Herbivore/pest level from count (S5 doc thresholds).
pub fn classify_pest_level(count: usize) -> (&'static str, &'static str) {
    match count {
        16.. => ("High", "Multiple pest species; monitor closely"),
        6..=15 => ("Above average", "Some pest pressure expected"),
        2..=5 => ("Typical", "Average pest observations"),
        1 => ("Low", "Few documented pests"),
        0 => ("No data", "Not well-studied or pest-free"),
    }
}

/// Pathogen/disease level from count (S5/S6 doc thresholds).
pub fn classify_disease_level(count: usize) -> (&'static str, &'static str) {
    match count {
        15.. => ("High", "Many diseases observed; avoid clustering same-disease plants"),
        7..=14 => ("Above average", "More diseases than typical"),
        3..=6 => ("Typical", "Average disease observations"),
        1..=2 => ("Low", "Few diseases observed"),
        0 => ("No data", "Not well-documented"),
    }
}

/// Predator habitat level from count (S6 doc thresholds).
pub fn classify_predator_level(count: usize) -> (&'static str, &'static str) {
    match count {
        29.. => ("Very high", "Excellent habitat for beneficial insects (top 10%)"),
        9..=28 => ("Above average", "Good predator habitat"),
        3..=8 => ("Typical", "Average predator observations"),
        1..=2 => ("Low", "Few predators observed"),
        0 => ("No data", "No predator observations (data gap)"),
    }
}

// ============================================================================
// Ecosystem Service Rating Conversion
// ============================================================================

/// Convert categorical rating string to display format.
pub fn format_rating(rating: Option<&str>) -> String {
    match rating {
        Some("Very High") => "Very High (5.0)".to_string(),
        Some("High") => "High (4.0)".to_string(),
        Some("Moderate") => "Moderate (3.0)".to_string(),
        Some("Low") => "Low (2.0)".to_string(),
        Some("Very Low") => "Very Low (1.0)".to_string(),
        Some(other) => other.to_string(),
        None => "Unable to Classify".to_string(),
    }
}

/// Get numeric score from rating string.
pub fn rating_to_numeric(rating: Option<&str>) -> Option<f64> {
    match rating {
        Some("Very High") => Some(5.0),
        Some("High") => Some(4.0),
        Some("Moderate") => Some(3.0),
        Some("Low") => Some(2.0),
        Some("Very Low") => Some(1.0),
        _ => None,
    }
}
