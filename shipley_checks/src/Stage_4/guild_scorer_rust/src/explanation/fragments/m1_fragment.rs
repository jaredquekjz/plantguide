use crate::explanation::types::{BenefitCard, MetricFragment, RiskCard, Severity};
use crate::metrics::M1Result;

/// Generate explanation fragment for M1 (Pest & Pathogen Independence)
///
/// High scores (>50) indicate high phylogenetic diversity - distant relatives
/// share fewer pests and pathogens.
///
/// Low scores (<30) indicate closely related plants that may share pests.
pub fn generate_m1_fragment(m1: &M1Result, display_score: f64) -> MetricFragment {
    if display_score > 50.0 {
        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "phylogenetic_diversity".to_string(),
            metric_code: "M1".to_string(),
            title: "High Phylogenetic Diversity".to_string(),
            message: format!(
                "Plants are distantly related (Faith's PD: {:.2})",
                m1.faiths_pd
            ),
            detail: "Distant relatives typically share fewer pests and pathogens, reducing disease spread in the guild.".to_string(),
            evidence: Some(format!(
                "Phylogenetic diversity score: {:.1}/100",
                display_score
            )),
        })
    } else if display_score < 30.0 {
        MetricFragment::with_risk(RiskCard {
            risk_type: "pest_vulnerability".to_string(),
            severity: Severity::from_score(display_score),
            icon: "🦠".to_string(),
            title: "Closely Related Plants".to_string(),
            message: "Guild contains closely related plants that may share pests".to_string(),
            detail: format!(
                "Low phylogenetic diversity (Faith's PD: {:.2}) increases pest/pathogen risk",
                m1.faiths_pd
            ),
            advice: "Consider adding plants from different families to increase diversity".to_string(),
        })
    } else {
        MetricFragment::empty()
    }
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
