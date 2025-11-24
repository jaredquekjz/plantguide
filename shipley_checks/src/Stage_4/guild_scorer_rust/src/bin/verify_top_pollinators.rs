use guild_scorer_rust::{GuildScorer, ExplanationGenerator};
use std::time::Instant;

fn main() -> anyhow::Result<()> {
    println!("Verifying Top 10 Pollinators Implementation...");

    // 1. Initialize Scorer
    let calibration_type = "7plant"; // Standard calibration
    let climate_tier = "tier_3_humid_temperate";
    
    println!("Initializing GuildScorer for {}...", climate_tier);
    let start = Instant::now();
    let scorer = GuildScorer::new(calibration_type, climate_tier)?;
    println!("Initialized in {:.2?}", start.elapsed());

    // 2. Define Sample Guild (Forest Garden from tests)
    let plant_ids = vec![
        "wfo-0000832453".to_string(), // Juglans regia (Walnut)
        "wfo-0000649136".to_string(), // Malus domestica (Apple)
        "wfo-0000642673".to_string(), // Prunus avium (Cherry)
        "wfo-0000984977".to_string(), // Ribes rubrum (Red Currant)
        "wfo-0000241769".to_string(), // Corylus avellana (Hazel)
        "wfo-0000092746".to_string(), // Allium ursinum (Wild Garlic)
        "wfo-0000690499".to_string(), // Symphytum officinale (Comfrey)
    ];

    println!("Scoring guild with {} plants...", plant_ids.len());
    let score_start = Instant::now();

    // 3. Score and get raw components for explanation
    let (
        guild_score,
        fragments,
        guild_plants,
        m2_result,
        m3_result,
        organisms_df, // Needed for explanation
        m4_result,
        m5_result,
        fungi_df,     // Needed for explanation
        m7_result,
        _ecosystem_services
    ) = scorer.score_guild_with_explanation_parallel(&plant_ids)?;
    
    println!("Scored in {:.2?}", score_start.elapsed());
    println!("Overall Score: {:.2}", guild_score.overall_score);
    println!("M7 Pollinator Score: {:.2} (Raw: {:.4})", guild_score.metrics[6], guild_score.raw_scores[6]);

    // DEBUG: Check direct analysis
    println!("\n--- DEBUG: Running analyze_pollinator_network directly ---");
    let debug_result = analyze_pollinator_network(
        &m7_result,
        &guild_plants,
        &organisms_df,
        &scorer.data().organism_categories,
    );
    match &debug_result {
        Ok(Some(profile)) => println!("DEBUG: Analysis succeeded with {} top pollinators", profile.top_pollinators.len()),
        Ok(None) => println!("DEBUG: Analysis returned None (empty inputs?)"),
        Err(e) => println!("DEBUG: Analysis FAILED: {:?}", e),
    }

    // 4. Generate Explanation
    println!("Generating explanation...");
    let explanation = ExplanationGenerator::generate(
        &guild_score,
        &guild_plants,
        climate_tier,
        fragments,
            &m2_result,
        &m3_result,
        &organisms_df,
        &m4_result,
        &m5_result,
        &fungi_df,
        &m7_result,
        &scorer.data().organism_categories,
    )?;

    // 5. Verify Pollinator Network Profile
    if let Some(profile) = explanation.pollinator_network_profile {
        println!("\n=== Pollinator Network Profile ===");
        println!("Total Unique Pollinators: {}", profile.total_unique_pollinators);
        
        println!("\n--- Top 10 Pollinators (by plant count) ---");
        if profile.top_pollinators.is_empty() {
            println!("No top pollinators found.");
        } else {
            for (i, pollinator) in profile.top_pollinators.iter().enumerate() {
                println!(
                    "{:>2}. {} ({} plants) - Category: {:?}", 
                    i + 1, 
                    pollinator.pollinator_name, 
                    pollinator.plant_count,
                    pollinator.category
                );
            }
        }
        
        // Verify count
        assert!(profile.top_pollinators.len() <= 10, "Should have at most 10 top pollinators");
        
        // Verify sorting
        let mut prev_count = usize::MAX;
        for pol in &profile.top_pollinators {
            assert!(pol.plant_count <= prev_count, "Pollinators should be sorted by count descending");
            prev_count = pol.plant_count;
        }
        println!("\nVerification Passed: Top pollinators are strictly sorted and limited to 10.");

    } else {
        println!("No pollinator network profile generated (M7 score might be 0 or no data).");
    }

    Ok(())
}