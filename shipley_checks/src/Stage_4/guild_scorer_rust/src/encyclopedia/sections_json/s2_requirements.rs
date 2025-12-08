//! S2: Growing Requirements (JSON)
//!
//! Cloned from sections_md/s2_requirements.rs with minimal changes.
//! Returns RequirementsSection struct instead of markdown String.
//!
//! CHANGE LOG from sections_md:
//! - Return type: String → RequirementsSection
//! - Markdown formatting → struct fields
//! - Local suitability comparison logic moved to separate function
//! - All classification logic unchanged
//!
//! Data Sources (same as markdown):
//! - EIVE indicators: `EIVEres-L`, `EIVEres-M`, `EIVEres-T`, `EIVEres-R`, `EIVEres-N`
//! - Climate envelope (BioClim): `wc2.1_30s_bio_5_*` (warmest month), `wc2.1_30s_bio_6_*` (coldest month), `wc2.1_30s_bio_12_*` (annual precip)
//! - Agroclimate indicators: `FD_*`, `CFD_*`, `TR_*`, `DTR_*`, `GSL_*`, `WW_*`, `CDD_*`
//! - Soil envelope: `phh2o_0_5cm_*`, `clay_0_5cm_*`, `sand_0_5cm_*`, `soc_0_5cm_*`

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::{get_str, get_f64};
use crate::encyclopedia::utils::classify::*;
use crate::encyclopedia::utils::texture as usda_texture;
use crate::encyclopedia::view_models::{
    RequirementsSection, LightRequirement, TemperatureSection, MoistureSection,
    SoilSection, SoilTextureDetails, TextureComponent, RangeValue, SoilParameter,
    OverallSuitability, ComparisonRow, FitLevel, DiseasePressure, GrowingTipJson,
};
use crate::encyclopedia::suitability::local_conditions::LocalConditions;
use crate::encyclopedia::suitability::advice::build_assessment;
use crate::encyclopedia::suitability::comparator::EnvelopeFit;
use crate::encyclopedia::suitability::climate_tier::TierMatchType;

// ============================================================================
// Unit Conversion Helpers - CLONED FROM sections_md
// ============================================================================

/// Convert dekadal mean to annual estimate (×36 dekads/year).
/// Used for FD (frost days), TR (tropical nights), SU (summer days).
#[inline]
fn dekadal_to_annual(value: f64) -> f64 {
    value * 36.0
}

/// Convert seasonal mean to annual estimate (×4 seasons/year).
/// Used for WW (warm-wet days).
#[inline]
fn seasonal_to_annual(value: f64) -> f64 {
    value * 4.0
}

/// Generate the S2 Growing Requirements section.
pub fn generate(
    data: &HashMap<String, Value>,
    local: Option<&LocalConditions>,
) -> RequirementsSection {
    // Build assessment if we have local conditions
    let assessment = local.map(|l| build_assessment(l, data, ""));

    // Light requirements
    let light = build_light_section(data);

    // Temperature section
    let mut temperature = build_temperature_section(data);
    if let (Some(ref loc), Some(ref assess)) = (&local, &assessment) {
        temperature.comparisons = build_temperature_comparisons(loc, assess);
        // Category badge = worst of individual comparisons
        let fits: Vec<FitLevel> = temperature.comparisons.iter().map(|c| c.fit).collect();
        if !fits.is_empty() {
            temperature.fit = Some(worst_fit(&fits));
        }
    }

    // Moisture section
    let mut moisture = build_moisture_section(data);
    if let (Some(ref loc), Some(ref assess)) = (&local, &assessment) {
        moisture.comparisons = build_moisture_comparisons(loc, assess);
        // Category badge = worst of individual comparisons
        let fits: Vec<FitLevel> = moisture.comparisons.iter().map(|c| c.fit).collect();
        if !fits.is_empty() {
            moisture.fit = Some(worst_fit(&fits));
        }
    }

    // Soil section
    let mut soil = build_soil_section(data);
    if let (Some(ref loc), Some(ref assess)) = (&local, &assessment) {
        soil.comparisons = build_soil_comparisons(loc, assess);
        // Category badge = worst of individual comparisons
        let fits: Vec<FitLevel> = soil.comparisons.iter().map(|c| c.fit).collect();
        if !fits.is_empty() {
            soil.fit = Some(worst_fit(&fits));
        }
        // Add amendments from soil and texture assessments (matches MD version)
        let all_amendments: Vec<String> = assess.soil.amendments.iter()
            .chain(assess.texture.amendments.iter())
            .cloned()
            .collect();
        soil.advice.extend(all_amendments);
    }

    // Climate tier override: if plant occurs in the same climate zone as the location,
    // cap severity at Marginal (never Outside). Rationale: the plant demonstrably grows
    // in this climate type, so minor envelope deviations aren't dealbreakers.
    if let Some(ref assess) = assessment {
        if assess.climate_zone.match_type == TierMatchType::ExactMatch {
            if temperature.fit == Some(FitLevel::Outside) {
                temperature.fit = Some(FitLevel::Marginal);
            }
            if moisture.fit == Some(FitLevel::Outside) {
                moisture.fit = Some(FitLevel::Marginal);
            }
            if soil.fit == Some(FitLevel::Outside) {
                soil.fit = Some(FitLevel::Marginal);
            }
        }
    }

    // Overall suitability - calibrated by worst category fit
    let category_fits = [temperature.fit, moisture.fit, soil.fit];
    let overall_suitability = match (&local, &assessment) {
        (Some(loc), Some(assess)) => Some(build_overall_suitability(loc, assess, &category_fits)),
        _ => None,
    };

    RequirementsSection {
        light,
        temperature,
        moisture,
        soil,
        overall_suitability,
    }
}

