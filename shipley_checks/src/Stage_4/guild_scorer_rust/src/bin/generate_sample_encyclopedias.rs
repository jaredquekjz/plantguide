//! Generate Sample Encyclopedia Articles
//!
//! Generates encyclopedia articles for 3 well-known plants and saves to reports folder.
//! Run with: cargo run --features api --bin generate_sample_encyclopedias

#[cfg(feature = "api")]
use guild_scorer_rust::encyclopedia::{EncyclopediaGenerator, OrganismCounts, FungalCounts, OrganismLists, OrganismProfile, CategorizedOrganisms};
#[cfg(feature = "api")]
use guild_scorer_rust::query_engine::QueryEngine;
#[cfg(feature = "api")]
use guild_scorer_rust::explanation::unified_taxonomy::{OrganismCategory, OrganismRole};
#[cfg(feature = "api")]
use std::collections::HashMap;
#[cfg(feature = "api")]
use std::fs;
#[cfg(feature = "api")]
use std::path::Path;
#[cfg(feature = "api")]
use rustc_hash::FxHashMap;

#[cfg(feature = "api")]
const PROJECT_ROOT: &str = "/home/olier/ellenberg";
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
    let mut pathogenic = 0;

    for row in &json_data {
        let guild = row.get("guild")?.as_str()?.to_lowercase();
        let count = row.get("count")?.as_u64()? as usize;

        // Match actual source_column values from fungi_flat.parquet
        if guild.contains("amf_fungi") || guild.contains("arbuscular") {
            amf += count;
        } else if guild.contains("emf_fungi") || guild.contains("ectomycorrhiz") {
            emf += count;
        } else if guild.contains("endophytic_fungi") || guild.contains("endophyt") {
            endophytes += count;
        } else if guild.contains("mycoparasite_fungi") || guild.contains("mycoparasit") {
            mycoparasites += count;
        } else if guild.contains("entomopathogenic_fungi") || guild.contains("entomopathogen") {
            entomopathogens += count;
        } else if guild.contains("pathogenic_fungi") || guild == "pathogenic" {
            // Plant pathogenic fungi (diseases) - must check after entomopathogenic
            pathogenic += count;
        }
    }

    if amf + emf + endophytes + mycoparasites + entomopathogens + pathogenic > 0 {
        Some(FungalCounts {
            amf,
            emf,
            endophytes,
            mycoparasites,
            entomopathogens,
            pathogenic,
        })
    } else {
        None
    }
}

#[cfg(feature = "api")]
fn parse_organism_lists(
    batches: &[datafusion::arrow::array::RecordBatch],
) -> Option<OrganismLists> {
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

    let mut pollinators = Vec::new();
    let mut herbivores = Vec::new();
    let mut predators = Vec::new();

    for row in &json_data {
        let source_column = row.get("source_column")?.as_str()?.to_lowercase();
        let organism_taxon = row.get("organism_taxon")?.as_str()?.to_string();

        if organism_taxon.is_empty() {
            continue;
        }

        match source_column.as_str() {
            "pollinators" => pollinators.push(organism_taxon),
            "herbivores" => herbivores.push(organism_taxon),
            "predators" => predators.push(organism_taxon),
            _ => {}
        }
    }

    if pollinators.is_empty() && herbivores.is_empty() && predators.is_empty() {
        return None;
    }

    Some(OrganismLists {
        pollinators,
        herbivores,
        predators,
    })
}

