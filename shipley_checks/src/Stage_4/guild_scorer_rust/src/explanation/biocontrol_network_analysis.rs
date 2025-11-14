//! Biocontrol Network Analysis for M3 (Insect Pest Control)
//!
//! Analyzes which plants attract beneficial predators and entomopathogenic fungi,
//! identifies generalist biocontrol agents, and finds network hubs.

use polars::prelude::*;
use rustc_hash::{FxHashMap, FxHashSet};
use anyhow::Result;
use serde::{Deserialize, Serialize};

/// Predator taxonomic categories (8 categories)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum PredatorCategory {
    Spiders,
    Bats,
    Birds,
    Ladybugs,
    GroundBeetles,
    PredatoryBugs,
    PredatoryWasps,
    OtherPredators,
}

impl PredatorCategory {
    /// Categorize a predator based on its name
    pub fn from_name(name: &str) -> Self {
        let name_lower = name.to_lowercase();

        // Spiders (Araneae) - most common
        if name_lower.contains("aculepeira") || name_lower.contains("agalenatea") ||
           name_lower.contains("argiope") || name_lower.contains("araneus") ||
           name_lower.contains("araneae") || name_lower.contains("spider") ||
           name_lower.contains("lycosa") || name_lower.contains("salticidae") {
            return PredatorCategory::Spiders;
        }

        // Bats (Chiroptera)
        if name_lower.contains("myotis") || name_lower.contains("eptesicus") ||
           name_lower.contains("corynorhinus") || name_lower.contains("miniopterus") ||
           name_lower.contains("pipistrellus") || name_lower.contains("rhinolophus") ||
           name_lower.contains("lasiurus") || name_lower.contains("barbastella") ||
           name_lower.contains("plecotus") || name_lower.contains("nyctalus") ||
           name_lower.contains("tadarida") || name_lower.contains("antrozous") ||
           name_lower.contains("murina") || name_lower.contains("eumops") ||
           name_lower.contains("bat") || name_lower.contains("chiroptera") {
            return PredatorCategory::Bats;
        }

        // Birds (Aves)
        if name_lower.contains("anthus") || name_lower.contains("agelaius") ||
           name_lower.contains("vireo") || name_lower.contains("cyanistes") ||
           name_lower.contains("empidonax") || name_lower.contains("setophaga") ||
           name_lower.contains("cardinalis") || name_lower.contains("catharus") ||
           name_lower.contains("baeolophus") || name_lower.contains("tyrannus") ||
           name_lower.contains("coccyzus") || name_lower.contains("sialia") ||
           name_lower.contains("lanius") || name_lower.contains("contopus") ||
           name_lower.contains("dryobates") || name_lower.contains("falco") ||
           name_lower.contains("rhipidura") || name_lower.contains("merops") ||
           name_lower.contains("cracticus") || name_lower.contains("bird") ||
           name_lower.contains("aves") {
            return PredatorCategory::Birds;
        }

        // Ladybugs (Coccinellidae)
        if name_lower.contains("adalia") || name_lower.contains("coccinella") ||
           name_lower.contains("hippodamia") || name_lower.contains("harmonia") ||
           name_lower.contains("chilocorus") || name_lower.contains("coccinellidae") ||
           name_lower.contains("ladybug") {
            return PredatorCategory::Ladybugs;
        }

        // Ground/Rove Beetles (Carabidae/Staphylinidae)
        if name_lower.contains("carabus") || name_lower.contains("pterostichus") ||
           name_lower.contains("abax") || name_lower.contains("acupalpus") ||
           name_lower.contains("carabidae") || name_lower.contains("staphylinidae") ||
           name_lower.contains("staphylinus") {
            return PredatorCategory::GroundBeetles;
        }

        // Predatory Bugs (Hemiptera)
        if name_lower.contains("anthocoris") || name_lower.contains("orius") ||
           name_lower.contains("nabis") || name_lower.contains("geocoris") ||
           name_lower.contains("picromerus") || name_lower.contains("arilus") ||
           name_lower.contains("phymata") {
            return PredatorCategory::PredatoryBugs;
        }

        // Predatory Wasps (Hymenoptera)
        if name_lower.contains("vespula") || name_lower.contains("polistes") ||
           name_lower.contains("vespa") || name_lower.contains("dolichovespula") ||
           name_lower.contains("ichneumon") || name_lower.contains("braconidae") ||
           name_lower.contains("eurytoma") || name_lower.contains("mesopolobus") ||
           name_lower.contains("pteromalus") || name_lower.contains("ascogaster") ||
           name_lower.contains("campoletis") || name_lower.contains("symmorphus") {
            return PredatorCategory::PredatoryWasps;
        }

        PredatorCategory::OtherPredators
    }

