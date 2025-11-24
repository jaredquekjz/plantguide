use crate::explanation::types::{BenefitCard, MetricFragment, Severity, WarningCard};
use crate::metrics::M2Result;

/// Generate explanation fragment for M2 (Growth Compatibility)
///
/// Measures CSR (Competitive-Stress-Ruderal) strategy compatibility.
/// Lower conflict scores indicate compatible growth strategies.
/// Higher conflict scores indicate potential competition or incompatibility.
pub fn generate_m2_fragment(m2: &M2Result, display_score: f64) -> MetricFragment {
    // Build CSR breakdown
    // Note: Counts represent plants with high values (>75th percentile) in each strategy
    // Plants can be high in multiple strategies, so counts may not sum to guild size
    let mut parts = Vec::new();
    if m2.high_c_count > 0 {
        parts.push(format!("{} Competitive-dominant", m2.high_c_count));
    }
    if m2.high_s_count > 0 {
        parts.push(format!("{} Stress-tolerant-dominant", m2.high_s_count));
    }
    if m2.high_r_count > 0 {
        parts.push(format!("{} Ruderal-dominant", m2.high_r_count));
    }

    let breakdown = if parts.is_empty() {
        "Mixed strategies with no dominant types".to_string()
    } else {
        format!("{} (high CSR values: >75th percentile)", parts.join(", "))
    };

    // Always show as benefit - conflicts are detailed in CSR Strategy Profile below
    let (title, detail_suffix) = if m2.total_conflicts > 2.0 {
        (
            "Growth Strategy Compatibility",
            ". Many potential conflicts detected - see CSR Strategy Profile below for details and recommendations.".to_string()
        )
    } else if m2.total_conflicts > 0.0 {
        (
            "Growth Strategy Compatibility",
            ". Some potential conflicts detected - see CSR Strategy Profile below for details and recommendations.".to_string()
        )
    } else {
        (
            "Growth Strategy Compatibility",
            ". No conflicts detected - plants have compatible resource allocation strategies.".to_string()
        )
    };

    MetricFragment::with_benefit(BenefitCard {
        benefit_type: "growth_compatibility".to_string(),
        metric_code: "M2".to_string(),
        title: title.to_string(),
        message: format!(
            "{}th percentile compatibility",
            display_score.round() as i32
        ),
        detail: format!(
            "CSR strategies measure how plants allocate resources to Competitive growth, Stress tolerance, or Ruderal (disturbance) strategies. Guild composition: {}{}",
            breakdown,
            detail_suffix
        ),
        evidence: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_high_conflicts() {
        let m2 = M2Result {
            raw: 0.3,
            norm: 70.0,
            high_c_count: 4,
            high_s_count: 2,
            high_r_count: 1,
            total_conflicts: 2.5,
        };

        let fragment = generate_m2_fragment(&m2, 30.0);
        assert!(fragment.warning.is_some());

        let warning = fragment.warning.unwrap();
        assert_eq!(warning.warning_type, "csr_conflict");
        assert!(warning.detail.contains("4 Competitive-dominant"));
        assert!(warning.detail.contains("2 Stress-tolerant-dominant"));
        assert!(warning.detail.contains("1 Ruderal-dominant"));
        assert!(warning.detail.contains(">75th percentile"));
        assert_eq!(warning.severity as u8, Severity::High as u8);
    }

    #[test]
    fn test_medium_conflicts() {
        let m2 = M2Result {
            raw: 0.5,
            norm: 50.0,
            high_c_count: 3,
            high_s_count: 0,
            high_r_count: 0,
            total_conflicts: 1.5,
        };

        let fragment = generate_m2_fragment(&m2, 50.0);
        assert!(fragment.warning.is_some());

        let warning = fragment.warning.unwrap();
        assert_eq!(warning.severity as u8, Severity::Medium as u8);
    }

    #[test]
    fn test_no_conflicts() {
        let m2 = M2Result {
            raw: 0.9,
            norm: 10.0,
            high_c_count: 0,
            high_s_count: 0,
            high_r_count: 0,
            total_conflicts: 0.0,
        };

        let fragment = generate_m2_fragment(&m2, 90.0);
        assert!(fragment.warning.is_none());
    }
}
