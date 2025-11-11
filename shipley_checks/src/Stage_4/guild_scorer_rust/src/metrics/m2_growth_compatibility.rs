//! METRIC 2: GROWTH COMPATIBILITY (CSR CONFLICTS)
//!
//! Scores ecological compatibility based on Grime's CSR strategy conflicts.
//! Detects 4 types of conflicts (C-C, C-S, C-R, R-R) with context-specific
//! modulation based on growth form, height, and light preference.
//!
//! R reference: shipley_checks/src/Stage_4/metrics/m2_growth_compatibility.R

use polars::prelude::*;
use anyhow::Result;
use crate::utils::{Calibration, CsrCalibration, percentile_normalize, csr_to_percentile};

const PERCENTILE_THRESHOLD: f64 = 75.0; // Top quartile

/// Result of M2 calculation
#[derive(Debug)]
pub struct M2Result {
    /// Conflict density (conflicts per possible pair)
    pub raw: f64,
    /// Normalized percentile (0-100)
    pub norm: f64,
    /// Number of high-C plants
    pub high_c_count: usize,
    /// Number of high-S plants
    pub high_s_count: usize,
    /// Number of high-R plants
    pub high_r_count: usize,
    /// Total raw conflicts before density normalization
    pub total_conflicts: f64,
}

/// Plant data for conflict detection
#[derive(Debug, Clone)]
#[allow(dead_code)] // Fields used for debugging/diagnostics
struct PlantRow {
    index: usize,
    name: String,
    csr_c: f64,
    csr_s: f64,
    csr_r: f64,
    c_percentile: f64,
    s_percentile: f64,
    r_percentile: f64,
    height_m: f64,
    growth_form: String,
    light_pref: f64,
}

/// Calculate M2: Growth Compatibility (CSR Conflicts)
///
/// R reference: m2_growth_compatibility.R::calculate_m2_growth_compatibility
pub fn calculate_m2(
    guild_plants: &DataFrame,
    csr_calibration: Option<&CsrCalibration>,
    calibration: &Calibration,
) -> Result<M2Result> {
    let n_plants = guild_plants.height();

    // Extract data from DataFrame
    let plants = extract_plant_data(guild_plants, csr_calibration)?;

    // Classify plants
    let high_c: Vec<&PlantRow> = plants.iter()
        .filter(|p| p.c_percentile > PERCENTILE_THRESHOLD)
        .collect();
    let high_s: Vec<&PlantRow> = plants.iter()
        .filter(|p| p.s_percentile > PERCENTILE_THRESHOLD)
        .collect();
    let high_r: Vec<&PlantRow> = plants.iter()
        .filter(|p| p.r_percentile > PERCENTILE_THRESHOLD)
        .collect();

    let mut total_conflicts = 0.0;

    // CONFLICT TYPE 1: C-C (Competitive vs Competitive)
    if high_c.len() >= 2 {
        for i in 0..high_c.len() - 1 {
            for j in i + 1..high_c.len() {
                let conflict = calculate_c_c_conflict(high_c[i], high_c[j]);
                total_conflicts += conflict;
            }
        }
    }

    // CONFLICT TYPE 2: C-S (Competitive vs Stress-Tolerant)
    for plant_c in &high_c {
        for plant_s in &high_s {
            if plant_c.index != plant_s.index {
                let conflict = calculate_c_s_conflict(plant_c, plant_s);
                total_conflicts += conflict;
            }
        }
    }

    // CONFLICT TYPE 3: C-R (Competitive vs Ruderal)
    for plant_c in &high_c {
        for plant_r in &high_r {
            if plant_c.index != plant_r.index {
                let conflict = calculate_c_r_conflict(plant_c, plant_r);
                total_conflicts += conflict;
            }
        }
    }

    // CONFLICT TYPE 4: R-R (Ruderal vs Ruderal)
    if high_r.len() >= 2 {
        for i in 0..high_r.len() - 1 {
            for _j in i + 1..high_r.len() {
                total_conflicts += 0.3; // Fixed low severity
            }
        }
    }

    // Normalize by guild size (conflict density)
    let max_pairs = if n_plants > 1 {
        n_plants * (n_plants - 1)
    } else {
        1
    };
    let conflict_density = total_conflicts / max_pairs as f64;

    // Percentile normalization (Köppen tier-stratified)
    let m2_norm = percentile_normalize(conflict_density, "n4", calibration, false)?;

    Ok(M2Result {
        raw: conflict_density,
        norm: m2_norm,
        high_c_count: high_c.len(),
        high_s_count: high_s.len(),
        high_r_count: high_r.len(),
        total_conflicts,
    })
}

