//! EIVE Semantic Bins Lookup Tables
//!
//! Maps continuous EIVE scores (0-10 scale) to qualitative narrative labels.
//! Ported from R: shipley_checks/src/encyclopedia/utils/lookup_tables.R
//!
//! Data sources:
//! - L_bins.csv: Light indicator (9 classes)
//! - M_bins.csv: Moisture indicator (11 classes)
//! - T_bins.csv: Temperature indicator (12 classes)
//! - R_bins.csv: Reaction/pH indicator (9 classes)
//! - N_bins.csv: Nitrogen/fertility indicator (9 classes)


/// EIVE axis identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EiveAxis {
    Light,       // L
    Moisture,    // M
    Temperature, // T
    Reaction,    // R (pH)
    Nitrogen,    // N
}

/// A single EIVE bin with label and value range
#[derive(Debug, Clone)]
pub struct EiveBin {
    pub class: u8,
    pub label: &'static str,
    pub lower: f64,
    pub upper: f64,
}

// ============================================================================
// EMBEDDED EIVE BINS DATA
// Source: shipley_checks/src/encyclopedia/data/*.csv
// ============================================================================

static L_BINS: &[EiveBin] = &[
    EiveBin { class: 1, label: "deep shade plant (<1% relative illumination)", lower: 0.0, upper: 1.6053362367357376 },
    EiveBin { class: 2, label: "between deep shade and shade", lower: 1.6053362367357376, upper: 2.4402468081951527 },
    EiveBin { class: 3, label: "shade plant (mostly <5% relative illumination)", lower: 2.4402468081951527, upper: 3.2035578747634323 },
    EiveBin { class: 4, label: "between shade and semi-shade", lower: 3.2035578747634323, upper: 4.228452036818743 },
    EiveBin { class: 5, label: "semi-shade plant (>10% illumination, seldom full light)", lower: 4.228452036818743, upper: 5.447860885923845 },
    EiveBin { class: 6, label: "between semi-shade and semi-sun", lower: 5.447860885923845, upper: 6.501011333248853 },
    EiveBin { class: 7, label: "half-light plant (mostly well lit but tolerates shade)", lower: 6.501011333248853, upper: 7.467141697802003 },
    EiveBin { class: 8, label: "light-loving plant (rarely <40% illumination)", lower: 7.467141697802003, upper: 8.367525428703456 },
    EiveBin { class: 9, label: "full-light plant (requires full sun)", lower: 8.367525428703456, upper: 10.0 },
];

static M_BINS: &[EiveBin] = &[
    EiveBin { class: 1, label: "indicator of extreme dryness; soils often dry out", lower: 0.0, upper: 1.5058990840415756 },
    EiveBin { class: 2, label: "very dry sites; shallow soils or sand", lower: 1.5058990840415756, upper: 2.4661094549420053 },
    EiveBin { class: 3, label: "dry-site indicator; more often on dry ground", lower: 2.4661094549420053, upper: 3.2193224680865575 },
    EiveBin { class: 4, label: "moderately dry; also in dry sites with humidity", lower: 3.2193224680865575, upper: 3.9487692878652925 },
    EiveBin { class: 5, label: "fresh/mesic soils of average dampness", lower: 3.9487692878652925, upper: 4.688162299093515 },
    EiveBin { class: 6, label: "moist; upper range of fresh soils", lower: 4.688162299093515, upper: 5.3903529058605795 },
    EiveBin { class: 7, label: "constantly moist or damp but not wet", lower: 5.3903529058605795, upper: 6.072906716053945 },
    EiveBin { class: 8, label: "moist to wet; tolerates short inundation", lower: 6.072906716053945, upper: 6.777944648865165 },
    EiveBin { class: 9, label: "wet, water-saturated poorly aerated soils", lower: 6.777944648865165, upper: 7.535023171075245 },
    EiveBin { class: 10, label: "shallow water sites; often temporarily flooded", lower: 7.535023171075245, upper: 8.40132099361625 },
    EiveBin { class: 11, label: "rooted in water, emergent or floating", lower: 8.40132099361625, upper: 10.0 },
];

