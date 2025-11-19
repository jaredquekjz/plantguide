use guild_scorer_rust::explanation::{
    Explanation, OverallExplanation, ClimateExplanation, BenefitCard, 
    MetricsDisplay, MetricCard, BiocontrolNetworkProfile
};
use guild_scorer_rust::explanation::biocontrol_network_analysis::MatchedBiocontrolPair;
use guild_scorer_rust::{MarkdownFormatter, HtmlFormatter};
use guild_scorer_rust::explanation::unified_taxonomy::OrganismCategory;
use std::fs;

fn main() -> anyhow::Result<()> {
    println!("Generating SIMULATED explanation to demonstrate specific fungi matches...");

    // 1. Create a simulated Biocontrol Profile with specific matches
    let biocontrol_profile = BiocontrolNetworkProfile {
        total_unique_predators: 15,
        total_unique_entomo_fungi: 5,
        specific_predator_matches: 8,
        specific_fungi_matches: 2, // <--- This is what we want to see
        general_entomo_fungi_count: 3,
        matched_predator_pairs: vec![
            MatchedBiocontrolPair {
                target: "aphis gossypii".to_string(),
                target_category: OrganismCategory::Aphids,
                agent: "hippodamia convergens".to_string(),
                agent_category: OrganismCategory::Beetles,
            }
        ],
        // The Feature we want to test:
        matched_fungi_pairs: vec![
            MatchedBiocontrolPair {
                target: "leptinotarsa decemlineata".to_string(), // Colorado Potato Beetle
                target_category: OrganismCategory::Beetles,
                agent: "beauveria bassiana".to_string(),
                agent_category: OrganismCategory::Fungi,
            },
            MatchedBiocontrolPair {
                target: "plutella xylostella".to_string(), // Diamondback Moth
                target_category: OrganismCategory::Moths,
                agent: "metarhizium anisopliae".to_string(),
                agent_category: OrganismCategory::Fungi,
            }
        ],
        predator_category_counts: Default::default(),
        herbivore_category_counts: Default::default(),
        top_predators: vec![],
        top_entomo_fungi: vec![],
        hub_plants: vec![],
    };

    // 2. Create a minimal Explanation object wrapping it
    let explanation = Explanation {
        overall: OverallExplanation {
            score: 92.5,
            stars: "★★★★★".to_string(),
            label: "Exceptional".to_string(),
            message: "Simulated Guild Result".to_string(),
        },
        climate: ClimateExplanation {
            compatible: true,
            tier: "tier_3".to_string(),
            tier_display: "Tier 3".to_string(),
            message: "All compatible".to_string(),
        },
        benefits: vec![
            BenefitCard {
                benefit_type: "biocontrol".to_string(),
                metric_code: "M3".to_string(),
                title: "Natural Insect Pest Control".to_string(),
                message: "High biocontrol potential".to_string(),
                detail: "Specific fungi detected".to_string(),
                evidence: Some("Score: 100".to_string()),
            }
        ],
        warnings: vec![],
        risks: vec![],
        metrics_display: MetricsDisplay {
            universal: vec![
                MetricCard {
                    code: "M3".to_string(),
                    name: "Insect Control".to_string(),
                    score: 100.0,
                    raw: 1.0,
                    interpretation: "Excellent".to_string(),
                }
            ],
            bonus: vec![],
        },
        pest_profile: None,
        fungi_network_profile: None,
        pollinator_network_profile: None,
        biocontrol_network_profile: Some(biocontrol_profile),
        pathogen_control_profile: None,
    };

    // 3. Format output
    let html = HtmlFormatter::format(&explanation);
    let md = MarkdownFormatter::format(&explanation);

    // 4. Save
    fs::write("shipley_checks/reports/explanations/simulated_fungi_match.html", html)?;
    fs::write("shipley_checks/reports/explanations/simulated_fungi_match.md", md)?;

    println!("Done! Check 'shipley_checks/reports/explanations/simulated_fungi_match.html'");
    Ok(())
}
