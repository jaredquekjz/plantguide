//! S5: Biological Interactions (JSON)
//!
//! Cloned from sections_md/s5_interactions.rs with minimal changes.
//! Returns InteractionsSection struct instead of markdown String.
//!
//! CHANGE LOG from sections_md:
//! - Return type: String → InteractionsSection
//! - Markdown formatting → struct fields
//! - All classification logic unchanged
//!
//! Data Sources:
//! - Pests, pollinators, predators: organism_profiles_11711.parquet
//! - Diseases, beneficial fungi: fungal_guilds_hybrid_11711.parquet

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::{
    OrganismProfile, FungalCounts, RankedPathogen, BeneficialFungi, MycorrhizalType,
};
use crate::encyclopedia::utils::classify::*;
use crate::encyclopedia::view_models::{
    InteractionsSection, OrganismGroup, OrganismCategory, DiseaseGroup, PathogenInfo,
    FungiGroup, MycorrhizalDetails,
};

/// Generate the S5 Biological Interactions section.
pub fn generate(
    _data: &HashMap<String, Value>,
    organism_profile: Option<&OrganismProfile>,
    fungal_counts: Option<&FungalCounts>,
    ranked_pathogens: Option<&[RankedPathogen]>,
    beneficial_fungi: Option<&BeneficialFungi>,
) -> InteractionsSection {
    // Build pollinators group
    let pollinators = build_pollinator_group(organism_profile);

    // Build herbivores group
    let herbivores = build_herbivore_group(organism_profile);

    // Build beneficial predators group
    let beneficial_predators = build_predator_group(organism_profile);

    // Build fungivores group
    let fungivores = build_fungivore_group(organism_profile);

    // Build diseases group
    let diseases = build_disease_group(fungal_counts, ranked_pathogens);

    // Build beneficial fungi group
    let beneficial_fungi_group = build_beneficial_fungi_group(fungal_counts, beneficial_fungi);

    // Mycorrhizal type and details
    let (mycorrhizal_type, mycorrhizal_details) = build_mycorrhizal_info(fungal_counts);

    InteractionsSection {
        pollinators,
        herbivores,
        beneficial_predators,
        fungivores,
        diseases,
        beneficial_fungi: beneficial_fungi_group,
        mycorrhizal_type,
        mycorrhizal_details,
    }
}

/// Build pollinator organism group.
/// CLONED FROM sections_md generate_pollinator_section - outputs struct instead of markdown
fn build_pollinator_group(profile: Option<&OrganismProfile>) -> OrganismGroup {
    let count = profile.map(|p| p.total_pollinators).unwrap_or(0);

    let categories = if let Some(p) = profile {
        convert_categorized_organisms(&p.pollinators_by_category)
    } else {
        Vec::new()
    };

    OrganismGroup {
        title: "Pollinators".to_string(),
        icon: "🐝".to_string(),
        total_count: count,
        categories,
    }
}

/// Build herbivore organism group.
/// CLONED FROM sections_md generate_herbivore_section - outputs struct instead of markdown
fn build_herbivore_group(profile: Option<&OrganismProfile>) -> OrganismGroup {
    let count = profile.map(|p| p.total_herbivores).unwrap_or(0);

    let categories = if let Some(p) = profile {
        convert_categorized_organisms(&p.herbivores_by_category)
    } else {
        Vec::new()
    };

    OrganismGroup {
        title: "Herbivores & Parasites".to_string(),
        icon: "🐛".to_string(),
        total_count: count,
        categories,
    }
}

/// Build predator organism group.
/// CLONED FROM sections_md generate_predator_section - outputs struct instead of markdown
fn build_predator_group(profile: Option<&OrganismProfile>) -> OrganismGroup {
    let count = profile.map(|p| p.total_predators).unwrap_or(0);

    let categories = if let Some(p) = profile {
        convert_categorized_organisms(&p.predators_by_category)
    } else {
        Vec::new()
    };

    OrganismGroup {
        title: "Beneficial Predators".to_string(),
        icon: "🐞".to_string(),
        total_count: count,
        categories,
    }
}

/// Build fungivore organism group.
/// CLONED FROM sections_md generate_fungivore_section - outputs struct instead of markdown
fn build_fungivore_group(profile: Option<&OrganismProfile>) -> OrganismGroup {
    let count = profile.map(|p| p.total_fungivores).unwrap_or(0);

    let categories = if let Some(p) = profile {
        convert_categorized_organisms(&p.fungivores_by_category)
    } else {
        Vec::new()
    };

    OrganismGroup {
        title: "Fungivores (Disease Control)".to_string(),
        icon: "🍄".to_string(),
        total_count: count,
        categories,
    }
}

