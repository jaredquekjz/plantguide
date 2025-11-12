use crate::explanation::types::{BenefitCard, MetricFragment};
use crate::metrics::M5Result;

/// Generate explanation fragment for M5 (Beneficial Mycorrhizal Fungi)
///
/// High scores indicate strong fungal network connections between plants.
/// Shared mycorrhizal fungi facilitate nutrient exchange and communication.
pub fn generate_m5_fragment(m5: &M5Result, display_score: f64) -> MetricFragment {
    if display_score > 30.0 {
        let species_text = if m5.n_shared_fungi == 1 {
            "species".to_string()
        } else {
            "species".to_string()
        };

        let plants_text = if m5.plants_with_fungi == 1 {
            "plant".to_string()
        } else {
            "plants".to_string()
        };

        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "mycorrhizal_network".to_string(),
            metric_code: "M5".to_string(),
            title: "Beneficial Mycorrhizal Network".to_string(),
            message: format!(
                "{} shared mycorrhizal fungal {} connect {} {}",
                m5.n_shared_fungi, species_text, m5.plants_with_fungi, plants_text
            ),
            detail: "Shared mycorrhizal fungi create underground networks that facilitate nutrient exchange, water sharing, and chemical communication between plants.".to_string(),
            evidence: Some(format!(
                "Network score: {:.1}/100, coverage: {:.1}%",
                display_score, m5.coverage_ratio * 100.0
            )),
        })
    } else {
        MetricFragment::empty()
    }
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
        assert!(benefit.message.contains("12 shared mycorrhizal fungal species"));
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
        assert!(benefit.message.contains("3 shared mycorrhizal fungal species"));
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
