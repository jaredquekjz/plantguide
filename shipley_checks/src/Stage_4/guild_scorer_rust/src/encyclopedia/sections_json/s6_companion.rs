//! S6: Guild Potential / Companion Planting (JSON)
//!
//! Cloned from sections_md/s6_companion.rs with minimal changes.
//! Returns CompanionSection struct instead of markdown String.
//!
//! CHANGE LOG from sections_md:
//! - Return type: String → CompanionSection
//! - Markdown formatting → struct fields
//! - All classification logic unchanged
//!
//! Data Sources (same as markdown):
//! - Taxonomy: from plant data
//! - Growth compatibility: CSR values, height, growth form
//! - Pest/Disease control: organism_profiles, fungal_guilds
//! - Mycorrhizal network: AMF/EMF counts from fungal data
//! - Structural role: height, growth form
//! - Pollinator support: organism counts

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::{
    OrganismProfile, FungalCounts, get_str, get_f64,
    CsrStrategy, GrowthFormCategory, MycorrhizalType, StructuralLayer,
};
use crate::encyclopedia::utils::classify::*;
use crate::encyclopedia::view_models::{
    CompanionSection, GuildRole, GuildPotentialDetails, GuildSummary,
    GrowthCompatibility, PestControlAnalysis, DiseaseControlAnalysis,
    MycorrhizalAnalysis, StructuralRole, PollinatorSupport, CompanionPlant,
};

/// Try to get EIVE value from either column format.
/// CLONED FROM sections_md - logic unchanged
fn get_eive(data: &HashMap<String, Value>, axis: &str) -> Option<f64> {
    get_f64(data, &format!("EIVE_{}_complete", axis))
        .or_else(|| get_f64(data, &format!("EIVEres-{}_complete", axis)))
        .or_else(|| get_f64(data, &format!("EIVE_{}", axis)))
        .or_else(|| get_f64(data, &format!("EIVEres-{}", axis)))
}

/// Generate the S6 Guild Potential / Companion Planting section.
pub fn generate(
    data: &HashMap<String, Value>,
    organism_profile: Option<&OrganismProfile>,
    fungal_counts: Option<&FungalCounts>,
) -> CompanionSection {
    // Extract common values
    let family = get_str(data, "family").unwrap_or("Unknown");
    let c = get_f64(data, "C").unwrap_or(0.0);
    let s = get_f64(data, "S").unwrap_or(0.0);
    let r = get_f64(data, "R").unwrap_or(0.0);
    let csr = classify_csr_spread(c, s, r);
    let height_m = get_f64(data, "height_m");
    let growth_form = get_str(data, "try_growth_form");
    let form = classify_growth_form(growth_form, height_m);
    let eive_l = get_eive(data, "L");

    // Get organism and fungi counts
    let herbivores = organism_profile.map(|p| p.total_herbivores).unwrap_or(0);
    let predators = organism_profile.map(|p| p.total_predators).unwrap_or(0);
    let pollinators = organism_profile.map(|p| p.total_pollinators).unwrap_or(0);
    let (amf, emf) = fungal_counts.map(|c| (c.amf, c.emf)).unwrap_or((0, 0));
    let entomopath = fungal_counts.map(|c| c.entomopathogens).unwrap_or(0);
    let mycoparasites = fungal_counts.map(|c| c.mycoparasites).unwrap_or(0);
    let myco = classify_mycorrhizal(amf, emf);

    // Build guild roles
    let guild_roles = build_guild_roles(
        csr, form, myco, herbivores, predators, pollinators, mycoparasites, entomopath,
    );

    // Build detailed guild analysis
    let guild_details = Some(build_guild_details(
        data, organism_profile, fungal_counts,
        c, s, r, csr, form, height_m, eive_l,
        herbivores, predators, pollinators, amf, emf, mycoparasites,
    ));

    // Build avoid_with list
    let avoid_with = build_avoid_with(family, csr, eive_l);

    // Build planting notes
    let planting_notes = build_planting_notes(csr, form, myco);

    CompanionSection {
        guild_roles,
        guild_details,
        good_companions: Vec::new(),  // Requires external companion suggestions
        avoid_with,
        planting_notes,
    }
}

