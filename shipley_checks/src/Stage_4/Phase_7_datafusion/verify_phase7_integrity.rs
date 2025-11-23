#!/usr/bin/env rust-script
//! Verify Phase 7 SQL-optimized parquet files maintain data integrity
//!
//! This script uses DuckDB to verify that Phase 7 transformations:
//! 1. Preserve all source data (no data loss)
//! 2. Correctly transform columns (e.g., CSR normalization)
//! 3. Properly flatten arrays (correct interaction counts)
//! 4. Maintain referential integrity (all plant_wfo_ids exist)
//!
//! ```cargo
//! [dependencies]
//! duckdb = "1.1"
//! anyhow = "1.0"
//! ```

use duckdb::{Connection, Result as DuckResult};

const PROJECT_ROOT: &str = "/home/olier/ellenberg";

#[derive(Debug)]
struct VerificationResult {
    test_name: String,
    passed: bool,
    message: String,
}

impl VerificationResult {
    fn pass(test_name: &str, message: String) -> Self {
        Self {
            test_name: test_name.to_string(),
            passed: true,
            message,
        }
    }

    fn fail(test_name: &str, message: String) -> Self {
        Self {
            test_name: test_name.to_string(),
            passed: false,
            message,
        }
    }
}

fn main() -> anyhow::Result<()> {
    println!("================================================================================");
    println!("PHASE 7: DATA INTEGRITY VERIFICATION");
    println!("================================================================================\n");

    let conn = Connection::open_in_memory()?;

    let mut results = Vec::new();

    // Register all source files
    println!("Loading source files...");
    register_source_files(&conn)?;

    // Register all Phase 7 output files
    println!("Loading Phase 7 output files...");
    register_phase7_files(&conn)?;

    println!("\n================================================================================");
    println!("RUNNING VERIFICATION TESTS");
    println!("================================================================================\n");

    // Test 1: Plants - Row Count Verification
    results.push(verify_plants_row_count(&conn)?);

    // Test 2: Plants - All Source IDs Present
    results.push(verify_plants_ids_preserved(&conn)?);

    // Test 3: Plants - CSR Normalization Correct
    results.push(verify_csr_normalization(&conn)?);

    // Test 4: Plants - EIVE Column Renaming
    results.push(verify_eive_columns(&conn)?);

    // Test 5: Organisms - Interaction Count Matches Array Lengths
    results.push(verify_organisms_flattening(&conn)?);

    // Test 6: Organisms - Referential Integrity
    results.push(verify_organisms_referential_integrity(&conn)?);

    // Test 7: Fungi - Guild Count Matches Array Lengths
    results.push(verify_fungi_flattening(&conn)?);

    // Test 8: Fungi - Referential Integrity
    results.push(verify_fungi_referential_integrity(&conn)?);

    // Test 9: Plants - Computed Columns Correct
    results.push(verify_computed_columns(&conn)?);

    // Print results
    println!("\n================================================================================");
    println!("VERIFICATION SUMMARY");
    println!("================================================================================\n");

    let passed = results.iter().filter(|r| r.passed).count();
    let failed = results.iter().filter(|r| !r.passed).count();

    for result in &results {
        let status = if result.passed { "✓ PASS" } else { "✗ FAIL" };
        println!("{}: {}", status, result.test_name);
        println!("  → {}\n", result.message);
    }

    println!("Total: {} passed, {} failed", passed, failed);

    if failed > 0 {
        println!("\n❌ VERIFICATION FAILED");
        std::process::exit(1);
    } else {
        println!("\n✅ ALL TESTS PASSED - Data integrity verified");
    }

    Ok(())
}

fn register_source_files(conn: &Connection) -> anyhow::Result<()> {
    // Source: Phase 4 output (plants with all data)
    let phase4_path = format!("{}/shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet", PROJECT_ROOT);
    conn.execute(
        &format!("CREATE VIEW source_plants AS SELECT * FROM read_parquet('{}')", phase4_path),
        [],
    )?;

    // Source: Phase 0 organism profiles
    let organisms_path = format!("{}/shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet", PROJECT_ROOT);
    conn.execute(
        &format!("CREATE VIEW source_organisms AS SELECT * FROM read_parquet('{}')", organisms_path),
        [],
    )?;

    // Source: Phase 0 fungal guilds
    let fungi_path = format!("{}/shipley_checks/stage4/phase0_output/fungal_guilds_hybrid_11711.parquet", PROJECT_ROOT);
    conn.execute(
        &format!("CREATE VIEW source_fungi AS SELECT * FROM read_parquet('{}')", fungi_path),
        [],
    )?;

    Ok(())
}

