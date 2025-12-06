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

/// Generate structured growing tips based on comparison data
pub fn generate_growing_tips(assessment: &SuitabilityAssessment) -> Vec<GrowingTip> {
    let mut tips = Vec::new();

    // Temperature tips
    tips.extend(generate_temperature_tips(&assessment.temperature));

    // Moisture tips
    tips.extend(generate_moisture_tips(&assessment.moisture));

    // Soil tips
    tips.extend(generate_soil_tips(&assessment.soil, &assessment.texture));

    tips
}

fn generate_temperature_tips(temp: &TemperatureSuitability) -> Vec<GrowingTip> {
    let mut tips = Vec::new();

    // Frost days - too cold
    if let Some(ref comp) = temp.frost_comparison {
        let annual_local = dekadal_to_annual(comp.local_value);
        let annual_q95 = dekadal_to_annual(comp.q95);
        let annual_q05 = dekadal_to_annual(comp.q05);

        if comp.fit == EnvelopeFit::AboveRange {
            let extra_frost = (annual_local - annual_q95).round() as i32;
            if extra_frost > 50 {
                tips.push(GrowingTip::new(
                    "temperature",
                    "Overwinter indoors",
                    &format!("{} more frost days than typical; grow in containers", extra_frost),
                    "critical",
                ));
            } else if extra_frost > 20 {
                tips.push(GrowingTip::new(
                    "temperature",
                    "Protect in winter",
                    &format!("{} more frost days; use fleece or cold frame", extra_frost),
                    "warning",
                ));
            } else if extra_frost > 5 {
                tips.push(GrowingTip::new(
                    "temperature",
                    "Fleece in cold snaps",
                    &format!("{} more frost days than typical range", extra_frost),
                    "info",
                ));
            }
        } else if comp.fit == EnvelopeFit::BelowRange {
            let fewer_frost = (annual_q05 - annual_local).round() as i32;
            if fewer_frost > 60 {
                tips.push(GrowingTip::new(
                    "temperature",
                    "Provide artificial chill",
                    &format!("{} fewer frost days; may need refrigerated dormancy", fewer_frost),
                    "warning",
                ));
            }
        }
    }

    // Tropical nights - heat stress
    if let Some(ref comp) = temp.tropical_nights_comparison {
        let annual_local = dekadal_to_annual(comp.local_value);
        let annual_q95 = dekadal_to_annual(comp.q95);

        if comp.fit == EnvelopeFit::AboveRange {
            let extra_nights = (annual_local - annual_q95).round() as i32;
            if extra_nights > 100 {
                tips.push(GrowingTip::new(
                    "temperature",
                    "Heat stress likely",
                    &format!("{} more warm nights; plant may not thrive", extra_nights),
                    "critical",
                ));
            } else if extra_nights > 30 {
                tips.push(GrowingTip::new(
                    "temperature",
                    "Provide afternoon shade",
                    &format!("{} more warm nights; cool roots with mulch", extra_nights),
                    "warning",
                ));
            }
        }
    }

    // Growing season - too short
    if let Some(ref comp) = temp.growing_season_comparison {
        if comp.fit == EnvelopeFit::BelowRange {
            let fewer_days = (comp.q05 - comp.local_value).round() as i32;
            if fewer_days > 40 {
                tips.push(GrowingTip::new(
                    "temperature",
                    "Start early under cover",
                    &format!("{} fewer growing days; extend season with polytunnel", fewer_days),
                    "warning",
                ));
            } else if fewer_days > 15 {
                tips.push(GrowingTip::new(
                    "temperature",
                    "Start seeds indoors",
                    &format!("{} fewer growing days than typical", fewer_days),
                    "info",
                ));
            }
        } else if comp.fit == EnvelopeFit::AboveRange {
            let extra_days = (comp.local_value - comp.q95).round() as i32;
            if extra_days > 60 {
                tips.push(GrowingTip::new(
                    "temperature",
                    "May lack dormancy cues",
                    &format!("{} extra growing days; year-round growth possible", extra_days),
                    "info",
                ));
            }
        }
    }

    tips
}

