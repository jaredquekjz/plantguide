//! Baseline Memory Profiling Test
//!
//! This test measures memory usage and performance BEFORE LazyFrame optimization.
//! It scores 1 guild and pauses to allow external memory monitoring.
//!
//! Usage:
//!   cargo build --release --bin test_memory_baseline
//!   /usr/bin/time -v ./target/release/test_memory_baseline 2>&1 | tee baseline_memory.log
//!
//! In another terminal, monitor with:
//!   watch -n 1 'ps aux | grep test_memory_baseline'

use guild_scorer_rust::*;
use std::io::{self, Write};
use std::time::Instant;
use anyhow::Result;

fn main() -> Result<()> {
    println!("======================================================================");
    println!("BASELINE MEMORY PROFILING TEST (Before Optimization)");
    println!("======================================================================\n");

    // Default data_dir for local development
    let data_dir = std::env::var("DATA_DIR")
        .unwrap_or_else(|_| "shipley_checks/stage4".to_string());

    // Measure initialization time and memory
    println!("Starting initialization...");
    println!("(Check memory usage in another terminal with: ps aux | grep test_memory_baseline)\n");

    let init_start = Instant::now();
    let scorer = GuildScorer::new("7plant", "tier_3_humid_temperate", &data_dir)?;
    let init_time = init_start.elapsed();

    println!("Initialization complete: {:?}", init_time);
    println!("\n>>> Press Enter to continue (this allows you to check memory usage now)...");
    pause_for_user_input();

    // Test guild: Forest Garden (7 plants)
    // This is a representative guild for measuring per-guild memory usage
    let guild_name = "Forest Garden";
    let plant_ids = vec![
        "wfo-0000832453".to_string(),  // Fraxinus excelsior
        "wfo-0000649136".to_string(),  // Diospyros kaki
        "wfo-0000642673".to_string(),  // Deutzia scabra
        "wfo-0000984977".to_string(),  // Rubus moorei
        "wfo-0000241769".to_string(),  // Mercurialis perennis
        "wfo-0000092746".to_string(),  // Anaphalis margaritacea
        "wfo-0000690499".to_string(),  // Maianthemum racemosum
    ];

    println!("\n----------------------------------------------------------------------");
    println!("Scoring guild: {}", guild_name);
    println!("Number of plants: {}", plant_ids.len());
    println!("----------------------------------------------------------------------\n");

    let score_start = Instant::now();
    let result = scorer.score_guild(&plant_ids)?;
    let score_time = score_start.elapsed();

    println!("Overall score: {:.6}", result.overall_score);
    println!("Scoring time: {:?}", score_time);
    println!("\nIndividual metrics:");
    println!("  M1 (Pest Independence):    {:.1}", result.metrics[0]);
    println!("  M2 (Growth Compatibility): {:.1}", result.metrics[1]);
    println!("  M3 (Insect Control):       {:.1}", result.metrics[2]);
    println!("  M4 (Disease Control):      {:.1}", result.metrics[3]);
    println!("  M5 (Beneficial Fungi):     {:.1}", result.metrics[4]);
    println!("  M6 (Structural Diversity): {:.1}", result.metrics[5]);
    println!("  M7 (Pollinator Support):   {:.1}", result.metrics[6]);

    println!("\n>>> Press Enter to finish (check final memory usage)...");
    pause_for_user_input();

    println!("\n======================================================================");
    println!("BASELINE MEASUREMENT COMPLETE");
    println!("======================================================================");
    println!("\nRecord these values in OPTIMIZATION_METRICS.md:");
    println!("  - Initialization time: {:?}", init_time);
    println!("  - Scoring time: {:?}", score_time);
    println!("  - Peak RSS: (from /usr/bin/time -v output)");
    println!("  - Max resident set size: (from ps output)");
    println!("\n");

    Ok(())
}

/// Pause execution and wait for user to press Enter
///
/// This allows external monitoring tools to capture memory usage at specific points
fn pause_for_user_input() {
    let mut input = String::new();
    io::stdout().flush().unwrap();
    io::stdin().read_line(&mut input).unwrap();
}
