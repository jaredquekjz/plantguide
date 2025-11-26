//! S2: Growing Requirements
//!
//! Integrates climate envelope, soil envelope, and EIVE indicators using
//! the triangulation principle: present both occurrence-based perspectives.
//!
//! Data Sources:
//! - EIVE indicators: `EIVEres-L`, `EIVEres-M`, `EIVEres-T`, `EIVEres-R`, `EIVEres-N`
//! - Climate envelope: `TNn_*`, `TXx_*`, `wc2.1_30s_bio_*`, `CDD_*`
//! - Soil envelope: `phh2o_0_5cm_*`, `clay_0_5cm_*`, `sand_0_5cm_*`, `soc_0_5cm_*`

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::*;
use crate::encyclopedia::utils::classify::*;

/// Generate the S2 Growing Requirements section.
pub fn generate(data: &HashMap<String, Value>) -> String {
    let mut sections = Vec::new();
    sections.push("## Growing Requirements".to_string());

    // Light requirements (EIVE-L only)
    sections.push(generate_light_section(data));

    // Climate conditions
    sections.push(generate_climate_section(data));

    // Soil conditions
    sections.push(generate_soil_section(data));

    sections.join("\n\n")
}

/// Try to get EIVE value from either column format
fn get_eive(data: &HashMap<String, Value>, axis: &str) -> Option<f64> {
    // Try new format first (plants_searchable), then old format (master dataset)
    get_f64(data, &format!("EIVE_{}_complete", axis))
        .or_else(|| get_f64(data, &format!("EIVEres-{}_complete", axis)))
        .or_else(|| get_f64(data, &format!("EIVE_{}", axis)))
        .or_else(|| get_f64(data, &format!("EIVEres-{}", axis)))
}

fn generate_light_section(data: &HashMap<String, Value>) -> String {
    let mut lines = Vec::new();
    lines.push("### Light".to_string());

    let eive_l = get_eive(data, "L");
    let label = eive_light_label(eive_l);

    match eive_l {
        Some(l) => {
            lines.push(format!("**EIVE-L**: {:.1}/10 - {}", l, label));
            lines.push(light_advice(l));
        }
        None => {
            lines.push("**EIVE-L**: Not available".to_string());
        }
    }

    lines.join("\n")
}

fn light_advice(eive_l: f64) -> String {
    if eive_l < 2.0 {
        "North-facing, woodland floor, shade garden.".to_string()
    } else if eive_l < 4.0 {
        "Under tree canopy, north/east-facing borders.".to_string()
    } else if eive_l < 6.0 {
        "Dappled light, morning sun, woodland edge.".to_string()
    } else if eive_l < 8.0 {
        "Open borders work well; tolerates some afternoon shade.".to_string()
    } else {
        "South-facing, open positions, no shade.".to_string()
    }
}

fn generate_climate_section(data: &HashMap<String, Value>) -> String {
    let mut lines = Vec::new();
    lines.push("### Climate".to_string());

    // Hardiness (cold tolerance)
    // Note: Temperature data is stored in Kelvin, convert to Celsius
    let tnn_q05_k = get_f64(data, "TNn_q05");
    let tnn_q05_c = tnn_q05_k.map(|k| k - 273.15);
    if let Some((_zone, label)) = classify_hardiness_zone(tnn_q05_c) {
        lines.push(format!("**Hardiness**: {} ({:.0}°C minimum)", label, tnn_q05_c.unwrap_or(0.0)));
        lines.push(cold_advice(tnn_q05_c.unwrap_or(0.0)));
    }

    // Heat tolerance
    // Note: Temperature data is stored in Kelvin, convert to Celsius
    let txx_q95_k = get_f64(data, "TXx_q95");
    let txx_q95_c = txx_q95_k.map(|k| k - 273.15);
    if let Some(t) = txx_q95_c {
        let heat_label = classify_heat_tolerance(t);
        lines.push(format!("**Heat Tolerance**: {} ({:.0}°C maximum)", heat_label, t));
    }

    // EIVE-T
    let eive_t = get_eive(data, "T");
    if let Some(t) = eive_t {
        lines.push(format!("**EIVE-T**: {:.1}/10 - {}", t, eive_temperature_label(Some(t))));
    }

    // Moisture section
    lines.push(String::new());
    lines.push("**Moisture**:".to_string());

    // Annual precipitation
    let bio12_q05 = get_f64(data, "wc2.1_30s_bio_12_q05");
    let bio12_q50 = get_f64(data, "wc2.1_30s_bio_12_q50");
    let bio12_q95 = get_f64(data, "wc2.1_30s_bio_12_q95");
    if bio12_q05.is_some() || bio12_q50.is_some() {
        lines.push(format!(
            "- Annual rainfall: {}-{}mm (median {}mm)",
            fmt_f64(bio12_q05, 0),
            fmt_f64(bio12_q95, 0),
            fmt_f64(bio12_q50, 0)
        ));
    }

    // Drought tolerance
    let cdd_q95 = get_f64(data, "CDD_q95");
    if let Some(cdd) = cdd_q95 {
        let drought_label = classify_drought_tolerance(cdd);
        lines.push(format!("- Drought tolerance: {}", drought_label));
    }

    // EIVE-M
    let eive_m = get_eive(data, "M");
    if let Some(m) = eive_m {
        lines.push(format!("- EIVE-M: {:.1}/10 - {}", m, eive_moisture_label(Some(m))));
        lines.push(format!("- Watering: {}", moisture_advice(m)));
    }

    lines.join("\n")
}

