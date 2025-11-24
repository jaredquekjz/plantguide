//! Guild Scorer - Main coordinator for scoring plant guilds
//!
//! This module integrates all 7 metrics and provides the main guild scoring interface.
//! Includes both sequential and parallel (Rayon) implementations.
//!
//! R reference: shipley_checks/src/Stage_4/guild_scorer_v3_modular.R

use crate::data::GuildData;
use crate::metrics::*;
use crate::utils::normalization::{Calibration, CsrCalibration};
use crate::explanation::{generate_m1_fragment, generate_m2_fragment, generate_m3_fragment,
    generate_m4_fragment, generate_m5_fragment, generate_m6_fragment, generate_m7_fragment,
    MetricFragment};
use anyhow::{Result};
use polars::prelude::*;
use rayon::prelude::*;
use std::path::Path;

/// Main guild scorer
pub struct GuildScorer {
    data: GuildData,
    calibration: Calibration,
    csr_calibration: Option<CsrCalibration>,
    phylo_calculator: PhyloPDCalculator,
    climate_tier: String,
}

/// Guild score result
#[derive(Debug)]
pub struct GuildScore {
    pub overall_score: f64,
    pub metrics: [f64; 7],  // Display scores (M1-M7)
    pub raw_scores: [f64; 7],
    pub normalized: [f64; 7],  // Before display inversion
}

impl GuildScorer {
    /// Initialize guild scorer
    ///
    /// R reference: guild_scorer_v3_modular.R::initialize
    pub fn new(calibration_type: &str, climate_tier: &str) -> Result<Self> {
        println!("\nInitializing Guild Scorer (Rust)...");

        // Load calibration parameters
        let cal_path_str = format!(
            "shipley_checks/stage4/phase5_output/normalization_params_{}.json",
            calibration_type
        );
        let cal_path = Path::new(&cal_path_str);
        println!("Loading calibration: {:?}", cal_path);
        let calibration = Calibration::load(cal_path, climate_tier)?;

        // Load CSR calibration (global, not tier-specific)
        let csr_path_str = "shipley_checks/stage4/phase5_output/csr_percentile_calibration_global.json";
        let csr_path = Path::new(csr_path_str);
        let csr_calibration = if csr_path.exists() {
            println!("Loading CSR calibration: {:?}", csr_path);
            Some(CsrCalibration::load(csr_path)?)
        } else {
            println!("CSR calibration not found - using fixed thresholds");
            None
        };

        // Initialize Faith's PD calculator
        println!("Initializing Faith's PD calculator...");
        let phylo_calculator = PhyloPDCalculator::new()?;

        // Load datasets
        let data = GuildData::load()?;

        println!("\nGuild Scorer initialized:");
        println!("  Calibration: {}", calibration_type);
        println!("  Climate tier: {}", climate_tier);
        println!("  Plants: {}", data.plants.height());
        println!();

        Ok(Self {
            data,
            calibration,
            csr_calibration,
            phylo_calculator,
            climate_tier: climate_tier.to_string(),
        })
    }

    /// Create GuildScorer for calibration (uses dummy normalization)
    ///
    /// Mirrors R: GuildScorerV3Shipley$new(calibration_type='2plant', ...)
    /// but with dummy calibration for raw score extraction.
    ///
    /// # Arguments
    /// * `climate_tier` - Climate tier name (not used in calibration, but kept for API consistency)
    ///
    /// # Returns
    /// GuildScorer instance configured for calibration (no normalization)
    ///
    /// # Example
    /// ```rust
    /// let scorer = GuildScorer::new_for_calibration("tier_3_humid_temperate")?;
    /// let raw_scores = scorer.compute_raw_scores(&plant_ids)?;
    /// ```
    pub fn new_for_calibration(climate_tier: &str) -> Result<Self> {
        println!("\nInitializing Guild Scorer for Calibration (Rust)...");

        // Create dummy calibration (returns raw values without normalization)
        let calibration = Calibration::dummy();

        // Initialize Faith's PD calculator
        println!("Initializing Faith's PD calculator...");
        let phylo_calculator = PhyloPDCalculator::new()?;

        // Load datasets
        let data = GuildData::load()?;

        println!("\nGuild Scorer initialized for calibration:");
        println!("  Mode: Calibration (dummy normalization)");
        println!("  Climate tier: {} (reference only)", climate_tier);
        println!("  Plants: {}", data.plants.height());
        println!();

        Ok(Self {
            data,
            calibration,
            csr_calibration: None,  // Not needed for calibration
            phylo_calculator,
            climate_tier: climate_tier.to_string(),
        })
    }

