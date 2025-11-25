//! Categorization Utility Functions
//!
//! Categorical classification functions for plant traits, strategies, and
//! ecological attributes. Converts continuous/binary data to user-friendly
//! categories for encyclopedia text generation.
//!
//! Ported from R: shipley_checks/src/encyclopedia/utils/categorization.R

// ============================================================================
// CSR STRATEGY CATEGORIZATION
// ============================================================================

/// CSR strategy category
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CsrCategory {
    C,   // Competitor
    S,   // Stress-tolerator
    R,   // Ruderal
    CS,  // Competitor/Stress-tolerator mix
    CR,  // Competitor/Ruderal mix
    SR,  // Stress-tolerator/Ruderal mix
    CSR, // Generalist (balanced)
}

impl CsrCategory {
    pub fn as_str(&self) -> &'static str {
        match self {
            CsrCategory::C => "C",
            CsrCategory::S => "S",
            CsrCategory::R => "R",
            CsrCategory::CS => "CS",
            CsrCategory::CR => "CR",
            CsrCategory::SR => "SR",
            CsrCategory::CSR => "CSR",
        }
    }
}

/// Determine dominant CSR strategy from C, S, R scores.
///
/// Uses threshold logic to identify dominant strategy or mixed strategies.
/// Scores should be on 0-1 scale (normalized).
///
/// # Algorithm (from R):
/// 1. Single strategy if one score > 0.6 and others < 0.3
/// 2. Binary mix if two scores >= 0.35 and third < 0.25
/// 3. Ternary mix (CSR) if no single or binary dominance
///
/// # Returns
/// None if any input is NaN
pub fn get_csr_category(c: f64, s: f64, r: f64) -> Option<CsrCategory> {
    if c.is_nan() || s.is_nan() || r.is_nan() {
        return None;
    }

    // Normalize to 0-1 if in percentage form (0-100)
    let (c, s, r) = if c > 1.0 || s > 1.0 || r > 1.0 {
        (c / 100.0, s / 100.0, r / 100.0)
    } else {
        (c, s, r)
    };

    // Single-strategy dominance (score > 0.6, others < 0.3)
    if c > 0.6 && s < 0.3 && r < 0.3 {
        return Some(CsrCategory::C);
    }
    if s > 0.6 && c < 0.3 && r < 0.3 {
        return Some(CsrCategory::S);
    }
    if r > 0.6 && c < 0.3 && s < 0.3 {
        return Some(CsrCategory::R);
    }

    // Binary mixes (two >= 0.35, third < 0.25)
    if c >= 0.35 && s >= 0.35 && r < 0.25 {
        return Some(CsrCategory::CS);
    }
    if c >= 0.35 && r >= 0.35 && s < 0.25 {
        return Some(CsrCategory::CR);
    }
    if s >= 0.35 && r >= 0.35 && c < 0.25 {
        return Some(CsrCategory::SR);
    }

    // Default: ternary mix (center of triangle)
    Some(CsrCategory::CSR)
}

/// Get user-friendly description of CSR strategy category.
pub fn get_csr_description(category: CsrCategory) -> &'static str {
    match category {
        CsrCategory::C => "Competitor: fast-growing, resource-demanding, dominant in fertile undisturbed habitats",
        CsrCategory::S => "Stress-tolerator: slow-growing, efficient resource use, survives poor/extreme conditions",
        CsrCategory::R => "Ruderal: rapid lifecycle, opportunistic colonizer of disturbed sites",
        CsrCategory::CS => "Competitor/Stress-tolerator: vigorous growth in stressful but stable habitats",
        CsrCategory::CR => "Competitor/Ruderal: fast-growing, tolerates moderate disturbance",
        CsrCategory::SR => "Stress-tolerator/Ruderal: hardy pioneer in harsh or disturbed environments",
        CsrCategory::CSR => "Generalist: balanced strategy, adaptable to varied conditions",
    }
}

// ============================================================================
// KÖPPEN CLIMATE ZONE MAPPING
// ============================================================================

