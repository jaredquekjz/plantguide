//! Section 2: Growing Requirements (Site Selection)
//!
//! Translates EIVE indicators, CSR strategy, and Köppen climate data into
//! user-friendly site selection and growing requirement advice.
//!
//! Ported from R: shipley_checks/src/encyclopedia/sections/s2_growing_requirements.R

use crate::encyclopedia::utils::lookup_tables::{get_eive_label, EiveAxis};
use crate::encyclopedia::utils::categorization::map_koppen_to_usda;
use std::collections::HashMap;

/// Plant data needed for growing requirements
pub struct GrowingRequirementsData {
    pub eive_l: Option<f64>,
    pub eive_m: Option<f64>,
    pub eive_t: Option<f64>,
    pub eive_n: Option<f64>,
    pub eive_r: Option<f64>,
    pub csr_c: Option<f64>,
    pub csr_s: Option<f64>,
    pub csr_r: Option<f64>,
    pub koppen_tiers: Vec<u8>, // Active tiers (1-6)
    pub n_tier_memberships: Option<u8>,
}

impl GrowingRequirementsData {
    pub fn from_row(row: &HashMap<String, serde_json::Value>) -> Self {
        let mut koppen_tiers = Vec::new();

        // Check each Köppen tier column
        for tier in 1..=6 {
            let col_names = [
                format!("tier_{}_tropical", tier),
                format!("tier_{}_mediterranean", tier),
                format!("tier_{}_humid_temperate", tier),
                format!("tier_{}_continental", tier),
                format!("tier_{}_boreal_polar", tier),
                format!("tier_{}_arid", tier),
            ];

            for col in &col_names {
                if let Some(val) = row.get(col) {
                    if val.as_bool().unwrap_or(false) {
                        koppen_tiers.push(tier as u8);
                        break;
                    }
                }
            }
        }

        Self {
            eive_l: row.get("EIVE_L").and_then(|v| v.as_f64()),
            eive_m: row.get("EIVE_M").and_then(|v| v.as_f64()),
            eive_t: row.get("EIVE_T").and_then(|v| v.as_f64()),
            eive_n: row.get("EIVE_N").and_then(|v| v.as_f64()),
            eive_r: row.get("EIVE_R").and_then(|v| v.as_f64()),
            csr_c: row.get("C").and_then(|v| v.as_f64()).or_else(|| row.get("C_norm").and_then(|v| v.as_f64())),
            csr_s: row.get("S").and_then(|v| v.as_f64()).or_else(|| row.get("S_norm").and_then(|v| v.as_f64())),
            csr_r: row.get("R").and_then(|v| v.as_f64()).or_else(|| row.get("R_norm").and_then(|v| v.as_f64())),
            koppen_tiers,
            n_tier_memberships: row.get("n_tier_memberships").and_then(|v| v.as_u64()).map(|v| v as u8),
        }
    }
}

/// Generate Section 2: Growing Requirements
pub fn generate_growing_requirements(data: &GrowingRequirementsData) -> String {
    let mut sections = Vec::new();

    sections.push("## Growing Requirements".to_string());
    sections.push(String::new());

    // Light
    sections.push(generate_light_advice(data.eive_l));

    // Water
    sections.push(generate_water_advice(data.eive_m, data.csr_s));

    // Climate
    sections.push(generate_climate_advice(&data.koppen_tiers, data.n_tier_memberships));

    // Fertility
    sections.push(generate_fertility_advice(data.eive_n, data.csr_c));

    // pH
    sections.push(generate_ph_advice(data.eive_r));

    sections.join("\n\n")
}

fn generate_light_advice(eive_l: Option<f64>) -> String {
    let Some(l) = eive_l else {
        return "☀️ **Light**: Requirements unknown".to_string();
    };

    let label = get_eive_label(l, EiveAxis::Light).unwrap_or("unknown");

    let advice = if l < 3.0 {
        "Plant in shade beneath trees or north-facing sites"
    } else if l < 5.0 {
        "Suitable for partial shade or dappled light"
    } else if l < 7.0 {
        "Prefers open sites with good light but tolerates some shade"
    } else {
        "Requires full sun in open positions"
    };

    format!(
        "☀️ **Light**: {} (EIVE-L: {:.1}/10)\n   → {}",
        capitalize_first(label),
        l,
        advice
    )
}

fn generate_water_advice(eive_m: Option<f64>, csr_s: Option<f64>) -> String {
    let Some(m) = eive_m else {
        return "💧 **Water**: Requirements unknown".to_string();
    };

    let label = get_eive_label(m, EiveAxis::Moisture).unwrap_or("unknown");

    let mut advice = if m < 2.0 {
        "Requires very dry conditions; avoid irrigation after establishment".to_string()
    } else if m < 4.0 {
        "Water sparingly; allow soil to dry between waterings".to_string()
    } else if m < 6.0 {
        "Water regularly during growing season; moderate moisture".to_string()
    } else if m < 8.0 {
        "Keep consistently moist; do not allow to dry out".to_string()
    } else {
        "Requires waterlogged or aquatic conditions; plant in bog or pond".to_string()
    };

    // Add drought tolerance note for S-dominant plants
    if let Some(s) = csr_s {
        let s_norm = if s > 1.0 { s / 100.0 } else { s };
        if s_norm > 0.5 && m < 6.0 {
            advice.push_str(" | Drought-tolerant once established (stress-tolerator strategy)");
        }
    }

    format!(
        "💧 **Water**: {} (EIVE-M: {:.1}/10)\n   → {}",
        capitalize_first(label),
        m,
        advice
    )
}

