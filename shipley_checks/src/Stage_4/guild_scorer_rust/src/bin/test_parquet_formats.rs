use polars::prelude::*;

fn main() {
    println!("=================================================================");
    println!("Testing DuckDB Parquet Compatibility with Polars");
    println!("=================================================================\n");

    println!("1. OLD organism_profiles_pure_r.parquet (Nov 12 - before fungivores):");
    test_parquet("shipley_checks/validation/organism_profiles_pure_r.parquet");

    println!("\n2. NEW organism_profiles_11711.parquet (DuckDB COPY TO):");
    test_parquet("shipley_checks/validation/organism_profiles_11711.parquet");

    println!("\n3. CONVERTED organism_profiles_pure_rust.parquet (PyArrow):");
    test_parquet("shipley_checks/validation/organism_profiles_pure_rust.parquet");
}

fn test_parquet(path: &str) {
    match LazyFrame::scan_parquet(path, Default::default()) {
        Ok(lf) => {
            match lf.select(&[col("plant_wfo_id"), col("fungivores_eats_count")]).collect() {
                Ok(df) => {
                    println!("  ✓ SUCCESS");
                    println!("    Rows: {}", df.height());
                    println!("    Cols: {}", df.width());
                    if df.height() > 0 {
                        println!("    Sample: {:?}", df.head(Some(2)));
                    }
                }
                Err(e) => println!("  ✗ FAILED to collect: {}", e),
            }
        }
        Err(e) => println!("  ✗ FAILED to scan: {}", e),
    }
}
