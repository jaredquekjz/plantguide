//! Fungi Network Profile Analysis
//!
//! Provides detailed breakdown of beneficial fungi networks showing:
//! - Fungal diversity by category (AMF, EMF, endophytic, saprotrophic)
//! - Top network fungi ranked by connectivity
//! - Plant fungal hubs ranked by total associations

use polars::prelude::*;
use anyhow::Result;
use rustc_hash::FxHashMap;
use serde::{Deserialize, Serialize};
use crate::metrics::M5Result;

/// Fungus category type
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum FungusCategory {
    AMF,           // Arbuscular Mycorrhizal Fungi
    EMF,           // Ectomycorrhizal Fungi
    Endophytic,    // Endophytic fungi
    Saprotrophic,  // Saprotrophic fungi
}

impl std::fmt::Display for FungusCategory {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FungusCategory::AMF => write!(f, "AMF"),
            FungusCategory::EMF => write!(f, "EMF"),
            FungusCategory::Endophytic => write!(f, "Endophytic"),
            FungusCategory::Saprotrophic => write!(f, "Saprotrophic"),
        }
    }
}

/// A fungus shared by multiple plants
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharedFungus {
    pub fungus_name: String,
    pub plant_count: usize,
    pub plants: Vec<String>,
    pub category: FungusCategory,
    /// Network contribution (plant_count / n_plants)
    pub network_contribution: f64,
    /// Whether this fungus is dual-lifestyle (also appears in pathogenic_fungi)
    pub is_dual_lifestyle: bool,
}

/// Top fungus by network importance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopFungus {
    pub fungus_name: String,
    pub plant_count: usize,
    pub plants: Vec<String>,
    pub category: FungusCategory,
    pub network_contribution: f64,
    /// Whether this fungus is dual-lifestyle (also appears in pathogenic_fungi)
    pub is_dual_lifestyle: bool,
}

/// Fungus featured in a category
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopFungusInCategory {
    pub category: FungusCategory,
    pub fungus_name: String,
    pub plant_count: usize,
}

/// Fungi categorized by type
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FungiByCategoryProfile {
    pub amf_count: usize,
    pub emf_count: usize,
    pub endophytic_count: usize,
    pub saprotrophic_count: usize,
    /// Most connected fungus in each category
    pub top_per_category: Vec<TopFungusInCategory>,
}

/// Plant ranked by fungal connectivity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlantFungalHub {
    pub plant_name: String,
    pub plant_vernacular: String,
    pub fungus_count: usize,
    pub amf_count: usize,
    pub emf_count: usize,
    pub endophytic_count: usize,
    pub saprotrophic_count: usize,
    pub has_data: bool,
}

/// Detailed fungi network analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FungiNetworkProfile {
    /// Total unique beneficial fungi species
    pub total_unique_fungi: usize,

    /// Shared fungi (connecting 2+ plants)
    pub shared_fungi: Vec<SharedFungus>,

    /// Top 10 fungi by network contribution
    pub top_fungi: Vec<TopFungus>,

    /// Featured fungi by category
    pub fungi_by_category: FungiByCategoryProfile,

    /// Plants ranked by fungal connectivity
    pub hub_plants: Vec<PlantFungalHub>,
}

