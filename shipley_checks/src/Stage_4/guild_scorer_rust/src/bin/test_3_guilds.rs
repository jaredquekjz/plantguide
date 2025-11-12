//! Test 3 guilds for parity verification
//!
//! Expected scores from R (near-perfect parity with Python):
//! - Forest Garden: 90.467710
//! - Competitive Clash: 55.441621
//! - Stress-Tolerant: 45.442341

use guild_scorer_rust::GuildScorer;

fn main() {
    // Initialize scorer
    println!("Initializing Guild Scorer (Rust)...\n");
    let scorer = GuildScorer::new("7plant", "tier_3_humid_temperate")
        .expect("Failed to initialize scorer");

    // Define 3 test guilds from Stage_4_Dual_Verification_Pipeline.md
    let guilds = vec![
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
            90.467710,
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
            55.441621,
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
            45.442341,
        ),
    ];

    println!("\n{}", "=".repeat(70));
    println!("PARITY TEST: 3 Guilds vs R Implementation");
    println!("{}", "=".repeat(70));

    let mut max_diff = 0.0_f64;
    let mut all_passed = true;

    for (name, plant_ids, expected) in &guilds {
        match scorer.score_guild(plant_ids) {
            Ok(result) => {
                let diff = (result.overall_score - expected).abs();
                max_diff = max_diff.max(diff);

                let status = if diff < 0.0001 {
                    "✅ PERFECT"
                } else if diff < 0.01 {
                    "✓ PASS"
                } else {
                    all_passed = false;
                    "✗ FAIL"
                };

                println!("\n{}", name);
                println!("  Expected:  {:.6}", expected);
                println!("  Rust:      {:.6}", result.overall_score);
                println!("  Difference: {:.6}", diff);
                println!("  Status:    {}", status);

                // Show individual metrics
                println!("  Metrics:");
                println!("    M1: Pest Independence     {:.1}", result.metrics[0]);
                println!("    M2: Growth Compatibility  {:.1}", result.metrics[1]);
                println!("    M3: Insect Control        {:.1}", result.metrics[2]);
                println!("    M4: Disease Control       {:.1}", result.metrics[3]);
                println!("    M5: Beneficial Fungi      {:.1}", result.metrics[4]);
                println!("    M6: Structural Diversity  {:.1}", result.metrics[5]);
                println!("    M7: Pollinator Support    {:.1}", result.metrics[6]);
            }
            Err(e) => {
                println!("\n{}", name);
                println!("  ERROR: {:?}", e);
                all_passed = false;
            }
        }
    }

    println!("\n{}", "=".repeat(70));
    println!("SUMMARY");
    println!("{}", "=".repeat(70));
    println!("Maximum difference: {:.6}", max_diff);
    println!("Threshold: < 0.0001 (0.01%)");

    if all_passed && max_diff < 0.0001 {
        println!("\n✅ PARITY ACHIEVED: 100% match with R implementation");
        std::process::exit(0);
    } else if all_passed {
        println!("\n✓ NEAR PARITY: Within acceptable tolerance");
        std::process::exit(0);
    } else {
        println!("\n✗ PARITY FAILED: Differences exceed tolerance");
        std::process::exit(1);
    }
}