/// Map Köppen tier (1-6) to approximate USDA hardiness zones.
///
/// Mapping logic:
/// - Tier 1 (Tropical): USDA 10-13 (frost-free, >30°F min)
/// - Tier 2 (Mediterranean): USDA 8-10 (mild winters, 10-40°F)
/// - Tier 3 (Humid temperate): USDA 6-9 (moderate, -10 to 30°F)
/// - Tier 4 (Continental): USDA 4-7 (cold winters, -30 to 10°F)
/// - Tier 5 (Boreal/Polar): USDA 1-5 (very cold, <-30°F)
/// - Tier 6 (Arid): USDA 5-9 (variable by latitude, dry)
///
/// Caveat: Köppen is based on temperature + precipitation, while USDA
/// zones only reflect minimum winter temperature. Mapping is approximate.
pub fn map_koppen_to_usda(tier: u8) -> Option<&'static str> {
    match tier {
        1 => Some("10-13"), // Tropical
        2 => Some("8-10"),  // Mediterranean
        3 => Some("6-9"),   // Humid temperate
        4 => Some("4-7"),   // Continental
        5 => Some("1-5"),   // Boreal/Polar
        6 => Some("5-9"),   // Arid
        _ => None,
    }
}

/// Get descriptive name for Köppen tier.
pub fn get_koppen_description(tier: u8) -> Option<&'static str> {
    match tier {
        1 => Some("Tropical"),
        2 => Some("Mediterranean"),
        3 => Some("Humid Temperate"),
        4 => Some("Continental"),
        5 => Some("Boreal/Polar"),
        6 => Some("Arid"),
        _ => None,
    }
}

// ============================================================================
// ECOSYSTEM SERVICE CONFIDENCE
// ============================================================================

/// Confidence level for ecosystem service ratings
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConfidenceLevel {
    High,
    Moderate,
    Low,
}

impl ConfidenceLevel {
    pub fn as_str(&self) -> &'static str {
        match self {
            ConfidenceLevel::High => "High",
            ConfidenceLevel::Moderate => "Moderate",
            ConfidenceLevel::Low => "Low",
        }
    }
}

/// Categorize ecosystem service confidence score.
///
/// Thresholds (from R):
/// - High: confidence >= 0.7
/// - Moderate: 0.4 <= confidence < 0.7
/// - Low: confidence < 0.4
pub fn categorize_confidence(confidence: f64) -> Option<ConfidenceLevel> {
    if confidence.is_nan() {
        return None;
    }

    if confidence >= 0.7 {
        Some(ConfidenceLevel::High)
    } else if confidence >= 0.4 {
        Some(ConfidenceLevel::Moderate)
    } else {
        Some(ConfidenceLevel::Low)
    }
}

// ============================================================================
// GROWTH FORM CATEGORIZATION
// ============================================================================

/// Woodiness category
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WoodinessCategory {
    Herbaceous,
    SemiWoody,
    Woody,
}

impl WoodinessCategory {
    pub fn as_str(&self) -> &'static str {
        match self {
            WoodinessCategory::Herbaceous => "Herbaceous",
            WoodinessCategory::SemiWoody => "Semi-woody",
            WoodinessCategory::Woody => "Woody",
        }
    }

    pub fn as_lowercase(&self) -> &'static str {
        match self {
            WoodinessCategory::Herbaceous => "herbaceous",
            WoodinessCategory::SemiWoody => "semi-woody",
            WoodinessCategory::Woody => "woody",
        }
    }
}

/// Categorize plant by woodiness score.
///
/// Thresholds (0-1 continuous scale, from R):
/// - Herbaceous: woodiness < 0.3
/// - Semi-woody: 0.3 <= woodiness < 0.7 (subshrubs)
/// - Woody: woodiness >= 0.7 (shrubs, trees)
pub fn categorize_woodiness(woodiness: f64) -> Option<WoodinessCategory> {
    if woodiness.is_nan() {
        return None;
    }

    if woodiness < 0.3 {
        Some(WoodinessCategory::Herbaceous)
    } else if woodiness < 0.7 {
        Some(WoodinessCategory::SemiWoody)
    } else {
        Some(WoodinessCategory::Woody)
    }
}

// ============================================================================
// HEIGHT CATEGORIZATION
// ============================================================================

/// Height category for garden planning
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HeightCategory {
    GroundCover, // < 0.3m
    Low,         // 0.3-1m
    Medium,      // 1-2.5m
    Tall,        // 2.5-5m
    VeryTall,    // >= 5m
}

impl HeightCategory {
    pub fn as_str(&self) -> &'static str {
        match self {
            HeightCategory::GroundCover => "Ground cover",
            HeightCategory::Low => "Low",
            HeightCategory::Medium => "Medium",
            HeightCategory::Tall => "Tall",
            HeightCategory::VeryTall => "Very tall",
        }
    }

    pub fn as_lowercase(&self) -> &'static str {
        match self {
            HeightCategory::GroundCover => "ground cover",
            HeightCategory::Low => "low",
            HeightCategory::Medium => "medium",
            HeightCategory::Tall => "tall",
            HeightCategory::VeryTall => "very tall",
        }
    }
}

