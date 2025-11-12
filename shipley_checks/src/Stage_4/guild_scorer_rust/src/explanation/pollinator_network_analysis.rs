//! Pollinator Network Profile Analysis
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

/// Pollinator taxonomic categories
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum PollinatorCategory {
    Bees,
    Butterflies,
    Moths,
    Flies,
    Beetles,
    Wasps,
    Birds,
    Bats,
    Other,
}

impl PollinatorCategory {
    /// Categorize a pollinator based on its name
    pub fn from_name(name: &str) -> Self {
        let name_lower = name.to_lowercase();

        // Bees (Apoidea)
        if name_lower.contains("apis") || name_lower.contains("bombus") ||
           name_lower.contains("anthophora") || name_lower.contains("xylocopa") ||
           name_lower.contains("osmia") || name_lower.contains("megachile") ||
           name_lower.contains("andrena") || name_lower.contains("halictus") ||
           name_lower.contains("lasioglossum") || name_lower.contains("bee") {
            return PollinatorCategory::Bees;
        }

        // Butterflies (Lepidoptera - Rhopalocera)
        if name_lower.contains("papilio") || name_lower.contains("pieris") ||
           name_lower.contains("vanessa") || name_lower.contains("danaus") ||
           name_lower.contains("colias") || name_lower.contains("lycaena") ||
           name_lower.contains("polyommatus") || name_lower.contains("butterfly") {
            return PollinatorCategory::Butterflies;
        }

        // Moths (Lepidoptera - Heterocera)
        if name_lower.contains("moth") || name_lower.contains("sphinx") ||
           name_lower.contains("manduca") || name_lower.contains("hyles") {
            return PollinatorCategory::Moths;
        }

        // Flies (Diptera)
        if name_lower.contains("fly") || name_lower.contains("syrphus") ||
           name_lower.contains("eristalis") || name_lower.contains("musca") ||
           name_lower.contains("calliphora") || name_lower.contains("drosophila") ||
           name_lower.contains("diptera") {
            return PollinatorCategory::Flies;
        }

        // Beetles (Coleoptera)
        if name_lower.contains("beetle") || name_lower.contains("cetonia") ||
           name_lower.contains("meligethes") || name_lower.contains("coleoptera") {
            return PollinatorCategory::Beetles;
        }

        // Wasps (Hymenoptera - non-Apoidea)
        if name_lower.contains("wasp") || name_lower.contains("vespula") ||
           name_lower.contains("vespa") || name_lower.contains("polistes") {
            return PollinatorCategory::Wasps;
        }

        // Birds
        if name_lower.contains("bird") || name_lower.contains("hummingbird") ||
           name_lower.contains("trochilidae") {
            return PollinatorCategory::Birds;
        }

        // Bats
        if name_lower.contains("bat") || name_lower.contains("chiroptera") {
            return PollinatorCategory::Bats;
        }

        PollinatorCategory::Other
    }

    pub fn display_name(&self) -> &str {
        match self {
            PollinatorCategory::Bees => "Bees",
            PollinatorCategory::Butterflies => "Butterflies",
            PollinatorCategory::Moths => "Moths",
            PollinatorCategory::Flies => "Flies",
            PollinatorCategory::Beetles => "Beetles",
            PollinatorCategory::Wasps => "Wasps",
            PollinatorCategory::Birds => "Birds",
            PollinatorCategory::Bats => "Bats",
            PollinatorCategory::Other => "Other",
        }
    }
}

/// Shared pollinator with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharedPollinator {
    pub pollinator_name: String,
    pub plant_count: usize,
    pub plants: Vec<String>,
    pub category: PollinatorCategory,
    pub network_contribution: f64,
}

/// Top pollinator by interaction count
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopPollinator {
    pub pollinator_name: String,
    pub plant_count: usize,
    pub category: PollinatorCategory,
    pub network_contribution: f64,
}

