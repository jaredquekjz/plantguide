//! Metric modules for guild scoring
//!
//! Each metric is implemented in its own module following the R architecture.

pub mod m1_pest_pathogen_indep;
pub mod m2_growth_compatibility;
pub mod m3_insect_control;
pub mod m4_disease_control;
pub mod m5_beneficial_fungi;
pub mod m6_structural_diversity;
pub mod m7_pollinator_support;
pub mod ecosystem_services;

// Re-export metric functions
pub use m1_pest_pathogen_indep::{calculate_m1, PhyloPDCalculator, M1Result};
pub use m2_growth_compatibility::{calculate_m2, M2Result, GuildType};
pub use m3_insect_control::{calculate_m3, M3Result};
pub use m4_disease_control::{calculate_m4, M4Result};
pub use m5_beneficial_fungi::{calculate_m5, M5Result};
pub use m6_structural_diversity::{calculate_m6, M6Result};
pub use m7_pollinator_support::{calculate_m7, M7Result};
pub use ecosystem_services::{calculate_ecosystem_services, EcosystemServicesResult};

use crate::GuildData;
use anyhow::Result;
use polars::prelude::*;

/// Raw scores for all 7 metrics (unnormalized) - for calibration
#[derive(Debug, Clone)]
pub struct RawScores {
    pub m1_faiths_pd: f64,
    pub m1_pest_risk: f64,
    pub m2_conflict_density: f64,
    pub m3_biocontrol_raw: f64,  // Coverage % (0-100): % plants with biocontrol
    pub m4_pathogen_control_raw: f64,  // Coverage % (0-100): % plants with disease control
    pub m5_beneficial_fungi_raw: f64,  // Coverage % (0-100): % plants with beneficial fungi
    pub m6_stratification_raw: f64,
    pub m7_pollinator_raw: f64,  // Coverage % (0-100): % plants with pollinators
}

/// Compute raw scores for calibration (no normalization)
///
/// # Deprecated
/// This standalone function is deprecated. Use `GuildScorer::compute_raw_scores()` instead
/// for the canonical scorer pattern that mirrors the R implementation.
///
/// # Migration
/// ```rust
/// // Old pattern:
/// let data = GuildData::load()?;
/// let phylo = PhyloPDCalculator::new()?;
/// let scores = compute_raw_scores_for_calibration(&plant_ids, &data, &phylo)?;
///
/// // New pattern (preferred):
/// let scorer = GuildScorer::new_for_calibration("tier_3_humid_temperate")?;
/// let scores = scorer.compute_raw_scores(&plant_ids)?;
/// ```
#[deprecated(
    since = "0.2.0",
    note = "Use GuildScorer::compute_raw_scores() instead for canonical scorer pattern"
)]
pub fn compute_raw_scores_for_calibration(
    plant_ids: &[String],
    data: &GuildData,
    phylo_calculator: &PhyloPDCalculator,
) -> Result<RawScores> {
    // Create dummy calibration that returns raw values (no normalization)
    use crate::utils::normalization::Calibration;
    let dummy_cal = Calibration::dummy();

    // Calculate all metrics
    let m1_result = calculate_m1(plant_ids, phylo_calculator, &dummy_cal)?;
    let m2_result = calculate_m2(&data.plants_lazy, plant_ids, None, &dummy_cal)?;
    let m3_result = calculate_m3(
        plant_ids,
        &data.organisms_lazy,
        &data.fungi_lazy,
        &data.herbivore_predators,
        &data.insect_parasites,
        &dummy_cal,
    )?;
    let m4_result = calculate_m4(
        plant_ids,
        &data.organisms_lazy,
        &data.fungi_lazy,
        &data.pathogen_antagonists,
        &dummy_cal,
    )?;
    let m5_result = calculate_m5(plant_ids, &data.fungi_lazy, &dummy_cal)?;
    let m6_result = calculate_m6(plant_ids, &data.plants_lazy, &dummy_cal)?;
    let m7_result = calculate_m7(plant_ids, &data.organisms_lazy, &dummy_cal)?;

    Ok(RawScores {
        m1_faiths_pd: m1_result.raw,
        m1_pest_risk: m1_result.raw, // Using raw as pest_risk (exp transform already applied)
        m2_conflict_density: m2_result.raw,
        m3_biocontrol_raw: m3_result.raw,
        m4_pathogen_control_raw: m4_result.raw,
        m5_beneficial_fungi_raw: m5_result.raw,
        m6_stratification_raw: m6_result.raw,
        m7_pollinator_raw: m7_result.raw,
    })
}
