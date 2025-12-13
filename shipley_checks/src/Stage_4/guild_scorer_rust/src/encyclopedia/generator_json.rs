//! Encyclopedia Generator (JSON)
//!
//! Main entry point for generating plant encyclopedia data as JSON structs.
//! Orchestrates all six sections (S1-S6) to produce an EncyclopediaPageData struct.
//!
//! Public API (consumed by api_server.rs):
//! - generate_encyclopedia_data(...) -> Result<EncyclopediaPageData>

use std::collections::HashMap;
use serde_json::Value;

use crate::encyclopedia::types::{OrganismProfile, FungalCounts, PathogenicFungus, BeneficialFungi};
use crate::encyclopedia::sections_json::{
    s1_identity,
    s2_requirements,
    s3_maintenance,
    s4_services,
    s5_interactions,
    s6_companion,
};
use crate::encyclopedia::sections_json::s6_companion::InputRelatedSpecies;
use crate::encyclopedia::suitability::local_conditions::LocalConditions;
use crate::encyclopedia::view_models::{EncyclopediaPageData, LocationInfo};

/// Generate complete encyclopedia data for a plant as JSON structs.
///
/// # Arguments
/// * `wfo_id` - WFO taxon ID (e.g., "wfo-0001005999")
/// * `plant_data` - HashMap of plant attributes from Phase 7 parquet
/// * `organism_profile` - Optional categorized organism lists for rich display
/// * `fungal_counts` - Optional fungal association counts
/// * `pathogenic_fungi` - Optional pathogenic fungi with disease names (from fungi_flat + pathogen_diseases)
/// * `beneficial_fungi` - Optional beneficial fungi species (mycoparasites, entomopathogens)
/// * `related_species` - Optional list of phylogenetically closest relatives (for S6 companion section)
/// * `local_conditions` - Optional user's local climate and soil conditions
///
/// # Returns
/// Complete EncyclopediaPageData struct, or error message.
#[allow(clippy::too_many_arguments)]
pub fn generate_encyclopedia_data(
    wfo_id: &str,
    plant_data: &HashMap<String, Value>,
    organism_profile: Option<&OrganismProfile>,
    fungal_counts: Option<&FungalCounts>,
    pathogenic_fungi: Option<&[PathogenicFungus]>,
    beneficial_fungi: Option<&BeneficialFungi>,
    related_species: Option<&[InputRelatedSpecies]>,
    local_conditions: Option<&LocalConditions>,
) -> Result<EncyclopediaPageData, String> {
    // S1: Identity Card
    let identity = s1_identity::generate(
        wfo_id,
        plant_data,
    );

    // S2: Growing Requirements (with optional local suitability)
    let requirements = s2_requirements::generate(plant_data, local_conditions);

    // S3: Maintenance Profile
    let maintenance = s3_maintenance::generate(plant_data);

    // S4: Ecosystem Services
    let services = s4_services::generate(plant_data);

    // S5: Biological Interactions
    let interactions = s5_interactions::generate(
        plant_data,
        organism_profile,
        fungal_counts,
        pathogenic_fungi,
        beneficial_fungi,
    );

    // S6: Guild Potential (Companion Planting) - includes relatives for phylogenetic diversity
    let companion = s6_companion::generate(
        plant_data,
        organism_profile,
        fungal_counts,
        related_species,
    );

    // Location info
    let location = match local_conditions {
        Some(loc) => LocationInfo {
            name: loc.name.clone(),
            // Derive code from name (lowercase, first word)
            code: loc.name.split(',').next()
                .map(|s| s.to_lowercase().replace(' ', "-"))
                .unwrap_or_default(),
            climate_zone: loc.climate_tier().display_name().to_string(),
        },
        None => LocationInfo::default(),
    };

    Ok(EncyclopediaPageData {
        identity,
        requirements,
        maintenance,
        services,
        interactions,
        companion,
        location,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_minimal() {
        let mut data = HashMap::new();
        data.insert("wfo_scientific_name".to_string(), Value::String("Test species".to_string()));
        data.insert("family".to_string(), Value::String("Testaceae".to_string()));
        data.insert("genus".to_string(), Value::String("Testus".to_string()));

        let result = generate_encyclopedia_data(
            "wfo-test",
            &data,
            None, None, None, None, None, None
        );
        assert!(result.is_ok());

        let page = result.unwrap();
        assert_eq!(page.identity.scientific_name, "Test species");
        assert_eq!(page.identity.family, "Testaceae");
    }
}
