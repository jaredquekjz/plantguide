//! S2: Growing Requirements
//!
//! Integrates climate envelope, soil envelope, and EIVE indicators using
//! the triangulation principle: present both occurrence-based perspectives.
//!
//! Data Sources:
//! - EIVE indicators: `EIVEres-L`, `EIVEres-M`, `EIVEres-T`, `EIVEres-R`, `EIVEres-N`
//! - Climate envelope: `TNn_*`, `TXx_*`, `wc2.1_30s_bio_*`, `CDD_*`
//! - Agroclimate indicators (Phase 2): `FD_*`, `CFD_*`, `TR_*`, `DTR_*`, `GSL_*`, `WW_*`
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
    lines.push(String::new());

    let eive_l = get_eive(data, "L");
    let label = eive_light_label(eive_l);

    match eive_l {
        Some(l) => {
            lines.push(format!("**EIVE-L**: {:.1}/10 - {}", l, label));
            lines.push(light_advice(l));
            lines.push(String::new());
            lines.push("*Light indicator from expert field observations of typical light conditions where species is most abundant in natural vegetation*".to_string());
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
    lines.push(String::new());

    // Extract key values for range summary
    let tnn_q05_k = get_f64(data, "TNn_q05");
    let txx_q95_k = get_f64(data, "TXx_q95");
    let tnn_q05_c = tnn_q05_k.map(|k| k - 273.15);
    let txx_q95_c = txx_q95_k.map(|k| k - 273.15);

    // Get mean temperatures
    // NOTE: WorldClim 2.x stores BIO5/BIO6 directly in °C (only v1.4 used °C × 10).
    // DO NOT divide by 10 - values are already in °C.
    let bio5_q50 = get_f64(data, "wc2.1_30s_bio_5_q50"); // Max temp warmest month (°C)
    let bio6_q50 = get_f64(data, "wc2.1_30s_bio_6_q50"); // Min temp coldest month (°C)

    let bio12_q05 = get_f64(data, "wc2.1_30s_bio_12_q05");
    let bio12_q50 = get_f64(data, "wc2.1_30s_bio_12_q50");
    let bio12_q95 = get_f64(data, "wc2.1_30s_bio_12_q95");
    let eive_t = get_eive(data, "T");
    let eive_m = get_eive(data, "M");

    // Add dual perspectives explanation with range summary
    lines.push("*This section shows where populations naturally occur (climate tolerance) and where species is most abundant (ecological indicators):*".to_string());
    lines.push(String::new());

    // Climate range summary
    if let (Some(cold), Some(hot)) = (tnn_q05_c, txx_q95_c) {
        lines.push(format!("**Temperature extremes**: Coldest winter night {:.0}°C, hottest summer day {:.0}°C", cold, hot));
    }
    if let (Some(warm_max), Some(cold_min)) = (bio5_q50, bio6_q50) {
        lines.push(format!("**Temperature means**: Average {:.0}°C in warmest month, {:.0}°C in coldest month", warm_max, cold_min));
    }
    if let Some(rain50) = bio12_q50 {
        lines.push(format!("**Annual rainfall**: {:.0}-{:.0}mm/year across populations (typically {:.0}mm)",
            bio12_q05.unwrap_or(0.0), bio12_q95.unwrap_or(0.0), rain50));
    } else if let (Some(dry), Some(wet)) = (bio12_q05, bio12_q95) {
        lines.push(format!("**Annual rainfall**: {:.0}-{:.0}mm/year (from driest to wettest populations)", dry, wet));
    }

    lines.push(String::new());
    lines.push("---".to_string());
    lines.push(String::new());

    // Köppen zones (from master dataset)
    if let Some(koppen) = get_str(data, "top_zone_code") {
        if !koppen.is_empty() && koppen != "NA" {
            let koppen_label = interpret_koppen_zone(koppen);
            lines.push(format!("**Köppen Zones**: {} ({})", koppen, koppen_label));
        }
    }

    // Cold tolerance - occurrence-based
    // Note: Temperature data is stored in Kelvin, convert to Celsius
    let tnn_q05_k = get_f64(data, "TNn_q05");
    let tnn_q05_c = tnn_q05_k.map(|k| k - 273.15);
    if let Some(cold) = tnn_q05_c {
        let descriptor = cold_descriptor(cold);
        lines.push(format!("**Cold tolerance**: Coldest populations survive {:.0}°C winter nights ({})", cold, descriptor));
    }

    // Heat tolerance - occurrence-based
    // Note: Temperature data is stored in Kelvin, convert to Celsius
    let txx_q95_k = get_f64(data, "TXx_q95");
    let txx_q95_c = txx_q95_k.map(|k| k - 273.15);
    if let Some(hot) = txx_q95_c {
        let heat_category = classify_heat_category(hot);
        lines.push(format!("**Heat tolerance**: Hottest populations experience {:.0}°C summer days ({})", hot, heat_category));
    }

    // Frost Days (FD) - annual frost count
    let fd_q05 = get_f64(data, "FD_q05");
    let fd_q50 = get_f64(data, "FD_q50");
    let fd_q95 = get_f64(data, "FD_q95");
    if let Some(fd50) = fd_q50 {
        let frost_regime = classify_frost_regime(fd50);
        lines.push(format!(
            "**Frost exposure**: {}-{} frost days/year (typically {:.0})",
            fmt_f64(fd_q05, 0),
            fmt_f64(fd_q95, 0),
            fd50
        ));
        lines.push(format!("*{}*", frost_regime));
    }

    // Consecutive Frost Days (CFD) - cold spell duration
    let cfd_q95 = get_f64(data, "CFD_q95");
    if let Some(cfd) = cfd_q95 {
        let cold_spell = classify_cold_spell(cfd);
        lines.push(format!(
            "**Cold spell tolerance**: Populations survive up to {:.0} consecutive frost days",
            cfd
        ));
        lines.push(format!("*{} - Can endure extended cold periods*", cold_spell));
    }

    // Tropical Nights (TR) - warm night count
    let tr_q05 = get_f64(data, "TR_q05");
    let tr_q50 = get_f64(data, "TR_q50");
    let tr_q95 = get_f64(data, "TR_q95");
    if let Some(tr50) = tr_q50 {
        let tr_regime = classify_tropical_night_regime(tr50);
        if tr50 < 1.0 {
            lines.push("**Warm nights**: Essentially none (cool nights year-round)".to_string());
        } else {
            lines.push(format!(
                "**Warm nights**: Typically {:.0} nights/year exceed 20°C (range {:.0}-{:.0})",
                tr50,
                tr_q05.unwrap_or(0.0),
                tr_q95.unwrap_or(0.0)
            ));
        }
        // Add pest note for moderate-high tropical nights
        if tr50 > 10.0 {
            lines.push(format!("*{} - Expect increased aphid/whitefly activity in warm summers*", tr_regime));
        } else {
            lines.push(format!("*{}*", tr_regime));
        }
    }

    // Diurnal Temperature Range (DTR) - day-night variation
    let dtr_q05 = get_f64(data, "DTR_q05");
    let dtr_q50 = get_f64(data, "DTR_q50");
    let dtr_q95 = get_f64(data, "DTR_q95");
    if let Some(dtr50) = dtr_q50 {
        let dtr_stability = classify_diurnal_range(dtr50);
        lines.push(format!(
            "**Climate type**: Populations found where day-night temperature varies by {:.0}-{:.0}°C (typically {:.0}°C)",
            dtr_q05.unwrap_or(0.0),
            dtr_q95.unwrap_or(0.0),
            dtr50
        ));
        lines.push(format!("*{} climate - {}", dtr_stability,
            if dtr50 < 8.0 { "Maritime/stable conditions" }
            else if dtr50 < 12.0 { "Typical temperate variation" }
            else { "Continental climate with large temperature swings" }));
    }

    // Growing Season Length (GSL) - number of days suitable for plant growth
    let gsl_q05 = get_f64(data, "GSL_q05");
    let gsl_q50 = get_f64(data, "GSL_q50");
    let gsl_q95 = get_f64(data, "GSL_q95");
    if let Some(gsl50) = gsl_q50 {
        let season_type = classify_growing_season(gsl50);
        let months = (gsl50 / 30.0).round() as i32;
        lines.push(format!(
            "**Growing season**: {:.0}-{:.0} days/year with temperatures suitable for growth (typically {:.0} - about {} months)",
            gsl_q05.unwrap_or(0.0),
            gsl_q95.unwrap_or(0.0),
            gsl50,
            months
        ));
        lines.push(format!("*{} - Period when temperatures allow active growth*", season_type));
    }

    // EIVE-T - Temperature Indicator
    lines.push(String::new());
    lines.push("**Ecological Indicator (EIVE-T)**:".to_string());
    let eive_t_val = get_eive(data, "T");
    if let Some(t) = eive_t_val {
        let climate_type = if t < 2.0 { "Arctic-alpine; needs cool summers" }
            else if t < 4.0 { "Boreal/mountain; cool temperate" }
            else if t < 6.0 { "Temperate; typical Northern Europe" }
            else if t < 8.0 { "Warm temperate; Mediterranean margin" }
            else { "Subtropical; needs warm conditions" };

        lines.push(format!("- Temperature indicator: {:.1}/10", t));
        lines.push(format!("- Climate type: {}", climate_type));
        lines.push("*Where species is most abundant in natural vegetation; from field surveys*".to_string());
    }

    // Moisture section
    lines.push(String::new());
    lines.push("**Moisture**:".to_string());
    lines.push(String::new());

    // Annual precipitation
    let bio12_q05_val = get_f64(data, "wc2.1_30s_bio_12_q05");
    let bio12_q50_val = get_f64(data, "wc2.1_30s_bio_12_q50");
    let bio12_q95_val = get_f64(data, "wc2.1_30s_bio_12_q95");
    if let Some(bio12_50) = bio12_q50_val {
        let rainfall_type = if bio12_50 < 250.0 { "Arid (desert)" }
            else if bio12_50 < 500.0 { "Semi-arid (steppe)" }
            else if bio12_50 < 1000.0 { "Temperate" }
            else if bio12_50 < 1500.0 { "Moist" }
            else { "Wet (tropical/oceanic)" };

        lines.push(format!(
            "- **Annual rainfall**: {}-{}mm (typically {}mm)",
            fmt_f64(bio12_q05_val, 0),
            fmt_f64(bio12_q95_val, 0),
            fmt_f64(Some(bio12_50), 0)
        ));
        lines.push(format!("  *{} climate*", rainfall_type));
    }

    // Drought tolerance
    let cdd_q50 = get_f64(data, "CDD_q50");
    let cdd_q95 = get_f64(data, "CDD_q95");
    if let Some(cdd_max) = cdd_q95 {
        let drought_label = classify_drought_tolerance(cdd_max);
        if let Some(cdd_typ) = cdd_q50 {
            lines.push(format!(
                "- **Dry spells**: Typically {:.0} consecutive dry days, up to {:.0} days maximum",
                cdd_typ, cdd_max
            ));
        } else {
            lines.push(format!(
                "- **Dry spells**: Populations experience dry periods up to {:.0} consecutive days",
                cdd_max
            ));
        }
        lines.push(format!("  *{} - {}*", drought_label,
            if cdd_max > 60.0 { "Can handle prolonged drought; deep watering occasionally" }
            else if cdd_max > 30.0 { "Tolerates dry spells; water during extended drought" }
            else if cdd_max > 14.0 { "Needs moisture during 2+ week dry spells" }
            else { "Requires regular moisture; don't let soil dry out" }));
    }

    // Warm-Wet Days (WW) - disease risk indicator
    let ww_q05 = get_f64(data, "WW_q05");
    let ww_q50 = get_f64(data, "WW_q50");
    let ww_q95 = get_f64(data, "WW_q95");
    if let Some(ww50) = ww_q50 {
        let ww_regime = classify_warm_wet_regime(ww50);
        lines.push(format!(
            "- Warm-wet conditions: Populations found where {:.0}-{:.0} days/year are warm & wet (typically {:.0})",
            ww_q05.unwrap_or(0.0),
            ww_q95.unwrap_or(0.0),
            ww50
        ));
        // Add disease monitoring note based on WW level
        if ww50 > 150.0 {
            lines.push("  *High disease pressure areas - Populations likely have resistance; ensure good air circulation and monitor for mildew/rust*".to_string());
        } else if ww50 > 80.0 {
            lines.push("  *Moderate disease pressure - Provide good air circulation; watch for fungal issues in humid periods*".to_string());
        } else {
            lines.push("  *Low disease pressure - Plant from drier climates; may be vulnerable in humid gardens*".to_string());
        }
    }

    // EIVE-M - Moisture Indicator
    lines.push(String::new());
    lines.push("**Ecological Indicator (EIVE-M)**:".to_string());
    let eive_m_val = get_eive(data, "M");
    if let Some(m) = eive_m_val {
        let moisture_level = if m < 2.0 { "Extreme drought tolerance" }
            else if m < 4.0 { "Dry conditions" }
            else if m < 6.0 { "Moderate moisture" }
            else if m < 8.0 { "Moist conditions" }
            else { "Wet/waterlogged" };

        let watering = if m < 2.0 { "Minimal; allow to dry completely" }
            else if m < 4.0 { "Sparse; weekly in drought" }
            else if m < 6.0 { "Regular; 1-2 times weekly" }
            else if m < 8.0 { "Frequent; keep moist" }
            else { "Constant moisture needed" };

        lines.push(format!("- Moisture indicator: {:.1}/10", m));
        lines.push(format!("- Typical position: {}", moisture_level));
        lines.push(format!("- Watering: {}", watering));
        lines.push("*Where species is most abundant in natural vegetation; from field surveys*".to_string());
    }

    // Add caveat about cultivation vs natural conditions
    lines.push(String::new());
    lines.push("**Note**: These indicators show where plants are most abundant in nature after competition. In cultivation, plants may tolerate or even prefer different conditions. Experiment to find what works best in your garden.".to_string());

    lines.join("\n")
}

/// Concise cold hardiness descriptor (inline format per doc spec)
fn cold_descriptor(tnn_q05: f64) -> &'static str {
    if tnn_q05 < -40.0 {
        "Extremely hardy"
    } else if tnn_q05 < -25.0 {
        "Very hardy"
    } else if tnn_q05 < -15.0 {
        "Cold-hardy"
    } else if tnn_q05 < -5.0 {
        "Moderately hardy"
    } else if tnn_q05 < 0.0 {
        "Half-hardy"
    } else {
        "Frost-tender"
    }
}

