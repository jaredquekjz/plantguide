use guild_scorer_rust::{
    GuildScore, ExplanationGenerator, MarkdownFormatter, JsonFormatter, HtmlFormatter,
    MetricFragment, BenefitCard, WarningCard, RiskCard, Severity,
};
use guild_scorer_rust::metrics::{M3Result, M4Result, M5Result, M7Result};
use rustc_hash::FxHashMap;
use polars::prelude::*;
use std::fs;

#[allow(unused)]
use guild_scorer_rust::GuildScorer;

/// Create mock M3Result for testing
fn create_mock_m3_result() -> M3Result {
    M3Result {
        raw: 0.4,
        norm: 40.0,
        biocontrol_raw: 0.35,
        n_mechanisms: 2,
        predator_counts: FxHashMap::default(),
        entomo_fungi_counts: FxHashMap::default(),
        specific_predator_matches: 0,
        specific_fungi_matches: 0,
        matched_predator_pairs: Vec::new(),
        matched_fungi_pairs: Vec::new(),
    }
}

/// Create mock M4Result for testing
fn create_mock_m4_result() -> M4Result {
    M4Result {
        raw: 0.45,
        norm: 45.0,
        pathogen_control_raw: 0.4,
        n_mechanisms: 3,
        mycoparasite_counts: FxHashMap::default(),
        fungivore_counts: FxHashMap::default(),
        pathogen_counts: FxHashMap::default(),
        specific_antagonist_matches: 0,
        specific_fungivore_matches: 0,
        matched_antagonist_pairs: Vec::new(),
        matched_fungivore_pairs: Vec::new(),
    }
}

/// Create mock M5Result for testing
fn create_mock_m5_result() -> M5Result {
    M5Result {
        raw: 0.5,
        norm: 50.0,
        network_score: 0.4,
        coverage_ratio: 0.6,
        n_shared_fungi: 5,
        plants_with_fungi: 4,
        fungi_counts: FxHashMap::default(),
    }
}

/// Create mock fungi DataFrame for testing
fn create_mock_fungi_df() -> anyhow::Result<DataFrame> {
    Ok(df! {
        "plant_wfo_id" => &["plant1"],
        "amf_fungi" => &[""],
        "emf_fungi" => &[""],
        "endophytic_fungi" => &[""],
        "saprotrophic_fungi" => &[""],
    }?)
}

/// Create mock M7Result for testing
fn create_mock_m7_result() -> M7Result {
    M7Result {
        raw: 0.3,
        norm: 30.0,
        n_shared_pollinators: 3,
        pollinator_counts: FxHashMap::default(),
    }
}

/// Create mock organisms DataFrame for testing
fn create_mock_organisms_df() -> anyhow::Result<DataFrame> {
    Ok(df! {
        "plant_wfo_id" => &["plant1"],
        "pollinators" => &[""],
        "flower_visitors" => &[""],
    }?)
}

fn main() -> anyhow::Result<()> {
    println!("==================================================================");
    println!("EXPLANATION ENGINE UNIT TEST (Mock Data)");
    println!("==================================================================\n");

    // Test 1: High-scoring guild with benefits
    println!("\n--- Test 1: High-scoring guild (Forest Garden) ---");
    test_high_scoring_guild()?;

    // Test 2: Medium-scoring guild with warnings
    println!("\n--- Test 2: Medium-scoring guild (Competitive Clash) ---");
    test_medium_scoring_guild()?;

    // Test 3: Low-scoring guild with risks
    println!("\n--- Test 3: Low-scoring guild (Poor Guild) ---");
    test_low_scoring_guild()?;

    println!("\n==================================================================");
    println!("✅ ALL TESTS PASSED");
    println!("==================================================================\n");
    println!("Output files written to /tmp/:");
    println!("  - rust_explanation_high_scoring.md/json/html");
    println!("  - rust_explanation_medium_scoring.md/json/html");
    println!("  - rust_explanation_low_scoring.md/json/html\n");

    Ok(())
}

