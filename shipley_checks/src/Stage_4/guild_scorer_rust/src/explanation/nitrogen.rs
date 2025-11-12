use crate::explanation::types::{Severity, WarningCard};
use anyhow::Result;
use polars::prelude::*;

/// Check nitrogen fixation status of guild
///
/// Returns warning if >2 nitrogen-fixing plants (risk of over-fertilization)
pub fn check_nitrogen_fixation(guild_plants: &DataFrame) -> Result<Option<WarningCard>> {
    // Check if nitrogen_fixation column exists
    if let Ok(col) = guild_plants.column("nitrogen_fixation") {
        let n_fixers = col
            .str()?
            .into_iter()
            .filter(|opt| opt.map_or(false, |s| s == "Yes" || s == "yes" || s == "Y"))
            .count();

        if n_fixers > 2 {
            Ok(Some(WarningCard {
                warning_type: "nitrogen_excess".to_string(),
                severity: Severity::Medium,
                icon: "⚠️".to_string(),
                message: format!("{} nitrogen-fixing plants may over-fertilize", n_fixers),
                detail: "Excess nitrogen can favor fast-growing weeds and reduce soil biodiversity".to_string(),
                advice: "Reduce to 1-2 nitrogen fixers or add nitrogen-demanding plants".to_string(),
            }))
        } else {
            Ok(None)
        }
    } else {
        // Column doesn't exist - no nitrogen data available
        Ok(None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use polars::prelude::*;

    #[test]
    fn test_excess_nitrogen() {
        let df = df! {
            "wfo_taxon_id" => &["plant1", "plant2", "plant3", "plant4"],
            "nitrogen_fixation" => &["Yes", "Yes", "Yes", "No"]
        }
        .unwrap();

        let warning = check_nitrogen_fixation(&df).unwrap();
        assert!(warning.is_some());

        let w = warning.unwrap();
        assert_eq!(w.warning_type, "nitrogen_excess");
        assert!(w.message.contains("3 nitrogen-fixing plants"));
    }

    #[test]
    fn test_moderate_nitrogen() {
        let df = df! {
            "wfo_taxon_id" => &["plant1", "plant2", "plant3"],
            "nitrogen_fixation" => &["Yes", "Yes", "No"]
        }
        .unwrap();

        let warning = check_nitrogen_fixation(&df).unwrap();
        assert!(warning.is_none());
    }

    #[test]
    fn test_no_nitrogen_data() {
        let df = df! {
            "wfo_taxon_id" => &["plant1", "plant2", "plant3"]
        }
        .unwrap();

        let warning = check_nitrogen_fixation(&df).unwrap();
        assert!(warning.is_none());
    }
}