/// Analyze fungi network for a guild
///
/// Takes M5Result with fungi_counts and guild DataFrames to build detailed profile.
pub fn analyze_fungi_network(
    m5: &M5Result,
    guild_plants: &DataFrame,
    fungi_df: &DataFrame,
) -> Result<Option<FungiNetworkProfile>> {
    let n_plants = guild_plants.height();

    if m5.fungi_counts.is_empty() {
        return Ok(None);
    }

    // Step 1: Categorize all fungi by querying fungi_df and get pathogen set
    let (category_map, pathogen_set) = categorize_fungi(fungi_df, guild_plants)?;

    // Step 2: Build fungus-to-plants mapping by inverting fungi_counts
    let fungus_to_plants = build_fungus_to_plants_mapping(fungi_df, guild_plants, &category_map)?;

    // Step 3: Build shared fungi list (2+ plants)
    let mut shared_fungi: Vec<SharedFungus> = fungus_to_plants
        .iter()
        .filter(|(_, (plants, _))| plants.len() >= 2)
        .map(|(fungus_name, (plants, category))| SharedFungus {
            fungus_name: fungus_name.clone(),
            plant_count: plants.len(),
            plants: plants.clone(),
            category: category.clone(),
            network_contribution: plants.len() as f64 / n_plants as f64,
            is_dual_lifestyle: pathogen_set.contains(fungus_name),
        })
        .collect();

    // Sort by network contribution desc, then name asc
    shared_fungi.sort_by(|a, b| {
        b.network_contribution
            .partial_cmp(&a.network_contribution)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.fungus_name.cmp(&b.fungus_name))
    });

    // Step 4: Build top 10 fungi list
    let mut top_fungi: Vec<TopFungus> = fungus_to_plants
        .iter()
        .map(|(fungus_name, (plants, category))| TopFungus {
            fungus_name: fungus_name.clone(),
            plant_count: plants.len(),
            plants: plants.clone(),
            category: category.clone(),
            network_contribution: plants.len() as f64 / n_plants as f64,
            is_dual_lifestyle: pathogen_set.contains(fungus_name),
        })
        .collect();

    // Sort by network contribution desc, then name asc
    top_fungi.sort_by(|a, b| {
        b.network_contribution
            .partial_cmp(&a.network_contribution)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.fungus_name.cmp(&b.fungus_name))
    });
    top_fungi.truncate(10);

    // Step 5: Count fungi by category
    let mut amf_count = 0;
    let mut emf_count = 0;
    let mut endophytic_count = 0;
    let mut saprotrophic_count = 0;

    for (_, (_, category)) in &fungus_to_plants {
        match category {
            FungusCategory::AMF => amf_count += 1,
            FungusCategory::EMF => emf_count += 1,
            FungusCategory::Endophytic => endophytic_count += 1,
            FungusCategory::Saprotrophic => saprotrophic_count += 1,
        }
    }

    // Step 6: Find top fungus per category
    let mut top_per_category = Vec::new();
    for cat in &[
        FungusCategory::AMF,
        FungusCategory::EMF,
        FungusCategory::Endophytic,
        FungusCategory::Saprotrophic,
    ] {
        if let Some((fungus_name, (plants, _))) = fungus_to_plants
            .iter()
            .filter(|(_, (_, category))| category == cat)
            .max_by_key(|(_, (plants, _))| plants.len())
        {
            top_per_category.push(TopFungusInCategory {
                category: cat.clone(),
                fungus_name: fungus_name.clone(),
                plant_count: plants.len(),
            });
        }
    }

    let fungi_by_category = FungiByCategoryProfile {
        amf_count,
        emf_count,
        endophytic_count,
        saprotrophic_count,
        top_per_category,
    };

    // Step 7: Build plant fungal hubs
    let hub_plants = build_plant_fungal_hubs(guild_plants, fungi_df, &category_map)?;

    Ok(Some(FungiNetworkProfile {
        total_unique_fungi: fungus_to_plants.len(),
        shared_fungi,
        top_fungi,
        fungi_by_category,
        hub_plants,
    }))
}

