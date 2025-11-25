//! Section 7: Biodiversity Value (NEW)
//!
//! Composite index from organism/fungi richness and ecosystem services.

use crate::encyclopedia::sections::s5_biological_interactions::{OrganismCounts, FungalCounts};

/// Biodiversity value breakdown
pub struct BiodiversityBreakdown {
    pub pollinator_score: f64,    // 0-25
    pub herbivore_score: f64,     // 0-25 (food web support)
    pub predator_score: f64,      // 0-20 (natural enemy support)
    pub fungi_score: f64,         // 0-15 (soil partnerships)
    pub services_score: f64,      // 0-15 (ecosystem functions)
}

/// Data for biodiversity value section
pub struct BiodiversityValueData {
    pub organisms: Option<OrganismCounts>,
    pub fungi: Option<FungalCounts>,
    pub ecosystem_services_avg: Option<f64>, // Average of ecosystem service ratings
}

/// Generate Section 7: Biodiversity Value
pub fn generate_biodiversity_value(data: &BiodiversityValueData) -> String {
    let mut sections = Vec::new();

    sections.push("## Biodiversity Value".to_string());

    let breakdown = calculate_breakdown(data);
    let total_score = breakdown.pollinator_score
        + breakdown.herbivore_score
        + breakdown.predator_score
        + breakdown.fungi_score
        + breakdown.services_score;

    let (level, description) = if total_score >= 70.0 {
        ("HIGH", "Exceptional value for wildlife gardens and biodiversity support")
    } else if total_score >= 50.0 {
        ("MODERATE-HIGH", "Strong biodiversity value; supports diverse wildlife")
    } else if total_score >= 30.0 {
        ("MODERATE", "Provides useful biodiversity support")
    } else {
        ("LOW", "Limited documented biodiversity interactions")
    };

    sections.push(format!("\n**Overall Score: {:.0}/100 ({})**", total_score, level));
    sections.push(format!("\n*{}*", description));

    // Breakdown
    sections.push("\n\n**Score Breakdown**:".to_string());
    sections.push(format!("\n- Pollinator attraction: {:.0}/25", breakdown.pollinator_score));
    sections.push(format!("\n- Food web support (herbivores): {:.0}/25", breakdown.herbivore_score));
    sections.push(format!("\n- Natural enemy support: {:.0}/20", breakdown.predator_score));
    sections.push(format!("\n- Fungal partnerships: {:.0}/15", breakdown.fungi_score));
    sections.push(format!("\n- Ecosystem services: {:.0}/15", breakdown.services_score));

    // Best use recommendation
    let best_use = if total_score >= 70.0 {
        "Primary structure in wildlife/pollinator gardens"
    } else if breakdown.pollinator_score >= 15.0 {
        "Valuable addition to pollinator gardens"
    } else if breakdown.fungi_score >= 10.0 {
        "Good for soil health and mycorrhizal networks"
    } else {
        "General garden planting"
    };

    sections.push(format!("\n\n**Best Use**: {}", best_use));

    sections.join("")
}

fn calculate_breakdown(data: &BiodiversityValueData) -> BiodiversityBreakdown {
    let mut breakdown = BiodiversityBreakdown {
        pollinator_score: 0.0,
        herbivore_score: 0.0,
        predator_score: 0.0,
        fungi_score: 0.0,
        services_score: 0.0,
    };

    if let Some(ref org) = data.organisms {
        // Pollinator score: 0-25 based on total pollinators
        let total_pollinators = org.pollinators + org.visitors;
        breakdown.pollinator_score = (total_pollinators as f64 / 40.0 * 25.0).min(25.0);

        // Herbivore score: 0-25 (food web support - more herbivores = more food web connections)
        breakdown.herbivore_score = (org.herbivores as f64 / 100.0 * 25.0).min(25.0);

        // Predator score: 0-20 (natural enemies)
        breakdown.predator_score = (org.predators as f64 / 20.0 * 20.0).min(20.0);
    }

    if let Some(ref fungi) = data.fungi {
        // Fungi score: 0-15 based on beneficial fungi
        let beneficial = fungi.amf + fungi.emf + fungi.endophytes;
        breakdown.fungi_score = (beneficial as f64 / 15.0 * 15.0).min(15.0);
    }

    // Ecosystem services score: 0-15
    if let Some(avg) = data.ecosystem_services_avg {
        breakdown.services_score = (avg / 10.0 * 15.0).min(15.0);
    }

    breakdown
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_high_biodiversity() {
        let data = BiodiversityValueData {
            organisms: Some(OrganismCounts {
                pollinators: 30,
                visitors: 20,
                herbivores: 80,
                pathogens: 10,
                predators: 15,
            }),
            fungi: Some(FungalCounts {
                amf: 8,
                emf: 5,
                endophytes: 3,
                mycoparasites: 2,
                entomopathogens: 2,
            }),
            ecosystem_services_avg: Some(7.5),
        };
        let output = generate_biodiversity_value(&data);
        assert!(output.contains("HIGH") || output.contains("MODERATE-HIGH"));
    }

    #[test]
    fn test_low_biodiversity() {
        let data = BiodiversityValueData {
            organisms: Some(OrganismCounts {
                pollinators: 1,
                visitors: 1,
                herbivores: 2,
                pathogens: 1,
                predators: 0,
            }),
            fungi: None,
            ecosystem_services_avg: Some(3.0),
        };
        let output = generate_biodiversity_value(&data);
        assert!(output.contains("LOW") || output.contains("MODERATE"));
    }
}