/// Categorize plant height for garden planning.
///
/// Thresholds (from R):
/// - Ground cover: < 0.3m (< 1 ft)
/// - Low: 0.3-1m (1-3 ft)
/// - Medium: 1-2.5m (3-8 ft)
/// - Tall: 2.5-5m (8-16 ft)
/// - Very tall: >= 5m (>16 ft)
pub fn categorize_height(height_m: f64) -> Option<HeightCategory> {
    if height_m.is_nan() || height_m < 0.0 {
        return None;
    }

    if height_m < 0.3 {
        Some(HeightCategory::GroundCover)
    } else if height_m < 1.0 {
        Some(HeightCategory::Low)
    } else if height_m < 2.5 {
        Some(HeightCategory::Medium)
    } else if height_m < 5.0 {
        Some(HeightCategory::Tall)
    } else {
        Some(HeightCategory::VeryTall)
    }
}

// ============================================================================
// MAINTENANCE LEVEL
// ============================================================================

/// Maintenance level derived from CSR strategy
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MaintenanceLevel {
    Low,
    LowMedium,
    Medium,
    MediumHigh,
    High,
}

impl MaintenanceLevel {
    pub fn as_str(&self) -> &'static str {
        match self {
            MaintenanceLevel::Low => "LOW",
            MaintenanceLevel::LowMedium => "LOW-MEDIUM",
            MaintenanceLevel::Medium => "MEDIUM",
            MaintenanceLevel::MediumHigh => "MEDIUM-HIGH",
            MaintenanceLevel::High => "HIGH",
        }
    }
}

