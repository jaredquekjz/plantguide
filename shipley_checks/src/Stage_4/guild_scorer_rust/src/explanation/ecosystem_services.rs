/// Ecosystem Services Explanation
///
/// Provides layman-friendly descriptions and rating interpretations for
/// the 10 ecosystem services (M8-M17) based on community-weighted means.

use crate::metrics::EcosystemServicesResult;
use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EcosystemServiceCard {
    pub name: String,
    pub rating: String,
    pub description: String,
    pub benefit_level: String,  // "Excellent", "Good", "Moderate", "Limited", "Very Limited"
}

/// Generate ecosystem services section for guild explanation
pub fn generate_ecosystem_services(services: &EcosystemServicesResult) -> Vec<EcosystemServiceCard> {
    vec![
        generate_npp_card(services),
        generate_decomposition_card(services),
        generate_nutrient_cycling_card(services),
        generate_nutrient_retention_card(services),
        generate_nutrient_loss_card(services),
        generate_carbon_biomass_card(services),
        generate_carbon_recalcitrant_card(services),
        generate_carbon_total_card(services),
        generate_erosion_protection_card(services),
        generate_nitrogen_fixation_card(services),
    ]
}

fn rating_to_benefit_level(rating: &str) -> &'static str {
    match rating {
        "Very High" => "Excellent",
        "High" => "Good",
        "Moderate" => "Moderate",
        "Low" => "Limited",
        "Very Low" => "Very Limited",
        _ => "Unknown",
    }
}

fn generate_npp_card(services: &EcosystemServicesResult) -> EcosystemServiceCard {
    EcosystemServiceCard {
        name: "Net Primary Productivity".to_string(),
        rating: services.m8_npp_rating.clone(),
        description: "How much your plants grow and produce biomass each year. High productivity means more leaves, stems, and roots—providing food for wildlife, improving air quality, and creating a lush, thriving garden that captures more carbon from the atmosphere.".to_string(),
        benefit_level: rating_to_benefit_level(&services.m8_npp_rating).to_string(),
    }
}

fn generate_decomposition_card(services: &EcosystemServicesResult) -> EcosystemServiceCard {
    EcosystemServiceCard {
        name: "Decomposition Rate".to_string(),
        rating: services.m9_decomp_rating.clone(),
        description: "How quickly plant material breaks down and returns nutrients to the soil. Fast decomposition means nutrients cycle rapidly, keeping your soil fertile and reducing the need for external fertilizers. This supports healthy soil biology with active earthworms and microbes.".to_string(),
        benefit_level: rating_to_benefit_level(&services.m9_decomp_rating).to_string(),
    }
}

fn generate_nutrient_cycling_card(services: &EcosystemServicesResult) -> EcosystemServiceCard {
    EcosystemServiceCard {
        name: "Nutrient Cycling".to_string(),
        rating: services.m10_nutrient_cycling_rating.clone(),
        description: "How efficiently nutrients move through your garden's ecosystem—from soil to plants to decomposers and back to soil. Good cycling creates a self-sustaining system where nutrients are constantly recycled, reducing fertilizer dependency and creating resilient, healthy plants.".to_string(),
        benefit_level: rating_to_benefit_level(&services.m10_nutrient_cycling_rating).to_string(),
    }
}

fn generate_nutrient_retention_card(services: &EcosystemServicesResult) -> EcosystemServiceCard {
    EcosystemServiceCard {
        name: "Nutrient Retention".to_string(),
        rating: services.m11_nutrient_retention_rating.clone(),
        description: "How well plants and soil hold onto valuable nutrients instead of losing them to leaching or runoff. High retention means nutrients stay available for plant uptake longer, improving water quality downstream and reducing the need for frequent fertilizer applications.".to_string(),
        benefit_level: rating_to_benefit_level(&services.m11_nutrient_retention_rating).to_string(),
    }
}

fn generate_nutrient_loss_card(services: &EcosystemServicesResult) -> EcosystemServiceCard {
    // Note: For nutrient loss, LOWER is better (inverse relationship)
    let inverted_benefit = match services.m12_nutrient_loss_rating.as_str() {
        "Very High" => "Limited",      // High loss = bad
        "High" => "Moderate",          // Some loss = moderate concern
        "Moderate" => "Good",          // Moderate loss = acceptable
        "Low" => "Excellent",          // Low loss = very good
        "Very Low" => "Excellent",     // Very low loss = excellent
        _ => "Unknown",
    };

    EcosystemServiceCard {
        name: "Nutrient Loss Prevention".to_string(),
        rating: services.m12_nutrient_loss_rating.clone(),
        description: "How much your guild prevents nutrients from being washed away by rain or irrigation. Lower nutrient loss protects water quality in nearby streams and ponds, saves money on fertilizers, and keeps nutrients available for your plants rather than polluting waterways.".to_string(),
        benefit_level: inverted_benefit.to_string(),
    }
}