/// Try to get EIVE value from either column format.
/// CLONED FROM sections_md
fn get_eive(data: &HashMap<String, Value>, axis: &str) -> Option<f64> {
    get_f64(data, &format!("EIVE_{}_complete", axis))
        .or_else(|| get_f64(data, &format!("EIVEres-{}_complete", axis)))
        .or_else(|| get_f64(data, &format!("EIVE_{}", axis)))
        .or_else(|| get_f64(data, &format!("EIVEres-{}", axis)))
}

// ============================================================================
// Light Section - CLONED FROM sections_md
// ============================================================================

fn build_light_section(data: &HashMap<String, Value>) -> LightRequirement {
    let eive_l = get_eive(data, "L");
    let height_m = get_f64(data, "height_m");
    let category = eive_light_label(eive_l).to_string();

    let icon_fill_percent = eive_l
        .map(|l| ((l / 10.0) * 100.0) as u8)
        .unwrap_or(50);

    // Check if value is from expert observation or imputed
    let source = get_str(data, "EIVEres-L_source");
    let is_imputed = source.map(|s| s == "imputed").unwrap_or(false);

    let source_attribution = if eive_l.is_some() {
        if is_imputed {
            Some("Estimated from plant traits and habitat data using machine learning, calibrated against species with known Ecological Indicator Values for Europe (EIVE), derived from expert botanist field surveys.".to_string())
        } else {
            Some("Ecological Indicator Value for Europe (EIVE-L) from expert botanist field surveys — shows typical light conditions where this species is found in natural habitats under competition.".to_string())
        }
    } else {
        None
    };

    // Sun tolerance qualifier for tall trees with low EIVE-L
    // Distinguishes facultative shade-tolerant trees from true shade-obligate plants
    let sun_tolerance = sun_tolerance_qualifier(eive_l, height_m)
        .map(|s| s.to_string());

    LightRequirement {
        eive_l,
        category,
        icon_fill_percent,
        source_attribution,
        sun_tolerance,
    }
}

// ============================================================================
// Temperature Section - CLONED FROM sections_md
// ============================================================================

