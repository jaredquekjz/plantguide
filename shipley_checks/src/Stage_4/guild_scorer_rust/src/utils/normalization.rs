//! Normalization Utilities
//!
//! Converts raw metric scores to percentiles using Köppen climate tier-stratified
//! calibration parameters.
//!
//! R reference: shipley_checks/src/Stage_4/utils/normalization.R (193 lines)

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use anyhow::{Context, Result};

/// Calibration parameters for all Köppen tiers and metrics
#[derive(Debug, Deserialize, Serialize)]
pub struct Calibration {
    #[serde(flatten)]
    tiers: HashMap<String, TierCalibration>,

    #[serde(skip)]
    pub active_tier: String,
}

/// Calibration parameters for a single Köppen tier
#[derive(Debug, Deserialize, Serialize)]
struct TierCalibration {
    m1: Option<PercentileParams>,  // Pest risk
    n4: Option<PercentileParams>,  // Conflict density
    p1: Option<PercentileParams>,  // Biocontrol
    p2: Option<PercentileParams>,  // Disease control
    p3: Option<PercentileParams>,  // Beneficial fungi
    p5: Option<PercentileParams>,  // Structural diversity
    p6: Option<PercentileParams>,  // Pollinator support
}

/// Percentile values for a single metric
#[derive(Debug, Deserialize, Serialize, Clone)]
struct PercentileParams {
    p1: f64,
    p5: f64,
    p10: f64,
    p20: f64,
    p30: f64,
    p40: f64,
    p50: f64,
    p60: f64,
    p70: f64,
    p80: f64,
    p90: f64,
    p95: f64,
    p99: f64,
}

impl Calibration {
    /// Load calibration from JSON file
    pub fn load(path: &Path, climate_tier: &str) -> Result<Self> {
        let contents = fs::read_to_string(path)
            .with_context(|| format!("Failed to read calibration file: {:?}", path))?;

        let mut calibration: Calibration = serde_json::from_str(&contents)
            .with_context(|| "Failed to parse calibration JSON")?;

        calibration.active_tier = climate_tier.to_string();

        // Verify tier exists
        if !calibration.tiers.contains_key(climate_tier) {
            anyhow::bail!("Climate tier '{}' not found in calibration", climate_tier);
        }

        Ok(calibration)
    }

    /// Get tier calibration
    fn get_tier(&self) -> Result<&TierCalibration> {
        self.tiers.get(&self.active_tier)
            .ok_or_else(|| anyhow::anyhow!("Tier '{}' not found", self.active_tier))
    }
}

/// Percentile normalize using linear interpolation
///
/// Algorithm (from R normalization.R):
/// 1. Find bracketing percentiles [pi, pi+1] where values[pi] <= raw <= values[pi+1]
/// 2. Linear interpolation: percentile = pi + fraction × (pi+1 - pi)
/// 3. If invert = true, apply: percentile = 100 - percentile
///
/// R reference: shipley_checks/src/Stage_4/utils/normalization.R::percentile_normalize
pub fn percentile_normalize(
    raw_value: f64,
    metric_name: &str,
    calibration: &Calibration,
    invert: bool,
) -> Result<f64> {
    const PERCENTILES: [f64; 13] = [
        1.0, 5.0, 10.0, 20.0, 30.0, 40.0, 50.0,
        60.0, 70.0, 80.0, 90.0, 95.0, 99.0
    ];

    let tier = calibration.get_tier()?;

    // Get metric parameters
    let params = match metric_name {
        "m1" => &tier.m1,
        "n4" => &tier.n4,
        "p1" => &tier.p1,
        "p2" => &tier.p2,
        "p3" => &tier.p3,
        "p5" => &tier.p5,
        "p6" => &tier.p6,
        _ => anyhow::bail!("Unknown metric: {}", metric_name),
    };

    let params = params.as_ref()
        .ok_or_else(|| anyhow::anyhow!("No calibration params for metric: {}", metric_name))?;

    let values = [
        params.p1, params.p5, params.p10, params.p20, params.p30,
        params.p40, params.p50, params.p60, params.p70, params.p80,
        params.p90, params.p95, params.p99,
    ];

    // Edge cases
    if raw_value <= values[0] {
        return Ok(if invert { 100.0 } else { 0.0 });
    }
    if raw_value >= values[12] {
        return Ok(if invert { 0.0 } else { 100.0 });
    }

    // Linear interpolation
    for i in 0..12 {
        if values[i] <= raw_value && raw_value <= values[i + 1] {
            let fraction = if values[i + 1] - values[i] > 0.0 {
                (raw_value - values[i]) / (values[i + 1] - values[i])
            } else {
                0.0
            };

            let percentile = PERCENTILES[i] + fraction * (PERCENTILES[i + 1] - PERCENTILES[i]);

            return Ok(if invert { 100.0 - percentile } else { percentile });
        }
    }

    // Fallback (should never reach here)
    Ok(50.0)
}

