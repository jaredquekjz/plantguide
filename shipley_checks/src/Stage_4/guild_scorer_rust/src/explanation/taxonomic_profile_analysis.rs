use serde::{Deserialize, Serialize};
use polars::prelude::*;
use anyhow::Result;
use rustc_hash::FxHashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaxonomicProfile {
    pub total_plants: usize,
    pub total_families: usize,
    pub total_genera: usize,
    pub plant_entries: Vec<PlantTaxonomy>,
    pub family_distribution: Vec<(String, usize)>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlantTaxonomy {
    pub family: String,
    pub genus: String,
    pub display_name: String,
}

/// Analyze taxonomic diversity of guild plants
pub fn analyze_taxonomic_diversity(guild_plants: &DataFrame) -> Result<TaxonomicProfile> {
    // Extract taxonomic data (keep Option to handle nulls properly)
    let families = guild_plants
        .column("family")?
        .str()?
        .into_iter()
        .map(|f| f.map(|s| s.to_string()).unwrap_or_default())
        .collect::<Vec<_>>();

    let genera = guild_plants
        .column("genus")?
        .str()?
        .into_iter()
        .map(|g| g.map(|s| s.to_string()).unwrap_or_default())
        .collect::<Vec<_>>();

    let plant_names = guild_plants
        .column("wfo_scientific_name")?
        .str()?
        .into_iter()
        .map(|n| n.map(|s| s.to_string()).unwrap_or_default())
        .collect::<Vec<_>>();

    let vernacular_names_en = guild_plants
        .column("vernacular_name_en")?
        .str()?
        .into_iter()
        .map(|v| v.map(|s| s.to_string()).unwrap_or_default())
        .collect::<Vec<_>>();

    let vernacular_names_zh = guild_plants
        .column("vernacular_name_zh")?
        .str()?
        .into_iter()
        .map(|v| v.map(|s| s.to_string()).unwrap_or_default())
        .collect::<Vec<_>>();

    // Build plant entries with display names
    let mut plant_entries = Vec::new();
    for i in 0..families.len() {
        // Format vernacular names: use English, fallback to Chinese, replace semicolons with commas
        let vernacular = if !vernacular_names_en[i].is_empty() {
            // Clean up English names: replace semicolons with commas
            vernacular_names_en[i].replace("; ", ", ")
        } else if !vernacular_names_zh[i].is_empty() {
            // Fallback to Chinese names if English not available
            vernacular_names_zh[i].replace("; ", ", ")
        } else {
            String::new()
        };

        let display_name = if !vernacular.is_empty() {
            format!("{} ({})", plant_names[i], vernacular)
        } else {
            plant_names[i].clone()
        };

        plant_entries.push(PlantTaxonomy {
            family: families[i].clone(),
            genus: genera[i].clone(),
            display_name,
        });
    }

    // Sort by family, then genus, then plant name
    plant_entries.sort_by(|a, b| {
        a.family
            .cmp(&b.family)
            .then_with(|| a.genus.cmp(&b.genus))
            .then_with(|| a.display_name.cmp(&b.display_name))
    });

    // Count unique families and genera
    let unique_families: std::collections::HashSet<_> = families.iter().collect();
    let unique_genera: std::collections::HashSet<_> = genera.iter().collect();

    // Count plants per family
    let mut family_counts: FxHashMap<String, usize> = FxHashMap::default();
    for family in &families {
        *family_counts.entry(family.clone()).or_insert(0) += 1;
    }

    // Convert to sorted vec (by count descending, then name)
    let mut family_distribution: Vec<_> = family_counts.into_iter().collect();
    family_distribution.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));

    Ok(TaxonomicProfile {
        total_plants: plant_entries.len(),
        total_families: unique_families.len(),
        total_genera: unique_genera.len(),
        plant_entries,
        family_distribution,
    })
}
