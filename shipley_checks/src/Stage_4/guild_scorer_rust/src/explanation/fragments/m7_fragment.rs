use crate::explanation::types::{BenefitCard, MetricFragment};
use crate::metrics::M7Result;

/// Generate explanation fragment for M7 (Pollinator Support)
///
/// High scores indicate plants that share pollinators, supporting
/// robust pollinator populations and ensuring reliable pollination.
pub fn generate_m7_fragment(m7: &M7Result, display_score: f64) -> MetricFragment {
    if display_score > 30.0 {
        let species_text = if m7.n_shared_pollinators == 1 {
            "species".to_string()
        } else {
            "species".to_string()
        };

        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "pollinator_support".to_string(),
            metric_code: "M7".to_string(),
            title: "Robust Pollinator Support".to_string(),
            message: format!(
                "{} shared pollinator {}",
                m7.n_shared_pollinators, species_text
            ),
            detail: "Plants attract and support overlapping pollinator communities, ensuring reliable pollination services and promoting pollinator diversity.".to_string(),
            evidence: Some(format!(
                "Pollinator support score: {:.1}/100",
                display_score
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
