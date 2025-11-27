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
    lines.push(format!("**{}** ({} taxa documented)", level, count));
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
    lines.push(format!("**{}** ({} taxa documented)", level, count));
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

    lines.push(format!("**{} taxa documented** - natural pest control agents", count));

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

    lines.push(format!("**Disease Risk**: {} ({} taxa observed)", level, pathogen_count));
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
    lines.push("### Beneficial Associations".to_string());

    if let Some(c) = counts {
        // Mycorrhizal associations
        let myco_type = classify_mycorrhizal(c.amf, c.emf);

        lines.push(format!("**Mycorrhizal**: {}", myco_type.label()));

        if c.amf > 0 {
            lines.push(format!("- {} AMF species observed (aids phosphorus uptake)", c.amf));
        }
        if c.emf > 0 {
            lines.push(format!("- {} EMF species observed (nutrient + defense signaling)", c.emf));
        }
        if c.endophytes > 0 {
            lines.push(format!("- {} endophytic fungi observed (often protective)", c.endophytes));
        }

        // Biocontrol fungi with species names
        let has_biocontrol = c.mycoparasites > 0 || c.entomopathogens > 0;
        if has_biocontrol {
            lines.push(String::new());
            lines.push("**Biocontrol Fungi**:".to_string());

            // Display mycoparasites with species names
            if c.mycoparasites > 0 {
                if let Some(bf) = beneficial_fungi {
                    if !bf.mycoparasites.is_empty() {
                        let display: Vec<&str> = bf.mycoparasites.iter().take(3).map(|s| s.as_str()).collect();
                        let extra = bf.mycoparasites.len().saturating_sub(3);
                        let extra_str = if extra > 0 { format!(", +{} more", extra) } else { String::new() };
                        lines.push(format!(
                            "- **Mycoparasites** ({}): {}{}",
                            bf.mycoparasites.len(),
                            display.join(", "),
                            extra_str
                        ));
                    } else {
                        lines.push(format!(
                            "- {} mycoparasitic fungi observed (attack plant diseases)",
                            c.mycoparasites
                        ));
                    }
                } else {
                    lines.push(format!(
                        "- {} mycoparasitic fungi observed (attack plant diseases)",
                        c.mycoparasites
                    ));
                }
            }

            // Display entomopathogens with species names
            if c.entomopathogens > 0 {
                if let Some(bf) = beneficial_fungi {
                    if !bf.entomopathogens.is_empty() {
                        let display: Vec<&str> = bf.entomopathogens.iter().take(3).map(|s| s.as_str()).collect();
                        let extra = bf.entomopathogens.len().saturating_sub(3);
                        let extra_str = if extra > 0 { format!(", +{} more", extra) } else { String::new() };
                        lines.push(format!(
                            "- **Insect-Killing Fungi** ({}): {}{}",
                            bf.entomopathogens.len(),
                            display.join(", "),
                            extra_str
                        ));
                    } else {
                        lines.push(format!(
                            "- {} insect-killing fungi observed (natural pest control)",
                            c.entomopathogens
                        ));
                    }
                } else {
                    lines.push(format!(
                        "- {} insect-killing fungi observed (natural pest control)",
                        c.entomopathogens
                    ));
                }
            }
        }

        // Garden advice
        lines.push(String::new());
        match myco_type {
            MycorrhizalType::AMF | MycorrhizalType::EMF | MycorrhizalType::Dual => {
                lines.push("*Avoid excessive tillage to preserve mycorrhizal networks*".to_string());
            }
            MycorrhizalType::NonMycorrhizal => {
                lines.push("*No documented mycorrhizal associations*".to_string());
            }
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
        assert!(output.contains("15 taxa"));
        assert!(output.contains("AMF"));
    }
}
