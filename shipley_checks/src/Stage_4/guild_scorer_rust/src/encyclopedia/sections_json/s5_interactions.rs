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
//! - Diseases: fungi_flat.parquet (pathogenic_fungi) + pathogen_diseases.parquet
//! - Beneficial fungi: fungi_flat.parquet (mycoparasite_fungi, entomopathogenic_fungi)

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::{
    OrganismProfile, FungalCounts, PathogenicFungus, BeneficialFungi, MycorrhizalType,
};
use crate::encyclopedia::utils::classify::*;
use crate::encyclopedia::view_models::{
    InteractionsSection, OrganismGroup, OrganismCategory, DiseaseGroup, DiseaseCategory, DiseaseInfo,
    FungiGroup, MycorrhizalDetails,
};

/// Generate the S5 Biological Interactions section.
pub fn generate(
    _data: &HashMap<String, Value>,
    organism_profile: Option<&OrganismProfile>,
    fungal_counts: Option<&FungalCounts>,
    pathogenic_fungi: Option<&[PathogenicFungus]>,
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

    // Build diseases group (from pathogenic fungi)
    let diseases = build_disease_group(fungal_counts, pathogenic_fungi);

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

    // Get pollinator level and interpretation from classify.rs
    let (level, interpretation) = classify_pollinator_level(count);

    OrganismGroup {
        title: "Pollinators".to_string(),
        icon: "🐝".to_string(),
        total_count: count,
        level: level.to_string(),
        interpretation: interpretation.to_string(),
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

    // Get pest level and advice from classify.rs
    let (level, advice) = classify_pest_level(count);

    OrganismGroup {
        title: "Herbivores & Parasites".to_string(),
        icon: "🐛".to_string(),
        total_count: count,
        level: level.to_string(),
        interpretation: advice.to_string(),
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

    // Get predator level and interpretation from classify.rs
    let (level, interpretation) = classify_predator_level(count);

    OrganismGroup {
        title: "Beneficial Predators".to_string(),
        icon: "🐞".to_string(),
        total_count: count,
        level: level.to_string(),
        interpretation: interpretation.to_string(),
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

    // Use predator level thresholds for fungivores (similar biocontrol role)
    let (level, interpretation) = classify_predator_level(count);

    OrganismGroup {
        title: "Fungivores (Disease Control)".to_string(),
        icon: "🍄".to_string(),
        total_count: count,
        level: level.to_string(),
        interpretation: interpretation.to_string(),
        categories,
    }
}

/// Build disease group from pathogenic fungi.
/// Groups diseases by disease_type (rust, spot, mildew, rot, etc.)
fn build_disease_group(
    counts: Option<&FungalCounts>,
    pathogenic_fungi: Option<&[PathogenicFungus]>,
) -> DiseaseGroup {
    use std::collections::HashMap;

    // Get total pathogen count - from pathogenic_fungi list or fallback to fungal counts
    let pathogen_count = pathogenic_fungi
        .map(|p| p.len())
        .or_else(|| counts.map(|c| c.pathogenic))
        .unwrap_or(0);

    // Get disease level and advice from classify.rs
    let (disease_level, disease_advice) = classify_disease_level(pathogen_count);

    // Group pathogenic fungi by disease_type
    let categories: Vec<DiseaseCategory> = if let Some(pf) = pathogenic_fungi {
        // Group by disease_type
        let mut type_map: HashMap<String, Vec<DiseaseInfo>> = HashMap::new();

        for p in pf {
            let dtype = p.disease_type.clone().unwrap_or_else(|| "other".to_string());
            type_map
                .entry(dtype)
                .or_default()
                .push(DiseaseInfo {
                    taxon: p.taxon.clone(),
                    disease_name: p.disease_name.clone(),
                });
        }

        // Convert to sorted categories (by count descending, "other" at end)
        let mut cats: Vec<DiseaseCategory> = type_map
            .into_iter()
            .map(|(name, diseases)| DiseaseCategory { name, diseases })
            .collect();

        cats.sort_by(|a, b| {
            let a_is_other = a.name == "other";
            let b_is_other = b.name == "other";
            match (a_is_other, b_is_other) {
                (true, false) => std::cmp::Ordering::Greater,
                (false, true) => std::cmp::Ordering::Less,
                _ => b.diseases.len().cmp(&a.diseases.len())
                    .then_with(|| a.name.cmp(&b.name)),
            }
        });

        cats
    } else {
        Vec::new()
    };

    // Build resistance notes based on pathogen count
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
        disease_level: disease_level.to_string(),
        disease_advice: disease_advice.to_string(),
        pathogen_count,
        categories,
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
        MycorrhizalType::NonMycorrhizal => {
            // No documented associations - don't show section (absence of data ≠ absence of need)
            return (myco_type.label().to_string(), None);
        },
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
