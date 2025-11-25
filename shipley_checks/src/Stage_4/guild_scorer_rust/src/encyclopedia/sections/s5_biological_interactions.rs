//! Section 5: Biological Interactions Summary
//!
//! Summarizes multi-trophic network data including pollinators, pests,
//! diseases, and beneficial organisms.
//!
//! Ported from R: shipley_checks/src/encyclopedia/sections/s5_biological_interactions.R

/// Organism interaction counts
#[derive(Debug, Clone)]
pub struct OrganismCounts {
    pub pollinators: usize,
    pub visitors: usize,
    pub herbivores: usize,
    pub pathogens: usize,
    pub predators: usize,
}

/// Fungal guild counts
#[derive(Debug, Clone)]
pub struct FungalCounts {
    pub amf: usize,  // Arbuscular mycorrhizal fungi
    pub emf: usize,  // Ectomycorrhizal fungi
    pub endophytes: usize,
    pub mycoparasites: usize,
    pub entomopathogens: usize,
}

/// Data for biological interactions section
pub struct BiologicalInteractionsData {
    pub organisms: Option<OrganismCounts>,
    pub fungi: Option<FungalCounts>,
    pub mycorrhiza_type: Option<String>,
}

/// Generate Section 5: Biological Interactions
pub fn generate_biological_interactions(data: &BiologicalInteractionsData) -> String {
    let mut sections = Vec::new();

    sections.push("## Biological Interactions".to_string());

    if data.organisms.is_none() && data.fungi.is_none() {
        sections.push("\n**Natural Relationships**: Data not available for this species".to_string());
        return sections.join("");
    }

    sections.push("\n**Natural Relationships**:".to_string());

    // Pollinators
    sections.push(format!("\n{}", generate_pollinator_summary(&data.organisms)));

    // Pest pressure
    sections.push(format!("\n{}", generate_pest_summary(&data.organisms, &data.fungi)));

    // Disease risk
    sections.push(format!("\n{}", generate_disease_summary(&data.organisms, &data.fungi)));

    // Beneficial fungi
    sections.push(format!("\n{}", generate_fungi_summary(&data.fungi, data.mycorrhiza_type.as_deref())));

    sections.join("")
}

fn generate_pollinator_summary(organisms: &Option<OrganismCounts>) -> String {
    let Some(org) = organisms else {
        return "🐝 **Pollinators**: Unknown pollination strategy\n   → May be wind-pollinated or self-fertile".to_string();
    };

    let total = org.pollinators + org.visitors;

    if total == 0 {
        return "🐝 **Pollinators**: Unknown pollination strategy\n   → May be wind-pollinated or self-fertile".to_string();
    }

    let (value, advice) = if total >= 20 {
        ("Excellent", "→ Plant in groups to maximize pollinator benefit\n   → Peak pollinator activity during flowering season")
    } else if total >= 10 {
        ("Good", "→ Attracts diverse pollinators\n   → Consider companion planting with other pollinator plants")
    } else if total >= 3 {
        ("Moderate", "→ Provides some pollinator support")
    } else {
        ("Limited", "→ Likely supplemented by generalist pollinators")
    };

    format!(
        "🐝 **Pollinators**: {} pollinator value ({} species documented)\n   {}",
        value, total, advice
    )
}

fn generate_pest_summary(organisms: &Option<OrganismCounts>, fungi: &Option<FungalCounts>) -> String {
    let herbivore_count = organisms.as_ref().map(|o| o.herbivores).unwrap_or(0);
    let predator_count = organisms.as_ref().map(|o| o.predators).unwrap_or(0);
    let entomopath_count = fungi.as_ref().map(|f| f.entomopathogens).unwrap_or(0);

    if herbivore_count == 0 {
        return "🐛 **Pest Pressure**: LOW - Few known pests\n   → Minimal pest management required".to_string();
    }

    let control_agents = predator_count + entomopath_count;
    let control_ratio = control_agents as f64 / herbivore_count as f64;

    let (level, advice) = if control_ratio >= 0.5 {
        ("LOW with excellent natural control",
         "→ Avoid chemical sprays to preserve beneficial predators\n   → Natural enemies provide good pest suppression")
    } else if control_ratio >= 0.2 {
        ("MODERATE with good natural control",
         "→ Monitor pests but rely on natural enemies first\n   → Avoid broad-spectrum pesticides")
    } else {
        ("MODERATE-HIGH",
         "→ Consider companion planting for additional pest control\n   → Use targeted organic controls if needed")
    };

    format!(
        "🐛 **Pest Pressure**: {}\n   {} known herbivore species\n   {} predator species + {} entomopathogenic fungi\n   {}",
        level, herbivore_count, predator_count, entomopath_count, advice
    )
}

