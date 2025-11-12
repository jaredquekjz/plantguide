use crate::explanation::types::Explanation;

/// Markdown formatter for explanations
pub struct MarkdownFormatter;

impl MarkdownFormatter {
    /// Format explanation as markdown
    pub fn format(explanation: &Explanation) -> String {
        let mut md = String::with_capacity(2048);

        // Title with stars and score
        md.push_str(&format!(
            "# {} - {}\n\n",
            explanation.overall.stars, explanation.overall.label
        ));
        md.push_str(&format!(
            "**Overall Score:** {:.1}/100\n\n",
            explanation.overall.score
        ));
        md.push_str(&format!("{}\n\n", explanation.overall.message));

        // Climate
        md.push_str("## Climate Compatibility\n\n");
        md.push_str(&format!("✅ {}\n\n", explanation.climate.message));

        // Benefits
        if !explanation.benefits.is_empty() {
            md.push_str("## Benefits\n\n");
            for benefit in &explanation.benefits {
                md.push_str(&format!(
                    "### {} [{}]\n\n",
                    benefit.title, benefit.metric_code
                ));
                md.push_str(&format!("{}  \n", benefit.message));
                md.push_str(&format!("{}  \n\n", benefit.detail));
                if let Some(evidence) = &benefit.evidence {
                    md.push_str(&format!("*Evidence:* {}\n\n", evidence));
                }
            }
        }

        // Warnings
        if !explanation.warnings.is_empty() {
            md.push_str("## Warnings\n\n");
            for warning in &explanation.warnings {
                md.push_str(&format!("{} **{}**\n\n", warning.icon, warning.message));
                md.push_str(&format!("{}  \n", warning.detail));
                md.push_str(&format!("*Advice:* {}\n\n", warning.advice));
            }
        }

        // Risks
        if !explanation.risks.is_empty() {
            md.push_str("## Risks\n\n");
            for risk in &explanation.risks {
                md.push_str(&format!("{} **{}**\n\n", risk.icon, risk.title));
                md.push_str(&format!("{}  \n", risk.message));
                md.push_str(&format!("{}  \n", risk.detail));
                md.push_str(&format!("*Advice:* {}\n\n", risk.advice));
            }
        }

        // Metrics Breakdown
        md.push_str("## Metrics Breakdown\n\n");

        md.push_str("### Universal Indicators\n\n");
        md.push_str("| Metric | Score | Interpretation |\n");
        md.push_str("|--------|-------|----------------|\n");
        for metric in &explanation.metrics_display.universal {
            md.push_str(&format!(
                "| {} - {} | {:.1} | {} |\n",
                metric.code, metric.name, metric.score, metric.interpretation
            ));
        }

        md.push_str("\n### Bonus Indicators\n\n");
        md.push_str("| Metric | Score | Interpretation |\n");
        md.push_str("|--------|-------|----------------|\n");
        for metric in &explanation.metrics_display.bonus {
            md.push_str(&format!(
                "| {} - {} | {:.1} | {} |\n",
                metric.code, metric.name, metric.score, metric.interpretation
            ));
        }

        md.push('\n');
        md
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::explanation::types::*;

    #[test]
    fn test_format_basic() {
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
                universal: vec![
                    MetricCard {
                        code: "M1".to_string(),
                        name: "Pest & Pathogen Independence".to_string(),
                        score: 90.0,
                        raw: 0.1,
                        interpretation: "Excellent".to_string(),
                    },
                ],
                bonus: vec![],
            },
        };

        let md = MarkdownFormatter::format(&explanation);

        assert!(md.contains("# ★★★★☆ - Excellent"));
        assert!(md.contains("**Overall Score:** 85.0/100"));
        assert!(md.contains("## Climate Compatibility"));
        assert!(md.contains("## Metrics Breakdown"));
        assert!(md.contains("M1 - Pest & Pathogen Independence"));
    }

    #[test]
    fn test_format_with_warnings() {
        let explanation = Explanation {
            overall: OverallExplanation {
                score: 60.0,
                stars: "★★☆☆☆".to_string(),
                label: "Fair".to_string(),
                message: "Overall guild compatibility: 60.0/100".to_string(),
            },
            climate: ClimateExplanation {
                compatible: true,
                tier: "tier_3_humid_temperate".to_string(),
                tier_display: "Tier 3 (Humid Temperate)".to_string(),
                message: "All plants compatible with Tier 3 (Humid Temperate)".to_string(),
            },
            benefits: vec![],
            warnings: vec![WarningCard {
                warning_type: "nitrogen_excess".to_string(),
                severity: Severity::Medium,
                icon: "⚠️".to_string(),
                message: "3 nitrogen-fixing plants may over-fertilize".to_string(),
                detail: "Excess nitrogen can favor fast-growing weeds".to_string(),
                advice: "Reduce to 1-2 nitrogen fixers".to_string(),
            }],
            risks: vec![],
            metrics_display: MetricsDisplay {
                universal: vec![],
                bonus: vec![],
            },
        };

        let md = MarkdownFormatter::format(&explanation);

        assert!(md.contains("## Warnings"));
        assert!(md.contains("⚠️ **3 nitrogen-fixing plants may over-fertilize**"));
        assert!(md.contains("*Advice:* Reduce to 1-2 nitrogen fixers"));
    }
}