/// Build disease group.
/// CLONED FROM sections_md generate_disease_section - outputs struct instead of markdown
fn build_disease_group(
    counts: Option<&FungalCounts>,
    ranked_pathogens: Option<&[RankedPathogen]>,
) -> DiseaseGroup {
    // Convert ranked pathogens to PathogenInfo
    let pathogens: Vec<PathogenInfo> = if let Some(rp) = ranked_pathogens {
        rp.iter()
            .take(10)  // Top 10 pathogens for display
            .map(|p| PathogenInfo {
                name: p.taxon.clone(),
                observation_count: p.observation_count,
                severity: classify_pathogen_severity(p.observation_count),
            })
            .collect()
    } else {
        Vec::new()
    };

    // Build resistance notes based on pathogen count
    let pathogen_count = ranked_pathogens
        .map(|p| p.len())
        .or_else(|| counts.map(|c| c.pathogenic))
        .unwrap_or(0);

    let resistance_notes = if pathogen_count > 10 {
        vec![
            "Monitor in humid conditions; ensure good airflow".to_string(),
            "Higher disease pressure - consider resistant varieties".to_string(),
        ]
    } else if pathogen_count > 0 {
        vec!["Monitor in humid conditions; ensure good airflow".to_string()]
    } else {
        Vec::new()
    };

    DiseaseGroup {
        pathogens,
        resistance_notes,
    }
}

/// Build beneficial fungi group.
/// CLONED FROM sections_md generate_beneficial_fungi_section - outputs struct instead of markdown
fn build_beneficial_fungi_group(
    counts: Option<&FungalCounts>,
    beneficial_fungi: Option<&BeneficialFungi>,
) -> FungiGroup {
    let mycoparasites = if let Some(bf) = beneficial_fungi {
        bf.mycoparasites.clone()
    } else {
        Vec::new()
    };

    let entomopathogens = if let Some(bf) = beneficial_fungi {
        bf.entomopathogens.clone()
    } else {
        Vec::new()
    };

    let endophytes_count = counts.map(|c| c.endophytes).unwrap_or(0);

    FungiGroup {
        mycoparasites,
        entomopathogens,
        endophytes_count,
    }
}

/// Build mycorrhizal type and details.
/// CLONED FROM sections_md - logic from generate_beneficial_fungi_section
fn build_mycorrhizal_info(counts: Option<&FungalCounts>) -> (String, Option<MycorrhizalDetails>) {
    let Some(c) = counts else {
        return ("Unknown".to_string(), None);
    };

    let myco_type = classify_mycorrhizal(c.amf, c.emf);

    let (association_type, description, gardening_tip) = match myco_type {
        MycorrhizalType::AMF => (
            "AMF".to_string(),
            format!(
                "Arbuscular mycorrhizal fungi ({} species): Form networks inside root cells. Help plant absorb phosphorus and other nutrients from soil.",
                c.amf
            ),
            "Minimize soil disturbance to preserve beneficial fungal networks. Avoid excessive tilling and synthetic fertilizers which can harm mycorrhizal partnerships.".to_string(),
        ),
        MycorrhizalType::EMF => (
            "EMF".to_string(),
            format!(
                "Ectomycorrhizal fungi ({} species): Form sheaths around roots. Help absorb nutrients and can signal neighboring plants about pest attacks.",
                c.emf
            ),
            "Minimize soil disturbance to preserve beneficial fungal networks. Avoid excessive tilling and synthetic fertilizers which can harm mycorrhizal partnerships.".to_string(),
        ),
        MycorrhizalType::Dual => (
            "Dual".to_string(),
            format!(
                "Both AMF ({} species) and EMF ({} species) associations documented. Versatile root partnerships for nutrient uptake.",
                c.amf, c.emf
            ),
            "Minimize soil disturbance to preserve beneficial fungal networks. Avoid excessive tilling and synthetic fertilizers which can harm mycorrhizal partnerships.".to_string(),
        ),
        MycorrhizalType::NonMycorrhizal => (
            "None".to_string(),
            "This plant does not rely heavily on mycorrhizal partnerships.".to_string(),
            "Standard cultivation practices apply.".to_string(),
        ),
    };

    let species_count = c.amf + c.emf;

    (
        myco_type.label().to_string(),
        Some(MycorrhizalDetails {
            association_type,
            species_count,
            description,
            gardening_tip,
        }),
    )
}

/// Convert CategorizedOrganisms from types to view_models OrganismCategory.
fn convert_categorized_organisms(
    categories: &[crate::encyclopedia::types::CategorizedOrganisms],
) -> Vec<OrganismCategory> {
    categories
        .iter()
        .filter(|cat| !cat.organisms.is_empty())
        .map(|cat| OrganismCategory {
            name: cat.category.clone(),
            organisms: cat.organisms.clone(),
        })
        .collect()
}

/// Classify pathogen severity based on observation count.
/// CLONED FROM sections_md logic
fn classify_pathogen_severity(observation_count: usize) -> String {
    if observation_count >= 10 {
        "Common".to_string()
    } else if observation_count >= 3 {
        "Occasional".to_string()
    } else {
        "Rare".to_string()
    }
}
