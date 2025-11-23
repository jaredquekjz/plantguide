use crate::explanation::types::{BenefitCard, MetricFragment};
use crate::metrics::M3Result;

/// Generate explanation fragment for M3 (Insect Pest Control)
///
/// Measures natural biocontrol via predators and parasitoids.
/// Higher scores indicate more beneficial insects that suppress pests.
/// Lower scores indicate fewer documented biocontrol agents.
pub fn generate_m3_fragment(m3: &M3Result, display_score: f64) -> MetricFragment {
    let interpretation = if display_score >= 80.0 {
        "Excellent biocontrol - abundant predators and parasitoids provide strong pest suppression"
    } else if display_score >= 60.0 {
        "Good biocontrol - beneficial insects provide meaningful pest suppression"
    } else if display_score >= 40.0 {
        "Moderate biocontrol - some beneficial insects present but coverage may be limited"
    } else {
        "Limited biocontrol - few documented predators/parasitoids, may need supplemental pest management"
    };

    MetricFragment::with_benefit(BenefitCard {
        benefit_type: "insect_control".to_string(),
        metric_code: "M3".to_string(),
        title: "Natural Insect Pest Control".to_string(),
        message: format!(
            "{}th percentile biocontrol capacity",
            display_score.round() as i32
        ),
        detail: format!(
            "Plants attract beneficial insects (predators and parasitoids) that naturally suppress pest populations. {}",
            interpretation
        ),
        evidence: None,
    })
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
        assert!(benefit.message.contains("natural insect pest control"));
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
        assert!(benefit.message.contains("natural insect pest control"));
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
