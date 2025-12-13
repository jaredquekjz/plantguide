use anyhow::Result;
use guild_scorer_rust::{GuildScorer, explanation::soil_ph::check_ph_compatibility};

fn main() -> Result<()> {
    println!("Testing pH Warning with EIVE Semantic Binning\n");
    println!("{}", "=".repeat(60));

    // Default data_dir for local development
    let data_dir = std::env::var("DATA_DIR")
        .unwrap_or_else(|_| "shipley_checks/stage4".to_string());

    // Initialize scorer
    let scorer = GuildScorer::new("7plant", "tier_3_humid_temperate", &data_dir)?;

    // Test guilds (same as test_explanations_3_guilds)
    let test_guilds = vec![
        (
            "Forest Garden",
            vec![
                "wfo-0000832453".to_string(),
                "wfo-0000649136".to_string(),
                "wfo-0000642673".to_string(),
                "wfo-0000984977".to_string(),
                "wfo-0000241769".to_string(),
                "wfo-0000092746".to_string(),
                "wfo-0000690499".to_string(),
            ],
        ),
        (
            "Competitive Clash",
            vec![
                "wfo-0000757278".to_string(),
                "wfo-0000944034".to_string(),
                "wfo-0000186915".to_string(),
                "wfo-0000421791".to_string(),
                "wfo-0000418518".to_string(),
                "wfo-0000841021".to_string(),
                "wfo-0000394258".to_string(),
            ],
        ),
        (
            "Stress-Tolerant",
            vec![
                "wfo-0000721951".to_string(),
                "wfo-0000955348".to_string(),
                "wfo-0000901050".to_string(),
                "wfo-0000956222".to_string(),
                "wfo-0000777518".to_string(),
                "wfo-0000349035".to_string(),
                "wfo-0000209726".to_string(),
            ],
        ),
    ];

    for (name, plant_ids) in test_guilds {
        println!("\n\n### Guild: {}", name);
        println!("{}", "-".repeat(60));

        // Score guild to get guild_plants DataFrame
        let (_guild_score, _fragments, guild_plants, _m2_result, _m3_result, _m4_result, _m5_result, _m6_result, _m7_result, _ecosystem_services) = scorer.score_guild_with_explanation_parallel(&plant_ids)?;

        println!("Plants: {}", guild_plants.height());

        // Always check and display pH information
        match check_ph_compatibility(&guild_plants)? {
            Some(warning) => {
                // Show range with semantic bins
                println!("\nEIVE R (Soil Reaction):");
                println!("  Range: {:.2} - {:.2} (Δ = {:.2})",
                    warning.min_r, warning.max_r, warning.r_range);

                // Get semantic bins for bounds
                let min_category = warning.plant_categories.iter()
                    .min_by(|a, b| a.r_value.partial_cmp(&b.r_value).unwrap())
                    .unwrap();
                let max_category = warning.plant_categories.iter()
                    .max_by(|a, b| a.r_value.partial_cmp(&b.r_value).unwrap())
                    .unwrap();

                println!("  Lower bound: {}", min_category.category);
                println!("  Upper bound: {}", max_category.category);

                println!("\n⚠️  pH INCOMPATIBILITY WARNING");
                println!("  Severity: {:?}", warning.severity);
                println!("  Recommendation: {}", warning.recommendation);

                println!("\n  All plants:");
                for plant in &warning.plant_categories {
                    println!("    {} (R={:.2}): {}",
                        plant.plant_name, plant.r_value, plant.category);
                }
            }
            None => {
                // Still show pH range for compatible guilds
                use polars::prelude::*;
                use guild_scorer_rust::explanation::soil_ph::check_ph_compatibility;

                if let Ok(r_col) = guild_plants.column("soil_reaction_eive") {
                    let r_values: Vec<f64> = r_col.f64()?.into_iter().flatten().collect();
                    if !r_values.is_empty() {
                        let min_r = r_values.iter().copied().fold(f64::INFINITY, f64::min);
                        let max_r = r_values.iter().copied().fold(f64::NEG_INFINITY, f64::max);
                        let range = max_r - min_r;

                        println!("\nEIVE R (Soil Reaction):");
                        println!("  Range: {:.2} - {:.2} (Δ = {:.2})", min_r, max_r, range);

                        // Get semantic bins
                        let get_category = |r: f64| -> &str {
                            const PH_BINS: [(f64, f64, &str); 6] = [
                                (0.0, 2.0, "Strongly Acidic (pH 3-4)"),
                                (2.0, 4.0, "Acidic (pH 4-5)"),
                                (4.0, 5.5, "Slightly Acidic (pH 5-6)"),
                                (5.5, 7.0, "Neutral (pH 6-7)"),
                                (7.0, 8.5, "Alkaline (pH 7-8)"),
                                (8.5, 10.0, "Strongly Alkaline (pH >8)"),
                            ];
                            for (lower, upper, label) in PH_BINS.iter() {
                                if r >= *lower && r < *upper {
                                    return label;
                                }
                            }
                            PH_BINS.last().unwrap().2
                        };

                        println!("  Lower bound: {}", get_category(min_r));
                        println!("  Upper bound: {}", get_category(max_r));
                        println!("\n  ✅ No pH incompatibility (Δ ≤ 1.0)");
                    }
                }
            }
        }
    }

    println!("\n\n{}", "=".repeat(60));
    println!("pH Warning Test Complete");

    Ok(())
}