/// Concise heat tolerance category (doc spec lines 64-70)
fn classify_heat_category(txx_q95: f64) -> &'static str {
    if txx_q95 > 45.0 {
        "Extreme heat"
    } else if txx_q95 > 40.0 {
        "Very heat-tolerant"
    } else if txx_q95 > 35.0 {
        "Heat-tolerant"
    } else if txx_q95 > 30.0 {
        "Moderate"
    } else {
        "Cool-climate"
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

/// Classify frost day regime based on typical annual count
fn classify_frost_regime(fd_q50: f64) -> &'static str {
    if fd_q50 > 150.0 {
        "Extreme frost exposure"
    } else if fd_q50 > 100.0 {
        "Very long frost season"
    } else if fd_q50 > 60.0 {
        "Long frost season"
    } else if fd_q50 > 30.0 {
        "Moderate frost season"
    } else if fd_q50 > 10.0 {
        "Light frost season"
    } else {
        "Frost-free to occasional"
    }
}

/// Classify cold spell tolerance based on maximum consecutive frost days
fn classify_cold_spell(cfd_q95: f64) -> &'static str {
    if cfd_q95 > 60.0 {
        "Extreme prolonged cold"
    } else if cfd_q95 > 30.0 {
        "Long winter freeze"
    } else if cfd_q95 > 14.0 {
        "Extended freezing"
    } else if cfd_q95 > 7.0 {
        "1-2 week freezes"
    } else if cfd_q95 > 3.0 {
        "Short cold snaps"
    } else {
        "No prolonged frost"
    }
}

