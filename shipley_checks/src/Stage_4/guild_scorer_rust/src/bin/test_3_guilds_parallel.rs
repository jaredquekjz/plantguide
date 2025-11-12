//! Test 3 guilds with PARALLEL implementation
//!
//! Compares sequential vs parallel metric computation performance.
//!
//! Expected scores from R (near-perfect parity with Python):
//! - Forest Garden: 90.467710
//! - Competitive Clash: 55.441621
//! - Stress-Tolerant: 45.442341

use guild_scorer_rust::GuildScorer;
use std::time::Instant;

fn main() {
    // Initialize scorer
    println!("Initializing Guild Scorer (Rust)...\n");
    let init_start = Instant::now();
    let scorer = GuildScorer::new("7plant", "tier_3_humid_temperate")
        .expect("Failed to initialize scorer");
    let init_time = init_start.elapsed();

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
    println!("PARITY TEST: 3 Guilds (Sequential vs Parallel)");
    println!("{}", "=".repeat(70));

    // =======================================================================
    // SEQUENTIAL EXECUTION
    // =======================================================================
    println!("\n{}", "-".repeat(70));
    println!("SEQUENTIAL MODE (baseline)");
    println!("{}", "-".repeat(70));

    let mut max_diff_seq = 0.0_f64;
    let mut all_passed_seq = true;
    let mut guild_times_seq = Vec::new();

    let scoring_start_seq = Instant::now();
    for (name, plant_ids, expected) in &guilds {
        let guild_start = Instant::now();
        match scorer.score_guild(plant_ids) {
            Ok(result) => {
                let diff = (result.overall_score - expected).abs();
                max_diff_seq = max_diff_seq.max(diff);

                let status = if diff < 0.0001 {
                    "✅ PERFECT"
                } else if diff < 0.01 {
                    "✓ PASS"
                } else {
                    all_passed_seq = false;
                    "✗ FAIL"
                };

                println!("\n{}", name);
                println!("  Expected:  {:.6}", expected);
                println!("  Sequential: {:.6}", result.overall_score);
                println!("  Difference: {:.6}", diff);
                println!("  Status:    {}", status);

                let guild_time = guild_start.elapsed();
                guild_times_seq.push(guild_time);
            }
            Err(e) => {
                println!("\n{}", name);
                println!("  ERROR: {:?}", e);
                all_passed_seq = false;
            }
        }
    }
    let total_scoring_time_seq = scoring_start_seq.elapsed();

    // =======================================================================
    // PARALLEL EXECUTION
    // =======================================================================
    println!("\n{}", "-".repeat(70));
    println!("PARALLEL MODE (Rayon - 7 metrics in parallel)");
    println!("{}", "-".repeat(70));

    let mut max_diff_par = 0.0_f64;
    let mut all_passed_par = true;
    let mut guild_times_par = Vec::new();

    let scoring_start_par = Instant::now();
    for (name, plant_ids, expected) in &guilds {
        let guild_start = Instant::now();
        match scorer.score_guild_parallel(plant_ids) {
            Ok(result) => {
                let diff = (result.overall_score - expected).abs();
                max_diff_par = max_diff_par.max(diff);

                let status = if diff < 0.0001 {
                    "✅ PERFECT"
                } else if diff < 0.01 {
                    "✓ PASS"
                } else {
                    all_passed_par = false;
                    "✗ FAIL"
                };

                println!("\n{}", name);
                println!("  Expected:  {:.6}", expected);
                println!("  Parallel:  {:.6}", result.overall_score);
                println!("  Difference: {:.6}", diff);
                println!("  Status:    {}", status);

                let guild_time = guild_start.elapsed();
                guild_times_par.push(guild_time);
            }
            Err(e) => {
                println!("\n{}", name);
                println!("  ERROR: {:?}", e);
                all_passed_par = false;
            }
        }
    }
    let total_scoring_time_par = scoring_start_par.elapsed();

    // =======================================================================
    // SUMMARY
    // =======================================================================
    println!("\n{}", "=".repeat(70));
    println!("SUMMARY");
    println!("{}", "=".repeat(70));
    println!("Sequential max difference: {:.6}", max_diff_seq);
    println!("Parallel max difference:   {:.6}", max_diff_par);
    println!("Threshold: < 0.0001 (0.01%)");

    // =======================================================================
    // PERFORMANCE COMPARISON
    // =======================================================================
    println!("\n{}", "=".repeat(70));
    println!("PERFORMANCE COMPARISON (Debug Build)");
    println!("{}", "=".repeat(70));
    println!("Initialization: {:.3} ms", init_time.as_secs_f64() * 1000.0);
    println!();

    println!("Sequential Mode:");
    println!("  3 Guild Scoring: {:.3} ms total", total_scoring_time_seq.as_secs_f64() * 1000.0);
    for (i, time) in guild_times_seq.iter().enumerate() {
        println!("    Guild {}: {:.3} ms", i + 1, time.as_secs_f64() * 1000.0);
    }
    println!("  Average per guild: {:.3} ms", total_scoring_time_seq.as_secs_f64() * 1000.0 / 3.0);
    println!();

    println!("Parallel Mode (Rayon):");
    println!("  3 Guild Scoring: {:.3} ms total", total_scoring_time_par.as_secs_f64() * 1000.0);
    for (i, time) in guild_times_par.iter().enumerate() {
        println!("    Guild {}: {:.3} ms", i + 1, time.as_secs_f64() * 1000.0);
    }
    println!("  Average per guild: {:.3} ms", total_scoring_time_par.as_secs_f64() * 1000.0 / 3.0);
    println!();

    let speedup = total_scoring_time_seq.as_secs_f64() / total_scoring_time_par.as_secs_f64();
    println!("Speedup: {:.2}× faster (parallel vs sequential)", speedup);

    // Estimate for 100 guilds
    let seq_100 = (total_scoring_time_seq.as_secs_f64() / 3.0) * 100.0;
    let par_100 = (total_scoring_time_par.as_secs_f64() / 3.0) * 100.0;
    println!();
    println!("Estimated 100-guild performance:");
    println!("  Sequential: {:.1} seconds", seq_100);
    println!("  Parallel:   {:.1} seconds", par_100);
    println!("  Speedup:    {:.2}×", seq_100 / par_100);

    if all_passed_seq && all_passed_par && max_diff_seq < 0.0001 && max_diff_par < 0.0001 {
        println!("\n✅ PARITY ACHIEVED: 100% match in both sequential and parallel modes");
        std::process::exit(0);
    } else if all_passed_seq && all_passed_par {
        println!("\n✓ NEAR PARITY: Within acceptable tolerance");
        std::process::exit(0);
    } else {
        println!("\n✗ PARITY FAILED: Differences exceed tolerance");
        std::process::exit(1);
    }
}
