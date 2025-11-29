use guild_scorer_rust::GuildScorer;

fn main() -> anyhow::Result<()> {
    println!("Debug M4 for Stress-Tolerant Guild");
    println!("===================================\n");

    // Default data_dir for local development
    let data_dir = std::env::var("DATA_DIR")
        .unwrap_or_else(|_| "shipley_checks/stage4".to_string());

    let scorer = GuildScorer::new("7plant", "tier_3_humid_temperate", &data_dir)?;

    let plant_ids = vec![
        "wfo-0000721951".to_string(),
        "wfo-0000955348".to_string(),
        "wfo-0000901050".to_string(),
        "wfo-0000956222".to_string(),
        "wfo-0000777518".to_string(),
        "wfo-0000349035".to_string(),
        "wfo-0000209726".to_string(),
    ];

    let result = scorer.score_guild(&plant_ids)?;

    println!("Overall score: {:.6}", result.overall_score);
    println!("\nM4 (Disease Control):");
    println!("  Display score: {:.2}", result.metrics[3]);
    println!("  Raw score:     {:.6}", result.raw_scores[3]);
    println!("\nAll raw scores:");
    for (i, raw) in result.raw_scores.iter().enumerate() {
        println!("  M{}: {:.6}", i + 1, raw);
    }

    Ok(())
}
