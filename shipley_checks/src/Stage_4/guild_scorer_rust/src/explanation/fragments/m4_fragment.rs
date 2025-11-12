use crate::explanation::types::{BenefitCard, MetricFragment};
use crate::metrics::M4Result;

/// Generate explanation fragment for M4 (Disease Suppression)
///
/// High scores indicate plants with antagonistic fungi that suppress pathogens.
/// Multiple mechanisms provide robust disease control.
pub fn generate_m4_fragment(m4: &M4Result, display_score: f64) -> MetricFragment {
    if display_score > 50.0 {
        let mechanism_text = if m4.n_mechanisms == 1 {
            "mechanism".to_string()
        } else {
            "mechanisms".to_string()
        };

        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "disease_control".to_string(),
            metric_code: "M4".to_string(),
            title: "Natural Disease Suppression".to_string(),
            message: format!(
                "Guild provides disease suppression via {} antagonistic fungal {}",
                m4.n_mechanisms, mechanism_text
            ),
            detail: "Plants harbor beneficial fungi that antagonize pathogens, reducing disease incidence through biological control.".to_string(),
            evidence: Some(format!(
                "Pathogen control score: {:.1}/100, covering {} mechanisms",
                display_score, m4.n_mechanisms
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
    fn test_high_disease_control() {
        let m4 = M4Result {
            raw: 0.85,
            norm: 15.0,
            pathogen_control_raw: 0.82,
            n_mechanisms: 4,
        };
        let display_score = 85.0;

        let fragment = generate_m4_fragment(&m4, display_score);
        assert!(fragment.benefit.is_some());

        let benefit = fragment.benefit.unwrap();
        assert_eq!(benefit.metric_code, "M4");
        assert!(benefit.message.contains("4 antagonistic fungal mechanisms"));
    }

    #[test]
    fn test_single_mechanism() {
        let m4 = M4Result {
            raw: 0.6,
            norm: 40.0,
            pathogen_control_raw: 0.58,
            n_mechanisms: 1,
        };
        let display_score = 60.0;

        let fragment = generate_m4_fragment(&m4, display_score);
        assert!(fragment.benefit.is_some());

        let benefit = fragment.benefit.unwrap();
        assert!(benefit.message.contains("1 antagonistic fungal mechanism"));
    }

    #[test]
    fn test_low_disease_control() {
        let m4 = M4Result {
            raw: 0.25,
            norm: 75.0,
            pathogen_control_raw: 0.22,
            n_mechanisms: 1,
        };
        let display_score = 25.0;

        let fragment = generate_m4_fragment(&m4, display_score);
        assert!(fragment.benefit.is_none());
    }
}
