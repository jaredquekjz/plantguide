use crate::explanation::types::Explanation;
use crate::explanation::biocontrol_network_analysis::BiocontrolNetworkProfile;
use crate::explanation::pathogen_control_network_analysis::PathogenControlNetworkProfile;

/// HTML formatter for explanations
pub struct HtmlFormatter;

impl HtmlFormatter {
    /// Format explanation as standalone HTML with embedded CSS
    pub fn format(explanation: &Explanation) -> String {
        let mut html = String::with_capacity(8192);

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
        html.push_str("h4 { color: #555; margin-top: 15px; margin-bottom: 5px; font-size: 1.1em; }\n");
        html.push_str(".benefit { background: #d4edda; border-left: 4px solid #28a745; padding: 15px; margin: 15px 0; border-radius: 4px; }\n");
        html.push_str(".warning { background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 15px 0; border-radius: 4px; }\n");
        html.push_str(".risk { background: #f8d7da; border-left: 4px solid #dc3545; padding: 15px; margin: 15px 0; border-radius: 4px; }\n");
        html.push_str(".benefit h3, .warning h3, .risk h3 { margin-top: 0; }\n");
        html.push_str(".benefit em, .warning em, .risk em { color: #6c757d; }\n");
        html.push_str("table { width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 0.95em; }\n");
        html.push_str("th { background: #34495e; color: white; text-align: left; padding: 10px; font-weight: 600; }\n");
        html.push_str("td { padding: 10px; border-bottom: 1px solid #ecf0f1; vertical-align: top; }\n");
        html.push_str("tr:hover { background: #f8f9fa; }\n");
        html.push_str(".tag { display: inline-block; padding: 2px 6px; border-radius: 4px; font-size: 0.85em; font-weight: 500; }\n");
        html.push_str(".tag-pest { background: #ffebee; color: #c62828; }\n");
        html.push_str(".tag-agent { background: #e8f5e9; color: #2e7d32; }\n");
        html.push_str(".ecosystem-service { background: #f8f9fa; border-left: 4px solid #6c757d; padding: 15px; margin: 15px 0; border-radius: 4px; }\n");
        html.push_str(".ecosystem-service.excellent { background: #d4edda; border-left-color: #28a745; }\n");
        html.push_str(".ecosystem-service.good { background: #d1ecf1; border-left-color: #17a2b8; }\n");
        html.push_str(".ecosystem-service.moderate { background: #fff3cd; border-left-color: #ffc107; }\n");
        html.push_str(".ecosystem-service.limited { background: #f8d7da; border-left-color: #dc3545; }\n");
        html.push_str(".ecosystem-service h3 { margin-top: 0; display: flex; justify-content: space-between; align-items: center; }\n");
        html.push_str(".rating-badge { font-size: 0.75em; background: white; padding: 4px 12px; border-radius: 20px; font-weight: 600; }\n");
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

        // Metrics table (moved to top for quick reference)
        html.push_str("<h2>Metrics Breakdown</h2>\n");
        html.push_str("<table>\n<thead><tr><th>Metric</th><th>Score</th><th>Interpretation</th></tr></thead>\n<tbody>\n");

        // Combine universal and bonus indicators in order
        for metric in &explanation.metrics_display.universal {
            html.push_str(&format!(
                "<tr><td>{} - {}</td><td>{:.1}</td><td>{}</td></tr>\n",
                metric.code, metric.name, metric.score, metric.interpretation
            ));
        }
        for metric in &explanation.metrics_display.bonus {
            html.push_str(&format!(
                "<tr><td>{} - {}</td><td>{:.1}</td><td>{}</td></tr>\n",
                metric.code, metric.name, metric.score, metric.interpretation
            ));
        }
        html.push_str("</tbody>\n</table>\n");

        // Climate
        html.push_str("<h2>Climate Compatibility</h2>\n");
        html.push_str(&format!("<p>✅ {}</p>\n", explanation.climate.message));

        // Metrics Explanation
        if !explanation.benefits.is_empty() {
            html.push_str("<h2>Metrics Explanation</h2>\n");
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

                // Insert detailed profiles (2025-12 reorder: M1=Growth, M3=Pest, M4=Biocontrol, M5=Disease)
                if benefit.metric_code == "M3" {
                    // Taxonomic profile after M3 (Pest Independence)
                    if let Some(profile) = &explanation.taxonomic_profile {
                        html.push_str(&Self::format_taxonomic_profile(profile));
                    }
                } else if benefit.metric_code == "M4" {
                    // Biocontrol profile after M4 (Biocontrol Networks)
                    if let Some(profile) = &explanation.biocontrol_network_profile {
                        html.push_str(&Self::format_biocontrol_profile(profile));
                    }
                } else if benefit.metric_code == "M5" {
                    // Pathogen profile after M5 (Disease Suppression)
                    if let Some(profile) = &explanation.pathogen_control_profile {
                        html.push_str(&Self::format_pathogen_control_profile(profile));
                    }
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

        // Ecosystem Services (M8-M17)
        if let Some(services) = &explanation.ecosystem_services {
            html.push_str("<h2>Ecosystem Services</h2>\n");
            html.push_str("<p><em>These ratings show how your guild contributes to important ecosystem functions based on plant traits and growth strategies.</em></p>\n");

            for service in services {
                let (emoji, color_class) = match service.benefit_level.as_str() {
                    "Excellent" => ("🌟", "excellent"),
                    "Good" => ("✅", "good"),
                    "Moderate" => ("🔸", "moderate"),
                    "Limited" => ("⚠️", "limited"),
                    "Very Limited" => ("⚠️", "very-limited"),
                    _ => ("ℹ️", "unknown"),
                };

                html.push_str(&format!("<div class=\"ecosystem-service {}\">\n", color_class));
                html.push_str(&format!(
                    "<h3>{} {} <span class=\"rating-badge\">{}</span></h3>\n",
                    emoji, service.name, service.rating
                ));
                html.push_str(&format!("<p>{}</p>\n", service.description));
                html.push_str("</div>\n");
            }
        }

        html.push_str("</body>\n</html>\n");
        html
    }

    fn format_taxonomic_profile(profile: &crate::explanation::taxonomic_profile_analysis::TaxonomicProfile) -> String {
        let mut html = String::new();
        html.push_str("<h4>Taxonomic Diversity Profile</h4>");
        html.push_str("<p><em>Taxonomic diversity (variety of families and genera) generally correlates with phylogenetic diversity, as plants from different families typically share more distant evolutionary ancestry. However, the relationship is not perfect—phylogenetic diversity (measured using Faith's PD) quantifies total evolutionary history by summing branch lengths in the evolutionary tree, where branch lengths represent millions of years of independent evolution. This is what our percentile calculations are based on.</em></p>");

        // Summary
        html.push_str(&format!(
            "<p><strong>Guild contains: {} plants from {} families across {} genera</strong></p>",
            profile.total_plants,
            profile.total_families,
            profile.total_genera
        ));

        // Plant table
        html.push_str("<table><thead><tr><th>Family</th><th>Genus</th><th>Plant (Vernacular Name)</th></tr></thead><tbody>");
        for entry in &profile.plant_entries {
            html.push_str(&format!(
                "<tr><td>{}</td><td>{}</td><td>{}</td></tr>",
                entry.family, entry.genus, entry.display_name
            ));
        }
        html.push_str("</tbody></table>");

        // Family clustering
        if !profile.family_distribution.is_empty() {
            html.push_str("<p><strong>Family clustering:</strong> ");
            let family_strings: Vec<String> = profile
                .family_distribution
                .iter()
                .map(|(family, count)| {
                    if *count == 1 {
                        format!("{} (1 plant)", family)
                    } else {
                        format!("{} ({} plants)", family, count)
                    }
                })
                .collect();
            html.push_str(&family_strings.join(", "));
            html.push_str("</p>");
        }

        html
    }

    fn format_biocontrol_profile(profile: &BiocontrolNetworkProfile) -> String {
        let mut html = String::new();
        html.push_str("<h4>Biocontrol Network Profile</h4>");
        
        html.push_str("<ul>");
        html.push_str(&format!("<li>{} unique predator species</li>", profile.total_unique_predators));
        if profile.total_unique_entomo_fungi > 0 {
            html.push_str(&format!("<li>{} unique entomopathogenic fungi species</li>", profile.total_unique_entomo_fungi));
        }
        html.push_str("</ul>");

        if !profile.matched_predator_pairs.is_empty() {
            html.push_str("<h4>Matched Herbivore → Predator Pairs:</h4>");
            html.push_str("<table><thead><tr><th>Herbivore (Pest)</th><th>Category</th><th>Known Predator</th><th>Predator Category</th><th>Type</th></tr></thead><tbody>");
            
            for match_item in &profile.matched_predator_pairs {
                html.push_str(&format!(
                    "<tr><td>{}</td><td><span class=\"tag tag-pest\">{}</span></td><td>{}</td><td><span class=\"tag tag-agent\">{}</span></td><td>Specific</td></tr>",
                    match_item.target,
                    match_item.target_category.display_name(),
                    match_item.agent,
                    match_item.agent_category.display_name()
                ));
            }
            html.push_str("</tbody></table>");
        }

        if !profile.matched_fungi_pairs.is_empty() {
            html.push_str("<h4>Matched Herbivore → Entomopathogenic Fungi Pairs:</h4>");
            html.push_str("<table><thead><tr><th>Herbivore (Pest)</th><th>Category</th><th>Fungus</th><th>Type</th></tr></thead><tbody>");
            
            for match_item in &profile.matched_fungi_pairs {
                html.push_str(&format!(
                    "<tr><td>{}</td><td><span class=\"tag tag-pest\">{}</span></td><td><span class=\"tag tag-agent\">{}</span></td><td>Specific</td></tr>",
                    match_item.target,
                    match_item.target_category.display_name(),
                    match_item.agent
                ));
            }
            html.push_str("</tbody></table>");
        }

        html
    }

    fn format_pathogen_control_profile(profile: &PathogenControlNetworkProfile) -> String {
        let mut html = String::new();
        html.push_str("<h4>Pathogen Control Network Profile</h4>");
        
        html.push_str("<ul>");
        html.push_str(&format!("<li>{} unique mycoparasite species</li>", profile.total_unique_mycoparasites));
        html.push_str(&format!("<li>{} unique pathogen species in guild</li>", profile.total_unique_pathogens));
        html.push_str("</ul>");

        if !profile.matched_antagonist_pairs.is_empty() {
            html.push_str("<h4>Matched Pathogen → Mycoparasite Pairs:</h4>");
            html.push_str("<table><thead><tr><th>Pathogen</th><th>Known Antagonist</th><th>Type</th></tr></thead><tbody>");
            
            for (pathogen, antagonist) in &profile.matched_antagonist_pairs {
                html.push_str(&format!(
                    "<tr><td>{}</td><td><span class=\"tag tag-agent\">{}</span></td><td>Specific</td></tr>",
                    pathogen,
                    antagonist
                ));
            }
            html.push_str("</tbody></table>");
        }

        if !profile.matched_fungivore_pairs.is_empty() {
            html.push_str("<h4>Matched Pathogen → Fungivore Pairs:</h4>");
            html.push_str("<table><thead><tr><th>Pathogen</th><th>Known Antagonist</th><th>Category</th></tr></thead><tbody>");
            
            for match_item in &profile.matched_fungivore_pairs {
                html.push_str(&format!(
                    "<tr><td>{}</td><td>{}</td><td><span class=\"tag tag-agent\">{}</span></td></tr>",
                    match_item.pathogen,
                    match_item.fungivore,
                    match_item.fungivore_category.display_name()
                ));
            }
            html.push_str("</tbody></table>");
        }

        html
    }
}
