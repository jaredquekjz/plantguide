use guild_scorer_rust::GuildScorer;

fn main() -> anyhow::Result<()> {
    let scorer = GuildScorer::new("7plant", "tier_3_humid_temperate")?;
    
    let plant_ids = vec![
        "wfo-0000910097".to_string(),
        "wfo-0000421791".to_string(),
        "wfo-0000861498".to_string(),
        "wfo-0001007437".to_string(),
        "wfo-0000292858".to_string(),
        "wfo-0001005999".to_string(),
        "wfo-0000993770".to_string(),
    ];
    
    let result = scorer.score_guild(&plant_ids)?;
    
    println!("Entomopathogen Powerhouse:");
    println!("  Overall: {:.6}", result.overall_score);
    println!("  M4 display: {:.2}", result.metrics[3]);
    println!("  M4 raw: {:.6}", result.raw_scores[3]);
    
    Ok(())
}