fn build_temperature_section(data: &HashMap<String, Value>) -> TemperatureSection {
    let mut details = Vec::new();

    // Get BioClim temperature variables
    let bio5_q50 = get_f64(data, "wc2.1_30s_bio_5_q50");
    let bio5_q95 = get_f64(data, "wc2.1_30s_bio_5_q95");
    let bio6_q05 = get_f64(data, "wc2.1_30s_bio_6_q05");
    let bio6_q50 = get_f64(data, "wc2.1_30s_bio_6_q50");

    // Summary with range
    let summary = match (bio5_q50, bio6_q50) {
        (Some(warm), Some(cold)) => {
            let cold_display = if cold > -0.5 && cold < 0.5 { 0.0 } else { cold };
            let range_str = match (bio6_q05, bio5_q95) {
                (Some(cold_min), Some(warm_max)) =>
                    format!(" (range: {:.0}°C to {:.0}°C)", cold_min, warm_max),
                _ => String::new(),
            };
            format!("{:.0}°C warmest month, {:.0}°C coldest month{}", warm, cold_display, range_str)
        }
        _ => "Temperature data not available".to_string(),
    };

    // ========== COLD STRESS ==========

    // Frost days
    let fd_q05 = get_f64(data, "FD_q05");
    let fd_q50 = get_f64(data, "FD_q50");
    let fd_q95 = get_f64(data, "FD_q95");
    if let Some(fd50) = fd_q50 {
        let fd50_annual = dekadal_to_annual(fd50);
        let fd_q05_annual = fd_q05.map(dekadal_to_annual);
        let fd_q95_annual = fd_q95.map(dekadal_to_annual);
        let frost_regime = classify_frost_regime(fd50_annual);

        let range_str = match (fd_q05_annual, fd_q95_annual) {
            (Some(lo), Some(hi)) => format!(" ({:.0}-{:.0} across locations)", lo, hi),
            (None, Some(hi)) => format!(" (up to {:.0} in coldest locations)", hi),
            _ => String::new(),
        };
        details.push(format!(
            "Frost days: {:.0}/year{} - {}",
            fd50_annual, range_str, frost_regime
        ));
    }

    // Cold spells
    let cfd_q50 = get_f64(data, "CFD_q50");
    let cfd_q95 = get_f64(data, "CFD_q95");
    if let Some(cfd50) = cfd_q50 {
        let cold_spell = classify_cold_spell(cfd50);
        let max_str = cfd_q95.map(|c| format!(", up to {:.0}", c)).unwrap_or_default();
        details.push(format!(
            "Cold spells: {:.0} consecutive days typical{} - {}",
            cfd50, max_str, cold_spell
        ));
    }

    // ========== HEAT STRESS ==========

    // Summer Days (SU) - days with maximum temp above 25°C
    let su_q50 = get_f64(data, "SU_q50");
    let su_q95 = get_f64(data, "SU_q95");
    if let Some(su50) = su_q50 {
        let su50_annual = dekadal_to_annual(su50);
        let su_q95_annual = su_q95.map(dekadal_to_annual);
        if su50_annual >= 5.0 {
            let heat_regime = if su50_annual > 120.0 { "Very hot summers" }
                else if su50_annual > 90.0 { "Hot summers" }
                else if su50_annual > 60.0 { "Warm summers" }
                else if su50_annual > 30.0 { "Mild summers" }
                else { "Cool summers" };
            let max_str = su_q95_annual.map(|s| format!(" (up to {:.0} in warmest)", s)).unwrap_or_default();
            details.push(format!(
                "Hot days: {:.0}/year{} - {}",
                su50_annual, max_str, heat_regime
            ));
        }
    }

    // Tropical Nights (TR) - nights with minimum temp above 20°C
    let tr_q05 = get_f64(data, "TR_q05");
    let tr_q50 = get_f64(data, "TR_q50");
    let tr_q95 = get_f64(data, "TR_q95");
    if let Some(tr50) = tr_q50 {
        let tr50_annual = dekadal_to_annual(tr50);
        let tr_q05_annual = tr_q05.map(dekadal_to_annual);
        let tr_q95_annual = tr_q95.map(dekadal_to_annual);
        let night_regime = classify_tropical_night_regime(tr50_annual);

        if tr50_annual < 1.0 {
            let range_str = match tr_q95_annual {
                Some(hi) if hi >= 1.0 => format!(" (up to {:.0} in warmest locations)", hi),
                _ => String::new(),
            };
            details.push(format!("Warm nights: Rare{} - {}", range_str, night_regime));
        } else {
            let range_str = match (tr_q05_annual, tr_q95_annual) {
                (Some(lo), Some(hi)) => format!(" ({:.0}-{:.0} across locations)", lo, hi),
                (None, Some(hi)) => format!(" (up to {:.0} in warmest)", hi),
                _ => String::new(),
            };
            details.push(format!(
                "Warm nights: {:.0}/year{} - {}",
                tr50_annual, range_str, night_regime
            ));
        }
    }

    // ========== CLIMATE STABILITY ==========

    // Day-night swing
    let dtr_q05 = get_f64(data, "DTR_q05");
    let dtr_q50 = get_f64(data, "DTR_q50");
    let dtr_q95 = get_f64(data, "DTR_q95");
    if let Some(dtr50) = dtr_q50 {
        let stability = if dtr50 < 8.0 { "Maritime/oceanic - stable" }
            else if dtr50 < 12.0 { "Temperate - moderate" }
            else { "Continental - large swings" };
        let range_str = match (dtr_q05, dtr_q95) {
            (Some(lo), Some(hi)) => format!(" ({:.0}-{:.0}°C across locations)", lo, hi),
            _ => String::new(),
        };
        details.push(format!("Day-night swing: {:.0}°C{} - {}", dtr50, range_str, stability));
    }

    // Growing season
    let gsl_q05 = get_f64(data, "GSL_q05");
    let gsl_q50 = get_f64(data, "GSL_q50");
    let gsl_q95 = get_f64(data, "GSL_q95");
    if let Some(gsl50) = gsl_q50 {
        let season_type = classify_growing_season(gsl50);
        let months = (gsl50 / 30.0).round() as i32;
        let range_str = match (gsl_q05, gsl_q95) {
            (Some(lo), Some(hi)) => format!(" ({:.0}-{:.0} days across locations)", lo, hi),
            _ => String::new(),
        };
        details.push(format!(
            "Growing season: {:.0} days (~{} months){} - {}",
            gsl50, months, range_str, season_type
        ));
    }

    TemperatureSection {
        summary,
        details,
        comparisons: Vec::new(),
        fit: None,
    }
}

/// Classify tropical night regime based on typical annual count
fn classify_tropical_night_regime(tr_q50: f64) -> &'static str {
    if tr_q50 > 100.0 { "Year-round warmth" }
    else if tr_q50 > 60.0 { "Hot summer nights" }
    else if tr_q50 > 30.0 { "Frequent warm nights" }
    else if tr_q50 > 10.0 { "Regular warm nights" }
    else if tr_q50 > 1.0 { "Occasional warm nights" }
    else { "Cool nights year-round" }
}