    pub fn display_name(&self) -> &str {
        match self {
            PredatorCategory::Spiders => "Spiders",
            PredatorCategory::Bats => "Bats",
            PredatorCategory::Birds => "Birds",
            PredatorCategory::Ladybugs => "Ladybugs",
            PredatorCategory::GroundBeetles => "Ground Beetles",
            PredatorCategory::PredatoryBugs => "Predatory Bugs",
            PredatorCategory::PredatoryWasps => "Predatory Wasps",
            PredatorCategory::OtherPredators => "Other Predators",
        }
    }
}

/// Herbivore pest taxonomic categories (10 categories)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum HerbivoreCategory {
    Aphids,
    Mites,
    LeafMiners,
    ScaleInsects,
    Caterpillars,
    Thrips,
    Whiteflies,
    Beetles,
    Leafhoppers,
    OtherHerbivores,
}

impl HerbivoreCategory {
    /// Categorize a herbivore based on its name
    pub fn from_name(name: &str) -> Self {
        let name_lower = name.to_lowercase();

        // Aphids (Aphididae) - most common
        if (name_lower == "aphis" || name_lower.starts_with("aphis ") ||
            name_lower.contains(" aphis ") || name_lower.ends_with(" aphis")) ||
           name_lower.contains("aphid") || name_lower.contains("myzus") ||
           name_lower.contains("macrosiphum") || name_lower.contains("rhopalosiphum") ||
           name_lower.contains("acyrthosiphon") || name_lower.contains("aulacorthum") ||
           name_lower.contains("brachycaudus") || name_lower.contains("hyperomyzus") ||
           name_lower.contains("hyadaphis") || name_lower.contains("cinara") ||
           name_lower.contains("cavariella") || name_lower.contains("anoecia") ||
           name_lower.contains("dysaphis") || name_lower.contains("cryptomyzus") ||
           name_lower.contains("allaphis") || name_lower.contains("aphididae") {
            return HerbivoreCategory::Aphids;
        }

        // Herbivorous Mites
        if name_lower.contains("aceria") || name_lower.contains("tetranychus") ||
           name_lower.contains("panonychus") || name_lower.contains("tetranychidae") ||
           name_lower.contains("eriophyidae") || name_lower.contains("eriophyes") {
            return HerbivoreCategory::Mites;
        }

        // Leaf Miners
        if name_lower.contains("phytomyza") || name_lower.contains("liriomyza") ||
           name_lower.contains("agromyza") || name_lower.contains("chromatomyia") ||
           name_lower.contains("agromyzidae") || name_lower.contains("phytoliriomyza") ||
           name_lower.contains("calycomyza") {
            return HerbivoreCategory::LeafMiners;
        }

        // Scale Insects
        if name_lower.contains("aspidiotus") || name_lower.contains("aonidiella") ||
           name_lower.contains("diaspidiotus") || name_lower.contains("pseudococcus") ||
           name_lower.contains("coccus") || name_lower.contains("diaspididae") ||
           name_lower.contains("coccidae") || name_lower.contains("pseudococcidae") ||
           name_lower.contains("hemiberlesia") || name_lower.contains("abgrallaspis") ||
           name_lower.contains("lindingaspis") || name_lower.contains("pseudaulacaspis") ||
           name_lower.contains("eriococcus") || name_lower.contains("icerya") ||
           name_lower.contains("scale") {
            return HerbivoreCategory::ScaleInsects;
        }

        // Caterpillars
        if name_lower.contains("spodoptera") || name_lower.contains("helicoverpa") ||
           name_lower.contains("heliothis") || name_lower.contains("plutella") ||
           name_lower.contains("mamestra") || name_lower.contains("agrotis") ||
           name_lower.contains("abagrotis") || name_lower.contains("adoxophyes") ||
           name_lower.contains("archips") || name_lower.contains("choristoneura") ||
           name_lower.contains("acronicta") || name_lower.contains("euxoa") {
            return HerbivoreCategory::Caterpillars;
        }

        // Thrips
        if name_lower.contains("thrips") || name_lower.contains("frankliniella") ||
           name_lower.contains("heliothrips") || name_lower.contains("thysanoptera") ||
           name_lower.contains("akainothrips") {
            return HerbivoreCategory::Thrips;
        }

        // Whiteflies
        if name_lower.contains("bemisia") || name_lower.contains("trialeurodes") ||
           name_lower.contains("aleurodidae") || name_lower.contains("aleurocanthus") ||
           name_lower.contains("whitefly") {
            return HerbivoreCategory::Whiteflies;
        }

        // Herbivorous Beetles
        if name_lower.contains("phyllotreta") || name_lower.contains("chrysomelidae") ||
           name_lower.contains("diabrotica") || name_lower.contains("leptinotarsa") ||
           name_lower.contains("psylliodes") || name_lower.contains("cassida") ||
           name_lower.contains("chrysolina") || name_lower.contains("bruchidius") {
            return HerbivoreCategory::Beetles;
        }

        // Leafhoppers
        if name_lower.contains("empoasca") || name_lower.contains("cicadellidae") ||
           name_lower.contains("leafhopper") || name_lower.contains("erythroneura") ||
           name_lower.contains("ausejanus") {
            return HerbivoreCategory::Leafhoppers;
        }

        HerbivoreCategory::OtherHerbivores
    }

