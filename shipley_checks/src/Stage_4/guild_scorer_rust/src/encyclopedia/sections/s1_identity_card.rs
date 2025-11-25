//! Section 1: Plant Identity Card
//!
//! Generates concise plant identification summary with taxonomic classification
//! and key morphological traits.
//!
//! Ported from R: shipley_checks/src/encyclopedia/sections/s1_identity_card.R

use crate::encyclopedia::utils::categorization::{categorize_height, categorize_woodiness};
use std::collections::HashMap;

/// Plant data needed for identity card generation
pub struct PlantIdentity {
    pub scientific_name: String,
    pub family: Option<String>,
    pub genus: Option<String>,
    pub height_m: Option<f64>,
    pub growth_form: Option<String>,
    pub woodiness: Option<f64>,
    pub woodiness_text: Option<String>, // Some datasets use text labels
    pub leaf_type: Option<String>,
    pub leaf_phenology: Option<String>,
    pub photosynthesis_pathway: Option<String>,
    pub mycorrhiza_type: Option<String>,
}

impl PlantIdentity {
    /// Create from a HashMap of column values (from DataFusion query)
    pub fn from_row(row: &HashMap<String, serde_json::Value>) -> Option<Self> {
        let scientific_name = row
            .get("wfo_scientific_name")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())?;

        Some(Self {
            scientific_name,
            family: row.get("family").and_then(|v| v.as_str()).map(|s| s.to_string()),
            genus: row.get("genus").and_then(|v| v.as_str()).map(|s| s.to_string()),
            height_m: row.get("height_m").and_then(|v| v.as_f64()),
            growth_form: row.get("try_growth_form").and_then(|v| v.as_str()).map(|s| s.to_string()),
            woodiness: row.get("try_woodiness").and_then(|v| v.as_f64()),
            woodiness_text: row.get("try_woodiness").and_then(|v| v.as_str()).map(|s| s.to_string()),
            leaf_type: row.get("try_leaf_type").and_then(|v| v.as_str()).map(|s| s.to_string()),
            leaf_phenology: row.get("try_leaf_phenology").and_then(|v| v.as_str()).map(|s| s.to_string()),
            photosynthesis_pathway: row.get("try_photosynthesis_pathway").and_then(|v| v.as_str()).map(|s| s.to_string()),
            mycorrhiza_type: row.get("try_mycorrhiza_type").and_then(|v| v.as_str()).map(|s| s.to_string()),
        })
    }
}

/// Generate Section 1: Plant Identity Card
///
/// Creates taxonomic and morphological summary for encyclopedia header.
pub fn generate_identity_card(plant: &PlantIdentity) -> String {
    let mut lines = Vec::new();

    // Scientific name as header
    lines.push(format!("**{}**", plant.scientific_name));

    // Taxonomy line
    let family = plant.family.as_deref().unwrap_or("Unknown family");
    let genus = plant.genus.as_deref().unwrap_or("Unknown genus");
    lines.push(format!("*Family*: {} | *Genus*: {}", family, genus));
    lines.push(String::new()); // Blank line

    // Build description components
    let mut components = Vec::new();

    // Phenology
    if let Some(ref phenology) = plant.leaf_phenology {
        if !phenology.is_empty() {
            components.push(phenology.to_lowercase());
        }
    }

    // Woodiness
    let woodiness_text = get_woodiness_text(plant);
    if let Some(ref w) = woodiness_text {
        // Avoid redundancy with growth form
        let growth_form_lower = plant.growth_form.as_ref().map(|s| s.to_lowercase()).unwrap_or_default();
        if !growth_form_lower.contains(w.as_str()) {
            components.push(w.clone());
        }
    }

    // Growth form
    if let Some(ref form) = plant.growth_form {
        if !form.is_empty() {
            components.push(form.to_lowercase());
        }
    } else {
        components.push("plant".to_string());
    }

    // Height
    let height_text = if let Some(h) = plant.height_m {
        if let Some(cat) = categorize_height(h) {
            format!("{} ({:.1}m)", cat.as_lowercase(), h)
        } else {
            format!("{:.1}m", h)
        }
    } else {
        "height unknown".to_string()
    };

    // Assemble description line
    let description = components.join(" ");
    let description_sentence = capitalize_first(&description);
    lines.push(format!("{} - {}", description_sentence, height_text));

    // Leaf type
    if let Some(ref leaf_type) = plant.leaf_type {
        if !leaf_type.is_empty() {
            lines.push(format!("{} foliage", leaf_type.to_lowercase()));
        }
    }

    // Special adaptations
    let adaptations = get_special_adaptations(plant);
    if !adaptations.is_empty() {
        lines.push(format!("*Special traits*: {}", adaptations.join("; ")));
    }

    lines.join("\n")
}

