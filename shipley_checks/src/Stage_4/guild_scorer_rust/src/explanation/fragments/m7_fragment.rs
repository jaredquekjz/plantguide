use crate::explanation::types::{BenefitCard, MetricFragment};
use crate::metrics::M7Result;

/// Generate explanation fragment for M7 (Pollinator Support)
///
/// Measures shared pollinator communities between plants.
/// Higher scores indicate more overlapping pollinator species.
/// Lower scores indicate fewer documented shared pollinators.
pub fn generate_m7_fragment(m7: &M7Result, display_score: f64) -> MetricFragment {
    // Coverage-based interpretation
    let coverage_pct = m7.raw; // Now stores coverage % (0-100)
    let plants_covered = m7.plants_with_pollinators;
    let total_plants = m7.total_plants;

    let interpretation = if display_score >= 80.0 {
        "Excellent pollinator support - most plants have documented pollinators"
    } else if display_score >= 60.0 {
        "Good pollinator support - many plants attract documented pollinators"
    } else if display_score >= 40.0 {
        "Moderate pollinator support - some plants have pollinators but coverage is limited"
    } else {
        "Limited pollinator support - few documented pollinators, may need to add pollinator-friendly plants"
    };

    MetricFragment::with_benefit(BenefitCard {
        benefit_type: "pollinator_support".to_string(),
        metric_code: "M7".to_string(),
        title: "Pollinator Support".to_string(),
        message: format!(
            "{}th percentile - {:.0}% coverage ({}/{} plants have documented pollinators)",
            display_score.round() as i32,
            coverage_pct,
            plants_covered,
            total_plants
        ),
        detail: format!(
            "Plants attract and support pollinator communities, ensuring reliable pollination services and promoting pollinator diversity. {}",
            interpretation
        ),
        evidence: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_high_pollinator_support() {
        let m7 = M7Result {
            raw: 0.82,
            norm: 18.0,
            n_shared_pollinators: 15,
        };
        let display_score = 82.0;

        let fragment = generate_m7_fragment(&m7, display_score);
        assert!(fragment.benefit.is_some());

        let benefit = fragment.benefit.unwrap();
        assert_eq!(benefit.metric_code, "M7");
        assert!(benefit.message.contains("15 shared pollinator species"));
    }

    #[test]
    fn test_moderate_pollinator_support() {
        let m7 = M7Result {
            raw: 0.45,
            norm: 55.0,
            n_shared_pollinators: 3,
        };
        let display_score = 45.0;

        let fragment = generate_m7_fragment(&m7, display_score);
        assert!(fragment.benefit.is_some());

        let benefit = fragment.benefit.unwrap();
        assert!(benefit.message.contains("3 shared pollinator species"));
    }

    #[test]
    fn test_low_pollinator_support() {
        let m7 = M7Result {
            raw: 0.15,
            norm: 85.0,
            n_shared_pollinators: 1,
        };
        let display_score = 15.0;

        let fragment = generate_m7_fragment(&m7, display_score);
        assert!(fragment.benefit.is_none());
    }
}