    pub fn display_name(&self) -> &str {
        match self {
            HerbivoreCategory::Aphids => "Aphids",
            HerbivoreCategory::Mites => "Mites",
            HerbivoreCategory::LeafMiners => "Leaf Miners",
            HerbivoreCategory::ScaleInsects => "Scale Insects",
            HerbivoreCategory::Caterpillars => "Caterpillars",
            HerbivoreCategory::Thrips => "Thrips",
            HerbivoreCategory::Whiteflies => "Whiteflies",
            HerbivoreCategory::Beetles => "Beetles",
            HerbivoreCategory::Leafhoppers => "Leafhoppers",
            HerbivoreCategory::OtherHerbivores => "Other Herbivores",
        }
    }
}

/// Matched predator-herbivore pair with categories
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchedPredatorPair {
    pub herbivore: String,
    pub herbivore_category: HerbivoreCategory,
    pub predator: String,
    pub predator_category: PredatorCategory,
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
    pub matched_predator_pairs: Vec<MatchedPredatorPair>,

    /// List of matched (herbivore, entomopathogenic_fungus) pairs
    pub matched_fungi_pairs: Vec<(String, String)>,

    /// Predator category distribution
    pub predator_category_counts: FxHashMap<PredatorCategory, usize>,

    /// Herbivore category distribution
    pub herbivore_category_counts: FxHashMap<HerbivoreCategory, usize>,

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

    /// Number of predators visiting this plant
    pub total_predators: usize,

    /// Number of entomopathogenic fungi on this plant
    pub total_entomo_fungi: usize,

    /// Combined total biocontrol agents
    pub total_biocontrol_agents: usize,
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
    let mut predator_category_counts: FxHashMap<PredatorCategory, usize> = FxHashMap::default();
    for predator_name in predator_counts.keys() {
        let category = PredatorCategory::from_name(predator_name);
        *predator_category_counts.entry(category).or_insert(0) += 1;
    }

    // Categorize herbivores from matched pairs and build category counts
    let mut herbivore_category_counts: FxHashMap<HerbivoreCategory, usize> = FxHashMap::default();
    let mut unique_herbivores: FxHashSet<String> = FxHashSet::default();

    for (herbivore, _) in matched_predator_pairs {
        if unique_herbivores.insert(herbivore.clone()) {
            let category = HerbivoreCategory::from_name(herbivore);
            *herbivore_category_counts.entry(category).or_insert(0) += 1;
        }
    }

    // Build matched pairs with categories
    let matched_predator_pairs_with_categories: Vec<MatchedPredatorPair> = matched_predator_pairs
        .iter()
        .map(|(herbivore, predator)| MatchedPredatorPair {
            herbivore: herbivore.clone(),
            herbivore_category: HerbivoreCategory::from_name(herbivore),
            predator: predator.clone(),
            predator_category: PredatorCategory::from_name(predator),
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
        matched_fungi_pairs: matched_fungi_pairs.to_vec(),
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

/// Find plants that are biocontrol hubs (attract most agents)
fn find_biocontrol_hubs(
    guild_plants: &DataFrame,
    organisms_df: &DataFrame,
    fungi_df: &DataFrame,
    known_predators: &FxHashSet<String>,
    known_entomo_fungi: &FxHashSet<String>,
) -> Result<Vec<PlantBiocontrolHub>> {
    let mut hubs: Vec<PlantBiocontrolHub> = Vec::new();

    let plant_ids = guild_plants.column("wfo_taxon_id")?.str()?;
    let plant_names = guild_plants.column("wfo_scientific_name")?.str()?;

    for idx in 0..guild_plants.height() {
        if let (Some(plant_id), Some(plant_name)) = (plant_ids.get(idx), plant_names.get(idx)) {
            // Count predators for this plant (filtered to known predators only)
            let total_predators = count_predators_for_plant(organisms_df, plant_id, known_predators)?;

            // Count entomopathogenic fungi for this plant (filtered to known fungi only)
            let total_entomo_fungi = count_entomo_fungi_for_plant(fungi_df, plant_id, known_entomo_fungi)?;

            let total_biocontrol_agents = total_predators + total_entomo_fungi;

            if total_biocontrol_agents > 0 {
                hubs.push(PlantBiocontrolHub {
                    plant_name: plant_name.to_string(),
                    total_predators,
                    total_entomo_fungi,
                    total_biocontrol_agents,
                });
            }
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
