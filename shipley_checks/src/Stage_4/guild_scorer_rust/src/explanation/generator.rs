use crate::explanation::types::*;
use crate::explanation::{check_nitrogen_fixation, check_soil_ph_compatibility, analyze_fungi_network, analyze_pollinator_network, analyze_biocontrol_network, analyze_pathogen_control_network, analyze_csr_strategies, analyze_taxonomic_diversity, analyze_structural_diversity};
use crate::scorer::GuildScore;
use crate::metrics::{M2Result, M3Result, M4Result, M5Result, M6Result, M7Result, GuildType};
use anyhow::Result;
use polars::prelude::*;
use rustc_hash::FxHashMap;

/// Main explanation generator
pub struct ExplanationGenerator;

impl ExplanationGenerator {
    /// Generate complete explanation from GuildScore and fragments
    ///
    /// Takes:
    /// - guild_score: Computed scores
    /// - guild_plants: DataFrame of guild plants (for nitrogen/pH checks)
    /// - climate_tier: Köppen tier string
    /// - fragments: Pre-generated metric fragments from parallel scoring
    /// - m2_result: M2 result with CSR strategy data (for strategy profile)
    /// - m3_result: M3 result with biocontrol agent counts (for network analysis)
    /// - m4_result: M4 result with mycoparasite counts (for network analysis)
    /// - m5_result: M5 result with fungi counts (for network analysis)
    /// - fungi_df: Fungi DataFrame (for categorization)
    /// - m6_result: M6 result with structural diversity data (for layer profile)
    /// - m7_result: M7 result with pollinator counts (for network analysis)
    /// - organisms_df: Organisms DataFrame (for categorization)
    /// - organism_categories: Kimi AI categorization map
    /// - pathogen_diseases: Pathogen taxon to disease info mapping
    ///
    /// Returns: Complete Explanation with all cards
    pub fn generate(
        guild_score: &GuildScore,
        guild_plants: &DataFrame,
        climate_tier: &str,
        fragments: Vec<MetricFragment>,
        m2_result: &M2Result,
        m3_result: &M3Result,
        organisms_df: &DataFrame,
        m4_result: &M4Result,
        m5_result: &M5Result,
        fungi_df: &DataFrame,
        m6_result: &M6Result,
        m7_result: &M7Result,
        organism_categories: &FxHashMap<String, String>,
        ecosystem_services_result: &crate::metrics::EcosystemServicesResult,
        pathogen_diseases: &FxHashMap<String, (Option<String>, Option<String>)>,
    ) -> Result<Explanation> {
        use std::time::Instant;
        let gen_start = Instant::now();

        // Overall score with stars and guild type
        let overall = Self::generate_overall(guild_score.overall_score, m2_result.guild_type);

        // Climate compatibility
        let climate = Self::generate_climate(climate_tier);

        // Run all 10 profile analyses sequentially with timing
        let t0 = Instant::now();
        let nitrogen_warning = check_nitrogen_fixation(guild_plants).ok().flatten();
        let t_nitrogen = t0.elapsed();

        let t1 = Instant::now();
        let ph_warning = check_soil_ph_compatibility(guild_plants).ok().flatten();
        let t_ph = t1.elapsed();

        let t2 = Instant::now();
        let pest_profile = crate::explanation::pest_analysis::analyze_guild_pests(
            guild_plants,
            organism_categories,
        ).ok().flatten();
        let t_pest = t2.elapsed();

        let t3 = Instant::now();
        let taxonomic_profile = analyze_taxonomic_diversity(guild_plants).ok();
        let t_taxonomic = t3.elapsed();

        let t4 = Instant::now();
        let csr_strategy_profile = Some(analyze_csr_strategies(
            &m2_result.plant_csr_data,
            m2_result.total_conflicts,
            m2_result.high_c_count,
            m2_result.high_s_count,
            m2_result.high_r_count,
        ));
        let t_csr = t4.elapsed();

        let t5 = Instant::now();
        let biocontrol_network_profile = analyze_biocontrol_network(
            &m3_result.predator_counts,
            &m3_result.entomo_fungi_counts,
            m3_result.specific_predator_matches,
            m3_result.specific_fungi_matches,
            &m3_result.matched_predator_pairs,
            &m3_result.matched_fungi_pairs,
            guild_plants,
            organisms_df,
            fungi_df,
            organism_categories,
        ).ok().flatten();
        let t_biocontrol = t5.elapsed();

        let t6 = Instant::now();
        let pathogen_control_profile = analyze_pathogen_control_network(
            &m4_result.mycoparasite_counts,
            &m4_result.pathogen_counts,
            m4_result.specific_antagonist_matches,
            &m4_result.matched_antagonist_pairs,
            m4_result.specific_fungivore_matches,
            &m4_result.matched_fungivore_pairs,
            guild_plants,
            fungi_df,
            organism_categories,
            pathogen_diseases,
        ).ok().flatten();
        let t_pathogen = t6.elapsed();

        let t7 = Instant::now();
        let fungi_network_profile = analyze_fungi_network(m5_result, guild_plants, fungi_df).ok().flatten();
        let t_fungi = t7.elapsed();

        let t8 = Instant::now();
        let pollinator_network_profile = analyze_pollinator_network(
            m7_result,
            guild_plants,
            organisms_df,
            organism_categories,
        ).ok().flatten();
        let t_pollinator = t8.elapsed();

        let t9 = Instant::now();
        let structural_diversity_profile = analyze_structural_diversity(m6_result);
        let t_structural = t9.elapsed();

        let profiles_total = gen_start.elapsed();
        tracing::info!(
            "Generator profile timing (ms): nitrogen={:.1}, ph={:.1}, pest={:.1}, taxonomic={:.1}, csr={:.1}, biocontrol={:.1}, pathogen={:.1}, fungi={:.1}, pollinator={:.1}, structural={:.1}, TOTAL={:.1}",
            t_nitrogen.as_secs_f64() * 1000.0,
            t_ph.as_secs_f64() * 1000.0,
            t_pest.as_secs_f64() * 1000.0,
            t_taxonomic.as_secs_f64() * 1000.0,
            t_csr.as_secs_f64() * 1000.0,
            t_biocontrol.as_secs_f64() * 1000.0,
            t_pathogen.as_secs_f64() * 1000.0,
            t_fungi.as_secs_f64() * 1000.0,
            t_pollinator.as_secs_f64() * 1000.0,
            t_structural.as_secs_f64() * 1000.0,
            profiles_total.as_secs_f64() * 1000.0,
        );

        // Aggregate all benefits, warnings, risks from fragments
        let mut benefits = Vec::new();
        let mut warnings = Vec::new();
        let mut risks = Vec::new();

        for fragment in fragments {
            if let Some(benefit) = fragment.benefit {
                benefits.push(benefit);
            }
            if let Some(warning) = fragment.warning {
                warnings.push(warning);
            }
            if let Some(risk) = fragment.risk {
                risks.push(risk);
            }
        }

        // Add nitrogen and pH warnings
        if let Some(w) = nitrogen_warning {
            warnings.push(w);
        }
        if let Some(w) = ph_warning {
            warnings.push(w);
        }

        // Metrics display
        let metrics_display = Self::format_metrics_display(guild_score);

        // Ecosystem services (M8-M17)
        let ecosystem_services = Some(crate::explanation::ecosystem_services::generate_ecosystem_services(
            ecosystem_services_result
        ));

        Ok(Explanation {
            overall,
            climate,
            benefits,
            warnings,
            risks,
            metrics_display,
            pest_profile,
            taxonomic_profile,
            csr_strategy_profile,
            fungi_network_profile,
            pollinator_network_profile,
            biocontrol_network_profile,
            pathogen_control_profile,
            structural_diversity_profile,
            ecosystem_services,
        })
    }