fn classify_frost_regime(fd_q50: f64) -> &'static str {
    if fd_q50 > 150.0 { "Extreme frost" }
    else if fd_q50 > 100.0 { "Very long frost season" }
    else if fd_q50 > 60.0 { "Long frost season" }
    else if fd_q50 > 30.0 { "Moderate frost" }
    else if fd_q50 > 10.0 { "Light frost" }
    else { "Frost-free to occasional" }
}

fn classify_cold_spell(cfd_q95: f64) -> &'static str {
    if cfd_q95 > 60.0 { "Extreme prolonged cold" }
    else if cfd_q95 > 30.0 { "Long winter freeze" }
    else if cfd_q95 > 14.0 { "Extended freezing" }
    else if cfd_q95 > 7.0 { "1-2 week freezes" }
    else if cfd_q95 > 3.0 { "Short cold snaps" }
    else { "No prolonged frost" }
}

fn classify_growing_season(gsl_q50: f64) -> &'static str {
    if gsl_q50 > 330.0 { "Year-round" }
    else if gsl_q50 > 270.0 { "Very long" }
    else if gsl_q50 > 210.0 { "Long" }
    else if gsl_q50 > 150.0 { "Moderate" }
    else if gsl_q50 > 90.0 { "Short" }
    else { "Very short" }
}

// ============================================================================
// Moisture Section - CLONED FROM sections_md
// ============================================================================

fn build_moisture_section(data: &HashMap<String, Value>) -> MoistureSection {
    let mut advice = Vec::new();

    // Annual Rainfall
    let bio12_q05 = get_f64(data, "wc2.1_30s_bio_12_q05");
    let bio12_q50 = get_f64(data, "wc2.1_30s_bio_12_q50");
    let bio12_q95 = get_f64(data, "wc2.1_30s_bio_12_q95");

    let rainfall_mm = bio12_q50.map(|typical| RangeValue {
        typical,
        min: bio12_q05.unwrap_or(typical),
        max: bio12_q95.unwrap_or(typical),
        unit: "mm/year".to_string(),
    });

    let summary = rainfall_mm.as_ref()
        .map(|r| format!("{:.0}mm/year rainfall", r.typical))
        .unwrap_or_else(|| "Moisture data not available".to_string());

    // Dry spells (CDD - consecutive dry days with precip <1mm)
    let cdd_q50 = get_f64(data, "CDD_q50");
    let cdd_q95 = get_f64(data, "CDD_q95");

    let dry_spell_days = cdd_q50.map(|typical| {
        let max = cdd_q95.unwrap_or(typical);
        // Describe natural dry spell conditions (threshold: <1mm/day defines "dry")
        let drought_desc = if max > 60.0 { "Extended dry seasons" }
            else if max > 30.0 { "Moderate dry periods" }
            else if max > 14.0 { "Brief dry spells" }
            else { "Rare dry weather" };
        advice.push(format!("Drought: {}", drought_desc));

        RangeValue {
            typical,
            min: typical,  // No q05 for CDD
            max,
            unit: "days".to_string(),
        }
    });

    // Warm-Wet Days (WW) - days with Tmax >25°C AND precip >1mm (disease risk indicator)
    let ww_q05 = get_f64(data, "WW_q05");
    let ww_q50 = get_f64(data, "WW_q50");
    let ww_q95 = get_f64(data, "WW_q95");
    let disease_pressure = ww_q50.map(|ww50| {
        let days_per_year = seasonal_to_annual(ww50);
        let min = ww_q05.map(seasonal_to_annual);
        let max = ww_q95.map(seasonal_to_annual);
        // Describe natural humidity conditions (threshold: >25°C + >1mm defines "warm-wet")
        let (level, interpretation) = if days_per_year > 150.0 {
            ("High", "High humidity climate")
        } else if days_per_year > 80.0 {
            ("Moderate", "Moderate humidity")
        } else {
            ("Low", "Low humidity exposure")
        };
        DiseasePressure {
            days_per_year,
            min,
            max,
            level: level.to_string(),
            interpretation: interpretation.to_string(),
        }
    });

    // Wet spells (CWD - consecutive days with precip >1mm)
    let cwd_q50 = get_f64(data, "CWD_q50");
    let cwd_q95 = get_f64(data, "CWD_q95");

    let wet_spell_days = cwd_q50.map(|typical| {
        // Describe natural wet spell conditions (threshold: >1mm/day defines "wet")
        let waterlog_desc = if typical > 14.0 { "Extended wet periods" }
            else if typical > 7.0 { "Moderate wet spells" }
            else { "Brief wet periods" };
        advice.push(format!("Waterlogging: {}", waterlog_desc));

        RangeValue {
            typical,
            min: typical,
            max: cwd_q95.unwrap_or(typical),
            unit: "days".to_string(),
        }
    });

    MoistureSection {
        summary,
        rainfall_mm,
        dry_spell_days,
        wet_spell_days,
        disease_pressure,
        comparisons: Vec::new(),
        advice,
        fit: None,
    }
}

