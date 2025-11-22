//! Pathogen Control Network Analysis for M4 (Disease Suppression)
//!
//! Analyzes which plants harbor mycoparasite fungi that suppress pathogens,
//! identifies generalist mycoparasites, and finds network hubs.

use polars::prelude::*;
use rustc_hash::FxHashMap;
use anyhow::Result;
use serde::{Deserialize, Serialize};
use crate::explanation::unified_taxonomy::{OrganismCategory, OrganismRole};

/// Matched fungivore pair with category
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchedFungivorePair {
    pub pathogen: String,
    pub fungivore: String,
    pub fungivore_category: OrganismCategory,
}

/// Pathogen control network profile showing qualitative disease suppression information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PathogenControlNetworkProfile {
    /// Total unique mycoparasite species found across guild
    pub total_unique_mycoparasites: usize,

    /// Total unique pathogen species found across guild
    pub total_unique_pathogens: usize,

    /// Number of specific antagonist matches (pathogen → known mycoparasite)
    pub specific_antagonist_matches: usize,

    /// Number of specific fungivore matches (pathogen → known fungivore)
    pub specific_fungivore_matches: usize,

    /// Total count of general mycoparasites (primary mechanism)
    pub general_mycoparasite_count: usize,

    /// List of matched (pathogen, antagonist) pairs
    pub matched_antagonist_pairs: Vec<(String, String)>,

    /// List of matched (pathogen, fungivore) pairs with categories
    pub matched_fungivore_pairs: Vec<MatchedFungivorePair>,

    /// Top 10 mycoparasites by connectivity (visiting multiple plants)
    pub top_mycoparasites: Vec<MycoparasiteAgent>,

    /// Top 10 plants by mycoparasite count (protection hubs)
    pub hub_plants: Vec<PlantPathogenControlHub>,
}

/// A mycoparasite agent (fungus that parasitizes other fungi)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MycoparasiteAgent {
    /// Name of the mycoparasite
    pub mycoparasite_name: String,

    /// Number of guild plants harboring this mycoparasite
    pub plant_count: usize,

    /// Plant names (limited to first 5 for display)
    pub plants: Vec<String>,

    /// Network contribution: plant_count / n_plants
    pub network_contribution: f64,
}

/// Plant that serves as a pathogen control hub
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlantPathogenControlHub {
    /// Plant scientific name
    pub plant_name: String,

    /// Plant vernacular name
    pub plant_vernacular: String,

    /// Number of mycoparasites on this plant
    pub mycoparasite_count: usize,

    /// Number of pathogens attacking this plant
    pub pathogen_count: usize,

    /// Whether this plant has any pathogen control data
    pub has_data: bool,
}

