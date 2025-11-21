//! Biocontrol Network Analysis for M3 (Insect Pest Control)
//!
//! Analyzes which plants attract beneficial predators and entomopathogenic fungi,
//! identifies generalist biocontrol agents, and finds network hubs.

use polars::prelude::*;
use rustc_hash::{FxHashMap, FxHashSet};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use crate::explanation::unified_taxonomy::{OrganismCategory, OrganismRole};

/// Matched biocontrol pair with categories (Predator or Fungi)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchedBiocontrolPair {
    pub target: String,            // Herbivore (pest)
    pub target_category: OrganismCategory,
    pub agent: String,             // Predator or Fungus
    pub agent_category: OrganismCategory,
}

/// Biocontrol network profile showing qualitative pest control information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BiocontrolNetworkProfile {
    /// Total unique animal predators found across guild
    pub total_unique_predators: usize,

    /// Total unique entomopathogenic fungi found across guild
    pub total_unique_entomo_fungi: usize,

    /// Number of specific predator matches (herbivore → known predator)
    pub specific_predator_matches: usize,

    /// Number of specific fungi matches (herbivore → known entomopathogenic fungus)
    pub specific_fungi_matches: usize,

    /// Total count of general entomopathogenic fungi
    pub general_entomo_fungi_count: usize,

    /// List of matched (herbivore, predator) pairs with categories
    pub matched_predator_pairs: Vec<MatchedBiocontrolPair>,

    /// List of matched (herbivore, entomopathogenic_fungus) pairs with categories
    pub matched_fungi_pairs: Vec<MatchedBiocontrolPair>,

    /// Predator category distribution
    pub predator_category_counts: FxHashMap<OrganismCategory, usize>,

    /// Herbivore category distribution
    pub herbivore_category_counts: FxHashMap<OrganismCategory, usize>,

    /// Top 10 predators by connectivity (visiting multiple plants)
    pub top_predators: Vec<BiocontrolAgent>,

    /// Top 10 entomopathogenic fungi by connectivity
    pub top_entomo_fungi: Vec<BiocontrolAgent>,

    /// Top 10 plants by biocontrol agent count
    pub hub_plants: Vec<PlantBiocontrolHub>,
}

/// A biocontrol agent (predator or entomopathogenic fungus)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BiocontrolAgent {
    /// Name of the biocontrol agent
    pub agent_name: String,

    /// Type: "Predator" or "Entomopathogenic Fungus"
    pub agent_type: String,

    /// Number of guild plants this agent visits/protects
    pub plant_count: usize,

    /// Plant names (limited to first 5 for display)
    pub plants: Vec<String>,

    /// Network contribution: plant_count / n_plants
    pub network_contribution: f64,
}

/// Plant that serves as a biocontrol hub
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlantBiocontrolHub {
    /// Plant scientific name
    pub plant_name: String,

    /// Plant vernacular name
    pub plant_vernacular: String,

    /// Number of predators visiting this plant
    pub total_predators: usize,

    /// Number of entomopathogenic fungi on this plant
    pub total_entomo_fungi: usize,

    /// Combined total biocontrol agents
    pub total_biocontrol_agents: usize,

    /// Whether this plant has any biocontrol data
    pub has_data: bool,
}