fn classify_drought_tolerance(cdd_q95: f64) -> &'static str {
    if cdd_q95 > 60.0 { "High (tolerates >2 months dry)" }
    else if cdd_q95 > 30.0 { "Moderate (tolerates dry spells)" }
    else if cdd_q95 > 14.0 { "Limited" }
    else { "Low (requires regular moisture)" }
}

// ============================================================================
// Soil Section - CLONED FROM sections_md
// ============================================================================

fn build_soil_section(data: &HashMap<String, Value>) -> SoilSection {
    let advice = Vec::new();

    // Helper to calculate 0-15cm weighted average (topsoil - the amendable layer)
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

    // Depth-weighted average across all 6 SoilGrids layers (0-200cm profile)
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

    // pH
    let ph_q05_raw = calc_topsoil_avg("phh2o", "q05");
    let ph_q50_raw = calc_topsoil_avg("phh2o", "q50");
    let ph_q95_raw = calc_topsoil_avg("phh2o", "q95");
    let (ph_q05, ph_q50, ph_q95) = adjust_ph_values(ph_q05_raw, ph_q50_raw, ph_q95_raw);

    let ph = ph_q50.map(|value| {
        let ph_type = if value < 5.0 { "Strongly acidic" }
            else if value < 5.5 { "Moderately acidic" }
            else if value < 6.5 { "Slightly acidic" }
            else if value < 7.5 { "Neutral" }
            else if value < 8.0 { "Slightly alkaline" }
            else { "Alkaline/chalky" };

        let range = match (ph_q05, ph_q95) {
            (Some(lo), Some(hi)) => format!("{:.1}-{:.1}", lo, hi),
            _ => "unknown".to_string(),
        };

        SoilParameter {
            value,
            range,
            interpretation: ph_type.to_string(),
        }
    });

    // CEC (fertility)
    let cec_q05 = calc_topsoil_avg("cec", "q05");
    let cec_q50 = calc_topsoil_avg("cec", "q50");
    let cec_q95 = calc_topsoil_avg("cec", "q95");

    let fertility = cec_q50.map(|value| {
        let cec_interpretation = if value < 10.0 { "Low retention (sandy)" }
            else if value < 20.0 { "Moderate retention" }
            else if value < 30.0 { "Good retention" }
            else { "Excellent retention (clay/peat)" };

        let range = match (cec_q05, cec_q95) {
            (Some(lo), Some(hi)) => format!("{:.0}-{:.0}", lo, hi),
            _ => "unknown".to_string(),
        };

        SoilParameter {
            value,
            range,
            interpretation: cec_interpretation.to_string(),
        }
    });

    // SOC (organic carbon)
    let soc_q05 = calc_topsoil_avg("soc", "q05");
    let soc_q50 = calc_topsoil_avg("soc", "q50");
    let soc_q95 = calc_topsoil_avg("soc", "q95");

    let organic_carbon = soc_q50.map(|value| {
        let range = match (soc_q05, soc_q95) {
            (Some(lo), Some(hi)) => format!("{:.0}-{:.0}", lo, hi),
            _ => "unknown".to_string(),
        };

        // Interpret organic carbon level based on typical value
        let interpretation = if value > 100.0 {
            "High organic matter"
        } else if value > 50.0 {
            "Moderate organic matter"
        } else if value > 20.0 {
            "Low organic matter"
        } else {
            "Mineral soil"
        };

        SoilParameter {
            value,
            range,
            interpretation: interpretation.to_string(),
        }
    });

    // Texture
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

    let (texture_summary, texture_details) = match (clay_q50, sand_q50, silt_q50) {
        (Some(clay), Some(sand), Some(silt)) => {
            let classification = usda_texture::classify_texture(clay, sand, silt);

            let summary = classification.as_ref()
                .map(|c| c.class_name.clone())
                .unwrap_or_else(|| "Unknown".to_string());

            let details = classification.map(|c| SoilTextureDetails {
                sand: TextureComponent {
                    typical: sand,
                    min: sand_q05.unwrap_or(sand),
                    max: sand_q95.unwrap_or(sand),
                },
                silt: TextureComponent {
                    typical: silt,
                    min: silt_q05.unwrap_or(silt),
                    max: silt_q95.unwrap_or(silt),
                },
                clay: TextureComponent {
                    typical: clay,
                    min: clay_q05.unwrap_or(clay),
                    max: clay_q95.unwrap_or(clay),
                },
                usda_class: c.class_name.clone(),
                drainage: c.drainage.to_string(),
                water_retention: c.water_retention.to_string(),
                interpretation: c.advice.to_string(),
                triangle_x: Some(c.x),
                triangle_y: Some(c.y),
            });

            (summary, details)
        }
        _ => ("Unknown".to_string(), None),
    };

    // ========== PROFILE AVERAGE (0-200cm) ==========
    // Profile pH (with range)
    let profile_ph_q05_raw = calc_profile_avg("phh2o", "_q05");
    let profile_ph_q50_raw = calc_profile_avg("phh2o", "_q50");
    let profile_ph_q95_raw = calc_profile_avg("phh2o", "_q95");
    let (profile_ph_q05, profile_ph_q50, profile_ph_q95) = adjust_ph_values(
        profile_ph_q05_raw, profile_ph_q50_raw, profile_ph_q95_raw
    );

    let profile_ph = profile_ph_q50.map(|value| {
        let range = match (profile_ph_q05, profile_ph_q95) {
            (Some(lo), Some(hi)) => format!("{:.1}-{:.1}", lo, hi),
            _ => "unknown".to_string(),
        };
        SoilParameter {
            value,
            range,
            interpretation: "0-200cm average".to_string(),
        }
    });

    // Profile CEC (with range)
    let profile_cec_q05 = calc_profile_avg("cec", "_q05");
    let profile_cec_q50 = calc_profile_avg("cec", "_q50");
    let profile_cec_q95 = calc_profile_avg("cec", "_q95");

    let profile_fertility = profile_cec_q50.map(|value| {
        let range = match (profile_cec_q05, profile_cec_q95) {
            (Some(lo), Some(hi)) => format!("{:.0}-{:.0}", lo, hi),
            _ => "unknown".to_string(),
        };
        SoilParameter {
            value,
            range,
            interpretation: "cmol/kg (0-200cm)".to_string(),
        }
    });

    // Profile SOC (with range)
    let profile_soc_q05 = calc_profile_avg("soc", "_q05");
    let profile_soc_q50 = calc_profile_avg("soc", "_q50");
    let profile_soc_q95 = calc_profile_avg("soc", "_q95");

    let profile_organic_carbon = profile_soc_q50.map(|value| {
        let range = match (profile_soc_q05, profile_soc_q95) {
            (Some(lo), Some(hi)) => format!("{:.0}-{:.0}", lo, hi),
            _ => "unknown".to_string(),
        };
        SoilParameter {
            value,
            range,
            interpretation: "g/kg (0-200cm)".to_string(),
        }
    });

    SoilSection {
        texture_summary,
        texture_details,
        ph,
        fertility,
        organic_carbon,
        profile_ph,
        profile_fertility,
        profile_organic_carbon,
        comparisons: Vec::new(),
        advice,
        fit: None,
    }
}

