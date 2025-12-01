//! S1: Identity Card (JSON)
//!
//! Extracted from view_builder.rs - the identity section was already correct.
//! Returns IdentityCard struct for JSON serialization.
//!
//! CHANGE LOG from view_builder.rs:
//! - Extracted into standalone module (no logic changes)
//! - Made generate() public entry point
//! - All helper functions unchanged

use std::collections::HashMap;
use serde_json::Value;

use crate::encyclopedia::types::{get_str, get_f64};
use crate::encyclopedia::view_models::{
    IdentityCard, HeightInfo, LeafInfo, SeedInfo, GrowthIcon, RelativeSpecies,
};

// Re-export RelatedSpecies from sections_md for API compatibility (input type)
pub use crate::encyclopedia::sections_md::s1_identity::RelatedSpecies as InputRelatedSpecies;

/// Generate the S1 Identity Card section.
///
/// # Arguments
/// * `wfo_id` - WFO taxon ID
/// * `data` - Plant data from parquet
/// * `relatives` - Optional list of phylogenetically closest relatives (from api_server)
/// * `genus_species_count` - Total count of species in the same genus (deprecated, always 0)
pub fn generate(
    wfo_id: &str,
    data: &HashMap<String, Value>,
    relatives: Option<&[InputRelatedSpecies]>,
    genus_species_count: usize,
) -> IdentityCard {
    let scientific_name = get_str(data, "wfo_scientific_name")
        .unwrap_or("Unknown species")
        .to_string();

    let common_names = get_str(data, "vernacular_name_en")
        .map(|s| s.split(';').map(|n| to_title_case(n.trim())).collect())
        .unwrap_or_default();

    let chinese_names = get_str(data, "vernacular_name_zh")
        .filter(|s| !s.is_empty() && *s != "NA")
        .map(|s| s.to_string());

    let family = get_str(data, "family").unwrap_or("Unknown").to_string();
    let genus = get_str(data, "genus").unwrap_or("Unknown").to_string();

    let growth_form = get_str(data, "try_growth_form");
    let (growth_type, growth_icon) = classify_growth(growth_form, data);

    let native_climate = get_str(data, "top_zone_code")
        .filter(|s| !s.is_empty() && *s != "NA")
        .map(|k| interpret_koppen(k));

    let height = get_f64(data, "height_m").map(|h| HeightInfo {
        meters: h,
        description: describe_height(h),
    });

    let leaf = get_f64(data, "LA").map(|la| {
        let leaf_type = get_str(data, "try_leaf_type").unwrap_or("").to_string();
        LeafInfo {
            leaf_type: if leaf_type.is_empty() { "Broadleaved".to_string() } else { leaf_type },
            area_cm2: la / 100.0, // mm² to cm²
            description: describe_leaf_size(la),
        }
    });

    let seed = get_f64(data, "logSM").map(|log_sm| {
        let mass_mg = log_sm.exp();
        SeedInfo {
            mass_g: mass_mg / 1000.0,
            description: describe_seed_size(mass_mg),
        }
    });

    let relatives_vec = relatives.map(|r| {
        r.iter().take(5).map(|rel| RelativeSpecies {
            wfo_id: rel.wfo_id.clone(),
            scientific_name: rel.scientific_name.clone(),
            common_name: rel.common_name.clone(),
            relatedness: classify_relatedness(rel.distance),
            distance: rel.distance,
        }).collect()
    }).unwrap_or_default();

    IdentityCard {
        wfo_id: wfo_id.to_string(),
        scientific_name,
        common_names,
        chinese_names,
        family,
        genus,
        growth_type,
        growth_icon,
        native_climate,
        height,
        leaf,
        seed,
        relatives: relatives_vec,
        genus_species_count,
    }
}

// ============================================================================
// Helper Functions (unchanged from view_builder.rs)
// ============================================================================

fn classify_growth(growth_form: Option<&str>, data: &HashMap<String, Value>) -> (String, GrowthIcon) {
    let height = get_f64(data, "height_m");
    let phenology = get_str(data, "try_leaf_phenology");

    let gf = growth_form.unwrap_or("").to_lowercase();

    if gf.contains("tree") || height.map(|h| h > 5.0).unwrap_or(false) {
        let prefix = match phenology {
            Some(p) if p.to_lowercase().contains("deciduous") => "Deciduous",
            Some(p) if p.to_lowercase().contains("evergreen") => "Evergreen",
            _ => "",
        };
        (format!("{} tree", prefix).trim().to_string(), GrowthIcon::Tree)
    } else if gf.contains("shrub") || height.map(|h| h > 1.0 && h <= 5.0).unwrap_or(false) {
        ("Shrub".to_string(), GrowthIcon::Shrub)
    } else if gf.contains("vine") || gf.contains("liana") || gf.contains("climber") {
        ("Vine / Climber".to_string(), GrowthIcon::Vine)
    } else if gf.contains("grass") || gf.contains("graminoid") {
        ("Grass".to_string(), GrowthIcon::Grass)
    } else {
        ("Herb / Forb".to_string(), GrowthIcon::Herb)
    }
}

fn describe_height(h: f64) -> String {
    if h > 20.0 {
        "Needs significant space".to_string()
    } else if h > 10.0 {
        "Medium tree".to_string()
    } else if h > 5.0 {
        "Small tree".to_string()
    } else if h > 2.0 {
        "Shrub".to_string()
    } else if h > 0.5 {
        "Low shrub".to_string()
    } else {
        "Ground cover".to_string()
    }
}

/// Convert string to Title Case
fn to_title_case(s: &str) -> String {
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

fn describe_leaf_size(la_mm2: f64) -> String {
    let la_cm2 = la_mm2 / 100.0;
    if la_cm2 > 100.0 {
        "Very large".to_string()
    } else if la_cm2 > 30.0 {
        "Large".to_string()
    } else if la_cm2 > 10.0 {
        "Medium".to_string()
    } else if la_cm2 > 2.0 {
        "Small".to_string()
    } else {
        "Very small".to_string()
    }
}

fn describe_seed_size(mass_mg: f64) -> String {
    if mass_mg > 10000.0 {
        "Very large".to_string()
    } else if mass_mg > 1000.0 {
        "Large".to_string()
    } else if mass_mg > 100.0 {
        "Medium".to_string()
    } else if mass_mg > 10.0 {
        "Small".to_string()
    } else {
        "Tiny".to_string()
    }
}

fn interpret_koppen(code: &str) -> String {
    match code.chars().next() {
        Some('A') => "Tropical (warm year-round)".to_string(),
        Some('B') => "Arid / Semi-arid".to_string(),
        Some('C') => "Temperate (mild winters)".to_string(),
        Some('D') => "Continental (cold winters)".to_string(),
        Some('E') => "Polar / Alpine".to_string(),
        _ => format!("Climate zone: {}", code),
    }
}

fn classify_relatedness(distance: f64) -> String {
    if distance < 50.0 {
        "Close".to_string()
    } else if distance < 150.0 {
        "Moderate".to_string()
    } else {
        "Distant".to_string()
    }
}
