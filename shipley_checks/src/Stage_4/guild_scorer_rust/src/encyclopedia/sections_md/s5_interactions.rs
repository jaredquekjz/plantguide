//! S5: Biological Interactions
//!
//! Rules for generating the biological interactions section of encyclopedia articles.
//! Shows interactions documented for THIS plant from GloBI observation records.
//!
//! Data Sources:
//! - Pests, pollinators, predators: organism_profiles_11711.parquet
//! - Diseases, beneficial fungi: fungal_guilds_hybrid_11711.parquet
//!
//! Data Distribution Reference (from 11,711 plants):
//! | Metric              | p25 | p50 | p75 | p90 | Coverage |
//! |---------------------|-----|-----|-----|-----|----------|
//! | herbivore_count     |  1  |  2  |  6  | 15  | 33.6%    |
//! | pollinator_count    |  2  |  6  | 20  | 45  | 13.4%    |
//! | pathogenic_fungi    |  1  |  3  |  7  | 15  | 61.6%    |
//! | predators (sum)     |  1  |  3  |  9  | 29  | 35.1%    |

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::*;
use crate::encyclopedia::utils::classify::*;

/// Generate the S5 Biological Interactions section.
pub fn generate(
    _data: &HashMap<String, Value>,
    organism_counts: Option<&OrganismCounts>,
    fungal_counts: Option<&FungalCounts>,
    organism_profile: Option<&OrganismProfile>,
    ranked_pathogens: Option<&Vec<RankedPathogen>>,
    beneficial_fungi: Option<&BeneficialFungi>,
) -> String {
    let mut sections = Vec::new();
    sections.push("## Biological Interactions".to_string());
    sections.push(String::new());
    sections.push("*Organisms documented interacting with this plant from GloBI (Global Biotic Interactions) records.*".to_string());

    // Pollinators
    sections.push(String::new());
    sections.push(generate_pollinator_section(organism_counts, organism_profile));

    // Herbivores/Pests
    sections.push(String::new());
    sections.push(generate_herbivore_section(organism_counts, organism_profile));

    // Beneficial Predators (natural pest control)
    sections.push(String::new());
    sections.push(generate_predator_section(organism_counts, organism_profile));

    // Fungivores (natural disease control - eat pathogenic fungi)
    sections.push(String::new());
    sections.push(generate_fungivore_section(organism_profile));

    // Diseases
    sections.push(String::new());
    sections.push(generate_disease_section(fungal_counts, ranked_pathogens));

    // Beneficial Fungi
    sections.push(String::new());
    sections.push(generate_beneficial_fungi_section(fungal_counts, beneficial_fungi));

    sections.join("\n")
}

/// Format organisms by category for display (max 3 per category, show count if more)
fn format_organisms_by_category(categories: &[CategorizedOrganisms], max_per_category: usize) -> Vec<String> {
    let mut lines = Vec::new();

    for cat in categories {
        if cat.organisms.is_empty() {
            continue;
        }

        let display_names: Vec<&str> = cat.organisms.iter()
            .take(max_per_category)
            .map(|s| s.as_str())
            .collect();

        let extra = cat.organisms.len().saturating_sub(max_per_category);
        let extra_str = if extra > 0 {
            format!(", +{} more", extra)
        } else {
            String::new()
        };

        lines.push(format!(
            "- **{}** ({}): {}{}",
            cat.category,
            cat.organisms.len(),
            display_names.join(", "),
            extra_str
        ));
    }

    lines
}

fn generate_pollinator_section(
    counts: Option<&OrganismCounts>,
    profile: Option<&OrganismProfile>,
) -> String {
    let mut lines = Vec::new();
    lines.push("### Pollinators".to_string());

    let count = profile
        .map(|p| p.total_pollinators)
        .or_else(|| counts.map(|c| c.pollinators))
        .unwrap_or(0);

    if count == 0 {
        lines.push("No pollinator records available.".to_string());
        return lines.join("\n");
    }

    let (level, interpretation) = classify_pollinator_level(count);
    lines.push(format!("**{}** ({} species documented)", level, count));
    lines.push(format!("*{}*", interpretation));

    // Rich display with organism names by category
    if let Some(p) = profile {
        if !p.pollinators_by_category.is_empty() {
            lines.push(String::new());
            lines.extend(format_organisms_by_category(&p.pollinators_by_category, 3));
        }
    }

    // Visitor count if available (broader than strict pollinators)
    if let Some(c) = counts {
        if c.visitors > c.pollinators && c.visitors > 0 {
            lines.push(format!(
                "*Plus {} additional flower visitors observed*",
                c.visitors - c.pollinators
            ));
        }
    }

    lines.join("\n")
}

