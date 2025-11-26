//! S1: Identity Card
//!
//! Rules for generating the plant identity/header section of encyclopedia articles.
//!
//! Data Sources:
//! - Scientific name: `wfo_scientific_name` (WFO-verified)
//! - WFO ID: `wfo_taxon_id` (WFO backbone)
//! - Family: `family` (WFO/TRY)
//! - Genus: `genus` (WFO/TRY)
//! - Growth form: `try_growth_form` (TRY database)
//! - Height: `height_m` (TRY database)
//! - Leaf persistence: `try_leaf_phenology` (TRY database)
//! - Hardiness: derived from `TNn_q05`

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::*;
use crate::encyclopedia::utils::classify::*;

/// Generate the S1 Identity Card section.
pub fn generate(data: &HashMap<String, Value>) -> String {
    let mut sections = Vec::new();

    // Scientific name as header
    let scientific_name = get_str(data, "wfo_scientific_name")
        .unwrap_or("Unknown species");
    sections.push(format!("# {}", scientific_name));

    // Basic taxonomy
    let family = get_str(data, "family").unwrap_or("Unknown");
    let _genus = get_str(data, "genus").unwrap_or("Unknown");
    sections.push(format!("**Family**: {}", family));

    // Growth form with label translation
    let growth_form = get_str(data, "try_growth_form");
    let growth_label = translate_growth_form(growth_form);
    sections.push(format!("**Growth Form**: {}", growth_label));

    // Height with category
    let height_m = get_f64(data, "height_m");
    let height_category = classify_height_category(height_m);
    match height_m {
        Some(h) => sections.push(format!("**Height**: {:.1}m ({})", h, height_category)),
        None => sections.push("**Height**: Unknown".to_string()),
    }

    // Leaf phenology
    let leaf_phenology = get_str(data, "try_leaf_phenology");
    let leaf_label = translate_leaf_phenology(leaf_phenology);
    if !leaf_label.is_empty() {
        sections.push(format!("**Leaf Type**: {}", leaf_label));
    }

    // Hardiness zone from TNn_q05 (stored in Kelvin, convert to Celsius)
    let tnn_q05_k = get_f64(data, "TNn_q05");
    let tnn_q05_c = tnn_q05_k.map(|k| k - 273.15);
    if let Some((_zone, label)) = classify_hardiness_zone(tnn_q05_c) {
        let temp_str = tnn_q05_c.map(|t| format!(" ({:.0}°C)", t)).unwrap_or_default();
        sections.push(format!("**Hardiness**: {}{}", label, temp_str));
    }

    // Woodiness
    let woodiness = get_str(data, "try_woodiness");
    if let Some(w) = woodiness {
        if !w.is_empty() && w != "NA" {
            sections.push(format!("**Woodiness**: {}", capitalize_first(w)));
        }
    }

    sections.join("\n")
}

/// Translate growth form code to human-readable label.
fn translate_growth_form(growth_form: Option<&str>) -> String {
    match growth_form {
        Some(form) => {
            let form_lower = form.to_lowercase();
            if form_lower.contains("tree") {
                "Tree".to_string()
            } else if form_lower.contains("shrub") {
                "Shrub".to_string()
            } else if form_lower.contains("herb") {
                "Herbaceous".to_string()
            } else if form_lower.contains("graminoid") || form_lower.contains("grass") {
                "Grass/Sedge".to_string()
            } else if form_lower.contains("vine") || form_lower.contains("liana") || form_lower.contains("climber") {
                "Climber".to_string()
            } else if form_lower.contains("fern") {
                "Fern".to_string()
            } else if form_lower.contains("succulent") {
                "Succulent".to_string()
            } else {
                capitalize_first(form)
            }
        }
        None => "Unknown".to_string(),
    }
}

/// Translate leaf phenology code to human-readable label.
fn translate_leaf_phenology(phenology: Option<&str>) -> String {
    match phenology {
        Some(p) => {
            let p_lower = p.to_lowercase();
            if p_lower.contains("evergreen") {
                "Evergreen".to_string()
            } else if p_lower.contains("deciduous") {
                "Deciduous".to_string()
            } else if p_lower.contains("semi") {
                "Semi-evergreen".to_string()
            } else if p == "NA" || p.is_empty() {
                String::new()
            } else {
                capitalize_first(p)
            }
        }
        None => String::new(),
    }
}

/// Capitalize the first letter of a string.
fn capitalize_first(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        None => String::new(),
        Some(first) => first.to_uppercase().chain(chars).collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_translate_growth_form() {
        assert_eq!(translate_growth_form(Some("tree")), "Tree");
        assert_eq!(translate_growth_form(Some("shrub")), "Shrub");
        assert_eq!(translate_growth_form(Some("vine")), "Climber");
        assert_eq!(translate_growth_form(None), "Unknown");
    }

    #[test]
    fn test_translate_leaf_phenology() {
        assert_eq!(translate_leaf_phenology(Some("evergreen")), "Evergreen");
        assert_eq!(translate_leaf_phenology(Some("deciduous")), "Deciduous");
        assert_eq!(translate_leaf_phenology(Some("NA")), "");
    }
}
