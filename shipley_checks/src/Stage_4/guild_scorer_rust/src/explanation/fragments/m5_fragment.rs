use crate::explanation::types::{BenefitCard, MetricFragment};
use crate::metrics::M5Result;

/// Generate explanation fragment for M5 (Beneficial Mycorrhizal Fungi)
///
/// High scores indicate strong fungal network connections between plants.
/// Shared mycorrhizal fungi facilitate nutrient exchange and communication.
pub fn generate_m5_fragment(m5: &M5Result, display_score: f64) -> MetricFragment {
    // Coverage-based interpretation
    let coverage_pct = m5.raw; // Now stores coverage % (0-100)
    let plants_covered = m5.plants_with_fungi;
    let total_plants = m5.total_plants;

    let interpretation = if display_score >= 80.0 {
        "Excellent fungal network - most plants have beneficial fungal partners"
    } else if display_score >= 60.0 {
        "Good fungal network - many plants have beneficial fungal associations"
    } else if display_score >= 40.0 {
        "Moderate fungal network - some plants have beneficial fungi but coverage is limited"
    } else {
        "Limited fungal network - few documented beneficial fungi, plants may be more independent"
    };

    MetricFragment::with_benefit(BenefitCard {
        benefit_type: "mycorrhizal_network".to_string(),
        metric_code: "M5".to_string(),
        title: "Beneficial Mycorrhizal Network".to_string(),
        message: format!(
            "{}th percentile - {:.0}% coverage ({}/{} plants have beneficial fungi)",
            display_score.round() as i32,
            coverage_pct,
            plants_covered,
            total_plants
        ),
        detail: format!(
            "Beneficial fungi (mycorrhizal partners, endophytes, and saprotrophs) create underground networks that facilitate nutrient exchange, water sharing, and chemical communication between plants. {}",
            interpretation
        ),
        evidence: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_high_fungal_network() {
        let m5 = M5Result {
            raw: 0.8,
            norm: 20.0,
            network_score: 0.75,
            coverage_ratio: 0.85,
            n_shared_fungi: 12,
            plants_with_fungi: 6,
        };
        let display_score = 80.0;

        let fragment = generate_m5_fragment(&m5, display_score);
        assert!(fragment.benefit.is_some());

        let benefit = fragment.benefit.unwrap();
        assert_eq!(benefit.metric_code, "M5");
        assert!(benefit.message.contains("12 shared beneficial fungal species"));
        assert!(benefit.message.contains("6 plants"));
    }

    #[test]
    fn test_moderate_network() {
        let m5 = M5Result {
            raw: 0.5,
            norm: 50.0,
            network_score: 0.45,
            coverage_ratio: 0.6,
            n_shared_fungi: 3,
            plants_with_fungi: 4,
        };
        let display_score = 50.0;

        let fragment = generate_m5_fragment(&m5, display_score);
        assert!(fragment.benefit.is_some());

        let benefit = fragment.benefit.unwrap();
        assert!(benefit.message.contains("3 shared beneficial fungal species"));
        assert!(benefit.message.contains("4 plants"));
    }

    #[test]
    fn test_low_network() {
        let m5 = M5Result {
            raw: 0.2,
            norm: 80.0,
            network_score: 0.15,
            coverage_ratio: 0.25,
            n_shared_fungi: 1,
            plants_with_fungi: 2,
        };
        let display_score = 20.0;

        let fragment = generate_m5_fragment(&m5, display_score);
        assert!(fragment.benefit.is_none());
    }
}
