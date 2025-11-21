use crate::explanation::types::{MetricFragment, Severity, WarningCard};
use crate::metrics::M2Result;

/// Generate explanation fragment for M2 (Growth Compatibility)
///
/// Detects CSR (Competitive-Stress-Ruderal) strategy conflicts.
/// High C, S, or R counts indicate potential growth incompatibility.
pub fn generate_m2_fragment(m2: &M2Result, _display_score: f64) -> MetricFragment {
    if m2.total_conflicts > 0.0 {
        // Build detail message with CSR breakdown
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
            "Mixed strategies (no dominant types)".to_string()
        } else {
            format!("{} (high CSR values: >75th percentile)", parts.join(", "))
        };

        // Severity based on conflict magnitude
        let severity = if m2.total_conflicts > 2.0 {
            Severity::High
        } else if m2.total_conflicts > 1.0 {
            Severity::Medium
        } else {
            Severity::Low
        };

        MetricFragment::with_warning(WarningCard {
            warning_type: "csr_conflict".to_string(),
            severity,
            icon: "⚠️".to_string(),
            message: format!(
                "{:.1} CSR strategy conflicts detected",
                m2.total_conflicts
            ),
            detail: format!(
                "Growth strategy incompatibility: {}",
                breakdown
            ),
            advice: "Consider mixing growth strategies more evenly, or group plants with similar strategies together".to_string(),
        })
    } else {
        MetricFragment::empty()
    }
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
