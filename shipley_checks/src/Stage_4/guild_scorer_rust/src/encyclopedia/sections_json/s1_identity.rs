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

use crate::encyclopedia::types::{get_str, get_f64, get_usize, CsrStrategy as CsrStrategyEnum};
use crate::encyclopedia::utils::classify::classify_csr_spread;
use crate::encyclopedia::view_models::{
    IdentityCard, HeightInfo, LeafInfo, SeedInfo, GrowthIcon, CsrStrategy,
};

/// Generate the S1 Identity Card section.
///
/// # Arguments
/// * `wfo_id` - WFO taxon ID
/// * `data` - Plant data from parquet
pub fn generate(
    wfo_id: &str,
    data: &HashMap<String, Value>,
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

    let native_climate = build_native_climate(data);

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

    // CSR Strategy
    let csr_strategy = build_csr_strategy(data);

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
        csr_strategy,
    }
}

/// Build CSR Strategy from plant data.
fn build_csr_strategy(data: &HashMap<String, Value>) -> Option<CsrStrategy> {
    let c = get_f64(data, "C")?;
    let s = get_f64(data, "S")?;
    let r = get_f64(data, "R")?;

    let strategy = classify_csr_spread(c, s, r);
    let dominant = match strategy {
        CsrStrategyEnum::CDominant => "Competitor".to_string(),
        CsrStrategyEnum::SDominant => "Stress-tolerator".to_string(),
        CsrStrategyEnum::RDominant => "Ruderal".to_string(),
        CsrStrategyEnum::Balanced => "Balanced".to_string(),
    };

    let description = match strategy {
        CsrStrategyEnum::CDominant => {
            "Vigorous grower that actively spreads and may outcompete neighbours. Needs more attention to keep in check.".to_string()
        }
        CsrStrategyEnum::SDominant => {
            "Built for endurance, not speed. Grows slowly, tolerates neglect, and generally thrives when left alone.".to_string()
        }
        CsrStrategyEnum::RDominant => {
            "Fast-living opportunist. Grows quickly, sets seed, and may not live long. Plan for replacement or let it reseed.".to_string()
        }
        CsrStrategyEnum::Balanced => {
            "Adaptable and moderate in all respects. Neither aggressive nor demanding, it fits well in most garden situations.".to_string()
        }
    };

    Some(CsrStrategy {
        c_percent: c,
        s_percent: s,
        r_percent: r,
        dominant,
        description,
    })
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
    match code {
        // Tropical (A) - warm year-round, >18°C every month
        "Af" => "Tropical rainforest".to_string(),
        "Am" => "Tropical monsoon".to_string(),
        "Aw" | "As" => "Tropical savanna".to_string(),

        // Arid (B) - evaporation exceeds precipitation
        "BWh" => "Hot desert".to_string(),
        "BWk" => "Cold desert".to_string(),
        "BSh" => "Hot semi-arid".to_string(),
        "BSk" => "Cold semi-arid".to_string(),

        // Mediterranean (Cs) - dry summers, mild wet winters
        "Csa" => "Mediterranean (hot summer)".to_string(),
        "Csb" => "Mediterranean (warm summer)".to_string(),
        "Csc" => "Mediterranean (cool summer)".to_string(),

        // Humid subtropical / Oceanic (Cf, Cw)
        "Cfa" => "Humid subtropical".to_string(),
        "Cfb" => "Oceanic (mild year-round)".to_string(),
        "Cfc" => "Subpolar oceanic".to_string(),
        "Cwa" => "Subtropical (dry winter)".to_string(),
        "Cwb" | "Cwc" => "Subtropical highland".to_string(),

        // Continental (D) - cold winters, <0°C at least one month
        "Dfa" => "Humid continental (hot summer)".to_string(),
        "Dfb" => "Humid continental (warm summer)".to_string(),
        "Dfc" | "Dfd" => "Subarctic".to_string(),
        "Dwa" | "Dwb" => "Continental (dry winter)".to_string(),
        "Dwc" | "Dwd" => "Subarctic (dry winter)".to_string(),
        "Dsa" | "Dsb" => "Continental Mediterranean".to_string(),
        "Dsc" | "Dsd" => "Subarctic Mediterranean".to_string(),

        // Polar (E) - cold year-round
        "ET" | "ETf" => "Tundra".to_string(),
        "EF" => "Ice cap".to_string(),

        // Special cases
        "Ocean" => "Oceanic".to_string(),

        // Fallback: use first letter for unknown sub-codes
        _ => match code.chars().next() {
            Some('A') => "Tropical".to_string(),
            Some('B') => "Arid".to_string(),
            Some('C') => "Temperate".to_string(),
            Some('D') => "Continental".to_string(),
            Some('E') => "Polar".to_string(),
            _ => format!("Climate zone: {}", code),
        },
    }
}

/// Build native climate string considering tier breadth.
/// - 4+ tiers: "Cosmopolitan"
/// - 2-3 tiers: "Primary zone (also: other tiers)"
/// - 1 tier: just the primary zone
fn build_native_climate(data: &HashMap<String, Value>) -> Option<String> {
    let top_zone = get_str(data, "top_zone_code")
        .filter(|s| !s.is_empty() && *s != "NA")?;

    let n_tiers = get_usize(data, "n_tier_memberships").unwrap_or(1);

    // 4+ tiers = cosmopolitan
    if n_tiers >= 4 {
        return Some("Cosmopolitan".to_string());
    }

    let primary = interpret_koppen(top_zone);

    // 1 tier = just primary
    if n_tiers <= 1 {
        return Some(primary);
    }

    // 2-3 tiers = primary + also list
    let mut other_tiers = Vec::new();
    if get_bool(data, "tier_1_tropical") { other_tiers.push("Tropical"); }
    if get_bool(data, "tier_2_mediterranean") { other_tiers.push("Mediterranean"); }
    if get_bool(data, "tier_3_humid_temperate") { other_tiers.push("Temperate"); }
    if get_bool(data, "tier_4_continental") { other_tiers.push("Continental"); }
    if get_bool(data, "tier_5_boreal_polar") { other_tiers.push("Boreal"); }
    if get_bool(data, "tier_6_arid") { other_tiers.push("Arid"); }

    // Remove the primary tier from the "also" list
    let primary_tier = koppen_to_tier_name(top_zone);
    other_tiers.retain(|t| *t != primary_tier);

    if other_tiers.is_empty() {
        Some(primary)
    } else {
        Some(format!("{} (also: {})", primary, other_tiers.join(", ")))
    }
}

fn get_bool(data: &HashMap<String, Value>, key: &str) -> bool {
    data.get(key)
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

/// Map Köppen code to tier name for filtering
fn koppen_to_tier_name(code: &str) -> &'static str {
    match code.chars().next() {
        Some('A') => "Tropical",
        Some('B') => "Arid",
        Some('C') => {
            if code.len() >= 2 && code.chars().nth(1) == Some('s') {
                "Mediterranean"
            } else {
                "Temperate"
            }
        }
        Some('D') => {
            if code.len() >= 3 {
                let third = code.chars().nth(2);
                if third == Some('c') || third == Some('d') {
                    "Boreal"
                } else {
                    "Continental"
                }
            } else {
                "Continental"
            }
        }
        Some('E') => "Boreal",
        _ => "",
    }
}
