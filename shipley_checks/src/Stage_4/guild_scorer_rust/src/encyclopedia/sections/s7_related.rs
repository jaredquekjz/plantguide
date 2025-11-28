//! S7: Relatives Within Genus
//!
//! Shows the 5 closest phylogenetic relatives within the same genus.
//! Uses evolutionary distance calculated from the phylogenetic tree.
//!
//! Data Sources:
//! - Phylogenetic tree: compact_tree_11711.bin
//! - WFO mapping: mixgb_wfo_to_tree_mapping_11711.csv
//! - Plant data: genus, wfo_taxon_id, wfo_scientific_name, vernacular_name_en

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::*;

/// A related species with phylogenetic distance
#[derive(Debug, Clone)]
pub struct RelatedSpecies {
    pub wfo_id: String,
    pub scientific_name: String,
    pub common_name: String,
    pub distance: f64,
}

/// Data needed to find related species
pub struct RelatedSpeciesInput {
    pub base_wfo_id: String,
    pub genus: String,
    pub genus_species: Vec<GenusSpeciesInfo>,
}

/// Info about a species in the same genus
#[derive(Debug, Clone)]
pub struct GenusSpeciesInfo {
    pub wfo_id: String,
    pub scientific_name: String,
    pub common_name: String,
    pub tree_tip: Option<String>,
}

/// Generate the S7 Relatives Within Genus section.
pub fn generate(
    data: &HashMap<String, Value>,
    relatives: Option<&[RelatedSpecies]>,
    genus_count: usize,
) -> String {
    let mut lines = Vec::new();
    lines.push("## Relatives Within Genus".to_string());
    lines.push(String::new());

    let genus = get_str(data, "genus").unwrap_or("Unknown");

    match relatives {
        Some(rel) if !rel.is_empty() => {
            lines.push(format!(
                "**5 Closest Relatives** (from {} *{}* species in database, by evolutionary distance):",
                genus_count, genus
            ));
            lines.push(String::new());

            // Table header
            lines.push("| Species | Common Name | Relatedness |".to_string());
            lines.push("|---------|-------------|-------------|".to_string());

            // Table rows
            for species in rel.iter().take(5) {
                let relatedness = distance_to_label(species.distance);
                let common = if species.common_name.is_empty() {
                    "—".to_string()
                } else {
                    species.common_name.clone()
                };
                lines.push(format!(
                    "| *{}* | {} | {} |",
                    species.scientific_name, common, relatedness
                ));
            }

            // Friendly explanation
            lines.push(String::new());
            lines.push(format!(
                "*These {} are most similar to your plant. They likely need similar soil, \
                water, and care—handy if you want alternatives or companions that \"go together.\" \
                But they also catch the same bugs and diseases, so don't plant too many \
                of the same type in one spot. Mix in plants from different families for \
                a healthier garden.*",
                genus_plural(genus)
            ));
        }
        _ => {
            // No relatives found or only species in genus
            if genus_count <= 1 {
                lines.push(format!(
                    "*This is the only *{}* species in our database.*",
                    genus
                ));
            } else {
                lines.push(format!(
                    "*Could not calculate evolutionary distances for *{}* species.*",
                    genus
                ));
            }
        }
    }

    lines.join("\n")
}

/// Convert phylogenetic distance to human-readable label
/// Calibrated from actual tree distances: Trifolium ~2-35, Quercus ~24, Rosa ~68-141
fn distance_to_label(distance: f64) -> &'static str {
    // Calibrated based on actual branch lengths in our 11,711-species tree
    // Within-genus distances typically range from ~2 to ~150 Myr
    if distance < 5.0 {
        "Very close"
    } else if distance < 15.0 {
        "Close"
    } else if distance < 40.0 {
        "Moderate"
    } else if distance < 80.0 {
        "Distant"
    } else {
        "Very distant"
    }
}

/// Get plural form for genus (most are just "species" but some common ones have names)
fn genus_plural(genus: &str) -> &'static str {
    match genus {
        "Quercus" => "oaks",
        "Rosa" => "roses",
        "Acer" => "maples",
        "Prunus" => "cherries/plums",
        "Salix" => "willows",
        "Pinus" => "pines",
        "Betula" => "birches",
        "Fagus" => "beeches",
        "Fraxinus" => "ashes",
        "Malus" => "apples",
        "Pyrus" => "pears",
        "Sorbus" => "rowans",
        "Crataegus" => "hawthorns",
        "Cornus" => "dogwoods",
        "Viburnum" => "viburnums",
        "Rhododendron" => "rhododendrons",
        "Trifolium" => "clovers",
        "Vicia" => "vetches",
        "Geranium" => "geraniums",
        "Ranunculus" => "buttercups",
        "Carex" => "sedges",
        "Festuca" => "fescues",
        "Poa" => "meadow-grasses",
        _ => "species",
    }
}