/// Categorize fungi by querying which column they appear in
/// Returns (category_map, pathogen_set) where pathogen_set contains all pathogenic fungi
fn categorize_fungi(
    fungi_df: &DataFrame,
    guild_plants: &DataFrame,
) -> Result<(FxHashMap<String, FungusCategory>, rustc_hash::FxHashSet<String>)> {
    let mut category_map: FxHashMap<String, FungusCategory> = FxHashMap::default();
    let mut pathogen_set: rustc_hash::FxHashSet<String> = rustc_hash::FxHashSet::default();

    // Use wfo_taxon_id to match against fungi_df's plant_wfo_id
    let plant_ids = guild_plants.column("wfo_taxon_id")?.str()?;
    let guild_plant_set: rustc_hash::FxHashSet<String> = plant_ids
        .into_iter()
        .filter_map(|opt| opt.map(|s| s.to_string()))
        .collect();

    let fungi_plant_col = fungi_df.column("plant_wfo_id")?.str()?;

    // FIRST PASS: Build pathogen set from pathogenic_fungi column
    for idx in 0..fungi_df.height() {
        if let Some(plant_id) = fungi_plant_col.get(idx) {
            if !guild_plant_set.contains(plant_id) {
                continue; // Not in guild
            }

            // Extract pathogens for this plant
            if let Ok(col) = fungi_df.column("pathogenic_fungi") {
                if let Ok(list_col) = col.list() {
                    if let Some(list_series) = list_col.get_as_series(idx) {
                        if let Ok(str_series) = list_series.str() {
                            for fungus_opt in str_series.into_iter() {
                                if let Some(fungus) = fungus_opt {
                                    if !fungus.trim().is_empty() {
                                        pathogen_set.insert(fungus.trim().to_string());
                                    }
                                }
                            }
                        }
                    }
                } else if let Ok(str_col) = col.str() {
                    // Fallback: pipe-separated string (legacy format)
                    if let Some(fungi_str) = str_col.get(idx) {
                        if !fungi_str.is_empty() {
                            for fungus in fungi_str.split('|').filter(|s| !s.trim().is_empty()) {
                                pathogen_set.insert(fungus.trim().to_string());
                            }
                        }
                    }
                }
            }
        }
    }

    // SECOND PASS: Categorize beneficial fungi
    let columns = [
        ("amf_fungi", FungusCategory::AMF),
        ("emf_fungi", FungusCategory::EMF),
        ("endophytic_fungi", FungusCategory::Endophytic),
        ("saprotrophic_fungi", FungusCategory::Saprotrophic),
    ];

    for idx in 0..fungi_df.height() {
        if let Some(plant_id) = fungi_plant_col.get(idx) {
            if !guild_plant_set.contains(plant_id) {
                continue; // Not in guild
            }

            for (col_name, category) in &columns {
                if let Ok(col) = fungi_df.column(col_name) {
                    // Handle list column (Phase 0-4 format)
                    if let Ok(list_col) = col.list() {
                        if let Some(list_series) = list_col.get_as_series(idx) {
                            if let Ok(str_series) = list_series.str() {
                                for org_opt in str_series.into_iter() {
                                    if let Some(fungus) = org_opt {
                                        if !fungus.trim().is_empty() {
                                            category_map
                                                .entry(fungus.trim().to_string())
                                                .or_insert(category.clone());
                                        }
                                    }
                                }
                            }
                        }
                    } else if let Ok(str_col) = col.str() {
                        // Fallback: pipe-separated string (legacy format)
                        if let Some(fungi_str) = str_col.get(idx) {
                            if !fungi_str.is_empty() {
                                for fungus in fungi_str.split('|').filter(|s| !s.trim().is_empty()) {
                                    category_map
                                        .entry(fungus.trim().to_string())
                                        .or_insert(category.clone());
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Ok((category_map, pathogen_set))
}

/// Build fungus-to-plants mapping with categories
fn build_fungus_to_plants_mapping(
    fungi_df: &DataFrame,
    guild_plants: &DataFrame,
    category_map: &FxHashMap<String, FungusCategory>,
) -> Result<FxHashMap<String, (Vec<String>, FungusCategory)>> {
    let mut fungus_to_plants: FxHashMap<String, (Vec<String>, FungusCategory)> = FxHashMap::default();

    // Use wfo_taxon_id to match against fungi_df's plant_wfo_id
    let plant_ids = guild_plants.column("wfo_taxon_id")?.str()?;
    let guild_plant_set: rustc_hash::FxHashSet<String> = plant_ids
        .into_iter()
        .filter_map(|opt| opt.map(|s| s.to_string()))
        .collect();

    let fungi_plant_col = fungi_df.column("plant_wfo_id")?.str()?;

    let columns = ["amf_fungi", "emf_fungi", "endophytic_fungi", "saprotrophic_fungi"];

    for idx in 0..fungi_df.height() {
        if let Some(plant_id) = fungi_plant_col.get(idx) {
            if !guild_plant_set.contains(plant_id) {
                continue;
            }

            for col_name in &columns {
                if let Ok(col) = fungi_df.column(col_name) {
                    // Handle list column (Phase 0-4 format)
                    if let Ok(list_col) = col.list() {
                        if let Some(list_series) = list_col.get_as_series(idx) {
                            if let Ok(str_series) = list_series.str() {
                                for org_opt in str_series.into_iter() {
                                    if let Some(fungus) = org_opt {
                                        let fungus = fungus.trim();
                                        if !fungus.is_empty() {
                                            if let Some(category) = category_map.get(fungus) {
                                                let entry = fungus_to_plants
                                                    .entry(fungus.to_string())
                                                    .or_insert((Vec::new(), category.clone()));
                                                if !entry.0.contains(&plant_id.to_string()) {
                                                    entry.0.push(plant_id.to_string());
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else if let Ok(str_col) = col.str() {
                        // Fallback: pipe-separated string (legacy format)
                        if let Some(fungi_str) = str_col.get(idx) {
                            if !fungi_str.is_empty() {
                                for fungus in fungi_str.split('|').filter(|s| !s.trim().is_empty()) {
                                    let fungus = fungus.trim();
                                    if let Some(category) = category_map.get(fungus) {
                                        let entry = fungus_to_plants
                                            .entry(fungus.to_string())
                                            .or_insert((Vec::new(), category.clone()));
                                        if !entry.0.contains(&plant_id.to_string()) {
                                            entry.0.push(plant_id.to_string());
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Sort plant lists for deterministic output
    for (plants, _) in fungus_to_plants.values_mut() {
        plants.sort();
    }

    Ok(fungus_to_plants)
}

/// Build plant display map (WFO ID -> (scientific, vernacular))
fn build_plant_display_map(guild_plants: &DataFrame) -> Result<FxHashMap<String, (String, String)>> {
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

/// Build plant fungal hubs ranked by total fungi count
fn build_plant_fungal_hubs(
    guild_plants: &DataFrame,
    fungi_df: &DataFrame,
    category_map: &FxHashMap<String, FungusCategory>,
) -> Result<Vec<PlantFungalHub>> {
    // Get plant display map (scientific + vernacular)
    let plant_display_map = build_plant_display_map(guild_plants)?;

    // Get ALL guild plant IDs
    let plant_ids = guild_plants.column("wfo_taxon_id")?.str()?;
    let all_guild_plants: Vec<String> = plant_ids
        .into_iter()
        .filter_map(|opt| opt.map(|s| s.to_string()))
        .collect();

    let guild_plant_set: rustc_hash::FxHashSet<String> = all_guild_plants.iter().cloned().collect();

    let mut plant_fungi_counts: FxHashMap<String, (usize, usize, usize, usize, usize)> =
        FxHashMap::default();

    let fungi_plant_col = fungi_df.column("plant_wfo_id")?.str()?;
    let columns = ["amf_fungi", "emf_fungi", "endophytic_fungi", "saprotrophic_fungi"];

    for idx in 0..fungi_df.height() {
        if let Some(plant_id) = fungi_plant_col.get(idx) {
            if !guild_plant_set.contains(plant_id) {
                continue;
            }

            let entry = plant_fungi_counts
                .entry(plant_id.to_string())
                .or_insert((0, 0, 0, 0, 0));

            for col_name in &columns {
                if let Ok(col) = fungi_df.column(col_name) {
                    // Handle list column (Phase 0-4 format)
                    if let Ok(list_col) = col.list() {
                        if let Some(list_series) = list_col.get_as_series(idx) {
                            if let Ok(str_series) = list_series.str() {
                                for org_opt in str_series.into_iter() {
                                    if let Some(fungus) = org_opt {
                                        let fungus = fungus.trim();
                                        if !fungus.is_empty() {
                                            entry.0 += 1; // total
                                            if let Some(category) = category_map.get(fungus) {
                                                match category {
                                                    FungusCategory::AMF => entry.1 += 1,
                                                    FungusCategory::EMF => entry.2 += 1,
                                                    FungusCategory::Endophytic => entry.3 += 1,
                                                    FungusCategory::Saprotrophic => entry.4 += 1,
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else if let Ok(str_col) = col.str() {
                        // Fallback: pipe-separated string (legacy format)
                        if let Some(fungi_str) = str_col.get(idx) {
                            if !fungi_str.is_empty() {
                                for fungus in fungi_str.split('|').filter(|s| !s.trim().is_empty()) {
                                    let fungus = fungus.trim();
                                    entry.0 += 1; // total
                                    if let Some(category) = category_map.get(fungus) {
                                        match category {
                                            FungusCategory::AMF => entry.1 += 1,
                                            FungusCategory::EMF => entry.2 += 1,
                                            FungusCategory::Endophytic => entry.3 += 1,
                                            FungusCategory::Saprotrophic => entry.4 += 1,
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Build hubs for ALL guild plants (including zeros)
    let mut hubs: Vec<PlantFungalHub> = all_guild_plants
        .into_iter()
        .map(|plant_id| {
            let (total, amf, emf, endo, sapro) = plant_fungi_counts
                .get(&plant_id)
                .cloned()
                .unwrap_or((0, 0, 0, 0, 0));

            let (scientific, vernacular) = plant_display_map
                .get(&plant_id)
                .cloned()
                .unwrap_or_else(|| (plant_id.clone(), String::new()));

            PlantFungalHub {
                plant_name: scientific,
                plant_vernacular: vernacular,
                fungus_count: total,
                amf_count: amf,
                emf_count: emf,
                endophytic_count: endo,
                saprotrophic_count: sapro,
                has_data: total > 0,
            }
        })
        .collect();

    // Sort by total count desc, then name asc
    hubs.sort_by(|a, b| {
        b.fungus_count
            .cmp(&a.fungus_count)
            .then_with(|| a.plant_name.cmp(&b.plant_name))
    });

    Ok(hubs)
}
