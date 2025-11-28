//! S1: Identity Card
//!
//! Rules for generating the plant identity/header section of encyclopedia articles.
//! Displays scientific name, vernacular names, and key morphological traits.
//!
//! Data Sources:
//! - Scientific name: `wfo_scientific_name` (WFO-verified)
//! - Vernacular names: `vernacular_name_en`, `vernacular_name_zh` (iNaturalist via Phase 1)
//! - Family: `family` (WFO/TRY)
//! - Growth form: `try_growth_form` (TRY database)
//! - Height: `height_m` (TRY Global Spectrum - mature plant height)
//! - Leaf area: `LA` (TRY Global Spectrum - leaf size in mm²)
//! - Seed mass: `logSM` (TRY Global Spectrum - log seed mass, convert with exp())
//! - Leaf type: `try_leaf_type` (broadleaved/needleleaved)
//! - Leaf persistence: `try_leaf_phenology` (TRY database)

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

    // English vernacular names (all names, formatted)
    if let Some(en_names) = get_str(data, "vernacular_name_en") {
        if !en_names.is_empty() && en_names != "NA" {
            let formatted = format_vernacular_list(en_names);
            sections.push(format!("**Common Names**: {}", formatted));
        }
    }

    // Chinese vernacular names
    if let Some(zh_names) = get_str(data, "vernacular_name_zh") {
        if !zh_names.is_empty() && zh_names != "NA" {
            sections.push(format!("**Chinese**: {}", zh_names));
        }
    }

    // Basic taxonomy
    let family = get_str(data, "family").unwrap_or("Unknown");
    sections.push(format!("**Family**: {}", family));

    // Growth form with label translation, combined with woodiness where appropriate
    let growth_form = get_str(data, "try_growth_form");
    let woodiness = get_str(data, "try_woodiness");
    let leaf_phenology = get_str(data, "try_leaf_phenology");
    let growth_label = translate_growth_form_full(growth_form, woodiness, leaf_phenology);
    sections.push(format!("**Type**: {}", growth_label));

    // Mature height with friendly description
    let height_m = get_f64(data, "height_m");
    if let Some(h) = height_m {
        let height_desc = format_height_friendly(h);
        sections.push(format!("**Mature Height**: {}", height_desc));
    }

    // Leaf size (from LA column - leaf area in mm²)
    let leaf_area = get_f64(data, "LA");
    let leaf_type = get_str(data, "try_leaf_type");
    if let Some(la) = leaf_area {
        let leaf_desc = format_leaf_size_friendly(la, leaf_type);
        sections.push(format!("**Leaves**: {}", leaf_desc));
    }

    // Seed size (from logSM - need to exp() to get mg)
    let log_sm = get_f64(data, "logSM");
    if let Some(lsm) = log_sm {
        let seed_mg = lsm.exp();
        let seed_desc = format_seed_size_friendly(seed_mg);
        sections.push(format!("**Seeds**: {}", seed_desc));
    }

    // Data provenance note
    sections.push(String::new()); // blank line
    sections.push("*Taxonomy from World Flora Online. Plant characteristics from TRY database. Vernacular names from iNaturalist.*".to_string());

    sections.join("\n")
}

/// Format height with friendly description.
/// Height is mature plant height from TRY Global Spectrum dataset.
fn format_height_friendly(height_m: f64) -> String {
    if height_m >= 20.0 {
        format!("{:.0}m — Large tree, needs significant space", height_m)
    } else if height_m >= 10.0 {
        format!("{:.0}m — Medium tree", height_m)
    } else if height_m >= 4.0 {
        format!("{:.0}m — Small tree or large shrub", height_m)
    } else if height_m >= 1.5 {
        format!("{:.1}m — Shrub height", height_m)
    } else if height_m >= 0.5 {
        format!("{:.1}m — Low shrub or tall groundcover", height_m)
    } else if height_m >= 0.1 {
        format!("{:.0}cm — Low groundcover", height_m * 100.0)
    } else {
        format!("{:.0}cm — Creeping or mat-forming", height_m * 100.0)
    }
}

/// Format leaf size with friendly description.
fn format_leaf_size_friendly(leaf_area_mm2: f64, leaf_type: Option<&str>) -> String {
    let type_str = match leaf_type {
        Some(t) if t.to_lowercase().contains("needle") => "Needles",
        Some(t) if t.to_lowercase().contains("scale") => "Scale-like leaves",
        _ => "Broadleaved",
    };

    // Convert to cm² for readability
    let area_cm2 = leaf_area_mm2 / 100.0;

    let size_desc = if area_cm2 > 100.0 {
        format!("{:.0}cm² — Very large, bold foliage", area_cm2)
    } else if area_cm2 > 30.0 {
        format!("{:.0}cm² — Large leaves", area_cm2)
    } else if area_cm2 > 10.0 {
        format!("{:.0}cm² — Medium-sized", area_cm2)
    } else if area_cm2 > 3.0 {
        format!("{:.1}cm² — Small leaves", area_cm2)
    } else {
        format!("{:.1}cm² — Fine-textured foliage", area_cm2)
    };

    format!("{}, {}", type_str, size_desc)
}

/// Format seed size with friendly description.
/// Seed mass helps gardeners understand self-seeding potential and wildlife value.
fn format_seed_size_friendly(seed_mg: f64) -> String {
    if seed_mg >= 5000.0 {
        // > 5g - large nuts/fruits (acorns, walnuts)
        format!("{:.0}g — Large seeds/nuts, wildlife food", seed_mg / 1000.0)
    } else if seed_mg >= 500.0 {
        // 0.5-5g - medium seeds (beans, peas)
        format!("{:.1}g — Medium seeds, bird food", seed_mg / 1000.0)
    } else if seed_mg >= 10.0 {
        // 10-500mg - small seeds (rose hips, berries)
        format!("{:.0}mg — Small seeds", seed_mg)
    } else if seed_mg >= 1.0 {
        // 1-10mg - tiny seeds
        format!("{:.1}mg — Tiny seeds, may self-sow", seed_mg)
    } else {
        // < 1mg - dust-like (clover, orchids)
        format!("{:.2}mg — Dust-like, spreads freely", seed_mg)
    }
}

