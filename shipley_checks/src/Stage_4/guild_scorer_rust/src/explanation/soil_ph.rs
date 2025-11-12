use crate::explanation::types::{Severity, WarningCard};
use anyhow::Result;
use polars::prelude::*;

/// Check soil pH compatibility of guild
///
/// Returns warning if pH preferences differ by >2 units (incompatible)
pub fn check_soil_ph_compatibility(guild_plants: &DataFrame) -> Result<Option<WarningCard>> {
    // Check if soil_reaction_eive column exists
    if let Ok(col) = guild_plants.column("soil_reaction_eive") {
        let ph_prefs: Vec<f64> = col
            .f64()?
            .into_iter()
            .flatten()
            .collect();

        if ph_prefs.is_empty() {
            return Ok(None);
        }

        let min_ph = ph_prefs.iter().copied().fold(f64::INFINITY, f64::min);
        let max_ph = ph_prefs.iter().copied().fold(f64::NEG_INFINITY, f64::max);
        let ph_range = max_ph - min_ph;

        // pH range > 2 units = incompatible (e.g., acid-loving vs alkaline-preferring)
        if ph_range > 2.0 {
            Ok(Some(WarningCard {
                warning_type: "ph_incompatible".to_string(),
                severity: Severity::High,
                icon: "🚨".to_string(),
                message: "Incompatible soil pH preferences detected".to_string(),
                detail: format!(
                    "pH range: {:.1}-{:.1} (difference: {:.1} units)",
                    min_ph, max_ph, ph_range
                ),
                advice: "Group acid-loving and alkaline-preferring plants separately".to_string(),
            }))
        } else {
            Ok(None)
        }
    } else {
        // Column doesn't exist - no pH data available
        Ok(None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use polars::prelude::*;

    #[test]
    fn test_incompatible_ph() {
        let df = df! {
            "wfo_taxon_id" => &["plant1", "plant2", "plant3"],
            "soil_reaction_eive" => &[4.5, 7.8, 5.2]  // Range: 3.3 > 2.0
        }
        .unwrap();

        let warning = check_soil_ph_compatibility(&df).unwrap();
        assert!(warning.is_some());

        let w = warning.unwrap();
        assert_eq!(w.warning_type, "ph_incompatible");
        assert_eq!(w.severity as u8, Severity::High as u8);
        assert!(w.detail.contains("4.5-7.8"));
    }

    #[test]
    fn test_compatible_ph() {
        let df = df! {
            "wfo_taxon_id" => &["plant1", "plant2", "plant3"],
            "soil_reaction_eive" => &[6.0, 6.5, 7.5]  // Range: 1.5 < 2.0
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
