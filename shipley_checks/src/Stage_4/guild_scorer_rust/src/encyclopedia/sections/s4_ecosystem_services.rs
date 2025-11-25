//! Section 4: Ecosystem Services (Functional Benefits)
//!
//! Translates ecosystem service ratings into user-friendly environmental
//! benefits with star ratings and practical planting advice.
//!
//! Ported from R: shipley_checks/src/encyclopedia/sections/s4_ecosystem_services.R

use crate::encyclopedia::utils::categorization::categorize_confidence;

/// Ecosystem service data
pub struct EcosystemServicesData {
    pub carbon_rating: Option<f64>,
    pub carbon_confidence: Option<f64>,
    pub nitrogen_fix_rating: Option<f64>,
    pub nitrogen_fix_confidence: Option<f64>,
    pub nitrogen_fix_has_try: Option<bool>,
    pub erosion_rating: Option<f64>,
    pub erosion_confidence: Option<f64>,
    pub nutrient_cycling_rating: Option<f64>,
    pub nutrient_cycling_confidence: Option<f64>,
    pub decomposition_rating: Option<f64>,
    pub height_m: Option<f64>,
    pub woodiness: Option<f64>,
    pub growth_form: Option<String>,
}

/// Generate Section 4: Ecosystem Services
pub fn generate_ecosystem_services(data: &EcosystemServicesData) -> String {
    let mut sections = Vec::new();

    sections.push("## Ecosystem Services".to_string());

    let mut service_sections = Vec::new();

    // Carbon sequestration
    if let (Some(rating), Some(conf)) = (data.carbon_rating, data.carbon_confidence) {
        if conf >= 0.4 {
            service_sections.push(generate_carbon_service(rating, conf, data));
        }
    }

    // Nitrogen fixation
    if let (Some(rating), Some(conf)) = (data.nitrogen_fix_rating, data.nitrogen_fix_confidence) {
        if conf >= 0.4 {
            service_sections.push(generate_nitrogen_service(rating, conf, data.nitrogen_fix_has_try));
        }
    }

    // Erosion control
    if let (Some(rating), Some(conf)) = (data.erosion_rating, data.erosion_confidence) {
        if conf >= 0.4 {
            service_sections.push(generate_erosion_service(rating, conf, data.growth_form.as_deref()));
        }
    }

    // Nutrient cycling
    if let (Some(rating), Some(conf)) = (data.nutrient_cycling_rating, data.nutrient_cycling_confidence) {
        if conf >= 0.4 {
            service_sections.push(generate_nutrient_service(rating, conf, data.decomposition_rating));
        }
    }

    if service_sections.is_empty() {
        sections.push("\n**Environmental benefits**: Data insufficient for confident assessment".to_string());
    } else {
        sections.push("\n**Environmental Benefits**:".to_string());
        for s in service_sections {
            sections.push(format!("\n{}", s));
        }
    }

    sections.join("")
}

fn get_star_rating(rating: f64) -> String {
    let stars = ((rating / 2.0).ceil() as usize).clamp(1, 5);
    "⭐".repeat(stars)
}

fn get_rating_descriptor(rating: f64) -> &'static str {
    if rating >= 8.0 {
        "Excellent"
    } else if rating >= 6.0 {
        "High"
    } else if rating >= 4.0 {
        "Moderate"
    } else if rating >= 2.0 {
        "Low"
    } else {
        "Minimal"
    }
}

fn generate_carbon_service(rating: f64, confidence: f64, data: &EcosystemServicesData) -> String {
    let stars = get_star_rating(rating);
    let descriptor = get_rating_descriptor(rating);
    let conf_level = categorize_confidence(confidence)
        .map(|c| c.as_str())
        .unwrap_or("Unknown");

    // Estimate carbon storage
    let carbon_text = if let (Some(height), Some(woodiness)) = (data.height_m, data.woodiness) {
        let w = if woodiness > 1.0 { woodiness / 100.0 } else { woodiness };
        let carbon_kg = (height * w * 7.0).round() as i32;
        if carbon_kg > 0 {
            format!("Stores ~{} kg CO₂/year in biomass", carbon_kg)
        } else {
            "Carbon storage in plant tissues".to_string()
        }
    } else {
        "Carbon storage in plant tissues".to_string()
    };

    let advice = if rating >= 7.0 {
        "→ Excellent choice for carbon-conscious gardening"
    } else if rating >= 5.0 {
        "→ Contributes to garden carbon sequestration"
    } else {
        "→ Modest carbon storage"
    };

    format!(
        "🌿 **Carbon Sequestration**: {} {} (confidence: {})\n   {}\n   {}",
        stars, descriptor, conf_level, carbon_text, advice
    )
}

