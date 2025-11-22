//! Köppen-Stratified Calibration Pipeline (Rust Implementation)
//!
//! 2-Stage Calibration:
//!   Stage 1: 2-plant pairs (20K per tier × 6 tiers = 120K pairs)
//!   Stage 2: 7-plant guilds (20K per tier × 6 tiers = 120K guilds)
//!
//! Output: normalization_params_7plant.json (546 calibration values)
//!
//! Expected Performance:
//!   - R baseline: ~600 seconds
//!   - Rust target: ~25 seconds (24× speedup)

use guild_scorer_rust::{GuildScorer, ClimateOrganizer, RawScores};
use rayon::prelude::*;
use serde_json::json;
use std::time::Instant;
use rand::seq::SliceRandom;
use rand::thread_rng;
use std::sync::atomic::{AtomicUsize, Ordering};

const GUILDS_PER_TIER: usize = 20000;  // Production calibration - 20K guilds per tier
const PERCENTILES: [f64; 13] = [1.0, 5.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 95.0, 99.0];

fn main() -> anyhow::Result<()> {
    println!("\n{}", "=".repeat(80));
    println!("KÖPPEN-STRATIFIED CALIBRATION PIPELINE (RUST)");
    println!("{}", "=".repeat(80));

    let total_start = Instant::now();

    // Initialize canonical GuildScorer for calibration (mirrors R pattern)
    println!("\nInitializing GuildScorer...");
    let guild_scorer = GuildScorer::new_for_calibration("tier_3_humid_temperate")?;

    // Organize by climate tier
    println!("\nOrganizing plants by Köppen tier...");
    let organizer = ClimateOrganizer::from_plants(&guild_scorer.data().plants)?;

    // STAGE 1: 2-PLANT PAIRS
    println!("\n{}", "=".repeat(80));
    println!("STAGE 1: 2-PLANT PAIR CALIBRATION");
    println!("{}", "=".repeat(80));

    let stage1_start = Instant::now();
    let params_2plant = calibrate_2plant_pairs(&organizer, &guild_scorer)?;
    let stage1_time = stage1_start.elapsed();

    // Save Stage 1 results
    let output_path_2plant = "shipley_checks/stage4/phase5_output/normalization_params_2plant.json";
    std::fs::write(output_path_2plant, serde_json::to_string_pretty(&params_2plant)?)?;
    println!("\n✓ Saved: {}", output_path_2plant);

    // STAGE 2: 7-PLANT GUILDS
    println!("\n{}", "=".repeat(80));
    println!("STAGE 2: 7-PLANT GUILD CALIBRATION");
    println!("{}", "=".repeat(80));

    let stage2_start = Instant::now();
    let params_7plant = calibrate_7plant_guilds(&organizer, &guild_scorer)?;
    let stage2_time = stage2_start.elapsed();

    // Save Stage 2 results
    let output_path_7plant = "shipley_checks/stage4/phase5_output/normalization_params_7plant.json";
    std::fs::write(output_path_7plant, serde_json::to_string_pretty(&params_7plant)?)?;
    println!("\n✓ Saved: {}", output_path_7plant);

    // Summary
    let total_time = total_start.elapsed();
    println!("\n{}", "=".repeat(80));
    println!("CALIBRATION COMPLETE");
    println!("{}", "=".repeat(80));
    println!("\nStage 1 (2-plant pairs): {:.1}s", stage1_time.as_secs_f64());
    println!("Stage 2 (7-plant guilds): {:.1}s", stage2_time.as_secs_f64());
    println!("\nTotal time: {:.1}s", total_time.as_secs_f64());
    println!("Total guilds: {}", GUILDS_PER_TIER * 6 * 2);

    Ok(())
}

