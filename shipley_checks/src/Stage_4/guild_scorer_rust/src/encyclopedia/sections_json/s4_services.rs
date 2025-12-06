//! S4: Ecosystem Services (JSON)
//!
//! Cloned from sections_md/s4_services.rs with minimal changes.
//! Returns EcosystemServices struct instead of markdown String.
//!
//! CHANGE LOG from sections_md:
//! - Return type: String → EcosystemServices
//! - Markdown formatting → struct fields
//! - All description functions unchanged (logic preserved)
//!
//! Data Sources (from Stage 3 pipeline):
//! - NPP, decomposition, nutrient dynamics: CSR-derived (pre-calculated)
//! - Carbon storage: Growth form and biomass derived
//! - Nitrogen fixation: TRY database family-level classification

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::{get_str, get_f64};
use crate::encyclopedia::view_models::{
    EcosystemServices, EcosystemRatings, ServiceRating, ServiceCard, ServiceIcon,
};

/// Generate the S4 Ecosystem Services section.
pub fn generate(data: &HashMap<String, Value>) -> EcosystemServices {
    let ratings = build_ecosystem_ratings(data);
    let services = build_service_cards(data);

    let n_fix = get_str(data, "nitrogen_fixation_rating");
    let nitrogen_fixer = n_fix == Some("Very High") || n_fix == Some("High");

    let pollinator_score = get_f64(data, "ecoserv_pollination")
        .map(|p| (p * 100.0) as u8);

    let carbon_storage = get_str(data, "carbon_storage_rating")
        .map(|r| r.to_string());

    EcosystemServices {
        ratings: Some(ratings),
        services,
        nitrogen_fixer,
        pollinator_score,
        carbon_storage,
    }
}

/// Build all 10 ecosystem ratings from pre-calculated data.
/// CLONED FROM sections_md - reads same fields, outputs struct instead of markdown
fn build_ecosystem_ratings(data: &HashMap<String, Value>) -> EcosystemRatings {
    let npp_rating = get_str(data, "npp_rating");
    let decomp_rating = get_str(data, "decomposition_rating");
    let cycling_rating = get_str(data, "nutrient_cycling_rating");
    let retention_rating = get_str(data, "nutrient_retention_rating");
    let loss_rating = get_str(data, "nutrient_loss_rating");
    let biomass_rating = get_str(data, "carbon_storage_rating");
    let recalcitrant_rating = get_str(data, "leaf_carbon_recalcitrant_rating");
    let erosion_rating = get_str(data, "erosion_protection_rating");
    let n_fix_rating = get_str(data, "nitrogen_fixation_rating");

    let family = get_str(data, "family").unwrap_or("");
    let is_legume = family.eq_ignore_ascii_case("Fabaceae");

    EcosystemRatings {
        npp: ServiceRating {
            score: rating_to_score(npp_rating),
            rating: format_rating(npp_rating),
            description: npp_description(npp_rating).to_string(),
        },
        decomposition: ServiceRating {
            score: rating_to_score(decomp_rating),
            rating: format_rating(decomp_rating),
            description: decomp_description(decomp_rating).to_string(),
        },
        nutrient_cycling: ServiceRating {
            score: rating_to_score(cycling_rating),
            rating: format_rating(cycling_rating),
            description: "Efficiency of nutrient movement through the garden ecosystem".to_string(),
        },
        nutrient_retention: ServiceRating {
            score: rating_to_score(retention_rating),
            rating: format_rating(retention_rating),
            description: retention_description(retention_rating).to_string(),
        },
        nutrient_loss_risk: ServiceRating {
            score: rating_to_score(loss_rating),
            rating: format_rating(loss_rating),
            description: loss_description(loss_rating).to_string(),
        },
        carbon_storage: ServiceRating {
            score: rating_to_score(biomass_rating),
            rating: format_rating(biomass_rating),
            description: biomass_description(biomass_rating).to_string(),
        },
        carbon_recalcitrant: ServiceRating {
            score: rating_to_score(recalcitrant_rating),
            rating: format_rating(recalcitrant_rating),
            description: recalcitrant_description(recalcitrant_rating).to_string(),
        },
        erosion_protection: ServiceRating {
            score: rating_to_score(erosion_rating),
            rating: format_rating(erosion_rating),
            description: erosion_description(erosion_rating).to_string(),
        },
        nitrogen_fixation: ServiceRating {
            score: rating_to_score(n_fix_rating),
            rating: format_rating(n_fix_rating),
            description: if is_legume {
                "Fabaceae family - partners with rhizobia bacteria to capture atmospheric nitrogen".to_string()
            } else {
                n_fix_description(n_fix_rating).to_string()
            },
        },
        garden_value_summary: generate_garden_value_summary(data),
    }
}