/// Build guild roles from plant characteristics.
fn build_guild_roles(
    csr: CsrStrategy,
    form: GrowthFormCategory,
    myco: MycorrhizalType,
    herbivores: usize,
    predators: usize,
    pollinators: usize,
    mycoparasites: usize,
    entomopath: usize,
) -> Vec<GuildRole> {
    let mut roles = Vec::new();

    // CSR-based role
    let (csr_role, csr_strength) = match csr {
        CsrStrategy::CDominant => ("Competitor", "Strong"),
        CsrStrategy::SDominant => ("Stress-tolerator", "Strong"),
        CsrStrategy::RDominant => ("Pioneer/Gap filler", "Moderate"),
        CsrStrategy::Balanced => ("Generalist", "Moderate"),
    };
    roles.push(GuildRole {
        role: csr_role.to_string(),
        strength: csr_strength.to_string(),
        explanation: csr_role_explanation(csr),
    });

    // Structural role
    let structural_role = match form {
        GrowthFormCategory::Tree => "Canopy provider",
        GrowthFormCategory::Shrub => "Mid-layer structure",
        GrowthFormCategory::Herb => "Ground layer",
        GrowthFormCategory::Vine => "Vertical space user",
    };
    roles.push(GuildRole {
        role: structural_role.to_string(),
        strength: "Moderate".to_string(),
        explanation: format!("{} growth form provides structural function", form.label()),
    });

    // Mycorrhizal network role
    if myco != MycorrhizalType::NonMycorrhizal {
        roles.push(GuildRole {
            role: "Network participant".to_string(),
            strength: if myco == MycorrhizalType::Dual { "Strong" } else { "Moderate" }.to_string(),
            explanation: format!("{} - participates in underground fungal networks", myco.label()),
        });
    }

    // Pest control role (if significant predators or entomopathogens)
    if predators >= 9 || entomopath > 0 {
        let strength = if predators >= 29 { "Strong" } else { "Moderate" };
        roles.push(GuildRole {
            role: "Pest control habitat".to_string(),
            strength: strength.to_string(),
            explanation: format!(
                "Attracts {} predator species{}",
                predators,
                if entomopath > 0 { format!(" + {} insect-killing fungi", entomopath) } else { String::new() }
            ),
        });
    }

    // Disease control role
    if mycoparasites > 0 {
        roles.push(GuildRole {
            role: "Disease fighter host".to_string(),
            strength: "Moderate".to_string(),
            explanation: format!("Hosts {} beneficial fungi that attack plant diseases", mycoparasites),
        });
    }

    // Pollinator role
    if pollinators >= 6 {
        let strength = if pollinators >= 45 { "Strong" } else if pollinators >= 20 { "Moderate" } else { "Weak" };
        roles.push(GuildRole {
            role: "Pollinator attractor".to_string(),
            strength: strength.to_string(),
            explanation: format!("{} pollinator species documented", pollinators),
        });
    }

    roles
}

fn csr_role_explanation(csr: CsrStrategy) -> String {
    match csr {
        CsrStrategy::CDominant => "Vigorous grower that actively spreads - needs space management".to_string(),
        CsrStrategy::SDominant => "Built for endurance - low maintenance, reliable guild backbone".to_string(),
        CsrStrategy::RDominant => "Fast-living opportunist - good for gaps, plan for succession".to_string(),
        CsrStrategy::Balanced => "Adaptable generalist - fits well in most positions".to_string(),
    }
}

