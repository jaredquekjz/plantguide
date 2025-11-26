//! S4: Ecosystem Services
//!
//! Rules for generating the ecosystem services section using pre-calculated ratings.
//!
//! Data Sources (from Stage 3 pipeline):
//! - NPP, decomposition, nutrient dynamics: CSR-derived
//! - Carbon storage: Growth form and biomass derived
//! - Nitrogen fixation: TRY database family-level classification

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::*;
use crate::encyclopedia::utils::classify::*;

/// Generate the S4 Ecosystem Services section.
pub fn generate(data: &HashMap<String, Value>) -> String {
    let mut sections = Vec::new();
    sections.push("## Ecosystem Services".to_string());

    // Productivity
    sections.push(String::new());
    sections.push("### Productivity".to_string());
    sections.push(generate_productivity_section(data));

    // Nutrient Dynamics
    sections.push(String::new());
    sections.push("### Nutrient Dynamics".to_string());
    sections.push(generate_nutrient_section(data));

    // Carbon Storage
    sections.push(String::new());
    sections.push("### Carbon Storage".to_string());
    sections.push(generate_carbon_section(data));

    // Soil Services
    sections.push(String::new());
    sections.push("### Soil Services".to_string());
    sections.push(generate_soil_services_section(data));

    // Garden Value summary
    sections.push(String::new());
    sections.push(generate_garden_value_summary(data));

    sections.join("\n")
}

fn generate_productivity_section(data: &HashMap<String, Value>) -> String {
    let mut lines = Vec::new();

    // NPP (Net Primary Productivity)
    let npp = get_str(data, "npp_rating");
    let _npp_conf = get_str(data, "npp_confidence");
    lines.push(format!(
        "- **NPP**: {} - {}",
        format_rating(npp),
        npp_interpretation(npp)
    ));

    // Decomposition Rate
    let decomp = get_str(data, "decomposition_rating");
    lines.push(format!(
        "- **Decomposition**: {} - {}",
        format_rating(decomp),
        decomp_interpretation(decomp)
    ));

    lines.join("\n")
}

fn npp_interpretation(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") => "Very rapid growth",
        Some("High") => "Rapid growth",
        Some("Moderate") => "Moderate growth",
        Some("Low") => "Slow growth",
        Some("Very Low") => "Very slow growth",
        _ => "Unable to assess",
    }
}

fn decomp_interpretation(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") => "Very fast litter breakdown",
        Some("High") => "Fast breakdown",
        Some("Moderate") => "Moderate breakdown",
        Some("Low") => "Slow breakdown",
        Some("Very Low") => "Very slow breakdown (recalcitrant)",
        _ => "Unable to assess",
    }
}

fn generate_nutrient_section(data: &HashMap<String, Value>) -> String {
    let mut lines = Vec::new();

    // Nutrient Cycling
    let cycling = get_str(data, "nutrient_cycling_rating");
    lines.push(format!(
        "- **Nutrient Cycling**: {}",
        format_rating(cycling)
    ));

    // Nutrient Retention
    let retention = get_str(data, "nutrient_retention_rating");
    lines.push(format!(
        "- **Nutrient Retention**: {} - {}",
        format_rating(retention),
        retention_interpretation(retention)
    ));

    // Nutrient Loss
    let loss = get_str(data, "nutrient_loss_rating");
    lines.push(format!(
        "- **Nutrient Loss**: {} - {}",
        format_rating(loss),
        loss_interpretation(loss)
    ));

    lines.join("\n")
}

fn retention_interpretation(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") => "Excellent nutrient storage",
        Some("High") => "Good retention",
        Some("Moderate") => "Moderate retention",
        Some("Low") => "Limited retention",
        Some("Very Low") => "Poor retention (leaching risk)",
        _ => "",
    }
}

fn loss_interpretation(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") => "High loss potential",
        Some("High") => "Elevated loss",
        Some("Moderate") => "Moderate loss",
        Some("Low") => "Limited loss",
        Some("Very Low") => "Minimal loss",
        _ => "",
    }
}

fn generate_carbon_section(data: &HashMap<String, Value>) -> String {
    let mut lines = Vec::new();

    // Biomass Carbon
    let biomass = get_str(data, "carbon_biomass_rating");
    lines.push(format!(
        "- **Biomass Carbon**: {} - {}",
        format_rating(biomass),
        carbon_interpretation(biomass)
    ));

    // Recalcitrant Carbon
    let recalcitrant = get_str(data, "carbon_recalcitrant_rating");
    lines.push(format!(
        "- **Recalcitrant Carbon**: {} - {}",
        format_rating(recalcitrant),
        recalcitrant_interpretation(recalcitrant)
    ));

    // Total Carbon
    let total = get_str(data, "carbon_total_rating");
    lines.push(format!(
        "- **Total Carbon**: {}",
        format_rating(total)
    ));

    lines.join("\n")
}

fn carbon_interpretation(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") => "Major carbon store",
        Some("High") => "Significant living carbon",
        Some("Moderate") => "Moderate storage",
        Some("Low") => "Limited storage",
        Some("Very Low") => "Minimal storage",
        _ => "",
    }
}

fn recalcitrant_interpretation(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") => "Excellent long-term storage",
        Some("High") => "Good long-term storage",
        Some("Moderate") => "Some long-term storage",
        Some("Low") => "Limited persistence",
        Some("Very Low") => "Minimal persistence",
        _ => "",
    }
}

fn generate_soil_services_section(data: &HashMap<String, Value>) -> String {
    let mut lines = Vec::new();

    // Erosion Protection
    let erosion = get_str(data, "erosion_protection_rating");
    lines.push(format!(
        "- **Erosion Protection**: {} - {}",
        format_rating(erosion),
        erosion_interpretation(erosion)
    ));

    // Nitrogen Fixation
    let n_fix = get_str(data, "nitrogen_fixation_rating");
    let family = get_str(data, "family").unwrap_or("");
    let is_legume = family.eq_ignore_ascii_case("Fabaceae");

    lines.push(format!(
        "- **Nitrogen Fixation**: {}{}",
        format_rating(n_fix),
        if is_legume { " (Fabaceae - active N-fixer)" } else { "" }
    ));

    lines.join("\n")
}

fn erosion_interpretation(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") => "Excellent soil stabilisation",
        Some("High") => "Good stabilisation",
        Some("Moderate") => "Moderate protection",
        Some("Low") => "Limited protection",
        Some("Very Low") => "Poor protection",
        _ => "",
    }
}

fn generate_garden_value_summary(data: &HashMap<String, Value>) -> String {
    let mut highlights = Vec::new();

    // Check for notable ecosystem services
    let n_fix = get_str(data, "nitrogen_fixation_rating");
    if n_fix == Some("Very High") || n_fix == Some("High") {
        highlights.push("improves soil fertility through nitrogen fixation");
    }

    let carbon = get_str(data, "carbon_total_rating");
    if carbon == Some("Very High") || carbon == Some("High") {
        highlights.push("good carbon storage for climate-conscious planting");
    }

    let npp = get_str(data, "npp_rating");
    if npp == Some("Very High") || npp == Some("High") {
        highlights.push("fast-growing for quick establishment");
    }

    let erosion = get_str(data, "erosion_protection_rating");
    if erosion == Some("Very High") || erosion == Some("High") {
        highlights.push("excellent for slopes and erosion-prone areas");
    }

    if highlights.is_empty() {
        "**Garden Value**: Standard ecosystem contribution.".to_string()
    } else {
        format!("**Garden Value**: Good choice - {}.", highlights.join("; "))
    }
}
