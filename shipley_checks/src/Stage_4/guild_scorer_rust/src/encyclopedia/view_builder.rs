//! View Builder - Converts plant data to view models
//!
//! Transforms raw HashMap<String, Value> plant data into structured
//! view model types for Askama template rendering.

use std::collections::HashMap;
use serde_json::Value;

use crate::encyclopedia::types::{
    get_str, get_f64,
    OrganismProfile, FungalCounts, RankedPathogen, BeneficialFungi,
};
use crate::encyclopedia::sections::s1_identity::RelatedSpecies;
use crate::encyclopedia::suitability::local_conditions::LocalConditions;
use crate::encyclopedia::suitability::advice::build_assessment;
use crate::encyclopedia::suitability::comparator::EnvelopeFit;
use crate::encyclopedia::suitability::assessment::{
    SuitabilityAssessment, TemperatureSuitability, MoistureSuitability, SoilSuitability,
};
use crate::encyclopedia::view_models::*;

/// Build complete encyclopedia page data from raw plant data
pub fn build_encyclopedia_data(
    wfo_id: &str,
    plant_data: &HashMap<String, Value>,
    organism_profile: Option<&OrganismProfile>,
    fungal_counts: Option<&FungalCounts>,
    ranked_pathogens: Option<&[RankedPathogen]>,
    beneficial_fungi: Option<&BeneficialFungi>,
    related_species: Option<&[RelatedSpecies]>,
    genus_species_count: usize,
    local_conditions: Option<&LocalConditions>,
) -> EncyclopediaPageData {
    let location = local_conditions.map(|l| LocationInfo {
        name: l.name.clone(),
        code: location_name_to_code(&l.name),
        climate_zone: l.koppen_zone.clone(),
    }).unwrap_or_else(|| LocationInfo {
        name: "London, UK".to_string(),
        code: "london".to_string(),
        climate_zone: "Cfb".to_string(),
    });

    EncyclopediaPageData {
        identity: build_identity_card(wfo_id, plant_data, related_species, genus_species_count),
        requirements: build_requirements(plant_data, local_conditions),
        maintenance: build_maintenance(plant_data),
        services: build_services(plant_data),
        interactions: build_interactions(plant_data, organism_profile, fungal_counts, ranked_pathogens, beneficial_fungi),
        companion: build_companion(plant_data, organism_profile, fungal_counts),
        location,
    }
}

// ============================================================================
// S1: Identity Card Builder
// ============================================================================

fn build_identity_card(
    wfo_id: &str,
    data: &HashMap<String, Value>,
    relatives: Option<&[RelatedSpecies]>,
    genus_count: usize,
) -> IdentityCard {
    let scientific_name = get_str(data, "wfo_scientific_name")
        .unwrap_or("Unknown species")
        .to_string();

    let common_names = get_str(data, "vernacular_name_en")
        .map(|s| s.split(';').map(|n| n.trim().to_string()).collect())
        .unwrap_or_default();

    let chinese_names = get_str(data, "vernacular_name_zh")
        .filter(|s| !s.is_empty() && *s != "NA")
        .map(|s| s.to_string());

    let family = get_str(data, "family").unwrap_or("Unknown").to_string();
    let genus = get_str(data, "genus").unwrap_or("Unknown").to_string();

    let growth_form = get_str(data, "try_growth_form");
    let (growth_type, growth_icon) = classify_growth(growth_form, data);

    let native_climate = get_str(data, "top_zone_code")
        .filter(|s| !s.is_empty() && *s != "NA")
        .map(|k| interpret_koppen(k));

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

    let relatives_vec = relatives.map(|r| {
        r.iter().take(5).map(|rel| RelativeSpecies {
            wfo_id: rel.wfo_id.clone(),
            scientific_name: rel.scientific_name.clone(),
            common_name: rel.common_name.clone(),
            relatedness: classify_relatedness(rel.distance),
        }).collect()
    }).unwrap_or_default();

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
        relatives: relatives_vec,
        genus_species_count: genus_count,
    }
}