/// Analyze pathogen control network for M4
///
/// Extracts mycoparasite and pathogen information from fungi DataFrame,
/// identifies generalist mycoparasites, and finds hub plants.
pub fn analyze_pathogen_control_network(
    mycoparasite_counts: &FxHashMap<String, usize>,
    pathogen_counts: &FxHashMap<String, usize>,
    specific_antagonist_matches: usize,
    matched_antagonist_pairs: &[(String, String)],
    specific_fungivore_matches: usize,
    matched_fungivore_pairs: &[(String, String)],
    guild_plants: &DataFrame,
    fungi_df: &DataFrame,
    organism_categories: &FxHashMap<String, String>,
) -> Result<Option<PathogenControlNetworkProfile>> {
    let n_plants = guild_plants.height();

    if n_plants == 0 {
        return Ok(None);
    }

    // Get total unique agents
    let total_unique_mycoparasites = mycoparasite_counts.len();
    let total_unique_pathogens = pathogen_counts.len();
    let general_mycoparasite_count = mycoparasite_counts.values().sum();

    // Return None only if NO data at all (no mycoparasites AND no specific matches)
    if total_unique_mycoparasites == 0 && specific_fungivore_matches == 0 {
        return Ok(None);
    }

    // Transform matched fungivore pairs to include category (using Kimi lookup)
    let matched_fungivore_pairs_structs: Vec<MatchedFungivorePair> = matched_fungivore_pairs
        .iter()
        .map(|(pathogen, fungivore)| {
            let category = OrganismCategory::from_name(
                fungivore, 
                organism_categories, 
                Some(OrganismRole::Predator) // Fungivores act as predators of fungi
            );
            MatchedFungivorePair {
                pathogen: pathogen.clone(),
                fungivore: fungivore.clone(),
                fungivore_category: category,
            }
        })
        .collect();

    // Build plant ID → name mapping
    let plant_names = build_plant_name_map(guild_plants)?;

    // Get top mycoparasites by connectivity
    let top_mycoparasites = get_top_mycoparasites(
        mycoparasite_counts,
        &plant_names,
        fungi_df,
        n_plants,
        10,
    )?;

    // Find hub plants
    let hub_plants = find_pathogen_control_hubs(
        guild_plants,
        fungi_df,
    )?;

    Ok(Some(PathogenControlNetworkProfile {
        total_unique_mycoparasites,
        total_unique_pathogens,
        specific_antagonist_matches,
        specific_fungivore_matches,
        general_mycoparasite_count,
        matched_antagonist_pairs: matched_antagonist_pairs.to_vec(),
        matched_fungivore_pairs: matched_fungivore_pairs_structs,
        top_mycoparasites,
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

/// Get top mycoparasites by connectivity
fn get_top_mycoparasites(
    mycoparasite_counts: &FxHashMap<String, usize>,
    plant_names: &FxHashMap<String, String>,
    fungi_df: &DataFrame,
    n_plants: usize,
    limit: usize,
) -> Result<Vec<MycoparasiteAgent>> {
    // Build mycoparasite → [plant_ids] mapping from DataFrame
    let mycoparasite_to_plants = build_mycoparasite_to_plants_map(fungi_df)?;

    // Convert to MycoparasiteAgent structs
    let mut agents: Vec<MycoparasiteAgent> = mycoparasite_counts
        .iter()
        .filter_map(|(mycoparasite_name, &count)| {
            if count < 2 {
                return None; // Only show mycoparasites on 2+ plants
            }

            let plant_ids = mycoparasite_to_plants.get(mycoparasite_name)?;
            let plants: Vec<String> = plant_ids
                .iter()
                .filter_map(|id| plant_names.get(id).cloned())
                .take(5)
                .collect();

            Some(MycoparasiteAgent {
                mycoparasite_name: mycoparasite_name.clone(),
                plant_count: count,
                plants,
                network_contribution: count as f64 / n_plants as f64,
            })
        })
        .collect();

    // Sort by plant_count descending, then mycoparasite_name ascending
    agents.sort_by(|a, b| {
        b.plant_count
            .cmp(&a.plant_count)
            .then_with(|| a.mycoparasite_name.cmp(&b.mycoparasite_name))
    });

    agents.truncate(limit);
    Ok(agents)
}

/// Build mycoparasite → [plant_ids] mapping from fungi DataFrame
fn build_mycoparasite_to_plants_map(fungi_df: &DataFrame) -> Result<FxHashMap<String, Vec<String>>> {
    let mut map: FxHashMap<String, Vec<String>> = FxHashMap::default();

    let plant_ids = fungi_df.column("plant_wfo_id")?.str()?;

    if let Ok(col) = fungi_df.column("mycoparasite_fungi") {
        if let Ok(str_col) = col.str() {
            for idx in 0..fungi_df.height() {
                if let (Some(plant_id), Some(value)) = (plant_ids.get(idx), str_col.get(idx)) {
                    for mycoparasite in value.split('|').filter(|s| !s.is_empty()) {
                        map.entry(mycoparasite.to_string())
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
fn build_plant_display_map_pathogen(guild_plants: &DataFrame) -> Result<FxHashMap<String, (String, String)>> {
    use crate::utils::get_display_name;

    let plant_id_col = guild_plants.column("wfo_taxon_id")?.str()?;
    let scientific_col = guild_plants.column("wfo_scientific_name")?.str()?;
    let vernacular_en_col = guild_plants.column("vernacular_name_en").ok().and_then(|c| c.str().ok());
    let vernacular_zh_col = guild_plants.column("vernacular_name_zh").ok().and_then(|c| c.str().ok());

    let mut map = FxHashMap::default();
    for idx in 0..guild_plants.height() {
        if let (Some(id), Some(sci)) = (plant_id_col.get(idx), scientific_col.get(idx)) {
            // Use Title Case normalization from vernacular.rs
            let en = vernacular_en_col.and_then(|c| c.get(idx));
            let zh = vernacular_zh_col.and_then(|c| c.get(idx));
            let display_name_full = get_display_name(sci, en, zh);

            // Extract just the vernacular part from "Scientific (Vernacular)" format
            let vern = if let Some(start_idx) = display_name_full.find('(') {
                if let Some(end_idx) = display_name_full.rfind(')') {
                    display_name_full[start_idx + 1..end_idx].to_string()
                } else {
                    String::new()
                }
            } else {
                String::new()
            };

            map.insert(id.to_string(), (sci.to_string(), vern));
        }
    }
    Ok(map)
}

/// Find plants that are pathogen control hubs (harbor most mycoparasites)
fn find_pathogen_control_hubs(
    guild_plants: &DataFrame,
    fungi_df: &DataFrame,
) -> Result<Vec<PlantPathogenControlHub>> {
    // Get plant display map (scientific + vernacular)
    let plant_display_map = build_plant_display_map_pathogen(guild_plants)?;

    let mut hubs: Vec<PlantPathogenControlHub> = Vec::new();

    let plant_ids = guild_plants.column("wfo_taxon_id")?.str()?;

    // Include ALL guild plants (not just those with data)
    for idx in 0..guild_plants.height() {
        if let Some(plant_id) = plant_ids.get(idx) {
            // Count mycoparasites for this plant
            let mycoparasite_count = count_mycoparasites_for_plant(fungi_df, plant_id)?;

            // Count pathogens for this plant
            let pathogen_count = count_pathogens_for_plant(fungi_df, plant_id)?;

            let (scientific, vernacular) = plant_display_map
                .get(plant_id)
                .cloned()
                .unwrap_or_else(|| (plant_id.to_string(), String::new()));

            hubs.push(PlantPathogenControlHub {
                plant_name: scientific,
                plant_vernacular: vernacular,
                mycoparasite_count,
                pathogen_count,
                has_data: mycoparasite_count > 0 || pathogen_count > 0,
            });
        }
    }

    // Sort by mycoparasite_count descending, then plant_name ascending
    hubs.sort_by(|a, b| {
        b.mycoparasite_count
            .cmp(&a.mycoparasite_count)
            .then_with(|| a.plant_name.cmp(&b.plant_name))
    });

    hubs.truncate(10);
    Ok(hubs)
}

/// Count mycoparasites for a specific plant
fn count_mycoparasites_for_plant(fungi_df: &DataFrame, target_plant_id: &str) -> Result<usize> {
    let plant_ids = fungi_df.column("plant_wfo_id")?.str()?;

    if let Ok(col) = fungi_df.column("mycoparasite_fungi") {
        // Try list column first (Phase 0-4 format)
        if let Ok(list_col) = col.list() {
            for idx in 0..fungi_df.height() {
                if let Some(plant_id) = plant_ids.get(idx) {
                    if plant_id == target_plant_id {
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
            // Fallback: pipe-separated string (legacy format)
            for idx in 0..fungi_df.height() {
                if let (Some(plant_id), Some(value)) = (plant_ids.get(idx), str_col.get(idx)) {
                    if plant_id == target_plant_id {
                        let count = value.split('|').filter(|s| !s.is_empty()).count();
                        return Ok(count);
                    }
                }
            }
        }
    }

    Ok(0)
}

/// Count pathogens for a specific plant
fn count_pathogens_for_plant(fungi_df: &DataFrame, target_plant_id: &str) -> Result<usize> {
    let plant_ids = fungi_df.column("plant_wfo_id")?.str()?;

    if let Ok(col) = fungi_df.column("pathogenic_fungi") {
        // Try list column first (Phase 0-4 format)
        if let Ok(list_col) = col.list() {
            for idx in 0..fungi_df.height() {
                if let Some(plant_id) = plant_ids.get(idx) {
                    if plant_id == target_plant_id {
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
            // Fallback: pipe-separated string (legacy format)
            for idx in 0..fungi_df.height() {
                if let (Some(plant_id), Some(value)) = (plant_ids.get(idx), str_col.get(idx)) {
                    if plant_id == target_plant_id {
                        let count = value.split('|').filter(|s| !s.is_empty()).count();
                        return Ok(count);
                    }
                }
            }
        }
    }

    Ok(0)
}
