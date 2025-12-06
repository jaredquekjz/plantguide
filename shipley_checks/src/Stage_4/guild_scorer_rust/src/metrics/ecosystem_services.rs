/// M8-M17: Ecosystem Services
///
/// Community-weighted mean ratings for 10 ecosystem services based on
/// Shipley (2025) framework. Ratings are categorical (Very High, High, Moderate, Low, Very Low)
/// derived from CSR scores at the individual plant level in Stage 3.
///
/// This module calculates guild-level ratings by averaging plant-level categorical ratings
/// (converted to numeric scores, averaged, and converted back to categorical).
///
/// Services:
/// - M8: NPP (Net Primary Productivity)
/// - M9: Decomposition Rate
/// - M10: Nutrient Cycling
/// - M11: Nutrient Retention
/// - M12: Nutrient Loss
/// - M13: Carbon Storage - Biomass
/// - M14: Carbon Storage - Recalcitrant
/// - M15: Carbon Storage - Total
/// - M16: Soil Erosion Protection
/// - M17: Nitrogen Fixation

use polars::prelude::*;
use anyhow::{Result, Context};
use rustc_hash::FxHashSet;
use crate::utils::ecosystem_ratings::mean_rating;

/// Result structure for ecosystem services (M8-M17)
#[derive(Debug, Clone)]
pub struct EcosystemServicesResult {
    // M8: NPP (Net Primary Productivity)
    pub m8_npp_score: f64,
    pub m8_npp_rating: String,

    // M9: Decomposition Rate
    pub m9_decomp_score: f64,
    pub m9_decomp_rating: String,

    // M10: Nutrient Cycling
    pub m10_nutrient_cycling_score: f64,
    pub m10_nutrient_cycling_rating: String,

    // M11: Nutrient Retention
    pub m11_nutrient_retention_score: f64,
    pub m11_nutrient_retention_rating: String,

    // M12: Nutrient Loss
    pub m12_nutrient_loss_score: f64,
    pub m12_nutrient_loss_rating: String,

    // M13: Carbon Storage - Biomass
    pub m13_carbon_storage_score: f64,
    pub m13_carbon_storage_rating: String,

    // M14: Carbon Storage - Recalcitrant
    pub m14_leaf_carbon_recalcitrant_score: f64,
    pub m14_leaf_carbon_recalcitrant_rating: String,

    // M15: Soil Erosion Protection (renumbered from M16)
    pub m16_erosion_protection_score: f64,
    pub m16_erosion_protection_rating: String,

    // M17: Nitrogen Fixation
    pub m17_nitrogen_fixation_score: f64,
    pub m17_nitrogen_fixation_rating: String,
}

/// Calculate all 10 ecosystem services for a guild
///
/// # Arguments
/// * `plants_df` - DataFrame containing all plants with ecosystem service rating columns
/// * `plant_ids` - List of plant IDs in the guild (wfo_taxon_id format: "wfo-0000832453")
///
/// # Returns
/// EcosystemServicesResult with scores and ratings for M8-M17
///
/// # Algorithm
/// For each service:
/// 1. Extract rating column for guild plants
/// 2. Convert categorical ratings to numeric (Very High=5, High=4, Moderate=3, Low=2, Very Low=1)
/// 3. Calculate mean (excluding NaN/Unable to Classify)
/// 4. Convert back to categorical rating
pub fn calculate_ecosystem_services(
    plants_df: &DataFrame,
    plant_ids: &[String],
) -> Result<EcosystemServicesResult> {
    // Build set of plant IDs for filtering
    let plant_set: FxHashSet<&str> = plant_ids.iter()
        .map(|s| s.as_str())
        .collect();

    // Filter plants_df to guild plants only (using wfo_taxon_id)
    let guild_mask = plants_df
        .column("wfo_taxon_id")
        .with_context(|| "Missing wfo_taxon_id column")?
        .str()
        .with_context(|| "wfo_taxon_id is not a string column")?
        .into_iter()
        .map(|opt| opt.map(|id| plant_set.contains(id)).unwrap_or(false))
        .collect::<BooleanChunked>();

    let guild_df = plants_df.filter(&guild_mask)
        .with_context(|| "Failed to filter plants_df to guild plants")?;

    // Helper function to extract rating column as Vec<&str>
    let extract_ratings = |col_name: &str| -> Result<Vec<&str>> {
        Ok(guild_df
            .column(col_name)
            .with_context(|| format!("Missing column: {}", col_name))?
            .str()
            .with_context(|| format!("{} is not a string column", col_name))?
            .into_iter()
            .filter_map(|opt| opt)
            .collect::<Vec<&str>>())
    };

    // Extract all 10 service ratings
    let npp_ratings = extract_ratings("npp_rating")?;
    let decomp_ratings = extract_ratings("decomposition_rating")?;
    let nutrient_cycling_ratings = extract_ratings("nutrient_cycling_rating")?;
    let nutrient_retention_ratings = extract_ratings("nutrient_retention_rating")?;
    let nutrient_loss_ratings = extract_ratings("nutrient_loss_rating")?;
    let carbon_storage_ratings = extract_ratings("carbon_storage_rating")?;
    let carbon_recalcitrant_ratings = extract_ratings("leaf_carbon_recalcitrant_rating")?;
    let erosion_protection_ratings = extract_ratings("erosion_protection_rating")?;
    let nitrogen_fixation_ratings = extract_ratings("nitrogen_fixation_rating")?;

    // Calculate community-weighted means
    let (m8_score, m8_rating) = mean_rating(&npp_ratings);
    let (m9_score, m9_rating) = mean_rating(&decomp_ratings);
    let (m10_score, m10_rating) = mean_rating(&nutrient_cycling_ratings);
    let (m11_score, m11_rating) = mean_rating(&nutrient_retention_ratings);
    let (m12_score, m12_rating) = mean_rating(&nutrient_loss_ratings);
    let (m13_score, m13_rating) = mean_rating(&carbon_storage_ratings);
    let (m14_score, m14_rating) = mean_rating(&carbon_recalcitrant_ratings);
    let (m16_score, m16_rating) = mean_rating(&erosion_protection_ratings);
    let (m17_score, m17_rating) = mean_rating(&nitrogen_fixation_ratings);

    Ok(EcosystemServicesResult {
        m8_npp_score: m8_score,
        m8_npp_rating: m8_rating.to_string(),
        m9_decomp_score: m9_score,
        m9_decomp_rating: m9_rating.to_string(),
        m10_nutrient_cycling_score: m10_score,
        m10_nutrient_cycling_rating: m10_rating.to_string(),
        m11_nutrient_retention_score: m11_score,
        m11_nutrient_retention_rating: m11_rating.to_string(),
        m12_nutrient_loss_score: m12_score,
        m12_nutrient_loss_rating: m12_rating.to_string(),
        m13_carbon_storage_score: m13_score,
        m13_carbon_storage_rating: m13_rating.to_string(),
        m14_leaf_carbon_recalcitrant_score: m14_score,
        m14_leaf_carbon_recalcitrant_rating: m14_rating.to_string(),
        m16_erosion_protection_score: m16_score,
        m16_erosion_protection_rating: m16_rating.to_string(),
        m17_nitrogen_fixation_score: m17_score,
        m17_nitrogen_fixation_rating: m17_rating.to_string(),
    })
}