fn classify_growth(growth_form: Option<&str>, data: &HashMap<String, Value>) -> (String, GrowthIcon) {
    let height = get_f64(data, "height_m");
    let woodiness = get_str(data, "try_woodiness");
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
        format!("{:.0}m — Large tree, needs significant space", h)
    } else if h > 10.0 {
        format!("{:.0}m — Medium tree", h)
    } else if h > 5.0 {
        format!("{:.0}m — Small tree / large shrub", h)
    } else if h > 2.0 {
        format!("{:.1}m — Medium shrub", h)
    } else if h > 0.5 {
        format!("{:.1}m — Small shrub / tall herb", h)
    } else {
        format!("{:.0}cm — Ground cover", h * 100.0)
    }
}

fn describe_leaf_size(la_mm2: f64) -> String {
    let la_cm2 = la_mm2 / 100.0;
    if la_cm2 > 100.0 {
        "Very large leaves".to_string()
    } else if la_cm2 > 30.0 {
        "Large leaves".to_string()
    } else if la_cm2 > 10.0 {
        "Medium-sized leaves".to_string()
    } else if la_cm2 > 2.0 {
        "Small leaves".to_string()
    } else {
        "Very small leaves / needles".to_string()
    }
}

fn describe_seed_size(mass_mg: f64) -> String {
    if mass_mg > 10000.0 {
        "Very large seeds / nuts".to_string()
    } else if mass_mg > 1000.0 {
        "Large seeds".to_string()
    } else if mass_mg > 100.0 {
        "Medium seeds".to_string()
    } else if mass_mg > 10.0 {
        "Small seeds".to_string()
    } else {
        "Tiny seeds".to_string()
    }
}

fn classify_relatedness(distance: f64) -> String {
    if distance < 50.0 {
        "Close".to_string()
    } else if distance < 150.0 {
        "Moderate".to_string()
    } else {
        "Distant".to_string()
    }
}

fn interpret_koppen(code: &str) -> String {
    match code.chars().next() {
        Some('A') => "Tropical (warm year-round)".to_string(),
        Some('B') => "Arid / Semi-arid".to_string(),
        Some('C') => "Temperate (mild winters)".to_string(),
        Some('D') => "Continental (cold winters)".to_string(),
        Some('E') => "Polar / Alpine".to_string(),
        _ => format!("Climate zone: {}", code),
    }
}

// ============================================================================
// S2: Requirements Builder
// ============================================================================

fn build_requirements(
    data: &HashMap<String, Value>,
    local: Option<&LocalConditions>,
) -> RequirementsSection {
    let assessment = local.map(|l| build_assessment(l, data, ""));

    RequirementsSection {
        light: build_light_requirement(data),
        temperature: build_temperature_section(data, local, assessment.as_ref()),
        moisture: build_moisture_section(data, local, assessment.as_ref()),
        soil: build_soil_section(data, local, assessment.as_ref()),
        overall_suitability: assessment.as_ref().map(|a| build_overall_suitability(local.unwrap(), a)),
    }
}

fn build_light_requirement(data: &HashMap<String, Value>) -> LightRequirement {
    let eive_l = get_f64(data, "EIVEres-L");

    let (category, description, fill) = match eive_l {
        Some(l) if l >= 8.0 => ("Full sun", "Needs 6+ hours direct sunlight", 100),
        Some(l) if l >= 6.0 => ("Sun to partial shade", "Prefers sun, tolerates some shade", 75),
        Some(l) if l >= 4.0 => ("Partial shade", "Dappled light or morning sun", 50),
        Some(l) if l >= 2.0 => ("Shade tolerant", "Thrives in low light", 25),
        Some(_) => ("Deep shade", "Adapted to forest floor conditions", 10),
        None => ("Unknown", "Light requirements not documented", 50),
    };

    LightRequirement {
        eive_l,
        category: category.to_string(),
        description: description.to_string(),
        icon_fill_percent: fill,
    }
}

