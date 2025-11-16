/// Targeted test for M4 MECHANISM 3: Fungivorous animal biocontrol
///
/// Tests pairwise logic:
/// - Plant A has pathogen "Fusarium_oxysporum"
/// - Plant B has fungivore "Folsomia_candida" (springtail)
/// - pathogen_antagonists lookup: Fusarium_oxysporum → [Folsomia_candida]
/// - Expected: M4 should detect match and score +1.0

use polars::prelude::*;
use rustc_hash::FxHashMap;
use std::fs;

fn main() {
    println!("=================================================================");
    println!("M4 MECHANISM 3: Fungivore Biocontrol Logic Test");
    println!("=================================================================\n");

    // Create test scenario
    println!("Test Scenario:");
    println!("  Plant A (wfo-test-001): pathogen = Fusarium_oxysporum");
    println!("  Plant B (wfo-test-002): fungivore = Folsomia_candida");
    println!("  Lookup: Fusarium_oxysporum → [Folsomia_candida]");
    println!("  Expected: Match detected, score +1.0\n");

    // Create temporary test parquets
    create_test_fungi_parquet();
    create_test_organisms_parquet();
    create_test_antagonists_lookup();

    println!("Test files created. Running M4 calculation...\n");

    // Load test data
    let fungi_lazy = LazyFrame::scan_parquet(
        "/tmp/test_fungi.parquet",
        Default::default()
    ).unwrap();

    let organisms_lazy = LazyFrame::scan_parquet(
        "/tmp/test_organisms.parquet",
        Default::default()
    ).unwrap();

    let pathogen_antagonists = load_test_antagonists();

    // Mock calibration (minimal tier structure for testing)
    let calibration_json = r#"{
        "tier_test": {
            "p2": {
                "p01": 0.0, "p05": 0.1, "p10": 0.2, "p20": 0.3, "p30": 0.4,
                "p40": 0.5, "p50": 0.6, "p60": 0.7, "p70": 0.8, "p80": 0.9,
                "p90": 1.0, "p95": 1.1, "p99": 1.2
            }
        }
    }"#;
    let mut calibration: guild_scorer_rust::utils::Calibration =
        serde_json::from_str(calibration_json).unwrap();
    calibration.active_tier = "tier_test".to_string();

    // Run M4 calculation
    let plant_ids = vec!["wfo-test-001".to_string(), "wfo-test-002".to_string()];

    let result = guild_scorer_rust::metrics::m4_disease_control::calculate_m4(
        &plant_ids,
        &organisms_lazy,
        &fungi_lazy,
        &pathogen_antagonists,
        &calibration,
    );

    match result {
        Ok(m4) => {
            println!("=================================================================");
            println!("M4 RESULTS:");
            println!("=================================================================");
            println!("Raw score: {:.4}", m4.raw);
            println!("Normalized score: {:.2}", m4.norm);
            println!("Pathogen control (raw): {:.4}", m4.pathogen_control_raw);
            println!("Mechanisms detected: {}", m4.n_mechanisms);
            println!("Specific fungivore matches: {}", m4.specific_fungivore_matches);
            println!("Matched fungivore pairs: {:?}", m4.matched_fungivore_pairs);
            println!("\nFungivore counts: {:?}", m4.fungivore_counts);
            println!("Pathogen counts: {:?}", m4.pathogen_counts);

            println!("\n=================================================================");
            println!("VALIDATION:");
            println!("=================================================================");

            if m4.specific_fungivore_matches > 0 {
                println!("✓ PASS: Fungivore match detected (expected >= 1)");
            } else {
                println!("✗ FAIL: No fungivore matches (expected >= 1)");
            }

            if m4.matched_fungivore_pairs.contains(&(
                "Fusarium_oxysporum".to_string(),
                "Folsomia_candida".to_string()
            )) {
                println!("✓ PASS: Correct pair matched (Fusarium_oxysporum, Folsomia_candida)");
            } else {
                println!("✗ FAIL: Expected pair not found");
            }

            if m4.pathogen_control_raw >= 1.0 {
                println!("✓ PASS: Score increased (raw >= 1.0)");
            } else {
                println!("✗ FAIL: Score not increased (raw = {:.4})", m4.pathogen_control_raw);
            }
        }
        Err(e) => {
            println!("✗ ERROR: M4 calculation failed: {}", e);
        }
    }

    // Cleanup
    let _ = fs::remove_file("/tmp/test_fungi.parquet");
    let _ = fs::remove_file("/tmp/test_organisms.parquet");
}

fn create_test_fungi_parquet() {
    let plant_ids = vec!["wfo-test-001", "wfo-test-002"];
    let pathogens = vec!["Fusarium_oxysporum", ""]; // Plant A has pathogen, Plant B doesn't
    let mycoparasites = vec!["", ""]; // No mycoparasites for simplicity

    let df = df! {
        "plant_wfo_id" => plant_ids,
        "pathogenic_fungi" => pathogens,
        "mycoparasite_fungi" => mycoparasites,
    }.unwrap();

    let mut file = std::fs::File::create("/tmp/test_fungi.parquet").unwrap();
    ParquetWriter::new(&mut file).finish(&mut df.clone()).unwrap();
}

fn create_test_organisms_parquet() {
    let plant_ids = vec!["wfo-test-001", "wfo-test-002"];
    let fungivores = vec!["", "Folsomia_candida"]; // Plant B has fungivore, Plant A doesn't

    let df = df! {
        "plant_wfo_id" => plant_ids,
        "fungivores_eats" => fungivores,
    }.unwrap();

    let mut file = std::fs::File::create("/tmp/test_organisms.parquet").unwrap();
    ParquetWriter::new(&mut file).finish(&mut df.clone()).unwrap();
}

fn create_test_antagonists_lookup() {
    // Just for reference - actual loading happens in load_test_antagonists
}

fn load_test_antagonists() -> FxHashMap<String, Vec<String>> {
    let mut map = FxHashMap::default();
    map.insert(
        "Fusarium_oxysporum".to_string(),
        vec!["Folsomia_candida".to_string()],
    );
    map
}
