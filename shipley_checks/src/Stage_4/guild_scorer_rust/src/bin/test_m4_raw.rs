///! Simple test to show M4 raw scores

use guild_scorer_rust::GuildScorer;

fn main() {
    println!("\n=== M4 RAW CALCULATION (Rust) ===\n");

    let scorer = GuildScorer::new("7plant", "tier_3_humid_temperate")
        .expect("Failed to initialize scorer");

    // Forest Garden
    let guild_ids = vec![
        "wfo-0000832453".to_string(),
        "wfo-0000649136".to_string(),
        "wfo-0000642673".to_string(),
        "wfo-0000984977".to_string(),
        "wfo-0000241769".to_string(),
        "wfo-0000092746".to_string(),
        "wfo-0000690499".to_string(),
    ];

    let raw_scores = scorer.compute_raw_scores(&guild_ids)
        .expect("Failed to compute raw scores");

    println!("M4 raw (normalized):     {:.6}", raw_scores.m4_pathogen_control_raw);
}
