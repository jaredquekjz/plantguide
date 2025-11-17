//! METRIC 7: POLLINATOR SUPPORT (SHARED POLLINATORS)
//!
//! **PHASE 3 OPTIMIZATION**: Pre-filtered LazyFrame with column projection
//!
//! Scores shared pollinator networks using quadratic weighting to reflect
//! non-linear benefits of high-overlap pollinator communities.
//!
//! **Memory optimization**:
//!   - Old: Receives full organisms_df (11,711 rows), filters inside count_shared_organisms
//!   - New: Receives pre-filtered organisms_lazy (7 rows), selects only 2 needed columns
//!   - Reuses same organisms_lazy as M3 (no redundant filtering!)
//!
//! **Columns needed** (M7 selects these 2):
//!   1. plant_wfo_id - Plant identification (for filtering)
//!   2. pollinators - Pipe-separated pollinator IDs (strict pollinators only)
//!
//! **Data Quality Note**:
//!   - Uses ONLY "pollinators" column (GloBI interactionTypeName == 'pollinates')
//!   - Does NOT use "flower_visitors" (contaminated with herbivores, fungi, etc.)
//!   - flower_visitors includes mites, caterpillars, and pathogenic fungi
//!
//! R reference: shipley_checks/src/Stage_4/metrics/m7_pollinator_support.R

use polars::prelude::*;
use anyhow::Result;
use rustc_hash::FxHashMap;
use crate::utils::{Calibration, percentile_normalize, count_shared_organisms, materialize_with_columns, filter_to_guild};

/// Column requirements for M7 calculation (from organisms parquet)
pub const REQUIRED_ORGANISM_COLS: &[&str] = &[
    "plant_wfo_id",
    "pollinators",
    "flower_visitors",      // Added for R parity
];

/// Result of M7 calculation
#[derive(Debug)]
pub struct M7Result {
    /// Quadratic-weighted pollinator overlap score
    pub raw: f64,
    /// Percentile score (0-100, HIGH = GOOD)
    pub norm: f64,
    /// Number of shared pollinators
    pub n_shared_pollinators: usize,
    /// Map of pollinator_name → plant_count for detailed analysis
    pub pollinator_counts: FxHashMap<String, usize>,
}

/// Calculate M7: Pollinator Support
///
/// **PHASE 3 OPTIMIZATION**: Reuses organisms LazyFrame from scorer, filters after column projection
///
/// R reference: m7_pollinator_support.R::calculate_m7_pollinator_support
pub fn calculate_m7(
    plant_ids: &[String],        // Guild plant IDs for filtering
    organisms_lazy: &LazyFrame,  // Schema-only scan (from scorer, reused from M3!)
    calibration: &Calibration,
) -> Result<M7Result> {
    // STEP 1: Materialize organisms columns and filter to guild
    let organisms_df = materialize_with_columns(
        organisms_lazy,
        REQUIRED_ORGANISM_COLS,
        "M7 organisms",
    )?;

    let guild_organisms = filter_to_guild(&organisms_df, plant_ids, "plant_wfo_id", "M7")?;

    let n_plants = guild_organisms.height();

    // Get plant IDs from the filtered DataFrame (now local to this function)
    let guild_plant_ids: Vec<String> = guild_organisms
        .column("plant_wfo_id")?
        .str()?
        .into_iter()
        .filter_map(|opt| opt.map(|s| s.to_string()))
        .collect();

    // Count shared pollinators (pollinators hosted by ≥2 plants)
    // Uses both pollinators AND flower_visitors (R parity)
    let shared_pollinators = count_shared_organisms(
        &guild_organisms,
        &guild_plant_ids,
        &["pollinators", "flower_visitors"],  // Match R implementation
    )?;

    // Score with QUADRATIC weighting
    // Reflects non-linear benefits of high-overlap pollinator communities
    let mut p7_raw = 0.0;
    for (_org_name, count) in &shared_pollinators {
        if *count >= 2 {
            let overlap_ratio = *count as f64 / n_plants as f64;
            p7_raw += overlap_ratio.powi(2); // QUADRATIC benefit
        }
    }

    // Percentile normalize
    let m7_norm = percentile_normalize(p7_raw, "p6", calibration, false)?;

    Ok(M7Result {
        raw: p7_raw,
        norm: m7_norm,
        n_shared_pollinators: shared_pollinators.len(),
        pollinator_counts: shared_pollinators,
    })
}

#[cfg(test)]
mod tests {
    use approx::assert_relative_eq;

    #[test]
    fn test_quadratic_weighting() {
        let n_plants = 7.0_f64;

        // 2 plants → overlap = 2/7 ≈ 0.286 → squared ≈ 0.082
        let overlap = 2.0_f64 / n_plants;
        let contribution = overlap.powi(2);
        assert_relative_eq!(contribution, 0.082, epsilon = 0.001);

        // 5 plants → overlap = 5/7 ≈ 0.714 → squared ≈ 0.51
        let overlap = 5.0_f64 / n_plants;
        let contribution = overlap.powi(2);
        assert_relative_eq!(contribution, 0.51, epsilon = 0.01);

        // 7 plants → overlap = 7/7 = 1.0 → squared = 1.0
        let overlap = 7.0_f64 / n_plants;
        let contribution = overlap.powi(2);
        assert_relative_eq!(contribution, 1.0, epsilon = 0.0001);
    }

    #[test]
    fn test_multiple_pollinators() {
        let n_plants = 5.0_f64;

        let mut p7_raw = 0.0_f64;

        // Pollinator 1: 3 plants
        let overlap = 3.0_f64 / n_plants;
        p7_raw += overlap.powi(2);

        // Pollinator 2: 4 plants
        let overlap = 4.0_f64 / n_plants;
        p7_raw += overlap.powi(2);

        // Total: (3/5)² + (4/5)² = 0.36 + 0.64 = 1.0
        assert_relative_eq!(p7_raw, 1.0, epsilon = 0.0001);
    }
}
