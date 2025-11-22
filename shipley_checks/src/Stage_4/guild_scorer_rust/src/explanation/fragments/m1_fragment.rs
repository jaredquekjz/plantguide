use crate::explanation::types::{BenefitCard, MetricFragment, RiskCard, Severity};
use crate::metrics::M1Result;

/// Generate explanation fragment for M1 (Pest & Pathogen Independence)
///
/// Measures phylogenetic diversity - how distantly related plants are.
/// Higher scores indicate more distant relatives that share fewer pests/pathogens.
/// Lower scores indicate closer relatives that may share more pests/pathogens.
pub fn generate_m1_fragment(m1: &M1Result, display_score: f64) -> MetricFragment {
    // Determine interpretation and implications based on score
    let (message, detail) = if display_score >= 70.0 {
        (
            "Plants are distantly related (high phylogenetic diversity)",
            "Distant evolutionary relationships mean plants evolved different defense strategies and attract different pest communities. This reduces the risk of pest and pathogen spread across the guild."
        )
    } else if display_score >= 50.0 {
        (
            "Plants are moderately related (good phylogenetic diversity)",
            "Plants have moderate evolutionary distance, providing reasonable pest independence. Some pest sharing may occur among closely related species, but overall diversity is adequate."
        )
    } else if display_score >= 30.0 {
        (
            "Plants have some close relatives (fair phylogenetic diversity)",
            "Several plants share recent evolutionary history. Related plants often share susceptibility to the same pests and pathogens, though the guild is not critically clustered."
        )
    } else {
        (
            "Plants are closely related (low phylogenetic diversity)",
            "Many plants share recent evolutionary ancestry. Closely related plants typically share the same pests, pathogens, and disease vulnerabilities, increasing risk of rapid disease spread through the guild."
        )
    };

    // Always show as benefit with contextual explanation
    MetricFragment::with_benefit(BenefitCard {
        benefit_type: "phylogenetic_diversity".to_string(),
        metric_code: "M1".to_string(),
        title: "Phylogenetic Diversity".to_string(),
        message: format!(
            "{}th percentile (Faith's PD: {:.2}) - {}",
            display_score.round() as i32,
            m1.faiths_pd,
            message
        ),
        detail: detail.to_string(),
        evidence: None,
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