/// Build detailed guild analysis.
#[allow(clippy::too_many_arguments)]
fn build_guild_details(
    data: &HashMap<String, Value>,
    organism_profile: Option<&OrganismProfile>,
    fungal_counts: Option<&FungalCounts>,
    c: f64, s: f64, r: f64,
    csr: CsrStrategy,
    form: GrowthFormCategory,
    height_m: Option<f64>,
    eive_l: Option<f64>,
    herbivores: usize,
    predators: usize,
    pollinators: usize,
    amf: usize, emf: usize,
    mycoparasites: usize,
) -> GuildPotentialDetails {
    let family = get_str(data, "family").unwrap_or("Unknown");
    let genus = get_str(data, "genus").unwrap_or("Unknown");
    let layer = classify_structural_layer(height_m);
    let myco = classify_mycorrhizal(amf, emf);
    let entomopath = fungal_counts.map(|c| c.entomopathogens).unwrap_or(0);

    // Summary (from GP summary card)
    let summary = GuildSummary {
        taxonomy_guidance: format!("Seek plants from different families than {}", family),
        growth_guidance: csr_short_guidance(csr).to_string(),
        structure_role: structural_short_guidance(layer).to_string(),
        mycorrhizal_guidance: myco_short_guidance(myco).to_string(),
        pest_summary: pest_short_guidance(herbivores, predators).to_string(),
        disease_summary: disease_short_guidance(mycoparasites).to_string(),
        pollinator_summary: format!("{} species documented", pollinators),
    };

    // Key principles (from sections_md generate_summary_card)
    let key_principles = vec![
        format!("Diversify taxonomy - seek plants from different families than {}", family),
        format!("Growth compatibility - {}", csr_compatibility_advice(csr)),
        format!("Layer plants - {}", layer_advice(layer)),
        format!("Fungal network - {}", myco_advice(myco)),
    ];

    // Growth compatibility
    let growth_compatibility = GrowthCompatibility {
        csr_profile: format!("C: {:.0}% | S: {:.0}% | R: {:.0}%", c, s, r),
        classification: format!("{} (spread-based)", csr.label()),
        growth_form: form.label().to_string(),
        height_m: height_m.unwrap_or(0.0),
        light_preference: eive_l.unwrap_or(0.0),
        companion_strategy: csr_form_advice(csr, form, eive_l),
        avoid_pairing: csr_avoid_list(csr),
    };

    // Pest control analysis
    let (pest_level, pest_interp) = classify_pest_level(herbivores);
    let (pred_level, pred_interp) = classify_predator_level(predators);
    let pest_control = PestControlAnalysis {
        pest_count: herbivores,
        pest_level: pest_level.to_string(),
        pest_interpretation: pest_interp.to_string(),
        predator_count: predators + entomopath,
        predator_level: pred_level.to_string(),
        predator_interpretation: pred_interp.to_string(),
        recommendations: build_pest_recommendations(herbivores, predators, entomopath),
    };

    // Disease control analysis
    let disease_control = DiseaseControlAnalysis {
        beneficial_fungi_count: mycoparasites,
        recommendations: build_disease_recommendations(mycoparasites),
    };

    // Mycorrhizal analysis
    let mycorrhizal_network = MycorrhizalAnalysis {
        association_type: myco.label().to_string(),
        species_count: amf + emf,
        network_type: match myco {
            MycorrhizalType::AMF => "AMF network".to_string(),
            MycorrhizalType::EMF => "EMF network".to_string(),
            MycorrhizalType::Dual => "Dual AMF/EMF network".to_string(),
            MycorrhizalType::NonMycorrhizal => "No network".to_string(),
        },
        recommendations: build_myco_recommendations(myco),
    };

    // Structural role
    let structural_role = StructuralRole {
        layer: layer.label().to_string(),
        height_m: height_m.unwrap_or(0.0),
        growth_form: form.label().to_string(),
        light_preference: eive_l.unwrap_or(0.0),
        understory_recommendations: understory_advice(layer),
        avoid_recommendations: layer_avoid_advice(layer, eive_l),
        benefits: layer_benefits(layer),
    };

    // Pollinator support
    let (poll_level, poll_interp) = classify_pollinator_level(pollinators);
    let pollinator_support = PollinatorSupport {
        count: pollinators,
        level: poll_level.to_string(),
        interpretation: poll_interp.to_string(),
        recommendations: pollinator_recommendation(pollinators),
        benefits: build_pollinator_benefits(pollinators),
    };

    // Cautions
    let cautions = build_cautions(family, csr, eive_l);

    GuildPotentialDetails {
        summary,
        key_principles,
        growth_compatibility,
        pest_control,
        disease_control,
        mycorrhizal_network,
        structural_role,
        pollinator_support,
        cautions,
    }
}

// ============================================================================
// Helper functions - CLONED FROM sections_md
// ============================================================================