/// CSR Calibration parameters (global, not tier-specific)
#[derive(Debug, Deserialize, Serialize)]
pub struct CsrCalibration {
    c: CsrPercentileParams,
    s: CsrPercentileParams,
    r: CsrPercentileParams,
}

/// Percentile values for CSR strategies
#[derive(Debug, Deserialize, Serialize)]
struct CsrPercentileParams {
    p1: f64,
    p5: f64,
    p10: f64,
    p20: f64,
    p30: f64,
    p40: f64,
    p50: f64,
    p60: f64,
    p70: f64,
    p75: f64,
    p80: f64,
    p85: f64,
    p90: f64,
    p95: f64,
    p99: f64,
}

impl CsrCalibration {
    /// Load CSR calibration from JSON file
    pub fn load(path: &Path) -> Result<Self> {
        let contents = fs::read_to_string(path)
            .with_context(|| format!("Failed to read CSR calibration file: {:?}", path))?;

        serde_json::from_str(&contents)
            .with_context(|| "Failed to parse CSR calibration JSON")
    }
}

/// Convert raw CSR score to percentile using global calibration
///
/// Unlike guild metrics (tier-stratified), CSR uses GLOBAL percentiles
/// because conflicts are within-guild comparisons, not cross-guild.
///
/// R reference: shipley_checks/src/Stage_4/utils/normalization.R::csr_to_percentile
pub fn csr_to_percentile(
    raw_value: f64,
    strategy: char,
    csr_calibration: Option<&CsrCalibration>,
) -> f64 {
    // Fallback to fixed thresholds if no calibration
    let Some(csr_cal) = csr_calibration else {
        return match strategy {
            'c' | 's' => if raw_value >= 60.0 { 100.0 } else { 50.0 },
            'r' => if raw_value >= 50.0 { 100.0 } else { 50.0 },
            _ => 50.0,
        };
    };

    const PERCENTILES: [f64; 15] = [
        1.0, 5.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0,
        70.0, 75.0, 80.0, 85.0, 90.0, 95.0, 99.0
    ];

    let params = match strategy {
        'c' => &csr_cal.c,
        's' => &csr_cal.s,
        'r' => &csr_cal.r,
        _ => return 50.0,
    };

    let values = [
        params.p1, params.p5, params.p10, params.p20, params.p30,
        params.p40, params.p50, params.p60, params.p70, params.p75,
        params.p80, params.p85, params.p90, params.p95, params.p99,
    ];

    // Edge cases
    if raw_value <= values[0] {
        return 0.0;
    }
    if raw_value >= values[14] {
        return 100.0;
    }

    // Linear interpolation
    for i in 0..14 {
        if values[i] <= raw_value && raw_value <= values[i + 1] {
            let fraction = if values[i + 1] - values[i] > 0.0 {
                (raw_value - values[i]) / (values[i + 1] - values[i])
            } else {
                0.0
            };

            return PERCENTILES[i] + fraction * (PERCENTILES[i + 1] - PERCENTILES[i]);
        }
    }

    50.0 // Fallback
}

#[cfg(test)]
mod tests {
    use super::*;
    use approx::assert_relative_eq;

    #[test]
    fn test_percentile_normalize_edge_cases() {
        // Test with mock calibration
        let json = r#"{
            "tier_3_humid_temperate": {
                "m1": {
                    "p1": 0.5, "p5": 0.55, "p10": 0.6, "p20": 0.65, "p30": 0.7,
                    "p40": 0.75, "p50": 0.8, "p60": 0.85, "p70": 0.9, "p80": 0.95,
                    "p90": 1.0, "p95": 1.05, "p99": 1.1
                }
            }
        }"#;

        let cal: Calibration = serde_json::from_str(json).unwrap();
        let mut cal = cal;
        cal.active_tier = "tier_3_humid_temperate".to_string();

        // Below minimum
        let result = percentile_normalize(0.4, "m1", &cal, false).unwrap();
        assert_relative_eq!(result, 0.0, epsilon = 0.0001);

        // Above maximum
        let result = percentile_normalize(1.2, "m1", &cal, false).unwrap();
        assert_relative_eq!(result, 100.0, epsilon = 0.0001);

        // At midpoint (p50 = 0.8)
        let result = percentile_normalize(0.8, "m1", &cal, false).unwrap();
        assert_relative_eq!(result, 50.0, epsilon = 0.0001);
    }

    #[test]
    fn test_csr_to_percentile_fallback() {
        // Test fallback behavior without calibration
        assert_eq!(csr_to_percentile(70.0, 'c', None), 100.0);
        assert_eq!(csr_to_percentile(50.0, 'c', None), 50.0);
        assert_eq!(csr_to_percentile(60.0, 'r', None), 100.0);
        assert_eq!(csr_to_percentile(40.0, 'r', None), 50.0);
    }
}