fn register_phase7_files(conn: &Connection) -> anyhow::Result<()> {
    let phase7_dir = format!("{}/shipley_checks/stage4/phase7_output", PROJECT_ROOT);

    // Phase 7 plants
    let plants_path = format!("{}/plants_searchable_11711.parquet", phase7_dir);
    conn.execute(
        &format!("CREATE VIEW phase7_plants AS SELECT * FROM read_parquet('{}')", plants_path),
        [],
    )?;

    // Phase 7 organisms
    let organisms_path = format!("{}/organisms_searchable.parquet", phase7_dir);
    conn.execute(
        &format!("CREATE VIEW phase7_organisms AS SELECT * FROM read_parquet('{}')", organisms_path),
        [],
    )?;

    // Phase 7 fungi
    let fungi_path = format!("{}/fungi_searchable.parquet", phase7_dir);
    conn.execute(
        &format!("CREATE VIEW phase7_fungi AS SELECT * FROM read_parquet('{}')", fungi_path),
        [],
    )?;

    Ok(())
}

fn verify_plants_row_count(conn: &Connection) -> DuckResult<VerificationResult> {
    let source_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM source_plants",
        [],
        |row| row.get(0),
    )?;

    let phase7_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM phase7_plants",
        [],
        |row| row.get(0),
    )?;

    if source_count == phase7_count {
        Ok(VerificationResult::pass(
            "Plants Row Count",
            format!("Both datasets have {} rows", source_count),
        ))
    } else {
        Ok(VerificationResult::fail(
            "Plants Row Count",
            format!("Source has {} rows, Phase 7 has {} rows", source_count, phase7_count),
        ))
    }
}

fn verify_plants_ids_preserved(conn: &Connection) -> DuckResult<VerificationResult> {
    let missing_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM source_plants s
         WHERE NOT EXISTS (
            SELECT 1 FROM phase7_plants p WHERE p.wfo_taxon_id = s.wfo_taxon_id
         )",
        [],
        |row| row.get(0),
    )?;

    if missing_count == 0 {
        Ok(VerificationResult::pass(
            "Plants IDs Preserved",
            "All source plant IDs present in Phase 7".to_string(),
        ))
    } else {
        Ok(VerificationResult::fail(
            "Plants IDs Preserved",
            format!("{} plant IDs missing from Phase 7", missing_count),
        ))
    }
}

fn verify_csr_normalization(conn: &Connection) -> DuckResult<VerificationResult> {
    let mismatch_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM source_plants s
         JOIN phase7_plants p ON s.wfo_taxon_id = p.wfo_taxon_id
         WHERE ABS(s.C / 100.0 - p.C_norm) > 0.0001
            OR ABS(s.S / 100.0 - p.S_norm) > 0.0001
            OR ABS(s.R / 100.0 - p.R_norm) > 0.0001",
        [],
        |row| row.get(0),
    )?;

    if mismatch_count == 0 {
        Ok(VerificationResult::pass(
            "CSR Normalization",
            "All CSR scores correctly normalized to 0-1 scale".to_string(),
        ))
    } else {
        Ok(VerificationResult::fail(
            "CSR Normalization",
            format!("{} plants have incorrect CSR normalization", mismatch_count),
        ))
    }
}