fn csr_short_guidance(csr: CsrStrategy) -> &'static str {
    match csr {
        CsrStrategy::CDominant => "Avoid C-C pairs",
        CsrStrategy::SDominant => "Good with most",
        CsrStrategy::RDominant => "Plan succession",
        CsrStrategy::Balanced => "Flexible",
    }
}

fn structural_short_guidance(layer: StructuralLayer) -> &'static str {
    match layer {
        StructuralLayer::Canopy => "Shade provider",
        StructuralLayer::SubCanopy => "Partial shade",
        StructuralLayer::TallShrub => "Mid-layer",
        StructuralLayer::Understory => "Shade user",
        StructuralLayer::GroundCover => "Soil protection",
    }
}

fn myco_short_guidance(myco: MycorrhizalType) -> &'static str {
    match myco {
        MycorrhizalType::AMF => "Connect with AMF plants",
        MycorrhizalType::EMF => "Connect with EMF plants",
        MycorrhizalType::Dual => "Bridges both networks",
        MycorrhizalType::NonMycorrhizal => "No network benefit",
    }
}

fn pest_short_guidance(herbivores: usize, predators: usize) -> &'static str {
    if predators >= 9 {
        "Strong biocontrol habitat"
    } else if herbivores >= 15 {
        "Benefits from predator plants"
    } else {
        "Typical"
    }
}

fn disease_short_guidance(mycoparasites: usize) -> &'static str {
    if mycoparasites > 0 {
        "Hosts disease fighters"
    } else {
        "No documented antagonists"
    }
}

fn csr_compatibility_advice(csr: CsrStrategy) -> &'static str {
    match csr {
        CsrStrategy::CDominant => "avoid other C-dominant plants at same height",
        CsrStrategy::SDominant => "compatible with most strategies",
        CsrStrategy::RDominant => "pair with longer-lived S or balanced plants",
        CsrStrategy::Balanced => "flexible positioning; compatible with most",
    }
}

fn layer_advice(layer: StructuralLayer) -> &'static str {
    match layer {
        StructuralLayer::Canopy | StructuralLayer::SubCanopy => "pair with shade-tolerant understory",
        StructuralLayer::TallShrub => "works as mid-layer; ground covers below",
        StructuralLayer::Understory | StructuralLayer::GroundCover => "can grow under taller plants",
    }
}

fn myco_advice(myco: MycorrhizalType) -> &'static str {
    match myco {
        MycorrhizalType::AMF => "seek other AMF-associated plants for network benefits",
        MycorrhizalType::EMF => "seek other EMF-associated plants for network benefits",
        MycorrhizalType::Dual => "bridges both network types - very flexible",
        MycorrhizalType::NonMycorrhizal => "no underground network constraints",
    }
}

fn csr_form_advice(csr: CsrStrategy, form: GrowthFormCategory, eive_l: Option<f64>) -> String {
    match (csr, form) {
        (CsrStrategy::CDominant, GrowthFormCategory::Tree) => {
            "Canopy competitor. Pairs well with shade-tolerant understory (EIVE-L < 5). Avoid other large C-dominant trees nearby.".to_string()
        }
        (CsrStrategy::CDominant, GrowthFormCategory::Shrub) => {
            "Vigorous mid-layer. Give wide spacing from other C-dominant shrubs. Good with S-dominant ground covers.".to_string()
        }
        (CsrStrategy::CDominant, GrowthFormCategory::Herb) => {
            "Spreading competitor. May outcompete neighbouring herbs. Best with well-spaced, resilient companions.".to_string()
        }
        (CsrStrategy::CDominant, GrowthFormCategory::Vine) => {
            "Aggressive climber. Needs robust host tree or structure. May smother less vigorous plants.".to_string()
        }
        (CsrStrategy::SDominant, _) => {
            let light_note = match eive_l {
                Some(l) if l < 3.2 => "Shade-tolerant. Thrives under C-dominant canopy trees.",
                Some(l) if l > 7.47 => "Sun-demanding despite S-strategy. Needs open position.",
                _ => "Flexible S-plant. Tolerates range of companions.",
            };
            format!("{}. Low competition profile. Pairs well with most strategies. Long-lived and persistent.", light_note)
        }
        (CsrStrategy::RDominant, GrowthFormCategory::Herb) => {
            "Annual/biennial. Good for dynamic, changing plantings. Pair with longer-lived S or balanced plants.".to_string()
        }
        (CsrStrategy::RDominant, GrowthFormCategory::Vine) => {
            "May die back; regrows rapidly. Pair with longer-lived plants for continuity.".to_string()
        }
        (CsrStrategy::RDominant, _) => {
            "Short-lived opportunist. Use for seasonal colour or gap-filling. Pair with longer-lived plants.".to_string()
        }
        (CsrStrategy::Balanced, _) => {
            "Generalist strategy. Compatible with most companion types. Moderate vigour; flexible in guild positioning.".to_string()
        }
    }
}