fn build_temperature_section(
    data: &HashMap<String, Value>,
    local: Option<&LocalConditions>,
    assessment: Option<&crate::encyclopedia::suitability::assessment::SuitabilityAssessment>,
) -> TemperatureSection {
    let mut details = Vec::new();

    // Build summary from plant data
    if let Some(bio5) = get_f64(data, "wc2.1_30s_bio_5_q50") {
        if let Some(bio6) = get_f64(data, "wc2.1_30s_bio_6_q50") {
            details.push(format!("Temperature range: {:.0}°C to {:.0}°C", bio6, bio5));
        }
    }

    if let Some(fd) = get_f64(data, "FD_q50") {
        let annual = fd * 36.0;
        details.push(format!("Frost days: ~{:.0}/year", annual));
    }

    if let Some(gsl) = get_f64(data, "GSL_q50") {
        details.push(format!("Growing season: ~{:.0} days", gsl));
    }

    // Build comparison rows if we have local data
    let comparisons = if let (Some(_loc), Some(assess)) = (local, assessment) {
        build_temperature_comparisons(&assess.temperature)
    } else {
        Vec::new()
    };

    TemperatureSection {
        summary: details.first().cloned().unwrap_or_else(|| "Temperature data not available".to_string()),
        details,
        comparisons,
    }
}

fn build_temperature_comparisons(
    temp: &TemperatureSuitability,
) -> Vec<ComparisonRow> {
    let mut rows = Vec::new();

    if let Some(ref comp) = temp.frost_comparison {
        rows.push(ComparisonRow {
            parameter: "Frost days/year".to_string(),
            local_value: format!("{:.0}", comp.local_value * 36.0),
            plant_range: format!("{:.0}–{:.0}", comp.q05 * 36.0, comp.q95 * 36.0),
            fit: convert_fit(comp.fit),
        });
    }

    if let Some(ref comp) = temp.tropical_nights_comparison {
        rows.push(ComparisonRow {
            parameter: "Warm nights (>20°C)".to_string(),
            local_value: format!("{:.0}", comp.local_value * 36.0),
            plant_range: format!("{:.0}–{:.0}", comp.q05 * 36.0, comp.q95 * 36.0),
            fit: convert_fit(comp.fit),
        });
    }

    if let Some(ref comp) = temp.growing_season_comparison {
        rows.push(ComparisonRow {
            parameter: "Growing season (days)".to_string(),
            local_value: format!("{:.0}", comp.local_value),
            plant_range: format!("{:.0}–{:.0}", comp.q05, comp.q95),
            fit: convert_fit(comp.fit),
        });
    }

    rows
}

fn build_moisture_section(
    data: &HashMap<String, Value>,
    local: Option<&LocalConditions>,
    assessment: Option<&crate::encyclopedia::suitability::assessment::SuitabilityAssessment>,
) -> MoistureSection {
    let rainfall = get_f64(data, "wc2.1_30s_bio_12_q50").map(|r| {
        let min = get_f64(data, "wc2.1_30s_bio_12_q05").unwrap_or(r * 0.8);
        let max = get_f64(data, "wc2.1_30s_bio_12_q95").unwrap_or(r * 1.2);
        RangeValue { typical: r, min, max, unit: "mm/year".to_string() }
    });

    let summary = rainfall.as_ref()
        .map(|r| format!("Rainfall: {:.0}mm/year (range: {:.0}–{:.0}mm)", r.typical, r.min, r.max))
        .unwrap_or_else(|| "Moisture requirements not documented".to_string());

    let comparisons = if let (Some(_loc), Some(assess)) = (local, assessment) {
        build_moisture_comparisons(&assess.moisture)
    } else {
        Vec::new()
    };

    let advice = assessment.as_ref()
        .map(|a| a.moisture.recommendations.clone())
        .unwrap_or_default();

    MoistureSection {
        summary,
        rainfall_mm: rainfall,
        dry_spell_days: None,
        wet_spell_days: None,
        comparisons,
        advice,
    }
}