fn generate_herbivore_section(
    counts: Option<&OrganismCounts>,
    profile: Option<&OrganismProfile>,
) -> String {
    let mut lines = Vec::new();
    lines.push("### Herbivores & Parasites".to_string());

    let count = profile
        .map(|p| p.total_herbivores)
        .or_else(|| counts.map(|c| c.herbivores))
        .unwrap_or(0);

    if count == 0 {
        lines.push("No herbivore/parasite records available.".to_string());
        return lines.join("\n");
    }

    let (level, advice) = classify_pest_level(count);
    lines.push(format!("**{}** ({} species documented)", level, count));
    lines.push(format!("*{}*", advice));

    // Rich display with organism names by category
    if let Some(p) = profile {
        if !p.herbivores_by_category.is_empty() {
            lines.push(String::new());
            lines.extend(format_organisms_by_category(&p.herbivores_by_category, 3));
        }
    }

    lines.join("\n")
}

fn generate_predator_section(
    counts: Option<&OrganismCounts>,
    profile: Option<&OrganismProfile>,
) -> String {
    let mut lines = Vec::new();
    lines.push("### Beneficial Predators".to_string());

    let count = profile
        .map(|p| p.total_predators)
        .or_else(|| counts.map(|c| c.predators))
        .unwrap_or(0);

    if count == 0 {
        lines.push("No beneficial predator records available.".to_string());
        lines.push("*This plant may benefit from companions that attract pest predators.*".to_string());
        return lines.join("\n");
    }

    lines.push(format!("**{} species documented** - natural pest control agents", count));

    // Rich display with organism names by category
    if let Some(p) = profile {
        if !p.predators_by_category.is_empty() {
            lines.push(String::new());
            lines.extend(format_organisms_by_category(&p.predators_by_category, 3));
        }
    }

    lines.push(String::new());
    lines.push("*These beneficial organisms help control pest populations.*".to_string());

    lines.join("\n")
}

fn generate_fungivore_section(
    profile: Option<&OrganismProfile>,
) -> String {
    let mut lines = Vec::new();
    lines.push("### Fungivores (Disease Control)".to_string());

    let count = profile
        .map(|p| p.total_fungivores)
        .unwrap_or(0);

    if count == 0 {
        lines.push("No fungivore records available.".to_string());
        return lines.join("\n");
    }

    lines.push(format!("**{} species documented** - organisms that eat fungi", count));
    lines.push(String::new());
    lines.push("*Fungivores help control plant diseases by consuming pathogenic fungi. They provide natural disease suppression in the garden ecosystem.*".to_string());

    // Rich display with organism names by category
    if let Some(p) = profile {
        if !p.fungivores_by_category.is_empty() {
            lines.push(String::new());
            lines.extend(format_organisms_by_category(&p.fungivores_by_category, 3));
        }
    }

    lines.join("\n")
}

fn generate_disease_section(
    counts: Option<&FungalCounts>,
    ranked_pathogens: Option<&Vec<RankedPathogen>>,
) -> String {
    let mut lines = Vec::new();
    lines.push("### Diseases".to_string());

    // Count from ranked pathogens if available, else from fungal counts
    let pathogen_count = ranked_pathogens
        .map(|p| p.len())
        .or_else(|| counts.map(|c| c.pathogenic))
        .unwrap_or(0);

    let (level, advice) = classify_disease_level(pathogen_count);

    lines.push(format!("**Disease Risk**: {} ({} pathogens observed)", level, pathogen_count));
    lines.push(format!("*{}*", advice));

    // Display top pathogens with observation counts
    if let Some(pathogens) = ranked_pathogens {
        if !pathogens.is_empty() {
            lines.push(String::new());
            lines.push("**Most Observed Diseases** (by GloBI observation frequency):".to_string());

            for (i, p) in pathogens.iter().take(5).enumerate() {
                lines.push(format!(
                    "{}. **{}** ({} obs)",
                    i + 1,
                    p.taxon,
                    p.observation_count
                ));
            }

            if pathogens.len() > 5 {
                lines.push(format!("*...and {} more*", pathogens.len() - 5));
            }
        }
    }

    if pathogen_count > 0 {
        lines.push(String::new());
        lines.push("*Monitor in humid conditions; ensure good airflow*".to_string());
    }

    lines.join("\n")
}

