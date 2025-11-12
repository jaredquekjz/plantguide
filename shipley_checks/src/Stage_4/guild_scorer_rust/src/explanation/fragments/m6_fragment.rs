use crate::explanation::types::{BenefitCard, MetricFragment};
use crate::metrics::M6Result;

/// Generate explanation fragment for M6 (Structural Diversity)
///
/// High scores indicate diverse growth forms and vertical stratification.
/// Multiple canopy layers maximize space use and light capture.
pub fn generate_m6_fragment(m6: &M6Result, display_score: f64) -> MetricFragment {
    if display_score > 50.0 {
        let forms_text = if m6.n_forms == 1 {
            "form".to_string()
        } else {
            "forms".to_string()
        };

        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "structural_diversity".to_string(),
            metric_code: "M6".to_string(),
            title: "High Structural Diversity".to_string(),
            message: format!(
                "{} growth {} spanning {:.1}m height range",
                m6.n_forms, forms_text, m6.height_range
            ),
            detail: "Diverse plant structures create vertical stratification, maximizing space use, light capture, and habitat complexity.".to_string(),
            evidence: Some(format!(
                "Structural diversity score: {:.1}/100, stratification quality: {:.2}",
                display_score, m6.stratification_quality
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
    fn test_high_structural_diversity() {
        let m6 = M6Result {
            raw: 0.85,
            norm: 15.0,
            height_range: 8.5,
            n_forms: 5,
            stratification_quality: 0.82,
            form_diversity: 0.78,
        };
        let display_score = 85.0;

        let fragment = generate_m6_fragment(&m6, display_score);
        assert!(fragment.benefit.is_some());

        let benefit = fragment.benefit.unwrap();
        assert_eq!(benefit.metric_code, "M6");
        assert!(benefit.message.contains("5 growth forms"));
        assert!(benefit.message.contains("8.5m height range"));
    }

    #[test]
    fn test_single_form() {
        let m6 = M6Result {
            raw: 0.6,
            norm: 40.0,
            height_range: 2.5,
            n_forms: 1,
            stratification_quality: 0.55,
            form_diversity: 0.0,
        };
        let display_score = 60.0;

        let fragment = generate_m6_fragment(&m6, display_score);
        assert!(fragment.benefit.is_some());

        let benefit = fragment.benefit.unwrap();
        assert!(benefit.message.contains("1 growth form"));
        assert!(benefit.message.contains("2.5m height range"));
    }

    #[test]
    fn test_low_structural_diversity() {
        let m6 = M6Result {
            raw: 0.3,
            norm: 70.0,
            height_range: 1.2,
            n_forms: 2,
            stratification_quality: 0.25,
            form_diversity: 0.3,
        };
        let display_score = 30.0;

        let fragment = generate_m6_fragment(&m6, display_score);
        assert!(fragment.benefit.is_none());
    }
}