/// Adjust pH values if they appear to be ×10 scaled.
fn adjust_ph_values(q05: Option<f64>, q50: Option<f64>, q95: Option<f64>) -> (Option<f64>, Option<f64>, Option<f64>) {
    match q50 {
        Some(v) if v > 14.0 => (
            q05.map(|x| x / 10.0),
            q50.map(|x| x / 10.0),
            q95.map(|x| x / 10.0),
        ),
        _ => (q05, q50, q95),
    }
}

// ============================================================================
// Local Comparisons - Adapted from sections_md
// ============================================================================

fn build_temperature_comparisons(
    _local: &LocalConditions,
    assessment: &crate::encyclopedia::suitability::assessment::SuitabilityAssessment,
) -> Vec<ComparisonRow> {
    let temp = &assessment.temperature;
    let mut rows = Vec::new();

    // Frost days
    if let Some(ref comp) = temp.frost_comparison {
        rows.push(ComparisonRow {
            parameter: "Frost days/year".to_string(),
            local_value: format!("{:.0}", dekadal_to_annual(comp.local_value)),
            plant_range: format!("{:.0}–{:.0}", dekadal_to_annual(comp.q05), dekadal_to_annual(comp.q95)),
            fit: convert_fit_with_tolerance(comp, MIN_ABS_FROST_DAYS),
        });
    }

    // Tropical nights
    if let Some(ref comp) = temp.tropical_nights_comparison {
        rows.push(ComparisonRow {
            parameter: "Warm nights (>20°C)".to_string(),
            local_value: format!("{:.0}", dekadal_to_annual(comp.local_value)),
            plant_range: format!("{:.0}–{:.0}", dekadal_to_annual(comp.q05), dekadal_to_annual(comp.q95)),
            fit: convert_fit_with_tolerance(comp, MIN_ABS_WARM_NIGHTS),
        });
    }

    // Growing season
    if let Some(ref comp) = temp.growing_season_comparison {
        rows.push(ComparisonRow {
            parameter: "Growing season (days)".to_string(),
            local_value: format!("{:.0}", comp.local_value),
            plant_range: format!("{:.0}–{:.0}", comp.q05, comp.q95),
            fit: convert_fit_with_tolerance(comp, MIN_ABS_GROWING_SEASON),
        });
    }

    rows
}

