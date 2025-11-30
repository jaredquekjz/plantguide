//! Generate Sample Encyclopedia Articles
//!
//! Generates encyclopedia articles for 3 well-known plants and saves to reports folder.
//! Run with: cargo run --features api --bin generate_sample_encyclopedias

#[cfg(feature = "api")]
use guild_scorer_rust::encyclopedia::{EncyclopediaGenerator, OrganismCounts, FungalCounts, OrganismLists, OrganismProfile, CategorizedOrganisms, RankedPathogen, BeneficialFungi, RelatedSpecies};
#[cfg(feature = "api")]
use guild_scorer_rust::encyclopedia::suitability::local_conditions::{LocalConditions, london, singapore, helsinki, test_locations};
#[cfg(feature = "api")]
use guild_scorer_rust::query_engine::QueryEngine;
#[cfg(feature = "api")]
use guild_scorer_rust::explanation::unified_taxonomy::{OrganismCategory, OrganismRole};
#[cfg(feature = "api")]
use guild_scorer_rust::compact_tree::CompactTree;
#[cfg(feature = "api")]
use std::collections::HashMap;
#[cfg(feature = "api")]
use std::collections::HashSet;
#[cfg(feature = "api")]
use std::fs;
#[cfg(feature = "api")]
use std::path::Path;
#[cfg(feature = "api")]
use rustc_hash::FxHashMap;
#[cfg(feature = "api")]
use datafusion::arrow::array::{StringArray, LargeStringArray, StringViewArray, Array};