/// Analyze biocontrol network for M3
///
/// Extracts predator and entomopathogenic fungi information from organisms and fungi DataFrames,
/// identifies generalist agents, and finds hub plants.
pub fn analyze_biocontrol_network(
    predator_counts: &FxHashMap<String, usize>,
    entomo_fungi_counts: &FxHashMap<String, usize>,
    specific_predator_matches: usize,
    specific_fungi_matches: usize,
    matched_predator_pairs: &[(String, String)],
    matched_fungi_pairs: &[(String, String)],
    guild_plants: &DataFrame,
    organisms_df: &DataFrame,
    fungi_df: &DataFrame,
    organism_categories: &FxHashMap<String, String>,
) -> Result<Option<BiocontrolNetworkProfile>> {
    let n_plants = guild_plants.height();

    if n_plants == 0 {
        return Ok(None);
    }

    // Get total unique agents
    let total_unique_predators = predator_counts.len();
    let total_unique_entomo_fungi = entomo_fungi_counts.len();
    let general_entomo_fungi_count = entomo_fungi_counts.values().sum();

    if total_unique_predators == 0 && total_unique_entomo_fungi == 0 {
        return Ok(None);
    }

    // Categorize predators and build category counts
    let mut predator_category_counts: FxHashMap<OrganismCategory, usize> = FxHashMap::default();
    for predator_name in predator_counts.keys() {
        let category = OrganismCategory::from_name(predator_name, organism_categories, Some(OrganismRole::Predator));
        *predator_category_counts.entry(category).or_insert(0) += 1;
    }

    // Categorize herbivores from matched pairs and build category counts
    let mut herbivore_category_counts: FxHashMap<OrganismCategory, usize> = FxHashMap::default();
    let mut unique_herbivores: FxHashSet<String> = FxHashSet::default();

    // Check herbivores from both predator and fungi matches
    for (herbivore, _) in matched_predator_pairs.iter().chain(matched_fungi_pairs.iter()) {
        if unique_herbivores.insert(herbivore.clone()) {
            let category = OrganismCategory::from_name(herbivore, organism_categories, Some(OrganismRole::Herbivore));
            *herbivore_category_counts.entry(category).or_insert(0) += 1;
        }
    }

    // Build matched predator pairs with categories
    let matched_predator_pairs_with_categories: Vec<MatchedBiocontrolPair> = matched_predator_pairs
        .iter()
        .map(|(herbivore, predator)| MatchedBiocontrolPair {
            target: herbivore.clone(),
            target_category: OrganismCategory::from_name(herbivore, organism_categories, Some(OrganismRole::Herbivore)),
            agent: predator.clone(),
            agent_category: OrganismCategory::from_name(predator, organism_categories, Some(OrganismRole::Predator)),
        })
        .collect();

    // Build matched fungi pairs with categories
    // Fungi don't have specific categories in OrganismCategory like "Beetles", so we use the generic role or name
    // Usually entomopathogenic fungi are categorized as "Fungi" or "Entomopathogenic" if the enum supports it.
    // For now, we'll trust from_name to do its best or default.
    let matched_fungi_pairs_with_categories: Vec<MatchedBiocontrolPair> = matched_fungi_pairs
        .iter()
        .map(|(herbivore, fungus)| MatchedBiocontrolPair {
            target: herbivore.clone(),
            target_category: OrganismCategory::from_name(herbivore, organism_categories, Some(OrganismRole::Herbivore)),
            agent: fungus.clone(),
            agent_category: OrganismCategory::from_name(fungus, organism_categories, None), // No specific role needed, defaults apply
        })
        .collect();

    // Build plant ID → name mapping
    let plant_names = build_plant_name_map(guild_plants)?;

    // Get top predators by connectivity
    let top_predators = get_top_agents(
        predator_counts,
        &plant_names,
        organisms_df,
        "Predator",
        n_plants,
        10,
    )?;

    // Get top entomopathogenic fungi by connectivity
    let top_entomo_fungi = get_top_agents(
        entomo_fungi_counts,
        &plant_names,
        fungi_df,
        "Entomopathogenic Fungus",
        n_plants,
        10,
    )?;

    // Build filter sets from already-filtered counts (these are the known biocontrol agents)
    let known_predators: FxHashSet<String> = predator_counts.keys().cloned().collect();
    let known_entomo_fungi: FxHashSet<String> = entomo_fungi_counts.keys().cloned().collect();

    // Find hub plants (using filtered agent sets)
    let hub_plants = find_biocontrol_hubs(
        guild_plants,
        organisms_df,
        fungi_df,
        &known_predators,
        &known_entomo_fungi,
    )?;

    Ok(Some(BiocontrolNetworkProfile {
        total_unique_predators,
        total_unique_entomo_fungi,
        specific_predator_matches,
        specific_fungi_matches,
        general_entomo_fungi_count,
        matched_predator_pairs: matched_predator_pairs_with_categories,
        matched_fungi_pairs: matched_fungi_pairs_with_categories,
        predator_category_counts,
        herbivore_category_counts,
        top_predators,
        top_entomo_fungi,
        hub_plants,
    }))
}

/// Build plant_wfo_id → scientific_name mapping
fn build_plant_name_map(guild_plants: &DataFrame) -> Result<FxHashMap<String, String>> {
    let mut map = FxHashMap::default();

    let plant_ids = guild_plants.column("wfo_taxon_id")?.str()?;
    let plant_names = guild_plants.column("wfo_scientific_name")?.str()?;

    for idx in 0..guild_plants.height() {
        if let (Some(id), Some(name)) = (plant_ids.get(idx), plant_names.get(idx)) {
            map.insert(id.to_string(), name.to_string());
        }
    }

    Ok(map)
}