/// Classify tropical night regime based on typical annual count
fn classify_tropical_night_regime(tr_q50: f64) -> &'static str {
    if tr_q50 > 100.0 {
        "Year-round warmth"
    } else if tr_q50 > 60.0 {
        "Hot summer nights"
    } else if tr_q50 > 30.0 {
        "Frequent warm nights"
    } else if tr_q50 > 10.0 {
        "Regular warm nights"
    } else if tr_q50 > 1.0 {
        "Occasional warm nights"
    } else {
        "Cool nights year-round"
    }
}

/// Classify diurnal temperature range (climate stability)
fn classify_diurnal_range(dtr_q50: f64) -> &'static str {
    if dtr_q50 > 15.0 {
        "Extreme variation"
    } else if dtr_q50 > 12.0 {
        "Large variation"
    } else if dtr_q50 > 8.0 {
        "Moderate variation"
    } else if dtr_q50 > 5.0 {
        "Stable"
    } else {
        "Very stable"
    }
}

/// Classify growing season length
fn classify_growing_season(gsl_q50: f64) -> &'static str {
    if gsl_q50 > 330.0 {
        "Year-round"
    } else if gsl_q50 > 270.0 {
        "Very long"
    } else if gsl_q50 > 210.0 {
        "Long"
    } else if gsl_q50 > 150.0 {
        "Moderate"
    } else if gsl_q50 > 90.0 {
        "Short"
    } else {
        "Very short"
    }
}