fn verify_eive_columns(conn: &Connection) -> DuckResult<VerificationResult> {
    // Check if EIVE columns were correctly renamed and converted
    let mismatch_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM source_plants s
         JOIN phase7_plants p ON s.wfo_taxon_id = p.wfo_taxon_id
         WHERE CAST(s.\"EIVEres-L\" AS DOUBLE) != p.EIVE_L
            OR CAST(s.\"EIVEres-M\" AS DOUBLE) != p.EIVE_M
            OR CAST(s.\"EIVEres-T\" AS DOUBLE) != p.EIVE_T
            OR CAST(s.\"EIVEres-N\" AS DOUBLE) != p.EIVE_N
            OR CAST(s.\"EIVEres-R\" AS DOUBLE) != p.EIVE_R",
        [],
        |row| row.get(0),
    )?;

    if mismatch_count == 0 {
        Ok(VerificationResult::pass(
            "EIVE Column Renaming",
            "All EIVE columns correctly renamed and converted".to_string(),
        ))
    } else {
        Ok(VerificationResult::fail(
            "EIVE Column Renaming",
            format!("{} plants have incorrect EIVE values", mismatch_count),
        ))
    }
}

fn verify_organisms_flattening(conn: &Connection) -> DuckResult<VerificationResult> {
    // Count total interactions by summing array lengths in source
    let source_count: i64 = conn.query_row(
        "SELECT
            COALESCE(SUM(len(pollinators)), 0) +
            COALESCE(SUM(len(herbivores)), 0) +
            COALESCE(SUM(len(pathogens)), 0) +
            COALESCE(SUM(len(flower_visitors)), 0) +
            COALESCE(SUM(len(predators_hasHost)), 0) +
            COALESCE(SUM(len(predators_interactsWith)), 0) +
            COALESCE(SUM(len(predators_adjacentTo)), 0) +
            COALESCE(SUM(len(fungivores_eats)), 0)
         FROM source_organisms",
        [],
        |row| row.get(0),
    )?;

    let phase7_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM phase7_organisms",
        [],
        |row| row.get(0),
    )?;

    if source_count == phase7_count {
        Ok(VerificationResult::pass(
            "Organisms Flattening",
            format!("Correctly flattened {} interactions from arrays", phase7_count),
        ))
    } else {
        Ok(VerificationResult::fail(
            "Organisms Flattening",
            format!("Source arrays have {} items, Phase 7 has {} rows", source_count, phase7_count),
        ))
    }
}

fn verify_organisms_referential_integrity(conn: &Connection) -> DuckResult<VerificationResult> {
    let orphan_count: i64 = conn.query_row(
        "SELECT COUNT(DISTINCT o.plant_wfo_id) FROM phase7_organisms o
         WHERE NOT EXISTS (
            SELECT 1 FROM phase7_plants p WHERE p.wfo_taxon_id = o.plant_wfo_id
         )",
        [],
        |row| row.get(0),
    )?;

    if orphan_count == 0 {
        Ok(VerificationResult::pass(
            "Organisms Referential Integrity",
            "All organism plant_wfo_ids exist in plants table".to_string(),
        ))
    } else {
        Ok(VerificationResult::fail(
            "Organisms Referential Integrity",
            format!("{} plant IDs in organisms don't exist in plants", orphan_count),
        ))
    }
}

fn verify_fungi_flattening(conn: &Connection) -> DuckResult<VerificationResult> {
    let source_count: i64 = conn.query_row(
        "SELECT
            COALESCE(SUM(len(pathogenic_fungi)), 0) +
            COALESCE(SUM(len(pathogenic_fungi_host_specific)), 0) +
            COALESCE(SUM(len(amf_fungi)), 0) +
            COALESCE(SUM(len(emf_fungi)), 0) +
            COALESCE(SUM(len(mycoparasite_fungi)), 0) +
            COALESCE(SUM(len(entomopathogenic_fungi)), 0) +
            COALESCE(SUM(len(endophytic_fungi)), 0) +
            COALESCE(SUM(len(saprotrophic_fungi)), 0)
         FROM source_fungi",
        [],
        |row| row.get(0),
    )?;

    let phase7_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM phase7_fungi",
        [],
        |row| row.get(0),
    )?;

    if source_count == phase7_count {
        Ok(VerificationResult::pass(
            "Fungi Flattening",
            format!("Correctly flattened {} interactions from arrays", phase7_count),
        ))
    } else {
        Ok(VerificationResult::fail(
            "Fungi Flattening",
            format!("Source arrays have {} items, Phase 7 has {} rows", source_count, phase7_count),
        ))
    }
}

fn verify_fungi_referential_integrity(conn: &Connection) -> DuckResult<VerificationResult> {
    let orphan_count: i64 = conn.query_row(
        "SELECT COUNT(DISTINCT f.plant_wfo_id) FROM phase7_fungi f
         WHERE NOT EXISTS (
            SELECT 1 FROM phase7_plants p WHERE p.wfo_taxon_id = f.plant_wfo_id
         )",
        [],
        |row| row.get(0),
    )?;

    if orphan_count == 0 {
        Ok(VerificationResult::pass(
            "Fungi Referential Integrity",
            "All fungi plant_wfo_ids exist in plants table".to_string(),
        ))
    } else {
        Ok(VerificationResult::fail(
            "Fungi Referential Integrity",
            format!("{} plant IDs in fungi don't exist in plants", orphan_count),
        ))
    }
}

fn verify_computed_columns(conn: &Connection) -> DuckResult<VerificationResult> {
    // Verify maintenance_level logic
    let incorrect_maintenance: i64 = conn.query_row(
        "SELECT COUNT(*) FROM phase7_plants
         WHERE (S > 50 AND maintenance_level != 'low')
            OR (C > 50 AND S <= 50 AND maintenance_level != 'high')
            OR (S <= 50 AND C <= 50 AND maintenance_level != 'medium')",
        [],
        |row| row.get(0),
    )?;

    // Verify boolean flags
    let incorrect_flags: i64 = conn.query_row(
        "SELECT COUNT(*) FROM phase7_plants
         WHERE (S > 60 AND NOT drought_tolerant)
            OR (S <= 60 AND drought_tolerant)
            OR (R > 60 AND NOT fast_growing)
            OR (R <= 60 AND fast_growing)",
        [],
        |row| row.get(0),
    )?;

    let total_errors = incorrect_maintenance + incorrect_flags;

    if total_errors == 0 {
        Ok(VerificationResult::pass(
            "Computed Columns",
            "All computed columns (maintenance_level, flags) correct".to_string(),
        ))
    } else {
        Ok(VerificationResult::fail(
            "Computed Columns",
            format!("{} plants have incorrect computed values", total_errors),
        ))
    }
}
