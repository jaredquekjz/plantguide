//! METRIC 6: STRUCTURAL DIVERSITY (VERTICAL STRATIFICATION)
//!
//! **PHASE 4 OPTIMIZATION**: Pre-filtered LazyFrame with column projection
//!
//! Scores vertical stratification quality and growth form diversity.
//! Validates that height differences are compatible with light preferences.
//!
//! **Memory optimization**:
//!   - Old: Receives full guild_plants (7 rows × 782 columns)
//!   - New: Receives plants_lazy, selects only 4 needed columns
//!   - Savings per metric call: 778 columns not loaded
//!
//! **Columns needed** (M6 selects these 4):
//!   1. wfo_scientific_name - Plant name for grouping
//!   2. height_m - Plant height for stratification analysis
//!   3. light_pref - EIVE-L value for light compatibility validation
//!   4. try_growth_form - Growth form category for diversity scoring
//!
//! R reference: shipley_checks/src/Stage_4/metrics/m6_structural_diversity.R

use polars::prelude::*;
use rustc_hash::{FxHashSet, FxHashMap};
use anyhow::Result;
use crate::utils::{Calibration, percentile_normalize};

/// Plant with height and light preference information
#[derive(Debug, Clone)]
pub struct PlantHeight {
    pub name: String,
    pub height_m: f64,
    pub light_pref: Option<f64>,  // EIVE-L value (1-9)
}

/// Growth form group with plants
#[derive(Debug, Clone)]
pub struct GrowthFormGroup {
    pub form_name: String,
    pub plants: Vec<PlantHeight>,
    pub height_range: (f64, f64),
}

/// Result of M6 calculation
#[derive(Debug)]
pub struct M6Result {
    /// Combined stratification + form diversity (0-1 scale)
    pub raw: f64,
    /// Percentile score (0-100, HIGH = GOOD)
    pub norm: f64,
    /// Height range in meters
    pub height_range: f64,
    /// Number of unique growth forms
    pub n_forms: usize,
    /// Stratification quality (0-1)
    pub stratification_quality: f64,
    /// Form diversity score (0-1)
    pub form_diversity: f64,
    /// Growth form groups with plant details
    pub growth_form_groups: Vec<GrowthFormGroup>,
}