fn cold_advice(tnn_q05: f64) -> String {
    if tnn_q05 < -40.0 {
        "Extremely hardy; survives severe continental winters.".to_string()
    } else if tnn_q05 < -25.0 {
        "Very hardy; reliable in cold temperate climates.".to_string()
    } else if tnn_q05 < -15.0 {
        "Cold-hardy; survives hard frosts.".to_string()
    } else if tnn_q05 < -5.0 {
        "Moderately hardy; mulch roots in cold areas.".to_string()
    } else if tnn_q05 < 0.0 {
        "Half-hardy; protect from hard frost.".to_string()
    } else {
        "Frost-tender; requires frost protection.".to_string()
    }
}

fn classify_heat_tolerance(txx_q95: f64) -> &'static str {
    if txx_q95 > 45.0 {
        "Extreme heat (thrives in desert conditions)"
    } else if txx_q95 > 40.0 {
        "Very heat-tolerant (survives prolonged hot spells)"
    } else if txx_q95 > 35.0 {
        "Heat-tolerant (tolerates hot summers)"
    } else if txx_q95 > 30.0 {
        "Moderate (shade in extreme heat)"
    } else {
        "Cool-climate (struggles in hot summers; shade essential)"
    }
}

fn classify_drought_tolerance(cdd_q95: f64) -> &'static str {
    if cdd_q95 > 60.0 {
        "High (tolerates >2 months dry)"
    } else if cdd_q95 > 30.0 {
        "Moderate (tolerates dry spells)"
    } else if cdd_q95 > 14.0 {
        "Limited"
    } else {
        "Low (requires regular moisture)"
    }
}

fn moisture_advice(eive_m: f64) -> String {
    if eive_m < 2.0 {
        "Water sparingly; overwatering harmful.".to_string()
    } else if eive_m < 4.0 {
        "Deep infrequent watering.".to_string()
    } else if eive_m < 6.0 {
        "Regular watering in dry spells.".to_string()
    } else if eive_m < 8.0 {
        "Keep soil moist; don't let dry out.".to_string()
    } else {
        "Bog garden, pond margins, wet soil.".to_string()
    }
}