    /// Compute raw scores for a guild (for calibration)
    ///
    /// Mirrors R: compute_raw_scores(guild_ids, guild_scorer, plants_df)
    ///
    /// Returns raw metric values without normalization for percentile calculation.
    /// Uses the canonical metric calculation code path, ensuring calibration and
    /// production use identical logic.
    ///
    /// # Arguments
    /// * `plant_ids` - Vector of plant WFO IDs for the guild
    ///
    /// # Returns
    /// RawScores struct with unnormalized values for all 7 metrics
    ///
    /// # Example
    /// ```rust
    /// let scorer = GuildScorer::new_for_calibration("tier_3_humid_temperate")?;
    /// let plant_ids = vec!["wfo-123".to_string(), "wfo-456".to_string()];
    /// let scores = scorer.compute_raw_scores(&plant_ids)?;
    /// println!("M1 raw: {}", scores.m1_pest_risk);
    /// ```
    pub fn compute_raw_scores(&self, plant_ids: &[String]) -> Result<RawScores> {
        // Call canonical metric functions (same as score_guild but with dummy calibration)
        let m1 = calculate_m1(plant_ids, &self.phylo_calculator, &self.calibration)?;
        let m2 = calculate_m2(
            &self.data.plants_lazy,
            plant_ids,
            self.csr_calibration.as_ref(),
            &self.calibration,
        )?;
        let m3 = calculate_m3(
            plant_ids,
            &self.data.organisms_lazy,
            &self.data.fungi_lazy,
            &self.data.herbivore_predators,
            &self.data.insect_parasites,
            &self.calibration,
        )?;
        let m4 = calculate_m4(
            plant_ids,
            &self.data.organisms_lazy,
            &self.data.fungi_lazy,
            &self.data.pathogen_antagonists,
            &self.calibration,
        )?;
        let m5 = calculate_m5(plant_ids, &self.data.fungi_lazy, &self.calibration)?;
        let m6 = calculate_m6(plant_ids, &self.data.plants_lazy, &self.calibration)?;
        let m7 = calculate_m7(plant_ids, &self.data.organisms_lazy, &self.calibration)?;

        Ok(RawScores {
            m1_faiths_pd: m1.raw,
            m1_pest_risk: m1.raw,
            m2_conflict_density: m2.raw,
            m3_biocontrol_raw: m3.raw,
            m4_pathogen_control_raw: m4.raw,
            m5_beneficial_fungi_raw: m5.raw,
            m6_stratification_raw: m6.raw,
            m7_pollinator_raw: m7.raw,
        })
    }

    /// Access guild data (for calibration script to organize by tier)
    ///
    /// Returns reference to GuildData for external access patterns like
    /// climate tier organization in calibration pipeline.
    pub fn data(&self) -> &GuildData {
        &self.data
    }

    /// Provide LazyFrames for organisms and fungi (metrics will filter during collect)
    ///
    /// **PHASE 3 OPTIMIZATION**: Share LazyFrames across M3/M4/M5/M7
    ///
    /// **Problem being solved:**
    ///   - M3 filters organisms_df to guild plants
    ///   - M4 filters fungi_df to guild plants
    ///   - M5 filters fungi_df to guild plants (again!)
    ///   - M7 filters organisms_df to guild plants (again!)
    ///   Total: 2 organisms filters + 2 fungi filters = 4 redundant DataFrame operations
    ///
    /// **Solution:**
    ///   Each metric receives the same LazyFrame references
    ///   They materialize different column projections as needed
    ///   Polars optimizes each .select().collect() call independently
    ///
    /// **Memory savings:**
    ///   Instead of: Each metric receiving full DataFrames (11,711 rows each)
    ///   Now: Each metric loads only needed columns for guild plants
    ///   - M3: 5 organism cols + 2 fungi cols
    ///   - M4: 3 fungi cols
    ///   - M5: 5 fungi cols
    ///   - M7: 3 organism cols
    ///   All filtered to 7 rows during their individual .collect() calls
    ///
    /// Returns: References to organisms_lazy and fungi_lazy (not filtered yet)
    fn get_lazy_frames(&self) -> (&LazyFrame, &LazyFrame) {
        (&self.data.organisms_lazy, &self.data.fungi_lazy)
    }