fn test_high_scoring_guild() -> anyhow::Result<()> {
    // Mock high-scoring guild (Forest Garden style)
    let guild_score = GuildScore {
        overall_score: 88.5,
        metrics: [92.0, 85.0, 78.0, 88.0, 82.0, 91.0, 75.0],
        raw_scores: [0.08, 0.15, 0.78, 0.88, 0.82, 0.91, 0.75],
        normalized: [8.0, 15.0, 78.0, 88.0, 82.0, 91.0, 75.0],
    };

    // Mock fragments with benefits
    let fragments = vec![
        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "phylogenetic_diversity".to_string(),
            metric_code: "M1".to_string(),
            title: "High Phylogenetic Diversity".to_string(),
            message: "Plants are distantly related (Faith's PD: 185.42)".to_string(),
            detail: "Distant relatives typically share fewer pests and pathogens".to_string(),
            evidence: Some("Phylogenetic diversity score: 92.0/100".to_string()),
        }),
        MetricFragment::empty(), // M2
        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "insect_control".to_string(),
            metric_code: "M3".to_string(),
            title: "Natural Insect Pest Control".to_string(),
            message: "Guild provides insect pest control via 4 biocontrol mechanisms".to_string(),
            detail: "Plants attract beneficial insects that naturally suppress pests".to_string(),
            evidence: Some("Biocontrol score: 78.0/100, covering 4 mechanisms".to_string()),
        }),
        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "disease_control".to_string(),
            metric_code: "M4".to_string(),
            title: "Natural Disease Suppression".to_string(),
            message: "Guild provides disease suppression via 3 antagonistic fungal mechanisms".to_string(),
            detail: "Plants harbor beneficial fungi that antagonize pathogens".to_string(),
            evidence: Some("Pathogen control score: 88.0/100, covering 3 mechanisms".to_string()),
        }),
        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "mycorrhizal_network".to_string(),
            metric_code: "M5".to_string(),
            title: "Beneficial Mycorrhizal Network".to_string(),
            message: "15 shared mycorrhizal fungal species connect 6 plants".to_string(),
            detail: "Shared mycorrhizal fungi create underground networks".to_string(),
            evidence: Some("Network score: 82.0/100, coverage: 85.7%".to_string()),
        }),
        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "structural_diversity".to_string(),
            metric_code: "M6".to_string(),
            title: "High Structural Diversity".to_string(),
            message: "5 growth forms spanning 8.5m height range".to_string(),
            detail: "Diverse plant structures create vertical stratification".to_string(),
            evidence: Some("Structural diversity score: 91.0/100, stratification quality: 0.88".to_string()),
        }),
        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "pollinator_support".to_string(),
            metric_code: "M7".to_string(),
            title: "Robust Pollinator Support".to_string(),
            message: "18 shared pollinator species".to_string(),
            detail: "Plants attract overlapping pollinator communities".to_string(),
            evidence: Some("Pollinator support score: 75.0/100".to_string()),
        }),
    ];

    // Mock guild plants (no nitrogen/pH issues)
    let guild_plants = df! {
        "wfo_taxon_id" => &["plant1", "plant2", "plant3", "plant4", "plant5", "plant6", "plant7"],
        "wfo_taxon_name" => &["Plant 1", "Plant 2", "Plant 3", "Plant 4", "Plant 5", "Plant 6", "Plant 7"],
    }?;

    let m5_result = create_mock_m5_result();
    let m3_result = create_mock_m3_result();
    let organisms_df = create_mock_organisms_df()?;
    let m4_result = create_mock_m4_result();
    let fungi_df = create_mock_fungi_df()?;
    let m7_result = create_mock_m7_result();

    // Generate explanation
    let explanation = ExplanationGenerator::generate(
        &guild_score,
        &guild_plants,
        "tier_3_humid_temperate",
        fragments,
        &m3_result,
        &organisms_df,
        &m4_result,
        &m5_result,
        &fungi_df,
        &m7_result,
    )?;

    // Print summary
    println!("Overall: {} - {:.1}/100", explanation.overall.stars, explanation.overall.score);
    println!("Benefits: {} | Warnings: {} | Risks: {}",
        explanation.benefits.len(), explanation.warnings.len(), explanation.risks.len());

    // Format to all formats
    let markdown = MarkdownFormatter::format(&explanation);
    let json = JsonFormatter::format(&explanation)?;
    let html = HtmlFormatter::format(&explanation);

    // Write outputs
    fs::write("/tmp/rust_explanation_high_scoring.md", markdown)?;
    fs::write("/tmp/rust_explanation_high_scoring.json", json)?;
    fs::write("/tmp/rust_explanation_high_scoring.html", html)?;

    println!("✅ Test passed");
    Ok(())
}