fn generate_disease_summary(organisms: &Option<OrganismCounts>, fungi: &Option<FungalCounts>) -> String {
    let pathogen_count = organisms.as_ref().map(|o| o.pathogens).unwrap_or(0);
    let mycoparasite_count = fungi.as_ref().map(|f| f.mycoparasites).unwrap_or(0);

    if pathogen_count == 0 {
        return "🦠 **Disease Risk**: LOW - No major documented pathogens\n   → Minimal disease management required".to_string();
    }

    let control_ratio = mycoparasite_count as f64 / pathogen_count as f64;

    let (level, advice) = if control_ratio >= 0.3 {
        ("LOW",
         "→ Beneficial fungi provide natural disease suppression\n   → Avoid fungicides to preserve antagonists")
    } else if control_ratio >= 0.1 {
        ("MODERATE",
         "→ Ensure good air circulation and drainage\n   → Monitor for common fungal diseases")
    } else {
        ("MODERATE-HIGH",
         "→ Preventive measures recommended\n   → Ensure good drainage, avoid overhead watering\n   → Consider biocontrol inoculants (e.g., Trichoderma)")
    };

    format!(
        "🦠 **Disease Risk**: {}\n   {} documented pathogen species\n   {} antagonistic fungi available\n   {}",
        level, pathogen_count, mycoparasite_count, advice
    )
}

fn generate_fungi_summary(fungi: &Option<FungalCounts>, mycorrhiza_type: Option<&str>) -> String {
    let Some(f) = fungi else {
        return "🍄 **Beneficial Fungi**: Associations not well documented\n   → May benefit from general mycorrhizal inoculant".to_string();
    };

    let mycorrhiza_total = f.amf + f.emf;

    if mycorrhiza_total == 0 && f.endophytes == 0 {
        return "🍄 **Beneficial Fungi**: Associations not well documented\n   → May benefit from general mycorrhizal inoculant".to_string();
    }

    let (myco_type, myco_benefit, myco_advice) = if f.amf > 0 && f.emf == 0 {
        ("Arbuscular mycorrhizae (AMF)",
         "enhances water and phosphorus uptake",
         "Use AMF inoculant at planting")
    } else if f.emf > 0 && f.amf == 0 {
        ("Ectomycorrhizae (EMF)",
         "enhances nutrient uptake and drought resistance",
         "Use EMF inoculant for woody plants")
    } else if f.amf > 0 && f.emf > 0 {
        ("Mixed mycorrhizae",
         "versatile nutrient partnerships",
         "Use mixed mycorrhizal inoculant")
    } else {
        ("Mycorrhizal associations possible",
         "may enhance nutrient uptake",
         "Consider general mycorrhizal inoculant")
    };

    let endophyte_text = if f.endophytes > 0 {
        format!("\n   Endophytic fungi ({} species) - boost disease resistance", f.endophytes)
    } else {
        String::new()
    };

    format!(
        "🍄 **Beneficial Fungi**: Active soil partnerships\n   {} - {}{}\n   → {}\n   → Avoid fungicides; preserve soil biology",
        myco_type, myco_benefit, endophyte_text, myco_advice
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pollinator_summary_high() {
        let organisms = Some(OrganismCounts {
            pollinators: 25,
            visitors: 10,
            herbivores: 5,
            pathogens: 2,
            predators: 3,
        });
        let summary = generate_pollinator_summary(&organisms);
        assert!(summary.contains("Excellent"));
    }

    #[test]
    fn test_pest_summary_with_control() {
        let organisms = Some(OrganismCounts {
            pollinators: 5,
            visitors: 5,
            herbivores: 10,
            pathogens: 5,
            predators: 8,
        });
        let fungi = Some(FungalCounts {
            amf: 5,
            emf: 3,
            endophytes: 2,
            mycoparasites: 3,
            entomopathogens: 4,
        });
        let summary = generate_pest_summary(&organisms, &fungi);
        // 12 control agents / 10 herbivores = 1.2 ratio -> excellent control
        assert!(summary.contains("LOW") || summary.contains("natural control"));
    }

    #[test]
    fn test_fungi_summary_amf() {
        let fungi = Some(FungalCounts {
            amf: 5,
            emf: 0,
            endophytes: 2,
            mycoparasites: 1,
            entomopathogens: 1,
        });
        let summary = generate_fungi_summary(&fungi, None);
        assert!(summary.contains("AMF"));
    }
}
