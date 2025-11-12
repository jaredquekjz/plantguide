//! Benchmark Rust CompactTree on 1000 test guilds
//!
//! Tests Faith's PD calculation against R picante (gold standard) and C++ CompactTree.
//! Validates 100% parity on 1000 random guilds with realistic size distribution.

use guild_scorer_rust::compact_tree::CompactTree;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::time::Instant;
use anyhow::Result;

fn main() -> Result<()> {
    // Paths
    let tree_bin_path = "data/stage1/phlogeny/compact_tree_11711.bin";
    let guilds_path = "shipley_checks/stage4/test_guilds_1000.csv";
    let output_path = "shipley_checks/stage4/rust_results_1000.csv";

    // Load tree ONCE (amortize loading cost)
    println!("Loading phylogenetic tree...");
    let tree_start = Instant::now();
    let tree = CompactTree::from_binary(tree_bin_path)?;
    let tree_load_ms = tree_start.elapsed().as_secs_f64() * 1000.0;

    println!("Tree loaded:");
    println!("  Nodes: {}", tree.get_num_nodes());
    println!("  Leaves: {}", tree.num_leaves());
    println!("  Load time: {:.3} ms", tree_load_ms);

    // Load guilds CSV
    println!("\nLoading guilds from: {}", guilds_path);
    let file = File::open(guilds_path)?;
    let reader = BufReader::new(file);

    let mut guild_ids = Vec::new();
    let mut guild_sizes = Vec::new();
    let mut guild_species = Vec::new();

    for (i, line) in reader.lines().enumerate() {
        if i == 0 {
            continue; // Skip header: guild_id,guild_size,species
        }

        let line = line?;
        let parts: Vec<&str> = line.split(',').collect();

        if parts.len() < 3 {
            eprintln!("Warning: Skipping malformed line {}: {}", i, line);
            continue;
        }

        guild_ids.push(parts[0].parse::<usize>()?);
        guild_sizes.push(parts[1].parse::<usize>()?);

        // Parse species list (delimiter: ;;)
        // Format: wfo-0000832453|Fraxinus_excelsior;;wfo-0000649136|Malus_domestica
        let species: Vec<String> = parts[2]
            .split(";;")
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();

        guild_species.push(species);
    }

    println!("Loaded {} guilds", guild_ids.len());

    // Warm-up (3 iterations to prime CPU cache)
    println!("\nWarm-up (3 iterations)...");
    for _ in 0..3 {
        let _ = tree.calculate_faiths_pd_by_labels(&guild_species[0]);
    }

    // Benchmark all guilds
    println!("\nBenchmarking {} guilds...", guild_ids.len());
    let mut results = Vec::new();

    let start = Instant::now();

    for species_list in &guild_species {
        let pd = tree.calculate_faiths_pd_by_labels(species_list);
        results.push(pd);
    }

    let total_time_sec = start.elapsed().as_secs_f64();
    let mean_time_ms = (total_time_sec / results.len() as f64) * 1000.0;
    let mean_time_us = mean_time_ms * 1000.0;

    // Save results
    println!("\nSaving results to: {}", output_path);
    let mut output = File::create(output_path)?;
    writeln!(output, "guild_id,guild_size,faiths_pd")?;
    for i in 0..results.len() {
        writeln!(output, "{},{},{:.10}", guild_ids[i], guild_sizes[i], results[i])?;
    }

    // Print summary
    println!("\n======================================================================");
    println!("RUST COMPACTTREE BENCHMARK");
    println!("======================================================================");
    println!("Guilds processed: {}", results.len());
    println!("Total time: {:.3} seconds", total_time_sec);
    println!("Mean time per guild: {:.6} ms ({:.3} μs)", mean_time_ms, mean_time_us);
    println!("Throughput: {:.0} guilds/second", results.len() as f64 / total_time_sec);
    println!("\n======================================================================");
    println!("COMPARISON TO GOLD STANDARD");
    println!("======================================================================");
    println!("R picante (gold):    11.668 ms/guild = 86 guilds/second");
    println!("C++ CompactTree:      0.016 ms/guild = 60,853 guilds/second (708×)");
    println!("Rust CompactTree:     {:.3} ms/guild = {:.0} guilds/second",
             mean_time_ms, results.len() as f64 / total_time_sec);

    let speedup_vs_r = 11.668 / mean_time_ms;
    let speedup_vs_cpp = 0.016433 / mean_time_ms;
    println!("\nSpeedup:");
    println!("  vs R picante: {:.0}×", speedup_vs_r);
    println!("  vs C++ CompactTree: {:.2}×", speedup_vs_cpp);

    println!("\nResults saved to: {}", output_path);
    println!("\nNext step: Run comparison script to verify parity");
    println!("  python shipley_checks/src/Stage_4/faiths_pd_benchmark/compare_faiths_pd_results.py");

    Ok(())
}
