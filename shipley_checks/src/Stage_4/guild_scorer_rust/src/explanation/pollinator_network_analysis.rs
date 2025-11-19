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

/// Pollinator taxonomic categories (expanded from 9 to 15 categories)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum PollinatorCategory {
    HoneyBees,
    Bumblebees,
    SolitaryBees,
    HoverFlies,
    MuscidFlies,
    Mosquitoes,
    OtherFlies,
    Butterflies,
    Moths,
    PollenBeetles,
    OtherBeetles,
    Wasps,
    Birds,
    Bats,
    Other,
}

impl PollinatorCategory {
    /// Categorize a pollinator based on its name
    /// Order matters: most specific patterns first to avoid false matches
    pub fn from_name(name: &str) -> Self {
        let name_lower = name.to_lowercase();

        // Honey Bees (Apis) - match word boundary
        if name_lower == "apis" || name_lower.starts_with("apis ") ||
           name_lower.contains(" apis ") || name_lower.ends_with(" apis") {
            return PollinatorCategory::HoneyBees;
        }

        // Bumblebees (Bombus)
        if name_lower.contains("bombus") {
            return PollinatorCategory::Bumblebees;
        }

        // Hover Flies (Syrphidae) - before general "fly"
        if name_lower.contains("syrph") || name_lower.contains("episyrphus") ||
           name_lower.contains("eristalis") || name_lower.contains("eupeodes") ||
           name_lower.contains("melanostoma") || name_lower.contains("platycheirus") ||
           name_lower.contains("sphaerophoria") || name_lower.contains("cheilosia") {
            return PollinatorCategory::HoverFlies;
        }

        // Mosquitoes (Culicidae) - before general "fly"
        if name_lower.contains("aedes") || name_lower.contains("culex") ||
           name_lower.contains("anopheles") || name_lower.contains("culiseta") ||
           name_lower.contains("mosquito") {
            return PollinatorCategory::Mosquitoes;
        }

        // Muscid Flies (Muscidae/Anthomyiidae) - before general "fly"
        if name_lower.contains("anthomyia") || name_lower.contains(" musca ") ||
           name_lower.starts_with("musca ") || name_lower.ends_with(" musca") ||
           name_lower == "musca" || name_lower.contains("fannia") ||
           name_lower.contains("phaonia") || name_lower.contains("delia") ||
           name_lower.contains("drymeia") || name_lower.contains("muscidae") {
            return PollinatorCategory::MuscidFlies;
        }

        // Solitary Bees (after Apis/Bombus, before general "bee")
        if name_lower.contains("andrena") || name_lower.contains("lasioglossum") ||
           name_lower.contains("halictus") || name_lower.contains("osmia") ||
           name_lower.contains("megachile") || name_lower.contains("ceratina") ||
           name_lower.contains("xylocopa") || name_lower.contains("anthophora") ||
           name_lower.contains("anthidium") || name_lower.contains("colletes") ||
           name_lower.contains("nomada") || name_lower.contains("agapostemon") ||
           name_lower.contains("amegilla") || name_lower.contains("trigona") ||
           name_lower.contains("melipona") || name_lower.contains("eulaema") ||
           name_lower.contains("epicharis") || name_lower.contains("augochlora") ||
           name_lower.contains("chelostoma") || name_lower.contains("tetralonia") ||
           name_lower.contains("bee") {
            return PollinatorCategory::SolitaryBees;
        }

        // Other Flies (catch remaining Diptera)
        if name_lower.contains("fly") || name_lower.contains("empis") ||
           name_lower.contains("calliphora") || name_lower.contains("scathophaga") ||
           name_lower.contains("drosophila") || name_lower.contains("bibio") ||
           name_lower.contains("diptera") || name_lower.contains("rhamphomyia") {
            return PollinatorCategory::OtherFlies;
        }

        // Pollen Beetles (before general "beetle")
        if name_lower.contains("meligethes") || name_lower.contains("brassicogethes") ||
           name_lower.contains("oedemera") {
            return PollinatorCategory::PollenBeetles;
        }

        // Other Beetles
        if name_lower.contains("beetle") || name_lower.contains("cetonia") ||
           name_lower.contains("trichius") || name_lower.contains("anaspis") ||
           name_lower.contains("coleoptera") {
            return PollinatorCategory::OtherBeetles;
        }

        // Butterflies (Lepidoptera - Rhopalocera)
        if name_lower.contains("papilio") || name_lower.contains("pieris") ||
           name_lower.contains("vanessa") || name_lower.contains("danaus") ||
           name_lower.contains("colias") || name_lower.contains("lycaena") ||
           name_lower.contains("polyommatus") || name_lower.contains("aglais") ||
           name_lower.contains("coenonympha") || name_lower.contains("erebia") ||
           name_lower.contains("gonepteryx") || name_lower.contains("anthocharis") ||
           name_lower.contains("maniola") || name_lower.contains("butterfly") {
            return PollinatorCategory::Butterflies;
        }

        // Moths (Lepidoptera - Heterocera)
        if name_lower.contains("moth") || name_lower.contains("sphinx") ||
           name_lower.contains("manduca") || name_lower.contains("hyles") ||
           name_lower.contains("macroglossum") {
            return PollinatorCategory::Moths;
        }

        // Wasps (Hymenoptera - non-Apoidea)
        if name_lower.contains("wasp") || name_lower.contains("vespula") ||
           name_lower.contains("vespa") || name_lower.contains("polistes") ||
           name_lower.contains("dolichovespula") {
            return PollinatorCategory::Wasps;
        }

        // Birds
        if name_lower.contains("bird") || name_lower.contains("hummingbird") ||
           name_lower.contains("trochilidae") || name_lower.contains("amazilia") ||
           name_lower.contains("phaethornis") || name_lower.contains("coereba") ||
           name_lower.contains("anthracothorax") || name_lower.contains(" aves ") ||
           name_lower.starts_with("aves ") || name_lower.ends_with(" aves") ||
           name_lower == "aves" {
            return PollinatorCategory::Birds;
        }

        // Bats
        if name_lower.contains("bat") || name_lower.contains("chiroptera") ||
           name_lower.contains("pteropus") || name_lower.contains("artibeus") {
            return PollinatorCategory::Bats;
        }

        PollinatorCategory::Other
    }

