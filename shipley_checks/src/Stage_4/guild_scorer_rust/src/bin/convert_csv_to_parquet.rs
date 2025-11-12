//! Convert CSV files to Parquet format (Rust version)
//!
//! This binary converts all CSV files used by the Rust guild scorer to Parquet format
//! using Polars to ensure compatibility with Rust's data loading.
//!
//! Usage:
//!   cargo run --bin convert_csv_to_parquet

use polars::prelude::*;
use std::time::Instant;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("\n{}", "=".repeat(70));
    println!("CSV to Parquet Conversion (Rust)");
    println!("{}", "=".repeat(70));
    println!();

    // Define file paths
    let files = vec![
        (
            "Plants Dataset",
            "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.csv",
            "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711_rust.parquet",
        ),
        (
            "Organism Profiles",
            "shipley_checks/validation/organism_profiles_pure_r.csv",
            "shipley_checks/validation/organism_profiles_pure_rust.parquet",
        ),
        (
            "Fungal Guilds",
            "shipley_checks/validation/fungal_guilds_pure_r.csv",
            "shipley_checks/validation/fungal_guilds_pure_rust.parquet",
        ),
        (
            "Herbivore Predators",
            "shipley_checks/validation/herbivore_predators_pure_r.csv",
            "shipley_checks/validation/herbivore_predators_pure_rust.parquet",
        ),
        (
            "Insect Fungal Parasites",
            "shipley_checks/validation/insect_fungal_parasites_pure_r.csv",
            "shipley_checks/validation/insect_fungal_parasites_pure_rust.parquet",
        ),
        (
            "Pathogen Antagonists",
            "shipley_checks/validation/pathogen_antagonists_pure_r.csv",
            "shipley_checks/validation/pathogen_antagonists_pure_rust.parquet",
        ),
    ];

    let total_start = Instant::now();

    for (name, csv_path, parquet_path) in files {
        println!("Converting: {}", name);
        println!("  CSV:     {}", csv_path);
        println!("  Parquet: {}", parquet_path);

        // Check if CSV exists
        if !std::path::Path::new(csv_path).exists() {
            println!("  ERROR: CSV file not found\n");
            continue;
        }

        // Load CSV with NA handling
        let load_start = Instant::now();
        let parse_options = CsvParseOptions::default()
            .with_null_values(Some(NullValues::AllColumnsSingle("NA".into())));

        let df = CsvReadOptions::default()
            .with_has_header(true)
            .with_infer_schema_length(None) // Scan entire file
            .with_parse_options(parse_options)
            .try_into_reader_with_file_path(Some(csv_path.into()))?
            .finish()?;

        let load_time = load_start.elapsed();

        println!(
            "  Loaded:  {} rows × {} columns ({:.3} ms)",
            df.height(),
            df.width(),
            load_time.as_secs_f64() * 1000.0
        );

        // Write Parquet with ZSTD compression
        let write_start = Instant::now();
        let file = std::fs::File::create(parquet_path)?;
        ParquetWriter::new(file)
            .with_compression(ParquetCompression::Zstd(None))
            .finish(&mut df.clone())?;
        let write_time = write_start.elapsed();

        // Get file sizes
        let csv_size = std::fs::metadata(csv_path)?.len() as f64 / (1024.0 * 1024.0);
        let parquet_size = std::fs::metadata(parquet_path)?.len() as f64 / (1024.0 * 1024.0);
        let compression_ratio = csv_size / parquet_size;

        println!(
            "  Written: {:.2} MB ({:.3} ms)",
            parquet_size,
            write_time.as_secs_f64() * 1000.0
        );
        println!("  CSV size: {:.2} MB", csv_size);
        println!("  Compression: {:.1}x\n", compression_ratio);
    }

    let total_time = total_start.elapsed();

    println!("{}", "=".repeat(70));
    println!("Total time: {:.3} ms", total_time.as_secs_f64() * 1000.0);
    println!("{}", "=".repeat(70));
    println!("\nParquet files ready for Rust pipeline.\n");

    Ok(())
}
