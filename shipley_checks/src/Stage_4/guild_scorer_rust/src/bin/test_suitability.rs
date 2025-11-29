//! Test Suitability Engine
//!
//! Tests the local suitability engine by generating suitability assessments
//! for 3 sample plants across 3 test locations (Singapore, London, Helsinki).
//!
//! Run with: cargo run --features api --bin test_suitability

#[cfg(feature = "api")]
use guild_scorer_rust::encyclopedia::suitability::{
    local_conditions::{singapore, london, helsinki, test_locations, LocalConditions},
    advice::{generate_suitability_section, build_assessment},
};
#[cfg(feature = "api")]
use guild_scorer_rust::query_engine::QueryEngine;
#[cfg(feature = "api")]
use std::collections::HashMap;
#[cfg(feature = "api")]
use std::fs;

#[cfg(feature = "api")]
const PROJECT_ROOT: &str = "/home/olier/ellenberg";
#[cfg(feature = "api")]
const OUTPUT_DIR: &str = "/home/olier/ellenberg/shipley_checks/stage4/reports/suitability";

/// Sample plants for testing
#[cfg(feature = "api")]
const SAMPLE_PLANTS: &[(&str, &str)] = &[
    ("wfo-0000292858", "Quercus robur"),       // English Oak - temperate tree
    ("wfo-0001005999", "Rosa canina"),         // Dog Rose - temperate shrub
    ("wfo-0000213062", "Trifolium repens"),    // White Clover - temperate herb
];

#[cfg(feature = "api")]
fn batch_to_hashmap(
    batches: &[datafusion::arrow::array::RecordBatch],
) -> Option<HashMap<String, serde_json::Value>> {
    if batches.is_empty() || batches[0].num_rows() == 0 {
        return None;
    }

    let mut buf = Vec::new();
    {
        let mut writer = datafusion::arrow::json::ArrayWriter::new(&mut buf);
        for batch in batches {
            writer.write(batch).ok()?;
        }
        writer.finish().ok()?;
    }

    let json_data: Vec<serde_json::Value> = serde_json::from_slice(&buf).ok()?;
    json_data
        .into_iter()
        .next()
        .and_then(|v| serde_json::from_value(v).ok())
}

#[cfg(feature = "api")]
async fn test_plant_at_location(
    engine: &QueryEngine,
    plant_id: &str,
    plant_name: &str,
    location: &LocalConditions,
) -> Option<String> {
    // Fetch plant data
    let plant_batches = engine.get_plant(plant_id).await.ok()?;
    let plant_data = batch_to_hashmap(&plant_batches)?;

    // Generate suitability section
    let section = generate_suitability_section(location, &plant_data, plant_name);
    Some(section)
}

#[cfg(feature = "api")]
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    println!("Testing Local Suitability Engine\n");
    println!("=================================\n");

    // Ensure output directory exists
    fs::create_dir_all(OUTPUT_DIR)?;

    // Initialize query engine
    let engine = QueryEngine::new(PROJECT_ROOT).await?;

    // Get test locations
    let locations = test_locations();

    for (plant_id, plant_name) in SAMPLE_PLANTS {
        println!("\n## {} ({})\n", plant_name, plant_id);

        // Fetch plant data once
        let plant_batches = engine.get_plant(plant_id).await?;
        let plant_data = batch_to_hashmap(&plant_batches)
            .ok_or_else(|| anyhow::anyhow!("Plant {} not found", plant_id))?;

        // Print plant's climate tiers
        println!("Plant climate tiers:");
        for tier in &[
            "tier_1_tropical", "tier_2_mediterranean", "tier_3_humid_temperate",
            "tier_4_continental", "tier_5_boreal_polar", "tier_6_arid"
        ] {
            if let Some(val) = plant_data.get(*tier) {
                if val.as_bool().unwrap_or(false) {
                    println!("  - {}", tier);
                }
            }
        }
        println!();

        // Test each location
        let mut combined_output = format!("# {} Suitability Assessment\n\n", plant_name);
        combined_output.push_str(&format!("WFO ID: {}\n\n", plant_id));

        for location in &locations {
            println!("  Testing: {}", location.name);

            // Build assessment
            let assessment = build_assessment(location, &plant_data, plant_name);

            // Print summary
            println!("    Climate: {:?} → {:?}",
                location.climate_tier(),
                assessment.climate_zone.occurrence_fit);
            println!("    Temperature: {:?}", assessment.temperature.rating);
            println!("    Moisture: {:?}", assessment.moisture.rating);
            println!("    Soil: {:?}", assessment.soil.rating);
            println!("    Overall: {:?}\n", assessment.overall_rating);

            // Generate full section
            let section = generate_suitability_section(location, &plant_data, plant_name);
            combined_output.push_str(&section);
            combined_output.push_str("\n\n---\n\n");
        }

        // Save to file
        let filename = plant_name.to_lowercase().replace(' ', "_");
        let output_path = format!("{}/suitability_{}.md", OUTPUT_DIR, filename);
        fs::write(&output_path, &combined_output)?;
        println!("  Saved: {}", output_path);
    }

    println!("\n=================================");
    println!("Done! Tested {} plants × {} locations = {} assessments",
        SAMPLE_PLANTS.len(), locations.len(), SAMPLE_PLANTS.len() * locations.len());

    Ok(())
}

#[cfg(not(feature = "api"))]
fn main() {
    eprintln!("This binary requires the 'api' feature. Run with: cargo run --features api --bin test_suitability");
}
