//! Pollinator Network Profile Analysis (M7)
//!
//! Analyzes pollinator networks to provide qualitative information about:
//! - Shared pollinators and their connectivity
//! - Top pollinators by interaction counts
//! - Pollinator diversity by taxonomic group
//! - Network hubs (plants with most pollinator associations)

use anyhow::Result;
use polars::prelude::*;
use rustc_hash::{FxHashMap, FxHashSet};
use serde::{Deserialize, Serialize};

use crate::metrics::M7Result;
use crate::explanation::unified_taxonomy::{OrganismCategory, OrganismRole};

/// Shared pollinator with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharedPollinator {
    pub pollinator_name: String,
    pub plant_count: usize,
    pub plants: Vec<String>,
    pub category: OrganismCategory,
    pub network_contribution: f64,
}

/// Top pollinator by interaction count
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopPollinator {
    pub pollinator_name: String,
    pub plant_count: usize,
    pub category: OrganismCategory,
    pub network_contribution: f64,
}

/// Pollinators grouped by category (expanded to match OrganismCategory variants relevant to pollinators)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PollinatorsByCategoryProfile {
    pub honey_bees_count: usize,
    pub bumblebees_count: usize,
    pub solitary_bees_count: usize,
    pub hover_flies_count: usize,
    pub muscid_flies_count: usize, // Mapped to Flies
    pub mosquitoes_count: usize,
    pub other_flies_count: usize,  // Mapped to Flies
    pub butterflies_count: usize,
    pub moths_count: usize,
    pub pollen_beetles_count: usize, // Mapped to Beetles
    pub other_beetles_count: usize,  // Mapped to Beetles
    pub wasps_count: usize,
    pub birds_count: usize,
    pub bats_count: usize,
    pub other_count: usize,
    pub top_per_category: Vec<TopPollinator>,
}

/// Plant with many pollinator associations (network hub)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlantPollinatorHub {
    pub plant_name: String,
    pub pollinator_count: usize,
    pub honey_bees_count: usize,
    pub bumblebees_count: usize,
    pub solitary_bees_count: usize,
    pub hover_flies_count: usize,
    pub muscid_flies_count: usize,
    pub mosquitoes_count: usize,
    pub other_flies_count: usize,
    pub butterflies_count: usize,
    pub moths_count: usize,
    pub pollen_beetles_count: usize,
    pub other_beetles_count: usize,
    pub wasps_count: usize,
    pub birds_count: usize,
    pub bats_count: usize,
    pub other_count: usize,
}

/// Complete pollinator network profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PollinatorNetworkProfile {
    pub total_unique_pollinators: usize,
    pub shared_pollinators: Vec<SharedPollinator>,
    pub top_pollinators: Vec<TopPollinator>,
    pub pollinators_by_category: PollinatorsByCategoryProfile,
    pub hub_plants: Vec<PlantPollinatorHub>,
}