fn generate_nitrogen_service(rating: f64, confidence: f64, has_try: Option<bool>) -> String {
    let stars = get_star_rating(rating);
    let descriptor = get_rating_descriptor(rating);
    let conf_level = categorize_confidence(confidence)
        .map(|c| c.as_str())
        .unwrap_or("Unknown");

    let (mechanism, advice) = if rating >= 7.0 {
        ("Fixes atmospheric nitrogen via root nodules",
         "→ Plant near nitrogen-demanding crops | Improves soil fertility naturally")
    } else if rating >= 4.0 {
        ("Moderate nitrogen contribution to soil",
         "→ Useful in mixed planting for soil improvement")
    } else {
        ("Not a nitrogen fixer | Relies on soil nitrogen",
         "→ Ensure adequate nitrogen in soil amendments")
    };

    let data_note = if has_try == Some(true) {
        " (verified by TRY database)"
    } else {
        ""
    };

    format!(
        "🌾 **Soil Improvement - Nitrogen**: {} {} (confidence: {}){}\n   {}\n   {}",
        stars, descriptor, conf_level, data_note, mechanism, advice
    )
}

fn generate_erosion_service(rating: f64, confidence: f64, growth_form: Option<&str>) -> String {
    let stars = get_star_rating(rating);
    let descriptor = get_rating_descriptor(rating);
    let conf_level = categorize_confidence(confidence)
        .map(|c| c.as_str())
        .unwrap_or("Unknown");

    let mechanism = match growth_form {
        Some(f) if f.to_lowercase().contains("grass") => "Dense fibrous root system stabilizes soil",
        Some("tree") | Some("shrub") => "Deep woody roots anchor soil on slopes",
        Some("climber") => "Ground cover reduces water runoff",
        _ => "Root system provides soil stabilization",
    };

    let advice = if rating >= 7.0 {
        "→ Excellent for slopes, banks, and erosion-prone sites"
    } else if rating >= 5.0 {
        "→ Useful for moderate erosion control"
    } else {
        "→ Limited erosion protection"
    };

    format!(
        "🌊 **Erosion Control**: {} {} (confidence: {})\n   {}\n   {}",
        stars, descriptor, conf_level, mechanism, advice
    )
}

fn generate_nutrient_service(rating: f64, confidence: f64, decomp_rating: Option<f64>) -> String {
    let stars = get_star_rating(rating);
    let descriptor = get_rating_descriptor(rating);
    let conf_level = categorize_confidence(confidence)
        .map(|c| c.as_str())
        .unwrap_or("Unknown");

    let mechanism = match decomp_rating {
        Some(d) if d >= 7.0 => "Fast-decomposing litter rapidly returns nutrients to soil",
        Some(d) if d >= 4.0 => "Moderate decomposition contributes to nutrient availability",
        Some(_) => "Slow-decomposing litter provides long-term organic matter",
        None => "Contributes organic matter to soil food web",
    };

    let advice = if rating >= 6.0 {
        "→ Excellent for building soil health over time"
    } else {
        "→ Modest contribution to nutrient cycling"
    };

    format!(
        "♻️ **Nutrient Cycling**: {} {} (confidence: {})\n   {}\n   {}",
        stars, descriptor, conf_level, mechanism, advice
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_star_rating() {
        assert_eq!(get_star_rating(10.0), "⭐⭐⭐⭐⭐");
        assert_eq!(get_star_rating(8.0), "⭐⭐⭐⭐");
        assert_eq!(get_star_rating(5.0), "⭐⭐⭐");
        assert_eq!(get_star_rating(2.0), "⭐");
    }

    #[test]
    fn test_rating_descriptor() {
        assert_eq!(get_rating_descriptor(9.0), "Excellent");
        assert_eq!(get_rating_descriptor(7.0), "High");
        assert_eq!(get_rating_descriptor(5.0), "Moderate");
        assert_eq!(get_rating_descriptor(3.0), "Low");
        assert_eq!(get_rating_descriptor(1.0), "Minimal");
    }

    #[test]
    fn test_ecosystem_services_output() {
        let data = EcosystemServicesData {
            carbon_rating: Some(8.0),
            carbon_confidence: Some(0.7),
            nitrogen_fix_rating: Some(9.0),
            nitrogen_fix_confidence: Some(0.8),
            nitrogen_fix_has_try: Some(true),
            erosion_rating: Some(6.0),
            erosion_confidence: Some(0.5),
            nutrient_cycling_rating: Some(5.0),
            nutrient_cycling_confidence: Some(0.6),
            decomposition_rating: Some(7.0),
            height_m: Some(10.0),
            woodiness: Some(0.8),
            growth_form: Some("tree".to_string()),
        };

        let output = generate_ecosystem_services(&data);
        assert!(output.contains("Carbon"));
        assert!(output.contains("Nitrogen"));
        assert!(output.contains("Erosion"));
        assert!(output.contains("Nutrient"));
    }
}
