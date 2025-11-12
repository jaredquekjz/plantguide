use crate::explanation::types::{BenefitCard, MetricFragment};
use crate::metrics::M3Result;

/// Generate explanation fragment for M3 (Insect Pest Control)
///
/// High scores indicate plants with beneficial insect predators and parasitoids.
/// Multiple biocontrol mechanisms provide robust pest suppression.
pub fn generate_m3_fragment(m3: &M3Result, display_score: f64) -> MetricFragment {
    if display_score > 50.0 {
        let mechanism_text = if m3.n_mechanisms == 1 {
            "mechanism".to_string()
        } else {
            "mechanisms".to_string()
        };

        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "insect_control".to_string(),
            metric_code: "M3".to_string(),
            title: "Natural Insect Pest Control".to_string(),
            message: format!(
                "Guild provides insect pest control via {} biocontrol {}",
                m3.n_mechanisms, mechanism_text
            ),
            detail: "Plants attract beneficial insects (predators and parasitoids) that naturally suppress pest populations.".to_string(),
            evidence: Some(format!(
                "Biocontrol score: {:.1}/100, covering {} mechanisms",
                display_score, m3.n_mechanisms
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
    fn test_high_biocontrol() {
        let m3 = M3Result {
            raw: 0.8,
            norm: 20.0,
            biocontrol_raw: 0.75,
            n_mechanisms: 5,
        };
        let display_score = 80.0;

        let fragment = generate_m3_fragment(&m3, display_score);
        assert!(fragment.benefit.is_some());

        let benefit = fragment.benefit.unwrap();
        assert_eq!(benefit.metric_code, "M3");
        assert!(benefit.message.contains("5 biocontrol mechanisms"));
    }

    #[test]
    fn test_single_mechanism() {
        let m3 = M3Result {
            raw: 0.6,
            norm: 40.0,
            biocontrol_raw: 0.55,
            n_mechanisms: 1,
        };
        let display_score = 60.0;

        let fragment = generate_m3_fragment(&m3, display_score);
        assert!(fragment.benefit.is_some());

        let benefit = fragment.benefit.unwrap();
        assert!(benefit.message.contains("1 biocontrol mechanism"));
    }

    #[test]
    fn test_low_biocontrol() {
        let m3 = M3Result {
            raw: 0.3,
            norm: 70.0,
            biocontrol_raw: 0.25,
            n_mechanisms: 2,
        };
        let display_score = 30.0;

        let fragment = generate_m3_fragment(&m3, display_score);
        assert!(fragment.benefit.is_none());
    }
}