/// Main analysis function
pub fn analyze_pollinator_network(
    m7: &M7Result,
    guild_plants: &DataFrame,
    organisms_df: &DataFrame,
    organism_categories: &FxHashMap<String, String>,
) -> Result<Option<PollinatorNetworkProfile>> {
    let n_plants = guild_plants.height();

    if m7.pollinator_counts.is_empty() {
        return Ok(None);
    }

    // Step 1: Categorize all pollinators
    let category_map = categorize_pollinators(organisms_df, guild_plants, organism_categories)?;

    // Step 2: Build pollinator-to-plants mapping
    let pollinator_to_plants = build_pollinator_to_plants_mapping(
        organisms_df,
        guild_plants,
        &category_map,
        organism_categories,
    )?;

    // Step 3: Build shared pollinators list (≥2 plants)
    let mut shared_pollinators: Vec<SharedPollinator> = pollinator_to_plants
        .iter()
        .filter(|(_, (plant_set, _))| plant_set.len() >= 2)
        .map(|(pol_name, (plant_set, category))| {
            let mut plants: Vec<String> = plant_set.iter().cloned().collect();
            plants.sort();
            SharedPollinator {
                pollinator_name: pol_name.clone(),
                plant_count: plant_set.len(),
                plants,
                category: category.clone(),
                network_contribution: plant_set.len() as f64 / n_plants as f64,
            }
        })
        .collect();

    // Sort by plant_count desc, then name asc
    shared_pollinators.sort_by(|a, b| {
        b.plant_count.cmp(&a.plant_count)
            .then_with(|| a.pollinator_name.cmp(&b.pollinator_name))
    });

    // Step 4: Build top pollinators (top 10 by plant count)
    let mut top_pollinators: Vec<TopPollinator> = m7.pollinator_counts
        .iter()
        .map(|(pol_name, &plant_count)| {
            let category = category_map.get(pol_name).cloned()
                .unwrap_or(OrganismCategory::Other);
            TopPollinator {
                pollinator_name: pol_name.clone(),
                plant_count,
                category,
                network_contribution: plant_count as f64 / n_plants as f64,
            }
        })
        .collect();

    top_pollinators.sort_by(|a, b| {
        b.plant_count.cmp(&a.plant_count)
            .then_with(|| a.pollinator_name.cmp(&b.pollinator_name))
    });
    top_pollinators.truncate(10);

    // Step 5: Count pollinators by category
    let mut category_counts: FxHashMap<OrganismCategory, usize> = FxHashMap::default();
    for category in category_map.values() {
        *category_counts.entry(category.clone()).or_insert(0) += 1;
    }

    // Step 6: Top pollinators per category (top 2 per category)
    let mut category_tops: FxHashMap<OrganismCategory, Vec<TopPollinator>> = FxHashMap::default();
    for pol in &top_pollinators {
        category_tops.entry(pol.category.clone())
            .or_insert_with(Vec::new)
            .push(pol.clone());
    }

    let mut top_per_category: Vec<TopPollinator> = Vec::new();
    for (_, mut pols) in category_tops {
        pols.truncate(2);
        top_per_category.extend(pols);
    }

    // Step 7: Build hub plants (plants with most pollinator associations)
    let hub_plants = build_plant_pollinator_hubs(organisms_df, guild_plants, &category_map, organism_categories)?;

    let pollinators_by_category = PollinatorsByCategoryProfile {
        honey_bees_count: *category_counts.get(&OrganismCategory::HoneyBees).unwrap_or(&0),
        bumblebees_count: *category_counts.get(&OrganismCategory::Bumblebees).unwrap_or(&0),
        solitary_bees_count: *category_counts.get(&OrganismCategory::SolitaryBees).unwrap_or(&0),
        hover_flies_count: *category_counts.get(&OrganismCategory::Hoverflies).unwrap_or(&0),
        muscid_flies_count: *category_counts.get(&OrganismCategory::Flies).unwrap_or(&0), // Map generic Flies to Muscid/Other bucket
        mosquitoes_count: *category_counts.get(&OrganismCategory::Mosquitoes).unwrap_or(&0),
        other_flies_count: 0, // Already counted in Flies
        butterflies_count: *category_counts.get(&OrganismCategory::Butterflies).unwrap_or(&0),
        moths_count: *category_counts.get(&OrganismCategory::Moths).unwrap_or(&0),
        pollen_beetles_count: *category_counts.get(&OrganismCategory::Beetles).unwrap_or(&0), // Map generic Beetles
        other_beetles_count: 0, // Already counted in Beetles
        wasps_count: *category_counts.get(&OrganismCategory::Wasps).unwrap_or(&0),
        birds_count: *category_counts.get(&OrganismCategory::Birds).unwrap_or(&0),
        bats_count: *category_counts.get(&OrganismCategory::Bats).unwrap_or(&0),
        other_count: *category_counts.get(&OrganismCategory::Other).unwrap_or(&0) +
                     *category_counts.get(&OrganismCategory::OtherPollinators).unwrap_or(&0),
        top_per_category,
    };

    Ok(Some(PollinatorNetworkProfile {
        total_unique_pollinators: m7.pollinator_counts.len(),
        shared_pollinators,
        top_pollinators,
        pollinators_by_category,
        hub_plants,
    }))
}

/// Categorize all pollinators in the dataset for guild plants
fn categorize_pollinators(
    organisms_df: &DataFrame,
    guild_plants: &DataFrame,
    organism_categories: &FxHashMap<String, String>,
) -> Result<FxHashMap<String, OrganismCategory>> {
    // Use wfo_taxon_id to match against organisms_df's plant_wfo_id
    let plant_ids = guild_plants.column("wfo_taxon_id")?.str()?;
    let guild_plant_set: FxHashSet<String> = plant_ids
        .into_iter()
        .filter_map(|opt| opt.map(|s| s.to_string()))
        .collect();

    let organisms_plant_col = organisms_df.column("plant_wfo_id")?.str()?;
    // Don't force .str() here - might be List type
    let pollinators_col_generic = organisms_df.column("pollinators")?;
    let pollinators_str_col = pollinators_col_generic.str().ok();
    let pollinators_list_col = pollinators_col_generic.list().ok();
    
    let mut category_map: FxHashMap<String, OrganismCategory> = FxHashMap::default();

    for idx in 0..organisms_df.height() {
        let plant_id_opt = organisms_plant_col.get(idx);
        if let Some(plant_id) = plant_id_opt {
            if !guild_plant_set.contains(plant_id) {
                continue;
            }

            // Helper to categorize
            let mut categorize = |pol_name: &str| {
                if !pol_name.is_empty() {
                    category_map.entry(pol_name.to_string())
                        .or_insert_with(|| OrganismCategory::from_name(pol_name, organism_categories, Some(OrganismRole::Pollinator)));
                }
            };

            // Process pollinators column (Legacy String Format)
            if let Some(col) = pollinators_str_col {
                if let Some(pollinators_str) = col.get(idx) {
                    if !pollinators_str.is_empty() {
                        for pol_name in pollinators_str.split(',') {
                            categorize(pol_name.trim());
                        }
                    }
                }
            }
            
            // Process pollinators column (List Format - Phase 0-4)
            if let Some(col) = pollinators_list_col {
                if let Some(list_series) = col.get_as_series(idx) {
                    if let Ok(str_series) = list_series.str() {
                        for pol_opt in str_series.into_iter() {
                            if let Some(pol_name) = pol_opt {
                                categorize(pol_name);
                            }
                        }
                    }
                }
            }
        }
    }

    Ok(category_map)
}

