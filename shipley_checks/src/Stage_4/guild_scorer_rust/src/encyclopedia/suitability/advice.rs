//! Advice Generation
//!
//! Generates friendly markdown advice text for suitability assessments.
//! Uses occurrence-based language (where the plant is found) rather than
//! prescriptive language (what the plant needs).

use std::collections::HashMap;
use serde_json::Value;

use super::assessment::*;
use super::climate_tier::*;
use super::comparator::*;
use super::local_conditions::LocalConditions;
use crate::encyclopedia::types::get_f64;
use crate::encyclopedia::utils::texture::classify_texture_from_clay_sand;

// ============================================================================
// Unit Conversion Helpers
// ============================================================================
//
// AgroClim indicators are stored as dekadal means (average per 10-day period).
// For user-friendly display, we convert to annual values where appropriate.

/// Convert dekadal mean to annual estimate (×36 dekads/year).
/// Used for FD (frost days), TR (tropical nights).
#[inline]
fn dekadal_to_annual(value: f64) -> f64 {
    value * 36.0
}

/// Generate the complete suitability section for an encyclopedia article
pub fn generate_suitability_section(
    local: &LocalConditions,
    plant_data: &HashMap<String, Value>,
    plant_name: &str,
) -> String {
    // Build the assessment
    let assessment = build_assessment(local, plant_data, plant_name);

    // Generate markdown
    let mut lines = Vec::new();

    lines.push(format!("## Growing in {}", local.name));
    lines.push(String::new());

    // Climate zone section
    lines.push(generate_climate_section(&assessment));
    lines.push(String::new());

    // Temperature section
    lines.push(generate_temperature_section(&assessment));
    lines.push(String::new());

    // Moisture section
    lines.push(generate_moisture_section(&assessment));
    lines.push(String::new());

    // Soil chemistry section
    lines.push(generate_soil_section(&assessment));
    lines.push(String::new());

    // Texture section (only if we have data)
    if assessment.texture.local_texture.is_some() || assessment.texture.plant_texture.is_some() {
        lines.push(generate_texture_section(&assessment));
        lines.push(String::new());
    }

    // Overall section
    lines.push(generate_overall_section(&assessment));

    lines.join("\n")
}

/// Build a complete suitability assessment
pub fn build_assessment(
    local: &LocalConditions,
    plant_data: &HashMap<String, Value>,
    plant_name: &str,
) -> SuitabilityAssessment {
    // Build climate zone assessment
    let plant_tiers = extract_plant_tiers(plant_data);
    let climate_zone = ClimateZoneAssessment::new(local.climate_tier(), plant_tiers);

    // Build temperature assessment
    let temperature = build_temperature_assessment(local, plant_data);

    // Build moisture assessment
    let moisture = build_moisture_assessment(local, plant_data);

    // Build soil assessment
    let soil = build_soil_assessment(local, plant_data);

    // Build texture assessment
    let texture = build_texture_assessment(local, plant_data);

    // Create assessment (initially without overall rating and summary)
    let mut assessment = SuitabilityAssessment {
        location: local.name.clone(),
        plant_name: plant_name.to_string(),
        climate_zone,
        temperature,
        moisture,
        soil,
        texture,
        overall_rating: OverallRating::Ideal, // Placeholder
        summary: String::new(), // Placeholder
    };

    // Compute overall rating
    assessment.overall_rating = compute_overall_rating(&assessment);

    // Generate summary
    assessment.summary = generate_summary(&assessment);

    assessment
}

/// Extract plant tier flags from plant data
fn extract_plant_tiers(data: &HashMap<String, Value>) -> PlantTierFlags {
    PlantTierFlags {
        tropical: get_bool(data, "tier_1_tropical"),
        mediterranean: get_bool(data, "tier_2_mediterranean"),
        humid_temperate: get_bool(data, "tier_3_humid_temperate"),
        continental: get_bool(data, "tier_4_continental"),
        boreal_polar: get_bool(data, "tier_5_boreal_polar"),
        arid: get_bool(data, "tier_6_arid"),
    }
}