fn build_moisture_comparisons(
    _local: &LocalConditions,
    assessment: &crate::encyclopedia::suitability::assessment::SuitabilityAssessment,
) -> Vec<ComparisonRow> {
    let moisture = &assessment.moisture;
    let mut rows = Vec::new();

    if let Some(ref comp) = moisture.rainfall_comparison {
        rows.push(ComparisonRow {
            parameter: "Annual rainfall (mm)".to_string(),
            local_value: format!("{:.0}", comp.local_value),
            plant_range: format!("{:.0}–{:.0}", comp.q05, comp.q95),
            fit: convert_fit_with_tolerance(comp, MIN_ABS_RAINFALL),
        });
    }

    if let Some(ref comp) = moisture.dry_days_comparison {
        rows.push(ComparisonRow {
            parameter: "Max dry spell (days)".to_string(),
            local_value: format!("{:.0}", comp.local_value),
            plant_range: format!("{:.0}–{:.0}", comp.q05, comp.q95),
            fit: convert_fit_with_tolerance(comp, MIN_ABS_DRY_DAYS),
        });
    }

    // Wet days comparison
    if let Some(ref comp) = moisture.wet_days_comparison {
        rows.push(ComparisonRow {
            parameter: "Max wet spell (days)".to_string(),
            local_value: format!("{:.0}", comp.local_value),
            plant_range: format!("{:.0}–{:.0}", comp.q05, comp.q95),
            fit: convert_fit_with_tolerance(comp, MIN_ABS_WET_DAYS),
        });
    }

    rows
}

fn build_soil_comparisons(
    _local: &LocalConditions,
    assessment: &crate::encyclopedia::suitability::assessment::SuitabilityAssessment,
) -> Vec<ComparisonRow> {
    let soil = &assessment.soil;
    let texture = &assessment.texture;
    let mut rows = Vec::new();

    if let Some(ref comp) = soil.ph_comparison {
        rows.push(ComparisonRow {
            parameter: "Soil pH".to_string(),
            local_value: format!("{:.1}", comp.local_value),
            plant_range: format!("{:.1}–{:.1}", comp.q05, comp.q95),
            fit: convert_fit_with_tolerance(comp, MIN_ABS_PH),
        });
    }

    if let Some(ref comp) = soil.cec_comparison {
        rows.push(ComparisonRow {
            parameter: "Fertility (CEC)".to_string(),
            local_value: format!("{:.0}", comp.local_value),
            plant_range: format!("{:.0}–{:.0}", comp.q05, comp.q95),
            fit: convert_fit_with_tolerance(comp, MIN_ABS_CEC),
        });
    }

    // Texture compatibility
    if let Some(ref local_tex) = texture.local_texture {
        use crate::encyclopedia::suitability::assessment::TextureCompatibility;
        let fit = match texture.compatibility {
            TextureCompatibility::Ideal | TextureCompatibility::Good => FitLevel::Good,
            TextureCompatibility::Marginal => FitLevel::Marginal,
            TextureCompatibility::Poor => FitLevel::Outside,
            TextureCompatibility::Unknown => FitLevel::Unknown,
        };
        let plant_tex_name = texture.plant_texture.as_ref()
            .map(|t| t.class_name.as_str())
            .unwrap_or("Unknown");
        rows.push(ComparisonRow {
            parameter: "Soil texture".to_string(),
            local_value: local_tex.class_name.clone(),
            plant_range: plant_tex_name.to_string(),
            fit,
        });
    }

    rows
}

// ============================================================================
// Minimum Absolute Thresholds (in native units)
// ============================================================================
// These prevent trivial deviations from triggering poor ratings.
// Values chosen to align with Growing Tips thresholds.

/// Frost days: 5 days annual = 5/36 dekadal (data stored as dekadal mean)
const MIN_ABS_FROST_DAYS: f64 = 5.0 / 36.0;

/// Warm nights: 10 nights annual = 10/36 dekadal (data stored as dekadal mean)
const MIN_ABS_WARM_NIGHTS: f64 = 10.0 / 36.0;

/// Growing season: 15 days (already annual)
const MIN_ABS_GROWING_SEASON: f64 = 15.0;

/// Rainfall: 100mm
const MIN_ABS_RAINFALL: f64 = 100.0;

/// Dry spells: 5 days
const MIN_ABS_DRY_DAYS: f64 = 5.0;

/// Wet spells: 3 days
const MIN_ABS_WET_DAYS: f64 = 3.0;

/// Soil pH: 0.3 units
const MIN_ABS_PH: f64 = 0.3;

/// CEC: 3 cmol/kg
const MIN_ABS_CEC: f64 = 3.0;

