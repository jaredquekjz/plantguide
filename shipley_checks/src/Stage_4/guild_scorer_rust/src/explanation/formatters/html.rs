use crate::explanation::types::Explanation;

/// HTML formatter for explanations
pub struct HtmlFormatter;

impl HtmlFormatter {
    /// Format explanation as standalone HTML with embedded CSS
    pub fn format(explanation: &Explanation) -> String {
        let mut html = String::with_capacity(4096);

        // HTML header with CSS
        html.push_str("<!DOCTYPE html>\n<html>\n<head>\n");
        html.push_str("<meta charset=\"UTF-8\">\n");
        html.push_str("<title>Guild Explanation</title>\n");
        html.push_str("<style>\n");
        html.push_str("body { font-family: system-ui, sans-serif; max-width: 800px; margin: 40px auto; padding: 20px; line-height: 1.6; }\n");
        html.push_str(".stars { font-size: 2em; color: #f39c12; }\n");
        html.push_str(".score { font-size: 1.5em; font-weight: bold; color: #2c3e50; }\n");
        html.push_str("h1 { color: #2c3e50; margin-bottom: 10px; }\n");
        html.push_str("h2 { color: #34495e; border-bottom: 2px solid #ecf0f1; padding-bottom: 5px; margin-top: 30px; }\n");
        html.push_str("h3 { color: #34495e; margin-top: 20px; }\n");
        html.push_str(".benefit { background: #d4edda; border-left: 4px solid #28a745; padding: 15px; margin: 15px 0; border-radius: 4px; }\n");
        html.push_str(".warning { background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 15px 0; border-radius: 4px; }\n");
        html.push_str(".risk { background: #f8d7da; border-left: 4px solid #dc3545; padding: 15px; margin: 15px 0; border-radius: 4px; }\n");
        html.push_str(".benefit h3, .warning h3, .risk h3 { margin-top: 0; }\n");
        html.push_str(".benefit em, .warning em, .risk em { color: #6c757d; }\n");
        html.push_str("table { width: 100%; border-collapse: collapse; margin: 16px 0; }\n");
        html.push_str("th { background: #34495e; color: white; text-align: left; padding: 12px; font-weight: 600; }\n");
        html.push_str("td { padding: 12px; border-bottom: 1px solid #ecf0f1; }\n");
        html.push_str("tr:hover { background: #f8f9fa; }\n");
        html.push_str("</style>\n</head>\n<body>\n");

        // Overall score
        html.push_str(&format!(
            "<div class=\"stars\">{}</div>\n",
            explanation.overall.stars
        ));
        html.push_str(&format!("<h1>{}</h1>\n", explanation.overall.label));
        html.push_str(&format!(
            "<p class=\"score\">{:.1}/100</p>\n",
            explanation.overall.score
        ));
        html.push_str(&format!("<p>{}</p>\n", explanation.overall.message));

        // Climate
        html.push_str("<h2>Climate Compatibility</h2>\n");
        html.push_str(&format!("<p>✅ {}</p>\n", explanation.climate.message));

        // Benefits
        if !explanation.benefits.is_empty() {
            html.push_str("<h2>Benefits</h2>\n");
            for benefit in &explanation.benefits {
                html.push_str("<div class=\"benefit\">\n");
                html.push_str(&format!(
                    "<h3>{} [{}]</h3>\n",
                    benefit.title, benefit.metric_code
                ));
                html.push_str(&format!("<p>{}</p>\n", benefit.message));
                html.push_str(&format!("<p><em>{}</em></p>\n", benefit.detail));
                if let Some(evidence) = &benefit.evidence {
                    html.push_str(&format!("<p><strong>Evidence:</strong> {}</p>\n", evidence));
                }
                html.push_str("</div>\n");
            }
        }

        // Warnings
        if !explanation.warnings.is_empty() {
            html.push_str("<h2>Warnings</h2>\n");
            for warning in &explanation.warnings {
                html.push_str("<div class=\"warning\">\n");
                html.push_str(&format!(
                    "<p>{} <strong>{}</strong></p>\n",
                    warning.icon, warning.message
                ));
                html.push_str(&format!("<p>{}</p>\n", warning.detail));
                html.push_str(&format!("<p><em>Advice: {}</em></p>\n", warning.advice));
                html.push_str("</div>\n");
            }
        }

        // Risks
        if !explanation.risks.is_empty() {
            html.push_str("<h2>Risks</h2>\n");
            for risk in &explanation.risks {
                html.push_str("<div class=\"risk\">\n");
                html.push_str(&format!(
                    "<h3>{} {}</h3>\n",
                    risk.icon, risk.title
                ));
                html.push_str(&format!("<p>{}</p>\n", risk.message));
                html.push_str(&format!("<p><em>{}</em></p>\n", risk.detail));
                html.push_str(&format!("<p><strong>Advice:</strong> {}</p>\n", risk.advice));
                html.push_str("</div>\n");
            }
        }

        // Metrics table
        html.push_str("<h2>Metrics Breakdown</h2>\n");
        html.push_str("<h3>Universal Indicators</h3>\n");
        html.push_str("<table>\n<thead><tr><th>Metric</th><th>Score</th><th>Interpretation</th></tr></thead>\n<tbody>\n");
        for metric in &explanation.metrics_display.universal {
            html.push_str(&format!(
                "<tr><td>{} - {}</td><td>{:.1}</td><td>{}</td></tr>\n",
                metric.code, metric.name, metric.score, metric.interpretation
            ));
        }
        html.push_str("</tbody>\n</table>\n");

        html.push_str("<h3>Bonus Indicators</h3>\n");
        html.push_str("<table>\n<thead><tr><th>Metric</th><th>Score</th><th>Interpretation</th></tr></thead>\n<tbody>\n");
        for metric in &explanation.metrics_display.bonus {
            html.push_str(&format!(
                "<tr><td>{} - {}</td><td>{:.1}</td><td>{}</td></tr>\n",
                metric.code, metric.name, metric.score, metric.interpretation
            ));
        }
        html.push_str("</tbody>\n</table>\n");

        html.push_str("</body>\n</html>\n");
        html
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::explanation::types::*;

    #[test]
    fn test_format_html() {
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

        let html = HtmlFormatter::format(&explanation);

        assert!(html.contains("<!DOCTYPE html>"));
        assert!(html.contains("<style>"));
        assert!(html.contains("<h1>Excellent</h1>"));
        assert!(html.contains("85.0/100"));
        assert!(html.contains("M1 - Pest & Pathogen Independence"));
        assert!(html.contains("</html>"));
    }

    #[test]
    fn test_format_with_cards() {
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
            benefits: vec![BenefitCard {
                benefit_type: "phylogenetic_diversity".to_string(),
                metric_code: "M1".to_string(),
                title: "High Phylogenetic Diversity".to_string(),
                message: "Plants are distantly related".to_string(),
                detail: "Reduces pest spread".to_string(),
                evidence: Some("PD: 150.5".to_string()),
            }],
            warnings: vec![WarningCard {
                warning_type: "nitrogen_excess".to_string(),
                severity: Severity::Medium,
                icon: "⚠️".to_string(),
                message: "3 nitrogen-fixing plants".to_string(),
                detail: "May over-fertilize".to_string(),
                advice: "Reduce to 1-2 fixers".to_string(),
            }],
            risks: vec![],
            metrics_display: MetricsDisplay {
                universal: vec![],
                bonus: vec![],
            },
        };

        let html = HtmlFormatter::format(&explanation);

        assert!(html.contains("<div class=\"benefit\">"));
        assert!(html.contains("High Phylogenetic Diversity"));
        assert!(html.contains("<div class=\"warning\">"));
        assert!(html.contains("⚠️"));
    }
}
