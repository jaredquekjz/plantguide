use crate::explanation::types::Explanation;
use serde_json;

/// JSON formatter for explanations
pub struct JsonFormatter;

impl JsonFormatter {
    /// Format explanation as pretty-printed JSON
    pub fn format(explanation: &Explanation) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(explanation)
    }

    /// Format explanation as compact JSON (no whitespace)
    pub fn format_compact(explanation: &Explanation) -> Result<String, serde_json::Error> {
        serde_json::to_string(explanation)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::explanation::types::*;

    #[test]
    fn test_format_json() {
        let explanation = Explanation {
            overall: OverallExplanation {
                score: 85.0,
                stars: "★★★★☆".to_string(),
                label: "Excellent".to_string(),
                message: "Overall guild compatibility: 85.0/100".to_string(),
            },
            climate: ClimateExplanation {
                compatible: true,
                tier: "tier_3_humid_temperate".to_string(),
                tier_display: "Tier 3 (Humid Temperate)".to_string(),
                message: "All plants compatible with Tier 3 (Humid Temperate)".to_string(),
            },
            benefits: vec![],
            warnings: vec![],
            risks: vec![],
            metrics_display: MetricsDisplay {
                universal: vec![],
                bonus: vec![],
            },
            pest_profile: None,
        };

        let json = JsonFormatter::format(&explanation).unwrap();

        assert!(json.contains("\"score\": 85.0"));
        assert!(json.contains("\"label\": \"Excellent\""));
        assert!(json.contains("\"tier\": \"tier_3_humid_temperate\""));
    }

    #[test]
    fn test_format_compact() {
        let explanation = Explanation {
            overall: OverallExplanation {
                score: 85.0,
                stars: "★★★★☆".to_string(),
                label: "Excellent".to_string(),
                message: "Overall guild compatibility: 85.0/100".to_string(),
            },
            climate: ClimateExplanation {
                compatible: true,
                tier: "tier_3_humid_temperate".to_string(),
                tier_display: "Tier 3 (Humid Temperate)".to_string(),
                message: "All plants compatible with Tier 3 (Humid Temperate)".to_string(),
            },
            benefits: vec![],
            warnings: vec![],
            risks: vec![],
            metrics_display: MetricsDisplay {
                universal: vec![],
                bonus: vec![],
            },
            pest_profile: None,
        };

        let json = JsonFormatter::format_compact(&explanation).unwrap();

        // Compact format should have no newlines (except potentially in strings)
        assert!(!json.contains("\n  "));
    }
}
