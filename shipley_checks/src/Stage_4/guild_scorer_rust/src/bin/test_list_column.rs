use polars::prelude::*;
use anyhow::Result;

/// Test version of count_mycoparasites_for_plant (copied from pathogen_control_network_analysis.rs)
fn count_mycoparasites_for_plant_test(fungi_df: &DataFrame, target_plant_id: &str) -> Result<usize> {
    let plant_ids = fungi_df.column("plant_wfo_id")?.str()?;

    if let Ok(col) = fungi_df.column("mycoparasite_fungi") {
        println!("  Column found, dtype: {:?}", col.dtype());

        // Try list column first (Phase 0-4 format)
        if let Ok(list_col) = col.list() {
            println!("  ✓ Successfully read as list column");
            for idx in 0..fungi_df.height() {
                if let Some(plant_id) = plant_ids.get(idx) {
                    if plant_id == target_plant_id {
                        println!("  Found plant at index {}", idx);
                        if let Some(list_series) = list_col.get_as_series(idx) {
                            if let Ok(str_series) = list_series.str() {
                                let count = str_series.into_iter()
                                    .filter_map(|opt| opt.map(|s| s.trim()))
                                    .filter(|s| !s.is_empty())
                                    .count();
                                return Ok(count);
                            }
                        }
                    }
                }
            }
        } else if let Ok(str_col) = col.str() {
            println!("  Using string column (legacy format)");
            for idx in 0..fungi_df.height() {
                if let (Some(plant_id), Some(value)) = (plant_ids.get(idx), str_col.get(idx)) {
                    if plant_id == target_plant_id {
                        let count = value.split('|').filter(|s| !s.is_empty()).count();
                        return Ok(count);
                    }
                }
            }
        }
    } else {
        println!("  ✗ Column not found!");
    }

    Ok(0)
}

fn main() -> Result<()> {
    println!("Testing list column reading from fungi parquet...\n");

    let fungi_path = "shipley_checks/phase0_output/fungal_guilds_hybrid_11711.parquet";

    // Load exactly like GuildData::load_fungi() does
    let fungi_df = LazyFrame::scan_parquet(fungi_path, Default::default())?
        .collect()?;

    println!("Loaded fungi DataFrame: {} rows", fungi_df.height());
    
    println!("Fungi DataFrame schema:");
    println!("{:?}\n", fungi_df.schema());
    
    let target_plant = "wfo-0000832453"; // Fraxinus excelsior
    
    println!("Looking for plant: {}", target_plant);
    
    let plant_ids = fungi_df.column("plant_wfo_id")?.str()?;
    
    if let Ok(col) = fungi_df.column("mycoparasite_fungi") {
        println!("Column mycoparasite_fungi found");
        println!("Column dtype: {:?}", col.dtype());
        
        // Try list column
        if let Ok(list_col) = col.list() {
            println!("✓ Successfully read as list column");
            
            for idx in 0..fungi_df.height() {
                if let Some(plant_id) = plant_ids.get(idx) {
                    if plant_id == target_plant {
                        println!("\nFound plant at index {}", idx);
                        
                        if let Some(list_series) = list_col.get_as_series(idx) {
                            println!("List series dtype: {:?}", list_series.dtype());
                            
                            if let Ok(str_series) = list_series.str() {
                                println!("✓ Successfully converted to string series");
                                
                                let items: Vec<&str> = str_series.into_iter()
                                    .filter_map(|opt| opt)
                                    .filter(|s| !s.trim().is_empty())
                                    .collect();
                                
                                println!("Found {} mycoparasites:", items.len());
                                for item in &items {
                                    println!("  - {}", item);
                                }
                            } else {
                                println!("✗ Failed to convert to string series");
                            }
                        } else {
                            println!("✗ Failed to get list series");
                        }
                        break;
                    }
                }
            }
        } else if let Ok(str_col) = col.str() {
            println!("Column is string type (legacy format)");
        } else {
            println!("✗ Column is neither list nor string");
        }
    } else {
        println!("✗ Column mycoparasite_fungi not found");
    }

    // Test the actual count function
    println!("\n===============================================");
    println!("Testing count_mycoparasites_for_plant function:");
    println!("===============================================\n");

    let count = count_mycoparasites_for_plant_test(&fungi_df, target_plant)?;
    println!("\nFinal count: {}", count);

    if count == 2 {
        println!("✓ SUCCESS: Function correctly counted 2 mycoparasites");
    } else {
        println!("✗ FAIL: Expected 2 mycoparasites, got {}", count);
    }

    Ok(())
}