/// Build mapping from pollinator to set of plants (with category)
fn build_pollinator_to_plants_mapping(
    organisms_df: &DataFrame,
    guild_plants: &DataFrame,
    category_map: &FxHashMap<String, OrganismCategory>,
    organism_categories: &FxHashMap<String, String>,
) -> Result<FxHashMap<String, (FxHashSet<String>, OrganismCategory)>> {
    let plant_ids = guild_plants.column("wfo_taxon_id")?.str()?;
    let guild_plant_set: FxHashSet<String> = plant_ids
        .into_iter()
        .filter_map(|opt| opt.map(|s| s.to_string()))
        .collect();

    let organisms_plant_col = organisms_df.column("plant_wfo_id")?.str()?;
    // Don't force .str() here - might be List type
    let pollinators_col_generic = organisms_df.column("pollinators")?;
    let pollinators_str_col = pollinators_col_generic.str().ok();
    let pollinators_list_col = pollinators_col_generic.list().ok();
    
    let mut pollinator_to_plants: FxHashMap<String, (FxHashSet<String>, OrganismCategory)> =
        FxHashMap::default();

    for idx in 0..organisms_df.height() {
        let plant_id_opt = organisms_plant_col.get(idx);
        if let Some(plant_id) = plant_id_opt {
            if !guild_plant_set.contains(plant_id) {
                continue;
            }

            let plant_id = plant_id.to_string();

            let mut process = |pol_name: &str| {
                 if !pol_name.is_empty() {
                    let category = category_map.get(pol_name).cloned()
                        .unwrap_or_else(|| OrganismCategory::from_name(pol_name, organism_categories, Some(OrganismRole::Pollinator)));
                    pollinator_to_plants.entry(pol_name.to_string())
                        .or_insert_with(|| (FxHashSet::default(), category))
                        .0.insert(plant_id.clone());
                }
            };

            if let Some(col) = pollinators_str_col {
                if let Some(pollinators_str) = col.get(idx) {
                    if !pollinators_str.is_empty() {
                        for pol_name in pollinators_str.split(',') {
                            process(pol_name.trim());
                        }
                    }
                }
            }
            
            if let Some(col) = pollinators_list_col {
                if let Some(list_series) = col.get_as_series(idx) {
                    if let Ok(str_series) = list_series.str() {
                        for pol_opt in str_series.into_iter() {
                            if let Some(pol_name) = pol_opt {
                                process(pol_name);
                            }
                        }
                    }
                }
            }
        }
    }

    Ok(pollinator_to_plants)
}