/// Convert envelope comparison to FitLevel using hybrid percentile + tolerance system.
///
/// Logic:
/// - Within Q05-Q95 → Ideal (this is where 90% of specimens occur)
/// - Outside Q05-Q95 but within tolerance buffer → Good
/// - Beyond tolerance but <50% of range width → Marginal
/// - ≥50% of range width beyond → Outside
///
/// Tolerance buffer = max(10% of range width, min_absolute_threshold)
fn convert_fit_with_tolerance(
    comp: &crate::encyclopedia::suitability::comparator::EnvelopeComparison,
    min_absolute: f64,
) -> FitLevel {
    // If comparator says within range, it's Optimal - even for zero-width ranges
    // (e.g., cold-climate plants with 0 warm nights: local=0, q05=0, q95=0)
    if comp.fit == EnvelopeFit::WithinRange {
        return FitLevel::Optimal;
    }

    let range_width = comp.q95 - comp.q05;

    // For zero-width ranges where we're outside, use min_absolute as tolerance
    if range_width <= 0.0 {
        let distance = comp.distance_from_range;
        return if distance <= min_absolute {
            FitLevel::Good
        } else if distance <= min_absolute * 5.0 {
            FitLevel::Marginal
        } else {
            FitLevel::Outside
        };
    }

    // Normal case: non-zero range width
    match comp.fit {
        EnvelopeFit::WithinRange => FitLevel::Optimal, // Already handled above
        EnvelopeFit::BelowRange | EnvelopeFit::AboveRange => {
            // Calculate tolerance buffer: larger of 10% range or min absolute
            let tolerance = (range_width * 0.10).max(min_absolute);

            // Distance from nearest boundary (already computed in comparator)
            let distance = comp.distance_from_range;

            if distance <= tolerance {
                FitLevel::Good  // Within tolerance buffer
            } else if distance <= range_width * 0.50 {
                FitLevel::Marginal  // Beyond tolerance but not extreme
            } else {
                FitLevel::Outside  // Far outside range
            }
        }
    }
}

/// Get worst (most severe) FitLevel from a slice
fn worst_fit(fits: &[FitLevel]) -> FitLevel {
    fits.iter().fold(FitLevel::Optimal, |worst, &fit| {
        match (worst, fit) {
            (FitLevel::Outside, _) | (_, FitLevel::Outside) => FitLevel::Outside,
            (FitLevel::Marginal, _) | (_, FitLevel::Marginal) => FitLevel::Marginal,
            (FitLevel::Good, _) | (_, FitLevel::Good) => FitLevel::Good,
            (FitLevel::Unknown, _) | (_, FitLevel::Unknown) => FitLevel::Unknown,
            _ => FitLevel::Optimal,
        }
    })
}


fn build_overall_suitability(
    local: &LocalConditions,
    assessment: &crate::encyclopedia::suitability::assessment::SuitabilityAssessment,
    category_fits: &[Option<FitLevel>],
) -> OverallSuitability {
    use crate::encyclopedia::suitability::advice::generate_growing_tips;

    // Determine overall fit from worst category
    let worst_category = category_fits
        .iter()
        .filter_map(|f| *f)
        .fold(FitLevel::Optimal, |worst, fit| {
            match (worst, fit) {
                (FitLevel::Outside, _) | (_, FitLevel::Outside) => FitLevel::Outside,
                (FitLevel::Marginal, _) | (_, FitLevel::Marginal) => FitLevel::Marginal,
                (FitLevel::Good, _) | (_, FitLevel::Good) => FitLevel::Good,
                (FitLevel::Unknown, _) | (_, FitLevel::Unknown) => FitLevel::Unknown,
                _ => FitLevel::Optimal,
            }
        });

    // Map worst category fit to score and verdict
    let (score_percent, verdict) = match worst_category {
        FitLevel::Optimal => (90, "Ideal conditions".to_string()),
        FitLevel::Good => (75, "Good match".to_string()),
        FitLevel::Marginal => (50, "Marginal - some challenges likely".to_string()),
        FitLevel::Outside => (25, "Beyond typical range - significant intervention needed".to_string()),
        FitLevel::Unknown => (50, "Insufficient data".to_string()),
    };

    // Collect concerns from all sections
    let mut key_concerns = Vec::new();
    key_concerns.extend(assessment.temperature.issues.iter().cloned());
    key_concerns.extend(assessment.moisture.issues.iter().cloned());

    // Collect advantages (interventions that help)
    let mut key_advantages = Vec::new();
    key_advantages.extend(assessment.temperature.interventions.iter().cloned());
    key_advantages.extend(assessment.moisture.recommendations.iter().cloned());

    // Generate structured growing tips
    let tips = generate_growing_tips(assessment);
    let growing_tips: Vec<GrowingTipJson> = tips
        .into_iter()
        .map(|t| GrowingTipJson {
            category: t.category,
            action: t.action,
            detail: t.detail,
            severity: t.severity,
        })
        .collect();

    // Tips severity veto: if tips indicate critical/warning issues, cap the score.
    // This ensures the headline matches the advice - if we're telling users they
    // need greenhouses or daily watering, we shouldn't call it "Good".
    let has_critical = growing_tips.iter().any(|t| t.severity == "critical");
    let has_warning = growing_tips.iter().any(|t| t.severity == "warning");

    let (final_score, final_verdict) = if has_critical {
        // Critical tips (e.g., "Overwinter indoors", "Drip irrigation required")
        // cap at NotRecommended regardless of category fits
        (score_percent.min(25), "Beyond typical range - significant intervention needed".to_string())
    } else if has_warning && score_percent > 50 {
        // Warning tips cap at Challenging
        (50, "Marginal - some challenges likely".to_string())
    } else {
        (score_percent, verdict)
    };

    OverallSuitability {
        location_name: local.name.clone(),
        score_percent: final_score,
        verdict: final_verdict,
        key_concerns,
        key_advantages,
        growing_tips,
    }
}