#[cfg(feature = "api")]
const PROJECT_ROOT: &str = "/home/olier/ellenberg";
#[cfg(feature = "api")]
const OUTPUT_DIR: &str = "/home/olier/ellenberg/shipley_checks/stage4/reports/encyclopedia";
#[cfg(feature = "api")]
const OUTPUT_DIR_SUITABILITY: &str = "/home/olier/ellenberg/shipley_checks/stage4/reports/encyclopedia_suitability";

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
    master_predators: &HashSet<String>,
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
    let mut fungivores = Vec::new();
    let mut all_organisms: HashSet<String> = HashSet::new();

    for row in &json_data {
        let source_column = row.get("source_column")?.as_str()?.to_lowercase();
        let organism_taxon = row.get("organism_taxon")?.as_str()?.to_string();

        if organism_taxon.is_empty() {
            continue;
        }

        // Collect by category
        match source_column.as_str() {
            "pollinators" => pollinators.push(organism_taxon.clone()),
            "herbivores" => herbivores.push(organism_taxon.clone()),
            "fungivores_eats" => fungivores.push(organism_taxon.clone()),
            _ => {}
        }

        // Collect ALL organisms for beneficial predator matching
        // (pollinators, flower_visitors, predators_*, herbivores, etc.)
        all_organisms.insert(organism_taxon);
    }

    // Find beneficial predators: organisms that visit this plant AND are known pest predators
    let predators: Vec<String> = all_organisms
        .iter()
        .filter(|org| master_predators.contains(&org.to_lowercase()))
        .cloned()
        .collect();

    if pollinators.is_empty() && herbivores.is_empty() && predators.is_empty() && fungivores.is_empty() {
        return None;
    }

    Some(OrganismLists {
        pollinators,
        herbivores,
        predators,
        fungivores,
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

        // Sort by count (descending) then category name, but "Other" categories always at bottom
        let mut result: Vec<CategorizedOrganisms> = category_map
            .into_iter()
            .map(|(cat, orgs)| CategorizedOrganisms {
                category: cat,
                organisms: orgs,
            })
            .collect();

        result.sort_by(|a, b| {
            let a_is_other = a.category.starts_with("Other");
            let b_is_other = b.category.starts_with("Other");

            // "Other" categories always go to bottom
            match (a_is_other, b_is_other) {
                (true, false) => std::cmp::Ordering::Greater,
                (false, true) => std::cmp::Ordering::Less,
                _ => b.organisms.len().cmp(&a.organisms.len())
                    .then_with(|| a.category.cmp(&b.category))
            }
        });

        result
    }

    OrganismProfile {
        pollinators_by_category: group_by_category(&lists.pollinators, OrganismRole::Pollinator, organism_categories),
        herbivores_by_category: group_by_category(&lists.herbivores, OrganismRole::Herbivore, organism_categories),
        predators_by_category: group_by_category(&lists.predators, OrganismRole::Predator, organism_categories),
        fungivores_by_category: group_by_category(&lists.fungivores, OrganismRole::Predator, organism_categories), // Fungivores act as predators of fungi
        total_pollinators: lists.pollinators.len(),
        total_herbivores: lists.herbivores.len(),
        total_predators: lists.predators.len(),
        total_fungivores: lists.fungivores.len(),
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
            if parts.len() >= 4 {
                let genus = parts[0].trim().to_lowercase();
                let category = parts[3].trim().to_string();  // kimi_label column
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
async fn load_master_predator_list(engine: &QueryEngine) -> HashSet<String> {
    // Load master list of predators from Phase 7 parquet
    // Source: predators_master.parquet (extracted from herbivore_predators_11711.parquet)
    match engine.get_master_predators().await {
        Ok(batches) => {
            let mut predators = HashSet::new();
            if batches.is_empty() {
                eprintln!("Warning: predators_master query returned 0 batches");
                return predators;
            }
            for batch in &batches {
                if let Some(col) = batch.column_by_name("predator_taxon") {
                    // Try StringArray, LargeStringArray, or StringViewArray
                    if let Some(arr) = col.as_any().downcast_ref::<StringArray>() {
                        for i in 0..arr.len() {
                            if !arr.is_null(i) {
                                let val = arr.value(i).to_lowercase();
                                if !val.is_empty() {
                                    predators.insert(val);
                                }
                            }
                        }
                    } else if let Some(arr) = col.as_any().downcast_ref::<LargeStringArray>() {
                        for i in 0..arr.len() {
                            if !arr.is_null(i) {
                                let val = arr.value(i).to_lowercase();
                                if !val.is_empty() {
                                    predators.insert(val);
                                }
                            }
                        }
                    } else if let Some(arr) = col.as_any().downcast_ref::<StringViewArray>() {
                        for i in 0..arr.len() {
                            if !arr.is_null(i) {
                                let val = arr.value(i).to_lowercase();
                                if !val.is_empty() {
                                    predators.insert(val);
                                }
                            }
                        }
                    } else {
                        eprintln!("Warning: Could not downcast column. Type: {:?}", col.data_type());
                    }
                } else {
                    eprintln!("Warning: Column 'predator_taxon' not found in batch");
                }
            }
            predators
        }
        Err(e) => {
            eprintln!("Error loading master predators: {}", e);
            HashSet::new()
        }
    }
}

#[cfg(feature = "api")]
async fn parse_pathogens_ranked(
    engine: &QueryEngine,
    plant_id: &str,
    limit: usize,
) -> Option<Vec<RankedPathogen>> {
    use datafusion::arrow::array::{UInt64Array, Int32Array, Int64Array};

    let batches = engine.get_pathogens(plant_id, Some(limit)).await.ok()?;
    if batches.is_empty() {
        return None;
    }

    let mut pathogens = Vec::new();
    for batch in &batches {
        let taxon_col = batch.column_by_name("pathogen_taxon")?;
        let count_col = batch.column_by_name("observation_count")?;

        // Support StringArray, LargeStringArray, and StringViewArray
        let get_taxon = |i: usize| -> Option<String> {
            if let Some(arr) = taxon_col.as_any().downcast_ref::<StringArray>() {
                if !arr.is_null(i) { Some(arr.value(i).to_string()) } else { None }
            } else if let Some(arr) = taxon_col.as_any().downcast_ref::<LargeStringArray>() {
                if !arr.is_null(i) { Some(arr.value(i).to_string()) } else { None }
            } else if let Some(arr) = taxon_col.as_any().downcast_ref::<StringViewArray>() {
                if !arr.is_null(i) { Some(arr.value(i).to_string()) } else { None }
            } else {
                None
            }
        };

        for i in 0..batch.num_rows() {
            let taxon = match get_taxon(i) {
                Some(t) => t,
                None => continue,
            };

            // Try different integer types for observation_count
            let count = if let Some(arr) = count_col.as_any().downcast_ref::<Int32Array>() {
                arr.value(i) as usize
            } else if let Some(arr) = count_col.as_any().downcast_ref::<Int64Array>() {
                arr.value(i) as usize
            } else if let Some(arr) = count_col.as_any().downcast_ref::<UInt64Array>() {
                arr.value(i) as usize
            } else {
                1 // fallback
            };

            pathogens.push(RankedPathogen {
                taxon,
                observation_count: count,
            });
        }
    }

    if pathogens.is_empty() {
        None
    } else {
        Some(pathogens)
    }
}

#[cfg(feature = "api")]
async fn parse_beneficial_fungi(
    engine: &QueryEngine,
    plant_id: &str,
) -> Option<BeneficialFungi> {
    let batches = engine.get_beneficial_fungi(plant_id).await.ok()?;
    if batches.is_empty() {
        return None;
    }

    let mut mycoparasites = Vec::new();
    let mut entomopathogens = Vec::new();

    for batch in &batches {
        let source_col = batch.column_by_name("source_column")?;
        let taxon_col = batch.column_by_name("fungus_taxon")?;

        // Helper to get string value supporting StringArray, LargeStringArray, and StringViewArray
        let get_str = |col: &dyn std::any::Any, i: usize| -> Option<String> {
            if let Some(arr) = col.downcast_ref::<StringArray>() {
                if !arr.is_null(i) { Some(arr.value(i).to_string()) } else { None }
            } else if let Some(arr) = col.downcast_ref::<LargeStringArray>() {
                if !arr.is_null(i) { Some(arr.value(i).to_string()) } else { None }
            } else if let Some(arr) = col.downcast_ref::<StringViewArray>() {
                if !arr.is_null(i) { Some(arr.value(i).to_string()) } else { None }
            } else {
                None
            }
        };

        for i in 0..batch.num_rows() {
            let source = match get_str(source_col.as_any(), i) {
                Some(s) => s,
                None => continue,
            };
            let taxon = match get_str(taxon_col.as_any(), i) {
                Some(t) => t,
                None => continue,
            };

            match source.as_str() {
                "mycoparasite_fungi" => mycoparasites.push(taxon),
                "entomopathogenic_fungi" => entomopathogens.push(taxon),
                _ => {}
            }
        }
    }

    if mycoparasites.is_empty() && entomopathogens.is_empty() {
        None
    } else {
        Some(BeneficialFungi {
            mycoparasites,
            entomopathogens,
        })
    }
}

// ============================================================================
// Phylogenetic Relatives
// ============================================================================

/// WFO to tree tip mapping
#[cfg(feature = "api")]
struct PhyloData {
    tree: CompactTree,
    wfo_to_tip: HashMap<String, String>,
}

#[cfg(feature = "api")]
impl PhyloData {
    /// Load phylogenetic tree and WFO mapping
    fn load() -> Option<Self> {
        let tree_path = format!("{}/data/stage1/phlogeny/compact_tree_11711.bin", PROJECT_ROOT);
        let mapping_path = format!("{}/data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv", PROJECT_ROOT);

        // Load tree
        let tree = CompactTree::from_binary(&tree_path).ok()?;

        // Load WFO -> tree tip mapping
        let contents = fs::read_to_string(&mapping_path).ok()?;
        let mut wfo_to_tip = HashMap::new();
        for (idx, line) in contents.lines().enumerate() {
            if idx == 0 { continue; } // Skip header
            let parts: Vec<&str> = line.split(',').collect();
            if parts.len() >= 6 {
                let wfo_id = parts[0].to_string();
                let tree_tip = parts[5].to_string();
                if !tree_tip.is_empty() && tree_tip != "NA" {
                    wfo_to_tip.insert(wfo_id, tree_tip);
                }
            }
        }

        Some(PhyloData { tree, wfo_to_tip })
    }

    /// Get tree tip label for a WFO ID
    fn get_tip(&self, wfo_id: &str) -> Option<&str> {
        self.wfo_to_tip.get(wfo_id).map(|s| s.as_str())
    }
}

/// Species info for genus query
#[cfg(feature = "api")]
struct GenusSpecies {
    wfo_id: String,
    scientific_name: String,
    common_name: String,
}

/// Find 5 closest relatives within the same genus
#[cfg(feature = "api")]
async fn find_related_species(
    engine: &QueryEngine,
    phylo: &PhyloData,
    base_wfo_id: &str,
    genus: &str,
) -> (Vec<RelatedSpecies>, usize) {
    // Query all species in the same genus
    let query = format!(
        "SELECT wfo_taxon_id, wfo_scientific_name, vernacular_name_en \
         FROM plants WHERE genus = '{}' AND wfo_taxon_id != '{}'",
        genus, base_wfo_id
    );

    let batches = match engine.query(&query).await {
        Ok(b) => b,
        Err(_) => return (vec![], 0),
    };

    if batches.is_empty() {
        return (vec![], 0);
    }

    // Parse results
    let mut genus_species: Vec<GenusSpecies> = Vec::new();
    for batch in &batches {
        let wfo_col = batch.column_by_name("wfo_taxon_id");
        let name_col = batch.column_by_name("wfo_scientific_name");
        let en_col = batch.column_by_name("vernacular_name_en");

        if wfo_col.is_none() || name_col.is_none() {
            continue;
        }

        let wfo_arr = wfo_col.unwrap();
        let name_arr = name_col.unwrap();
        let en_arr = en_col;

        for i in 0..batch.num_rows() {
            let wfo_id = extract_string_at(wfo_arr, i).unwrap_or_default();
            let scientific_name = extract_string_at(name_arr, i).unwrap_or_default();
            let common_name = en_arr
                .and_then(|arr| extract_string_at(arr, i))
                .unwrap_or_default();

            // Get first common name if multiple
            let common_name = common_name
                .split(';')
                .next()
                .unwrap_or("")
                .trim()
                .to_string();

            // Title case the common name
            let common_name = title_case(&common_name);

            if !wfo_id.is_empty() {
                genus_species.push(GenusSpecies {
                    wfo_id,
                    scientific_name,
                    common_name,
                });
            }
        }
    }

    let genus_count = genus_species.len() + 1; // Include the base plant

    // Get base plant's tree tip
    let base_tip = match phylo.get_tip(base_wfo_id) {
        Some(t) => t,
        None => return (vec![], genus_count),
    };

    // Calculate distances to all genus species
    let mut with_distances: Vec<(GenusSpecies, f64)> = genus_species
        .into_iter()
        .filter_map(|sp| {
            let tip = phylo.get_tip(&sp.wfo_id)?;
            let dist = phylo.tree.pairwise_distance_by_labels(base_tip, tip)?;
            Some((sp, dist))
        })
        .collect();

    // Sort by distance (closest first)
    with_distances.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));

    // Take top 5
    let related: Vec<RelatedSpecies> = with_distances
        .into_iter()
        .take(5)
        .map(|(sp, dist)| RelatedSpecies {
            wfo_id: sp.wfo_id,
            scientific_name: sp.scientific_name,
            common_name: sp.common_name,
            distance: dist,
        })
        .collect();

    (related, genus_count)
}

/// Extract string from Arrow array at index
#[cfg(feature = "api")]
fn extract_string_at(arr: &dyn Array, idx: usize) -> Option<String> {
    if arr.is_null(idx) {
        return None;
    }
    if let Some(sa) = arr.as_any().downcast_ref::<StringArray>() {
        return Some(sa.value(idx).to_string());
    }
    if let Some(sa) = arr.as_any().downcast_ref::<LargeStringArray>() {
        return Some(sa.value(idx).to_string());
    }
    if let Some(sa) = arr.as_any().downcast_ref::<StringViewArray>() {
        return Some(sa.value(idx).to_string());
    }
    None
}

/// Convert string to Title Case
#[cfg(feature = "api")]
fn title_case(s: &str) -> String {
    s.split_whitespace()
        .map(|word| {
            let mut chars = word.chars();
            match chars.next() {
                None => String::new(),
                Some(first) => {
                    let rest: String = chars.collect();
                    format!("{}{}", first.to_uppercase(), rest.to_lowercase())
                }
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(feature = "api")]
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    println!("Generating sample encyclopedia articles...\n");

    // Ensure output directories exist
    fs::create_dir_all(OUTPUT_DIR)?;
    fs::create_dir_all(OUTPUT_DIR_SUITABILITY)?;

    // Initialize query engine and generator
    let engine = QueryEngine::new(PROJECT_ROOT).await?;
    let generator = EncyclopediaGenerator::new();

    // Load organism categorization map (Kimi AI)
    let organism_categories = load_organism_categories();
    println!("Loaded {} organism category mappings", organism_categories.len());

    // Load master predator list from parquet (species known to eat pests in GloBI)
    let master_predators = load_master_predator_list(&engine).await;
    println!("Loaded {} master predators", master_predators.len());

    // Load phylogenetic tree for related species
    let phylo_data = PhyloData::load();
    if phylo_data.is_some() {
        println!("Loaded phylogenetic tree ({} mappings)", phylo_data.as_ref().unwrap().wfo_to_tip.len());
    } else {
        println!("Warning: Could not load phylogenetic tree");
    }

    // All test locations for suitability reports
    let all_locations = test_locations();
    println!("Test locations for suitability:");
    for loc in &all_locations {
        println!("  - {}", loc.name);
    }
    println!();

    let mut generic_count = 0;
    let mut suitability_count = 0;

    for (wfo_id, filename, description) in SAMPLE_PLANTS {
        println!("Generating: {} ({})", filename.replace('_', " "), description);

        // Fetch plant data
        let plant_batches = engine.get_plant(wfo_id).await?;
        let plant_data = batch_to_hashmap(&plant_batches)
            .ok_or_else(|| anyhow::anyhow!("Plant {} not found", wfo_id))?;

        // Fetch organism lists (with actual names)
        // Beneficial predators are computed by intersecting all plant-associated organisms
        // with the master list of pest predators
        let organism_lists = engine
            .get_organisms(wfo_id, None)
            .await
            .ok()
            .and_then(|b| parse_organism_lists(&b, &master_predators));

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

        // Fetch ranked pathogens (top 10 most observed diseases)
        let ranked_pathogens = parse_pathogens_ranked(&engine, wfo_id, 10).await;

        // Fetch beneficial fungi species
        let beneficial_fungi = parse_beneficial_fungi(&engine, wfo_id).await;

        // Find related species within genus
        let genus = plant_data
            .get("genus")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let (related_species, genus_count) = if let Some(ref phylo) = phylo_data {
            find_related_species(&engine, phylo, wfo_id, genus).await
        } else {
            (vec![], 0)
        };

        // Generate generic encyclopedia (for Google/SEO)
        let markdown = generator.generate(
            wfo_id,
            &plant_data,
            organism_counts.clone(),
            fungal_counts.clone(),
            organism_profile.clone(),
            ranked_pathogens.clone(),
            beneficial_fungi.clone(),
            if related_species.is_empty() { None } else { Some(related_species.clone()) },
            genus_count,
        ).map_err(|e| anyhow::anyhow!(e))?;

        // Save generic version
        let output_path = Path::new(OUTPUT_DIR).join(format!("encyclopedia_{}.md", filename));
        fs::write(&output_path, &markdown)?;
        println!("  Saved generic: {}", output_path.display());
        generic_count += 1;

        // Generate location-specific encyclopedias for ALL test locations
        for location in &all_locations {
            // Create location suffix from name (e.g., "London, UK (Temperate)" -> "london")
            let loc_suffix = location.name
                .split(&[',', '('][..])
                .next()
                .unwrap_or("unknown")
                .trim()
                .to_lowercase()
                .replace(' ', "_");

            let markdown_suitability = generator.generate_with_suitability(
                wfo_id,
                &plant_data,
                organism_counts.clone(),
                fungal_counts.clone(),
                organism_profile.clone(),
                ranked_pathogens.clone(),
                beneficial_fungi.clone(),
                if related_species.is_empty() { None } else { Some(related_species.clone()) },
                genus_count,
                location,
            ).map_err(|e| anyhow::anyhow!(e))?;

            // Save suitability version
            let output_path_suit = Path::new(OUTPUT_DIR_SUITABILITY)
                .join(format!("encyclopedia_{}_{}.md", filename, loc_suffix));
            fs::write(&output_path_suit, &markdown_suitability)?;
            println!("  Saved with suitability: {}", output_path_suit.display());
            suitability_count += 1;
        }
    }

    println!("\nDone! Generated {} generic + {} location-specific encyclopedia articles.",
        generic_count, suitability_count);
    Ok(())
}

#[cfg(not(feature = "api"))]
fn main() {
    eprintln!("This binary requires the 'api' feature. Run with: cargo run --features api --bin generate_sample_encyclopedias");
}