fn build_moisture_comparisons(
    moisture: &MoistureSuitability,
) -> Vec<ComparisonRow> {
    let mut rows = Vec::new();

    if let Some(ref comp) = moisture.rainfall_comparison {
        rows.push(ComparisonRow {
            parameter: "Annual rainfall (mm)".to_string(),
            local_value: format!("{:.0}", comp.local_value),
            plant_range: format!("{:.0}–{:.0}", comp.q05, comp.q95),
            fit: convert_fit(comp.fit),
        });
    }

    if let Some(ref comp) = moisture.dry_days_comparison {
        rows.push(ComparisonRow {
            parameter: "Max dry spell (days)".to_string(),
            local_value: format!("{:.0}", comp.local_value),
            plant_range: format!("{:.0}–{:.0}", comp.q05, comp.q95),
            fit: convert_fit(comp.fit),
        });
    }

    if let Some(ref comp) = moisture.wet_days_comparison {
        rows.push(ComparisonRow {
            parameter: "Max wet spell (days)".to_string(),
            local_value: format!("{:.0}", comp.local_value),
            plant_range: format!("{:.0}–{:.0}", comp.q05, comp.q95),
            fit: convert_fit(comp.fit),
        });
    }

    rows
}

fn build_soil_section(
    data: &HashMap<String, Value>,
    local: Option<&LocalConditions>,
    assessment: Option<&crate::encyclopedia::suitability::assessment::SuitabilityAssessment>,
) -> SoilSection {
    let ph = get_f64(data, "phh2o_0_5cm_q50").map(|p| {
        let min = get_f64(data, "phh2o_0_5cm_q05").unwrap_or(p - 0.5);
        let max = get_f64(data, "phh2o_0_5cm_q95").unwrap_or(p + 0.5);
        SoilParameter {
            value: p,
            range: format!("{:.1}–{:.1}", min, max),
            interpretation: interpret_ph(p),
        }
    });

    let texture_summary = describe_soil_texture(data);

    let comparisons = if let (Some(_loc), Some(assess)) = (local, assessment) {
        build_soil_comparisons(&assess.soil)
    } else {
        Vec::new()
    };

    let advice = assessment.as_ref()
        .map(|a| a.soil.amendments.clone())
        .unwrap_or_default();

    SoilSection {
        texture_summary,
        ph,
        fertility: None,
        organic_carbon: None,
        comparisons,
        advice,
    }
}

fn build_soil_comparisons(
    soil: &SoilSuitability,
) -> Vec<ComparisonRow> {
    let mut rows = Vec::new();

    if let Some(ref comp) = soil.ph_comparison {
        rows.push(ComparisonRow {
            parameter: "Soil pH".to_string(),
            local_value: format!("{:.1}", comp.local_value),
            plant_range: format!("{:.1}–{:.1}", comp.q05, comp.q95),
            fit: convert_fit(comp.fit),
        });
    }

    rows
}

fn interpret_ph(ph: f64) -> String {
    if ph < 5.5 {
        "Strongly acidic".to_string()
    } else if ph < 6.5 {
        "Slightly acidic".to_string()
    } else if ph < 7.5 {
        "Neutral".to_string()
    } else if ph < 8.5 {
        "Slightly alkaline".to_string()
    } else {
        "Strongly alkaline".to_string()
    }
}

fn describe_soil_texture(data: &HashMap<String, Value>) -> String {
    let clay = get_f64(data, "clay_0_5cm_q50");
    let sand = get_f64(data, "sand_0_5cm_q50");

    match (clay, sand) {
        (Some(c), Some(s)) if c > 40.0 => "Clay soil preference".to_string(),
        (Some(c), Some(s)) if s > 60.0 => "Sandy soil preference".to_string(),
        (Some(c), Some(s)) if c > 25.0 && c < 40.0 => "Loamy soil preference".to_string(),
        _ => "Adaptable to various soil types".to_string(),
    }
}

