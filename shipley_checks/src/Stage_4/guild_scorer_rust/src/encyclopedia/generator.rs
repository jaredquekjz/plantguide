//! Encyclopedia Generator
//!
//! Main entry point for generating plant encyclopedia articles.
//! Orchestrates all six sections (S1-S6) to produce a complete markdown document.
//!
//! Public API (consumed by api_server.rs and generate_sample_encyclopedias.rs):
//! - EncyclopediaGenerator::new() -> Self
//! - EncyclopediaGenerator::generate(wfo_id, plant_data, organism_counts, fungal_counts) -> Result<String>

use std::collections::HashMap;
use serde_json::Value;
use chrono::Utc;

use crate::encyclopedia::types::{OrganismCounts, FungalCounts, OrganismProfile, RankedPathogen, BeneficialFungi};
use crate::encyclopedia::sections::{
    s1_identity,
    s2_requirements,
    s3_maintenance,
    s4_services,
    s5_interactions,
    s6_companion,
};

/// Encyclopedia generator - stateless markdown generator.
pub struct EncyclopediaGenerator;

impl EncyclopediaGenerator {
    /// Create a new encyclopedia generator.
    pub fn new() -> Self {
        Self
    }

    /// Generate a complete encyclopedia article for a plant.
    ///
    /// # Arguments
    /// * `wfo_id` - WFO taxon ID (e.g., "wfo-0001005999")
    /// * `plant_data` - HashMap of plant attributes from Phase 7 parquet
    /// * `organism_counts` - Optional organism interaction counts
    /// * `fungal_counts` - Optional fungal association counts
    /// * `organism_profile` - Optional categorized organism lists for rich display
    /// * `ranked_pathogens` - Optional pathogens with observation counts (top diseases)
    /// * `beneficial_fungi` - Optional beneficial fungi species (mycoparasites, entomopathogens)
    ///
    /// # Returns
    /// Complete markdown document as a String, or error message.
    pub fn generate(
        &self,
        wfo_id: &str,
        plant_data: &HashMap<String, Value>,
        organism_counts: Option<OrganismCounts>,
        fungal_counts: Option<FungalCounts>,
        organism_profile: Option<OrganismProfile>,
        ranked_pathogens: Option<Vec<RankedPathogen>>,
        beneficial_fungi: Option<BeneficialFungi>,
    ) -> Result<String, String> {
        let mut sections = Vec::new();

        // YAML frontmatter
        sections.push(generate_frontmatter(wfo_id, plant_data));

        // S1: Identity Card
        sections.push(s1_identity::generate(plant_data));

        // S2: Growing Requirements
        sections.push(s2_requirements::generate(plant_data));

        // S3: Maintenance Profile
        sections.push(s3_maintenance::generate(plant_data));

        // S4: Ecosystem Services
        sections.push(s4_services::generate(plant_data));

        // S5: Biological Interactions
        sections.push(s5_interactions::generate(
            plant_data,
            organism_counts.as_ref(),
            fungal_counts.as_ref(),
            organism_profile.as_ref(),
            ranked_pathogens.as_ref(),
            beneficial_fungi.as_ref(),
        ));

        // S6: Guild Potential (Companion Planting)
        sections.push(s6_companion::generate(
            plant_data,
            organism_counts.as_ref(),
            fungal_counts.as_ref(),
        ));

        // Footer
        sections.push(generate_footer(wfo_id));

        // Join with separators: frontmatter just needs blank line, other sections get ---
        let mut result = sections[0].clone(); // frontmatter (ends with ---)
        result.push_str("\n\n"); // blank line after frontmatter
        result.push_str(&sections[1]); // S1 identity

        for section in &sections[2..] {
            result.push_str("\n\n---\n\n");
            result.push_str(section);
        }
        Ok(result)
    }
}

impl Default for EncyclopediaGenerator {
    fn default() -> Self {
        Self::new()
    }
}

/// Generate YAML frontmatter with metadata.
fn generate_frontmatter(wfo_id: &str, data: &HashMap<String, Value>) -> String {
    let scientific_name = data
        .get("wfo_scientific_name")
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown");

    let family = data
        .get("family")
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown");

    let genus = data
        .get("genus")
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown");

    let now = Utc::now().format("%Y-%m-%dT%H:%M:%SZ");

    format!(
        r#"---
wfo_id: "{}"
scientific_name: "{}"
family: "{}"
genus: "{}"
generated: "{}"
version: "2.0"
---"#,
        wfo_id, scientific_name, family, genus, now
    )
}

/// Generate footer with data sources and links.
fn generate_footer(wfo_id: &str) -> String {
    format!(
        r#"## Data Sources

- **Taxonomy**: [World Flora Online](https://www.worldfloraonline.org/taxon/{})
- **Traits**: TRY Plant Trait Database
- **Climate/Soil**: WorldClim 2.1, SoilGrids 2.0
- **EIVE**: Dengler et al. (2023) Ellenberg-type Indicator Values for Europe
- **CSR Strategy**: Pierce et al. (2017) StrateFy global calibration
- **Biotic Interactions**: GloBI (Global Biotic Interactions)
- **Fungal Guilds**: FungalTraits, FunGuild

*Encyclopedia generated from the Ellenberg Plant Database*"#,
        wfo_id
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_minimal() {
        let generator = EncyclopediaGenerator::new();
        let mut data = HashMap::new();
        data.insert("wfo_scientific_name".to_string(), Value::String("Test species".to_string()));
        data.insert("family".to_string(), Value::String("Testaceae".to_string()));
        data.insert("genus".to_string(), Value::String("Testus".to_string()));

        let result = generator.generate("wfo-test", &data, None, None, None, None, None);
        assert!(result.is_ok());

        let content = result.unwrap();
        assert!(content.contains("Test species"));
        assert!(content.contains("Testaceae"));
        assert!(content.contains("Growing Requirements"));
        assert!(content.contains("Maintenance Profile"));
        assert!(content.contains("Ecosystem Services"));
        assert!(content.contains("Biological Interactions"));
        assert!(content.contains("Guild Potential"));
    }

    #[test]
    fn test_frontmatter() {
        let mut data = HashMap::new();
        data.insert("wfo_scientific_name".to_string(), Value::String("Quercus robur".to_string()));
        data.insert("family".to_string(), Value::String("Fagaceae".to_string()));
        data.insert("genus".to_string(), Value::String("Quercus".to_string()));

        let frontmatter = generate_frontmatter("wfo-0000455648", &data);
        assert!(frontmatter.contains("wfo_id: \"wfo-0000455648\""));
        assert!(frontmatter.contains("scientific_name: \"Quercus robur\""));
        assert!(frontmatter.contains("family: \"Fagaceae\""));
    }
}