static T_BINS: &[EiveBin] = &[
    EiveBin { class: 1, label: "very cold climates (high alpine / arctic-boreal)", lower: 0.0, upper: 0.9128417336973594 },
    EiveBin { class: 2, label: "cold alpine to subalpine zones", lower: 0.9128417336973594, upper: 1.807954190575515 },
    EiveBin { class: 3, label: "cool; mainly subalpine and high montane", lower: 1.807954190575515, upper: 2.74471975795031 },
    EiveBin { class: 4, label: "rather cool montane climates", lower: 2.74471975795031, upper: 3.678656059173395 },
    EiveBin { class: 5, label: "moderately cool to moderately warm (montane-submontane)", lower: 3.678656059173395, upper: 4.429061683670151 },
    EiveBin { class: 6, label: "submontane / colline; mild montane", lower: 4.429061683670151, upper: 5.0879194708794255 },
    EiveBin { class: 7, label: "warm; colline, extending to mild northern areas", lower: 5.0879194708794255, upper: 5.938133059417395 },
    EiveBin { class: 8, label: "warm-submediterranean to mediterranean core", lower: 5.938133059417395, upper: 6.840896562709455 },
    EiveBin { class: 9, label: "very warm; southern-central European lowlands", lower: 6.840896562709455, upper: 7.738873905603625 },
    EiveBin { class: 10, label: "hot-submediterranean; warm Mediterranean foothills", lower: 7.738873905603625, upper: 8.50171065039674 },
    EiveBin { class: 11, label: "hot Mediterranean lowlands", lower: 8.50171065039674, upper: 9.211779157798134 },
    EiveBin { class: 12, label: "very hot / subtropical Mediterranean extremes", lower: 9.211779157798134, upper: 10.0 },
];

static R_BINS: &[EiveBin] = &[
    EiveBin { class: 1, label: "strongly acidic substrates only", lower: 0.0, upper: 1.822968912310665 },
    EiveBin { class: 2, label: "very acidic, seldom on less acidic soils", lower: 1.822968912310665, upper: 2.7297883209368274 },
    EiveBin { class: 3, label: "acid indicator; mainly acid soils", lower: 2.7297883209368274, upper: 3.5045510551139376 },
    EiveBin { class: 4, label: "slightly acidic; between acid and moderately acid", lower: 3.5045510551139376, upper: 4.41976378568784 },
    EiveBin { class: 5, label: "moderately acidic soils; occasional neutral/basic", lower: 4.41976378568784, upper: 5.409789128914085 },
    EiveBin { class: 6, label: "slightly acidic to neutral", lower: 5.409789128914085, upper: 6.376088551099505 },
    EiveBin { class: 7, label: "weakly acidic to weakly basic; absent from very acid", lower: 6.376088551099505, upper: 7.240893606081045 },
    EiveBin { class: 8, label: "between weakly basic and basic", lower: 7.240893606081045, upper: 8.053802404364234 },
    EiveBin { class: 9, label: "basic/alkaline; calcareous substrates", lower: 8.053802404364234, upper: 10.0 },
];

static N_BINS: &[EiveBin] = &[
    EiveBin { class: 1, label: "extremely infertile, oligotrophic sites", lower: 0.0, upper: 1.98295384219423 },
    EiveBin { class: 2, label: "very low fertility", lower: 1.98295384219423, upper: 2.7666156120442276 },
    EiveBin { class: 3, label: "infertile to moderately poor soils", lower: 2.7666156120442276, upper: 3.7086263418429777 },
    EiveBin { class: 4, label: "moderately poor; low fertility", lower: 3.7086263418429777, upper: 4.791965876476739 },
    EiveBin { class: 5, label: "intermediate fertility", lower: 4.791965876476739, upper: 5.710499035503474 },
    EiveBin { class: 6, label: "moderately rich soils", lower: 5.710499035503474, upper: 6.602150916587537 },
    EiveBin { class: 7, label: "rich, eutrophic sites", lower: 6.602150916587537, upper: 7.469835597495953 },
    EiveBin { class: 8, label: "very rich, high nutrient supply", lower: 7.469835597495953, upper: 8.346286662171046 },
    EiveBin { class: 9, label: "extremely rich; manure or waste sites", lower: 8.346286662171046, upper: 10.0 },
];

// ============================================================================
// LOOKUP FUNCTIONS
// ============================================================================

/// Get the semantic label for an EIVE value on a given axis.
///
/// Maps continuous EIVE score (0-10) to qualitative description.
/// Returns None if value is NaN or outside valid range.
///
/// # Examples
/// ```
/// use guild_scorer_rust::encyclopedia::utils::lookup_tables::{get_eive_label, EiveAxis};
///
/// let label = get_eive_label(8.4, EiveAxis::Light);
/// assert!(label.is_some());
/// assert!(label.unwrap().contains("light-loving"));
///
/// let label = get_eive_label(5.5, EiveAxis::Moisture);
/// assert!(label.unwrap().contains("moist"));
/// ```
pub fn get_eive_label(value: f64, axis: EiveAxis) -> Option<&'static str> {
    if value.is_nan() {
        return None;
    }

    let bins = match axis {
        EiveAxis::Light => L_BINS,
        EiveAxis::Moisture => M_BINS,
        EiveAxis::Temperature => T_BINS,
        EiveAxis::Reaction => R_BINS,
        EiveAxis::Nitrogen => N_BINS,
    };

    // Find bin where lower <= value < upper
    // Special case: value == 10.0 falls into highest bin
    for bin in bins {
        if value >= bin.lower && value < bin.upper {
            return Some(bin.label);
        }
    }

    // Edge case: exactly 10.0
    if (value - 10.0).abs() < f64::EPSILON {
        return bins.last().map(|b| b.label);
    }

    None
}