fn build_overall_suitability(
    local: &LocalConditions,
    assess: &SuitabilityAssessment,
) -> OverallSuitability {
    // Calculate overall score
    let mut fit_scores: Vec<u8> = Vec::new();

    // Collect all comparison fits
    if let Some(ref comp) = assess.temperature.frost_comparison {
        fit_scores.push(fit_to_score(comp.fit));
    }
    if let Some(ref comp) = assess.moisture.rainfall_comparison {
        fit_scores.push(fit_to_score(comp.fit));
    }
    if let Some(ref comp) = assess.soil.ph_comparison {
        fit_scores.push(fit_to_score(comp.fit));
    }

    let avg_score = if fit_scores.is_empty() {
        50
    } else {
        (fit_scores.iter().map(|&s| s as u32).sum::<u32>() / fit_scores.len() as u32) as u8
    };

    let verdict = if avg_score >= 80 {
        "Excellent match for your location"
    } else if avg_score >= 60 {
        "Good match with some considerations"
    } else if avg_score >= 40 {
        "Possible with extra care"
    } else {
        "Challenging for your climate"
    };

    // Collect concerns from issues and interventions
    let mut concerns: Vec<String> = Vec::new();
    concerns.extend(assess.temperature.issues.iter().cloned());
    concerns.extend(assess.moisture.issues.iter().cloned());

    OverallSuitability {
        location_name: local.name.clone(),
        score_percent: avg_score,
        verdict: verdict.to_string(),
        key_concerns: concerns.into_iter().take(3).collect(),
        key_advantages: Vec::new(),
    }
}

fn fit_to_score(fit: EnvelopeFit) -> u8 {
    match fit {
        EnvelopeFit::WithinRange => 80,
        EnvelopeFit::BelowRange | EnvelopeFit::AboveRange => 40,
    }
}

fn convert_fit(fit: EnvelopeFit) -> FitLevel {
    match fit {
        EnvelopeFit::WithinRange => FitLevel::Good,
        EnvelopeFit::BelowRange | EnvelopeFit::AboveRange => FitLevel::Marginal,
    }
}

fn location_name_to_code(name: &str) -> String {
    let lower = name.to_lowercase();
    if lower.contains("singapore") {
        "singapore".to_string()
    } else if lower.contains("helsinki") {
        "helsinki".to_string()
    } else {
        "london".to_string()
    }
}

// ============================================================================
// S3: Maintenance Builder
// ============================================================================

fn build_maintenance(data: &HashMap<String, Value>) -> MaintenanceSection {
    let (c, s, r) = get_csr_values(data);
    let (level, dominant, description) = classify_maintenance(c, s, r);

    MaintenanceSection {
        level,
        csr_strategy: CsrStrategy {
            c_percent: c,
            s_percent: s,
            r_percent: r,
            dominant,
            description,
        },
        tasks: build_maintenance_tasks(level),
        seasonal_notes: Vec::new(),
    }
}

fn get_csr_values(data: &HashMap<String, Value>) -> (f64, f64, f64) {
    let c = get_f64(data, "CSR_C_pct").unwrap_or(33.3);
    let s = get_f64(data, "CSR_S_pct").unwrap_or(33.3);
    let r = get_f64(data, "CSR_R_pct").unwrap_or(33.3);
    (c, s, r)
}

fn classify_maintenance(c: f64, s: f64, r: f64) -> (MaintenanceLevel, String, String) {
    if s > 50.0 {
        (MaintenanceLevel::Low, "Stress-tolerator".to_string(),
         "Adapted to harsh conditions, requires minimal intervention".to_string())
    } else if c > 50.0 {
        (MaintenanceLevel::Medium, "Competitor".to_string(),
         "Vigorous grower, may need management to prevent dominance".to_string())
    } else if r > 50.0 {
        (MaintenanceLevel::High, "Ruderal".to_string(),
         "Fast-growing opportunist, needs regular management".to_string())
    } else {
        (MaintenanceLevel::LowMedium, "Balanced".to_string(),
         "Moderate growth strategy, adaptable maintenance needs".to_string())
    }
}

