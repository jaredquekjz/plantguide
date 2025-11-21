use crate::explanation::types::{Severity, WarningCard};
use anyhow::Result;
use polars::prelude::*;
use serde::{Deserialize, Serialize};
use crate::utils::get_display_name;

/// EIVE R semantic binning from Dengler et al. 2023, Hill et al. 1999
/// Source: src/Stage_3/generate_100_plants_evaluation.py EIVE_SCALES['R']
const PH_BINS: [(f64, f64, &str); 6] = [
    (0.0, 2.0, "Strongly Acidic (pH 3-4)"),
    (2.0, 4.0, "Acidic (pH 4-5)"),
    (4.0, 5.5, "Slightly Acidic (pH 5-6)"),
    (5.5, 7.0, "Neutral (pH 6-7)"),
    (7.0, 8.5, "Alkaline (pH 7-8)"),
    (8.5, 10.0, "Strongly Alkaline (pH >8)"),
];

/// pH category for a plant
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhCategory {
    pub plant_name: String,
    pub r_value: f64,
    pub category: String,
}

/// pH compatibility warning with EIVE semantic binning
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhCompatibilityWarning {
    pub severity: Severity,
    pub r_range: f64,
    pub min_r: f64,
    pub max_r: f64,
    pub plant_categories: Vec<PhCategory>,
    pub recommendation: String,
}

/// Get pH category from EIVE R value
fn get_ph_category(r_value: f64) -> &'static str {
    for (lower, upper, label) in PH_BINS.iter() {
        if r_value >= *lower && r_value < *upper {
            return label;
        }
    }
    // Handle edge case: values >= 10.0 fall into last bin
    PH_BINS.last().unwrap().2
}

/// Check soil pH compatibility using EIVE semantic binning
///
/// Returns warning if pH preferences differ by >1 EIVE unit
pub fn check_soil_ph_compatibility(guild_plants: &DataFrame) -> Result<Option<WarningCard>> {
    let detailed = check_ph_compatibility(guild_plants)?;

    if let Some(warning_data) = detailed {
        // Convert to WarningCard format
        let severity_icon = match warning_data.severity {
            Severity::High => "🚨",
            Severity::Medium => "⚠️",
            Severity::Low => "⚡",
            _ => "ℹ️",
        };

        let categories_list: Vec<String> = warning_data.plant_categories
            .iter()
            .map(|p| format!("{}: {}", p.plant_name, p.category))
            .collect();

        let detail = format!(
            "EIVE R range: {:.1}-{:.1} (difference: {:.1} units)\n\nPlant pH preferences:\n{}",
            warning_data.min_r,
            warning_data.max_r,
            warning_data.r_range,
            categories_list.join("\n")
        );

        Ok(Some(WarningCard {
            warning_type: "ph_incompatible".to_string(),
            severity: warning_data.severity,
            icon: severity_icon.to_string(),
            message: "Soil pH incompatibility detected".to_string(),
            detail,
            advice: warning_data.recommendation,
        }))
    } else {
        Ok(None)
    }
}

