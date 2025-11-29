//! S1: Identity Card
//!
//! Rules for generating the plant identity/header section of encyclopedia articles.
//! Displays scientific name, vernacular names, key morphological traits, and closest relatives.
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
//! - Related species: Phylogenetic tree (compact_tree_11711.bin)

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::*;

/// A related species with phylogenetic distance (merged from S7)
#[derive(Debug, Clone)]
pub struct RelatedSpecies {
    pub wfo_id: String,
    pub scientific_name: String,
    pub common_name: String,
    pub distance: f64,
}

/// Info about a species in the same genus
#[derive(Debug, Clone)]
pub struct GenusSpeciesInfo {
    pub wfo_id: String,
    pub scientific_name: String,
    pub common_name: String,
    pub tree_tip: Option<String>,
}

/// Generate the S1 Identity Card section (basic version without relatives).
pub fn generate(data: &HashMap<String, Value>) -> String {
    generate_with_relatives(data, None, 0)
}

/// Generate the S1 Identity Card section with optional related species.
pub fn generate_with_relatives(
    data: &HashMap<String, Value>,
    relatives: Option<&[RelatedSpecies]>,
    genus_count: usize,
) -> String {
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

    // Native climate (Köppen zone, grandma-friendly)
    if let Some(koppen) = get_str(data, "top_zone_code") {
        if !koppen.is_empty() && koppen != "NA" {
            let climate_desc = interpret_koppen_zone_friendly(koppen);
            sections.push(format!("**Native Climate**: {}", climate_desc));
        }
    }

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

    // Related species within genus (merged from S7)
    let genus = get_str(data, "genus").unwrap_or("Unknown");
    sections.push(String::new()); // blank line before relatives
    sections.push(generate_relatives_subsection(genus, relatives, genus_count));

    // Data provenance note
    sections.push(String::new()); // blank line
    sections.push("*Taxonomy from World Flora Online. Plant characteristics from TRY database. Vernacular names from iNaturalist.*".to_string());

    sections.join("\n")
}

/// Generate the Related Species subsection (within S1).
fn generate_relatives_subsection(
    genus: &str,
    relatives: Option<&[RelatedSpecies]>,
    genus_count: usize,
) -> String {
    let mut lines = Vec::new();
    lines.push("### Closest Relatives".to_string());
    lines.push(String::new());

    match relatives {
        Some(rel) if !rel.is_empty() => {
            lines.push(format!(
                "*5 closest {} (from {} *{}* species in database, by evolutionary distance):*",
                genus_plural(genus), genus_count, genus
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
                "*These {} need similar soil, water, and care—handy if you want alternatives. \
                But they catch the same bugs and diseases, so mix in plants from different families.*",
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

/// Convert phylogenetic distance to human-readable label.
/// Calibrated from actual tree distances: Trifolium ~2-35, Quercus ~24, Rosa ~68-141
fn distance_to_label(distance: f64) -> &'static str {
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

/// Get plural form for genus (most are just "species" but some common ones have names).
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

/// Capitalize the first letter of a string.
fn capitalize_first(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        None => String::new(),
        Some(first) => first.to_uppercase().chain(chars).collect(),
    }
}

/// Interpret Köppen-Geiger climate code with grandma-friendly description.
fn interpret_koppen_zone_friendly(code: &str) -> &'static str {
    match code {
        // Tropical (A) - warm all year (>18°C every month)
        "Af" => "Tropical rainforest (warm and wet all year)",
        "Am" => "Tropical monsoon (warm all year with seasonal heavy rains)",
        "Aw" | "As" => "Tropical savanna (warm all year with wet and dry seasons)",

        // Arid (B) - very dry
        "BWh" => "Hot desert (very hot and dry)",
        "BWk" => "Cold desert (dry with cold winters)",
        "BWn" => "Mild desert (dry with mild temperatures)",
        "BSh" => "Hot steppe (hot with limited rainfall)",
        "BSk" => "Cold steppe (cool to cold with limited rainfall)",
        "BSn" => "Mild steppe (mild with limited rainfall)",

        // Temperate (C) - mild winters (0-18°C coldest month)
        "Cfa" => "Humid subtropical (hot humid summers, mild winters)",
        "Cfb" => "Temperate oceanic (mild year-round, no dry season)",
        "Cfc" => "Subpolar oceanic (cool summers, mild winters)",
        "Csa" => "Hot-summer Mediterranean (hot dry summers, mild wet winters)",
        "Csb" => "Warm-summer Mediterranean (warm dry summers, mild wet winters)",
        "Csc" => "Cool-summer Mediterranean (cool summers, mild wet winters)",
        "Cwa" => "Humid subtropical (hot summers, dry winters)",
        "Cwb" | "Cwc" => "Subtropical highland (mild with dry winters)",

        // Continental (D) - cold winters (below 0°C at least one month)
        "Dfa" | "Dfb" => "Humid continental (warm summers, cold snowy winters)",
        "Dfc" | "Dfd" => "Subarctic (short cool summers, very cold winters)",
        "Dwa" | "Dwb" | "Dwc" | "Dwd" => "Monsoon continental (dry cold winters, wet summers)",
        "Dsa" | "Dsb" | "Dsc" | "Dsd" => "Continental Mediterranean (dry summers, cold winters)",

        // Polar (E) - cold all year (every month <10°C)
        "ET" => "Tundra (very cold, short growing season)",
        "ETf" => "Cold tundra (very cold with freezing months)",
        "EF" => "Ice cap (frozen year-round)",

        _ => "Not classified",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_height() {
        assert!(format_height_friendly(25.0).contains("Large tree"));
        assert!(format_height_friendly(0.2).contains("cm"));
    }

    #[test]
    fn test_translate_growth_form_full() {
        assert!(translate_growth_form_full(Some("tree"), None, Some("deciduous")).contains("Deciduous"));
        assert!(translate_growth_form_full(Some("shrub"), None, Some("evergreen")).contains("Evergreen"));
    }

    #[test]
    fn test_distance_labels() {
        assert_eq!(distance_to_label(3.0), "Very close");
        assert_eq!(distance_to_label(10.0), "Close");
        assert_eq!(distance_to_label(100.0), "Very distant");
    }

    #[test]
    fn test_koppen_friendly() {
        assert_eq!(interpret_koppen_zone_friendly("Cfb"), "Temperate oceanic (mild year-round, no dry season)");
        assert_eq!(interpret_koppen_zone_friendly("Csa"), "Hot-summer Mediterranean (hot dry summers, mild wet winters)");
    }
}