fn csr_avoid_list(csr: CsrStrategy) -> Vec<String> {
    match csr {
        CsrStrategy::CDominant => vec![
            "Other C-dominant plants at same layer (competition)".to_string(),
            "Sun-loving plants in shade zone".to_string(),
        ],
        CsrStrategy::SDominant => Vec::new(),  // Good with most
        CsrStrategy::RDominant => vec![
            "Rely solely on R-plants for permanent structure".to_string(),
        ],
        CsrStrategy::Balanced => Vec::new(),  // Flexible
    }
}

fn build_pest_recommendations(herbivores: usize, predators: usize, entomopath: usize) -> Vec<String> {
    let mut recs = Vec::new();

    if herbivores >= 15 {
        recs.push("High pest diversity (top 10%). Benefits from companions that attract pest predators.".to_string());
    } else if herbivores >= 6 {
        recs.push("Above-average pest observations. Diverse plantings help maintain natural balance.".to_string());
    } else {
        recs.push("Typical pest observations. Standard companion planting applies.".to_string());
    }

    if predators >= 29 {
        recs.push("Excellent predator habitat (top 10%). Attracts many beneficial insects that protect neighbours.".to_string());
    } else if predators >= 9 {
        recs.push("Good predator habitat. Contributes beneficial insects to the garden.".to_string());
    }

    if entomopath > 0 {
        recs.push(format!("Hosts {} insect-killing fungi that may help control pests on neighbours.", entomopath));
    }

    recs
}

fn build_disease_recommendations(mycoparasites: usize) -> Vec<String> {
    if mycoparasites > 0 {
        vec![
            format!("Hosts {} beneficial fungi that attack plant diseases.", mycoparasites),
            "May help protect neighbouring plants from fungal diseases.".to_string(),
        ]
    } else {
        vec!["No documented mycoparasitic fungi. Focus on spacing and airflow for disease prevention.".to_string()]
    }
}

fn build_myco_recommendations(myco: MycorrhizalType) -> Vec<String> {
    match myco {
        MycorrhizalType::AMF => vec![
            "Network-compatible plants: Other plants with AMF associations".to_string(),
            "Can share phosphorus and carbon with AMF-compatible neighbours".to_string(),
            "Minimize tillage to preserve fungal hyphal connections".to_string(),
        ],
        MycorrhizalType::EMF => vec![
            "Network-compatible plants: Other plants with EMF associations".to_string(),
            "Can share nutrients and defense signals with EMF-compatible neighbours".to_string(),
            "Creates forest-type nutrient-sharing network".to_string(),
        ],
        MycorrhizalType::Dual => vec![
            "Can connect to both AMF and EMF network types".to_string(),
            "Versatile guild member - bridges different plant communities".to_string(),
        ],
        MycorrhizalType::NonMycorrhizal => vec![
            "Non-mycorrhizal or undocumented. May not participate in underground fungal networks.".to_string(),
            "No network conflict, but no documented network benefit from CMN.".to_string(),
        ],
    }
}

fn understory_advice(layer: StructuralLayer) -> String {
    match layer {
        StructuralLayer::Canopy => "Shade-tolerant understory plants (EIVE-L < 5)".to_string(),
        StructuralLayer::SubCanopy => "Ground covers, shade-tolerant shrubs".to_string(),
        StructuralLayer::TallShrub => "Low herbs, ground covers".to_string(),
        StructuralLayer::Understory | StructuralLayer::GroundCover => "N/A - low growing".to_string(),
    }
}