fn test_medium_scoring_guild() -> anyhow::Result<()> {
    // Mock medium-scoring guild with CSR conflicts
    let guild_score = GuildScore {
        overall_score: 62.3,
        metrics: [55.0, 48.0, 65.0, 60.0, 58.0, 72.0, 78.0],
        raw_scores: [0.45, 0.52, 0.65, 0.60, 0.58, 0.72, 0.78],
        normalized: [45.0, 52.0, 65.0, 60.0, 58.0, 72.0, 78.0],
    };

    // Mock fragments with warning
    let fragments = vec![
        MetricFragment::empty(), // M1
        MetricFragment::with_warning(WarningCard {
            warning_type: "csr_conflict".to_string(),
            severity: Severity::High,
            icon: "⚠️".to_string(),
            message: "2.8 CSR strategy conflicts detected".to_string(),
            detail: "Growth strategy incompatibility: 5 Competitive, 2 Stress-tolerant".to_string(),
            advice: "Consider mixing growth strategies more evenly".to_string(),
        }),
        MetricFragment::empty(), // M3
        MetricFragment::empty(), // M4
        MetricFragment::empty(), // M5
        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "structural_diversity".to_string(),
            metric_code: "M6".to_string(),
            title: "Good Structural Diversity".to_string(),
            message: "4 growth forms spanning 6.2m height range".to_string(),
            detail: "Diverse plant structures create vertical stratification".to_string(),
            evidence: Some("Structural diversity score: 72.0/100".to_string()),
        }),
        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "pollinator_support".to_string(),
            metric_code: "M7".to_string(),
            title: "Robust Pollinator Support".to_string(),
            message: "12 shared pollinator species".to_string(),
            detail: "Plants attract overlapping pollinator communities".to_string(),
            evidence: Some("Pollinator support score: 78.0/100".to_string()),
        }),
    ];

    // Mock guild plants (with nitrogen excess)
    let guild_plants = df! {
        "wfo_taxon_id" => &["plant1", "plant2", "plant3", "plant4", "plant5", "plant6", "plant7"],
        "wfo_taxon_name" => &["Plant 1", "Plant 2", "Plant 3", "Plant 4", "Plant 5", "Plant 6", "Plant 7"],
        "nitrogen_fixation" => &["Yes", "Yes", "Yes", "No", "No", "No", "No"],
    }?;

    let m5_result = create_mock_m5_result();
    let m3_result = create_mock_m3_result();
    let organisms_df = create_mock_organisms_df()?;
    let m4_result = create_mock_m4_result();
    let fungi_df = create_mock_fungi_df()?;
    let m7_result = create_mock_m7_result();

    // Generate explanation
    let explanation = ExplanationGenerator::generate(
        &guild_score,
        &guild_plants,
        "tier_3_humid_temperate",
        fragments,
        &m3_result,
        &organisms_df,
        &m4_result,
        &m5_result,
        &fungi_df,
        &m7_result,
    )?;

    // Print summary
    println!("Overall: {} - {:.1}/100", explanation.overall.stars, explanation.overall.score);
    println!("Benefits: {} | Warnings: {} | Risks: {}",
        explanation.benefits.len(), explanation.warnings.len(), explanation.risks.len());

    // Format and write
    fs::write("/tmp/rust_explanation_medium_scoring.md", MarkdownFormatter::format(&explanation))?;
    fs::write("/tmp/rust_explanation_medium_scoring.json", JsonFormatter::format(&explanation)?)?;
    fs::write("/tmp/rust_explanation_medium_scoring.html", HtmlFormatter::format(&explanation))?;

    println!("✅ Test passed");
    Ok(())
}