/// Calculate maintenance level from CSR scores.
///
/// Rationale:
/// - C-dominant = high maintenance (fast growth, vigorous)
/// - S-dominant = low maintenance (slow growth, hardy)
/// - R-dominant = medium (opportunistic but not as vigorous as C)
pub fn calculate_maintenance_level(c: f64, s: f64, r: f64) -> Option<MaintenanceLevel> {
    if c.is_nan() || s.is_nan() || r.is_nan() {
        return Some(MaintenanceLevel::Medium); // Default
    }

    // Normalize to 0-1 if in percentage form
    let (c, s, r) = if c > 1.0 || s > 1.0 || r > 1.0 {
        (c / 100.0, s / 100.0, r / 100.0)
    } else {
        (c, s, r)
    };

    // Thresholds based on CSR triangle partitioning
    if c > 0.6 {
        Some(MaintenanceLevel::High)
    } else if s > 0.6 {
        Some(MaintenanceLevel::Low)
    } else if r > 0.6 {
        Some(MaintenanceLevel::Medium)
    } else {
        // Mixed strategies
        if c > s && c > r {
            Some(MaintenanceLevel::MediumHigh)
        } else if s > c && s > r {
            Some(MaintenanceLevel::LowMedium)
        } else {
            Some(MaintenanceLevel::Medium)
        }
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    // ---- CSR Category Tests ----

    #[test]
    fn test_csr_single_dominance() {
        // C dominant
        assert_eq!(get_csr_category(0.8, 0.1, 0.1), Some(CsrCategory::C));
        // S dominant
        assert_eq!(get_csr_category(0.1, 0.8, 0.1), Some(CsrCategory::S));
        // R dominant
        assert_eq!(get_csr_category(0.1, 0.1, 0.8), Some(CsrCategory::R));
    }

    #[test]
    fn test_csr_binary_mixes() {
        // CS mix
        assert_eq!(get_csr_category(0.4, 0.5, 0.1), Some(CsrCategory::CS));
        // CR mix
        assert_eq!(get_csr_category(0.4, 0.1, 0.5), Some(CsrCategory::CR));
        // SR mix
        assert_eq!(get_csr_category(0.1, 0.4, 0.5), Some(CsrCategory::SR));
    }

    #[test]
    fn test_csr_generalist() {
        // Balanced - should be CSR
        assert_eq!(get_csr_category(0.35, 0.35, 0.3), Some(CsrCategory::CSR));
        assert_eq!(get_csr_category(0.33, 0.33, 0.34), Some(CsrCategory::CSR));
    }

    #[test]
    fn test_csr_percentage_normalization() {
        // Should handle 0-100 scale
        assert_eq!(get_csr_category(80.0, 10.0, 10.0), Some(CsrCategory::C));
    }

    #[test]
    fn test_csr_nan_handling() {
        assert_eq!(get_csr_category(f64::NAN, 0.5, 0.5), None);
    }

    // ---- Köppen Mapping Tests ----

    #[test]
    fn test_koppen_usda_mapping() {
        assert_eq!(map_koppen_to_usda(1), Some("10-13")); // Tropical
        assert_eq!(map_koppen_to_usda(2), Some("8-10"));  // Mediterranean
        assert_eq!(map_koppen_to_usda(3), Some("6-9"));   // Humid temperate
        assert_eq!(map_koppen_to_usda(4), Some("4-7"));   // Continental
        assert_eq!(map_koppen_to_usda(5), Some("1-5"));   // Boreal
        assert_eq!(map_koppen_to_usda(6), Some("5-9"));   // Arid
        assert_eq!(map_koppen_to_usda(7), None);          // Invalid
    }

    // ---- Confidence Tests ----

    #[test]
    fn test_confidence_categorization() {
        assert_eq!(categorize_confidence(0.8), Some(ConfidenceLevel::High));
        assert_eq!(categorize_confidence(0.7), Some(ConfidenceLevel::High));
        assert_eq!(categorize_confidence(0.5), Some(ConfidenceLevel::Moderate));
        assert_eq!(categorize_confidence(0.4), Some(ConfidenceLevel::Moderate));
        assert_eq!(categorize_confidence(0.3), Some(ConfidenceLevel::Low));
        assert_eq!(categorize_confidence(f64::NAN), None);
    }

    // ---- Woodiness Tests ----

    #[test]
    fn test_woodiness_categorization() {
        assert_eq!(categorize_woodiness(0.1), Some(WoodinessCategory::Herbaceous));
        assert_eq!(categorize_woodiness(0.29), Some(WoodinessCategory::Herbaceous));
        assert_eq!(categorize_woodiness(0.3), Some(WoodinessCategory::SemiWoody));
        assert_eq!(categorize_woodiness(0.5), Some(WoodinessCategory::SemiWoody));
        assert_eq!(categorize_woodiness(0.7), Some(WoodinessCategory::Woody));
        assert_eq!(categorize_woodiness(1.0), Some(WoodinessCategory::Woody));
        assert_eq!(categorize_woodiness(f64::NAN), None);
    }

    // ---- Height Tests ----

    #[test]
    fn test_height_categorization() {
        assert_eq!(categorize_height(0.1), Some(HeightCategory::GroundCover));
        assert_eq!(categorize_height(0.29), Some(HeightCategory::GroundCover));
        assert_eq!(categorize_height(0.3), Some(HeightCategory::Low));
        assert_eq!(categorize_height(0.5), Some(HeightCategory::Low));
        assert_eq!(categorize_height(1.0), Some(HeightCategory::Medium));
        assert_eq!(categorize_height(2.0), Some(HeightCategory::Medium));
        assert_eq!(categorize_height(2.5), Some(HeightCategory::Tall));
        assert_eq!(categorize_height(4.0), Some(HeightCategory::Tall));
        assert_eq!(categorize_height(5.0), Some(HeightCategory::VeryTall));
        assert_eq!(categorize_height(25.0), Some(HeightCategory::VeryTall));
        assert_eq!(categorize_height(f64::NAN), None);
        assert_eq!(categorize_height(-1.0), None);
    }

    // ---- Maintenance Level Tests ----

    #[test]
    fn test_maintenance_level() {
        // C-dominant -> High
        assert_eq!(calculate_maintenance_level(0.7, 0.2, 0.1), Some(MaintenanceLevel::High));
        // S-dominant -> Low
        assert_eq!(calculate_maintenance_level(0.2, 0.7, 0.1), Some(MaintenanceLevel::Low));
        // R-dominant -> Medium
        assert_eq!(calculate_maintenance_level(0.2, 0.1, 0.7), Some(MaintenanceLevel::Medium));
        // Mixed with C leading -> Medium-High
        assert_eq!(calculate_maintenance_level(0.5, 0.3, 0.2), Some(MaintenanceLevel::MediumHigh));
        // Mixed with S leading -> Low-Medium
        assert_eq!(calculate_maintenance_level(0.3, 0.5, 0.2), Some(MaintenanceLevel::LowMedium));
    }
}