#[cfg(feature = "api")]
fn categorize_organisms(
    lists: &OrganismLists,
    organism_categories: &FxHashMap<String, String>,
) -> OrganismProfile {
    // Helper to categorize and group organisms
    fn group_by_category(
        organisms: &[String],
        role: OrganismRole,
        organism_categories: &FxHashMap<String, String>,
    ) -> Vec<CategorizedOrganisms> {
        let mut category_map: FxHashMap<String, Vec<String>> = FxHashMap::default();

        for org in organisms {
            let category = OrganismCategory::from_name(org, organism_categories, Some(role));
            let category_name = category.display_name().to_string();
            category_map
                .entry(category_name)
                .or_default()
                .push(org.clone());
        }

        // Sort by count (descending) then category name
        let mut result: Vec<CategorizedOrganisms> = category_map
            .into_iter()
            .map(|(cat, orgs)| CategorizedOrganisms {
                category: cat,
                organisms: orgs,
            })
            .collect();

        result.sort_by(|a, b| {
            b.organisms.len().cmp(&a.organisms.len())
                .then_with(|| a.category.cmp(&b.category))
        });

        result
    }

    OrganismProfile {
        pollinators_by_category: group_by_category(&lists.pollinators, OrganismRole::Pollinator, organism_categories),
        herbivores_by_category: group_by_category(&lists.herbivores, OrganismRole::Herbivore, organism_categories),
        predators_by_category: group_by_category(&lists.predators, OrganismRole::Predator, organism_categories),
        total_pollinators: lists.pollinators.len(),
        total_herbivores: lists.herbivores.len(),
        total_predators: lists.predators.len(),
    }
}

#[cfg(feature = "api")]
fn load_organism_categories() -> FxHashMap<String, String> {
    // Try to load Kimi AI categorization map from CSV
    let csv_path = format!("{}/data/taxonomy/kimi_gardener_labels.csv", PROJECT_ROOT);
    if let Ok(content) = fs::read_to_string(&csv_path) {
        let mut map = FxHashMap::default();
        for line in content.lines().skip(1) {  // Skip header
            let parts: Vec<&str> = line.split(',').collect();
            if parts.len() >= 2 {
                let genus = parts[0].trim().to_lowercase();
                let category = parts[1].trim().to_string();
                if !genus.is_empty() && !category.is_empty() {
                    map.insert(genus, category);
                }
            }
        }
        if !map.is_empty() {
            return map;
        }
    }
    // Fallback to empty map (will use regex-based categorization)
    FxHashMap::default()
}

#[cfg(feature = "api")]
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    println!("Generating sample encyclopedia articles...\n");

    // Ensure output directory exists
    fs::create_dir_all(OUTPUT_DIR)?;

    // Initialize query engine and generator
    let engine = QueryEngine::new(PROJECT_ROOT).await?;
    let generator = EncyclopediaGenerator::new();

    // Load organism categorization map (Kimi AI)
    let organism_categories = load_organism_categories();
    println!("Loaded {} organism category mappings", organism_categories.len());

    for (wfo_id, filename, description) in SAMPLE_PLANTS {
        println!("Generating: {} ({})", filename.replace('_', " "), description);

        // Fetch plant data
        let plant_batches = engine.get_plant(wfo_id).await?;
        let plant_data = batch_to_hashmap(&plant_batches)
            .ok_or_else(|| anyhow::anyhow!("Plant {} not found", wfo_id))?;

        // Fetch organism lists (with actual names)
        let organism_lists = engine
            .get_organisms(wfo_id, None)
            .await
            .ok()
            .and_then(|b| parse_organism_lists(&b));

        // Categorize organisms
        let organism_profile = organism_lists
            .as_ref()
            .map(|lists| categorize_organisms(lists, &organism_categories));

        // Also get counts for backward compatibility
        let organism_counts = organism_lists
            .as_ref()
            .map(|lists| lists.to_counts());

        // Fetch fungal counts
        let fungal_counts = engine
            .get_fungi_summary(wfo_id)
            .await
            .ok()
            .and_then(|b| parse_fungal_counts(&b));

        // Generate encyclopedia
        let markdown = generator.generate(
            wfo_id,
            &plant_data,
            organism_counts,
            fungal_counts,
            organism_profile,
        ).map_err(|e| anyhow::anyhow!(e))?;

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
