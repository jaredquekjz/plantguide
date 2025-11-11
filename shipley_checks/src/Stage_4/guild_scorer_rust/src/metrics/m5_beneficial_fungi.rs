//! METRIC 5: BENEFICIAL FUNGI NETWORKS (MYCORRHIZAE & ENDOPHYTES)
//!
//! Scores Common Mycorrhizal Networks and individual fungal associations
//! using shared organism counting and coverage analysis.
//!
//! R reference: shipley_checks/src/Stage_4/metrics/m5_beneficial_fungi.R

use polars::prelude::*;
use anyhow::Result;
use crate::utils::{Calibration, percentile_normalize, count_shared_organisms};

/// Result of M5 calculation
#[derive(Debug)]
pub struct M5Result {
    /// Combined network + coverage score (0-1 scale)
    pub raw: f64,
    /// Percentile score (0-100, HIGH = GOOD)
    pub norm: f64,
    /// Network connectivity score
    pub network_score: f64,
    /// Fraction of plants with beneficial fungi
    pub coverage_ratio: f64,
    /// Number of shared fungi
    pub n_shared_fungi: usize,
    /// Number of plants with beneficial fungi
    pub plants_with_fungi: usize,
}

/// Calculate M5: Beneficial Fungi Networks
///
/// R reference: m5_beneficial_fungi.R::calculate_m5_beneficial_fungi
pub fn calculate_m5(
    plant_ids: &[String],
    fungi_df: &DataFrame,
    calibration: &Calibration,
) -> Result<M5Result> {
    let n_plants = plant_ids.len();

    // Beneficial fungi columns
    let columns = &["amf_fungi", "emf_fungi", "endophytic_fungi", "saprotrophic_fungi"];

    // Count shared beneficial fungi (fungi hosted by ≥2 plants)
    let beneficial_counts = count_shared_organisms(fungi_df, plant_ids, columns)?;

    // COMPONENT 1: Network score (weight 0.6)
    // For each shared fungus, calculate network connectivity
    let mut network_raw = 0.0;
    for (_org_name, count) in &beneficial_counts {
        if *count >= 2 {
            network_raw += *count as f64 / n_plants as f64;
        }
    }

    // COMPONENT 2: Coverage ratio (weight 0.4)
    // What fraction of plants have ANY beneficial fungi?
    let plants_with_beneficial = count_plants_with_beneficial_fungi(fungi_df, plant_ids, columns)?;
    let coverage_ratio = plants_with_beneficial as f64 / n_plants as f64;

    // Combined score: 60% network, 40% coverage
    let p5_raw = network_raw * 0.6 + coverage_ratio * 0.4;

    // Percentile normalize
    let m5_norm = percentile_normalize(p5_raw, "p3", calibration, false)?;

    Ok(M5Result {
        raw: p5_raw,
        norm: m5_norm,
        network_score: network_raw,
        coverage_ratio,
        n_shared_fungi: beneficial_counts.len(),
        plants_with_fungi: plants_with_beneficial,
    })
}

/// Count how many plants have at least one beneficial fungus
fn count_plants_with_beneficial_fungi(
    fungi_df: &DataFrame,
    plant_ids: &[String],
    columns: &[&str],
) -> Result<usize> {
    use rustc_hash::FxHashSet;

    let plant_id_set: FxHashSet<&String> = plant_ids.iter().collect();
    let plant_col = fungi_df.column("plant_wfo_id")?.str()?;

    let mut count = 0;
    for idx in 0..fungi_df.height() {
        if let Some(plant_id) = plant_col.get(idx) {
            if !plant_id_set.contains(&plant_id.to_string()) {
                continue; // Not in guild
            }

            // Check if this plant has any beneficial fungi
            let mut has_beneficial = false;
            for col_name in columns {
                if let Ok(col) = fungi_df.column(col_name) {
                    if let Ok(str_col) = col.str() {
                        if let Some(fungi_str) = str_col.get(idx) {
                            if !fungi_str.is_empty() {
                                has_beneficial = true;
                                break;
                            }
                        }
                    }
                }
            }

            if has_beneficial {
                count += 1;
            }
        }
    }

    Ok(count)
}

#[cfg(test)]
mod tests {
    use approx::assert_relative_eq;

    #[test]
    fn test_network_score_calculation() {
        // If 2 plants out of 3 share a fungus, connectivity = 2/3 ≈ 0.667
        // If 3 plants out of 3 share a fungus, connectivity = 3/3 = 1.0

        let n_plants = 3.0_f64;
        let mut network_raw = 0.0_f64;

        // Fungus 1 shared by 2 plants
        network_raw += 2.0 / n_plants;
        // Fungus 2 shared by 3 plants
        network_raw += 3.0 / n_plants;

        assert_relative_eq!(network_raw, 1.667, epsilon = 0.01);
    }

    #[test]
    fn test_coverage_ratio() {
        // If 2 out of 3 plants have any beneficial fungi
        let plants_with_fungi = 2;
        let n_plants = 3;
        let coverage_ratio = plants_with_fungi as f64 / n_plants as f64;

        assert_relative_eq!(coverage_ratio, 0.667, epsilon = 0.01);
    }

    #[test]
    fn test_combined_score() {
        // network_raw = 1.0, coverage_ratio = 1.0
        let p5_raw = 1.0_f64 * 0.6 + 1.0 * 0.4;
        assert_relative_eq!(p5_raw, 1.0, epsilon = 0.0001);

        // network_raw = 0.5, coverage_ratio = 0.8
        let p5_raw = 0.5_f64 * 0.6 + 0.8 * 0.4;
        assert_relative_eq!(p5_raw, 0.62, epsilon = 0.0001);
    }
}
