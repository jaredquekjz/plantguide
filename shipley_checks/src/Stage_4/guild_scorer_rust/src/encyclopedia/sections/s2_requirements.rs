//! S2: Growing Requirements
//!
//! Integrates climate envelope, soil envelope, and EIVE indicators using
//! the triangulation principle: present both occurrence-based perspectives.
//!
//! Data Sources:
//! - EIVE indicators: `EIVEres-L`, `EIVEres-M`, `EIVEres-T`, `EIVEres-R`, `EIVEres-N`
//! - Climate envelope (BioClim): `wc2.1_30s_bio_5_*` (warmest month), `wc2.1_30s_bio_6_*` (coldest month), `wc2.1_30s_bio_12_*` (annual precip)
//! - Agroclimate indicators: `FD_*`, `CFD_*`, `TR_*`, `DTR_*`, `GSL_*`, `WW_*`, `CDD_*`
//! - Soil envelope: `phh2o_0_5cm_*`, `clay_0_5cm_*`, `sand_0_5cm_*`, `soc_0_5cm_*`
//!
//! NOTE: TNn_*/TXx_* (AgroClim) removed from temperature display - they are temporal
//! means of dekadal extremes, not actual single-day extremes, making them incomparable
//! with BioClim monthly aggregates. See Stage_0 documentation for details.

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::*;
use crate::encyclopedia::utils::classify::*;
use crate::encyclopedia::utils::texture as usda_texture;

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

    // Check if value is from expert observation or imputed
    let source = get_str(data, "EIVEres-L_source");
    let is_imputed = source.map(|s| s == "imputed").unwrap_or(false);

    match eive_l {
        Some(l) => {
            lines.push(format!("**Light Needs**: {:.1}/10 - {}", l, label));
            lines.push(light_advice(l));
            lines.push(String::new());

            if is_imputed {
                lines.push("*Estimated from plant traits and habitat data using machine learning, calibrated against species with known Ecological Indicator Values for Europe (EIVE), derived from expert botanist field surveys.*".to_string());
            } else {
                lines.push("*Ecological Indicator Value for Europe (EIVE-L) from expert botanist field surveys — shows typical light conditions where this species is found in natural habitats under competition.*".to_string());
            }
        }
        None => {
            lines.push("**Light Needs**: Not available".to_string());
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

    // ==================== TEMPERATURE SECTION ====================
    lines.push("### Temperature".to_string());
    lines.push(String::new());

    lines.push("*Values show typical conditions where populations of the plant occur (median across populations), with range showing variation from mildest to most extreme locations.*".to_string());
    lines.push(String::new());

    // Get BioClim temperature variables (WorldClim 2.x stores directly in °C)
    let bio5_q50 = get_f64(data, "wc2.1_30s_bio_5_q50");
    let bio5_q95 = get_f64(data, "wc2.1_30s_bio_5_q95");
    let bio6_q05 = get_f64(data, "wc2.1_30s_bio_6_q05");
    let bio6_q50 = get_f64(data, "wc2.1_30s_bio_6_q50");

    // Climate range summary - using BioClim only (BIO5/BIO6)
    if let (Some(warm_typ), Some(cold_typ)) = (bio5_q50, bio6_q50) {
        // Avoid "-0" display issue
        let cold_display = if cold_typ > -0.5 && cold_typ < 0.5 { 0.0 } else { cold_typ };
        lines.push(format!(
            "**Range**: {:.0}°C warmest month, {:.0}°C coldest month",
            warm_typ, cold_display
        ));
        // Show range if available
        if let (Some(cold_min), Some(warm_max)) = (bio6_q05, bio5_q95) {
            lines.push(format!(
                "*Range: {:.0}°C to {:.0}°C across all population locations*",
                cold_min, warm_max
            ));
        }
    }

    // NOTE: Native climate (Köppen) moved to S1 Identity section

    // ========== COLD STRESS ==========

    // Frost Days (FD) - days with minimum temp below 0°C
    let fd_q05 = get_f64(data, "FD_q05");
    let fd_q50 = get_f64(data, "FD_q50");
    let fd_q95 = get_f64(data, "FD_q95");
    let cfd_q50 = get_f64(data, "CFD_q50");
    let cfd_q95 = get_f64(data, "CFD_q95");

    if let Some(fd50) = fd_q50 {
        let frost_regime = classify_frost_regime(fd50);

        if fd50 < 5.0 {
            lines.push(format!(
                "**Frost**: {:.0} days/year below 0°C (up to {} in coldest locations)",
                fd50,
                fmt_f64(fd_q95, 0)
            ));
            lines.push(format!("*{}*", frost_regime));
        } else {
            lines.push(format!(
                "**Frost days**: {:.0} days/year below 0°C ({}-{} across locations)",
                fd50,
                fmt_f64(fd_q05, 0),
                fmt_f64(fd_q95, 0)
            ));
            lines.push(format!("*{}*", frost_regime));

            if let Some(cfd50) = cfd_q50 {
                let cold_spell = classify_cold_spell(cfd50);
                if let Some(cfd95) = cfd_q95 {
                    lines.push(format!(
                        "**Cold spells**: {:.0} consecutive frost days typical, up to {:.0}",
                        cfd50, cfd95
                    ));
                } else {
                    lines.push(format!(
                        "**Cold spells**: {:.0} consecutive frost days typical",
                        cfd50
                    ));
                }
                lines.push(format!("*{}*", cold_spell));
            }
        }
    }

    // ========== HEAT STRESS ==========

    // Summer Days (SU) - days with maximum temp above 25°C
    let su_q50 = get_f64(data, "SU_q50");
    let su_q95 = get_f64(data, "SU_q95");
    if let Some(su50) = su_q50 {
        if su50 >= 5.0 {
            lines.push(format!(
                "**Hot days**: {:.0} days/year with max >25°C (up to {:.0} in warmest locations)",
                su50,
                su_q95.unwrap_or(su50)
            ));
            let heat_regime = if su50 > 120.0 { "Very hot summers" }
                else if su50 > 90.0 { "Hot summers" }
                else if su50 > 60.0 { "Warm summers" }
                else if su50 > 30.0 { "Mild summers" }
                else { "Cool summers" };
            lines.push(format!("*{}*", heat_regime));
        }
    }

    // Tropical Nights (TR) - nights with minimum temp above 20°C
    let tr_q05 = get_f64(data, "TR_q05");
    let tr_q50 = get_f64(data, "TR_q50");
    let tr_q95 = get_f64(data, "TR_q95");
    if let Some(tr50) = tr_q50 {
        if tr50 < 1.0 {
            // Show range even when rare
            let range_str = match (tr_q05, tr_q95) {
                (Some(_lo), Some(hi)) if hi >= 1.0 => format!(" (up to {:.0} in warmest locations)", hi),
                _ => String::new(),
            };
            lines.push(format!("**Warm nights**: Rare{} (nights with min >20°C)", range_str));
            lines.push("*Cool nights year-round*".to_string());
        } else {
            let range_str = match (tr_q05, tr_q95) {
                (Some(lo), Some(hi)) => format!(" ({:.0}-{:.0} across locations)", lo, hi),
                (None, Some(hi)) => format!(" (up to {:.0} in warmest locations)", hi),
                _ => String::new(),
            };
            lines.push(format!(
                "**Warm nights**: {:.0} nights/year with min >20°C{}",
                tr50, range_str
            ));
            if tr50 > 30.0 {
                lines.push("*Warm nights common - may need heat-tolerant varieties*".to_string());
            } else if tr50 > 10.0 {
                lines.push("*Occasional warm nights in summer*".to_string());
            } else {
                lines.push("*Few warm nights*".to_string());
            }
        }
    }

    // ========== CLIMATE STABILITY ==========

    // Diurnal Temperature Range (DTR) - day-night variation
    let dtr_q05 = get_f64(data, "DTR_q05");
    let dtr_q50 = get_f64(data, "DTR_q50");
    let dtr_q95 = get_f64(data, "DTR_q95");
    if let Some(dtr50) = dtr_q50 {
        let range_str = match (dtr_q05, dtr_q95) {
            (Some(lo), Some(hi)) => format!(" ({:.0}-{:.0}°C across locations)", lo, hi),
            _ => String::new(),
        };
        lines.push(format!(
            "**Day-night swing**: {:.0}°C typical daily range{}",
            dtr50, range_str
        ));
        lines.push(format!("*{}*",
            if dtr50 < 8.0 { "Maritime/oceanic - stable temperatures" }
            else if dtr50 < 12.0 { "Temperate - moderate variation" }
            else { "Continental - large temperature swings" }));
    }

    // Growing Season Length (GSL) - days with daily mean temp above 5°C
    let gsl_q05 = get_f64(data, "GSL_q05");
    let gsl_q50 = get_f64(data, "GSL_q50");
    let gsl_q95 = get_f64(data, "GSL_q95");
    if let Some(gsl50) = gsl_q50 {
        let season_type = classify_growing_season(gsl50);
        let months = (gsl50 / 30.0).round() as i32;
        lines.push(format!(
            "**Growing season**: {:.0} days with mean >5°C (~{} months)",
            gsl50,
            months
        ));
        if let (Some(short), Some(long)) = (gsl_q05, gsl_q95) {
            lines.push(format!("*{} - ranges from {:.0} to {:.0} days across locations*", season_type, short, long));
        } else {
            lines.push(format!("*{}*", season_type));
        }
    }

    // ==================== MOISTURE SECTION ====================
    lines.push(String::new());
    lines.push("### Moisture".to_string());
    lines.push(String::new());

    // Annual Rainfall
    let bio12_q05 = get_f64(data, "wc2.1_30s_bio_12_q05");
    let bio12_q50 = get_f64(data, "wc2.1_30s_bio_12_q50");
    let bio12_q95 = get_f64(data, "wc2.1_30s_bio_12_q95");
    if let Some(precip) = bio12_q50 {
        let range_str = match (bio12_q05, bio12_q95) {
            (Some(lo), Some(hi)) => format!(" ({:.0}-{:.0}mm across locations)", lo, hi),
            _ => String::new(),
        };
        lines.push(format!("**Rainfall**: {:.0}mm/year{}", precip, range_str));
    }

    // Drought tolerance - CDD (consecutive dry days with precip <1mm)
    let cdd_q50 = get_f64(data, "CDD_q50");
    let cdd_q95 = get_f64(data, "CDD_q95");
    if let Some(cdd_typ) = cdd_q50 {
        let drought_label = classify_drought_tolerance(cdd_q95.unwrap_or(cdd_typ));
        if let Some(cdd95) = cdd_q95 {
            lines.push(format!(
                "**Dry spells**: {:.0} consecutive dry days typical, {:.0} in driest locations",
                cdd_typ, cdd95
            ));
        } else {
            lines.push(format!(
                "**Dry spells**: {:.0} consecutive dry days typical",
                cdd_typ
            ));
        }
        let advice = if cdd_typ > 60.0 { "Deep watering occasionally once established" }
            else if cdd_typ > 30.0 { "Water during extended dry spells" }
            else if cdd_typ > 14.0 { "Water during 2+ week dry periods" }
            else { "Keep soil moist; don't let dry out" };
        lines.push(format!("*{} - {}*", drought_label, advice));
    }

    // Warm-Wet Days (WW) - days with Tmax >25°C AND precip >1mm (disease risk indicator)
    let ww_q50 = get_f64(data, "WW_q50");
    if let Some(ww50) = ww_q50 {
        lines.push(format!(
            "**Disease pressure**: {:.0} warm-wet days/year (days >25°C with rain)",
            ww50
        ));
        if ww50 > 150.0 {
            lines.push("*High (humid climate) - likely disease-resistant; still provide good airflow*".to_string());
        } else if ww50 > 80.0 {
            lines.push("*Moderate - monitor for mildew/rust in humid periods*".to_string());
        } else {
            lines.push("*Low (dry climate origin) - may be vulnerable to fungal diseases in humid gardens*".to_string());
        }
    }

    // Consecutive Wet Days (CWD) - consecutive days with precip >1mm (waterlogging risk)
    let cwd_q50 = get_f64(data, "CWD_q50");
    let cwd_q95 = get_f64(data, "CWD_q95");
    if let Some(cwd50) = cwd_q50 {
        if cwd50 >= 5.0 {
            lines.push(format!(
                "**Wet spells**: {:.0} consecutive rainy days typical (up to {:.0} in wettest locations)",
                cwd50,
                cwd_q95.unwrap_or(cwd50)
            ));
            let waterlog_advice = if cwd50 > 14.0 {
                "High waterlogging tolerance - can handle boggy conditions"
            } else if cwd50 > 7.0 {
                "Moderate waterlogging tolerance - ensure drainage in heavy soils"
            } else {
                "Good drainage needed - avoid waterlogged soils"
            };
            lines.push(format!("*{}*", waterlog_advice));
        }
    }

    // NOTE: EIVE-M commented out - occurrence data (rainfall, CDD dry spells, WW disease pressure)
    // provides more actionable information. EIVE-M retained in parquet for SQL filtering.
    //
    // // EIVE-M - Moisture Indicator
    // lines.push(String::new());
    // lines.push("**Ecological Indicator (EIVE-M)**:".to_string());
    // let eive_m_val = get_eive(data, "M");
    // if let Some(m) = eive_m_val {
    //     let moisture_level = if m < 2.0 { "Extreme drought tolerance" }
    //         else if m < 4.0 { "Dry conditions" }
    //         else if m < 6.0 { "Moderate moisture" }
    //         else if m < 8.0 { "Moist conditions" }
    //         else { "Wet/waterlogged" };
    //
    //     let watering = if m < 2.0 { "Minimal; allow to dry completely" }
    //         else if m < 4.0 { "Sparse; weekly in drought" }
    //         else if m < 6.0 { "Regular; 1-2 times weekly" }
    //         else if m < 8.0 { "Frequent; keep moist" }
    //         else { "Constant moisture needed" };
    //
    //     lines.push(format!("- Moisture indicator: {:.1}/10", m));
    //     lines.push(format!("- Typical position: {}", moisture_level));
    //     lines.push(format!("- Watering: {}", watering));
    //     lines.push("*Where species is most abundant in natural vegetation; from field surveys*".to_string());
    // }

    lines.join("\n")
}

// NOTE: cold_descriptor and classify_heat_category removed - TNn/TXx no longer used
// (AgroClim temporal means are incomparable with BioClim; see Stage 0 documentation)

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

fn generate_soil_section(data: &HashMap<String, Value>) -> String {
    let mut lines = Vec::new();
    lines.push("### Soil".to_string());
    lines.push(String::new());
    lines.push("*Soil conditions where populations of the plant occur (median across populations), with range showing variation across locations. These show where plants are found after competition - many species on poor soils are competitively excluded from richer soils, not physiologically limited. Experiment with fertility. Data from SoilGrids 2.0.*".to_string());
    lines.push(String::new());

    // ========== TOPSOIL (0-15cm) - THE AMENDABLE LAYER ==========
    // Weighted average: 0-5cm (5cm thick) + 5-15cm (10cm thick) = 15cm total

    lines.push("**Topsoil (0-15cm)** - *the layer you can amend*".to_string());
    lines.push(String::new());

    // Helper to calculate 0-15cm weighted average
    let calc_topsoil_avg = |prefix: &str, suffix: &str| -> Option<f64> {
        let v1 = get_f64(data, &format!("{}_0_5cm_{}", prefix, suffix));
        let v2 = get_f64(data, &format!("{}_5_15cm_{}", prefix, suffix));
        match (v1, v2) {
            (Some(a), Some(b)) => Some((a * 5.0 + b * 10.0) / 15.0),
            (Some(a), None) => Some(a),
            (None, Some(b)) => Some(b),
            _ => None,
        }
    };

    // pH (0-15cm average)
    let ph_q05_raw = calc_topsoil_avg("phh2o", "q05");
    let ph_q50_raw = calc_topsoil_avg("phh2o", "q50");
    let ph_q95_raw = calc_topsoil_avg("phh2o", "q95");
    let (ph_q05, ph_q50, ph_q95) = adjust_ph_values(ph_q05_raw, ph_q50_raw, ph_q95_raw);

    if let Some(ph) = ph_q50 {
        let ph_type = if ph < 5.0 { "Strongly acidic" }
            else if ph < 5.5 { "Moderately acidic" }
            else if ph < 6.5 { "Slightly acidic" }
            else if ph < 7.5 { "Neutral" }
            else if ph < 8.0 { "Slightly alkaline" }
            else { "Alkaline/chalky" };

        let range_width = match (ph_q05, ph_q95) {
            (Some(lo), Some(hi)) => hi - lo,
            _ => 0.0,
        };
        let ph_advice = if range_width > 2.0 {
            "wide tolerance - adaptable to most garden soils"
        } else if range_width > 1.0 {
            "moderate tolerance"
        } else if ph < 5.5 {
            "narrow preference - needs acidic soil; use ericaceous compost"
        } else if ph > 7.5 {
            "narrow preference - tolerates chalky/alkaline soil"
        } else {
            "narrow preference - match soil pH carefully"
        };

        lines.push(format!(
            "**pH**: {:.1} typical (range {}-{})",
            ph, fmt_f64(ph_q05, 1), fmt_f64(ph_q95, 1)
        ));
        lines.push(format!("*{}; {}*", ph_type, ph_advice));
    }

    // CEC (0-15cm average)
    let cec_q05 = calc_topsoil_avg("cec", "q05");
    let cec_q50 = calc_topsoil_avg("cec", "q50");
    let cec_q95 = calc_topsoil_avg("cec", "q95");

    if let Some(cec) = cec_q50 {
        let cec_advice = if cec < 10.0 {
            "Low retention (sandy) - nutrients wash out quickly; needs frequent light feeding"
        } else if cec < 20.0 {
            "Moderate retention - standard feeding schedule works well"
        } else if cec < 30.0 {
            "Good retention - soil holds fertilizer well; benefits from annual feeding"
        } else {
            "Excellent retention (clay/peat) - naturally fertile soil"
        };

        let range_str = match (cec_q05, cec_q95) {
            (Some(lo), Some(hi)) => format!(" ({:.0}-{:.0} across locations)", lo, hi),
            _ => String::new(),
        };

        lines.push(format!("**Fertility (CEC)**: {:.0} cmol/kg{}", cec, range_str));
        lines.push(format!("*{}*", cec_advice));
    }

    // SOC (0-15cm average)
    let soc_q05 = calc_topsoil_avg("soc", "q05");
    let soc_q50 = calc_topsoil_avg("soc", "q50");
    let soc_q95 = calc_topsoil_avg("soc", "q95");

    if let Some(soc) = soc_q50 {
        let range_str = match (soc_q05, soc_q95) {
            (Some(lo), Some(hi)) => format!(" ({:.0}-{:.0} across locations)", lo, hi),
            _ => String::new(),
        };
        lines.push(format!("**Organic Carbon**: {:.0} g/kg{}", soc, range_str));
    }

    // ========== TEXTURE (0-15cm) ==========
    lines.push(String::new());

    let clay_q05 = calc_topsoil_avg("clay", "q05");
    let clay_q50 = calc_topsoil_avg("clay", "q50");
    let clay_q95 = calc_topsoil_avg("clay", "q95");

    let sand_q05 = calc_topsoil_avg("sand", "q05");
    let sand_q50 = calc_topsoil_avg("sand", "q50");
    let sand_q95 = calc_topsoil_avg("sand", "q95");

    let silt_q50 = match (clay_q50, sand_q50) {
        (Some(c), Some(s)) => Some(100.0 - c - s),
        _ => None,
    };
    let silt_q05 = match (clay_q95, sand_q95) {
        (Some(c), Some(s)) => Some((100.0 - c - s).max(0.0)),
        _ => None,
    };
    let silt_q95 = match (clay_q05, sand_q05) {
        (Some(c), Some(s)) => Some((100.0 - c - s).min(100.0)),
        _ => None,
    };

    if let (Some(clay), Some(sand), Some(silt)) = (clay_q50, sand_q50, silt_q50) {
        lines.push("**Texture**".to_string());
        lines.push(String::new());
        lines.push("| Component | Typical | Range |".to_string());
        lines.push("|-----------|---------|-------|".to_string());

        let sand_range = match (sand_q05, sand_q95) {
            (Some(lo), Some(hi)) => format!("{:.0}-{:.0}%", lo, hi),
            _ => "-".to_string(),
        };
        lines.push(format!("| Sand | {:.0}% | {} |", sand, sand_range));

        let silt_range = match (silt_q05, silt_q95) {
            (Some(lo), Some(hi)) if lo >= 0.0 && hi <= 100.0 => format!("{:.0}-{:.0}%", lo, hi),
            _ => "-".to_string(),
        };
        lines.push(format!("| Silt | {:.0}% | {} |", silt, silt_range));

        let clay_range = match (clay_q05, clay_q95) {
            (Some(lo), Some(hi)) => format!("{:.0}-{:.0}%", lo, hi),
            _ => "-".to_string(),
        };
        lines.push(format!("| Clay | {:.0}% | {} |", clay, clay_range));

        lines.push(String::new());

        if let Some(classification) = usda_texture::classify_texture(clay, sand, silt) {
            lines.push(format!("**USDA Class**: {}", classification.class_name));
            lines.push(format!(
                "*Drainage: {} | Water retention: {} - {}*",
                classification.drainage,
                classification.water_retention,
                classification.advice
            ));
            lines.push(String::new());
            lines.push(format!(
                "**Triangle Coordinates**: x={:.1}, y={:.1}",
                classification.x, classification.y
            ));
            lines.push("*For plotting on USDA texture triangle; x = 0.5×clay + silt, y = clay*".to_string());
        }
    }

    // ========== PROFILE AVERAGE (0-200cm) ==========
    lines.push(String::new());
    lines.push("---".to_string());
    lines.push(String::new());
    lines.push("**Profile Average (0-200cm)** - *underlying conditions*".to_string());
    lines.push(String::new());

    // Depth-weighted average across all 6 SoilGrids layers
    let depth_weights: [(f64, &str); 6] = [
        (5.0, "0_5cm"),
        (10.0, "5_15cm"),
        (15.0, "15_30cm"),
        (30.0, "30_60cm"),
        (40.0, "60_100cm"),
        (100.0, "100_200cm"),
    ];

    // Helper to calculate profile average for any variable
    let calc_profile_avg = |prefix: &str, suffix: &str| -> Option<f64> {
        let mut weighted_sum = 0.0;
        let mut total_weight = 0.0;
        for (weight, depth) in depth_weights.iter() {
            if let Some(v) = get_f64(data, &format!("{}_{}{}", prefix, depth, suffix)) {
                weighted_sum += v * weight;
                total_weight += weight;
            }
        }
        if total_weight > 0.0 { Some(weighted_sum / total_weight) } else { None }
    };

    // Profile pH (with range)
    let profile_ph_q05_raw = calc_profile_avg("phh2o", "_q05");
    let profile_ph_q50_raw = calc_profile_avg("phh2o", "_q50");
    let profile_ph_q95_raw = calc_profile_avg("phh2o", "_q95");
    let (profile_ph_q05, profile_ph_q50, profile_ph_q95) = adjust_ph_values(
        profile_ph_q05_raw, profile_ph_q50_raw, profile_ph_q95_raw
    );

    // Profile CEC (with range)
    let profile_cec_q05 = calc_profile_avg("cec", "_q05");
    let profile_cec_q50 = calc_profile_avg("cec", "_q50");
    let profile_cec_q95 = calc_profile_avg("cec", "_q95");

    // Profile SOC (with range)
    let profile_soc_q05 = calc_profile_avg("soc", "_q05");
    let profile_soc_q50 = calc_profile_avg("soc", "_q50");
    let profile_soc_q95 = calc_profile_avg("soc", "_q95");

    // Display as compact table with ranges
    lines.push("| Indicator | Typical | Range |".to_string());
    lines.push("|-----------|---------|-------|".to_string());

    if let Some(ph) = profile_ph_q50 {
        let range_str = match (profile_ph_q05, profile_ph_q95) {
            (Some(lo), Some(hi)) => format!("{:.1}-{:.1}", lo, hi),
            _ => "-".to_string(),
        };
        lines.push(format!("| pH | {:.1} | {} |", ph, range_str));
    }
    if let Some(cec) = profile_cec_q50 {
        let range_str = match (profile_cec_q05, profile_cec_q95) {
            (Some(lo), Some(hi)) => format!("{:.0}-{:.0}", lo, hi),
            _ => "-".to_string(),
        };
        lines.push(format!("| CEC (cmol/kg) | {:.0} | {} |", cec, range_str));
    }
    if let Some(soc) = profile_soc_q50 {
        let range_str = match (profile_soc_q05, profile_soc_q95) {
            (Some(lo), Some(hi)) => format!("{:.0}-{:.0}", lo, hi),
            _ => "-".to_string(),
        };
        lines.push(format!("| SOC (g/kg) | {:.0} | {} |", soc, range_str));
    }

    // NOTE: EIVE-R and EIVE-N commented out - occurrence data (pH ranges, CEC fertility)
    // provides more actionable information with actual ranges. EIVE values retained in
    // parquet for SQL filtering. Only EIVE-L is displayed (no occurrence alternative for light).
    //
    // // ========== EIVE INDICATORS (after all occurrence data) ==========
    //
    // lines.push(String::new());
    //
    // // EIVE-R - pH Indicator
    // let eive_r_val = get_eive(data, "R");
    // if let Some(r) = eive_r_val {
    //     let ph_preference = if r < 2.0 { "Strongly acidic (calcifuge)" }
    //         else if r < 4.0 { "Moderately acidic" }
    //         else if r < 6.0 { "Slightly acidic to neutral" }
    //         else if r < 7.0 { "Neutral" }
    //         else { "Alkaline (calcicole)" };
    //
    //     let compost = if r < 2.0 { "Ericaceous compost required; avoid lime" }
    //         else if r < 4.0 { "Acidic to neutral compost" }
    //         else if r < 6.0 { "Standard multipurpose compost" }
    //         else if r < 8.0 { "Tolerates some lime" }
    //         else { "Lime-loving; add chalk if needed" };
    //
    //     lines.push("**Ecological Indicator (EIVE-R)**:".to_string());
    //     lines.push(format!("- pH indicator: {:.1}/10", r));
    //     lines.push(format!("- Typical position: {}", ph_preference));
    //     lines.push(format!("- Compost: {}", compost));
    //     lines.push("*Where species is most abundant in natural vegetation; from field surveys*".to_string());
    // }
    //
    // // EIVE-N - Nutrient Indicator
    // lines.push(String::new());
    // let eive_n_val = get_eive(data, "N");
    // if let Some(n) = eive_n_val {
    //     let nutrient_level = if n < 2.0 { "Very low nutrient" }
    //         else if n < 4.0 { "Low nutrient" }
    //         else if n < 6.0 { "Moderate nutrient" }
    //         else if n < 8.0 { "High nutrient" }
    //         else { "Very high nutrient" };
    //
    //     let feeding = if n < 2.0 { "Light feeding only; excess nitrogen causes weak growth" }
    //         else if n < 4.0 { "Minimal feeding; use balanced NPK fertilizer" }
    //         else if n < 6.0 { "Standard annual feeding in spring" }
    //         else if n < 8.0 { "Benefits from generous feeding; responds well to compost" }
    //         else { "Heavy feeder; responds well to manure and regular feeding" };
    //
    //     lines.push("**Ecological Indicator (EIVE-N)**:".to_string());
    //     lines.push(format!("- Nutrient indicator: {:.1}/10", n));
    //     lines.push(format!("- Typical position: {}", nutrient_level));
    //     lines.push(format!("- Feeding: {}", feeding));
    //     lines.push("*Where species is most abundant in natural vegetation; indicates fertility level, not preference*".to_string());
    // }
    //
    // // Note about competition
    // lines.push(String::new());
    // lines.push("**Note**: These indicators show where plants are most abundant in nature after competition. Many plants found in low-fertility areas are competitively excluded from richer soils by faster-growing species - they may actually thrive with MORE fertilization than their natural habitat suggests. pH tolerance is more physiological, but nutrient response is worth experimenting with.".to_string());

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

/// Interpret Köppen-Geiger climate code with grandma-friendly description
/// Returns just the friendly description without the technical code
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
        "Cfa" => "Humid subtropical (hot humid summers, mild winters, rain year-round)",
        "Cfb" => "Temperate oceanic (mild year-round, no dry season)",
        "Cfc" => "Subpolar oceanic (cool summers, mild winters, wet year-round)",
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
