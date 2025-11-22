use crate::explanation::types::{BenefitCard, MetricFragment, RiskCard, Severity};
use crate::metrics::M1Result;

/// Generate explanation fragment for M1 (Pest & Pathogen Independence)
///
/// Measures phylogenetic diversity - how distantly related plants are.
/// Higher scores indicate more distant relatives that share fewer pests/pathogens.
/// Lower scores indicate closer relatives that may share more pests/pathogens.
pub fn generate_m1_fragment(m1: &M1Result, display_score: f64) -> MetricFragment {
    // Determine interpretation based on score
    let (interpretation, advice) = if display_score >= 70.0 {
        ("Excellent diversity - distant plant relatives reduce pest/pathogen sharing",
         "Maintain this diversity to minimize disease spread")
    } else if display_score >= 50.0 {
        ("Good diversity - moderate phylogenetic distance provides decent pest independence",
         "Consider adding plants from different families to further increase diversity")
    } else if display_score >= 30.0 {
        ("Fair diversity - some related plants may share pests, but not critically clustered",
         "Consider diversifying with plants from different families")
    } else {
        ("Low diversity - closely related plants may share many pests and pathogens",
         "Strongly consider adding plants from different families to reduce disease risk")
    };

    // Always show as benefit with contextual explanation
    MetricFragment::with_benefit(BenefitCard {
        benefit_type: "phylogenetic_diversity".to_string(),
        metric_code: "M1".to_string(),
        title: "Phylogenetic Diversity".to_string(),
        message: format!(
            "Faith's PD: {:.2} ({}th percentile)",
            m1.faiths_pd,
            display_score.round() as i32
        ),
        detail: format!(
            "Phylogenetic diversity measures how distantly related plants are in evolutionary terms. {}",
            interpretation
        ),
        evidence: Some(format!(
            "{}. {}",
            interpretation,
            advice
        )),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_high_diversity_benefit() {
        let m1 = M1Result {
            raw: 0.8,
            normalized: 20.0,
            faiths_pd: 150.5,
        };
        let display_score = 80.0; // 100 - 20 = 80

        let fragment = generate_m1_fragment(&m1, display_score);
        assert!(fragment.benefit.is_some());
        assert!(fragment.risk.is_none());

        let benefit = fragment.benefit.unwrap();
        assert_eq!(benefit.metric_code, "M1");
        assert!(benefit.message.contains("150.5"));
    }

    #[test]
    fn test_low_diversity_risk() {
        let m1 = M1Result {
            raw: 0.2,
            normalized: 80.0,
            faiths_pd: 45.2,
        };
        let display_score = 20.0; // 100 - 80 = 20

        let fragment = generate_m1_fragment(&m1, display_score);
        assert!(fragment.benefit.is_none());
        assert!(fragment.risk.is_some());

        let risk = fragment.risk.unwrap();
        assert_eq!(risk.risk_type, "pest_vulnerability");
        assert!(risk.detail.contains("45.2"));
    }

    #[test]
    fn test_medium_diversity_no_card() {
        let m1 = M1Result {
            raw: 0.5,
            normalized: 50.0,
            faiths_pd: 100.0,
        };
        let display_score = 50.0;

        let fragment = generate_m1_fragment(&m1, display_score);
        assert!(fragment.benefit.is_none());
        assert!(fragment.risk.is_none());
    }
}