fn layer_avoid_advice(layer: StructuralLayer, eive_l: Option<f64>) -> String {
    match layer {
        StructuralLayer::Canopy => "Sun-loving plants in the shade zone".to_string(),
        StructuralLayer::SubCanopy => "Very shade-intolerant plants nearby".to_string(),
        StructuralLayer::TallShrub => "".to_string(),
        StructuralLayer::Understory => {
            match eive_l {
                Some(l) if l > 7.47 => "Planting under canopy (sun-loving)".to_string(),
                Some(l) if l < 3.2 => "Full sun exposure (shade-adapted)".to_string(),
                _ => "".to_string(),
            }
        }
        StructuralLayer::GroundCover => "".to_string(),
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

fn pollinator_recommendation(pollinators: usize) -> String {
    if pollinators >= 45 {
        "Pollinator hotspot (top 10%). Central to garden pollination success. Benefits ALL flowering neighbours.".to_string()
    } else if pollinators >= 20 {
        "Strong pollinator magnet. Valuable addition to any garden.".to_string()
    } else if pollinators >= 6 {
        "Typical pollinator observations. Good companion for other flowering plants.".to_string()
    } else if pollinators >= 2 {
        "Few pollinators observed. Consider pairing with pollinator-rich plants for better cross-pollination.".to_string()
    } else {
        "Little or no pollinator data in GloBI. Likely a data gap - most flowering plants attract pollinators.".to_string()
    }
}

fn build_pollinator_benefits(pollinators: usize) -> Vec<String> {
    let mut benefits = vec![format!("Nectar/pollen source for {} pollinator species", pollinators)];
    if pollinators >= 6 {
        benefits.push("Attraction effect may increase visits to neighbouring plants".to_string());
    }
    benefits
}

fn build_avoid_with(family: &str, csr: CsrStrategy, eive_l: Option<f64>) -> Vec<String> {
    let mut avoid = Vec::new();

    avoid.push(format!("Multiple {} plants clustered together (shared pests/diseases)", family));

    if csr == CsrStrategy::CDominant {
        avoid.push("Other C-dominant plants at same height".to_string());
    }

    if let Some(l) = eive_l {
        if l > 7.47 {
            avoid.push("Planting under dense canopy (sun-loving)".to_string());
        } else if l < 3.2 {
            avoid.push("Full sun exposure without shade (shade-adapted)".to_string());
        }
    }

    avoid
}

fn build_planting_notes(csr: CsrStrategy, form: GrowthFormCategory, myco: MycorrhizalType) -> Vec<String> {
    let mut notes = Vec::new();

    // CSR-based notes
    match csr {
        CsrStrategy::CDominant => {
            notes.push("Vigorous grower - needs space management".to_string());
        }
        CsrStrategy::SDominant => {
            notes.push("Low maintenance - reliable guild backbone".to_string());
        }
        CsrStrategy::RDominant => {
            notes.push("Short-lived - plan for succession or self-seeding".to_string());
        }
        CsrStrategy::Balanced => {
            notes.push("Adaptable - fits well in most positions".to_string());
        }
    }

    // Form-based notes
    if form == GrowthFormCategory::Vine {
        notes.push("Needs vertical support structure".to_string());
    }

    // Mycorrhizal notes
    if myco != MycorrhizalType::NonMycorrhizal {
        notes.push("Minimize soil disturbance to preserve fungal networks".to_string());
    }

    notes
}

fn build_cautions(family: &str, csr: CsrStrategy, eive_l: Option<f64>) -> Vec<String> {
    let mut cautions = Vec::new();

    cautions.push(format!("Avoid clustering multiple {} plants (shared pests and diseases)", family));

    if csr == CsrStrategy::CDominant {
        cautions.push("C-dominant strategy: may outcompete slower-growing neighbours".to_string());
    }

    if csr == CsrStrategy::RDominant {
        cautions.push("R-dominant strategy: short-lived, plan for succession or self-seeding".to_string());
    }

    if let Some(l) = eive_l {
        if l > 7.47 {
            cautions.push("Sun-loving: will struggle or fail under canopy shade".to_string());
        } else if l < 3.2 {
            cautions.push("Shade-adapted: may struggle in full sun without canopy protection".to_string());
        }
    }

    cautions
}
