//! Generate Exhaustive Pairwise Phylogenetic Distance Parquet
//!
//! Computes pairwise phylogenetic distances for all 11,673 plants with tree mappings.
//! Uses Rayon for parallel processing across all available cores.
//!
//! Output: shipley_checks/stage4/phase0_output/pairwise_phylo_distances.parquet
//!
//! Scale:
//!   - 11,673 plants × 11,672 = 136,223,256 pairs (full symmetric matrix)
//!   - ~3-4 GB parquet output (ZSTD compressed)
//!   - ~80-120 seconds on 32-thread system

use anyhow::{Context, Result};
use polars::prelude::*;
use rayon::prelude::*;
use std::collections::HashMap;
use std::fs;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;

use guild_scorer_rust::CompactTree;

fn main() -> Result<()> {
    println!("\n{}", "=".repeat(80));
    println!("PAIRWISE PHYLOGENETIC DISTANCE GENERATOR");
    println!("{}", "=".repeat(80));

    let total_start = Instant::now();

    // Paths
    let data_dir = std::env::var("DATA_DIR")
        .unwrap_or_else(|_| "shipley_checks/stage4".to_string());

    let tree_bin_path = format!("{}/stage1/phlogeny/compact_tree_11711.bin", data_dir);
    let tree_bin_fallback = "data/stage1/phlogeny/compact_tree_11711.bin";
    let mapping_path = format!("{}/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv", data_dir);
    let mapping_fallback = "data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv";
    let output_path = format!("{}/phase0_output/pairwise_phylo_distances.parquet", data_dir);

    // Resolve paths
    let tree_path = if std::path::Path::new(&tree_bin_path).exists() {
        tree_bin_path
    } else {
        tree_bin_fallback.to_string()
    };
    let map_path = if std::path::Path::new(&mapping_path).exists() {
        mapping_path
    } else {
        mapping_fallback.to_string()
    };

    // ========================================================================
    // Step 1: Load CompactTree
    // ========================================================================
    println!("\nStep 1: Loading phylogenetic tree...");
    let tree = CompactTree::from_binary(&tree_path)
        .with_context(|| format!("Failed to load tree from: {}", tree_path))?;
    println!("  Nodes: {}", tree.get_num_nodes());
    println!("  Leaves: {}", tree.num_leaves());

    // ========================================================================
    // Step 2: Load WFO -> tree_tip mapping
    // ========================================================================
    println!("\nStep 2: Loading WFO → tree tip mapping...");
    let wfo_to_tip = load_mapping(&map_path)?;
    println!("  WFO mappings: {}", wfo_to_tip.len());

    // ========================================================================
    // Step 3: Build WFO -> node_id mapping (only plants with tree presence)
    // ========================================================================
    println!("\nStep 3: Building WFO → node_id mapping...");
    let mut wfo_ids: Vec<String> = Vec::with_capacity(wfo_to_tip.len());
    let mut node_ids: Vec<u32> = Vec::with_capacity(wfo_to_tip.len());

    for (wfo_id, tree_tip) in &wfo_to_tip {
        if let Some(node_id) = tree.find_node_by_label(tree_tip) {
            wfo_ids.push(wfo_id.clone());
            node_ids.push(node_id);
        }
    }
    let n = wfo_ids.len();
    println!("  Plants with tree mappings: {}", n);
    println!("  Total pairs to compute: {} × {} = {} (full symmetric)", n, n - 1, n * (n - 1));

    // ========================================================================
    // Step 4: Compute all pairwise distances in parallel
    // ========================================================================
    println!("\nStep 4: Computing pairwise distances...");
    let compute_start = Instant::now();

    let progress = AtomicUsize::new(0);
    let total_anchors = n;

    // Full symmetric matrix: for each plant i, compute distance to all plants j (where j != i)
    let results: Vec<(String, String, f64)> = (0..n)
        .into_par_iter()
        .flat_map(|i| {
            // Progress tracking
            let count = progress.fetch_add(1, Ordering::Relaxed) + 1;
            if count % 500 == 0 || count == total_anchors {
                eprint!("\r  Progress: {}/{} anchors ({:.1}%)",
                    count, total_anchors, count as f64 / total_anchors as f64 * 100.0);
            }

            // Compute distances from plant i to all other plants
            (0..n)
                .filter(|&j| i != j)
                .map(|j| {
                    let distance = tree.pairwise_distance(node_ids[i], node_ids[j]);
                    (wfo_ids[i].clone(), wfo_ids[j].clone(), distance)
                })
                .collect::<Vec<_>>()
        })
        .collect();

    eprintln!(); // New line after progress
    let compute_time = compute_start.elapsed();
    println!("  Computed {} pairs in {:.1}s", results.len(), compute_time.as_secs_f64());
    println!("  Rate: {:.0} pairs/sec", results.len() as f64 / compute_time.as_secs_f64());

    // ========================================================================
    // Step 5: Write to Parquet
    // ========================================================================
    println!("\nStep 5: Writing parquet...");
    let write_start = Instant::now();

    // Convert to columnar format for Polars
    let wfo_id_a: Vec<&str> = results.iter().map(|(a, _, _)| a.as_str()).collect();
    let wfo_id_b: Vec<&str> = results.iter().map(|(_, b, _)| b.as_str()).collect();
    let distances: Vec<f64> = results.iter().map(|(_, _, d)| *d).collect();

    let df = DataFrame::new(vec![
        Series::new("wfo_id_a".into(), wfo_id_a).into(),
        Series::new("wfo_id_b".into(), wfo_id_b).into(),
        Series::new("distance".into(), distances).into(),
    ])?;

    println!("  DataFrame: {} rows × {} cols", df.height(), df.width());

    // Ensure output directory exists
    if let Some(parent) = std::path::Path::new(&output_path).parent() {
        fs::create_dir_all(parent)?;
    }

    // Write with ZSTD compression
    let file = fs::File::create(&output_path)?;
    ParquetWriter::new(file)
        .with_compression(ParquetCompression::Zstd(None))
        .finish(&mut df.clone())?;

    let write_time = write_start.elapsed();
    let file_size = fs::metadata(&output_path)?.len() as f64 / (1024.0 * 1024.0 * 1024.0);
    println!("  Written to: {}", output_path);
    println!("  File size: {:.2} GB", file_size);
    println!("  Write time: {:.1}s", write_time.as_secs_f64());

    // ========================================================================
    // Summary
    // ========================================================================
    let total_time = total_start.elapsed();
    println!("\n{}", "=".repeat(80));
    println!("COMPLETE");
    println!("{}", "=".repeat(80));
    println!("  Plants: {}", n);
    println!("  Pairs: {}", results.len());
    println!("  File: {} ({:.2} GB)", output_path, file_size);
    println!("  Total time: {:.1}s", total_time.as_secs_f64());
    println!("{}", "=".repeat(80));

    Ok(())
}

/// Load WFO ID -> tree tip mapping from CSV
fn load_mapping(path: &str) -> Result<HashMap<String, String>> {
    let contents = fs::read_to_string(path)
        .with_context(|| format!("Failed to read mapping file: {}", path))?;

    let mut mapping = HashMap::new();
    for (idx, line) in contents.lines().enumerate() {
        if idx == 0 {
            continue; // Skip header: wfo_taxon_id,wfo_scientific_name,is_infraspecific,parent_binomial,parent_label,tree_tip
        }
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() >= 6 {
            let wfo_id = parts[0].to_string();
            let tree_tip = parts[5].to_string(); // Column 5 is tree_tip
            if !tree_tip.is_empty() && tree_tip != "NA" {
                mapping.insert(wfo_id, tree_tip);
            }
        }
    }

    Ok(mapping)
}