/// Stage 1: Calibrate 2-plant pairs
///
/// Uses canonical GuildScorer to compute raw scores (mirrors R pattern)
fn calibrate_2plant_pairs(
    organizer: &ClimateOrganizer,
    guild_scorer: &GuildScorer,
) -> anyhow::Result<serde_json::Value> {
    let mut params = serde_json::Map::new();

    for tier_name in organizer.tiers() {
        println!("\n{}", "-".repeat(70));
        println!("Tier: {}", tier_name);
        println!("{}", "-".repeat(70));

        let tier_plants = organizer.get_tier_plants(tier_name);
        println!("  Available plants: {}", tier_plants.len());

        if tier_plants.len() < 2 {
            println!("  ⚠ Skipping tier (insufficient plants)");
            continue;
        }

        // Sample 20K random pairs
        let start_sampling = Instant::now();
        let pairs = sample_random_pairs(tier_plants, GUILDS_PER_TIER);
        println!("  Sampled {} pairs in {:.2}s", pairs.len(), start_sampling.elapsed().as_secs_f64());

        // Compute raw scores in parallel using canonical GuildScorer (with progress tracking)
        let start_scoring = Instant::now();
        let progress = AtomicUsize::new(0);
        let total = pairs.len();

        print!("  Scoring: 0/{}", total);
        std::io::Write::flush(&mut std::io::stdout()).ok();

        let (raw_scores, errors): (Vec<_>, Vec<_>) = pairs.par_iter()
            .map(|pair| {
                let result = guild_scorer.compute_raw_scores(pair);
                let count = progress.fetch_add(1, Ordering::Relaxed) + 1;
                if count % 1000 == 0 || count == total {
                    print!("\r  Scoring: {}/{}", count, total);
                    std::io::Write::flush(&mut std::io::stdout()).ok();
                }
                result
            })
            .partition(Result::is_ok);
        let raw_scores: Vec<_> = raw_scores.into_iter().map(Result::unwrap).collect();
        println!("\r  Computed raw scores in {:.2}s", start_scoring.elapsed().as_secs_f64());
        println!("  Valid scores: {}", raw_scores.len());
        if !errors.is_empty() {
            println!("  ⚠ Failed scores: {}", errors.len());
            println!("  First error: {}", errors[0].as_ref().unwrap_err());
        }

        // Calculate percentiles for M1 and M2
        let tier_params = calculate_tier_percentiles_2plant(&raw_scores);
        params.insert(tier_name.to_string(), tier_params);
    }

    Ok(serde_json::Value::Object(params))
}

/// Stage 2: Calibrate 7-plant guilds
///
/// Uses canonical GuildScorer to compute raw scores (mirrors R pattern)
fn calibrate_7plant_guilds(
    organizer: &ClimateOrganizer,
    guild_scorer: &GuildScorer,
) -> anyhow::Result<serde_json::Value> {
    let mut params = serde_json::Map::new();

    for tier_name in organizer.tiers() {
        println!("\n{}", "-".repeat(70));
        println!("Tier: {}", tier_name);
        println!("{}", "-".repeat(70));

        let tier_plants = organizer.get_tier_plants(tier_name);
        println!("  Available plants: {}", tier_plants.len());

        if tier_plants.len() < 7 {
            println!("  ⚠ Skipping tier (insufficient plants)");
            continue;
        }

        // Sample 20K random 7-plant guilds
        let start_sampling = Instant::now();
        let guilds = sample_random_guilds(tier_plants, 7, GUILDS_PER_TIER);
        println!("  Sampled {} guilds in {:.2}s", guilds.len(), start_sampling.elapsed().as_secs_f64());

        // Compute raw scores in parallel using canonical GuildScorer (with progress tracking)
        let start_scoring = Instant::now();
        let progress = AtomicUsize::new(0);
        let total = guilds.len();

        print!("  Scoring: 0/{}", total);
        std::io::Write::flush(&mut std::io::stdout()).ok();

        let raw_scores: Vec<_> = guilds.par_iter()
            .filter_map(|guild| {
                let result = guild_scorer.compute_raw_scores(guild).ok();
                let count = progress.fetch_add(1, Ordering::Relaxed) + 1;
                if count % 1000 == 0 || count == total {
                    print!("\r  Scoring: {}/{}", count, total);
                    std::io::Write::flush(&mut std::io::stdout()).ok();
                }
                result
            })
            .collect();
        println!("\r  Computed raw scores in {:.2}s", start_scoring.elapsed().as_secs_f64());
        println!("  Valid scores: {}", raw_scores.len());

        // Calculate percentiles for M1-M7
        let tier_params = calculate_tier_percentiles_7plant(&raw_scores);
        params.insert(tier_name.to_string(), tier_params);
    }

    Ok(serde_json::Value::Object(params))
}