fn generate_carbon_biomass_card(services: &EcosystemServicesResult) -> EcosystemServiceCard {
    EcosystemServiceCard {
        name: "Carbon Storage (Living Biomass)".to_string(),
        rating: services.m13_carbon_biomass_rating.clone(),
        description: "How much carbon your plants store in their stems, leaves, and roots while they're alive. Plants with large, dense growth capture more CO₂ from the air, helping combat climate change while creating habitat and shade. This is the 'green carbon' you can see and touch.".to_string(),
        benefit_level: rating_to_benefit_level(&services.m13_carbon_biomass_rating).to_string(),
    }
}

fn generate_carbon_recalcitrant_card(services: &EcosystemServicesResult) -> EcosystemServiceCard {
    EcosystemServiceCard {
        name: "Carbon Storage (Long-term Soil)".to_string(),
        rating: services.m14_carbon_recalcitrant_rating.clone(),
        description: "How much stable, long-lasting carbon your plants contribute to the soil through tough, slow-decomposing materials like woody tissues and waxy leaves. This 'recalcitrant' carbon stays in soil for decades or centuries, providing lasting climate benefits and improving soil structure.".to_string(),
        benefit_level: rating_to_benefit_level(&services.m14_carbon_recalcitrant_rating).to_string(),
    }
}

fn generate_carbon_total_card(services: &EcosystemServicesResult) -> EcosystemServiceCard {
    EcosystemServiceCard {
        name: "Total Carbon Storage".to_string(),
        rating: services.m15_carbon_total_rating.clone(),
        description: "The combined climate benefit from both living plant biomass and long-term soil carbon. High total storage means your guild acts as a powerful carbon sink, removing CO₂ from the atmosphere both quickly (through growth) and permanently (through soil enrichment).".to_string(),
        benefit_level: rating_to_benefit_level(&services.m15_carbon_total_rating).to_string(),
    }
}

fn generate_erosion_protection_card(services: &EcosystemServicesResult) -> EcosystemServiceCard {
    EcosystemServiceCard {
        name: "Soil Erosion Protection".to_string(),
        rating: services.m16_erosion_protection_rating.clone(),
        description: "How well your plants anchor the soil and prevent it from washing or blowing away. Good protection comes from extensive root systems and ground cover that hold soil in place during storms, preserving your topsoil—the most fertile layer—and preventing sediment pollution in waterways.".to_string(),
        benefit_level: rating_to_benefit_level(&services.m16_erosion_protection_rating).to_string(),
    }
}

fn generate_nitrogen_fixation_card(services: &EcosystemServicesResult) -> EcosystemServiceCard {
    EcosystemServiceCard {
        name: "Nitrogen Fixation".to_string(),
        rating: services.m17_nitrogen_fixation_rating.clone(),
        description: "Whether your guild includes legumes or other plants that partner with bacteria to capture nitrogen from the air and convert it into plant-usable forms. This natural fertilizer factory can provide 25-75+ pounds of nitrogen per acre per year, reducing or eliminating the need for synthetic fertilizers.".to_string(),
        benefit_level: rating_to_benefit_level(&services.m17_nitrogen_fixation_rating).to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rating_to_benefit_level() {
        assert_eq!(rating_to_benefit_level("Very High"), "Excellent");
        assert_eq!(rating_to_benefit_level("High"), "Good");
        assert_eq!(rating_to_benefit_level("Moderate"), "Moderate");
        assert_eq!(rating_to_benefit_level("Low"), "Limited");
        assert_eq!(rating_to_benefit_level("Very Low"), "Very Limited");
    }

    #[test]
    fn test_generate_ecosystem_services() {
        let services = EcosystemServicesResult {
            m8_npp_score: 4.0,
            m8_npp_rating: "High".to_string(),
            m9_decomp_score: 4.5,
            m9_decomp_rating: "Very High".to_string(),
            m10_nutrient_cycling_score: 3.5,
            m10_nutrient_cycling_rating: "High".to_string(),
            m11_nutrient_retention_score: 3.0,
            m11_nutrient_retention_rating: "Moderate".to_string(),
            m12_nutrient_loss_score: 2.5,
            m12_nutrient_loss_rating: "Moderate".to_string(),
            m13_carbon_biomass_score: 4.0,
            m13_carbon_biomass_rating: "High".to_string(),
            m14_carbon_recalcitrant_score: 3.5,
            m14_carbon_recalcitrant_rating: "High".to_string(),
            m15_carbon_total_score: 4.2,
            m15_carbon_total_rating: "High".to_string(),
            m16_erosion_protection_score: 3.8,
            m16_erosion_protection_rating: "High".to_string(),
            m17_nitrogen_fixation_score: 2.0,
            m17_nitrogen_fixation_rating: "Low".to_string(),
        };

        let cards = generate_ecosystem_services(&services);
        assert_eq!(cards.len(), 10);
        assert_eq!(cards[0].name, "Net Primary Productivity");
        assert_eq!(cards[0].rating, "High");
        assert_eq!(cards[0].benefit_level, "Good");
    }
}