    /// Check climate compatibility (Köppen tier overlap)
    ///
    /// R reference: guild_scorer_v3_modular.R::check_climate_compatibility
    fn check_climate_compatibility(&self, guild_plants: &DataFrame) -> Result<()> {
        let tier_columns = [
            "tier_1_tropical",
            "tier_2_mediterranean",
            "tier_3_humid_temperate",
            "tier_4_continental",
            "tier_5_boreal_polar",
            "tier_6_arid",
        ];

        // Find tiers for each plant
        let mut all_plant_tiers: Vec<Vec<String>> = Vec::new();

        for idx in 0..guild_plants.height() {
            let mut plant_tiers = Vec::new();

            for tier_col in &tier_columns {
                if let Ok(col) = guild_plants.column(tier_col) {
                    // Handle both boolean and integer columns
                    let is_true = if let Ok(bool_series) = col.bool() {
                        bool_series.get(idx).unwrap_or(false)
                    } else if let Ok(int_series) = col.i32() {
                        int_series.get(idx).unwrap_or(0) == 1
                    } else {
                        false
                    };

                    if is_true {
                        plant_tiers.push(tier_col.to_string());
                    }
                }
            }

            all_plant_tiers.push(plant_tiers);
        }

        if all_plant_tiers.is_empty() {
            anyhow::bail!("Plants missing Köppen tier membership data");
        }

        // Find intersection of all plant tiers
        let mut shared_tiers = all_plant_tiers[0].clone();
        for plant_tiers in &all_plant_tiers[1..] {
            shared_tiers.retain(|tier| plant_tiers.contains(tier));
        }

        if shared_tiers.is_empty() {
            anyhow::bail!("Plants have no overlapping climate zones");
        }

        Ok(())
    }