fn generate_beneficial_fungi_section(
    counts: Option<&FungalCounts>,
    beneficial_fungi: Option<&BeneficialFungi>,
) -> String {
    let mut lines = Vec::new();
    lines.push("### Beneficial Fungi".to_string());
    lines.push(String::new());
    lines.push("*Fungi form important partnerships with plants. Some help roots absorb nutrients, others protect against diseases or pests.*".to_string());

    if let Some(c) = counts {
        let myco_type = classify_mycorrhizal(c.amf, c.emf);

        // Root Partnership Fungi (Mycorrhizal)
        lines.push(String::new());
        lines.push("**Root Partnership Fungi (Mycorrhizal)**".to_string());
        lines.push(format!("Status: {}", myco_type.label()));

        if c.amf > 0 {
            lines.push(format!(
                "- **Arbuscular mycorrhizal fungi** ({} species): Form networks inside root cells. Help plant absorb phosphorus and other nutrients from soil.",
                c.amf
            ));
        }
        if c.emf > 0 {
            lines.push(format!(
                "- **Ectomycorrhizal fungi** ({} species): Form sheaths around roots. Help absorb nutrients and can signal neighboring plants about pest attacks.",
                c.emf
            ));
        }
        if c.endophytes > 0 {
            lines.push(format!(
                "- **Endophytic fungi** ({} species): Live inside plant tissues without causing harm. Often help plants tolerate drought or deter herbivores.",
                c.endophytes
            ));
        }
        if c.amf == 0 && c.emf == 0 && c.endophytes == 0 {
            lines.push("- No root partnership fungi documented for this species.".to_string());
        }

        // Pest & Disease Control Fungi
        let has_biocontrol = c.mycoparasites > 0 || c.entomopathogens > 0;
        if has_biocontrol {
            lines.push(String::new());
            lines.push("**Pest & Disease Control Fungi**".to_string());

            if c.mycoparasites > 0 {
                if let Some(bf) = beneficial_fungi {
                    if !bf.mycoparasites.is_empty() {
                        let display: Vec<&str> = bf.mycoparasites.iter().take(3).map(|s| s.as_str()).collect();
                        let extra = bf.mycoparasites.len().saturating_sub(3);
                        let extra_str = if extra > 0 { format!(", +{} more", extra) } else { String::new() };
                        lines.push(format!(
                            "- **Disease-fighting fungi** ({} species): {}{} - These fungi attack and destroy plant pathogens like mildews and rusts.",
                            bf.mycoparasites.len(),
                            display.join(", "),
                            extra_str
                        ));
                    } else {
                        lines.push(format!(
                            "- **Disease-fighting fungi** ({} species): Attack and destroy plant pathogens like mildews and rusts.",
                            c.mycoparasites
                        ));
                    }
                } else {
                    lines.push(format!(
                        "- **Disease-fighting fungi** ({} species): Attack and destroy plant pathogens like mildews and rusts.",
                        c.mycoparasites
                    ));
                }
            }

            if c.entomopathogens > 0 {
                if let Some(bf) = beneficial_fungi {
                    if !bf.entomopathogens.is_empty() {
                        let display: Vec<&str> = bf.entomopathogens.iter().take(3).map(|s| s.as_str()).collect();
                        let extra = bf.entomopathogens.len().saturating_sub(3);
                        let extra_str = if extra > 0 { format!(", +{} more", extra) } else { String::new() };
                        lines.push(format!(
                            "- **Insect-killing fungi** ({} species): {}{} - Natural pest control agents that infect and kill harmful insects.",
                            bf.entomopathogens.len(),
                            display.join(", "),
                            extra_str
                        ));
                    } else {
                        lines.push(format!(
                            "- **Insect-killing fungi** ({} species): Natural pest control agents that infect and kill harmful insects.",
                            c.entomopathogens
                        ));
                    }
                } else {
                    lines.push(format!(
                        "- **Insect-killing fungi** ({} species): Natural pest control agents that infect and kill harmful insects.",
                        c.entomopathogens
                    ));
                }
            }
        }

        // Garden advice (only for documented mycorrhizal - absence of data ≠ absence of need)
        if matches!(myco_type, MycorrhizalType::AMF | MycorrhizalType::EMF | MycorrhizalType::Dual) {
            lines.push(String::new());
            lines.push("**Gardening tip**: Minimize soil disturbance to preserve beneficial fungal networks. Avoid excessive tilling and synthetic fertilizers which can harm mycorrhizal partnerships.".to_string());
        }
    } else {
        lines.push("No fungal association data available.".to_string());
    }

    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_with_counts() {
        let data = HashMap::new();
        let organisms = OrganismCounts {
            pollinators: 15,
            visitors: 20,
            herbivores: 8,
            pathogens: 3,
            predators: 5,
        };
        let fungi = FungalCounts {
            amf: 3,
            emf: 0,
            endophytes: 2,
            mycoparasites: 0,
            entomopathogens: 1,
            pathogenic: 5,
        };

        let output = generate(&data, Some(&organisms), Some(&fungi), None, None, None);
        assert!(output.contains("Pollinators"));
        assert!(output.contains("15 species"));
        assert!(output.contains("AMF"));
    }
}