/// Extract plant data from DataFrame and convert CSR to percentiles
fn extract_plant_data(
    df: &DataFrame,
    csr_calibration: Option<&CsrCalibration>,
) -> Result<Vec<PlantRow>> {
    let n = df.height();
    let mut plants = Vec::with_capacity(n);

    let names = df.column("wfo_scientific_name")?.str()?;
    let csr_c = df.column("CSR_C")?.f64()?;
    let csr_s = df.column("CSR_S")?.f64()?;
    let csr_r = df.column("CSR_R")?.f64()?;
    let heights = df.column("height_m")?.f64()?;
    let growth_forms = df.column("try_growth_form")?.str()?;
    let light_prefs = df.column("light_pref")?.f64()?;

    for i in 0..n {
        let c_val = csr_c.get(i).unwrap_or(50.0);
        let s_val = csr_s.get(i).unwrap_or(50.0);
        let r_val = csr_r.get(i).unwrap_or(50.0);

        plants.push(PlantRow {
            index: i,
            name: names.get(i).unwrap_or("Unknown").to_string(),
            csr_c: c_val,
            csr_s: s_val,
            csr_r: r_val,
            c_percentile: csr_to_percentile(c_val, 'c', csr_calibration),
            s_percentile: csr_to_percentile(s_val, 's', csr_calibration),
            r_percentile: csr_to_percentile(r_val, 'r', csr_calibration),
            height_m: heights.get(i).unwrap_or(1.0),
            growth_form: growth_forms.get(i).unwrap_or("").to_lowercase(),
            light_pref: light_prefs.get(i).unwrap_or(5.0),
        });
    }

    Ok(plants)
}

/// Calculate C-C conflict with growth form and height modulation
///
/// R reference: m2_growth_compatibility.R lines 187-235
fn calculate_c_c_conflict(plant_a: &PlantRow, plant_b: &PlantRow) -> f64 {
    let mut conflict = 1.0; // Base severity

    // Growth form complementarity
    let form_a = &plant_a.growth_form;
    let form_b = &plant_b.growth_form;

    if (form_a.contains("vine") || form_a.contains("liana")) && form_b.contains("tree") {
        conflict *= 0.2; // Vine can climb tree
    } else if (form_b.contains("vine") || form_b.contains("liana")) && form_a.contains("tree") {
        conflict *= 0.2; // Vine can climb tree
    } else if (form_a.contains("tree") && form_b.contains("herb"))
        || (form_b.contains("tree") && form_a.contains("herb"))
    {
        conflict *= 0.4; // Different vertical niches
    } else {
        // Height separation
        let height_diff = (plant_a.height_m - plant_b.height_m).abs();
        if height_diff < 2.0 {
            conflict *= 1.0; // Same canopy layer
        } else if height_diff < 5.0 {
            conflict *= 0.6; // Partial separation
        } else {
            conflict *= 0.3; // Different canopy layers
        }
    }

    conflict
}

/// Calculate C-S conflict with critical light preference modulation
///
/// R reference: m2_growth_compatibility.R lines 268-315
fn calculate_c_s_conflict(plant_c: &PlantRow, plant_s: &PlantRow) -> f64 {
    let mut conflict = 0.6; // Base severity

    let s_light = plant_s.light_pref;

    // Critical: Light-based modulation
    if s_light < 3.2 {
        // S is SHADE-ADAPTED - wants to be under C plant's canopy
        conflict = 0.0;
    } else if s_light > 7.47 {
        // S is SUN-LOVING - will be shaded out by C plant
        conflict = 0.9;
    } else {
        // S is FLEXIBLE - depends on height difference
        let height_diff = (plant_c.height_m - plant_s.height_m).abs();
        if height_diff > 8.0 {
            conflict *= 0.3; // Beneficial vertical niche separation
        }
        // Otherwise use base conflict of 0.6
    }

    conflict
}

/// Calculate C-R conflict with height modulation
///
/// R reference: m2_growth_compatibility.R lines 334-361
fn calculate_c_r_conflict(plant_c: &PlantRow, plant_r: &PlantRow) -> f64 {
    let mut conflict = 0.8; // Base severity

    // Height difference allows R plants to exploit gaps
    let height_diff = (plant_c.height_m - plant_r.height_m).abs();
    if height_diff > 5.0 {
        conflict *= 0.3; // Temporal niche separation
    }

    conflict
}