/// Get woodiness text, handling both numeric and string formats
fn get_woodiness_text(plant: &PlantIdentity) -> Option<String> {
    // First check text label
    if let Some(ref text) = plant.woodiness_text {
        match text.as_str() {
            "non-woody" => return Some("herbaceous".to_string()),
            "semi-woody" | "woody" => return Some(text.to_lowercase()),
            _ => {}
        }
    }

    // Then try numeric
    if let Some(w) = plant.woodiness {
        if let Some(cat) = categorize_woodiness(w) {
            return Some(cat.as_lowercase().to_string());
        }
    }

    None
}

/// Get list of special adaptations
fn get_special_adaptations(plant: &PlantIdentity) -> Vec<String> {
    let mut adaptations = Vec::new();

    // Photosynthesis pathway
    if let Some(ref pathway) = plant.photosynthesis_pathway {
        match pathway.as_str() {
            "CAM" => adaptations.push("Drought-adapted (CAM photosynthesis)".to_string()),
            "C4" => adaptations.push("Heat-efficient (C4 photosynthesis)".to_string()),
            _ => {}
        }
    }

    // Mycorrhizal associations
    if let Some(ref myco) = plant.mycorrhiza_type {
        if !myco.is_empty() && myco.to_lowercase() != "none" {
            adaptations.push(format!("Forms {} associations", myco.to_lowercase()));
        }
    }

    adaptations
}

/// Capitalize first letter of string
fn capitalize_first(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        None => String::new(),
        Some(first) => first.to_uppercase().chain(chars).collect(),
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    fn make_test_plant() -> PlantIdentity {
        PlantIdentity {
            scientific_name: "Quercus robur".to_string(),
            family: Some("Fagaceae".to_string()),
            genus: Some("Quercus".to_string()),
            height_m: Some(25.0),
            growth_form: Some("tree".to_string()),
            woodiness: Some(1.0),
            woodiness_text: Some("woody".to_string()),
            leaf_type: Some("broadleaf".to_string()),
            leaf_phenology: Some("deciduous".to_string()),
            photosynthesis_pathway: Some("C3".to_string()),
            mycorrhiza_type: Some("ectomycorrhizal".to_string()),
        }
    }

    #[test]
    fn test_identity_card_contains_scientific_name() {
        let plant = make_test_plant();
        let card = generate_identity_card(&plant);
        assert!(card.contains("**Quercus robur**"), "Should contain scientific name");
    }

    #[test]
    fn test_identity_card_contains_taxonomy() {
        let plant = make_test_plant();
        let card = generate_identity_card(&plant);
        assert!(card.contains("Fagaceae"), "Should contain family");
        assert!(card.contains("Quercus"), "Should contain genus");
    }

    #[test]
    fn test_identity_card_contains_height() {
        let plant = make_test_plant();
        let card = generate_identity_card(&plant);
        assert!(card.contains("25.0m") || card.contains("very tall"), "Should contain height info");
    }

    #[test]
    fn test_identity_card_contains_growth_form() {
        let plant = make_test_plant();
        let card = generate_identity_card(&plant);
        assert!(card.contains("tree"), "Should contain growth form");
    }

    #[test]
    fn test_identity_card_contains_phenology() {
        let plant = make_test_plant();
        let card = generate_identity_card(&plant);
        // Output capitalizes first letter, so use case-insensitive check
        assert!(card.to_lowercase().contains("deciduous"), "Should contain phenology");
    }

    #[test]
    fn test_identity_card_contains_mycorrhiza() {
        let plant = make_test_plant();
        let card = generate_identity_card(&plant);
        assert!(card.contains("ectomycorrhizal"), "Should contain mycorrhiza type");
    }

    #[test]
    fn test_identity_card_handles_minimal_data() {
        let plant = PlantIdentity {
            scientific_name: "Unknown species".to_string(),
            family: None,
            genus: None,
            height_m: None,
            growth_form: None,
            woodiness: None,
            woodiness_text: None,
            leaf_type: None,
            leaf_phenology: None,
            photosynthesis_pathway: None,
            mycorrhiza_type: None,
        };
        let card = generate_identity_card(&plant);
        assert!(card.contains("Unknown species"));
        assert!(card.contains("Unknown family"));
        assert!(card.contains("height unknown"));
    }

    #[test]
    fn test_cam_adaptation() {
        let mut plant = make_test_plant();
        plant.photosynthesis_pathway = Some("CAM".to_string());
        let card = generate_identity_card(&plant);
        assert!(card.contains("CAM") || card.contains("Drought-adapted"));
    }
}