/// Translate growth form with full context (woodiness + phenology).
fn translate_growth_form_full(
    growth_form: Option<&str>,
    woodiness: Option<&str>,
    phenology: Option<&str>,
) -> String {
    let is_deciduous = phenology
        .map(|p| p.to_lowercase().contains("deciduous"))
        .unwrap_or(false);
    let is_evergreen = phenology
        .map(|p| p.to_lowercase().contains("evergreen"))
        .unwrap_or(false);

    match growth_form {
        Some(form) => {
            let form_lower = form.to_lowercase();
            if form_lower.contains("tree") {
                if is_deciduous {
                    "Deciduous tree".to_string()
                } else if is_evergreen {
                    "Evergreen tree".to_string()
                } else {
                    "Tree".to_string()
                }
            } else if form_lower.contains("shrub") {
                if is_deciduous {
                    "Deciduous shrub".to_string()
                } else if is_evergreen {
                    "Evergreen shrub".to_string()
                } else {
                    "Shrub".to_string()
                }
            } else if form_lower.contains("herb") {
                "Herbaceous perennial".to_string()
            } else if form_lower.contains("graminoid") || form_lower.contains("grass") {
                "Grass or sedge".to_string()
            } else if form_lower.contains("vine") || form_lower.contains("liana") || form_lower.contains("climber") {
                // Woody climbers are often scrambling shrubs (e.g., Rosa)
                match woodiness {
                    Some(w) if w.to_lowercase().contains("woody") => {
                        if is_deciduous {
                            "Scrambling shrub (deciduous)".to_string()
                        } else {
                            "Scrambling shrub".to_string()
                        }
                    }
                    _ => "Climbing vine".to_string(),
                }
            } else if form_lower.contains("fern") {
                "Fern".to_string()
            } else if form_lower.contains("succulent") {
                "Succulent".to_string()
            } else {
                capitalize_first(form)
            }
        }
        None => {
            // Fall back to woodiness if no growth form
            match woodiness {
                Some(w) if w.to_lowercase().contains("woody") => "Woody plant".to_string(),
                Some(w) if w.to_lowercase().contains("herb") => "Herbaceous plant".to_string(),
                _ => "Unknown".to_string(),
            }
        }
    }
}

/// Format vernacular name list with Title Case and semicolon separation.
fn format_vernacular_list(raw: &str) -> String {
    raw.split(';')
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| to_title_case(s))
        .collect::<Vec<_>>()
        .join("; ")
}

/// Convert string to Title Case.
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

/// Translate growth form with woodiness into a readable plant type.
/// Combines growth form and woodiness to give clear plant type labels.
fn translate_growth_form_with_woodiness(growth_form: Option<&str>, woodiness: Option<&str>) -> String {
    let form_label = match growth_form {
        Some(form) => {
            let form_lower = form.to_lowercase();
            if form_lower.contains("tree") {
                "Deciduous tree"
            } else if form_lower.contains("shrub") {
                "Shrub"
            } else if form_lower.contains("herb") {
                "Herbaceous perennial"
            } else if form_lower.contains("graminoid") || form_lower.contains("grass") {
                "Grass/Sedge"
            } else if form_lower.contains("vine") || form_lower.contains("liana") || form_lower.contains("climber") {
                "Climber"
            } else if form_lower.contains("fern") {
                "Fern"
            } else if form_lower.contains("succulent") {
                "Succulent"
            } else {
                return capitalize_first(form);
            }
        }
        None => {
            // Fall back to woodiness if no growth form
            return match woodiness {
                Some(w) if w.to_lowercase().contains("woody") => "Woody plant".to_string(),
                Some(w) if w.to_lowercase().contains("herb") => "Herbaceous plant".to_string(),
                _ => "Unknown".to_string(),
            };
        }
    };

    form_label.to_string()
}

/// Translate growth form code to human-readable label (simple version).
#[allow(dead_code)]
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

/// Interpret Köppen-Geiger climate code with human-readable label.
fn interpret_koppen_zone(code: &str) -> &'static str {
    match code {
        // Tropical (A)
        "Af" => "Tropical rainforest",
        "Am" => "Tropical monsoon",
        "Aw" | "As" => "Tropical savanna",

        // Arid (B)
        "BWh" => "Hot desert",
        "BWk" => "Cold desert",
        "BSh" => "Hot semi-arid",
        "BSk" => "Cold semi-arid",

        // Temperate (C)
        "Cfa" => "Humid subtropical",
        "Cfb" => "Temperate oceanic",
        "Cfc" => "Subpolar oceanic",
        "Csa" => "Mediterranean hot summer",
        "Csb" => "Mediterranean warm summer",
        "Csc" => "Mediterranean cool summer",
        "Cwa" => "Humid subtropical (dry winter)",
        "Cwb" | "Cwc" => "Subtropical highland",

        // Continental (D)
        "Dfa" | "Dfb" => "Humid continental",
        "Dfc" | "Dfd" => "Subarctic",
        "Dwa" | "Dwb" | "Dwc" | "Dwd" => "Continental (dry winter)",
        "Dsa" | "Dsb" | "Dsc" | "Dsd" => "Continental Mediterranean",

        // Polar (E)
        "ET" => "Tundra",
        "EF" => "Ice cap",

        _ => "Unknown climate type",
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
