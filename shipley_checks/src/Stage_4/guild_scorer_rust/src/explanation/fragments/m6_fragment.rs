use crate::explanation::types::{BenefitCard, MetricFragment};
use crate::metrics::M6Result;

/// Generate explanation fragment for M6 (Structural Diversity)
///
/// Measures vertical layering and growth form diversity.
/// Higher scores indicate better space utilization through stratification.
/// Lower scores indicate less vertical diversity or fewer growth forms.
pub fn generate_m6_fragment(m6: &M6Result, display_score: f64) -> MetricFragment {
    let interpretation = if display_score >= 80.0 {
        "Excellent structural diversity - multiple layers maximize space and light use"
    } else if display_score >= 60.0 {
        "Good structural diversity - meaningful vertical layering supports diverse niches"
    } else if display_score >= 40.0 {
        "Moderate structural diversity - some layering present but coverage may be limited"
    } else {
        "Limited structural diversity - few layers or growth forms, less efficient space use"
    };

    // Always show structural diversity (even for low scores)
        let forms_text = if m6.n_forms == 1 {
            "form".to_string()
        } else {
            "forms".to_string()
        };

        // Build detailed stratification analysis
        let mut detail = format!(
            "**Vertical Stratification (Quality: {:.2} - {}):**\n\n",
            m6.stratification_quality,
            if m6.stratification_quality >= 0.8 { "Excellent" }
            else if m6.stratification_quality >= 0.6 { "Good" }
            else if m6.stratification_quality >= 0.4 { "Fair" }
            else { "Poor" }
        );

        if !m6.growth_form_groups.is_empty() {
            // Collect all plants and sort by height (tallest to shortest)
            let mut all_plants: Vec<&crate::metrics::m6_structural_diversity::PlantHeight> =
                m6.growth_form_groups.iter().flat_map(|g| g.plants.iter()).collect();
            all_plants.sort_by(|a, b| b.height_m.partial_cmp(&a.height_m).unwrap_or(std::cmp::Ordering::Equal));

            // Define layers
            let mut canopy = Vec::new();     // >15m
            let mut understory = Vec::new(); // 5-15m
            let mut shrub = Vec::new();      // 1-5m
            let mut ground = Vec::new();     // <1m

            for plant in &all_plants {
                if plant.height_m >= 15.0 {
                    canopy.push(plant);
                } else if plant.height_m >= 5.0 {
                    understory.push(plant);
                } else if plant.height_m >= 1.0 {
                    shrub.push(plant);
                } else {
                    ground.push(plant);
                }
            }

            // Format each layer
            let format_layer = |plants: &[&&crate::metrics::m6_structural_diversity::PlantHeight]| -> Vec<String> {
                plants.iter().map(|p| {
                    let light_info = match p.light_pref {
                        Some(l) => format!("EIVE-L: {:.1}", l),
                        None => "EIVE-L: N/A".to_string(),
                    };
                    format!("  - {}: {:.1}m, {} ({})",
                        p.name, p.height_m, light_info,
                        match p.light_pref {
                            Some(l) if l < 3.2 => "shade-tolerant ✓",
                            Some(l) if l > 7.47 => "sun-loving ⚠",
                            Some(_) => "flexible",
                            None => "unknown",
                        }
                    )
                }).collect()
            };

            if !canopy.is_empty() {
                detail.push_str("**Canopy Layer (>15m):**\n");
                detail.push_str(&format_layer(&canopy).join("\n"));
                detail.push_str("\n\n");
            }

            if !understory.is_empty() {
                detail.push_str("**Understory (5-15m):**\n");
                detail.push_str(&format_layer(&understory).join("\n"));
                detail.push_str("\n\n");
            }

            if !shrub.is_empty() {
                detail.push_str("**Shrub Layer (1-5m):**\n");
                detail.push_str(&format_layer(&shrub).join("\n"));
                detail.push_str("\n\n");
            }

            if !ground.is_empty() {
                detail.push_str("**Ground Layer (<1m):**\n");
                detail.push_str(&format_layer(&ground).join("\n"));
                detail.push_str("\n\n");
            }

            // Explain why stratification works or doesn't
            let shade_tolerant_count = all_plants.iter().filter(|p|
                p.light_pref.map_or(false, |l| l < 3.2)
            ).count();
            let flexible_count = all_plants.iter().filter(|p|
                p.light_pref.map_or(false, |l| l >= 3.2 && l <= 7.47)
            ).count();
            let sun_loving_count = all_plants.iter().filter(|p|
                p.light_pref.map_or(false, |l| l > 7.47)
            ).count();

            detail.push_str("**Why this stratification ");
            if m6.stratification_quality >= 0.8 {
                detail.push_str("works well:**\n");
            } else if m6.stratification_quality >= 0.6 {
                detail.push_str("is acceptable:**\n");
            } else {
                detail.push_str("has issues:**\n");
            }

            if shade_tolerant_count > 0 {
                let (plant_word, verb) = if shade_tolerant_count == 1 { ("plant", "is") } else { ("plants", "are") };
                detail.push_str(&format!("{} {} {} shade-tolerant (EIVE-L <3.2) and thrive under canopy. ",
                    shade_tolerant_count, plant_word, verb));
            }
            if flexible_count > 0 {
                let (plant_word, verb) = if flexible_count == 1 { ("plant", "is") } else { ("plants", "are") };
                detail.push_str(&format!("{} {} {} flexible (EIVE-L 3.2-7.47) and tolerate partial shade. ",
                    flexible_count, plant_word, verb));
            }
            if sun_loving_count > 0 {
                let (plant_word, verb) = if sun_loving_count == 1 { ("plant", "is") } else { ("plants", "are") };
                detail.push_str(&format!("⚠ {} {} {} sun-loving (EIVE-L >7.47) and may be shaded out by taller plants.",
                    sun_loving_count, plant_word, verb));
            } else {
                detail.push_str("No sun-loving plants that would be shaded out.");
            }
            detail.push_str("\n\n");
        } else {
            detail.push_str("Diverse plant structures create vertical stratification, maximizing space use, light capture, and habitat complexity.\n\n");
        }

        detail.push_str(&format!(
            "*Evidence:* Structural diversity score: {:.1}/100, stratification quality: {:.2}",
            display_score, m6.stratification_quality
        ));

        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "structural_diversity".to_string(),
            metric_code: "M6".to_string(),
            title: "Structural Diversity".to_string(),
            message: format!(
                "{} growth {} spanning {:.1}m height range ({}th percentile)",
                m6.n_forms, forms_text, m6.height_range,
                display_score.round() as i32
            ),
            detail: format!("{}\n\n{}", detail, interpretation),
            evidence: Some(format!(
                "Structural diversity score: {:.1}/100. Higher scores indicate more growth forms and better vertical stratification.",
                display_score
            )),
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_high_structural_diversity() {
        use crate::metrics::m6_structural_diversity::{GrowthFormGroup, PlantHeight};

        let m6 = M6Result {
            raw: 0.85,
            norm: 15.0,
            height_range: 8.5,
            n_forms: 5,
            stratification_quality: 0.82,
            form_diversity: 0.78,
            growth_form_groups: vec![
                GrowthFormGroup {
                    form_name: "Tree".to_string(),
                    plants: vec![
                        PlantHeight {
                            name: "Oak".to_string(),
                            height_m: 15.0,
                            light_pref: Some(6.5),  // flexible
                        },
                        PlantHeight {
                            name: "Beech".to_string(),
                            height_m: 12.0,
                            light_pref: Some(2.5),  // shade-tolerant
                        },
                    ],
                    height_range: (12.0, 15.0),
                },
            ],
        };
        let display_score = 85.0;

        let fragment = generate_m6_fragment(&m6, display_score);
        assert!(fragment.benefit.is_some());

        let benefit = fragment.benefit.unwrap();
        assert_eq!(benefit.metric_code, "M6");
        assert!(benefit.message.contains("5 growth forms"));
        assert!(benefit.message.contains("8.5m height range"));
        assert!(benefit.detail.contains("(flexible)"));
        assert!(benefit.detail.contains("(shade-tolerant"));
    }

    #[test]
    fn test_single_form() {
        let m6 = M6Result {
            raw: 0.6,
            norm: 40.0,
            height_range: 2.5,
            n_forms: 1,
            stratification_quality: 0.55,
            form_diversity: 0.0,
            growth_form_groups: vec![],
        };
        let display_score = 60.0;

        let fragment = generate_m6_fragment(&m6, display_score);
        assert!(fragment.benefit.is_some());

        let benefit = fragment.benefit.unwrap();
        assert!(benefit.message.contains("1 growth form"));
        assert!(benefit.message.contains("2.5m height range"));
    }

    #[test]
    fn test_low_structural_diversity() {
        let m6 = M6Result {
            raw: 0.3,
            norm: 70.0,
            height_range: 1.2,
            n_forms: 2,
            stratification_quality: 0.25,
            form_diversity: 0.3,
            growth_form_groups: vec![],
        };
        let display_score = 30.0;

        let fragment = generate_m6_fragment(&m6, display_score);
        assert!(fragment.benefit.is_none());
    }
}