/// Get top biocontrol agents by connectivity
fn get_top_agents(
    agent_counts: &FxHashMap<String, usize>,
    plant_names: &FxHashMap<String, String>,
    df: &DataFrame,
    agent_type: &str,
    n_plants: usize,
    limit: usize,
) -> Result<Vec<BiocontrolAgent>> {
    // Build agent → [plant_ids] mapping from DataFrame
    let agent_to_plants = match agent_type {
        "Predator" => build_predator_to_plants_map(df)?,
        "Entomopathogenic Fungus" => build_fungi_to_plants_map(df)?,
        _ => return Ok(Vec::new()),
    };

    // Convert to BiocontrolAgent structs
    let mut agents: Vec<BiocontrolAgent> = agent_counts
        .iter()
        .filter_map(|(agent_name, &count)| {
            if count < 2 {
                return None; // Only show agents visiting 2+ plants
            }

            let plant_ids = agent_to_plants.get(agent_name)?;
            let plants: Vec<String> = plant_ids
                .iter()
                .filter_map(|id| plant_names.get(id).cloned())
                .take(5)
                .collect();

            Some(BiocontrolAgent {
                agent_name: agent_name.clone(),
                agent_type: agent_type.to_string(),
                plant_count: count,
                plants,
                network_contribution: count as f64 / n_plants as f64,
            })
        })
        .collect();

    // Sort by plant_count descending, then agent_name ascending
    agents.sort_by(|a, b| {
        b.plant_count
            .cmp(&a.plant_count)
            .then_with(|| a.agent_name.cmp(&b.agent_name))
    });

    agents.truncate(limit);
    Ok(agents)
}

/// Build predator → [plant_ids] mapping from organisms DataFrame
fn build_predator_to_plants_map(organisms_df: &DataFrame) -> Result<FxHashMap<String, Vec<String>>> {
    let mut map: FxHashMap<String, Vec<String>> = FxHashMap::default();

    let plant_ids = organisms_df.column("plant_wfo_id")?.str()?;

    // Aggregate all predator columns
    let predator_columns = [
        "predators_hasHost",
        "predators_interactsWith",
        "predators_adjacentTo",
    ];

    for idx in 0..organisms_df.height() {
        if let Some(plant_id) = plant_ids.get(idx) {
            for col_name in &predator_columns {
                if let Ok(col) = organisms_df.column(col_name) {
                    if let Ok(str_col) = col.str() {
                        if let Some(value) = str_col.get(idx) {
                            for predator in value.split('|').filter(|s| !s.is_empty()) {
                                map.entry(predator.to_string())
                                    .or_insert_with(Vec::new)
                                    .push(plant_id.to_string());
                            }
                        }
                    }
                }
            }
        }
    }

    // Deduplicate plant lists
    for plants in map.values_mut() {
        plants.sort_unstable();
        plants.dedup();
    }

    Ok(map)
}

/// Build entomopathogenic_fungi → [plant_ids] mapping from fungi DataFrame
fn build_fungi_to_plants_map(fungi_df: &DataFrame) -> Result<FxHashMap<String, Vec<String>>> {
    let mut map: FxHashMap<String, Vec<String>> = FxHashMap::default();

    let plant_ids = fungi_df.column("plant_wfo_id")?.str()?;

    if let Ok(col) = fungi_df.column("entomopathogenic_fungi") {
        if let Ok(str_col) = col.str() {
            for idx in 0..fungi_df.height() {
                if let (Some(plant_id), Some(value)) = (plant_ids.get(idx), str_col.get(idx)) {
                    for fungus in value.split('|').filter(|s| !s.is_empty()) {
                        map.entry(fungus.to_string())
                            .or_insert_with(Vec::new)
                            .push(plant_id.to_string());
                    }
                }
            }
        }
    }

    // Deduplicate plant lists
    for plants in map.values_mut() {
        plants.sort_unstable();
        plants.dedup();
    }

    Ok(map)
}

/// Build plant display map (WFO ID -> (scientific, vernacular))
fn build_plant_display_map_biocontrol(guild_plants: &DataFrame) -> Result<FxHashMap<String, (String, String)>> {
    let plant_id_col = guild_plants.column("wfo_taxon_id")?.str()?;
    let scientific_col = guild_plants.column("wfo_scientific_name")?.str()?;

    // Try vernacular_name_en first, fall back to vernacular_name_zh, then empty string
    let vernacular_col = if let Ok(col) = guild_plants.column("vernacular_name_en") {
        Some(col.str()?.clone())
    } else if let Ok(col) = guild_plants.column("vernacular_name_zh") {
        Some(col.str()?.clone())
    } else {
        None
    };

    let mut map = FxHashMap::default();
    for idx in 0..guild_plants.height() {
        if let (Some(id), Some(sci)) = (plant_id_col.get(idx), scientific_col.get(idx)) {
            let vern = if let Some(ref v_col) = vernacular_col {
                v_col.get(idx).unwrap_or("").to_string()
            } else {
                String::new()
            };
            map.insert(id.to_string(), (sci.to_string(), vern));
        }
    }
    Ok(map)
}