/// Calculate M6: Structural Diversity
///
/// **PHASE 4 OPTIMIZATION**: Uses LazyFrame with column projection
///
/// R reference: m6_structural_diversity.R::calculate_m6_structural_diversity
pub fn calculate_m6(
    plant_ids: &[String],        // Guild plant IDs for filtering
    plants_lazy: &LazyFrame,     // Schema-only scan (from scorer)
    calibration: &Calibration,
) -> Result<M6Result> {
    // STEP 1: Materialize only the 4 columns M6 needs
    let plants_selected = plants_lazy
        .clone()
        .select(&[
            col("wfo_taxon_id"),
            col("wfo_scientific_name"),
            col("height_m"),
            col("EIVEres-L_complete").alias("light_pref"),  // Use imputed complete values
            col("try_growth_form"),
        ])
        .collect()?;  // Execute: loads only 5 columns × 11,711 rows

    // STEP 2: Filter to guild plants (fast - only 5 columns)
    use std::collections::HashSet;
    let id_set: HashSet<_> = plant_ids.iter().collect();
    let id_col = plants_selected.column("wfo_taxon_id")?.str()?;
    let mask: BooleanChunked = id_col
        .into_iter()
        .map(|opt| opt.map_or(false, |s| id_set.contains(&s.to_string())))
        .collect();
    let guild_plants = plants_selected.filter(&mask)?;  // Result: 5 columns × 7 rows

    // Extract plant data from filtered DataFrame
    let growth_forms = guild_plants.column("try_growth_form")?.str()?;
    let orig_heights = guild_plants.column("height_m")?.f64()?;  // For height range calculation

    // COMPONENT 1: Light-validated height stratification (70%)
    let mut valid_stratification = 0.0;
    let mut invalid_stratification = 0.0;

    let n = guild_plants.height();
    if n >= 2 {
        // CRITICAL: Sort by height (R line 127: sorted_guild <- guild_plants[order(guild_plants$height_m), ])
        let sorted = guild_plants.clone().lazy()
            .sort(["height_m"], Default::default())
            .collect()?;

        let heights = sorted.column("height_m")?.f64()?;
        let light_prefs = sorted.column("light_pref")?.f64()?;

        // Analyze all tall-short pairs (R lines 130-156)
        for i in 0..n - 1 {
            for j in i + 1..n {
                let short_height_opt = heights.get(i);
                let tall_height_opt = heights.get(j);

                // Skip pairs with NULL heights (match R behavior: !is.na(height_diff))
                if short_height_opt.is_none() || tall_height_opt.is_none() {
                    continue;
                }

                let short_height = short_height_opt.unwrap();
                let tall_height = tall_height_opt.unwrap();
                let height_diff = tall_height - short_height;

                // Only significant height differences (>2m = different canopy layers)
                if height_diff > 2.0 {
                    let short_light = light_prefs.get(i);

                    match short_light {
                        None => {
                            // Conservative: neutral/flexible (missing data)
                            valid_stratification += height_diff * 0.5;
                        }
                        Some(light) if light < 3.2 => {
                            // Shade-tolerant (EIVE-L 1-3): Can thrive under canopy
                            valid_stratification += height_diff;
                        }
                        Some(light) if light > 7.47 => {
                            // Sun-loving (EIVE-L 8-9): Will be shaded out
                            invalid_stratification += height_diff;
                        }
                        Some(_) => {
                            // Flexible (EIVE-L 4-7): Partial compatibility
                            valid_stratification += height_diff * 0.6;
                        }
                    }
                }
            }
        }
    }

    // Stratification quality: valid / total
    let total_height_diffs = valid_stratification + invalid_stratification;
    let stratification_quality = if total_height_diffs > 0.0 {
        valid_stratification / total_height_diffs
    } else {
        0.0 // No vertical diversity
    };

    // COMPONENT 2: Form diversity (30%)
    let mut unique_forms: FxHashSet<String> = FxHashSet::default();
    for idx in 0..n {
        if let Some(form) = growth_forms.get(idx) {
            if !form.is_empty() {
                unique_forms.insert(form.to_string());
            }
        }
    }
    let n_forms = unique_forms.len();
    let form_diversity = if n_forms > 0 {
        (n_forms - 1) as f64 / 5.0 // 6 forms max
    } else {
        0.0
    };

    // Combined (70% light-validated height, 30% form)
    let p6_raw = 0.7 * stratification_quality + 0.3 * form_diversity;

    // Percentile normalize
    let m6_norm = percentile_normalize(p6_raw, "p5", calibration, false)?;

    // Calculate height range for details
    let mut valid_heights = Vec::new();
    for idx in 0..n {
        if let Some(h) = orig_heights.get(idx) {
            valid_heights.push(h);
        }
    }
    let height_range = if valid_heights.len() >= 2 {
        valid_heights.iter().copied().fold(f64::NEG_INFINITY, f64::max)
            - valid_heights.iter().copied().fold(f64::INFINITY, f64::min)
    } else {
        0.0
    };

    // Group plants by growth form with heights and light preferences
    let plant_names = guild_plants.column("wfo_scientific_name")?.str()?;
    let light_prefs = guild_plants.column("light_pref")?.f64()?;
    let mut form_groups: FxHashMap<String, Vec<PlantHeight>> = FxHashMap::default();

    for idx in 0..n {
        if let (Some(form), Some(name), Some(height)) = (
            growth_forms.get(idx),
            plant_names.get(idx),
            orig_heights.get(idx),
        ) {
            if !form.is_empty() {
                let light_pref = light_prefs.get(idx);
                form_groups
                    .entry(form.to_string())
                    .or_insert_with(Vec::new)
                    .push(PlantHeight {
                        name: name.to_string(),
                        height_m: height,
                        light_pref,
                    });
            }
        }
    }

    // Convert to GrowthFormGroup vec
    let mut growth_form_groups: Vec<GrowthFormGroup> = form_groups
        .into_iter()
        .map(|(form_name, plants)| {
            let heights: Vec<f64> = plants.iter().map(|p| p.height_m).collect();
            let min_height = heights.iter().copied().fold(f64::INFINITY, f64::min);
            let max_height = heights.iter().copied().fold(f64::NEG_INFINITY, f64::max);

            GrowthFormGroup {
                form_name,
                plants,
                height_range: (min_height, max_height),
            }
        })
        .collect();

    // Sort by min height for consistent display
    growth_form_groups.sort_by(|a, b| {
        a.height_range.0.partial_cmp(&b.height_range.0).unwrap_or(std::cmp::Ordering::Equal)
    });

    Ok(M6Result {
        raw: p6_raw,
        norm: m6_norm,
        height_range,
        n_forms,
        stratification_quality,
        form_diversity,
        growth_form_groups,
    })
}

#[cfg(test)]
mod tests {
    use approx::assert_relative_eq;

    #[test]
    fn test_stratification_quality() {
        // valid = 5.0, invalid = 0.0 → quality = 1.0
        let valid = 5.0;
        let invalid = 0.0;
        let quality = valid / (valid + invalid);
        assert_relative_eq!(quality, 1.0, epsilon = 0.0001);

        // valid = 3.0, invalid = 1.0 → quality = 0.75
        let valid = 3.0;
        let invalid = 1.0;
        let quality = valid / (valid + invalid);
        assert_relative_eq!(quality, 0.75, epsilon = 0.0001);
    }

    #[test]
    fn test_form_diversity() {
        // 3 forms → (3-1)/5 = 0.4
        let n_forms = 3;
        let diversity = (n_forms - 1) as f64 / 5.0;
        assert_relative_eq!(diversity, 0.4, epsilon = 0.0001);

        // 6 forms → (6-1)/5 = 1.0 (maximum)
        let n_forms = 6;
        let diversity = (n_forms - 1) as f64 / 5.0;
        assert_relative_eq!(diversity, 1.0, epsilon = 0.0001);
    }

    #[test]
    fn test_combined_score() {
        // stratification_quality = 0.8, form_diversity = 0.6
        let p6_raw = 0.7 * 0.8 + 0.3 * 0.6;
        assert_relative_eq!(p6_raw, 0.74, epsilon = 0.0001);
    }
}