fn build_maintenance_tasks(level: MaintenanceLevel) -> Vec<MaintenanceTask> {
    match level {
        MaintenanceLevel::Low => vec![
            MaintenanceTask {
                name: "Annual health check".to_string(),
                frequency: "Once per year".to_string(),
                importance: "Recommended".to_string(),
            },
        ],
        MaintenanceLevel::Medium => vec![
            MaintenanceTask {
                name: "Pruning".to_string(),
                frequency: "1-2 times per year".to_string(),
                importance: "Recommended".to_string(),
            },
            MaintenanceTask {
                name: "Mulching".to_string(),
                frequency: "Annually".to_string(),
                importance: "Optional".to_string(),
            },
        ],
        MaintenanceLevel::High => vec![
            MaintenanceTask {
                name: "Regular pruning".to_string(),
                frequency: "3-4 times per year".to_string(),
                importance: "Essential".to_string(),
            },
            MaintenanceTask {
                name: "Weed management".to_string(),
                frequency: "Monthly during growing season".to_string(),
                importance: "Essential".to_string(),
            },
        ],
        _ => vec![
            MaintenanceTask {
                name: "General care".to_string(),
                frequency: "Seasonal".to_string(),
                importance: "Recommended".to_string(),
            },
        ],
    }
}

// ============================================================================
// S4: Services Builder
// ============================================================================

fn build_services(data: &HashMap<String, Value>) -> EcosystemServices {
    let mut services = Vec::new();

    // Pollination
    if let Some(poll) = get_f64(data, "ecoserv_pollination") {
        services.push(ServiceCard {
            name: "Pollination Support".to_string(),
            icon: ServiceIcon::Pollination,
            value: format!("{:.0}%", poll * 100.0),
            description: describe_pollination(poll),
            confidence: get_confidence(data, "ecoserv_pollination_conf"),
        });
    }

    // Carbon storage
    if let Some(carbon) = get_f64(data, "ecoserv_carbon") {
        services.push(ServiceCard {
            name: "Carbon Storage".to_string(),
            icon: ServiceIcon::CarbonStorage,
            value: format!("{:.0}%", carbon * 100.0),
            description: describe_carbon(carbon),
            confidence: get_confidence(data, "ecoserv_carbon_conf"),
        });
    }

    // Soil health
    if let Some(soil) = get_f64(data, "ecoserv_soil_health") {
        services.push(ServiceCard {
            name: "Soil Health".to_string(),
            icon: ServiceIcon::SoilHealth,
            value: format!("{:.0}%", soil * 100.0),
            description: "Improves soil structure and biology".to_string(),
            confidence: get_confidence(data, "ecoserv_soil_conf"),
        });
    }

    let nitrogen_fixer = get_str(data, "N_fixer")
        .map(|s| s.to_lowercase() == "yes" || s == "1")
        .unwrap_or(false);

    if nitrogen_fixer {
        services.push(ServiceCard {
            name: "Nitrogen Fixation".to_string(),
            icon: ServiceIcon::SoilHealth,
            value: "Yes".to_string(),
            description: "Fixes atmospheric nitrogen, enriching soil".to_string(),
            confidence: "High".to_string(),
        });
    }

    EcosystemServices {
        services,
        nitrogen_fixer,
        pollinator_score: get_f64(data, "ecoserv_pollination").map(|p| (p * 100.0) as u8),
        carbon_storage: get_f64(data, "ecoserv_carbon").map(|c| format!("{:.0}%", c * 100.0)),
    }
}

fn describe_pollination(score: f64) -> String {
    if score > 0.7 {
        "Major pollinator resource".to_string()
    } else if score > 0.4 {
        "Moderate pollinator support".to_string()
    } else {
        "Some pollinator value".to_string()
    }
}

fn describe_carbon(score: f64) -> String {
    if score > 0.7 {
        "High carbon sequestration potential".to_string()
    } else if score > 0.4 {
        "Moderate carbon storage".to_string()
    } else {
        "Some carbon storage".to_string()
    }
}

fn get_confidence(_data: &HashMap<String, Value>, _key: &str) -> String {
    "Medium".to_string() // Placeholder
}

// ============================================================================
// S5: Interactions Builder
// ============================================================================

