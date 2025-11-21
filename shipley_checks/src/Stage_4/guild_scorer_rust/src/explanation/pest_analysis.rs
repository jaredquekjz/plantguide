use polars::prelude::*;
use anyhow::Result;
use serde::{Serialize, Deserialize};
use rustc_hash::FxHashMap;
use crate::explanation::unified_taxonomy::{OrganismCategory, OrganismRole};

/// Pest profile for a guild (qualitative information)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PestProfile {
    pub total_unique_pests: usize,
    pub shared_pests: Vec<SharedPest>,
    pub top_pests: Vec<TopPest>,
    pub vulnerable_plants: Vec<VulnerablePlant>,
}

/// Pest that attacks multiple plants (generalist)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharedPest {
    pub pest_name: String,
    pub category: String,
    pub plant_count: usize,
    pub plants: Vec<String>,
}

/// Top pest by total interactions
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopPest {
    pub pest_name: String,
    pub category: String,
    pub plant_count: usize,
    pub plants: Vec<String>,
}

/// Plant with its pest vulnerability
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VulnerablePlant {
    pub plant_name: String,
    pub pest_count: usize,
}

/// Analyze pest profile for a guild
///
/// Extracts herbivore information and identifies:
/// - Shared pests (generalists attacking 2+ plants)
/// - Top 10 pests by interaction count
/// - Most vulnerable plants
pub fn analyze_guild_pests(
    guild_plants: &DataFrame,
    organism_categories: &FxHashMap<String, String>,
) -> Result<Option<PestProfile>> {
    // Check if herbivores column exists (try both list and string formats)
    let herbivores_col = match guild_plants.column("herbivores") {
        Ok(col) => col,
        Err(_) => return Ok(None),
    };

    // Try both list format (Phase 0-4) and string format (legacy)
    let herbivores_list_col = herbivores_col.list().ok();
    let herbivores_str_col = herbivores_col.str().ok();

    let plant_names = guild_plants.column("wfo_taxon_name")?.str()?;

    // Build pest-to-plants mapping
    let mut pest_to_plants: FxHashMap<String, Vec<String>> = FxHashMap::default();
    let mut plant_pest_counts: FxHashMap<String, usize> = FxHashMap::default();

    for idx in 0..guild_plants.height() {
        if let Some(plant_name) = plant_names.get(idx) {
            let plant_name = plant_name.to_string();
            let mut herbivores: Vec<String> = Vec::new();

            // Try list column format first (Phase 0-4)
            if let Some(list_col) = herbivores_list_col {
                if let Some(list_series) = list_col.get_as_series(idx) {
                    if let Ok(str_series) = list_series.str() {
                        for herb_opt in str_series.into_iter() {
                            if let Some(herb) = herb_opt {
                                let herb = herb.trim();
                                if !herb.is_empty() {
                                    herbivores.push(herb.to_string());
                                }
                            }
                        }
                    }
                }
            }

            // Fallback to pipe-separated string format (legacy)
            if herbivores.is_empty() {
                if let Some(str_col) = herbivores_str_col {
                    if let Some(herbivores_str) = str_col.get(idx) {
                        if !herbivores_str.is_empty() {
                            for herb in herbivores_str.split('|') {
                                let herb = herb.trim();
                                if !herb.is_empty() {
                                    herbivores.push(herb.to_string());
                                }
                            }
                        }
                    }
                }
            }

            if herbivores.is_empty() {
                continue;
            }

            *plant_pest_counts.entry(plant_name.clone()).or_insert(0) += herbivores.len();

            for pest in herbivores {
                pest_to_plants
                    .entry(pest)
                    .or_insert_with(Vec::new)
                    .push(plant_name.clone());
            }
        }
    }

    if pest_to_plants.is_empty() {
        return Ok(None);
    }

    // Deduplicate plants per pest (in case same pest listed multiple times)
    for plants in pest_to_plants.values_mut() {
        plants.sort();
        plants.dedup();
    }

    let total_unique_pests = pest_to_plants.len();

    // Identify shared pests (2+ plants)
    let mut shared_pests: Vec<SharedPest> = pest_to_plants
        .iter()
        .filter(|(_, plants)| plants.len() >= 2)
        .map(|(pest, plants)| {
            let category = OrganismCategory::from_name(pest, organism_categories, Some(OrganismRole::Herbivore));
            SharedPest {
                pest_name: pest.clone(),
                category: category.display_name().to_string(),
                plant_count: plants.len(),
                plants: plants.clone(),
            }
        })
        .collect();

    // Sort by plant count (most generalist first), then by name for deterministic ordering
    shared_pests.sort_by(|a, b| {
        b.plant_count.cmp(&a.plant_count)
            .then_with(|| a.pest_name.cmp(&b.pest_name))
    });

    // Top 10 pests by plant count (even if only 1 plant)
    let mut top_pests: Vec<TopPest> = pest_to_plants
        .iter()
        .map(|(pest, plants)| {
            let category = OrganismCategory::from_name(pest, organism_categories, Some(OrganismRole::Herbivore));
            TopPest {
                pest_name: pest.clone(),
                category: category.display_name().to_string(),
                plant_count: plants.len(),
                plants: plants.clone(),
            }
        })
        .collect();

    // Sort by plant count
    // Sort by plant count (descending), then by name (ascending) for deterministic ordering
    top_pests.sort_by(|a, b| {
        b.plant_count.cmp(&a.plant_count)
            .then_with(|| a.pest_name.cmp(&b.pest_name))
    });
    top_pests.truncate(10);

    // Most vulnerable plants (by pest count)
    let mut vulnerable_plants: Vec<VulnerablePlant> = plant_pest_counts
        .iter()
        .map(|(plant, count)| VulnerablePlant {
            plant_name: plant.clone(),
            pest_count: *count,
        })
        .collect();

    // Sort by pest count (descending), then by name for deterministic ordering
    vulnerable_plants.sort_by(|a, b| {
        b.pest_count.cmp(&a.pest_count)
            .then_with(|| a.plant_name.cmp(&b.plant_name))
    });

    Ok(Some(PestProfile {
        total_unique_pests,
        shared_pests,
        top_pests,
        vulnerable_plants,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pest_analysis_with_shared() {
        let df = df! {
            "wfo_taxon_name" => &["Plant A", "Plant B", "Plant C"],
            "herbivores" => &["Aphid|Beetle", "Aphid|Moth", "Beetle"]
        }
        .unwrap();

        let categories = FxHashMap::default();
        let profile = analyze_guild_pests(&df, &categories).unwrap().unwrap();

        assert_eq!(profile.total_unique_pests, 3);
        assert_eq!(profile.shared_pests.len(), 2); // Aphid and Beetle
        assert_eq!(profile.top_pests.len(), 3);

        // Aphid should be top (2 plants)
        assert_eq!(profile.top_pests[0].pest_name, "Aphid");
        assert_eq!(profile.top_pests[0].plant_count, 2);
    }

    #[test]
    fn test_pest_analysis_no_shared() {
        let df = df! {
            "wfo_taxon_name" => &["Plant A", "Plant B"],
            "herbivores" => &["Pest1|Pest2", "Pest3|Pest4"]
        }
        .unwrap();

        let categories = FxHashMap::default();
        let profile = analyze_guild_pests(&df, &categories).unwrap().unwrap();

        assert_eq!(profile.total_unique_pests, 4);
        assert_eq!(profile.shared_pests.len(), 0); // No shared pests
        assert_eq!(profile.top_pests.len(), 4);
    }

    #[test]
    fn test_pest_analysis_empty() {
        let df = df! {
            "wfo_taxon_name" => &["Plant A", "Plant B"],
            "herbivores" => &["", ""]
        }
        .unwrap();

        let categories = FxHashMap::default();
        let profile = analyze_guild_pests(&df, &categories).unwrap();
        assert!(profile.is_none());
    }
}