    /// Generate overall score interpretation with stars and guild type
    fn generate_overall(score: f64, guild_type: GuildType) -> OverallExplanation {
        let (stars, label) = match score {
            s if s >= 90.0 => ("★★★★★", "Exceptional"),
            s if s >= 80.0 => ("★★★★☆", "Excellent"),
            s if s >= 70.0 => ("★★★☆☆", "Good"),
            s if s >= 60.0 => ("★★☆☆☆", "Fair"),
            s if s >= 50.0 => ("★☆☆☆☆", "Poor"),
            _ => ("☆☆☆☆☆", "Unsuitable"),
        };

        OverallExplanation {
            score,
            stars: stars.to_string(),
            label: label.to_string(),
            message: format!("Overall guild compatibility: {:.1}/100", score),
            guild_type,
            guild_type_display: guild_type.display_name().to_string(),
            guild_type_note: guild_type.environment_note().to_string(),
        }
    }

    /// Generate climate tier explanation
    fn generate_climate(tier: &str) -> ClimateExplanation {
        let tier_display = match tier {
            "tier_1_tropical" => "Tier 1 (Tropical)",
            "tier_2_mediterranean" => "Tier 2 (Mediterranean)",
            "tier_3_humid_temperate" => "Tier 3 (Humid Temperate)",
            "tier_4_continental" => "Tier 4 (Continental)",
            "tier_5_boreal_polar" => "Tier 5 (Boreal/Polar)",
            "tier_6_arid" => "Tier 6 (Arid)",
            _ => "Unknown",
        };

        ClimateExplanation {
            compatible: true, // Already checked in scorer
            tier: tier.to_string(),
            tier_display: tier_display.to_string(),
            message: format!("All plants compatible with {}", tier_display),
        }
    }