fn build_interactions(
    data: &HashMap<String, Value>,
    organism_profile: Option<&OrganismProfile>,
    fungal_counts: Option<&FungalCounts>,
    ranked_pathogens: Option<&[RankedPathogen]>,
    beneficial_fungi: Option<&BeneficialFungi>,
) -> InteractionsSection {
    let pollinators = organism_profile.map(|p| {
        OrganismGroup {
            title: "Pollinators".to_string(),
            icon: "butterfly".to_string(),
            total_count: p.total_pollinators,
            categories: p.pollinators_by_category.iter().map(|c| OrganismCategory {
                name: c.category.clone(),
                organisms: c.organisms.clone(),
            }).collect(),
        }
    }).unwrap_or_else(|| OrganismGroup {
        title: "Pollinators".to_string(),
        icon: "butterfly".to_string(),
        total_count: 0,
        categories: Vec::new(),
    });

    let herbivores = organism_profile.map(|p| {
        OrganismGroup {
            title: "Herbivores & Pests".to_string(),
            icon: "bug".to_string(),
            total_count: p.total_herbivores,
            categories: p.herbivores_by_category.iter().map(|c| OrganismCategory {
                name: c.category.clone(),
                organisms: c.organisms.clone(),
            }).collect(),
        }
    }).unwrap_or_else(|| OrganismGroup {
        title: "Herbivores & Pests".to_string(),
        icon: "bug".to_string(),
        total_count: 0,
        categories: Vec::new(),
    });

    let diseases = DiseaseGroup {
        pathogens: ranked_pathogens.map(|rp| {
            rp.iter().take(5).map(|p| PathogenInfo {
                name: p.taxon.clone(),
                observation_count: p.observation_count,
                severity: if p.observation_count > 10 { "Common" } else { "Occasional" }.to_string(),
            }).collect()
        }).unwrap_or_default(),
        resistance_notes: Vec::new(),
    };

    let beneficial = beneficial_fungi.map(|bf| FungiGroup {
        mycoparasites: bf.mycoparasites.clone(),
        entomopathogens: bf.entomopathogens.clone(),
        endophytes_count: 0,
    }).unwrap_or_default();

    let mycorrhizal = if fungal_counts.map(|f| f.emf > 0).unwrap_or(false) {
        if fungal_counts.map(|f| f.amf > 0).unwrap_or(false) {
            "Dual (AMF + EMF)".to_string()
        } else {
            "Ectomycorrhizal (EMF)".to_string()
        }
    } else if fungal_counts.map(|f| f.amf > 0).unwrap_or(false) {
        "Arbuscular (AMF)".to_string()
    } else {
        "Not documented".to_string()
    };

    InteractionsSection {
        pollinators,
        herbivores,
        diseases,
        beneficial_fungi: beneficial,
        mycorrhizal_type: mycorrhizal,
    }
}

// ============================================================================
// S6: Companion Builder
// ============================================================================

fn build_companion(
    data: &HashMap<String, Value>,
    _organism_profile: Option<&OrganismProfile>,
    fungal_counts: Option<&FungalCounts>,
) -> CompanionSection {
    let mut roles = Vec::new();

    // N-fixer role
    let n_fixer = get_str(data, "N_fixer")
        .map(|s| s.to_lowercase() == "yes" || s == "1")
        .unwrap_or(false);
    if n_fixer {
        roles.push(GuildRole {
            role: "Nitrogen Fixer".to_string(),
            strength: "Strong".to_string(),
            explanation: "Provides nitrogen to neighboring plants through root nodules".to_string(),
        });
    }

    // Mycorrhizal networking
    if fungal_counts.map(|f| f.emf > 0 || f.amf > 0).unwrap_or(false) {
        roles.push(GuildRole {
            role: "Mycorrhizal Hub".to_string(),
            strength: "Moderate".to_string(),
            explanation: "Can share nutrients with compatible plants via fungal networks".to_string(),
        });
    }

    CompanionSection {
        guild_roles: roles,
        good_companions: Vec::new(),
        avoid_with: Vec::new(),
        planting_notes: Vec::new(),
    }
}
