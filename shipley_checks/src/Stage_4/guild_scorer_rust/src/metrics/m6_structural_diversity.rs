//! METRIC 6: STRUCTURAL DIVERSITY (VERTICAL STRATIFICATION)
//!
//! Scores vertical stratification quality and growth form diversity.
//! Validates that height differences are compatible with light preferences.
//!
//! R reference: shipley_checks/src/Stage_4/metrics/m6_structural_diversity.R

use polars::prelude::*;
use rustc_hash::FxHashSet;
use anyhow::Result;
use crate::utils::{Calibration, percentile_normalize};

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
}

/// Calculate M6: Structural Diversity
///
/// R reference: m6_structural_diversity.R::calculate_m6_structural_diversity
pub fn calculate_m6(
    guild_plants: &DataFrame,
    calibration: &Calibration,
) -> Result<M6Result> {
    // Extract plant data
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
                let short_height = heights.get(i).unwrap_or(1.0);
                let tall_height = heights.get(j).unwrap_or(1.0);

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

    Ok(M6Result {
        raw: p6_raw,
        norm: m6_norm,
        height_range,
        n_forms,
        stratification_quality,
        form_diversity,
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