    /// Score a guild of plants using all 7 metrics
    ///
    /// R reference: guild_scorer_v3_modular.R::score_guild
    pub fn score_guild(&self, plant_ids: &[String]) -> Result<GuildScore> {
        let n_plants = plant_ids.len();

        // Filter to guild plants
        let id_set: std::collections::HashSet<_> = plant_ids.iter().collect();
        let plant_col = self.data.plants.column("wfo_taxon_id")?.str()?;
        let mask: BooleanChunked = plant_col
            .into_iter()
            .map(|opt| opt.map_or(false, |s| id_set.contains(&s.to_string())))
            .collect();
        let guild_plants = self.data.plants.filter(&mask)?;

        if guild_plants.height() != n_plants {
            anyhow::bail!("Missing plant data for some IDs");
        }

        // Check climate compatibility
        self.check_climate_compatibility(&guild_plants)?;

        // ====================================================================
        // PHASE 3 OPTIMIZATION: Share LazyFrames across M3/M4/M5/M7
        // ====================================================================
        //
        // Each metric receives the same LazyFrame references (unfiltered)
        // They materialize only their needed columns, then filter in memory
        // This eliminates redundant filtering and minimizes data loading
        let (organisms_lazy, fungi_lazy) = self.get_lazy_frames();

        // Calculate M1: Pest & Pathogen Independence
        // M1 already optimal: Only uses plant_ids, no DataFrame access
        let m1 = calculate_m1(plant_ids, &self.phylo_calculator, &self.calibration)?;

        // Calculate M2: Growth Compatibility
        // PHASE 2 OPTIMIZATION: Use LazyFrame instead of materialized DataFrame
        // Old: Pass &guild_plants (all 782 columns)
        // New: Pass &plants_lazy + plant_ids (loads only 7 columns)
        let m2 = calculate_m2(&self.data.plants_lazy, plant_ids, self.csr_calibration.as_ref(), &self.calibration)?;

        // Calculate M3: Insect Control
        // PHASE 3 OPTIMIZATION: Use LazyFrames with column projection
        // Old: Pass full organisms/fungi DataFrames (11,711 rows each)
        // New: Pass LazyFrames + plant_ids (M3 selects 5 organism + 2 fungi columns, then filters)
        let m3 = calculate_m3(
            plant_ids,
            organisms_lazy,
            fungi_lazy,
            &self.data.herbivore_predators,
            &self.data.insect_parasites,
            &self.calibration,
        )?;

        // Calculate M4: Disease Control
        // PHASE 3 OPTIMIZATION: Use LazyFrame with column projection
        // Reuses same organisms_lazy and fungi_lazy as M3 (no redundant full-DataFrame passing!)
        let m4 = calculate_m4(
            plant_ids,
            organisms_lazy,
            fungi_lazy,
            &self.data.pathogen_antagonists,
            &self.calibration,
        )?;

        // Calculate M5: Beneficial Fungi
        // PHASE 3 OPTIMIZATION: Use LazyFrame with column projection
        // Reuses same fungi_lazy as M3/M4 (triple reuse!)
        let m5 = calculate_m5(plant_ids, fungi_lazy, &self.calibration)?;

        // Calculate M6: Structural Diversity
        // PHASE 4 OPTIMIZATION: Use LazyFrame with column projection
        // Old: Pass &guild_plants (all 782 columns)
        // New: Pass &plants_lazy + plant_ids (loads only 5 columns)
        let m6 = calculate_m6(plant_ids, &self.data.plants_lazy, &self.calibration)?;

        // Calculate M7: Pollinator Support
        // PHASE 3 OPTIMIZATION: Use LazyFrame with column projection
        // Reuses same organisms_lazy as M3 (no redundant filtering!)
        let m7 = calculate_m7(plant_ids, organisms_lazy, &self.calibration)?;

        // Raw scores
        let raw_scores = [m1.raw, m2.raw, m3.raw, m4.raw, m5.raw, m6.raw, m7.raw];

        // Normalized percentiles (before display inversion)
        let normalized = [
            m1.normalized,
            m2.norm,
            m3.norm,
            m4.norm,
            m5.norm,
            m6.norm,
            m7.norm,
        ];

        // Display scores (invert M1 and M2)
        // R reference: guild_scorer_v3_modular.R lines 338-339
        let metrics = [
            100.0 - m1.normalized,  // M1: 100 - percentile (low pest risk = high display score)
            100.0 - m2.norm,        // M2: 100 - percentile (low conflicts = high display score)
            m3.norm,                // M3-M7: direct percentile
            m4.norm,
            m5.norm,
            m6.norm,
            m7.norm,
        ];

        // Overall score: simple average (matches R line 342)
        let overall_score = metrics.iter().sum::<f64>() / 7.0;

        Ok(GuildScore {
            overall_score,
            metrics,
            raw_scores,
            normalized,
        })
    }

