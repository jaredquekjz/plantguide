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

        // Fungi Network Profile (qualitative information)
        if let Some(fungi_profile) = &explanation.fungi_network_profile {
            md.push_str("## Beneficial Fungi Network Profile\n\n");
            md.push_str("*Qualitative information about fungal networks (60% of M5 scoring)*\n\n");

            md.push_str(&format!(
                "**Total unique beneficial fungi species:** {}\n\n",
                fungi_profile.total_unique_fungi
            ));

            // Fungal diversity by category
            md.push_str("**Fungal Community Composition:**\n\n");
            let total = fungi_profile.total_unique_fungi as f64;
            if total > 0.0 {
                let amf_pct = fungi_profile.fungi_by_category.amf_count as f64 / total * 100.0;
                let emf_pct = fungi_profile.fungi_by_category.emf_count as f64 / total * 100.0;
                let endo_pct = fungi_profile.fungi_by_category.endophytic_count as f64 / total * 100.0;
                let sapro_pct = fungi_profile.fungi_by_category.saprotrophic_count as f64 / total * 100.0;

                md.push_str(&format!("- {} AMF species (Arbuscular Mycorrhizal) - {:.1}%\n",
                    fungi_profile.fungi_by_category.amf_count, amf_pct));
                md.push_str(&format!("- {} EMF species (Ectomycorrhizal) - {:.1}%\n",
                    fungi_profile.fungi_by_category.emf_count, emf_pct));
                md.push_str(&format!("- {} Endophytic species - {:.1}%\n",
                    fungi_profile.fungi_by_category.endophytic_count, endo_pct));
                md.push_str(&format!("- {} Saprotrophic species - {:.1}%\n\n",
                    fungi_profile.fungi_by_category.saprotrophic_count, sapro_pct));
            }

            // Top network fungi
            if !fungi_profile.top_fungi.is_empty() {
                md.push_str("**Top Network Fungi (by connectivity):**\n\n");
                md.push_str("| Rank | Fungus Species | Category | Plants Connected | Network Contribution |\n");
                md.push_str("|------|----------------|----------|------------------|----------------------|\n");
                for (i, fungus) in fungi_profile.top_fungi.iter().enumerate() {
                    let plant_list = if fungus.plants.len() > 3 {
                        format!("{} plants", fungus.plants.len())
                    } else {
                        fungus.plants.join(", ")
                    };
                    md.push_str(&format!(
                        "| {} | {} | {} | {} | {:.1}% |\n",
                        i + 1,
                        fungus.fungus_name,
                        fungus.category,
                        plant_list,
                        fungus.network_contribution * 100.0
                    ));
                }
                md.push_str("\n");
            }

            // Network hubs
            if !fungi_profile.hub_plants.is_empty() {
                md.push_str("**Network Hubs (most connected plants):**\n\n");
                md.push_str("| Plant | Total Fungi | AMF | EMF | Endophytic | Saprotrophic |\n");
                md.push_str("|-------|-------------|-----|-----|------------|---------------|\n");
                for hub in fungi_profile.hub_plants.iter().take(10) {
                    md.push_str(&format!(
                        "| {} | {} | {} | {} | {} | {} |\n",
                        hub.plant_name,
                        hub.fungus_count,
                        hub.amf_count,
                        hub.emf_count,
                        hub.endophytic_count,
                        hub.saprotrophic_count
                    ));
                }
                md.push_str("\n");
            }
        }

        // Pollinator Network Profile (qualitative information)
        if let Some(pollinator_profile) = &explanation.pollinator_network_profile {
            md.push_str("## Pollinator Network Profile\n\n");
            md.push_str("*Qualitative information about pollinator networks (100% of M7 scoring)*\n\n");

            md.push_str(&format!(
                "**Total unique pollinator species:** {}\n\n",
                pollinator_profile.total_unique_pollinators
            ));

            // Pollinator diversity by category
            md.push_str("**Pollinator Community Composition:**\n\n");
            let total = pollinator_profile.total_unique_pollinators as f64;
            if total > 0.0 {
                let bees_pct = pollinator_profile.pollinators_by_category.bees_count as f64 / total * 100.0;
                let butterflies_pct = pollinator_profile.pollinators_by_category.butterflies_count as f64 / total * 100.0;
                let moths_pct = pollinator_profile.pollinators_by_category.moths_count as f64 / total * 100.0;
                let flies_pct = pollinator_profile.pollinators_by_category.flies_count as f64 / total * 100.0;
                let beetles_pct = pollinator_profile.pollinators_by_category.beetles_count as f64 / total * 100.0;
                let wasps_pct = pollinator_profile.pollinators_by_category.wasps_count as f64 / total * 100.0;
                let birds_pct = pollinator_profile.pollinators_by_category.birds_count as f64 / total * 100.0;
                let bats_pct = pollinator_profile.pollinators_by_category.bats_count as f64 / total * 100.0;
                let other_pct = pollinator_profile.pollinators_by_category.other_count as f64 / total * 100.0;

                if pollinator_profile.pollinators_by_category.bees_count > 0 {
                    md.push_str(&format!("- {} Bees - {:.1}%\n",
                        pollinator_profile.pollinators_by_category.bees_count, bees_pct));
                }
                if pollinator_profile.pollinators_by_category.butterflies_count > 0 {
                    md.push_str(&format!("- {} Butterflies - {:.1}%\n",
                        pollinator_profile.pollinators_by_category.butterflies_count, butterflies_pct));
                }
                if pollinator_profile.pollinators_by_category.moths_count > 0 {
                    md.push_str(&format!("- {} Moths - {:.1}%\n",
                        pollinator_profile.pollinators_by_category.moths_count, moths_pct));
                }
                if pollinator_profile.pollinators_by_category.flies_count > 0 {
                    md.push_str(&format!("- {} Flies - {:.1}%\n",
                        pollinator_profile.pollinators_by_category.flies_count, flies_pct));
                }
                if pollinator_profile.pollinators_by_category.beetles_count > 0 {
                    md.push_str(&format!("- {} Beetles - {:.1}%\n",
                        pollinator_profile.pollinators_by_category.beetles_count, beetles_pct));
                }
                if pollinator_profile.pollinators_by_category.wasps_count > 0 {
                    md.push_str(&format!("- {} Wasps - {:.1}%\n",
                        pollinator_profile.pollinators_by_category.wasps_count, wasps_pct));
                }
                if pollinator_profile.pollinators_by_category.birds_count > 0 {
                    md.push_str(&format!("- {} Birds - {:.1}%\n",
                        pollinator_profile.pollinators_by_category.birds_count, birds_pct));
                }
                if pollinator_profile.pollinators_by_category.bats_count > 0 {
                    md.push_str(&format!("- {} Bats - {:.1}%\n",
                        pollinator_profile.pollinators_by_category.bats_count, bats_pct));
                }
                if pollinator_profile.pollinators_by_category.other_count > 0 {
                    md.push_str(&format!("- {} Other - {:.1}%\n",
                        pollinator_profile.pollinators_by_category.other_count, other_pct));
                }
                md.push_str("\n");
            }

            // Shared pollinators
            if !pollinator_profile.shared_pollinators.is_empty() {
                md.push_str("**Shared Pollinators (visiting ≥2 plants):**\n\n");
                md.push_str(&format!("{} pollinator species are shared across multiple plants in this guild.\n\n",
                    pollinator_profile.shared_pollinators.len()));
            } else {
                md.push_str("**No shared pollinators detected** - Each pollinator visits only one plant species in this guild.\n\n");
            }

            // Top network pollinators
            if !pollinator_profile.top_pollinators.is_empty() {
                md.push_str("**Top Network Pollinators (by connectivity):**\n\n");
                md.push_str("| Rank | Pollinator Species | Category | Plants Connected | Network Contribution |\n");
                md.push_str("|------|-------------------|----------|------------------|----------------------|\n");
                for (i, pollinator) in pollinator_profile.top_pollinators.iter().enumerate() {
                    md.push_str(&format!(
                        "| {} | {} | {} | {} plants | {:.1}% |\n",
                        i + 1,
                        pollinator.pollinator_name,
                        pollinator.category.display_name(),
                        pollinator.plant_count,
                        pollinator.network_contribution * 100.0
                    ));
                }
                md.push_str("\n");
            }

            // Network hubs
            if !pollinator_profile.hub_plants.is_empty() {
                md.push_str("**Network Hubs (most connected plants):**\n\n");
                md.push_str("| Plant | Total | Bees | Butterflies | Moths | Flies | Beetles | Wasps | Birds | Bats | Other |\n");
                md.push_str("|-------|-------|------|-------------|-------|-------|---------|-------|-------|------|-------|\n");
                for hub in pollinator_profile.hub_plants.iter().take(10) {
                    md.push_str(&format!(
                        "| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |\n",
                        hub.plant_name,
                        hub.pollinator_count,
                        hub.bees_count,
                        hub.butterflies_count,
                        hub.moths_count,
                        hub.flies_count,
                        hub.beetles_count,
                        hub.wasps_count,
                        hub.birds_count,
                        hub.bats_count,
                        hub.other_count
                    ));
                }
                md.push_str("\n");
            }
        }

        // Pest Profile (qualitative information)
        if let Some(pest_profile) = &explanation.pest_profile {
            md.push_str("## Pest Vulnerability Profile\n\n");
            md.push_str("*Qualitative information about herbivore pests (not used in scoring)*\n\n");

            md.push_str(&format!(
                "**Total unique herbivore species:** {}\n\n",
                pest_profile.total_unique_pests
            ));

            // Shared pests (generalists)
            if !pest_profile.shared_pests.is_empty() {
                md.push_str("### Shared Pests (Generalists)\n\n");
                md.push_str("These pests attack multiple plants in the guild:\n\n");
                for (i, pest) in pest_profile.shared_pests.iter().enumerate().take(10) {
                    md.push_str(&format!(
                        "{}. **{}**: attacks {} plant(s) ({})\n",
                        i + 1,
                        pest.pest_name,
                        pest.plant_count,
                        pest.plants.join(", ")
                    ));
                }
                md.push_str("\n");
            } else {
                md.push_str("**No shared pests detected** - Each herbivore attacks only one plant species in this guild, indicating high diversity.\n\n");
            }

            // Top pests by interaction count
            if !pest_profile.top_pests.is_empty() {
                md.push_str("### Top 10 Herbivore Pests\n\n");
                md.push_str("| Rank | Pest Species | Plants Attacked |\n");
                md.push_str("|------|--------------|------------------|\n");
                for (i, pest) in pest_profile.top_pests.iter().enumerate().take(10) {
                    let plant_list = if pest.plants.len() > 3 {
                        format!("{} plants", pest.plants.len())
                    } else {
                        pest.plants.join(", ")
                    };
                    md.push_str(&format!(
                        "| {} | {} | {} |\n",
                        i + 1,
                        pest.pest_name,
                        plant_list
                    ));
                }
                md.push_str("\n");
            }

            // Most vulnerable plants
            if !pest_profile.vulnerable_plants.is_empty() {
                md.push_str("### Most Vulnerable Plants\n\n");
                md.push_str("| Plant | Herbivore Count |\n");
                md.push_str("|-------|------------------|\n");
                for plant in pest_profile.vulnerable_plants.iter().take(5) {
                    md.push_str(&format!(
                        "| {} | {} |\n",
                        plant.plant_name,
                        plant.pest_count
                    ));
                }
                md.push_str("\n");
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
            pest_profile: None,
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
            pest_profile: None,
        };

        let md = MarkdownFormatter::format(&explanation);

        assert!(md.contains("## Warnings"));
        assert!(md.contains("⚠️ **3 nitrogen-fixing plants may over-fertilize**"));
        assert!(md.contains("*Advice:* Reduce to 1-2 nitrogen fixers"));
    }
}