fn generate_soil_section(data: &HashMap<String, Value>) -> String {
    let mut lines = Vec::new();
    lines.push("### Soil".to_string());

    // pH/Reaction
    let ph_q05 = get_f64(data, "phh2o_0_5cm_q05");
    let ph_q50 = get_f64(data, "phh2o_0_5cm_q50");
    let ph_q95 = get_f64(data, "phh2o_0_5cm_q95");

    // Note: pH values may be stored as ×10 in raw data
    let (ph_q05_adj, ph_q50_adj, ph_q95_adj) = adjust_ph_values(ph_q05, ph_q50, ph_q95);

    if ph_q50_adj.is_some() {
        lines.push(format!(
            "**pH**: {}-{} (median {}) - {}",
            fmt_f64(ph_q05_adj, 1),
            fmt_f64(ph_q95_adj, 1),
            fmt_f64(ph_q50_adj, 1),
            classify_ph_regime(ph_q50_adj)
        ));
    }

    // EIVE-R
    let eive_r = get_eive(data, "R");
    if let Some(r) = eive_r {
        lines.push(format!("**EIVE-R**: {:.1}/10 - {}", r, eive_reaction_label(Some(r))));
        lines.push(format!("*{}*", ph_advice(r)));
    }

    // Fertility (CEC, Nitrogen)
    let cec_q50 = get_f64(data, "cec_0_5cm_q50");
    if let Some(cec) = cec_q50 {
        let fertility_label = classify_fertility(cec);
        lines.push(format!("**Fertility**: {} (CEC {} cmol/kg)", fertility_label, fmt_f64(Some(cec), 0)));
    }

    // EIVE-N
    let eive_n = get_eive(data, "N");
    if let Some(n) = eive_n {
        lines.push(format!("**EIVE-N**: {:.1}/10 - {}", n, eive_nitrogen_label(Some(n))));
        lines.push(format!("*{}*", nitrogen_advice(n)));
    }

    // Texture
    let clay_q50 = get_f64(data, "clay_0_5cm_q50");
    let sand_q95 = get_f64(data, "sand_0_5cm_q95");
    if clay_q50.is_some() || sand_q95.is_some() {
        let texture = classify_texture(clay_q50, sand_q95);
        lines.push(format!("**Texture**: {}", texture));
    }

    lines.join("\n")
}

/// Adjust pH values if they appear to be ×10 scaled.
fn adjust_ph_values(q05: Option<f64>, q50: Option<f64>, q95: Option<f64>) -> (Option<f64>, Option<f64>, Option<f64>) {
    // If median pH > 14, assume values are ×10
    match q50 {
        Some(v) if v > 14.0 => (
            q05.map(|x| x / 10.0),
            q50.map(|x| x / 10.0),
            q95.map(|x| x / 10.0),
        ),
        _ => (q05, q50, q95),
    }
}

fn classify_ph_regime(ph_q50: Option<f64>) -> &'static str {
    match ph_q50 {
        Some(ph) if ph < 5.0 => "Strongly acid soils (calcifuge)",
        Some(ph) if ph < 5.5 => "Moderately acid",
        Some(ph) if ph < 6.5 => "Slightly acid",
        Some(ph) if ph < 7.5 => "Neutral",
        Some(ph) if ph < 8.0 => "Slightly alkaline",
        Some(_) => "Calcareous/alkaline (calcicole)",
        None => "Unknown",
    }
}

fn ph_advice(eive_r: f64) -> String {
    if eive_r < 2.0 {
        "Ericaceous compost required; avoid lime.".to_string()
    } else if eive_r < 4.0 {
        "Acidic to neutral compost.".to_string()
    } else if eive_r < 6.0 {
        "Standard multipurpose compost.".to_string()
    } else if eive_r < 8.0 {
        "Tolerates some lime.".to_string()
    } else {
        "Lime-loving; add chalk if needed.".to_string()
    }
}

fn classify_fertility(cec: f64) -> &'static str {
    if cec < 5.0 {
        "Very low fertility"
    } else if cec < 10.0 {
        "Low fertility"
    } else if cec < 20.0 {
        "Moderate fertility"
    } else if cec < 30.0 {
        "Fertile"
    } else {
        "Very fertile"
    }
}

fn nitrogen_advice(eive_n: f64) -> String {
    if eive_n < 2.0 {
        "Light feeding only; excess N harmful.".to_string()
    } else if eive_n < 4.0 {
        "Minimal feeding; balanced NPK.".to_string()
    } else if eive_n < 6.0 {
        "Standard annual feeding.".to_string()
    } else if eive_n < 8.0 {
        "Benefits from generous feeding.".to_string()
    } else {
        "Heavy feeder; responds well to manure.".to_string()
    }
}

fn classify_texture(clay_q50: Option<f64>, sand_q95: Option<f64>) -> String {
    let clay_label = match clay_q50 {
        Some(c) if c > 35.0 => "Heavy clay",
        Some(c) if c > 25.0 => "Clay loam",
        Some(c) if c > 15.0 => "Loam",
        Some(_) => "Sandy loam/sand",
        None => return "Unknown".to_string(),
    };

    let sand_tolerance = match sand_q95 {
        Some(s) if s > 80.0 => "; tolerates very sandy",
        Some(s) if s > 65.0 => "; tolerates sandy",
        Some(s) if s > 50.0 => "; moderate sand tolerance",
        Some(_) => "; prefers heavier soils",
        None => "",
    };

    format!("{}{}", clay_label, sand_tolerance)
}
