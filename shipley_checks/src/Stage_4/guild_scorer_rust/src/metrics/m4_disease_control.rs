//! METRIC 4: DISEASE SUPPRESSION (ANTAGONIST FUNGI)
//!
//! Scores fungal disease control provided by mycoparasitic fungi.
//! Uses pairwise analysis to identify protective relationships
//! between vulnerable (disease-prone) and protective (mycoparasite-hosting) plants.
//!
//! R reference: shipley_checks/src/Stage_4/metrics/m4_disease_control.R

use polars::prelude::*;
use rustc_hash::{FxHashMap, FxHashSet};
use anyhow::Result;
use crate::utils::{Calibration, percentile_normalize};

/// Result of M4 calculation
#[derive(Debug)]
pub struct M4Result {
    /// Normalized pathogen control score (scaled by guild size)
    pub raw: f64,
    /// Percentile score (0-100, HIGH = GOOD)
    pub norm: f64,
    /// Total pathogen control before normalization
    pub pathogen_control_raw: f64,
    /// Number of mechanisms detected
    pub n_mechanisms: usize,
}

/// Calculate M4: Disease Suppression (Antagonist Fungi)
///
/// R reference: m4_disease_control.R::calculate_m4_disease_control
pub fn calculate_m4(
    plant_ids: &[String],
    fungi_df: &DataFrame,
    pathogen_antagonists: &FxHashMap<String, Vec<String>>,
    calibration: &Calibration,
) -> Result<M4Result> {
    let n_plants = plant_ids.len();
    let mut pathogen_control_raw = 0.0;
    let mut n_mechanisms = 0;

    // Extract guild fungi data
    let guild_fungi = filter_to_guild(fungi_df, plant_ids, "plant_wfo_id")?;

    if guild_fungi.height() == 0 {
        return Ok(M4Result {
            raw: 0.0,
            norm: 0.0,
            pathogen_control_raw: 0.0,
            n_mechanisms: 0,
        });
    }

    // Extract fungi data into structured format
    let plant_pathogens = extract_column_data(&guild_fungi, "pathogenic_fungi")?;
    let plant_mycoparasites = extract_column_data(&guild_fungi, "mycoparasite_fungi")?;

    // Pairwise analysis: vulnerable plant A vs protective plant B
    for (plant_a_id, pathogens_a) in &plant_pathogens {
        if pathogens_a.is_empty() {
            continue; // Skip plants with no pathogens
        }

        for (plant_b_id, mycoparasites_b) in &plant_mycoparasites {
            if plant_a_id == plant_b_id || mycoparasites_b.is_empty() {
                continue; // Skip self-comparison and plants without mycoparasites
            }

            // MECHANISM 1: Specific antagonist matches (weight 1.0) - RARELY FIRES
            for pathogen in pathogens_a {
                if let Some(known_antagonists) = pathogen_antagonists.get(pathogen) {
                    let matches = count_matches(mycoparasites_b, known_antagonists);
                    if matches > 0 {
                        pathogen_control_raw += matches as f64 * 1.0;
                        n_mechanisms += 1;
                    }
                }
            }

            // MECHANISM 2: General mycoparasites (weight 1.0) - PRIMARY MECHANISM
            // If plant A has any pathogens AND plant B has any mycoparasites
            pathogen_control_raw += mycoparasites_b.len() as f64 * 1.0;
            n_mechanisms += 1;
        }
    }

    // Normalize by guild size
    let max_pairs = n_plants * (n_plants - 1);
    let pathogen_control_normalized = if max_pairs > 0 {
        pathogen_control_raw / max_pairs as f64 * 10.0
    } else {
        0.0
    };

    // Percentile normalization
    let m4_norm = percentile_normalize(pathogen_control_normalized, "p2", calibration, false)?;

    Ok(M4Result {
        raw: pathogen_control_normalized,
        norm: m4_norm,
        pathogen_control_raw,
        n_mechanisms,
    })
}

/// Filter DataFrame to guild plants
fn filter_to_guild(df: &DataFrame, plant_ids: &[String], col: &str) -> Result<DataFrame> {
    let plant_id_set: FxHashSet<&String> = plant_ids.iter().collect();
    let plant_col = df.column(col)?.str()?;
    let mask: BooleanChunked = plant_col
        .into_iter()
        .map(|opt| opt.map_or(false, |s| plant_id_set.contains(&s.to_string())))
        .collect();
    Ok(df.filter(&mask)?)
}

/// Extract single column data: plant_id → list of fungi
fn extract_column_data(
    df: &DataFrame,
    col_name: &str,
) -> Result<FxHashMap<String, Vec<String>>> {
    let mut map: FxHashMap<String, Vec<String>> = FxHashMap::default();

    let plant_ids = df.column("plant_wfo_id")?.str()?;

    if let Ok(col) = df.column(col_name) {
        if let Ok(str_col) = col.str() {
            for idx in 0..df.height() {
                if let (Some(plant_id), Some(fungi_str)) = (plant_ids.get(idx), str_col.get(idx)) {
                    let fungi: Vec<String> = fungi_str
                        .split('|')
                        .filter(|s| !s.is_empty())
                        .map(|s| s.to_string())
                        .collect();

                    if !fungi.is_empty() {
                        map.insert(plant_id.to_string(), fungi);
                    }
                }
            }
        }
    }

    Ok(map)
}

/// Count how many elements from list_a are in list_b
fn count_matches(list_a: &[String], list_b: &[String]) -> usize {
    let set_b: FxHashSet<&String> = list_b.iter().collect();
    list_a.iter().filter(|item| set_b.contains(item)).count()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_count_matches() {
        let list_a = vec!["fungus1".to_string(), "fungus2".to_string()];
        let list_b = vec!["fungus2".to_string(), "fungus3".to_string()];

        assert_eq!(count_matches(&list_a, &list_b), 1);
    }

    #[test]
    fn test_count_matches_none() {
        let list_a = vec!["fungus1".to_string()];
        let list_b = vec!["fungus2".to_string()];

        assert_eq!(count_matches(&list_a, &list_b), 0);
    }

    #[test]
    fn test_count_matches_multiple() {
        let list_a = vec!["f1".to_string(), "f2".to_string(), "f3".to_string()];
        let list_b = vec!["f1".to_string(), "f2".to_string(), "f4".to_string()];

        assert_eq!(count_matches(&list_a, &list_b), 2);
    }
}