fn get_bool(data: &HashMap<String, Value>, key: &str) -> bool {
    data.get(key)
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

/// Build temperature assessment
fn build_temperature_assessment(
    local: &LocalConditions,
    plant_data: &HashMap<String, Value>,
) -> TemperatureSuitability {
    let mut assessment = TemperatureSuitability::default();
    let mut issues = Vec::new();
    let mut interventions = Vec::new();

    // Frost days comparison
    // Note: FD is stored as dekadal means, so convert distance to annual for threshold comparison
    if let Some(comp) = compare_to_envelope_opt(
        local.frost_days,
        get_f64(plant_data, "FD_q05"),
        get_f64(plant_data, "FD_q50"),
        get_f64(plant_data, "FD_q95"),
    ) {
        if comp.fit == EnvelopeFit::AboveRange {
            // Convert dekadal distance to annual (×36) for intuitive thresholds
            let annual_distance = dekadal_to_annual(comp.distance_from_range);
            if annual_distance > 50.0 {
                issues.push("Significantly more frost days than where this plant is observed".to_string());
                interventions.push("Consider cold-hardy alternatives from the same genus".to_string());
            } else if annual_distance > 30.0 {
                issues.push("More frost days than typical occurrence locations".to_string());
                interventions.push("Winter protection essential".to_string());
            } else if annual_distance > 10.0 {
                issues.push("Slightly more frost than typical".to_string());
                interventions.push("Consider fleece protection in cold snaps".to_string());
            }
        }
        assessment.frost_comparison = Some(comp);
    }

    // Tropical nights comparison
    // Note: TR is stored as dekadal means, so convert distance to annual for threshold comparison
    if let Some(comp) = compare_to_envelope_opt(
        local.tropical_nights,
        get_f64(plant_data, "TR_q05"),
        get_f64(plant_data, "TR_q50"),
        get_f64(plant_data, "TR_q95"),
    ) {
        if comp.fit == EnvelopeFit::AboveRange {
            // Convert dekadal distance to annual (×36) for intuitive thresholds
            let annual_distance = dekadal_to_annual(comp.distance_from_range);
            if annual_distance > 100.0 {
                issues.push("This plant is not found in locations with year-round warm nights".to_string());
            } else if annual_distance > 30.0 {
                issues.push("Warmer nights than where this plant typically occurs".to_string());
                interventions.push("Consider shade and root cooling".to_string());
            }
        }
        assessment.tropical_nights_comparison = Some(comp);
    }

    // Growing season comparison
    if let Some(comp) = compare_to_envelope_opt(
        local.growing_season_days,
        get_f64(plant_data, "GSL_q05"),
        get_f64(plant_data, "GSL_q50"),
        get_f64(plant_data, "GSL_q95"),
    ) {
        if comp.fit == EnvelopeFit::BelowRange {
            if comp.distance_from_range > 60.0 {
                issues.push("Growing season much shorter than where this plant occurs".to_string());
                interventions.push("Choose species adapted to shorter growing seasons".to_string());
            } else if comp.distance_from_range > 30.0 {
                issues.push("Shorter growing season than typical occurrence locations".to_string());
                interventions.push("Early start under cover recommended".to_string());
            }
        } else if comp.fit == EnvelopeFit::AboveRange && comp.distance_from_range > 60.0 {
            issues.push("This plant typically occurs in locations with seasonal dormancy".to_string());
        }
        assessment.growing_season_comparison = Some(comp);
    }

    // BIO5 (warmest month) - column is wc2.1_30s_bio_5_q05
    assessment.warmest_month_comparison = compare_to_envelope_opt(
        local.temp_warmest_month,
        get_f64(plant_data, "wc2.1_30s_bio_5_q05"),
        get_f64(plant_data, "wc2.1_30s_bio_5_q50"),
        get_f64(plant_data, "wc2.1_30s_bio_5_q95"),
    );

    // BIO6 (coldest month) - column is wc2.1_30s_bio_6_q05
    assessment.coldest_month_comparison = compare_to_envelope_opt(
        local.temp_coldest_month,
        get_f64(plant_data, "wc2.1_30s_bio_6_q05"),
        get_f64(plant_data, "wc2.1_30s_bio_6_q50"),
        get_f64(plant_data, "wc2.1_30s_bio_6_q95"),
    );

    // Determine overall rating
    assessment.rating = if issues.iter().any(|i| i.contains("not found")) {
        FitRating::OutOfRange
    } else if !issues.is_empty() {
        FitRating::Marginal
    } else {
        FitRating::WithinRange
    };

    assessment.issues = issues;
    assessment.interventions = interventions;
    assessment
}

/// Build moisture assessment
fn build_moisture_assessment(
    local: &LocalConditions,
    plant_data: &HashMap<String, Value>,
) -> MoistureSuitability {
    let mut assessment = MoistureSuitability::default();
    let mut issues = Vec::new();
    let mut recommendations = Vec::new();

    // Annual rainfall comparison - column is wc2.1_30s_bio_12_q05
    if let Some(comp) = compare_to_envelope_opt(
        local.annual_rainfall_mm,
        get_f64(plant_data, "wc2.1_30s_bio_12_q05"),
        get_f64(plant_data, "wc2.1_30s_bio_12_q50"),
        get_f64(plant_data, "wc2.1_30s_bio_12_q95"),
    ) {
        if comp.fit == EnvelopeFit::BelowRange {
            let ratio = local.annual_rainfall_mm / comp.q05.max(1.0);
            if ratio < 0.5 {
                issues.push("Much drier than where this plant is observed".to_string());
                recommendations.push("Drip irrigation essential".to_string());
            } else {
                issues.push("Drier than typical occurrence locations".to_string());
                recommendations.push("Regular supplemental watering recommended".to_string());
            }
        } else if comp.fit == EnvelopeFit::AboveRange {
            let ratio = local.annual_rainfall_mm / comp.q95.max(1.0);
            if ratio > 2.0 {
                issues.push("Much wetter than where this plant is observed".to_string());
                recommendations.push("Drainage critical - raised beds recommended".to_string());
            } else if ratio > 1.5 {
                issues.push("Wetter than typical occurrence locations".to_string());
                recommendations.push("Good drainage essential".to_string());
            } else {
                issues.push("Slightly wetter than typical".to_string());
                recommendations.push("Ensure adequate drainage".to_string());
            }
        }
        assessment.rainfall_comparison = Some(comp);
    }

    // Consecutive dry days
    if let Some(comp) = compare_to_envelope_opt(
        local.consecutive_dry_days,
        get_f64(plant_data, "CDD_q05"),
        get_f64(plant_data, "CDD_q50"),
        get_f64(plant_data, "CDD_q95"),
    ) {
        if comp.fit == EnvelopeFit::AboveRange && comp.distance_from_range > 14.0 {
            issues.push("Longer dry spells than typical".to_string());
            recommendations.push("Water during extended dry periods".to_string());
        }
        assessment.dry_days_comparison = Some(comp);
    }

    // Consecutive wet days
    if let Some(comp) = compare_to_envelope_opt(
        local.consecutive_wet_days,
        get_f64(plant_data, "CWD_q05"),
        get_f64(plant_data, "CWD_q50"),
        get_f64(plant_data, "CWD_q95"),
    ) {
        if comp.fit == EnvelopeFit::AboveRange && comp.distance_from_range > 7.0 {
            issues.push("More consecutive wet days than typical".to_string());
            recommendations.push("Improve drainage to prevent waterlogging".to_string());
        }
        assessment.wet_days_comparison = Some(comp);
    }

    // Determine overall rating
    assessment.rating = if issues.iter().any(|i| i.contains("Much")) {
        FitRating::OutOfRange
    } else if !issues.is_empty() {
        FitRating::Marginal
    } else {
        FitRating::WithinRange
    };

    assessment.issues = issues;
    assessment.recommendations = recommendations;
    assessment
}

/// Build soil chemistry assessment
fn build_soil_assessment(
    local: &LocalConditions,
    plant_data: &HashMap<String, Value>,
) -> SoilSuitability {
    let mut assessment = SoilSuitability::default();
    let mut amendments = Vec::new();

    // pH comparison - use topsoil (0-5cm) depth
    if let Some(comp) = compare_to_envelope_opt(
        local.soil_ph,
        get_f64(plant_data, "phh2o_0_5cm_q05"),
        get_f64(plant_data, "phh2o_0_5cm_q50"),
        get_f64(plant_data, "phh2o_0_5cm_q95"),
    ) {
        assessment.ph_fit = PhFit::from_comparison(&comp);

        match assessment.ph_fit {
            PhFit::TooAcid => {
                if comp.distance_from_range > 0.5 {
                    amendments.push("Add lime (significant pH adjustment needed)".to_string());
                } else {
                    amendments.push("Add lime (minor adjustment)".to_string());
                }
            }
            PhFit::TooAlkaline => {
                if comp.distance_from_range > 0.5 {
                    amendments.push("Add sulfur or ericaceous compost (significant adjustment)".to_string());
                } else {
                    amendments.push("Add sulfur (minor adjustment)".to_string());
                }
            }
            PhFit::Good => {}
        }

        assessment.ph_comparison = Some(comp);
    }

    // CEC comparison - use topsoil (0-5cm) depth
    if let Some(comp) = compare_to_envelope_opt(
        local.soil_cec,
        get_f64(plant_data, "cec_0_5cm_q05"),
        get_f64(plant_data, "cec_0_5cm_q50"),
        get_f64(plant_data, "cec_0_5cm_q95"),
    ) {
        assessment.fertility_fit = FertilityFit::from_comparison(&comp);

        if assessment.fertility_fit == FertilityFit::Low {
            amendments.push("Low fertility - add compost, feed little and often".to_string());
        }

        assessment.cec_comparison = Some(comp);
    }

    // Determine overall rating
    assessment.rating = if assessment.ph_fit != PhFit::Good && assessment.fertility_fit == FertilityFit::Low {
        FitRating::OutOfRange
    } else if assessment.ph_fit != PhFit::Good || assessment.fertility_fit == FertilityFit::Low {
        FitRating::Marginal
    } else {
        FitRating::WithinRange
    };

    assessment.amendments = amendments;
    assessment
}

/// Build texture assessment
fn build_texture_assessment(
    local: &LocalConditions,
    plant_data: &HashMap<String, Value>,
) -> TextureSuitability {
    let mut assessment = TextureSuitability::default();

    // Classify local texture
    assessment.local_texture = classify_texture_from_clay_sand(
        local.soil_clay_pct,
        local.soil_sand_pct,
    );

    // Classify plant's typical texture (use topsoil 0-15cm weighted average)
    let plant_clay = calc_topsoil_avg(plant_data, "clay", "q50");
    let plant_sand = calc_topsoil_avg(plant_data, "sand", "q50");

    if let (Some(clay), Some(sand)) = (plant_clay, plant_sand) {
        assessment.plant_texture = classify_texture_from_clay_sand(clay, sand);
    }

    // Determine compatibility based on texture groups
    if let (Some(ref local_tex), Some(ref plant_tex)) = (&assessment.local_texture, &assessment.plant_texture) {
        let local_group = texture_group(&local_tex.class_name);
        let plant_group = texture_group(&plant_tex.class_name);

        assessment.compatibility = match (local_group, plant_group) {
            (a, b) if a == b => TextureCompatibility::Ideal,
            (TextureGroup::Loamy, _) | (_, TextureGroup::Loamy) => TextureCompatibility::Good,
            (TextureGroup::Sandy, TextureGroup::Clay) | (TextureGroup::Clay, TextureGroup::Sandy) => {
                TextureCompatibility::Poor
            }
            _ => TextureCompatibility::Marginal,
        };

        // Add amendments if needed
        if assessment.compatibility == TextureCompatibility::Poor {
            if local_group == TextureGroup::Clay {
                assessment.amendments.push("Heavy soil - add grit/sharp sand to improve drainage".to_string());
            } else {
                assessment.amendments.push("Light soil - add organic matter to improve water retention".to_string());
            }
        }
    }

    // Determine rating
    assessment.rating = match assessment.compatibility {
        TextureCompatibility::Ideal | TextureCompatibility::Good => FitRating::WithinRange,
        TextureCompatibility::Marginal => FitRating::Marginal,
        TextureCompatibility::Poor => FitRating::OutOfRange,
        TextureCompatibility::Unknown => FitRating::WithinRange, // Assume OK if unknown
    };

    assessment
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TextureGroup {
    Sandy,
    Loamy,
    Clay,
}

fn texture_group(class_name: &str) -> TextureGroup {
    match class_name {
        "Sand" | "Loamy Sand" | "Sandy Loam" => TextureGroup::Sandy,
        "Clay" | "Silty Clay" | "Sandy Clay" => TextureGroup::Clay,
        _ => TextureGroup::Loamy,
    }
}

/// Calculate 0-15cm weighted average (topsoil - the amendable layer)
fn calc_topsoil_avg(data: &HashMap<String, Value>, prefix: &str, suffix: &str) -> Option<f64> {
    let v1 = get_f64(data, &format!("{}_0_5cm_{}", prefix, suffix));
    let v2 = get_f64(data, &format!("{}_5_15cm_{}", prefix, suffix));
    match (v1, v2) {
        (Some(a), Some(b)) => Some((a * 5.0 + b * 10.0) / 15.0),
        (Some(a), None) => Some(a),
        (None, Some(b)) => Some(b),
        _ => None,
    }
}

// ============================================================================
// Markdown Generation
// ============================================================================

fn generate_climate_section(assessment: &SuitabilityAssessment) -> String {
    let climate = &assessment.climate_zone;
    let mut lines = Vec::new();

    let header = match climate.occurrence_fit {
        OccurrenceFit::Observed => "### Climatic Zone: Observed",
        OccurrenceFit::Related => "### Climatic Zone: Related",
        OccurrenceFit::NotObserved => "### Climatic Zone: Not Observed",
    };
    lines.push(header.to_string());

    let local_name = climate.local_tier.display_name();
    let plant_zones = climate.plant_tiers.observed_tiers_text();

    match climate.occurrence_fit {
        OccurrenceFit::Observed => {
            lines.push(format!(
                "Your {} climate matches where this plant naturally occurs.",
                local_name
            ));
            if !plant_zones.is_empty() {
                lines.push(format!("Plant observed in: {}", plant_zones));
            }
        }
        OccurrenceFit::Related => {
            lines.push(format!(
                "Your {} climate is related to where this plant occurs.",
                local_name
            ));
            if !plant_zones.is_empty() {
                lines.push(format!("Plant observed in: {}", plant_zones));
            }
        }
        OccurrenceFit::NotObserved => {
            lines.push(format!(
                "Your {} climate differs from where this plant is observed.",
                local_name
            ));
            if !plant_zones.is_empty() {
                lines.push(format!("Plant occurs in: {} zones.", plant_zones));
            }
        }
    }

    lines.join("\n")
}

fn generate_temperature_section(assessment: &SuitabilityAssessment) -> String {
    let temp = &assessment.temperature;
    let mut lines = Vec::new();

    let header = match temp.rating {
        FitRating::WithinRange => "### Temperature: Within Observed Range",
        FitRating::Marginal => "### Temperature: Marginal",
        FitRating::OutOfRange => "### Temperature: Outside Observed Range",
    };
    lines.push(header.to_string());
    lines.push(String::new());

    // Always show quantitative comparisons in a table
    lines.push("| Parameter | Your Location | Plant Range (5th-95th) | Typical |".to_string());
    lines.push("|-----------|---------------|------------------------|---------|".to_string());

    // Frost days - convert dekadal to annual for display
    if let Some(ref comp) = temp.frost_comparison {
        let status = match comp.fit {
            EnvelopeFit::WithinRange => "✓",
            EnvelopeFit::BelowRange => "↓",
            EnvelopeFit::AboveRange => "↑",
        };
        lines.push(format!(
            "| Frost days | {:.0} {} | {:.0}–{:.0} | {:.0} |",
            dekadal_to_annual(comp.local_value), status,
            dekadal_to_annual(comp.q05), dekadal_to_annual(comp.q95),
            dekadal_to_annual(comp.q50)
        ));
    }

    // Tropical nights - convert dekadal to annual for display
    if let Some(ref comp) = temp.tropical_nights_comparison {
        let status = match comp.fit {
            EnvelopeFit::WithinRange => "✓",
            EnvelopeFit::BelowRange => "↓",
            EnvelopeFit::AboveRange => "↑",
        };
        lines.push(format!(
            "| Warm nights (>20°C) | {:.0} {} | {:.0}–{:.0} | {:.0} |",
            dekadal_to_annual(comp.local_value), status,
            dekadal_to_annual(comp.q05), dekadal_to_annual(comp.q95),
            dekadal_to_annual(comp.q50)
        ));
    }

    // Growing season
    if let Some(ref comp) = temp.growing_season_comparison {
        let status = match comp.fit {
            EnvelopeFit::WithinRange => "✓",
            EnvelopeFit::BelowRange => "↓",
            EnvelopeFit::AboveRange => "↑",
        };
        lines.push(format!(
            "| Growing season (days) | {:.0} {} | {:.0}–{:.0} | {:.0} |",
            comp.local_value, status, comp.q05, comp.q95, comp.q50
        ));
    }

    // Warmest month
    if let Some(ref comp) = temp.warmest_month_comparison {
        let status = match comp.fit {
            EnvelopeFit::WithinRange => "✓",
            EnvelopeFit::BelowRange => "↓",
            EnvelopeFit::AboveRange => "↑",
        };
        lines.push(format!(
            "| Warmest month (°C) | {:.1} {} | {:.1}–{:.1} | {:.1} |",
            comp.local_value, status, comp.q05, comp.q95, comp.q50
        ));
    }

    // Coldest month
    if let Some(ref comp) = temp.coldest_month_comparison {
        let status = match comp.fit {
            EnvelopeFit::WithinRange => "✓",
            EnvelopeFit::BelowRange => "↓",
            EnvelopeFit::AboveRange => "↑",
        };
        lines.push(format!(
            "| Coldest month (°C) | {:.1} {} | {:.1}–{:.1} | {:.1} |",
            comp.local_value, status, comp.q05, comp.q95, comp.q50
        ));
    }

    // Separate severe (veto) issues from minor issues
    let severe_issues: Vec<_> = temp.issues.iter()
        .filter(|i| i.contains("not found") || i.contains("Significantly"))
        .collect();
    let minor_issues: Vec<_> = temp.issues.iter()
        .filter(|i| !i.contains("not found") && !i.contains("Significantly"))
        .collect();

    // Show severe issues first (these are veto factors)
    if !severe_issues.is_empty() {
        lines.push(String::new());
        lines.push("**Severe (veto factors):**".to_string());
        for issue in &severe_issues {
            lines.push(format!("- {}", issue));
        }
    }

    // Show minor issues
    if !minor_issues.is_empty() {
        lines.push(String::new());
        lines.push("**Issues:**".to_string());
        for issue in &minor_issues {
            lines.push(format!("- {}", issue));
        }
    }

    // Add interventions
    if !temp.interventions.is_empty() {
        lines.push(String::new());
        lines.push("**Recommendations:**".to_string());
        for intervention in &temp.interventions {
            lines.push(format!("- {}", intervention));
        }
    }

    lines.join("\n")
}

fn generate_moisture_section(assessment: &SuitabilityAssessment) -> String {
    let moisture = &assessment.moisture;
    let mut lines = Vec::new();

    let header = match moisture.rating {
        FitRating::WithinRange => "### Moisture: Within Observed Range",
        FitRating::Marginal => "### Moisture: Marginal",
        FitRating::OutOfRange => "### Moisture: Outside Observed Range",
    };
    lines.push(header.to_string());
    lines.push(String::new());

    // Always show quantitative comparisons in a table
    lines.push("| Parameter | Your Location | Plant Range (5th-95th) | Typical |".to_string());
    lines.push("|-----------|---------------|------------------------|---------|".to_string());

    // Annual rainfall
    if let Some(ref comp) = moisture.rainfall_comparison {
        let status = match comp.fit {
            EnvelopeFit::WithinRange => "✓",
            EnvelopeFit::BelowRange => "↓",
            EnvelopeFit::AboveRange => "↑",
        };
        lines.push(format!(
            "| Annual rainfall (mm) | {:.0} {} | {:.0}–{:.0} | {:.0} |",
            comp.local_value, status, comp.q05, comp.q95, comp.q50
        ));
    }

    // Consecutive dry days
    if let Some(ref comp) = moisture.dry_days_comparison {
        let status = match comp.fit {
            EnvelopeFit::WithinRange => "✓",
            EnvelopeFit::BelowRange => "↓",
            EnvelopeFit::AboveRange => "↑",
        };
        lines.push(format!(
            "| Max dry spell (days) | {:.0} {} | {:.0}–{:.0} | {:.0} |",
            comp.local_value, status, comp.q05, comp.q95, comp.q50
        ));
    }

    // Consecutive wet days
    if let Some(ref comp) = moisture.wet_days_comparison {
        let status = match comp.fit {
            EnvelopeFit::WithinRange => "✓",
            EnvelopeFit::BelowRange => "↓",
            EnvelopeFit::AboveRange => "↑",
        };
        lines.push(format!(
            "| Max wet spell (days) | {:.0} {} | {:.0}–{:.0} | {:.0} |",
            comp.local_value, status, comp.q05, comp.q95, comp.q50
        ));
    }

    // Separate severe (veto) issues from minor issues
    let severe_issues: Vec<_> = moisture.issues.iter()
        .filter(|i| i.contains("Much"))
        .collect();
    let minor_issues: Vec<_> = moisture.issues.iter()
        .filter(|i| !i.contains("Much"))
        .collect();

    // Show severe issues first (these are veto factors)
    if !severe_issues.is_empty() {
        lines.push(String::new());
        lines.push("**Severe (veto factors):**".to_string());
        for issue in &severe_issues {
            lines.push(format!("- {}", issue));
        }
    }

    // Show minor issues
    if !minor_issues.is_empty() {
        lines.push(String::new());
        lines.push("**Issues:**".to_string());
        for issue in &minor_issues {
            lines.push(format!("- {}", issue));
        }
    }

    // Add recommendations
    if !moisture.recommendations.is_empty() {
        lines.push(String::new());
        lines.push("**Recommendations:**".to_string());
        for rec in &moisture.recommendations {
            lines.push(format!("- {}", rec));
        }
    }

    lines.join("\n")
}

fn generate_soil_section(assessment: &SuitabilityAssessment) -> String {
    let soil = &assessment.soil;
    let mut lines = Vec::new();

    let header = match soil.rating {
        FitRating::WithinRange => "### Soil Chemistry: Within Observed Range",
        FitRating::Marginal => "### Soil Chemistry: Marginal",
        FitRating::OutOfRange => "### Soil Chemistry: Outside Observed Range",
    };
    lines.push(header.to_string());
    lines.push(String::new());

    // Always show quantitative comparisons in a table
    lines.push("| Parameter | Your Location | Plant Range (5th-95th) | Typical |".to_string());
    lines.push("|-----------|---------------|------------------------|---------|".to_string());

    // pH
    if let Some(ref comp) = soil.ph_comparison {
        let status = match comp.fit {
            EnvelopeFit::WithinRange => "✓",
            EnvelopeFit::BelowRange => "↓ acidic",
            EnvelopeFit::AboveRange => "↑ alkaline",
        };
        lines.push(format!(
            "| Soil pH | {:.1} {} | {:.1}–{:.1} | {:.1} |",
            comp.local_value, status, comp.q05, comp.q95, comp.q50
        ));
    }

    // CEC (fertility)
    if let Some(ref comp) = soil.cec_comparison {
        let status = match comp.fit {
            EnvelopeFit::WithinRange => "✓",
            EnvelopeFit::BelowRange => "↓ low",
            EnvelopeFit::AboveRange => "↑ high",
        };
        lines.push(format!(
            "| CEC (cmol/kg) | {:.1} {} | {:.1}–{:.1} | {:.1} |",
            comp.local_value, status, comp.q05, comp.q95, comp.q50
        ));
    }

    // Fertility interpretation
    lines.push(String::new());
    lines.push(format!("**Fertility**: {}", soil.fertility_fit.display_text()));

    // Amendments
    if !soil.amendments.is_empty() {
        lines.push(String::new());
        lines.push("**Amendments:**".to_string());
        for amendment in &soil.amendments {
            lines.push(format!("- {}", amendment));
        }
    }

    lines.join("\n")
}

fn generate_texture_section(assessment: &SuitabilityAssessment) -> String {
    let texture = &assessment.texture;
    let mut lines = Vec::new();

    let header = match texture.rating {
        FitRating::WithinRange => "### Soil Texture: Good Match",
        FitRating::Marginal => "### Soil Texture: Marginal Match",
        FitRating::OutOfRange => "### Soil Texture: Poor Match",
    };
    lines.push(header.to_string());

    if let Some(ref local_tex) = texture.local_texture {
        lines.push(format!("Your soil: {} ({})", local_tex.class_name, local_tex.advice));
    }

    if let Some(ref plant_tex) = texture.plant_texture {
        lines.push(format!("Plant's typical soil: {}", plant_tex.class_name));
    }

    if !texture.amendments.is_empty() {
        lines.push(String::new());
        for amendment in &texture.amendments {
            lines.push(format!("- {}", amendment));
        }
    }

    lines.join("\n")
}

fn generate_overall_section(assessment: &SuitabilityAssessment) -> String {
    let mut lines = Vec::new();

    lines.push(format!("### Overall: {}", assessment.overall_rating.display_text()));

    // Use summary if available (more specific), otherwise use generic description
    if !assessment.summary.is_empty() {
        lines.push(assessment.summary.clone());
    } else {
        lines.push(assessment.overall_rating.description().to_string());
    }

    lines.join("\n")
}

fn generate_summary(assessment: &SuitabilityAssessment) -> String {
    let mut parts = Vec::new();

    // Count categories
    let climate_ok = assessment.climate_zone.occurrence_fit != OccurrenceFit::NotObserved;
    let temp_ok = assessment.temperature.rating == FitRating::WithinRange;
    let moisture_ok = assessment.moisture.rating == FitRating::WithinRange;
    let soil_ok = assessment.soil.rating == FitRating::WithinRange;

    match assessment.overall_rating {
        OverallRating::Ideal => {
            parts.push("Conditions at your location match where this plant naturally thrives.".to_string());
        }
        OverallRating::Good => {
            if !climate_ok {
                parts.push("Your climate is related to where this plant occurs.".to_string());
            }
            if !temp_ok {
                parts.push("Minor temperature adaptations may help.".to_string());
            }
            if !moisture_ok {
                parts.push("Adjust watering to match plant preferences.".to_string());
            }
            if !soil_ok {
                parts.push("Soil amendments recommended.".to_string());
            }
        }
        OverallRating::Challenging => {
            parts.push("Significant intervention required for success.".to_string());
        }
        OverallRating::NotRecommended => {
            parts.push("Conditions differ significantly from where this plant is observed.".to_string());
            parts.push("Consider species native to your climate zone.".to_string());
        }
    }

    parts.join(" ")
}

// ============================================================================
// Growing Tips Generation
// ============================================================================

use super::assessment::GrowingTip;
use super::comparator::EnvelopeComparison;
use crate::encyclopedia::view_models::FitLevel;

/// Generate structured growing tips based on comparison data.
/// Each comparison's FitLevel determines both tip content AND severity.
pub fn generate_growing_tips(
    assessment: &SuitabilityAssessment,
    _temp_fit: Option<FitLevel>,
    _moisture_fit: Option<FitLevel>,
    _soil_fit: Option<FitLevel>,
) -> Vec<GrowingTip> {
    let mut tips = Vec::new();

    // Temperature tips - each comparison gets its own FitLevel
    tips.extend(generate_temperature_tips(&assessment.temperature));

    // Moisture tips - each comparison gets its own FitLevel
    tips.extend(generate_moisture_tips(&assessment.moisture));

    // Soil tips - each comparison gets its own FitLevel
    tips.extend(generate_soil_tips(&assessment.soil, &assessment.texture));

    tips
}

// ============================================================================
// Minimum Absolute Thresholds (matching s2_requirements.rs)
// ============================================================================
// These prevent trivial deviations from triggering poor ratings.

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

/// Round to specified decimal places
fn round_to_decimals(value: f64, decimals: u32) -> f64 {
    let factor = 10_f64.powi(decimals as i32);
    (value * factor).round() / factor
}

/// Compute FitLevel from a comparison using hybrid percentile + tolerance system.
///
/// Logic:
/// - If displayed values match (after rounding) → Optimal
/// - Within Q05-Q95 → Optimal (this is where 90% of specimens occur)
/// - Outside Q05-Q95 but within tolerance buffer → Good
/// - Beyond tolerance but <50% of range width → Marginal
/// - ≥50% of range width beyond → Outside
///
/// Tolerance buffer = max(10% of range width, min_absolute_threshold)
///
/// `display_decimals`: Number of decimal places used in UI display (0 for integers, 1 for pH)
fn comparison_to_fitlevel_with_min_abs(
    comp: &EnvelopeComparison,
    min_absolute: f64,
    display_decimals: u32,
) -> FitLevel {
    // If comparator says within range, it's Optimal - even for zero-width ranges
    if comp.fit == EnvelopeFit::WithinRange {
        return FitLevel::Optimal;
    }

    // Display-precision check: if rounded values show local within range, treat as Optimal.
    // This ensures classification matches what users see in the UI.
    let rounded_local = round_to_decimals(comp.local_value, display_decimals);
    let rounded_q05 = round_to_decimals(comp.q05, display_decimals);
    let rounded_q95 = round_to_decimals(comp.q95, display_decimals);
    if rounded_local >= rounded_q05 && rounded_local <= rounded_q95 {
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

/// Map FitLevel directly to severity.
/// Good → info, Marginal → warning, Outside → critical
fn fitlevel_to_severity(fit: FitLevel) -> &'static str {
    match fit {
        FitLevel::Optimal => "info",
        FitLevel::Good => "info",
        FitLevel::Marginal => "warning",
        FitLevel::Outside => "critical",
        FitLevel::Unknown => "info",
    }
}

/// Generate light placement tips based on EIVE-L preference and height.
///
/// Light doesn't have LocalConditions data (it's garden-spot-specific),
/// so we generate placement guidance based on the plant's EIVE-L alone.
///
/// **Height adjustment**: Tall trees (>5m) with low EIVE-L values are
/// facultatively shade-tolerant - they establish in shade but grow into
/// full sun as adults. This is reflected in the tip wording.
///
/// **Concerns**: Only generated for warning severity tips (strict requirements).
/// Info-level tips are flexible guidance, not concerns.
pub fn generate_light_tips(eive_l: Option<f64>, height_m: Option<f64>) -> Vec<GrowingTip> {
    let mut tips = Vec::new();

    // Check if this is a tall tree that can handle more sun at maturity
    let is_canopy_tree = matches!((eive_l, height_m), (Some(l), Some(h)) if l < 5.0 && h > 10.0);
    let is_subcanopy_tree = matches!((eive_l, height_m), (Some(l), Some(h)) if l < 5.0 && h > 5.0 && h <= 10.0);

    match eive_l {
        Some(l) if l < 2.0 => {
            if is_canopy_tree {
                tips.push(GrowingTip::new(
                    "light",
                    "Shade when young, full sun at maturity",
                    "Plant in sheltered spot; crown will reach full sun as tree matures",
                    "info",
                ));
            } else if is_subcanopy_tree {
                tips.push(GrowingTip::new(
                    "light",
                    "Shade when young, tolerates more sun later",
                    "Start in shade; can handle partial sun as it establishes",
                    "info",
                ));
            } else {
                // Small shade-obligate plant - strict requirement
                tips.push(GrowingTip::with_concern(
                    "light",
                    "Requires deep shade",
                    "Deep shade required",
                    "North-facing wall or under dense canopy; protect from direct sun",
                    "warning",
                ));
            }
        }
        Some(l) if l < 4.0 => {
            if is_canopy_tree {
                tips.push(GrowingTip::new(
                    "light",
                    "Shade-tolerant, full sun at maturity",
                    "Establish in partial shade; crown grows into full sun",
                    "info",
                ));
            } else if is_subcanopy_tree {
                tips.push(GrowingTip::new(
                    "light",
                    "Shade-tolerant when young",
                    "Start in shade; tolerates more sun as adult",
                    "info",
                ));
            } else {
                tips.push(GrowingTip::new(
                    "light",
                    "Shade preferred",
                    "Under trees or morning sun only; avoid afternoon sun",
                    "info",
                ));
            }
        }
        Some(l) if l < 6.0 => {
            if is_canopy_tree || is_subcanopy_tree {
                tips.push(GrowingTip::new(
                    "light",
                    "Part shade to full sun",
                    "Flexible positioning; tolerates range of light conditions",
                    "info",
                ));
            } else {
                tips.push(GrowingTip::new(
                    "light",
                    "Dappled light ideal",
                    "East-facing beds or open canopy; some direct sun acceptable",
                    "info",
                ));
            }
        }
        Some(l) if l >= 8.0 => {
            // Strict full-sun requirement
            tips.push(GrowingTip::with_concern(
                "light",
                "Requires full sun",
                "Full sun required",
                "South-facing, unobstructed; needs 6+ hours direct sun daily",
                "warning",
            ));
        }
        // 6.0-8.0: flexible, no special tip needed
        _ => {}
    }

    tips
}

fn generate_temperature_tips(temp: &TemperatureSuitability) -> Vec<GrowingTip> {
    let mut tips = Vec::new();

    // Frost days - too cold
    if let Some(ref comp) = temp.frost_comparison {
        let fit = comparison_to_fitlevel_with_min_abs(comp, MIN_ABS_FROST_DAYS, 0);
        if fit != FitLevel::Optimal {
            let severity = fitlevel_to_severity(fit);
            let annual_local = dekadal_to_annual(comp.local_value);
            let annual_q95 = dekadal_to_annual(comp.q95);
            let annual_q05 = dekadal_to_annual(comp.q05);

            if comp.fit == EnvelopeFit::AboveRange {
                let extra = (annual_local - annual_q95).round() as i32;
                let (concern, action, detail) = match fit {
                    FitLevel::Outside => (
                        Some("Significantly more frost"),
                        "Overwinter indoors",
                        format!("{} more frost days; grow in containers", extra),
                    ),
                    FitLevel::Marginal => (
                        Some("More frost than typical"),
                        "Protect in winter",
                        format!("{} more frost days; use fleece or cold frame", extra),
                    ),
                    _ => (None, "Fleece in cold snaps", format!("{} more frost days than typical", extra)),
                };
                if let Some(c) = concern {
                    tips.push(GrowingTip::with_concern("temperature", c, action, &detail, severity));
                } else {
                    tips.push(GrowingTip::new("temperature", action, &detail, severity));
                }
            } else if comp.fit == EnvelopeFit::BelowRange {
                let fewer = (annual_q05 - annual_local).round() as i32;
                let detail = format!("{} fewer frost days; may need refrigerated dormancy", fewer);
                let (concern, action) = match fit {
                    FitLevel::Outside => (Some("Insufficient winter chill"), "Provide artificial chill"),
                    FitLevel::Marginal => (Some("Fewer frost days than needed"), "Provide artificial chill"),
                    _ => (None, "Provide artificial chill"),
                };
                if let Some(c) = concern {
                    tips.push(GrowingTip::with_concern("temperature", c, action, &detail, severity));
                } else {
                    tips.push(GrowingTip::new("temperature", action, &detail, severity));
                }
            }
        }
    }

    // Tropical nights - heat stress
    if let Some(ref comp) = temp.tropical_nights_comparison {
        let fit = comparison_to_fitlevel_with_min_abs(comp, MIN_ABS_WARM_NIGHTS, 0);
        if fit != FitLevel::Optimal && comp.fit == EnvelopeFit::AboveRange {
            let severity = fitlevel_to_severity(fit);
            let annual_local = dekadal_to_annual(comp.local_value);
            let annual_q95 = dekadal_to_annual(comp.q95);
            let extra = (annual_local - annual_q95).round() as i32;

            let (concern, action, detail) = match fit {
                FitLevel::Outside => (
                    Some("Too warm for this plant"),
                    "Heat stress likely",
                    format!("{} more warm nights; plant may not thrive", extra),
                ),
                FitLevel::Marginal => (
                    Some("Warmer nights than typical"),
                    "Provide afternoon shade",
                    format!("{} more warm nights; cool roots with mulch", extra),
                ),
                _ => (None, "Mulch to cool roots", format!("{} more warm nights than typical", extra)),
            };
            if let Some(c) = concern {
                tips.push(GrowingTip::with_concern("temperature", c, action, &detail, severity));
            } else {
                tips.push(GrowingTip::new("temperature", action, &detail, severity));
            }
        }
    }

    // Growing season - only generate tips for Marginal/Outside (skip Good level)
    if let Some(ref comp) = temp.growing_season_comparison {
        let fit = comparison_to_fitlevel_with_min_abs(comp, MIN_ABS_GROWING_SEASON, 0);
        if fit == FitLevel::Marginal || fit == FitLevel::Outside {
            let severity = fitlevel_to_severity(fit);

            if comp.fit == EnvelopeFit::BelowRange {
                let fewer = (comp.q05 - comp.local_value).round() as i32;
                let (concern, action, detail) = match fit {
                    FitLevel::Outside => (
                        Some("Growing season too short"),
                        "Start early under cover",
                        format!("{} fewer growing days; extend with polytunnel", fewer),
                    ),
                    _ => (
                        Some("Shorter growing season"),
                        "Start seeds indoors",
                        format!("{} fewer growing days than typical", fewer),
                    ),
                };
                tips.push(GrowingTip::with_concern("temperature", concern.unwrap(), action, &detail, severity));
            } else if comp.fit == EnvelopeFit::AboveRange {
                let extra = (comp.local_value - comp.q95).round() as i32;
                let local_gsl = comp.local_value;
                let is_tropical = local_gsl >= 350.0;

                let (concern, action, detail) = match (is_tropical, fit) {
                    // Tropical (GSL ≥ 350): year-round growth language appropriate
                    (true, FitLevel::Outside) => (
                        "Insufficient winter dormancy",
                        "Consider dormancy needs",
                        format!("{} extra growing days; year-round growth possible but plant may be heat stressed", extra),
                    ),
                    (true, _) => (
                        "May lack seasonal cues",
                        "Consider dormancy needs",
                        format!("{} extra growing days; year-round growth likely possible", extra),
                    ),
                    // Temperate (GSL < 350): no "year-round" claims
                    (false, FitLevel::Outside) => (
                        "Insufficient winter dormancy",
                        "Consider dormancy needs",
                        format!("{} extra growing days; extended season may disrupt dormancy cycle", extra),
                    ),
                    (false, _) => (
                        "May lack seasonal cues",
                        "Monitor for dormancy issues",
                        format!("{} extra growing days; longer growing season than typical", extra),
                    ),
                };
                tips.push(GrowingTip::with_concern("temperature", concern, action, &detail, severity));
            }
        }
    }

    tips
}

fn generate_moisture_tips(moisture: &MoistureSuitability) -> Vec<GrowingTip> {
    let mut tips = Vec::new();

    // Annual rainfall
    if let Some(ref comp) = moisture.rainfall_comparison {
        let fit = comparison_to_fitlevel_with_min_abs(comp, MIN_ABS_RAINFALL, 0);
        if fit != FitLevel::Optimal {
            let severity = fitlevel_to_severity(fit);

            if comp.fit == EnvelopeFit::BelowRange {
                let deficit = (comp.q05 - comp.local_value).round() as i32;
                let (concern, action, detail) = match fit {
                    FitLevel::Outside => (
                        Some("Much drier than typical"),
                        "Drip irrigation required",
                        format!("{}mm less rainfall; irrigation essential", deficit),
                    ),
                    FitLevel::Marginal => (
                        Some("Drier than typical"),
                        "Water weekly in growing season",
                        format!("{}mm less annual rainfall", deficit),
                    ),
                    _ => (None, "Supplemental watering may help", format!("{}mm less rainfall than typical", deficit)),
                };
                if let Some(c) = concern {
                    tips.push(GrowingTip::with_concern("moisture", c, action, &detail, severity));
                } else {
                    tips.push(GrowingTip::new("moisture", action, &detail, severity));
                }
            } else if comp.fit == EnvelopeFit::AboveRange {
                let excess = (comp.local_value - comp.q95).round() as i32;
                let (concern, action, detail) = match fit {
                    FitLevel::Outside => (
                        Some("Much wetter than typical"),
                        "Raised bed with grit essential",
                        format!("{}mm more rainfall; drainage critical", excess),
                    ),
                    FitLevel::Marginal => (
                        Some("Wetter than typical"),
                        "Ensure excellent drainage",
                        format!("{}mm more annual rainfall", excess),
                    ),
                    _ => (None, "Good drainage recommended", format!("{}mm more rainfall than typical", excess)),
                };
                if let Some(c) = concern {
                    tips.push(GrowingTip::with_concern("moisture", c, action, &detail, severity));
                } else {
                    tips.push(GrowingTip::new("moisture", action, &detail, severity));
                }
            }
        }
    }

    // Consecutive dry days
    if let Some(ref comp) = moisture.dry_days_comparison {
        let fit = comparison_to_fitlevel_with_min_abs(comp, MIN_ABS_DRY_DAYS, 0);
        if fit != FitLevel::Optimal && comp.fit == EnvelopeFit::AboveRange {
            let severity = fitlevel_to_severity(fit);
            let extra = (comp.local_value - comp.q95).round() as i32;
            let (concern, action, detail) = match fit {
                FitLevel::Outside => (
                    Some("Extended drought periods"),
                    "Mulch heavily, deep watering",
                    format!("Dry spells {} days longer; drought stress", extra),
                ),
                FitLevel::Marginal => (
                    Some("Longer dry spells"),
                    "Water during dry spells",
                    format!("Dry spells {} days longer", extra),
                ),
                _ => (None, "Water during dry spells", format!("Dry spells {} days longer", extra)),
            };
            if let Some(c) = concern {
                tips.push(GrowingTip::with_concern("moisture", c, action, &detail, severity));
            } else {
                tips.push(GrowingTip::new("moisture", action, &detail, severity));
            }
        }
    }

    // Consecutive wet days
    if let Some(ref comp) = moisture.wet_days_comparison {
        let fit = comparison_to_fitlevel_with_min_abs(comp, MIN_ABS_WET_DAYS, 0);
        if fit != FitLevel::Optimal && comp.fit == EnvelopeFit::AboveRange {
            let severity = fitlevel_to_severity(fit);
            let extra = (comp.local_value - comp.q95).round() as i32;
            let (concern, action, detail) = match fit {
                FitLevel::Outside => (
                    Some("Prolonged wet conditions"),
                    "Crown rot risk, improve drainage",
                    format!("Wet spells {} days longer; keep crown dry", extra),
                ),
                FitLevel::Marginal => (
                    Some("Longer wet spells"),
                    "Avoid waterlogging",
                    format!("Wet spells {} days longer", extra),
                ),
                _ => (None, "Avoid waterlogging", format!("Wet spells {} days longer", extra)),
            };
            if let Some(c) = concern {
                tips.push(GrowingTip::with_concern("moisture", c, action, &detail, severity));
            } else {
                tips.push(GrowingTip::new("moisture", action, &detail, severity));
            }
        }
    }

    tips
}

fn generate_soil_tips(soil: &SoilSuitability, texture: &TextureSuitability) -> Vec<GrowingTip> {
    let mut tips = Vec::new();

    // pH adjustment
    if let Some(ref comp) = soil.ph_comparison {
        let fit = comparison_to_fitlevel_with_min_abs(comp, MIN_ABS_PH, 1);
        if fit != FitLevel::Optimal {
            let severity = fitlevel_to_severity(fit);

            if comp.fit == EnvelopeFit::BelowRange {
                let diff = comp.q05 - comp.local_value;
                let (concern, action, detail) = match fit {
                    FitLevel::Outside => (
                        Some("Soil too acidic"),
                        "Lime soil to raise pH",
                        format!("Soil {:.1} pH units too acidic", diff),
                    ),
                    FitLevel::Marginal => (
                        Some("Soil more acidic than typical"),
                        "Add lime",
                        format!("Soil {:.1} pH units below typical", diff),
                    ),
                    _ => (None, "Add lime (minor adjustment)", format!("Soil {:.1} pH units below typical", diff)),
                };
                if let Some(c) = concern {
                    tips.push(GrowingTip::with_concern("soil", c, action, &detail, severity));
                } else {
                    tips.push(GrowingTip::new("soil", action, &detail, severity));
                }
            } else if comp.fit == EnvelopeFit::AboveRange {
                let diff = comp.local_value - comp.q95;
                let (concern, action, detail) = match fit {
                    FitLevel::Outside => (
                        Some("Soil too alkaline"),
                        "Add sulfur or ericaceous compost",
                        format!("Soil {:.1} pH units too alkaline", diff),
                    ),
                    FitLevel::Marginal => (
                        Some("Soil more alkaline than typical"),
                        "Acidify soil",
                        format!("Soil {:.1} pH units above typical", diff),
                    ),
                    _ => (None, "Acidify slightly", format!("Soil {:.1} pH units above typical", diff)),
                };
                if let Some(c) = concern {
                    tips.push(GrowingTip::with_concern("soil", c, action, &detail, severity));
                } else {
                    tips.push(GrowingTip::new("soil", action, &detail, severity));
                }
            }
        }
    }

    // Fertility (CEC)
    if let Some(ref comp) = soil.cec_comparison {
        let fit = comparison_to_fitlevel_with_min_abs(comp, MIN_ABS_CEC, 0);
        if fit != FitLevel::Optimal && comp.fit == EnvelopeFit::BelowRange {
            let severity = fitlevel_to_severity(fit);
            let deficit = (comp.q05 - comp.local_value).round() as i32;
            let detail = format!("Fertility {} CEC below typical", deficit);
            let (concern, action) = match fit {
                FitLevel::Outside => (Some("Low soil fertility"), "Feed fortnightly in growing season"),
                FitLevel::Marginal => (Some("Lower fertility than typical"), "Feed fortnightly in growing season"),
                _ => (None, "Feed fortnightly in growing season"),
            };
            if let Some(c) = concern {
                tips.push(GrowingTip::with_concern("soil", c, action, &detail, severity));
            } else {
                tips.push(GrowingTip::new("soil", action, &detail, severity));
            }
        }
    }

    // Texture mismatch - use texture compatibility to determine FitLevel equivalent
    if texture.compatibility == TextureCompatibility::Poor {
        if let (Some(ref local), Some(ref plant)) = (&texture.local_texture, &texture.plant_texture) {
            let local_group = texture_group(&local.class_name);
            let plant_group = texture_group(&plant.class_name);

            if local_group == TextureGroup::Clay && plant_group == TextureGroup::Sandy {
                tips.push(GrowingTip::with_concern(
                    "soil",
                    "Soil texture incompatible",
                    "Add grit for drainage",
                    &format!("Heavy {} soil; plant prefers {}", local.class_name, plant.class_name),
                    "critical",
                ));
            } else if local_group == TextureGroup::Sandy && plant_group == TextureGroup::Clay {
                tips.push(GrowingTip::with_concern(
                    "soil",
                    "Soil texture incompatible",
                    "Add organic matter",
                    &format!("Light {} soil; plant prefers {}", local.class_name, plant.class_name),
                    "critical",
                ));
            }
        }
    } else if texture.compatibility == TextureCompatibility::Marginal {
        if let (Some(ref local), Some(ref plant)) = (&texture.local_texture, &texture.plant_texture) {
            tips.push(GrowingTip::with_concern(
                "soil",
                "Soil texture mismatch",
                "Amend soil texture",
                &format!("{} soil; plant prefers {}", local.class_name, plant.class_name),
                "warning",
            ));
        }
    }

    tips
}