/// Sample random pairs from tier plants
fn sample_random_pairs(plants: &[String], n_pairs: usize) -> Vec<Vec<String>> {
    let mut rng = thread_rng();
    let mut pairs = Vec::with_capacity(n_pairs);

    for _ in 0..n_pairs {
        let pair: Vec<_> = plants.choose_multiple(&mut rng, 2).cloned().collect();
        pairs.push(pair);
    }

    pairs
}

/// Sample random guilds from tier plants
fn sample_random_guilds(plants: &[String], guild_size: usize, n_guilds: usize) -> Vec<Vec<String>> {
    let mut rng = thread_rng();
    let mut guilds = Vec::with_capacity(n_guilds);

    for _ in 0..n_guilds {
        let guild: Vec<_> = plants.choose_multiple(&mut rng, guild_size).cloned().collect();
        guilds.push(guild);
    }

    guilds
}

/// Calculate percentiles for 2-plant pairs (M1, M2 only)
fn calculate_tier_percentiles_2plant(raw_scores: &[RawScores]) -> serde_json::Value {
    // Extract raw values
    let m1_values: Vec<f64> = raw_scores.iter().map(|s| s.m1_pest_risk).collect();
    let m2_values: Vec<f64> = raw_scores.iter().map(|s| s.m2_conflict_density).collect();

    // Calculate percentiles
    let m1_percentiles = calculate_percentiles(&m1_values);
    let m2_percentiles = calculate_percentiles(&m2_values);

    json!({
        "m1": m1_percentiles,
        "n4": m2_percentiles,  // n4 is legacy name for M2
    })
}

/// Calculate percentiles for 7-plant guilds (M1-M7)
fn calculate_tier_percentiles_7plant(raw_scores: &[RawScores]) -> serde_json::Value {
    // Extract raw values for each metric
    let m1_values: Vec<f64> = raw_scores.iter().map(|s| s.m1_pest_risk).collect();
    let m2_values: Vec<f64> = raw_scores.iter().map(|s| s.m2_conflict_density).collect();
    let m3_values: Vec<f64> = raw_scores.iter().map(|s| s.m3_biocontrol_raw).collect();
    let m4_values: Vec<f64> = raw_scores.iter().map(|s| s.m4_pathogen_control_raw).collect();
    let m5_values: Vec<f64> = raw_scores.iter().map(|s| s.m5_beneficial_fungi_raw).collect();
    let m6_values: Vec<f64> = raw_scores.iter().map(|s| s.m6_stratification_raw).collect();
    let m7_values: Vec<f64> = raw_scores.iter().map(|s| s.m7_pollinator_raw).collect();

    // Calculate percentiles
    json!({
        "m1": calculate_percentiles(&m1_values),
        "n4": calculate_percentiles(&m2_values),  // n4 is legacy name for M2
        "p1": calculate_percentiles(&m3_values),  // p1 is legacy name for M3
        "p2": calculate_percentiles(&m4_values),  // p2 is legacy name for M4
        "p3": calculate_percentiles(&m5_values),  // p3 is legacy name for M5
        "p5": calculate_percentiles(&m6_values),  // p5 is legacy name for M6
        "p6": calculate_percentiles(&m7_values),  // p6 is legacy name for M7
    })
}

/// Calculate percentile values for a metric
fn calculate_percentiles(values: &[f64]) -> serde_json::Value {
    let mut sorted = values.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

    let mut percentile_map = serde_json::Map::new();

    // Handle empty values (shouldn't happen, but be defensive)
    if sorted.is_empty() {
        for &p in &PERCENTILES {
            percentile_map.insert(format!("p{}", p as i32), json!(50.0));
        }
        return serde_json::Value::Object(percentile_map);
    }

    for &p in &PERCENTILES {
        let index = (p / 100.0 * (sorted.len() - 1) as f64).round() as usize;
        let value = sorted.get(index).copied().unwrap_or(50.0);  // Fallback to 50.0
        percentile_map.insert(format!("p{}", p as i32), json!(value));
    }

    serde_json::Value::Object(percentile_map)
}
