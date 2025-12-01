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
    sections.push(String::new());
    sections.push("*How this plant contributes to garden health and environmental benefits. Ratings derived from functional traits and growth strategy (CSR scores).*".to_string());

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
    lines.push(format!(
        "**Net Primary Productivity**: {}",
        format_rating(npp)
    ));
    lines.push(format!("*{}*", npp_description(npp)));

    // Decomposition Rate
    let decomp = get_str(data, "decomposition_rating");
    lines.push(format!(
        "**Decomposition Rate**: {}",
        format_rating(decomp)
    ));
    lines.push(format!("*{}*", decomp_description(decomp)));

    lines.join("\n")
}

fn npp_description(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") | Some("High") =>
            "Rapid growth produces abundant biomass each year—more leaves, stems, and roots. Provides food for wildlife, improves air quality, and captures significant carbon from the atmosphere.",
        Some("Moderate") =>
            "Moderate growth rate. Steady biomass production for a balanced contribution to garden ecosystem.",
        Some("Low") | Some("Very Low") =>
            "Slow growth conserves resources. Less biomass production but often longer-lived and more stress-tolerant.",
        _ => "Unable to assess growth rate.",
    }
}

fn decomp_description(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") | Some("High") =>
            "Fast litter breakdown returns nutrients to soil quickly, keeping it fertile and reducing fertilizer needs. Supports active earthworms and soil microbes.",
        Some("Moderate") =>
            "Moderate breakdown rate. Nutrients recycle at a balanced pace.",
        Some("Low") | Some("Very Low") =>
            "Slow decomposition means leaf litter persists longer. Good for mulch and long-term carbon storage, but nutrients release slowly.",
        _ => "Unable to assess decomposition rate.",
    }
}

fn generate_nutrient_section(data: &HashMap<String, Value>) -> String {
    let mut lines = Vec::new();

    lines.push("*How efficiently nutrients move through your garden—from soil to plants to decomposers and back. Good cycling creates a self-sustaining system.*".to_string());
    lines.push(String::new());

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
        retention_description(retention)
    ));

    // Nutrient Loss
    let loss = get_str(data, "nutrient_loss_rating");
    lines.push(format!(
        "- **Nutrient Loss Risk**: {} - {}",
        format_rating(loss),
        loss_description(loss)
    ));

    lines.join("\n")
}

fn retention_description(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") | Some("High") =>
            "holds nutrients well; reduces fertilizer needs",
        Some("Moderate") =>
            "moderate retention",
        Some("Low") | Some("Very Low") =>
            "nutrients may leach away; more frequent feeding needed",
        _ => "",
    }
}

fn loss_description(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") | Some("High") =>
            "higher runoff risk; protect waterways",
        Some("Moderate") =>
            "moderate loss potential",
        Some("Low") | Some("Very Low") =>
            "minimal runoff; good for water quality",
        _ => "",
    }
}

fn generate_carbon_section(data: &HashMap<String, Value>) -> String {
    let mut lines = Vec::new();

    lines.push("*Plants capture CO₂ from the atmosphere. Some store it in living tissue (biomass), others contribute long-lasting carbon to soil.*".to_string());
    lines.push(String::new());

    // Biomass Carbon
    let biomass = get_str(data, "carbon_biomass_rating");
    lines.push(format!(
        "- **Living Biomass**: {} - {}",
        format_rating(biomass),
        biomass_description(biomass)
    ));

    // Recalcitrant Carbon
    let recalcitrant = get_str(data, "carbon_recalcitrant_rating");
    lines.push(format!(
        "- **Long-term Soil Carbon**: {} - {}",
        format_rating(recalcitrant),
        recalcitrant_description(recalcitrant)
    ));

    // Total Carbon
    let total = get_str(data, "carbon_total_rating");
    lines.push(format!(
        "- **Total Carbon Benefit**: {}",
        format_rating(total)
    ));

    lines.join("\n")
}

fn biomass_description(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") | Some("High") =>
            "large, dense growth captures significant CO₂; creates habitat and shade",
        Some("Moderate") =>
            "moderate carbon storage in stems, leaves, roots",
        Some("Low") | Some("Very Low") =>
            "smaller plants store less carbon in living tissue",
        _ => "",
    }
}

fn recalcitrant_description(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") | Some("High") =>
            "tough woody/waxy tissues persist in soil for decades",
        Some("Moderate") =>
            "some long-lasting carbon contribution",
        Some("Low") | Some("Very Low") =>
            "soft tissues decompose quickly; less permanent storage",
        _ => "",
    }
}

fn generate_soil_services_section(data: &HashMap<String, Value>) -> String {
    let mut lines = Vec::new();

    // Erosion Protection
    let erosion = get_str(data, "erosion_protection_rating");
    lines.push(format!(
        "**Erosion Protection**: {}",
        format_rating(erosion)
    ));
    lines.push(format!("*{}*", erosion_description(erosion)));

    // Nitrogen Fixation
    let n_fix = get_str(data, "nitrogen_fixation_rating");
    let family = get_str(data, "family").unwrap_or("");
    let is_legume = family.eq_ignore_ascii_case("Fabaceae");

    lines.push(format!(
        "**Nitrogen Fixation**: {}",
        format_rating(n_fix)
    ));

    if is_legume {
        lines.push("*Fabaceae family - partners with rhizobia bacteria to capture atmospheric nitrogen. Can provide 25-75+ lbs N/acre/year, reducing or eliminating synthetic fertilizer needs.*".to_string());
    } else {
        lines.push(format!("*{}*", n_fix_description(n_fix)));
    }

    lines.join("\n")
}

fn erosion_description(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") | Some("High") =>
            "Extensive roots and ground cover anchor soil, protecting topsoil during storms and preventing sediment runoff to waterways. Excellent for slopes.",
        Some("Moderate") =>
            "Moderate root system provides reasonable soil protection.",
        Some("Low") | Some("Very Low") =>
            "Limited root coverage; consider underplanting with ground covers on slopes.",
        _ => "Unable to assess erosion protection.",
    }
}

fn n_fix_description(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") | Some("High") =>
            "Active nitrogen fixer—natural fertilizer factory that enriches soil for neighbouring plants.",
        Some("Moderate") =>
            "Some nitrogen-fixing capacity through root associations.",
        Some("Low") | Some("Very Low") | Some("Unable to Classify") | None =>
            "Does not fix atmospheric nitrogen. Benefits from nitrogen-fixing companion plants.",
        _ => "Unable to classify nitrogen fixation ability.",
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