    /// Format metrics display (universal vs bonus indicators)
    fn format_metrics_display(guild_score: &GuildScore) -> MetricsDisplay {
        // REORDERED per 2025-12 restructure
        let metric_names = [
            "Growth Strategy",           // M1: CSR classification (qualitative)
            "Structural Diversity",      // M2: Vertical layers
            "Pest & Pathogen Independence", // M3: Phylogenetic diversity
            "Biocontrol Networks",       // M4: Insect predators/parasitoids
            "Disease Suppression",       // M5: Antagonistic fungi
            "Beneficial Fungi",          // M6: Mycorrhizal networks
            "Pollinator Support",        // M7: Pollinator networks
        ];

        let mut universal = Vec::new();
        let mut bonus = Vec::new();

        for (i, (name, score)) in metric_names.iter().zip(&guild_score.metrics).enumerate() {
            let interpretation = match score {
                s if *s >= 80.0 => "Excellent",
                s if *s >= 60.0 => "Good",
                s if *s >= 40.0 => "Fair",
                _ => "Poor",
            };

            let card = MetricCard {
                code: format!("M{}", i + 1),
                name: name.to_string(),
                score: *score,
                raw: guild_score.raw_scores[i],
                interpretation: interpretation.to_string(),
            };

            if i < 4 {
                universal.push(card);
            } else {
                bonus.push(card);
            }
        }

        MetricsDisplay { universal, bonus }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_overall_exceptional() {
        let overall = ExplanationGenerator::generate_overall(92.5, GuildType::FertileGarden);
        assert_eq!(overall.stars, "★★★★★");
        assert_eq!(overall.label, "Exceptional");
        assert_eq!(overall.score, 92.5);
        assert_eq!(overall.guild_type, GuildType::FertileGarden);
        assert_eq!(overall.guild_type_display, "Fertile Garden Guild");
    }

    #[test]
    fn test_generate_overall_excellent() {
        let overall = ExplanationGenerator::generate_overall(85.0, GuildType::LowInput);
        assert_eq!(overall.stars, "★★★★☆");
        assert_eq!(overall.label, "Excellent");
        assert_eq!(overall.guild_type, GuildType::LowInput);
    }

    #[test]
    fn test_generate_overall_poor() {
        let overall = ExplanationGenerator::generate_overall(55.0, GuildType::Generalist);
        assert_eq!(overall.stars, "★☆☆☆☆");
        assert_eq!(overall.label, "Poor");
        assert_eq!(overall.guild_type, GuildType::Generalist);
    }

    #[test]
    fn test_generate_climate() {
        let climate = ExplanationGenerator::generate_climate("tier_3_humid_temperate");
        assert_eq!(climate.tier, "tier_3_humid_temperate");
        assert_eq!(climate.tier_display, "Tier 3 (Humid Temperate)");
        assert!(climate.compatible);
    }

    #[test]
    fn test_format_metrics_display() {
        let guild_score = GuildScore {
            overall_score: 85.0,
            metrics: [90.0, 75.0, 80.0, 70.0, 60.0, 85.0, 55.0],
            raw_scores: [0.1, 0.25, 0.8, 0.7, 0.6, 0.85, 0.55],
            normalized: [10.0, 25.0, 80.0, 70.0, 60.0, 85.0, 55.0],
        };

        let display = ExplanationGenerator::format_metrics_display(&guild_score);

        assert_eq!(display.universal.len(), 4); // M1-M4
        assert_eq!(display.bonus.len(), 3); // M5-M7

        assert_eq!(display.universal[0].code, "M1");
        assert_eq!(display.universal[0].interpretation, "Excellent");

        assert_eq!(display.bonus[0].code, "M5");
        assert_eq!(display.bonus[0].interpretation, "Good");
    }
}