fn test_low_scoring_guild() -> anyhow::Result<()> {
    // Mock low-scoring guild with multiple issues
    let guild_score = GuildScore {
        overall_score: 38.2,
        metrics: [25.0, 35.0, 42.0, 38.0, 28.0, 45.0, 55.0],
        raw_scores: [0.75, 0.65, 0.42, 0.38, 0.28, 0.45, 0.55],
        normalized: [75.0, 65.0, 42.0, 38.0, 28.0, 45.0, 55.0],
    };

    // Mock fragments with risk
    let fragments = vec![
        MetricFragment::with_risk(RiskCard {
            risk_type: "pest_vulnerability".to_string(),
            severity: Severity::High,
            icon: "🦠".to_string(),
            title: "Closely Related Plants".to_string(),
            message: "Guild contains closely related plants that may share pests".to_string(),
            detail: "Low phylogenetic diversity (Faith's PD: 45.23) increases pest/pathogen risk".to_string(),
            advice: "Consider adding plants from different families to increase diversity".to_string(),
        }),
        MetricFragment::with_warning(WarningCard {
            warning_type: "csr_conflict".to_string(),
            severity: Severity::Medium,
            icon: "⚠️".to_string(),
            message: "1.8 CSR strategy conflicts detected".to_string(),
            detail: "Growth strategy incompatibility: 6 Competitive, 1 Stress-tolerant".to_string(),
            advice: "Consider mixing growth strategies more evenly".to_string(),
        }),
        MetricFragment::empty(), // M3
        MetricFragment::empty(), // M4
        MetricFragment::empty(), // M5
        MetricFragment::empty(), // M6
        MetricFragment::empty(), // M7
    ];

    // Mock guild plants (with pH incompatibility)
    let guild_plants = df! {
        "wfo_taxon_id" => &["plant1", "plant2", "plant3", "plant4", "plant5", "plant6", "plant7"],
        "wfo_taxon_name" => &["Plant 1", "Plant 2", "Plant 3", "Plant 4", "Plant 5", "Plant 6", "Plant 7"],
        "soil_reaction_eive" => &[4.2, 7.8, 5.1, 4.8, 7.2, 6.5, 7.9],
    }?;

    let m5_result = create_mock_m5_result();
    let m3_result = create_mock_m3_result();
    let organisms_df = create_mock_organisms_df()?;
    let m4_result = create_mock_m4_result();
    let fungi_df = create_mock_fungi_df()?;
    let m7_result = create_mock_m7_result();

    // Generate explanation
    let explanation = ExplanationGenerator::generate(
        &guild_score,
        &guild_plants,
        "tier_3_humid_temperate",
        fragments,
        &m3_result,
        &organisms_df,
        &m4_result,
        &m5_result,
        &fungi_df,
        &m7_result,
    )?;

    // Print summary
    println!("Overall: {} - {:.1}/100", explanation.overall.stars, explanation.overall.score);
    println!("Benefits: {} | Warnings: {} | Risks: {}",
        explanation.benefits.len(), explanation.warnings.len(), explanation.risks.len());

    // Format and write
    fs::write("/tmp/rust_explanation_low_scoring.md", MarkdownFormatter::format(&explanation))?;
    fs::write("/tmp/rust_explanation_low_scoring.json", JsonFormatter::format(&explanation)?)?;
    fs::write("/tmp/rust_explanation_low_scoring.html", HtmlFormatter::format(&explanation))?;

    println!("✅ Test passed");
    Ok(())
}
