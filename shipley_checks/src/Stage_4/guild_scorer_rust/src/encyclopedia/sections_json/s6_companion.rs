//! S6: Guild Potential / Companion Planting (JSON)
//!
//! Slimmed down Dec 2024 to only generate fields used by frontend.
//! See s6_companion.md for documentation of what's displayed.
//!
//! Frontend uses:
//! - Garden Layers: structural_role.layer, height_m, benefits
//! - Closest Relatives: relatives[]
//! - Guild Exchange Provides: predator_count, pollinator count, fungi count, biocontrol counts
//! - Guild Exchange Needs: genus (for diversity), height_m (for spacing)

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::{
    OrganismProfile, FungalCounts, get_str, get_f64,
    StructuralLayer,
};
use crate::encyclopedia::utils::classify::*;
use crate::encyclopedia::view_models::{
    CompanionSection, GuildPotentialDetails, GuildSummary,
    GrowthCompatibility, PestControlAnalysis,
    MycorrhizalAnalysis, StructuralRole, PollinatorSupport,
    RelativeSpecies,
};

// Re-export RelatedSpecies from sections_md for API compatibility (input type)
pub use crate::encyclopedia::sections_md::s1_identity::RelatedSpecies as InputRelatedSpecies;

/// Generate the S6 Guild Potential / Companion Planting section.
pub fn generate(
    data: &HashMap<String, Value>,
    organism_profile: Option<&OrganismProfile>,
    fungal_counts: Option<&FungalCounts>,
    relatives: Option<&[InputRelatedSpecies]>,
) -> CompanionSection {
    // Build detailed guild analysis (slimmed)
    let guild_details = Some(build_guild_details(
        data, organism_profile, fungal_counts,
    ));

    // Build relatives list
    let relatives_vec = relatives.map(|r| {
        r.iter().take(5).map(|rel| RelativeSpecies {
            wfo_id: rel.wfo_id.clone(),
            scientific_name: rel.scientific_name.clone(),
            common_name: rel.common_name.clone(),
            relatedness: classify_relatedness(rel.distance),
            distance: rel.distance,
        }).collect()
    }).unwrap_or_default();

    CompanionSection {
        guild_details,
        relatives: relatives_vec,
    }
}

/// Classify phylogenetic distance into relatedness category.
fn classify_relatedness(distance: f64) -> String {
    if distance < 50.0 {
        "Close".to_string()
    } else if distance < 150.0 {
        "Moderate".to_string()
    } else {
        "Distant".to_string()
    }
}

/// Build slimmed guild details - only fields used by frontend.
fn build_guild_details(
    data: &HashMap<String, Value>,
    organism_profile: Option<&OrganismProfile>,
    fungal_counts: Option<&FungalCounts>,
) -> GuildPotentialDetails {
    let genus = get_str(data, "genus").unwrap_or("Unknown");
    let height_m = get_f64(data, "height_m");
    let layer = classify_structural_layer(height_m);

    // Get counts
    let c = get_f64(data, "C").unwrap_or(0.0);
    let s = get_f64(data, "S").unwrap_or(0.0);
    let r = get_f64(data, "R").unwrap_or(0.0);
    let csr = classify_csr_spread(c, s, r);

    let predators = organism_profile.map(|p| p.total_predators).unwrap_or(0);
    let pollinators = organism_profile.map(|p| p.total_pollinators).unwrap_or(0);
    let (amf, emf) = fungal_counts.map(|c| (c.amf, c.emf)).unwrap_or((0, 0));
    let entomopath = fungal_counts.map(|c| c.entomopathogens).unwrap_or(0);
    let mycoparasites = fungal_counts.map(|c| c.mycoparasites).unwrap_or(0);

    // Summary - only genus + biocontrol counts
    let summary = GuildSummary {
        genus: genus.to_string(),
        mycoparasite_count: mycoparasites,
        entomopathogen_count: entomopath,
    };

    // Growth compatibility - only classification for CSR check
    let growth_compatibility = GrowthCompatibility {
        classification: format!("{} (spread-based)", csr.label()),
    };

    // Pest control - only predator count
    let pest_control = PestControlAnalysis {
        predator_count: predators + entomopath,
    };

    // Mycorrhizal - only species count
    let mycorrhizal_network = MycorrhizalAnalysis {
        species_count: amf + emf,
    };

    // Structural role - layer, height, benefits
    let structural_role = StructuralRole {
        layer: layer.label().to_string(),
        height_m: height_m.unwrap_or(0.0),
        benefits: layer_benefits(layer),
    };

    // Pollinator support - only count
    let pollinator_support = PollinatorSupport {
        count: pollinators,
    };

    GuildPotentialDetails {
        summary,
        growth_compatibility,
        pest_control,
        mycorrhizal_network,
        structural_role,
        pollinator_support,
    }
}

fn layer_benefits(layer: StructuralLayer) -> String {
    match layer {
        StructuralLayer::Canopy => "Creates significant shade; wind protection for neighbours".to_string(),
        StructuralLayer::SubCanopy => "Provides partial shade, benefits from canopy protection".to_string(),
        StructuralLayer::TallShrub => "Mid-structure role in layered plantings".to_string(),
        StructuralLayer::Understory => "Flexible placement in layered plantings".to_string(),
        StructuralLayer::GroundCover => "Soil protection, weed suppression, living mulch".to_string(),
    }
}