/// Get the EIVE class number for a value on a given axis.
pub fn get_eive_class(value: f64, axis: EiveAxis) -> Option<u8> {
    if value.is_nan() {
        return None;
    }

    let bins = match axis {
        EiveAxis::Light => L_BINS,
        EiveAxis::Moisture => M_BINS,
        EiveAxis::Temperature => T_BINS,
        EiveAxis::Reaction => R_BINS,
        EiveAxis::Nitrogen => N_BINS,
    };

    for bin in bins {
        if value >= bin.lower && value < bin.upper {
            return Some(bin.class);
        }
    }

    if (value - 10.0).abs() < f64::EPSILON {
        return bins.last().map(|b| b.class);
    }

    None
}

/// Get all bins for an axis (for testing/debugging)
pub fn get_bins(axis: EiveAxis) -> &'static [EiveBin] {
    match axis {
        EiveAxis::Light => L_BINS,
        EiveAxis::Moisture => M_BINS,
        EiveAxis::Temperature => T_BINS,
        EiveAxis::Reaction => R_BINS,
        EiveAxis::Nitrogen => N_BINS,
    }
}

// ============================================================================
// TESTS - Validate against R implementation
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    /// Test bin counts match R data files
    #[test]
    fn test_bin_counts_match_r() {
        // From R: nrow(.lookup_env$L_bins) etc.
        assert_eq!(L_BINS.len(), 9, "L_bins should have 9 classes");
        assert_eq!(M_BINS.len(), 11, "M_bins should have 11 classes");
        assert_eq!(T_BINS.len(), 12, "T_bins should have 12 classes");
        assert_eq!(R_BINS.len(), 9, "R_bins should have 9 classes");
        assert_eq!(N_BINS.len(), 9, "N_bins should have 9 classes");
    }

    /// Test bins are contiguous (no gaps)
    #[test]
    fn test_bins_contiguous() {
        for (axis, bins) in [
            (EiveAxis::Light, L_BINS),
            (EiveAxis::Moisture, M_BINS),
            (EiveAxis::Temperature, T_BINS),
            (EiveAxis::Reaction, R_BINS),
            (EiveAxis::Nitrogen, N_BINS),
        ] {
            // First bin starts at 0
            assert!(
                bins[0].lower.abs() < f64::EPSILON,
                "{:?} first bin should start at 0",
                axis
            );

            // Last bin ends at 10
            assert!(
                (bins.last().unwrap().upper - 10.0).abs() < f64::EPSILON,
                "{:?} last bin should end at 10",
                axis
            );

            // Each bin's upper == next bin's lower
            for i in 0..bins.len() - 1 {
                let gap = (bins[i].upper - bins[i + 1].lower).abs();
                assert!(
                    gap < 1e-10,
                    "{:?} bins {} and {} have gap: {}",
                    axis,
                    i,
                    i + 1,
                    gap
                );
            }
        }
    }

    /// Test specific values match R get_eive_label() output
    /// Verify bin boundaries match R CSV data
    #[test]
    fn test_light_labels_match_r() {
        // Light value 8.0 -> class 8 (light-loving) - within 7.467-8.367 range
        let label = get_eive_label(8.0, EiveAxis::Light).unwrap();
        assert!(
            label.contains("light-loving"),
            "L=8.0 should be 'light-loving', got: {}",
            label
        );

        // Light value 8.4 -> class 9 (full-light) - 8.4 > 8.367 boundary
        let label = get_eive_label(8.4, EiveAxis::Light).unwrap();
        assert!(
            label.contains("full-light"),
            "L=8.4 should be 'full-light', got: {}",
            label
        );

        // Light value 1.0 -> class 1 (deep shade)
        let label = get_eive_label(1.0, EiveAxis::Light).unwrap();
        assert!(
            label.contains("deep shade"),
            "L=1.0 should be 'deep shade', got: {}",
            label
        );

        // Light value 5.0 -> class 5 (semi-shade)
        let label = get_eive_label(5.0, EiveAxis::Light).unwrap();
        assert!(
            label.contains("semi-shade"),
            "L=5.0 should be 'semi-shade', got: {}",
            label
        );

        // Light value 9.5 -> class 9 (full-light)
        let label = get_eive_label(9.5, EiveAxis::Light).unwrap();
        assert!(
            label.contains("full-light"),
            "L=9.5 should be 'full-light', got: {}",
            label
        );
    }

    /// Test moisture labels match R
    /// R code: get_eive_label(5.5, "M") -> "fresh/mesic soils of average dampness"
    #[test]
    fn test_moisture_labels_match_r() {
        // M=5.5 is in class 7 "constantly moist" (5.39-6.07)
        let label = get_eive_label(5.5, EiveAxis::Moisture).unwrap();
        assert!(
            label.contains("moist"),
            "M=5.5 should contain 'moist', got: {}",
            label
        );

        // M=1.0 -> extreme dryness
        let label = get_eive_label(1.0, EiveAxis::Moisture).unwrap();
        assert!(
            label.contains("extreme dryness") || label.contains("dry"),
            "M=1.0 should indicate dryness, got: {}",
            label
        );

        // M=9.0 -> wet/water-saturated
        let label = get_eive_label(9.0, EiveAxis::Moisture).unwrap();
        assert!(
            label.contains("water") || label.contains("flooded"),
            "M=9.0 should indicate water/flooding, got: {}",
            label
        );
    }

    /// Test temperature labels match R
    #[test]
    fn test_temperature_labels_match_r() {
        // T=0.5 -> very cold
        let label = get_eive_label(0.5, EiveAxis::Temperature).unwrap();
        assert!(
            label.contains("cold") || label.contains("alpine"),
            "T=0.5 should indicate cold/alpine, got: {}",
            label
        );

        // T=6.0 -> warm
        let label = get_eive_label(6.0, EiveAxis::Temperature).unwrap();
        assert!(
            label.contains("warm") || label.contains("mediterranean"),
            "T=6.0 should indicate warm, got: {}",
            label
        );
    }

    /// Test nitrogen labels match R
    #[test]
    fn test_nitrogen_labels_match_r() {
        // N=1.5 -> extremely infertile
        let label = get_eive_label(1.5, EiveAxis::Nitrogen).unwrap();
        assert!(
            label.contains("infertile") || label.contains("oligotrophic"),
            "N=1.5 should indicate infertile, got: {}",
            label
        );

        // N=7.0 -> rich
        let label = get_eive_label(7.0, EiveAxis::Nitrogen).unwrap();
        assert!(
            label.contains("rich") || label.contains("eutrophic"),
            "N=7.0 should indicate rich, got: {}",
            label
        );
    }

    /// Test pH/reaction labels match R
    #[test]
    fn test_reaction_labels_match_r() {
        // R=1.5 -> strongly acidic
        let label = get_eive_label(1.5, EiveAxis::Reaction).unwrap();
        assert!(
            label.contains("acidic"),
            "R=1.5 should indicate acidic, got: {}",
            label
        );

        // R=8.5 -> basic/alkaline
        let label = get_eive_label(8.5, EiveAxis::Reaction).unwrap();
        assert!(
            label.contains("basic") || label.contains("alkaline"),
            "R=8.5 should indicate basic/alkaline, got: {}",
            label
        );
    }

    /// Test edge cases: boundaries and extremes
    #[test]
    fn test_edge_cases() {
        // Exactly 0.0 should work
        assert!(get_eive_label(0.0, EiveAxis::Light).is_some());

        // Exactly 10.0 should work (highest bin)
        let label = get_eive_label(10.0, EiveAxis::Light).unwrap();
        assert!(label.contains("full-light"));

        // NaN should return None
        assert!(get_eive_label(f64::NAN, EiveAxis::Light).is_none());

        // Very small positive value
        assert!(get_eive_label(0.001, EiveAxis::Moisture).is_some());
    }

    /// Test class number retrieval
    #[test]
    fn test_get_eive_class() {
        assert_eq!(get_eive_class(8.0, EiveAxis::Light), Some(8));  // 8.0 is in class 8 (7.467-8.367)
        assert_eq!(get_eive_class(8.4, EiveAxis::Light), Some(9));  // 8.4 > 8.367 boundary -> class 9
        assert_eq!(get_eive_class(1.0, EiveAxis::Light), Some(1));
        assert_eq!(get_eive_class(10.0, EiveAxis::Light), Some(9));
        assert_eq!(get_eive_class(f64::NAN, EiveAxis::Light), None);
    }
}