fn generate_climate_advice(tiers: &[u8], n_memberships: Option<u8>) -> String {
    if tiers.is_empty() {
        return "🌡️ **Climate**: Climate preferences unknown".to_string();
    }

    let tier_names: Vec<&str> = tiers
        .iter()
        .filter_map(|&t| match t {
            1 => Some("Tropical"),
            2 => Some("Mediterranean"),
            3 => Some("Humid Temperate"),
            4 => Some("Continental"),
            5 => Some("Boreal/Polar"),
            6 => Some("Arid"),
            _ => None,
        })
        .collect();

    let adaptability = match n_memberships {
        Some(n) if n >= 4 => "Highly adaptable across diverse climates",
        Some(n) if n >= 2 => "Adaptable to multiple climate types",
        _ => "Specialized climate requirements",
    };

    let usda = tiers.first().and_then(|&t| map_koppen_to_usda(t)).unwrap_or("varies");

    format!(
        "🌡️ **Climate**: {} climates\n   → {}\n   → Approximate USDA zones: {}",
        tier_names.join(", "),
        adaptability,
        usda
    )
}

fn generate_fertility_advice(eive_n: Option<f64>, csr_c: Option<f64>) -> String {
    let Some(n) = eive_n else {
        return "🌱 **Fertility**: Requirements unknown".to_string();
    };

    let label = get_eive_label(n, EiveAxis::Nitrogen).unwrap_or("unknown");

    let mut advice = if n < 2.0 {
        "Thrives in infertile soils; avoid fertilizing".to_string()
    } else if n < 4.0 {
        "Low fertility needs; light annual feeding sufficient".to_string()
    } else if n < 6.0 {
        "Moderate fertility; balanced fertilizer in spring".to_string()
    } else if n < 8.0 {
        "Hungry feeder; fertilize monthly during growing season".to_string()
    } else {
        "Extremely high nutrient needs; heavy fertilization required".to_string()
    };

    // Add note for C-dominant plants
    if let Some(c) = csr_c {
        let c_norm = if c > 1.0 { c / 100.0 } else { c };
        if c_norm > 0.5 && n >= 5.0 {
            advice.push_str(" | Vigorous grower; benefits from rich soil");
        }
    }

    format!(
        "🌱 **Fertility**: {} (EIVE-N: {:.1}/10)\n   → {}",
        capitalize_first(label),
        n,
        advice
    )
}

fn generate_ph_advice(eive_r: Option<f64>) -> String {
    let Some(r) = eive_r else {
        return "⚗️ **pH**: Requirements unknown".to_string();
    };

    let label = get_eive_label(r, EiveAxis::Reaction).unwrap_or("unknown");

    let advice = if r < 3.0 {
        "Requires acidic conditions; use ericaceous compost | pH 4.0-5.5"
    } else if r < 5.0 {
        "Prefers acidic to neutral soil; avoid lime | pH 5.0-6.5"
    } else if r < 7.0 {
        "Adaptable to slightly acidic to neutral soil | pH 6.0-7.0"
    } else if r < 9.0 {
        "Tolerates alkaline conditions; can add lime | pH 6.5-8.0"
    } else {
        "Requires alkaline soil; thrives on chalk or limestone | pH 7.5-8.5"
    };

    format!(
        "⚗️ **pH**: {} (EIVE-R: {:.1}/10)\n   → {}",
        capitalize_first(label),
        r,
        advice
    )
}

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
    fn test_light_advice_shade() {
        let advice = generate_light_advice(Some(2.5));
        assert!(advice.contains("shade") || advice.contains("Shade"));
    }

    #[test]
    fn test_light_advice_full_sun() {
        let advice = generate_light_advice(Some(8.5));
        assert!(advice.contains("full sun") || advice.contains("light-loving"));
    }

    #[test]
    fn test_water_advice_dry() {
        let advice = generate_water_advice(Some(1.5), None);
        assert!(advice.contains("dry"));
    }

    #[test]
    fn test_water_advice_drought_tolerant() {
        let advice = generate_water_advice(Some(3.0), Some(0.7));
        assert!(advice.contains("Drought-tolerant"));
    }

    #[test]
    fn test_ph_advice_acidic() {
        let advice = generate_ph_advice(Some(2.0));
        assert!(advice.contains("acidic") || advice.contains("ericaceous"));
    }

    #[test]
    fn test_ph_advice_alkaline() {
        let advice = generate_ph_advice(Some(8.5));
        assert!(advice.contains("alkaline") || advice.contains("chalk"));
    }
}