/// Build list of hub plants with high pollinator connectivity
fn build_plant_pollinator_hubs(
    organisms_df: &DataFrame,
    guild_plants: &DataFrame,
    category_map: &FxHashMap<String, OrganismCategory>,
    organism_categories: &FxHashMap<String, String>,
) -> Result<Vec<PlantPollinatorHub>> {
    // ... (same setup as before) ...
    let plant_ids = guild_plants.column("wfo_taxon_id")?.str()?;
    let guild_plant_set: FxHashSet<String> = plant_ids
        .into_iter()
        .filter_map(|opt| opt.map(|s| s.to_string()))
        .collect();

    let plant_id_col = guild_plants.column("wfo_taxon_id")?.str()?;
    let plant_name_col = guild_plants.column("wfo_taxon_name")?.str()?;
    let mut id_to_name_map: FxHashMap<String, String> = FxHashMap::default();
    for idx in 0..guild_plants.height() {
        if let (Some(id), Some(name)) = (plant_id_col.get(idx), plant_name_col.get(idx)) {
            id_to_name_map.insert(id.to_string(), name.to_string());
        }
    }

    let organisms_plant_col = organisms_df.column("plant_wfo_id")?.str()?;
    // Don't force .str() here - might be List type
    let pollinators_col_generic = organisms_df.column("pollinators")?;
    let pollinators_str_col = pollinators_col_generic.str().ok();
    let pollinators_list_col = pollinators_col_generic.list().ok();

    let mut plant_pollinator_counts: FxHashMap<String, (usize, usize, usize, usize, usize, usize, usize, usize, usize, usize, usize, usize, usize, usize, usize, usize)> =
        FxHashMap::default();

    for idx in 0..organisms_df.height() {
        let plant_id_opt = organisms_plant_col.get(idx);
        if let Some(plant_id) = plant_id_opt {
            if !guild_plant_set.contains(plant_id) {
                continue;
            }

            let plant_id = plant_id.to_string();
            let entry = plant_pollinator_counts.entry(plant_id.clone())
                .or_insert((0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0));

            let mut pollinators_seen: FxHashSet<String> = FxHashSet::default();

            let mut count_pollinator = |pol_name: &str| {
                if !pol_name.is_empty() && !pollinators_seen.contains(pol_name) {
                    pollinators_seen.insert(pol_name.to_string());
                    let category = category_map.get(pol_name).cloned()
                        .unwrap_or_else(|| OrganismCategory::from_name(pol_name, organism_categories, Some(OrganismRole::Pollinator)));
                    entry.0 += 1; // total
                    match category {
                        OrganismCategory::HoneyBees => entry.1 += 1,
                        OrganismCategory::Bumblebees => entry.2 += 1,
                        OrganismCategory::SolitaryBees => entry.3 += 1,
                        OrganismCategory::Hoverflies => entry.4 += 1,
                        OrganismCategory::Flies => entry.5 += 1, // Muscid/Other Flies
                        OrganismCategory::Mosquitoes => entry.6 += 1,
                        // OtherFlies merged into Flies (entry.5) or Other (entry.7)
                        // Struct has 16 fields (0..15). 7 is "other_flies". 
                        // I will map Flies to 5 (Muscid) and 7 (OtherFlies) -> just put all in 5 or 7?
                        // Let's put generic Flies in 7.
                        // Wait, I mapped Flies to 5 in `pollinators_by_category` above. Consistency needed.
                        // Above: `muscid_flies_count: ...Flies`. `other_flies_count: 0`.
                        // So I should put Flies in 5.
                        
                        OrganismCategory::Butterflies => entry.8 += 1,
                        OrganismCategory::Moths => entry.9 += 1,
                        OrganismCategory::Beetles => entry.10 += 1, // Pollen/Other Beetles
                        // 11 is OtherBeetles.
                        
                        OrganismCategory::Wasps => entry.12 += 1,
                        OrganismCategory::Birds => entry.13 += 1,
                        OrganismCategory::Bats => entry.14 += 1,
                        _ => entry.15 += 1,
                    }
                }
            };

            if let Some(col) = pollinators_str_col {
                if let Some(pollinators_str) = col.get(idx) {
                    if !pollinators_str.is_empty() {
                        for pol_name in pollinators_str.split(',') {
                            count_pollinator(pol_name.trim());
                        }
                    }
                }
            }
            
            if let Some(col) = pollinators_list_col {
                if let Some(list_series) = col.get_as_series(idx) {
                    if let Ok(str_series) = list_series.str() {
                        for pol_opt in str_series.into_iter() {
                            if let Some(pol_name) = pol_opt {
                                count_pollinator(pol_name);
                            }
                        }
                    }
                }
            }
        }
    }

    let mut hubs: Vec<PlantPollinatorHub> = plant_pollinator_counts
        .into_iter()
        .map(|(plant_id, (total, honey_bees, bumblebees, solitary_bees, hover_flies, muscid_flies, mosquitoes, other_flies, butterflies, moths, pollen_beetles, other_beetles, wasps, birds, bats, other))| {
            PlantPollinatorHub {
                plant_name: id_to_name_map.get(&plant_id).cloned().unwrap_or(plant_id),
                pollinator_count: total,
                honey_bees_count: honey_bees,
                bumblebees_count: bumblebees,
                solitary_bees_count: solitary_bees,
                hover_flies_count: hover_flies,
                muscid_flies_count: muscid_flies,
                mosquitoes_count: mosquitoes,
                other_flies_count: other_flies,
                butterflies_count: butterflies,
                moths_count: moths,
                pollen_beetles_count: pollen_beetles,
                other_beetles_count: other_beetles,
                wasps_count: wasps,
                birds_count: birds,
                bats_count: bats,
                other_count: other,
            }
        })
        .collect();

    // Sort by total count desc, then name asc
    hubs.sort_by(|a, b| {
        b.pollinator_count.cmp(&a.pollinator_count)
            .then_with(|| a.plant_name.cmp(&b.plant_name))
    });

    Ok(hubs)
}