/// Pollinators grouped by category
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PollinatorsByCategoryProfile {
    pub bees_count: usize,
    pub butterflies_count: usize,
    pub moths_count: usize,
    pub flies_count: usize,
    pub beetles_count: usize,
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
    pub bees_count: usize,
    pub butterflies_count: usize,
    pub moths_count: usize,
    pub flies_count: usize,
    pub beetles_count: usize,
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
) -> Result<Option<PollinatorNetworkProfile>> {
    let n_plants = guild_plants.height();

    if m7.pollinator_counts.is_empty() {
        return Ok(None);
    }

    // Step 1: Categorize all pollinators
    let category_map = categorize_pollinators(organisms_df, guild_plants)?;

    // Step 2: Build pollinator-to-plants mapping
    let pollinator_to_plants = build_pollinator_to_plants_mapping(
        organisms_df,
        guild_plants,
        &category_map,
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
                .unwrap_or(PollinatorCategory::Other);
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
    let mut category_counts: FxHashMap<PollinatorCategory, usize> = FxHashMap::default();
    for category in category_map.values() {
        *category_counts.entry(category.clone()).or_insert(0) += 1;
    }

    // Step 6: Top pollinators per category (top 2 per category)
    let mut category_tops: FxHashMap<PollinatorCategory, Vec<TopPollinator>> = FxHashMap::default();
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
    let hub_plants = build_plant_pollinator_hubs(organisms_df, guild_plants, &category_map)?;

    let pollinators_by_category = PollinatorsByCategoryProfile {
        bees_count: *category_counts.get(&PollinatorCategory::Bees).unwrap_or(&0),
        butterflies_count: *category_counts.get(&PollinatorCategory::Butterflies).unwrap_or(&0),
        moths_count: *category_counts.get(&PollinatorCategory::Moths).unwrap_or(&0),
        flies_count: *category_counts.get(&PollinatorCategory::Flies).unwrap_or(&0),
        beetles_count: *category_counts.get(&PollinatorCategory::Beetles).unwrap_or(&0),
        wasps_count: *category_counts.get(&PollinatorCategory::Wasps).unwrap_or(&0),
        birds_count: *category_counts.get(&PollinatorCategory::Birds).unwrap_or(&0),
        bats_count: *category_counts.get(&PollinatorCategory::Bats).unwrap_or(&0),
        other_count: *category_counts.get(&PollinatorCategory::Other).unwrap_or(&0),
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
) -> Result<FxHashMap<String, PollinatorCategory>> {
    // Use wfo_taxon_id to match against organisms_df's plant_wfo_id
    let plant_ids = guild_plants.column("wfo_taxon_id")?.str()?;
    let guild_plant_set: FxHashSet<String> = plant_ids
        .into_iter()
        .filter_map(|opt| opt.map(|s| s.to_string()))
        .collect();

    let organisms_plant_col = organisms_df.column("plant_wfo_id")?.str()?;
    let pollinators_col = organisms_df.column("pollinators")?.str()?;
    let flower_visitors_col = organisms_df.column("flower_visitors")?.str()?;

    let mut category_map: FxHashMap<String, PollinatorCategory> = FxHashMap::default();

    for idx in 0..organisms_df.height() {
        let plant_id_opt = organisms_plant_col.get(idx);
        if let Some(plant_id) = plant_id_opt {
            if !guild_plant_set.contains(plant_id) {
                continue;
            }

            // Process pollinators column
            if let Some(pollinators_str) = pollinators_col.get(idx) {
                if !pollinators_str.is_empty() {
                    for pol_name in pollinators_str.split(',') {
                        let pol_name = pol_name.trim().to_string();
                        if !pol_name.is_empty() {
                            category_map.entry(pol_name.clone())
                                .or_insert_with(|| PollinatorCategory::from_name(&pol_name));
                        }
                    }
                }
            }

            // Process flower_visitors column
            if let Some(visitors_str) = flower_visitors_col.get(idx) {
                if !visitors_str.is_empty() {
                    for pol_name in visitors_str.split(',') {
                        let pol_name = pol_name.trim().to_string();
                        if !pol_name.is_empty() {
                            category_map.entry(pol_name.clone())
                                .or_insert_with(|| PollinatorCategory::from_name(&pol_name));
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
    category_map: &FxHashMap<String, PollinatorCategory>,
) -> Result<FxHashMap<String, (FxHashSet<String>, PollinatorCategory)>> {
    // Use wfo_taxon_id to match against organisms_df's plant_wfo_id
    let plant_ids = guild_plants.column("wfo_taxon_id")?.str()?;
    let guild_plant_set: FxHashSet<String> = plant_ids
        .into_iter()
        .filter_map(|opt| opt.map(|s| s.to_string()))
        .collect();

    let organisms_plant_col = organisms_df.column("plant_wfo_id")?.str()?;
    let pollinators_col = organisms_df.column("pollinators")?.str()?;
    let flower_visitors_col = organisms_df.column("flower_visitors")?.str()?;

    let mut pollinator_to_plants: FxHashMap<String, (FxHashSet<String>, PollinatorCategory)> =
        FxHashMap::default();

    for idx in 0..organisms_df.height() {
        let plant_id_opt = organisms_plant_col.get(idx);
        if let Some(plant_id) = plant_id_opt {
            if !guild_plant_set.contains(plant_id) {
                continue;
            }

            let plant_id = plant_id.to_string();

            // Process pollinators column
            if let Some(pollinators_str) = pollinators_col.get(idx) {
                if !pollinators_str.is_empty() {
                    for pol_name in pollinators_str.split(',') {
                        let pol_name = pol_name.trim().to_string();
                        if !pol_name.is_empty() {
                            let category = category_map.get(&pol_name).cloned()
                                .unwrap_or(PollinatorCategory::Other);
                            pollinator_to_plants.entry(pol_name)
                                .or_insert_with(|| (FxHashSet::default(), category))
                                .0.insert(plant_id.clone());
                        }
                    }
                }
            }

            // Process flower_visitors column
            if let Some(visitors_str) = flower_visitors_col.get(idx) {
                if !visitors_str.is_empty() {
                    for pol_name in visitors_str.split(',') {
                        let pol_name = pol_name.trim().to_string();
                        if !pol_name.is_empty() {
                            let category = category_map.get(&pol_name).cloned()
                                .unwrap_or(PollinatorCategory::Other);
                            pollinator_to_plants.entry(pol_name)
                                .or_insert_with(|| (FxHashSet::default(), category))
                                .0.insert(plant_id.clone());
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
    category_map: &FxHashMap<String, PollinatorCategory>,
) -> Result<Vec<PlantPollinatorHub>> {
    // Use wfo_taxon_id to match against organisms_df's plant_wfo_id
    let plant_ids = guild_plants.column("wfo_taxon_id")?.str()?;
    let guild_plant_set: FxHashSet<String> = plant_ids
        .into_iter()
        .filter_map(|opt| opt.map(|s| s.to_string()))
        .collect();

    // Also need plant names for display (wfo_taxon_id -> wfo_taxon_name mapping)
    let plant_id_col = guild_plants.column("wfo_taxon_id")?.str()?;
    let plant_name_col = guild_plants.column("wfo_taxon_name")?.str()?;
    let mut id_to_name_map: FxHashMap<String, String> = FxHashMap::default();
    for idx in 0..guild_plants.height() {
        if let (Some(id), Some(name)) = (plant_id_col.get(idx), plant_name_col.get(idx)) {
            id_to_name_map.insert(id.to_string(), name.to_string());
        }
    }

    let organisms_plant_col = organisms_df.column("plant_wfo_id")?.str()?;
    let pollinators_col = organisms_df.column("pollinators")?.str()?;
    let flower_visitors_col = organisms_df.column("flower_visitors")?.str()?;

    // Map: plant_id -> (total, bees, butterflies, moths, flies, beetles, wasps, birds, bats, other)
    let mut plant_pollinator_counts: FxHashMap<String, (usize, usize, usize, usize, usize, usize, usize, usize, usize, usize)> =
        FxHashMap::default();

    for idx in 0..organisms_df.height() {
        let plant_id_opt = organisms_plant_col.get(idx);
        if let Some(plant_id) = plant_id_opt {
            if !guild_plant_set.contains(plant_id) {
                continue;
            }

            let plant_id = plant_id.to_string();
            let entry = plant_pollinator_counts.entry(plant_id.clone())
                .or_insert((0, 0, 0, 0, 0, 0, 0, 0, 0, 0));

            let mut pollinators_seen: FxHashSet<String> = FxHashSet::default();

            // Process pollinators column
            if let Some(pollinators_str) = pollinators_col.get(idx) {
                if !pollinators_str.is_empty() {
                    for pol_name in pollinators_str.split(',') {
                        let pol_name = pol_name.trim().to_string();
                        if !pol_name.is_empty() && !pollinators_seen.contains(&pol_name) {
                            pollinators_seen.insert(pol_name.clone());
                            let category = category_map.get(&pol_name).cloned()
                                .unwrap_or(PollinatorCategory::Other);
                            entry.0 += 1; // total
                            match category {
                                PollinatorCategory::Bees => entry.1 += 1,
                                PollinatorCategory::Butterflies => entry.2 += 1,
                                PollinatorCategory::Moths => entry.3 += 1,
                                PollinatorCategory::Flies => entry.4 += 1,
                                PollinatorCategory::Beetles => entry.5 += 1,
                                PollinatorCategory::Wasps => entry.6 += 1,
                                PollinatorCategory::Birds => entry.7 += 1,
                                PollinatorCategory::Bats => entry.8 += 1,
                                PollinatorCategory::Other => entry.9 += 1,
                            }
                        }
                    }
                }
            }

            // Process flower_visitors column
            if let Some(visitors_str) = flower_visitors_col.get(idx) {
                if !visitors_str.is_empty() {
                    for pol_name in visitors_str.split(',') {
                        let pol_name = pol_name.trim().to_string();
                        if !pol_name.is_empty() && !pollinators_seen.contains(&pol_name) {
                            pollinators_seen.insert(pol_name.clone());
                            let category = category_map.get(&pol_name).cloned()
                                .unwrap_or(PollinatorCategory::Other);
                            entry.0 += 1; // total
                            match category {
                                PollinatorCategory::Bees => entry.1 += 1,
                                PollinatorCategory::Butterflies => entry.2 += 1,
                                PollinatorCategory::Moths => entry.3 += 1,
                                PollinatorCategory::Flies => entry.4 += 1,
                                PollinatorCategory::Beetles => entry.5 += 1,
                                PollinatorCategory::Wasps => entry.6 += 1,
                                PollinatorCategory::Birds => entry.7 += 1,
                                PollinatorCategory::Bats => entry.8 += 1,
                                PollinatorCategory::Other => entry.9 += 1,
                            }
                        }
                    }
                }
            }
        }
    }

    let mut hubs: Vec<PlantPollinatorHub> = plant_pollinator_counts
        .into_iter()
        .map(|(plant_id, (total, bees, butterflies, moths, flies, beetles, wasps, birds, bats, other))| {
            PlantPollinatorHub {
                plant_name: id_to_name_map.get(&plant_id).cloned().unwrap_or(plant_id),
                pollinator_count: total,
                bees_count: bees,
                butterflies_count: butterflies,
                moths_count: moths,
                flies_count: flies,
                beetles_count: beetles,
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
