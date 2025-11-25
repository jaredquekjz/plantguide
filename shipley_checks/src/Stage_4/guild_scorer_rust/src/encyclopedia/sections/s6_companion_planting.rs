//! Section 6: Companion Planting (NEW)
//!
//! Guild compatibility scores and specific plant recommendations.
//! Uses guild scoring M1-M7 metrics and EIVE similarity.

/// Companion plant recommendation
pub struct CompanionRecommendation {
    pub wfo_id: String,
    pub scientific_name: String,
    pub compatibility_score: f64,
    pub benefits: Vec<String>,
}

/// Data for companion planting section
pub struct CompanionPlantingData {
    pub top_companions: Vec<CompanionRecommendation>,
    pub plants_to_avoid: Vec<CompanionRecommendation>,
}

/// Generate Section 6: Companion Planting
///
/// Note: This is a placeholder. Full implementation requires:
/// 1. Pre-computed companion scores (expensive to calculate on-the-fly)
/// 2. Integration with guild scoring M1-M7 metrics
/// 3. Similar plants lookup via EIVE distance
pub fn generate_companion_planting(data: &CompanionPlantingData) -> String {
    let mut sections = Vec::new();

    sections.push("## Companion Planting".to_string());

    if data.top_companions.is_empty() {
        sections.push("\n*Companion planting recommendations not yet available for this species.*".to_string());
        return sections.join("");
    }

    sections.push("\n**Recommended Companions**:".to_string());

    for (i, companion) in data.top_companions.iter().take(5).enumerate() {
        let benefits = if companion.benefits.is_empty() {
            "Compatible growing requirements".to_string()
        } else {
            companion.benefits.join("; ")
        };

        sections.push(format!(
            "\n{}. **{}** (score: {:.0}/100)\n   → {}",
            i + 1,
            companion.scientific_name,
            companion.compatibility_score,
            benefits
        ));
    }

    if !data.plants_to_avoid.is_empty() {
        sections.push("\n\n**Plants to Avoid**:".to_string());
        for companion in data.plants_to_avoid.iter().take(3) {
            sections.push(format!(
                "\n- {} (potential competition or incompatibility)",
                companion.scientific_name
            ));
        }
    }

    sections.join("")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_companions() {
        let data = CompanionPlantingData {
            top_companions: vec![],
            plants_to_avoid: vec![],
        };
        let output = generate_companion_planting(&data);
        assert!(output.contains("not yet available"));
    }

    #[test]
    fn test_with_companions() {
        let data = CompanionPlantingData {
            top_companions: vec![
                CompanionRecommendation {
                    wfo_id: "wfo-123".to_string(),
                    scientific_name: "Companion plant".to_string(),
                    compatibility_score: 85.0,
                    benefits: vec!["Shared pollinators".to_string()],
                },
            ],
            plants_to_avoid: vec![],
        };
        let output = generate_companion_planting(&data);
        assert!(output.contains("Companion plant"));
        assert!(output.contains("85"));
    }
}