    /// Score a guild of plants using all 7 metrics IN PARALLEL
    ///
    /// Uses Rayon to compute all 7 metrics concurrently across CPU cores.
    /// Expected speedup: 3-5× vs sequential on modern CPUs.
    ///
    /// All metrics are thread-safe (immutable data access only).
    pub fn score_guild_parallel(&self, plant_ids: &[String]) -> Result<GuildScore> {
        let n_plants = plant_ids.len();

        // Filter to guild plants (sequential - fast operation)
        let id_set: std::collections::HashSet<_> = plant_ids.iter().collect();
        let plant_col = self.data.plants.column("wfo_taxon_id")?.str()?;
        let mask: BooleanChunked = plant_col
            .into_iter()
            .map(|opt| opt.map_or(false, |s| id_set.contains(&s.to_string())))
            .collect();
        let guild_plants = self.data.plants.filter(&mask)?;

        if guild_plants.height() != n_plants {
            anyhow::bail!("Missing plant data for some IDs");
        }

        // Check climate compatibility (sequential - fast operation)
        self.check_climate_compatibility(&guild_plants)?;

        // Get LazyFrame references for M3/M4/M5/M7
        let (organisms_lazy, fungi_lazy) = self.get_lazy_frames();

        // Compute all 7 metrics IN PARALLEL using Rayon
        // Each metric is independent and can run on a separate thread
        let metric_results: Vec<Result<Box<dyn std::any::Any + Send>>> = (0..7)
            .into_par_iter()
            .map(|i| -> Result<Box<dyn std::any::Any + Send>> {
                match i {
                    0 => {
                        let m1 = calculate_m1(plant_ids, &self.phylo_calculator, &self.calibration)?;
                        Ok(Box::new(m1))
                    }
                    1 => {
                        // PHASE 2 OPTIMIZATION: Use LazyFrame
                        let m2 = calculate_m2(&self.data.plants_lazy, plant_ids, self.csr_calibration.as_ref(), &self.calibration)?;
                        Ok(Box::new(m2))
                    }
                    2 => {
                        // PHASE 3 OPTIMIZATION: Use LazyFrames with column projection
                        let m3 = calculate_m3(
                            plant_ids,
                            organisms_lazy,
                            fungi_lazy,
                            &self.data.herbivore_predators,
                            &self.data.insect_parasites,
                            &self.calibration,
                        )?;
                        Ok(Box::new(m3))
                    }
                    3 => {
                        // PHASE 3 OPTIMIZATION: Use LazyFrame with column projection
                        let m4 = calculate_m4(
                            plant_ids,
                            organisms_lazy,
                            fungi_lazy,
                            &self.data.pathogen_antagonists,
                            &self.calibration,
                        )?;
                        Ok(Box::new(m4))
                    }
                    4 => {
                        // PHASE 3 OPTIMIZATION: Use LazyFrame with column projection
                        let m5 = calculate_m5(plant_ids, fungi_lazy, &self.calibration)?;
                        Ok(Box::new(m5))
                    }
                    5 => {
                        // PHASE 4 OPTIMIZATION: Use LazyFrame with column projection
                        let m6 = calculate_m6(plant_ids, &self.data.plants_lazy, &self.calibration)?;
                        Ok(Box::new(m6))
                    }
                    6 => {
                        // PHASE 3 OPTIMIZATION: Use LazyFrame with column projection
                        let m7 = calculate_m7(plant_ids, organisms_lazy, &self.calibration)?;
                        Ok(Box::new(m7))
                    }
                    _ => unreachable!(),
                }
            })
            .collect();

        // Unwrap results (propagate any errors)
        let mut unwrapped_results = Vec::new();
        for result in metric_results {
            unwrapped_results.push(result?);
        }

        // Downcast back to concrete types
        let m1 = unwrapped_results[0]
            .downcast_ref::<M1Result>()
            .ok_or_else(|| anyhow::anyhow!("Failed to downcast M1"))?;
        let m2 = unwrapped_results[1]
            .downcast_ref::<M2Result>()
            .ok_or_else(|| anyhow::anyhow!("Failed to downcast M2"))?;
        let m3 = unwrapped_results[2]
            .downcast_ref::<M3Result>()
            .ok_or_else(|| anyhow::anyhow!("Failed to downcast M3"))?;
        let m4 = unwrapped_results[3]
            .downcast_ref::<M4Result>()
            .ok_or_else(|| anyhow::anyhow!("Failed to downcast M4"))?;
        let m5 = unwrapped_results[4]
            .downcast_ref::<M5Result>()
            .ok_or_else(|| anyhow::anyhow!("Failed to downcast M5"))?;
        let m6 = unwrapped_results[5]
            .downcast_ref::<M6Result>()
            .ok_or_else(|| anyhow::anyhow!("Failed to downcast M6"))?;
        let m7 = unwrapped_results[6]
            .downcast_ref::<M7Result>()
            .ok_or_else(|| anyhow::anyhow!("Failed to downcast M7"))?;

        // Raw scores
        let raw_scores = [m1.raw, m2.raw, m3.raw, m4.raw, m5.raw, m6.raw, m7.raw];

        // Normalized percentiles (before display inversion)
        let normalized = [
            m1.normalized,
            m2.norm,
            m3.norm,
            m4.norm,
            m5.norm,
            m6.norm,
            m7.norm,
        ];

        // Display scores (invert M1 and M2)
        let metrics = [
            100.0 - m1.normalized,  // M1: 100 - percentile (low pest risk = high display score)
            100.0 - m2.norm,        // M2: 100 - percentile (low conflicts = high display score)
            m3.norm,                // M3-M7: direct percentile
            m4.norm,
            m5.norm,
            m6.norm,
            m7.norm,
        ];

        // Overall score: simple average
        let overall_score = metrics.iter().sum::<f64>() / 7.0;

        Ok(GuildScore {
            overall_score,
            metrics,
            raw_scores,
            normalized,
        })
    }