/// Classify warm-wet days (disease pressure indicator)
fn classify_warm_wet_regime(ww_q50: f64) -> &'static str {
    if ww_q50 > 250.0 {
        "Extreme"
    } else if ww_q50 > 200.0 {
        "Very high disease pressure"
    } else if ww_q50 > 150.0 {
        "High disease pressure"
    } else if ww_q50 > 100.0 {
        "Moderate"
    } else if ww_q50 > 50.0 {
        "Low"
    } else {
        "Very low"
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
    lines.push(String::new());

    // Extract values for range summary
    let ph_q05 = get_f64(data, "phh2o_0_5cm_q05");
    let ph_q95 = get_f64(data, "phh2o_0_5cm_q95");
    let (ph_q05_adj, _, ph_q95_adj) = adjust_ph_values(ph_q05, None, ph_q95);

    // Soil range summary
    if let (Some(acidic), Some(alkaline)) = (ph_q05_adj, ph_q95_adj) {
        lines.push(format!("**pH tolerance**: {:.1}-{:.1} (from most acidic to most alkaline population locations)", acidic, alkaline));
        let range = alkaline - acidic;
        let flexibility = if range > 2.0 { "Wide tolerance; adaptable" }
            else if range > 1.0 { "Moderate flexibility" }
            else { "Narrow preference" };
        lines.push(format!("*{}*", flexibility));
        lines.push(String::new());
    }

    lines.push("---".to_string());
    lines.push(String::new());

    // pH details
    let ph_q05_val = get_f64(data, "phh2o_0_5cm_q05");
    let ph_q50_val = get_f64(data, "phh2o_0_5cm_q50");
    let ph_q95_val = get_f64(data, "phh2o_0_5cm_q95");

    // Note: pH values may be stored as ×10 in raw data
    let (ph_q05_adj, ph_q50_adj, ph_q95_adj) = adjust_ph_values(ph_q05_val, ph_q50_val, ph_q95_val);

    if let Some(ph50) = ph_q50_adj {
        let ph_type = if ph50 < 5.0 { "Strongly acidic" }
            else if ph50 < 5.5 { "Moderately acidic" }
            else if ph50 < 6.5 { "Slightly acidic" }
            else if ph50 < 7.5 { "Neutral" }
            else if ph50 < 8.0 { "Slightly alkaline" }
            else { "Alkaline/chalky" };

        lines.push(format!(
            "**pH**: {}-{} (typically {})",
            fmt_f64(ph_q05_adj, 1),
            fmt_f64(ph_q95_adj, 1),
            fmt_f64(Some(ph50), 1)
        ));
        lines.push(format!("*{}*", ph_type));
    }

    // EIVE-R - pH Indicator
    lines.push(String::new());
    lines.push("**Ecological Indicator (EIVE-R)**:".to_string());
    let eive_r_val = get_eive(data, "R");
    if let Some(r) = eive_r_val {
        let ph_preference = if r < 2.0 { "Strongly acidic (calcifuge)" }
            else if r < 4.0 { "Moderately acidic" }
            else if r < 6.0 { "Slightly acidic to neutral" }
            else if r < 7.0 { "Neutral" }
            else { "Alkaline (calcicole)" };

        let compost = if r < 2.0 { "Ericaceous compost required; avoid lime" }
            else if r < 4.0 { "Acidic to neutral compost" }
            else if r < 6.0 { "Standard multipurpose compost" }
            else if r < 8.0 { "Tolerates some lime" }
            else { "Lime-loving; add chalk if needed" };

        lines.push(format!("- pH indicator: {:.1}/10", r));
        lines.push(format!("- Typical position: {}", ph_preference));
        lines.push(format!("- Compost: {}", compost));
        lines.push("*Where species is most abundant in natural vegetation; from field surveys*".to_string());
    }

    // Fertility (CEC, Nitrogen)
    let cec_q50 = get_f64(data, "cec_0_5cm_q50");
    if let Some(cec) = cec_q50 {
        let fertility_label = classify_fertility(cec);
        lines.push(String::new());
        lines.push(format!("**Fertility**: Populations found in {} soils (CEC {} cmol/kg)",
            fertility_label.to_lowercase(), fmt_f64(Some(cec), 0)));
        lines.push(format!("*{}*",
            if cec < 10.0 { "Sandy/low nutrient retention - Needs frequent feeding" }
            else if cec < 20.0 { "Moderate nutrient retention - Standard feeding" }
            else if cec < 30.0 { "Good nutrient retention (clay loam) - Benefits from annual feeding" }
            else { "Excellent nutrient retention (clay/peat) - Naturally fertile" }));
    }

    // EIVE-N - Nutrient Indicator
    lines.push(String::new());
    lines.push("**Ecological Indicator (EIVE-N)**:".to_string());
    let eive_n_val = get_eive(data, "N");
    if let Some(n) = eive_n_val {
        let nutrient_level = if n < 2.0 { "Very low nutrient" }
            else if n < 4.0 { "Low nutrient" }
            else if n < 6.0 { "Moderate nutrient" }
            else if n < 8.0 { "High nutrient" }
            else { "Very high nutrient" };

        let feeding = if n < 2.0 { "Light feeding only; excess N harmful" }
            else if n < 4.0 { "Minimal feeding; balanced NPK" }
            else if n < 6.0 { "Standard annual feeding" }
            else if n < 8.0 { "Benefits from generous feeding" }
            else { "Heavy feeder; responds well to manure" };

        lines.push(format!("- Nutrient indicator: {:.1}/10", n));
        lines.push(format!("- Typical position: {}", nutrient_level));
        lines.push(format!("- Feeding: {}", feeding));
        lines.push("*Where species is most abundant in natural vegetation; indicates fertility level, not preference*".to_string());
    }

    // Add caveat about cultivation vs natural conditions (especially for nutrients)
    lines.push(String::new());
    lines.push("**Note**: These indicators show where plants are most abundant in nature after competition. Many plants found in low-fertility areas are competitively excluded from richer soils by faster-growing species - they may actually thrive with MORE fertilization than their natural habitat suggests. pH tolerance is more physiological, but nutrient response is worth experimenting with.".to_string());

    // Texture
    let clay_q50 = get_f64(data, "clay_0_5cm_q50");
    let sand_q95 = get_f64(data, "sand_0_5cm_q95");
    if let Some(clay) = clay_q50 {
        lines.push(String::new());
        let texture_label = if clay > 35.0 { "Heavy clay" }
            else if clay > 25.0 { "Clay loam" }
            else if clay > 15.0 { "Loam" }
            else { "Sandy loam" };

        lines.push(format!("**Texture**: Populations found primarily in {} (clay ~{:.0}%)",
            texture_label.to_lowercase(), clay));

        if let Some(sand) = sand_q95 {
            if sand > 65.0 {
                lines.push("*Some populations tolerate sandy soils - Adaptable to lighter textures*".to_string());
            } else if sand > 50.0 {
                lines.push("*Moderate sand tolerance - Standard garden soil works*".to_string());
            } else {
                lines.push("*Prefers heavier soils - May struggle in very sandy conditions*".to_string());
            }
        }
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

/// Interpret Köppen-Geiger climate code with human-readable label
fn interpret_koppen_zone(code: &str) -> &'static str {
    match code {
        // Tropical (A) - warm all year (>18°C every month)
        "Af" => "Tropical rainforest - warm & wet year-round",
        "Am" => "Tropical monsoon - warm year-round with seasonal heavy rains",
        "Aw" | "As" => "Tropical savanna - warm year-round with distinct wet/dry seasons",

        // Arid (B) - very dry
        "BWh" => "Hot desert - very hot & dry year-round",
        "BWk" => "Cold desert - dry with cold winters",
        "BWn" => "Mild desert - dry with mild temperatures",
        "BSh" => "Hot semi-arid - hot with limited rainfall",
        "BSk" => "Cold semi-arid - cool to cold with limited rainfall",
        "BSn" => "Mild semi-arid - mild with limited rainfall",

        // Temperate (C) - mild winters (0-18°C coldest month)
        "Cfa" => "Humid subtropical - hot humid summers, mild winters, rain year-round",
        "Cfb" => "Temperate oceanic - mild year-round, no dry season (typical Western Europe)",
        "Cfc" => "Subpolar oceanic - cool summers, mild winters, wet year-round",
        "Csa" => "Hot-summer Mediterranean - hot dry summers, mild wet winters",
        "Csb" => "Warm-summer Mediterranean - warm dry summers, mild wet winters",
        "Csc" => "Cool-summer Mediterranean - cool summers, mild wet winters",
        "Cwa" => "Humid subtropical - hot summers, dry winters",
        "Cwb" | "Cwc" => "Subtropical highland - mild with dry winters",

        // Continental (D) - cold winters (below 0°C at least one month)
        "Dfa" | "Dfb" => "Humid continental - warm summers, cold snowy winters",
        "Dfc" | "Dfd" => "Subarctic - short cool summers, very cold winters",
        "Dwa" | "Dwb" | "Dwc" | "Dwd" => "Monsoon continental - dry cold winters, wet summers",
        "Dsa" | "Dsb" | "Dsc" | "Dsd" => "Continental Mediterranean - dry summers, cold winters",

        // Polar (E) - cold all year (every month <10°C)
        "ET" => "Tundra - very cold, short growing season",
        "ETf" => "Cold tundra - very cold with at least one month below 0°C",
        "EF" => "Ice cap - frozen year-round",

        _ => "Climate type not classified",
    }
}