/// Check pH compatibility and return detailed information
pub fn check_ph_compatibility(guild_plants: &DataFrame) -> Result<Option<PhCompatibilityWarning>> {
    // Check if soil_reaction_eive column exists
    if let Ok(r_col) = guild_plants.column("soil_reaction_eive") {
        let r_values = r_col.f64()?;

        // Get plant names
        let names = if let Ok(name_col) = guild_plants.column("wfo_taxon_name") {
            name_col.str()?
        } else if let Ok(id_col) = guild_plants.column("wfo_taxon_id") {
            id_col.str()?
        } else {
            return Ok(None);
        };

        // Try to get pre-computed display_name (preferred) or fallback to vernacular columns
        let display_name_col = guild_plants.column("display_name").ok().and_then(|c| c.str().ok());
        let vernacular_en = guild_plants.column("vernacular_name_en").ok().and_then(|c| c.str().ok());
        let vernacular_zh = guild_plants.column("vernacular_name_zh").ok().and_then(|c| c.str().ok());

        // Build plant categories
        let mut plant_categories = Vec::new();
        for idx in 0..guild_plants.height() {
            if let (Some(name), Some(r)) = (names.get(idx), r_values.get(idx)) {
                // Try optimized path first (display_name column), fallback to runtime normalization
                let display_name = if let Some(col) = display_name_col {
                    if let Some(d) = col.get(idx) {
                        crate::utils::get_display_name_optimized(name, Some(d))
                    } else {
                        let en = vernacular_en.and_then(|c| c.get(idx));
                        let zh = vernacular_zh.and_then(|c| c.get(idx));
                        get_display_name(name, en, zh)
                    }
                } else {
                    let en = vernacular_en.and_then(|c| c.get(idx));
                    let zh = vernacular_zh.and_then(|c| c.get(idx));
                    get_display_name(name, en, zh)
                };
                
                plant_categories.push(PhCategory {
                    plant_name: display_name,
                    r_value: r,
                    category: get_ph_category(r).to_string(),
                });
            }
        }

        if plant_categories.is_empty() {
            return Ok(None);
        }

        // Calculate range
        let min_r = plant_categories.iter().map(|p| p.r_value).fold(f64::INFINITY, f64::min);
        let max_r = plant_categories.iter().map(|p| p.r_value).fold(f64::NEG_INFINITY, f64::max);
        let r_range = max_r - min_r;

        // Check if range > 1.0 EIVE unit
        if r_range > 1.0 {
            let severity = if r_range > 3.0 {
                Severity::High
            } else if r_range > 2.0 {
                Severity::Medium
            } else {
                Severity::Low
            };

            let recommendation = match severity {
                Severity::High => {
                    "Strong pH incompatibility. Consider separating plants into distinct beds with appropriate soil amendments.".to_string()
                },
                Severity::Medium => {
                    "Moderate pH incompatibility. Use soil amendments to adjust pH for different zones.".to_string()
                },
                Severity::Low => {
                    "Minor pH incompatibility. Monitor plant health and adjust soil pH as needed.".to_string()
                },
                _ => "Monitor pH levels.".to_string(),
            };

            Ok(Some(PhCompatibilityWarning {
                severity,
                r_range,
                min_r,
                max_r,
                plant_categories,
                recommendation,
            }))
        } else {
            Ok(None)
        }
    } else {
        Ok(None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use polars::prelude::*;

    #[test]
    fn test_get_ph_category() {
        assert_eq!(get_ph_category(1.5), "Strongly Acidic (pH 3-4)");
        assert_eq!(get_ph_category(3.0), "Acidic (pH 4-5)");
        assert_eq!(get_ph_category(5.0), "Slightly Acidic (pH 5-6)");
        assert_eq!(get_ph_category(6.0), "Neutral (pH 6-7)");
        assert_eq!(get_ph_category(7.5), "Alkaline (pH 7-8)");
        assert_eq!(get_ph_category(9.0), "Strongly Alkaline (pH >8)");
    }

    #[test]
    fn test_incompatible_ph_high_severity() {
        let df = df! {
            "wfo_taxon_id" => &["plant1", "plant2", "plant3"],
            "wfo_taxon_name" => &["Acidic Plant", "Alkaline Plant", "Neutral Plant"],
            "soil_reaction_eive" => &[2.5, 7.8, 5.2]  // Range: 5.3 > 3.0
        }
        .unwrap();

        let warning = check_soil_ph_compatibility(&df).unwrap();
        assert!(warning.is_some());

        let w = warning.unwrap();
        assert_eq!(w.warning_type, "ph_incompatible");
        assert_eq!(w.severity as u8, Severity::High as u8);
        assert!(w.detail.contains("2.5-7.8"));
        assert!(w.detail.contains("Acidic (pH 4-5)"));
        assert!(w.detail.contains("Alkaline (pH 7-8)"));
    }

    #[test]
    fn test_incompatible_ph_medium_severity() {
        let df = df! {
            "wfo_taxon_id" => &["plant1", "plant2"],
            "wfo_taxon_name" => &["Plant A", "Plant B"],
            "soil_reaction_eive" => &[4.0, 6.5]  // Range: 2.5 (Medium)
        }
        .unwrap();

        let warning = check_soil_ph_compatibility(&df).unwrap();
        assert!(warning.is_some());

        let w = warning.unwrap();
        assert_eq!(w.severity as u8, Severity::Medium as u8);
    }

    #[test]
    fn test_incompatible_ph_low_severity() {
        let df = df! {
            "wfo_taxon_id" => &["plant1", "plant2"],
            "wfo_taxon_name" => &["Plant A", "Plant B"],
            "soil_reaction_eive" => &[5.5, 7.0]  // Range: 1.5 (Low)
        }
        .unwrap();

        let warning = check_soil_ph_compatibility(&df).unwrap();
        assert!(warning.is_some());

        let w = warning.unwrap();
        assert_eq!(w.severity as u8, Severity::Low as u8);
    }

    #[test]
    fn test_compatible_ph() {
        let df = df! {
            "wfo_taxon_id" => &["plant1", "plant2", "plant3"],
            "soil_reaction_eive" => &[6.0, 6.5, 6.8]  // Range: 0.8 < 1.0
        }
        .unwrap();

        let warning = check_soil_ph_compatibility(&df).unwrap();
        assert!(warning.is_none());
    }

    #[test]
    fn test_no_ph_data() {
        let df = df! {
            "wfo_taxon_id" => &["plant1", "plant2", "plant3"]
        }
        .unwrap();

        let warning = check_soil_ph_compatibility(&df).unwrap();
        assert!(warning.is_none());
    }

    #[test]
    fn test_missing_ph_values() {
        let df = df! {
            "wfo_taxon_id" => &["plant1", "plant2", "plant3"],
            "soil_reaction_eive" => &[None::<f64>, None, None]
        }
        .unwrap();

        let warning = check_soil_ph_compatibility(&df).unwrap();
        assert!(warning.is_none());
    }
}