    pub fn display_name(&self) -> &str {
        match self {
            PollinatorCategory::HoneyBees => "Honey Bees",
            PollinatorCategory::Bumblebees => "Bumblebees",
            PollinatorCategory::SolitaryBees => "Solitary Bees",
            PollinatorCategory::HoverFlies => "Hover Flies",
            PollinatorCategory::MuscidFlies => "Muscid Flies",
            PollinatorCategory::Mosquitoes => "Mosquitoes",
            PollinatorCategory::OtherFlies => "Other Flies",
            PollinatorCategory::Butterflies => "Butterflies",
            PollinatorCategory::Moths => "Moths",
            PollinatorCategory::PollenBeetles => "Pollen Beetles",
            PollinatorCategory::OtherBeetles => "Other Beetles",
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

/// Pollinators grouped by category (expanded to 15 categories)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PollinatorsByCategoryProfile {
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
    pub top_per_category: Vec<TopPollinator>,
}

/// Plant with many pollinator associations (network hub, expanded to 15 categories)
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
        honey_bees_count: *category_counts.get(&PollinatorCategory::HoneyBees).unwrap_or(&0),
        bumblebees_count: *category_counts.get(&PollinatorCategory::Bumblebees).unwrap_or(&0),
        solitary_bees_count: *category_counts.get(&PollinatorCategory::SolitaryBees).unwrap_or(&0),
        hover_flies_count: *category_counts.get(&PollinatorCategory::HoverFlies).unwrap_or(&0),
        muscid_flies_count: *category_counts.get(&PollinatorCategory::MuscidFlies).unwrap_or(&0),
        mosquitoes_count: *category_counts.get(&PollinatorCategory::Mosquitoes).unwrap_or(&0),
        other_flies_count: *category_counts.get(&PollinatorCategory::OtherFlies).unwrap_or(&0),
        butterflies_count: *category_counts.get(&PollinatorCategory::Butterflies).unwrap_or(&0),
        moths_count: *category_counts.get(&PollinatorCategory::Moths).unwrap_or(&0),
        pollen_beetles_count: *category_counts.get(&PollinatorCategory::PollenBeetles).unwrap_or(&0),
        other_beetles_count: *category_counts.get(&PollinatorCategory::OtherBeetles).unwrap_or(&0),
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
    // Note: We intentionally ignore "flower_visitors" to match M7 scoring logic
    // (flower_visitors is contaminated with herbivores and fungi)

    let mut category_map: FxHashMap<String, PollinatorCategory> = FxHashMap::default();

    for idx in 0..organisms_df.height() {
        let plant_id_opt = organisms_plant_col.get(idx);
        if let Some(plant_id) = plant_id_opt {
            if !guild_plant_set.contains(plant_id) {
                continue;
            }

            // Process pollinators column (Legacy String Format)
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
            // Process pollinators column (List Format - Phase 0-4)
            if let Ok(list_col) = organisms_df.column("pollinators").and_then(|c| c.list()) {
                if let Some(list_series) = list_col.get_as_series(idx) {
                    if let Ok(str_series) = list_series.str() {
                        for pol_opt in str_series.into_iter() {
                            if let Some(pol_name) = pol_opt {
                                if !pol_name.is_empty() {
                                    let pol_name = pol_name.to_string();
                                    category_map.entry(pol_name.clone())
                                        .or_insert_with(|| PollinatorCategory::from_name(&pol_name));
                                }
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
    // Ignore flower_visitors

    let mut pollinator_to_plants: FxHashMap<String, (FxHashSet<String>, PollinatorCategory)> =
        FxHashMap::default();

    for idx in 0..organisms_df.height() {
        let plant_id_opt = organisms_plant_col.get(idx);
        if let Some(plant_id) = plant_id_opt {
            if !guild_plant_set.contains(plant_id) {
                continue;
            }

            let plant_id = plant_id.to_string();

            // Process pollinators column (Legacy String Format)
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
            // Process pollinators column (List Format - Phase 0-4)
            if let Ok(list_col) = organisms_df.column("pollinators").and_then(|c| c.list()) {
                if let Some(list_series) = list_col.get_as_series(idx) {
                    if let Ok(str_series) = list_series.str() {
                        for pol_opt in str_series.into_iter() {
                            if let Some(pol_name) = pol_opt {
                                if !pol_name.is_empty() {
                                    let pol_name = pol_name.to_string();
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
    // Ignore flower_visitors

    // Map: plant_id -> (total, honey_bees, bumblebees, solitary_bees, hover_flies, muscid_flies, mosquitoes, other_flies, butterflies, moths, pollen_beetles, other_beetles, wasps, birds, bats, other)
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

            // Process pollinators column (Legacy String Format)
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
                                PollinatorCategory::HoneyBees => entry.1 += 1,
                                PollinatorCategory::Bumblebees => entry.2 += 1,
                                PollinatorCategory::SolitaryBees => entry.3 += 1,
                                PollinatorCategory::HoverFlies => entry.4 += 1,
                                PollinatorCategory::MuscidFlies => entry.5 += 1,
                                PollinatorCategory::Mosquitoes => entry.6 += 1,
                                PollinatorCategory::OtherFlies => entry.7 += 1,
                                PollinatorCategory::Butterflies => entry.8 += 1,
                                PollinatorCategory::Moths => entry.9 += 1,
                                PollinatorCategory::PollenBeetles => entry.10 += 1,
                                PollinatorCategory::OtherBeetles => entry.11 += 1,
                                PollinatorCategory::Wasps => entry.12 += 1,
                                PollinatorCategory::Birds => entry.13 += 1,
                                PollinatorCategory::Bats => entry.14 += 1,
                                PollinatorCategory::Other => entry.15 += 1,
                            }
                        }
                    }
                }
            }
            // Process pollinators column (List Format - Phase 0-4)
            if let Ok(list_col) = organisms_df.column("pollinators").and_then(|c| c.list()) {
                if let Some(list_series) = list_col.get_as_series(idx) {
                    if let Ok(str_series) = list_series.str() {
                        for pol_opt in str_series.into_iter() {
                            if let Some(pol_name) = pol_opt {
                                if !pol_name.is_empty() && !pollinators_seen.contains(pol_name) {
                                    let pol_name = pol_name.to_string();
                                    pollinators_seen.insert(pol_name.clone());
                                    let category = category_map.get(&pol_name).cloned()
                                        .unwrap_or(PollinatorCategory::Other);
                                    entry.0 += 1; // total
                                    match category {
                                        PollinatorCategory::HoneyBees => entry.1 += 1,
                                        PollinatorCategory::Bumblebees => entry.2 += 1,
                                        PollinatorCategory::SolitaryBees => entry.3 += 1,
                                        PollinatorCategory::HoverFlies => entry.4 += 1,
                                        PollinatorCategory::MuscidFlies => entry.5 += 1,
                                        PollinatorCategory::Mosquitoes => entry.6 += 1,
                                        PollinatorCategory::OtherFlies => entry.7 += 1,
                                        PollinatorCategory::Butterflies => entry.8 += 1,
                                        PollinatorCategory::Moths => entry.9 += 1,
                                        PollinatorCategory::PollenBeetles => entry.10 += 1,
                                        PollinatorCategory::OtherBeetles => entry.11 += 1,
                                        PollinatorCategory::Wasps => entry.12 += 1,
                                        PollinatorCategory::Birds => entry.13 += 1,
                                        PollinatorCategory::Bats => entry.14 += 1,
                                        PollinatorCategory::Other => entry.15 += 1,
                                    }
                                }
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