/// Build service cards for visual display.
fn build_service_cards(data: &HashMap<String, Value>) -> Vec<ServiceCard> {
    let mut cards = Vec::new();

    // Pollination
    if let Some(poll) = get_f64(data, "ecoserv_pollination") {
        cards.push(ServiceCard {
            name: "Pollination Support".to_string(),
            icon: ServiceIcon::Pollination,
            value: format!("{:.0}%", poll * 100.0),
            description: describe_pollination(poll),
            confidence: get_confidence(data, "ecoserv_pollination_conf"),
        });
    }

    // Carbon storage
    if let Some(carbon) = get_f64(data, "ecoserv_carbon") {
        cards.push(ServiceCard {
            name: "Carbon Storage".to_string(),
            icon: ServiceIcon::CarbonStorage,
            value: format!("{:.0}%", carbon * 100.0),
            description: describe_carbon(carbon),
            confidence: get_confidence(data, "ecoserv_carbon_conf"),
        });
    }

    // Soil health
    if let Some(soil) = get_f64(data, "ecoserv_soil_health") {
        cards.push(ServiceCard {
            name: "Soil Health".to_string(),
            icon: ServiceIcon::SoilHealth,
            value: format!("{:.0}%", soil * 100.0),
            description: "Improves soil structure and biology".to_string(),
            confidence: get_confidence(data, "ecoserv_soil_conf"),
        });
    }

    // Nitrogen fixation (if applicable)
    let n_fix = get_str(data, "nitrogen_fixation_rating");
    if n_fix == Some("Very High") || n_fix == Some("High") {
        cards.push(ServiceCard {
            name: "Nitrogen Fixation".to_string(),
            icon: ServiceIcon::SoilHealth,
            value: "Yes".to_string(),
            description: "Fixes atmospheric nitrogen, enriching soil".to_string(),
            confidence: "High".to_string(),
        });
    }

    cards
}

/// Convert rating string to numeric score (1-5 scale).
fn rating_to_score(rating: Option<&str>) -> Option<f64> {
    match rating {
        Some("Very High") => Some(5.0),
        Some("High") => Some(4.0),
        Some("Moderate") => Some(3.0),
        Some("Low") => Some(2.0),
        Some("Very Low") => Some(1.0),
        _ => None,
    }
}

/// Format rating for display (with fallback).
fn format_rating(rating: Option<&str>) -> String {
    rating.unwrap_or("Unknown").to_string()
}

/// Get confidence level from data.
fn get_confidence(data: &HashMap<String, Value>, field: &str) -> String {
    get_str(data, field)
        .map(|s| s.to_string())
        .unwrap_or_else(|| "Medium".to_string())
}

/// Describe pollination support level.
fn describe_pollination(score: f64) -> String {
    if score > 0.7 {
        "Strong pollinator magnet - attracts bees, butterflies, and other pollinators".to_string()
    } else if score > 0.4 {
        "Moderate pollinator support".to_string()
    } else {
        "Limited pollinator value".to_string()
    }
}

/// Describe carbon storage level.
fn describe_carbon(score: f64) -> String {
    if score > 0.7 {
        "Excellent carbon capture - large woody biomass stores significant carbon".to_string()
    } else if score > 0.4 {
        "Good carbon contribution".to_string()
    } else {
        "Modest carbon storage".to_string()
    }
}

// ============================================================================
// Description Functions - CLONED FROM sections_md (unchanged)
// ============================================================================

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
            "Fast litter breakdown returns nutrients to soil quickly, keeping it fertile and reducing fertilizer needs.",
        Some("Moderate") =>
            "Moderate breakdown rate. Nutrients recycle at a balanced pace.",
        Some("Low") | Some("Very Low") =>
            "Slow decomposition means leaf litter persists longer. Good for mulch and long-term carbon storage.",
        _ => "Unable to assess decomposition rate.",
    }
}

fn retention_description(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") | Some("High") =>
            "Holds nutrients well; reduces fertilizer needs",
        Some("Moderate") =>
            "Moderate retention",
        Some("Low") | Some("Very Low") =>
            "Nutrients may leach away; more frequent feeding needed",
        _ => "",
    }
}

fn loss_description(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") | Some("High") =>
            "Higher runoff risk; protect waterways",
        Some("Moderate") =>
            "Moderate loss potential",
        Some("Low") | Some("Very Low") =>
            "Minimal runoff; good for water quality",
        _ => "",
    }
}

fn biomass_description(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") | Some("High") =>
            "Large, dense growth captures significant CO₂; creates habitat and shade",
        Some("Moderate") =>
            "Moderate carbon storage in stems, leaves, roots",
        Some("Low") | Some("Very Low") =>
            "Smaller plants store less carbon in living tissue",
        _ => "",
    }
}

fn recalcitrant_description(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") | Some("High") =>
            "Tough woody/waxy tissues persist in soil for decades",
        Some("Moderate") =>
            "Some long-lasting carbon contribution",
        Some("Low") | Some("Very Low") =>
            "Soft tissues decompose quickly; less permanent storage",
        _ => "",
    }
}

fn erosion_description(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") | Some("High") =>
            "Extensive roots and ground cover anchor soil, excellent for slopes",
        Some("Moderate") =>
            "Moderate root system provides reasonable soil protection",
        Some("Low") | Some("Very Low") =>
            "Limited root coverage; consider underplanting with ground covers on slopes",
        _ => "Unable to assess erosion protection",
    }
}

fn n_fix_description(rating: Option<&str>) -> &'static str {
    match rating {
        Some("Very High") | Some("High") =>
            "Active nitrogen fixer—natural fertilizer factory that enriches soil for neighbouring plants",
        Some("Moderate") =>
            "Some nitrogen-fixing capacity through root associations",
        Some("Low") | Some("Very Low") | Some("Unable to Classify") | None =>
            "Does not fix atmospheric nitrogen. Benefits from nitrogen-fixing companion plants",
        _ => "Unable to classify nitrogen fixation ability",
    }
}

/// Generate garden value summary.
/// CLONED FROM sections_md - logic unchanged
fn generate_garden_value_summary(data: &HashMap<String, Value>) -> String {
    let mut highlights = Vec::new();

    let n_fix = get_str(data, "nitrogen_fixation_rating");
    if n_fix == Some("Very High") || n_fix == Some("High") {
        highlights.push("improves soil fertility through nitrogen fixation");
    }

    let carbon = get_str(data, "carbon_storage_rating");
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
        "Standard ecosystem contribution".to_string()
    } else {
        format!("Good choice - {}", highlights.join("; "))
    }
}