fn generate_moisture_tips(moisture: &MoistureSuitability) -> Vec<GrowingTip> {
    let mut tips = Vec::new();

    // Annual rainfall
    if let Some(ref comp) = moisture.rainfall_comparison {
        if comp.fit == EnvelopeFit::BelowRange {
            let deficit = (comp.q05 - comp.local_value).round() as i32;
            let ratio = comp.local_value / comp.q05.max(1.0);

            if ratio < 0.5 {
                tips.push(GrowingTip::new(
                    "moisture",
                    "Drip irrigation or daily watering required",
                    &format!("{}mm less rainfall; half of minimum needed", deficit),
                    "critical",
                ));
            } else if ratio < 0.8 {
                tips.push(GrowingTip::new(
                    "moisture",
                    "Water weekly in growing season",
                    &format!("{}mm less annual rainfall than typical", deficit),
                    "warning",
                ));
            }
        } else if comp.fit == EnvelopeFit::AboveRange {
            let excess = (comp.local_value - comp.q95).round() as i32;
            let ratio = comp.local_value / comp.q95.max(1.0);

            if ratio > 2.0 {
                tips.push(GrowingTip::new(
                    "moisture",
                    "Raised bed with grit essential",
                    &format!("{}mm more rainfall; twice the maximum typical", excess),
                    "critical",
                ));
            } else if ratio > 1.3 {
                tips.push(GrowingTip::new(
                    "moisture",
                    "Ensure excellent drainage",
                    &format!("{}mm more annual rainfall than typical", excess),
                    "warning",
                ));
            }
        }
    }

    // Consecutive dry days - drought stress
    if let Some(ref comp) = moisture.dry_days_comparison {
        if comp.fit == EnvelopeFit::AboveRange {
            let extra_days = (comp.local_value - comp.q95).round() as i32;
            if extra_days > 14 {
                tips.push(GrowingTip::new(
                    "moisture",
                    "Mulch heavily, deep watering",
                    &format!("Dry spells {} days longer than typical", extra_days),
                    "warning",
                ));
            } else if extra_days > 5 {
                tips.push(GrowingTip::new(
                    "moisture",
                    "Water during dry spells",
                    &format!("Dry periods {} days longer than typical", extra_days),
                    "info",
                ));
            }
        }
    }

    // Consecutive wet days - waterlogging risk
    if let Some(ref comp) = moisture.wet_days_comparison {
        if comp.fit == EnvelopeFit::AboveRange {
            let extra_days = (comp.local_value - comp.q95).round() as i32;
            if extra_days > 10 {
                tips.push(GrowingTip::new(
                    "moisture",
                    "Crown rot risk, improve drainage",
                    &format!("Wet spells {} days longer; keep crown dry", extra_days),
                    "warning",
                ));
            } else if extra_days > 3 {
                tips.push(GrowingTip::new(
                    "moisture",
                    "Avoid waterlogging",
                    &format!("Wet periods {} days longer than typical", extra_days),
                    "info",
                ));
            }
        }
    }

    tips
}

fn generate_soil_tips(soil: &SoilSuitability, texture: &TextureSuitability) -> Vec<GrowingTip> {
    let mut tips = Vec::new();

    // pH adjustment
    if let Some(ref comp) = soil.ph_comparison {
        if comp.fit == EnvelopeFit::BelowRange {
            let diff = comp.q05 - comp.local_value;
            if diff > 0.5 {
                tips.push(GrowingTip::new(
                    "soil",
                    "Lime soil to raise pH",
                    &format!("Soil {:.1} pH units too acidic", diff),
                    "warning",
                ));
            } else if diff > 0.2 {
                tips.push(GrowingTip::new(
                    "soil",
                    "Add lime (minor adjustment)",
                    &format!("Soil {:.1} pH units below typical range", diff),
                    "info",
                ));
            }
        } else if comp.fit == EnvelopeFit::AboveRange {
            let diff = (comp.local_value - comp.q95).abs();
            if diff > 0.5 {
                tips.push(GrowingTip::new(
                    "soil",
                    "Add sulfur or ericaceous compost",
                    &format!("Soil {:.1} pH units too alkaline", diff),
                    "warning",
                ));
            } else if diff > 0.2 {
                tips.push(GrowingTip::new(
                    "soil",
                    "Acidify slightly",
                    &format!("Soil {:.1} pH units above typical range", diff),
                    "info",
                ));
            }
        }
    }

    // Fertility
    if let Some(ref comp) = soil.cec_comparison {
        if comp.fit == EnvelopeFit::BelowRange {
            let deficit = (comp.q05 - comp.local_value).round() as i32;
            tips.push(GrowingTip::new(
                "soil",
                "Feed fortnightly in growing season",
                &format!("Fertility {} CEC below typical range", deficit),
                if deficit > 15 { "warning" } else { "info" },
            ));
        }
    }

    // Texture mismatch
    if texture.compatibility == TextureCompatibility::Poor {
        if let (Some(ref local), Some(ref plant)) = (&texture.local_texture, &texture.plant_texture) {
            let local_group = texture_group(&local.class_name);
            let plant_group = texture_group(&plant.class_name);

            if local_group == TextureGroup::Clay && plant_group == TextureGroup::Sandy {
                tips.push(GrowingTip::new(
                    "soil",
                    "Add grit for drainage",
                    &format!("Heavy {} soil; plant prefers {}", local.class_name, plant.class_name),
                    "warning",
                ));
            } else if local_group == TextureGroup::Sandy && plant_group == TextureGroup::Clay {
                tips.push(GrowingTip::new(
                    "soil",
                    "Add organic matter",
                    &format!("Light {} soil; plant prefers {}", local.class_name, plant.class_name),
                    "warning",
                ));
            }
        }
    } else if texture.compatibility == TextureCompatibility::Marginal {
        if let (Some(ref local), Some(ref plant)) = (&texture.local_texture, &texture.plant_texture) {
            tips.push(GrowingTip::new(
                "soil",
                "Amend soil texture",
                &format!("{} soil; plant typically found in {}", local.class_name, plant.class_name),
                "info",
            ));
        }
    }

    tips
}