#[cfg(test)]
mod tests {
    use super::*;
    use approx::assert_relative_eq;

    #[test]
    fn test_c_c_conflict_base() {
        let plant_a = PlantRow {
            index: 0,
            name: "Plant A".to_string(),
            csr_c: 80.0,
            csr_s: 10.0,
            csr_r: 10.0,
            c_percentile: 90.0,
            s_percentile: 10.0,
            r_percentile: 10.0,
            height_m: 2.0,
            growth_form: "shrub".to_string(),
            light_pref: 7.0,
        };
        let plant_b = PlantRow {
            index: 1,
            name: "Plant B".to_string(),
            csr_c: 85.0,
            csr_s: 10.0,
            csr_r: 5.0,
            c_percentile: 92.0,
            s_percentile: 8.0,
            r_percentile: 5.0,
            height_m: 2.5,
            growth_form: "shrub".to_string(),
            light_pref: 8.0,
        };

        // Height diff < 2m → conflict = 1.0
        let conflict = calculate_c_c_conflict(&plant_a, &plant_b);
        assert_relative_eq!(conflict, 1.0, epsilon = 0.001);
    }

    #[test]
    fn test_c_c_conflict_vine_tree() {
        let vine = PlantRow {
            index: 0,
            name: "Vine".to_string(),
            csr_c: 80.0,
            csr_s: 10.0,
            csr_r: 10.0,
            c_percentile: 90.0,
            s_percentile: 10.0,
            r_percentile: 10.0,
            height_m: 5.0,
            growth_form: "vine".to_string(),
            light_pref: 7.0,
        };
        let tree = PlantRow {
            index: 1,
            name: "Tree".to_string(),
            csr_c: 85.0,
            csr_s: 10.0,
            csr_r: 5.0,
            c_percentile: 92.0,
            s_percentile: 8.0,
            r_percentile: 5.0,
            height_m: 15.0,
            growth_form: "tree".to_string(),
            light_pref: 8.0,
        };

        // Vine + tree → complementary → conflict = 0.2
        let conflict = calculate_c_c_conflict(&vine, &tree);
        assert_relative_eq!(conflict, 0.2, epsilon = 0.001);
    }

    #[test]
    fn test_c_s_conflict_shade_adapted() {
        let plant_c = PlantRow {
            index: 0,
            name: "Competitive".to_string(),
            csr_c: 80.0,
            csr_s: 10.0,
            csr_r: 10.0,
            c_percentile: 90.0,
            s_percentile: 10.0,
            r_percentile: 10.0,
            height_m: 10.0,
            growth_form: "tree".to_string(),
            light_pref: 8.0,
        };
        let plant_s = PlantRow {
            index: 1,
            name: "Shade-tolerant".to_string(),
            csr_c: 10.0,
            csr_s: 80.0,
            csr_r: 10.0,
            c_percentile: 10.0,
            s_percentile: 90.0,
            r_percentile: 10.0,
            height_m: 0.5,
            growth_form: "herb".to_string(),
            light_pref: 2.0, // Shade-adapted (< 3.2)
        };

        // S is shade-adapted → beneficial relationship → conflict = 0.0
        let conflict = calculate_c_s_conflict(&plant_c, &plant_s);
        assert_relative_eq!(conflict, 0.0, epsilon = 0.001);
    }

    #[test]
    fn test_c_s_conflict_sun_loving() {
        let plant_c = PlantRow {
            index: 0,
            name: "Competitive".to_string(),
            csr_c: 80.0,
            csr_s: 10.0,
            csr_r: 10.0,
            c_percentile: 90.0,
            s_percentile: 10.0,
            r_percentile: 10.0,
            height_m: 10.0,
            growth_form: "tree".to_string(),
            light_pref: 8.0,
        };
        let plant_s = PlantRow {
            index: 1,
            name: "Sun-loving".to_string(),
            csr_c: 10.0,
            csr_s: 80.0,
            csr_r: 10.0,
            c_percentile: 10.0,
            s_percentile: 90.0,
            r_percentile: 10.0,
            height_m: 0.5,
            growth_form: "herb".to_string(),
            light_pref: 8.5, // Sun-loving (> 7.47)
        };

        // S is sun-loving → will be shaded out → conflict = 0.9
        let conflict = calculate_c_s_conflict(&plant_c, &plant_s);
        assert_relative_eq!(conflict, 0.9, epsilon = 0.001);
    }
}