    /// Score a guild WITH explanation generation (parallel)
    ///
    /// Generates both scores and explanation fragments in a single parallel pass.
    /// Each metric calculates its score and generates its explanation fragment inline.
    ///
    /// Returns: (GuildScore, Vec<MetricFragment>, DataFrame of guild_plants, M5Result, fungi_df)
    pub fn score_guild_with_explanation_parallel(
        &self,
        plant_ids: &[String],
    ) -> Result<(GuildScore, Vec<MetricFragment>, DataFrame, M2Result, M3Result, DataFrame, M4Result, M5Result, DataFrame, M7Result, EcosystemServicesResult)> {
        let n_plants = plant_ids.len();

        // Filter to guild plants (sequential - fast operation)
        let id_set: std::collections::HashSet<_> = plant_ids.iter().collect();
        let plant_col = self.data.plants.column("wfo_taxon_id")?.str()?;
        let mask: BooleanChunked = plant_col
            .into_iter()
            .map(|opt| opt.map_or(false, |s| id_set.contains(&s.to_string())))
            .collect();
        let guild_plants = self.data.plants.filter(&mask)?;

        if guild_plants.height() != n_plants {
            anyhow::bail!("Missing plant data for some IDs");
        }

        // Check climate compatibility (sequential - fast operation)
        self.check_climate_compatibility(&guild_plants)?;

        // Get LazyFrame references for M3/M4/M5/M7
        let (organisms_lazy, fungi_lazy) = self.get_lazy_frames();

        // Compute all 7 metrics + explanations IN PARALLEL using Rayon
        // Each metric is independent and can run on a separate thread
        type MetricResultWithFragment = (Box<dyn std::any::Any + Send>, MetricFragment);

        let metric_results: Vec<Result<MetricResultWithFragment>> = (0..7)
            .into_par_iter()
            .map(|i| -> Result<MetricResultWithFragment> {
                match i {
                    0 => {
                        let m1 = calculate_m1(plant_ids, &self.phylo_calculator, &self.calibration)?;
                        let display_score = 100.0 - m1.normalized;
                        let fragment = generate_m1_fragment(&m1, display_score);
                        Ok((Box::new(m1), fragment))
                    }
                    1 => {
                        // PHASE 2 OPTIMIZATION: Use LazyFrame (explanation engine path)
                        let m2 = calculate_m2(&self.data.plants_lazy, plant_ids, self.csr_calibration.as_ref(), &self.calibration)?;
                        let display_score = 100.0 - m2.norm;
                        let fragment = generate_m2_fragment(&m2, display_score);
                        Ok((Box::new(m2), fragment))
                    }
                    2 => {
                        // PHASE 3 OPTIMIZATION: Use LazyFrames with column projection
                        let m3 = calculate_m3(
                            plant_ids,
                            organisms_lazy,
                            fungi_lazy,
                            &self.data.herbivore_predators,
                            &self.data.insect_parasites,
                            &self.calibration,
                        )?;
                        let display_score = m3.norm;
                        let fragment = generate_m3_fragment(&m3, display_score);
                        Ok((Box::new(m3), fragment))
                    }
                    3 => {
                        // PHASE 3 OPTIMIZATION: Use LazyFrame with column projection
                        let m4 = calculate_m4(
                            plant_ids,
                            organisms_lazy,
                            fungi_lazy,
                            &self.data.pathogen_antagonists,
                            &self.calibration,
                        )?;
                        let display_score = m4.norm;
                        let fragment = generate_m4_fragment(&m4, display_score);
                        Ok((Box::new(m4), fragment))
                    }
                    4 => {
                        // PHASE 3 OPTIMIZATION: Use LazyFrame with column projection
                        let m5 = calculate_m5(plant_ids, fungi_lazy, &self.calibration)?;
                        let display_score = m5.norm;
                        let fragment = generate_m5_fragment(&m5, display_score);
                        Ok((Box::new(m5), fragment))
                    }
                    5 => {
                        // PHASE 4 OPTIMIZATION: Use LazyFrame with column projection
                        let m6 = calculate_m6(plant_ids, &self.data.plants_lazy, &self.calibration)?;
                        let display_score = m6.norm;
                        let fragment = generate_m6_fragment(&m6, display_score);
                        Ok((Box::new(m6), fragment))
                    }
                    6 => {
                        // PHASE 3 OPTIMIZATION: Use LazyFrame with column projection
                        let m7 = calculate_m7(plant_ids, organisms_lazy, &self.calibration)?;
                        let display_score = m7.norm;
                        let fragment = generate_m7_fragment(&m7, display_score);
                        Ok((Box::new(m7), fragment))
                    }
                    _ => unreachable!(),
                }
            })
            .collect();

        // Unwrap results and separate metrics from fragments
        let mut unwrapped_results = Vec::new();
        let mut fragments = Vec::new();

        for result in metric_results {
            let (metric_result, fragment) = result?;
            unwrapped_results.push(metric_result);
            fragments.push(fragment);
        }

        // Downcast back to concrete types
        let m1 = unwrapped_results[0]
            .downcast_ref::<M1Result>()
            .ok_or_else(|| anyhow::anyhow!("Failed to downcast M1"))?;
        let m2 = unwrapped_results[1]
            .downcast_ref::<M2Result>()
            .ok_or_else(|| anyhow::anyhow!("Failed to downcast M2"))?;
        let m3 = unwrapped_results[2]
            .downcast_ref::<M3Result>()
            .ok_or_else(|| anyhow::anyhow!("Failed to downcast M3"))?;
        let m4 = unwrapped_results[3]
            .downcast_ref::<M4Result>()
            .ok_or_else(|| anyhow::anyhow!("Failed to downcast M4"))?;
        let m5 = unwrapped_results[4]
            .downcast_ref::<M5Result>()
            .ok_or_else(|| anyhow::anyhow!("Failed to downcast M5"))?;
        let m6 = unwrapped_results[5]
            .downcast_ref::<M6Result>()
            .ok_or_else(|| anyhow::anyhow!("Failed to downcast M6"))?;
        let m7 = unwrapped_results[6]
            .downcast_ref::<M7Result>()
            .ok_or_else(|| anyhow::anyhow!("Failed to downcast M7"))?;

        // Raw scores
        let raw_scores = [m1.raw, m2.raw, m3.raw, m4.raw, m5.raw, m6.raw, m7.raw];

        // Normalized percentiles (before display inversion)
        let normalized = [
            m1.normalized,
            m2.norm,
            m3.norm,
            m4.norm,
            m5.norm,
            m6.norm,
            m7.norm,
        ];

        // Display scores (invert M1 and M2)
        let metrics = [
            100.0 - m1.normalized,  // M1: 100 - percentile (low pest risk = high display score)
            100.0 - m2.norm,        // M2: 100 - percentile (low conflicts = high display score)
            m3.norm,                // M3-M7: direct percentile
            m4.norm,
            m5.norm,
            m6.norm,
            m7.norm,
        ];

        // Overall score: simple average
        let overall_score = metrics.iter().sum::<f64>() / 7.0;

        let guild_score = GuildScore {
            overall_score,
            metrics,
            raw_scores,
            normalized,
        };

        // Join herbivores column from organisms DataFrame for pest profile analysis
        // Note: organisms DataFrame uses "plant_wfo_id" (Phase 0 schema)
        let organisms_subset = self.data.organisms
            .clone()
            .lazy()
            .select(&[col("plant_wfo_id"), col("herbivores")])
            .with_column(col("plant_wfo_id").alias("wfo_taxon_id"))
            .collect()?;
        let guild_plants_with_organisms = guild_plants
            .join(
                &organisms_subset,
                ["wfo_taxon_id"],
                ["wfo_taxon_id"],
                JoinArgs::new(JoinType::Left),
                None,  // JoinTypeOptions added in Polars 0.46
            )?;

        // Clone M3Result for biocontrol network analysis
        let m3_cloned = M3Result {
            raw: m3.raw,
            norm: m3.norm,
            biocontrol_raw: m3.biocontrol_raw,
            plants_with_biocontrol: m3.plants_with_biocontrol,
            total_plants: m3.total_plants,
            n_mechanisms: m3.n_mechanisms,
            predator_counts: m3.predator_counts.clone(),
            entomo_fungi_counts: m3.entomo_fungi_counts.clone(),
            specific_predator_matches: m3.specific_predator_matches,
            specific_fungi_matches: m3.specific_fungi_matches,
            matched_predator_pairs: m3.matched_predator_pairs.clone(),
            matched_fungi_pairs: m3.matched_fungi_pairs.clone(),
        };

        // Clone M4Result for pathogen control network analysis
        let m4_cloned = M4Result {
            raw: m4.raw,
            norm: m4.norm,
            pathogen_control_raw: m4.pathogen_control_raw,
            plants_with_disease_control: m4.plants_with_disease_control,
            total_plants: m4.total_plants,
            n_mechanisms: m4.n_mechanisms,
            mycoparasite_counts: m4.mycoparasite_counts.clone(),
            fungivore_counts: m4.fungivore_counts.clone(),
            pathogen_counts: m4.pathogen_counts.clone(),
            specific_antagonist_matches: m4.specific_antagonist_matches,
            specific_fungivore_matches: m4.specific_fungivore_matches,
            matched_antagonist_pairs: m4.matched_antagonist_pairs.clone(),
            matched_fungivore_pairs: m4.matched_fungivore_pairs.clone(),
        };

        // Clone M2Result for CSR strategy profile analysis
        let m2_cloned = M2Result {
            raw: m2.raw,
            norm: m2.norm,
            high_c_count: m2.high_c_count,
            high_s_count: m2.high_s_count,
            high_r_count: m2.high_r_count,
            total_conflicts: m2.total_conflicts,
            plant_csr_data: m2.plant_csr_data.clone(),
        };

        // Clone M5Result for fungi network analysis
        let m5_cloned = M5Result {
            raw: m5.raw,
            norm: m5.norm,
            network_score: m5.network_score,
            coverage_ratio: m5.coverage_ratio,
            n_shared_fungi: m5.n_shared_fungi,
            plants_with_fungi: m5.plants_with_fungi,
            total_plants: m5.total_plants,
            fungi_counts: m5.fungi_counts.clone(),
        };

        // Clone M7Result for pollinator network analysis
        let m7_cloned = M7Result {
            raw: m7.raw,
            norm: m7.norm,
            quadratic_score: m7.quadratic_score,
            n_shared_pollinators: m7.n_shared_pollinators,
            plants_with_pollinators: m7.plants_with_pollinators,
            total_plants: m7.total_plants,
            pollinator_counts: m7.pollinator_counts.clone(),
        };

        // Calculate ecosystem services (M8-M17)
        // Note: Uses plants dataframe which has ecosystem service rating columns from Stage 3
        let ecosystem_services = calculate_ecosystem_services(&self.data.plants, plant_ids)?;

        Ok((guild_score, fragments, guild_plants_with_organisms, m2_cloned, m3_cloned, self.data.organisms.clone(), m4_cloned, m5_cloned, self.data.fungi.clone(), m7_cloned, ecosystem_services))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use approx::assert_relative_eq;

    #[test]
    #[ignore] // Requires data files and C++ binary
    fn test_score_forest_garden() {
        let scorer = GuildScorer::new("7plant", "tier_3_humid_temperate").unwrap();

        let plant_ids = vec![
            "wfo-0000832453".to_string(),
            "wfo-0000649136".to_string(),
            "wfo-0000642673".to_string(),
            "wfo-0000984977".to_string(),
            "wfo-0000241769".to_string(),
            "wfo-0000092746".to_string(),
            "wfo-0000690499".to_string(),
        ];

        let result = scorer.score_guild(&plant_ids).unwrap();

        // Expected from R: 90.467710
        assert_relative_eq!(result.overall_score, 90.467710, epsilon = 0.0001);
    }
}
