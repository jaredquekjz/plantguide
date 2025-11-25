//! Generate Sample Encyclopedia Articles
//!
//! Generates encyclopedia articles for 3 well-known plants and saves to reports folder.
//! Run with: cargo run --features api --bin generate_sample_encyclopedias

#[cfg(feature = "api")]
use guild_scorer_rust::encyclopedia::EncyclopediaGenerator;
#[cfg(feature = "api")]
use guild_scorer_rust::encyclopedia::sections::s5_biological_interactions::{
    FungalCounts, OrganismCounts,
};
#[cfg(feature = "api")]
use guild_scorer_rust::query_engine::QueryEngine;
#[cfg(feature = "api")]
use std::collections::HashMap;
#[cfg(feature = "api")]
use std::fs;
#[cfg(feature = "api")]
use std::path::Path;

#[cfg(feature = "api")]
const DATA_DIR: &str = "/home/olier/ellenberg/shipley_checks/stage4/phase7_output";
#[cfg(feature = "api")]
const OUTPUT_DIR: &str = "/home/olier/ellenberg/shipley_checks/stage4/reports/encyclopedia";

#[cfg(feature = "api")]
const SAMPLE_PLANTS: &[(&str, &str, &str)] = &[
    ("wfo-0000292858", "Quercus_robur", "English Oak - large deciduous tree"),
    ("wfo-0001005999", "Rosa_canina", "Dog Rose - shrub with many pollinators"),
    ("wfo-0000213062", "Trifolium_repens", "White Clover - nitrogen-fixing legume"),
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
fn parse_organism_counts(
    batches: &[datafusion::arrow::array::RecordBatch],
) -> Option<OrganismCounts> {
    if batches.is_empty() {
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

    let mut pollinators = 0;
    let mut visitors = 0;
    let mut herbivores = 0;
    let mut pathogens = 0;
    let mut predators = 0;

    for row in &json_data {
        let interaction_type = row.get("interaction_type")?.as_str()?;
        let count = row.get("count")?.as_u64()? as usize;

        match interaction_type.to_lowercase().as_str() {
            "pollinator" | "pollinators" => pollinators += count,
            "visitor" | "visitors" | "flower_visitor" => visitors += count,
            "herbivore" | "herbivores" => herbivores += count,
            "pathogen" | "pathogens" | "pathogenic" => pathogens += count,
            "predator" | "predators" | "natural_enemy" => predators += count,
            _ => {}
        }
    }

    if pollinators + visitors + herbivores + pathogens + predators > 0 {
        Some(OrganismCounts {
            pollinators,
            visitors,
            herbivores,
            pathogens,
            predators,
        })
    } else {
        None
    }
}

#[cfg(feature = "api")]
fn parse_fungal_counts(
    batches: &[datafusion::arrow::array::RecordBatch],
) -> Option<FungalCounts> {
    if batches.is_empty() {
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

    let mut amf = 0;
    let mut emf = 0;
    let mut endophytes = 0;
    let mut mycoparasites = 0;
    let mut entomopathogens = 0;

    for row in &json_data {
        let guild = row.get("guild")?.as_str()?.to_lowercase();
        let count = row.get("count")?.as_u64()? as usize;

        if guild.contains("arbuscular") || guild.contains("amf") {
            amf += count;
        } else if guild.contains("ectomycorrhiz") || guild.contains("emf") {
            emf += count;
        } else if guild.contains("endophyt") {
            endophytes += count;
        } else if guild.contains("mycoparasit") || guild.contains("hyperparasit") {
            mycoparasites += count;
        } else if guild.contains("entomopathogen") || guild.contains("insect_pathogen") {
            entomopathogens += count;
        }
    }

    if amf + emf + endophytes + mycoparasites + entomopathogens > 0 {
        Some(FungalCounts {
            amf,
            emf,
            endophytes,
            mycoparasites,
            entomopathogens,
        })
    } else {
        None
    }
}

#[cfg(feature = "api")]
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    println!("Generating sample encyclopedia articles...\n");

    // Ensure output directory exists
    fs::create_dir_all(OUTPUT_DIR)?;

    // Initialize query engine and generator
    let engine = QueryEngine::new(DATA_DIR).await?;
    let generator = EncyclopediaGenerator::new();

    for (wfo_id, filename, description) in SAMPLE_PLANTS {
        println!("Generating: {} ({})", filename.replace('_', " "), description);

        // Fetch plant data
        let plant_batches = engine.get_plant(wfo_id).await?;
        let plant_data = batch_to_hashmap(&plant_batches)
            .ok_or_else(|| anyhow::anyhow!("Plant {} not found", wfo_id))?;

        // Fetch organism counts
        let organism_counts = engine
            .get_organism_summary(wfo_id)
            .await
            .ok()
            .and_then(|b| parse_organism_counts(&b));

        // Fetch fungal counts
        let fungal_counts = engine
            .get_fungi_summary(wfo_id)
            .await
            .ok()
            .and_then(|b| parse_fungal_counts(&b));

        // Generate encyclopedia
        let markdown = generator.generate(wfo_id, &plant_data, organism_counts, fungal_counts)
            .map_err(|e| anyhow::anyhow!(e))?;

        // Save to file
        let output_path = Path::new(OUTPUT_DIR).join(format!("encyclopedia_{}.md", filename));
        fs::write(&output_path, &markdown)?;
        println!("  Saved: {}", output_path.display());
    }

    println!("\nDone! Generated {} encyclopedia articles.", SAMPLE_PLANTS.len());
    Ok(())
}

#[cfg(not(feature = "api"))]
fn main() {
    eprintln!("This binary requires the 'api' feature. Run with: cargo run --features api --bin generate_sample_encyclopedias");
}