/// Find plants that are biocontrol hubs (attract most agents)
fn find_biocontrol_hubs(
    guild_plants: &DataFrame,
    organisms_df: &DataFrame,
    fungi_df: &DataFrame,
    known_predators: &FxHashSet<String>,
    known_entomo_fungi: &FxHashSet<String>,
) -> Result<Vec<PlantBiocontrolHub>> {
    // Get plant display map (scientific + vernacular)
    let plant_display_map = build_plant_display_map_biocontrol(guild_plants)?;

    let mut hubs: Vec<PlantBiocontrolHub> = Vec::new();

    let plant_ids = guild_plants.column("wfo_taxon_id")?.str()?;

    // Include ALL guild plants (not just those with agents)
    for idx in 0..guild_plants.height() {
        if let Some(plant_id) = plant_ids.get(idx) {
            // Count predators for this plant (filtered to known predators only)
            let total_predators = count_predators_for_plant(organisms_df, plant_id, known_predators)?;

            // Count entomopathogenic fungi for this plant (filtered to known fungi only)
            let total_entomo_fungi = count_entomo_fungi_for_plant(fungi_df, plant_id, known_entomo_fungi)?;

            let total_biocontrol_agents = total_predators + total_entomo_fungi;

            let (scientific, vernacular) = plant_display_map
                .get(plant_id)
                .cloned()
                .unwrap_or_else(|| (plant_id.to_string(), String::new()));

            hubs.push(PlantBiocontrolHub {
                plant_name: scientific,
                plant_vernacular: vernacular,
                total_predators,
                total_entomo_fungi,
                total_biocontrol_agents,
                has_data: total_biocontrol_agents > 0,
            });
        }
    }

    // Sort by total_biocontrol_agents descending, then plant_name ascending
    hubs.sort_by(|a, b| {
        b.total_biocontrol_agents
            .cmp(&a.total_biocontrol_agents)
            .then_with(|| a.plant_name.cmp(&b.plant_name))
    });

    hubs.truncate(10);
    Ok(hubs)
}

/// Count predators for a specific plant (filtered to known predators only)
fn count_predators_for_plant(
    organisms_df: &DataFrame,
    target_plant_id: &str,
    known_predators: &FxHashSet<String>,
) -> Result<usize> {
    let plant_ids = organisms_df.column("plant_wfo_id")?.str()?;

    let predator_columns = [
        "predators_hasHost",
        "predators_interactsWith",
        "predators_adjacentTo",
    ];

    for idx in 0..organisms_df.height() {
        if let Some(plant_id) = plant_ids.get(idx) {
            if plant_id == target_plant_id {
                let mut predators = Vec::new();

                for col_name in &predator_columns {
                    if let Ok(col) = organisms_df.column(col_name) {
                        if let Ok(str_col) = col.str() {
                            if let Some(value) = str_col.get(idx) {
                                for predator in value.split('|').filter(|s| !s.is_empty()) {
                                    // ONLY count if this is a known predator from lookup table
                                    if known_predators.contains(predator) {
                                        predators.push(predator.to_string());
                                    }
                                }
                            }
                        }
                    }
                }

                predators.sort_unstable();
                predators.dedup();
                return Ok(predators.len());
            }
        }
    }

    Ok(0)
}

/// Count entomopathogenic fungi for a specific plant (filtered to known fungi only)
fn count_entomo_fungi_for_plant(
    fungi_df: &DataFrame,
    target_plant_id: &str,
    known_entomo_fungi: &FxHashSet<String>,
) -> Result<usize> {
    let plant_ids = fungi_df.column("plant_wfo_id")?.str()?;

    if let Ok(col) = fungi_df.column("entomopathogenic_fungi") {
        if let Ok(str_col) = col.str() {
            for idx in 0..fungi_df.height() {
                if let (Some(plant_id), Some(value)) = (plant_ids.get(idx), str_col.get(idx)) {
                    if plant_id == target_plant_id {
                        // ONLY count fungi that are known entomopathogenic fungi from lookup table
                        let count = value.split('|')
                            .filter(|s| !s.is_empty() && known_entomo_fungi.contains(*s))
                            .count();
                        return Ok(count);
                    }
                }
            }
        }
    }

    Ok(0)
}