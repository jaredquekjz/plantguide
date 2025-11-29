//! Suitability Assessment Types
//!
//! Output structures for the suitability engine, capturing the results
//! of comparing local conditions against plant occurrence envelopes.

use super::climate_tier::{ClimateTier, TierMatchType, OccurrenceFit, PlantTierFlags};
use super::comparator::{EnvelopeComparison, EnvelopeFit};
use crate::encyclopedia::utils::texture::TextureClassification;

/// Overall suitability rating
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum OverallRating {
    /// Native climate, all factors good
    Ideal,
    /// Similar climate or native with minor issues
    Good,
    /// Marginal climate or multiple issues
    Challenging,
    /// Incompatible climate or severe issues
    NotRecommended,
}

impl OverallRating {
    pub fn display_text(&self) -> &'static str {
        match self {
            OverallRating::Ideal => "Ideal",
            OverallRating::Good => "Good",
            OverallRating::Challenging => "Challenging",
            OverallRating::NotRecommended => "Not Recommended",
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            OverallRating::Ideal => "Conditions match where this plant naturally thrives",
            OverallRating::Good => "Good conditions with minor adaptations needed",
            OverallRating::Challenging => "Growing is possible but requires significant intervention",
            OverallRating::NotRecommended => "Conditions differ significantly from where this plant occurs",
        }
    }

    /// Return the worse of two ratings
    pub fn min(self, other: Self) -> Self {
        if self > other { self } else { other }
    }
}

/// Rating for individual factors (temperature, moisture, soil)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FitRating {
    /// Within observed occurrence range
    WithinRange,
    /// Close to observed range, minor adaptation
    Marginal,
    /// Outside observed range
    OutOfRange,
}

impl FitRating {
    pub fn display_text(&self) -> &'static str {
        match self {
            FitRating::WithinRange => "Within Range",
            FitRating::Marginal => "Marginal",
            FitRating::OutOfRange => "Outside Range",
        }
    }

    pub fn from_envelope_fit(fit: EnvelopeFit, is_significant: bool) -> Self {
        match fit {
            EnvelopeFit::WithinRange => FitRating::WithinRange,
            _ if is_significant => FitRating::OutOfRange,
            _ => FitRating::Marginal,
        }
    }
}

/// Complete suitability assessment for a plant at a location
#[derive(Debug, Clone)]
pub struct SuitabilityAssessment {
    /// Location name
    pub location: String,

    /// Plant name
    pub plant_name: String,

    /// Climate zone assessment (first-cut filter)
    pub climate_zone: ClimateZoneAssessment,

    /// Temperature suitability
    pub temperature: TemperatureSuitability,

    /// Moisture suitability
    pub moisture: MoistureSuitability,

    /// Soil chemistry suitability (pH, CEC)
    pub soil: SoilSuitability,

    /// Soil texture suitability
    pub texture: TextureSuitability,

    /// Overall recommendation
    pub overall_rating: OverallRating,

    /// Summary advice text
    pub summary: String,
}

/// Climate zone assessment result
#[derive(Debug, Clone)]
pub struct ClimateZoneAssessment {
    /// User's climate tier
    pub local_tier: ClimateTier,

    /// Tiers where plant is observed
    pub plant_tiers: PlantTierFlags,

    /// Match result
    pub match_type: TierMatchType,

    /// Occurrence fit classification
    pub occurrence_fit: OccurrenceFit,
}

impl ClimateZoneAssessment {
    /// Create from comparison
    pub fn new(local_tier: ClimateTier, plant_tiers: PlantTierFlags) -> Self {
        let match_type = super::climate_tier::compare_climate_tiers(local_tier, &plant_tiers);
        let occurrence_fit = OccurrenceFit::from_match_type(match_type);

        Self {
            local_tier,
            plant_tiers,
            match_type,
            occurrence_fit,
        }
    }

    /// Get ceiling rating based on climate match
    pub fn rating_ceiling(&self) -> OverallRating {
        match self.match_type {
            TierMatchType::ExactMatch => OverallRating::Ideal,
            TierMatchType::AdjacentMatch => OverallRating::Good,
            TierMatchType::NoMatch => OverallRating::Challenging,
        }
    }
}

/// Temperature suitability assessment
#[derive(Debug, Clone)]
pub struct TemperatureSuitability {
    /// Overall temperature rating
    pub rating: FitRating,

    /// Frost days comparison (if available)
    pub frost_comparison: Option<EnvelopeComparison>,

    /// Tropical nights comparison (if available)
    pub tropical_nights_comparison: Option<EnvelopeComparison>,

    /// Growing season comparison (if available)
    pub growing_season_comparison: Option<EnvelopeComparison>,

    /// Warmest month comparison (if available)
    pub warmest_month_comparison: Option<EnvelopeComparison>,

    /// Coldest month comparison (if available)
    pub coldest_month_comparison: Option<EnvelopeComparison>,

    /// Specific issues identified
    pub issues: Vec<String>,

    /// Recommended interventions
    pub interventions: Vec<String>,
}

impl Default for TemperatureSuitability {
    fn default() -> Self {
        Self {
            rating: FitRating::WithinRange,
            frost_comparison: None,
            tropical_nights_comparison: None,
            growing_season_comparison: None,
            warmest_month_comparison: None,
            coldest_month_comparison: None,
            issues: Vec::new(),
            interventions: Vec::new(),
        }
    }
}

/// Moisture suitability assessment
#[derive(Debug, Clone)]
pub struct MoistureSuitability {
    /// Overall moisture rating
    pub rating: FitRating,

    /// Annual rainfall comparison
    pub rainfall_comparison: Option<EnvelopeComparison>,

    /// Consecutive dry days comparison
    pub dry_days_comparison: Option<EnvelopeComparison>,

    /// Consecutive wet days comparison
    pub wet_days_comparison: Option<EnvelopeComparison>,

    /// Specific issues identified
    pub issues: Vec<String>,

    /// Watering/drainage recommendations
    pub recommendations: Vec<String>,
}

impl Default for MoistureSuitability {
    fn default() -> Self {
        Self {
            rating: FitRating::WithinRange,
            rainfall_comparison: None,
            dry_days_comparison: None,
            wet_days_comparison: None,
            issues: Vec::new(),
            recommendations: Vec::new(),
        }
    }
}

/// Soil chemistry suitability assessment
#[derive(Debug, Clone)]
pub struct SoilSuitability {
    /// Overall soil rating
    pub rating: FitRating,

    /// pH comparison
    pub ph_comparison: Option<EnvelopeComparison>,

    /// CEC (fertility) comparison
    pub cec_comparison: Option<EnvelopeComparison>,

    /// pH assessment
    pub ph_fit: PhFit,

    /// Fertility assessment
    pub fertility_fit: FertilityFit,

    /// Recommended amendments
    pub amendments: Vec<String>,
}

impl Default for SoilSuitability {
    fn default() -> Self {
        Self {
            rating: FitRating::WithinRange,
            ph_comparison: None,
            cec_comparison: None,
            ph_fit: PhFit::Good,
            fertility_fit: FertilityFit::Adequate,
            amendments: Vec::new(),
        }
    }
}

/// pH fit classification
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PhFit {
    TooAcid,
    Good,
    TooAlkaline,
}

impl PhFit {
    pub fn from_comparison(comp: &EnvelopeComparison) -> Self {
        match comp.fit {
            EnvelopeFit::BelowRange => PhFit::TooAcid,
            EnvelopeFit::WithinRange => PhFit::Good,
            EnvelopeFit::AboveRange => PhFit::TooAlkaline,
        }
    }

    pub fn display_text(&self) -> &'static str {
        match self {
            PhFit::TooAcid => "More acidic than typical",
            PhFit::Good => "Within observed range",
            PhFit::TooAlkaline => "More alkaline than typical",
        }
    }
}

/// Fertility fit classification
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FertilityFit {
    Low,
    Adequate,
    High,
}

impl FertilityFit {
    pub fn from_comparison(comp: &EnvelopeComparison) -> Self {
        match comp.fit {
            EnvelopeFit::BelowRange => FertilityFit::Low,
            EnvelopeFit::WithinRange => FertilityFit::Adequate,
            EnvelopeFit::AboveRange => FertilityFit::High,
        }
    }

    pub fn display_text(&self) -> &'static str {
        match self {
            FertilityFit::Low => "Lower fertility than typical",
            FertilityFit::Adequate => "Within observed range",
            FertilityFit::High => "Higher fertility than typical",
        }
    }
}

/// Texture suitability assessment
#[derive(Debug, Clone)]
pub struct TextureSuitability {
    /// Overall texture rating
    pub rating: FitRating,

    /// Local soil texture classification
    pub local_texture: Option<TextureClassification>,

    /// Plant's typical texture classification
    pub plant_texture: Option<TextureClassification>,

    /// Texture group compatibility
    pub compatibility: TextureCompatibility,

    /// Recommended amendments
    pub amendments: Vec<String>,
}

impl Default for TextureSuitability {
    fn default() -> Self {
        Self {
            rating: FitRating::WithinRange,
            local_texture: None,
            plant_texture: None,
            compatibility: TextureCompatibility::Unknown,
            amendments: Vec::new(),
        }
    }
}

/// Texture compatibility classification
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TextureCompatibility {
    /// Same texture group
    Ideal,
    /// Adjacent texture groups
    Good,
    /// Different but manageable
    Marginal,
    /// Very different textures
    Poor,
    /// Cannot determine
    Unknown,
}

impl TextureCompatibility {
    pub fn display_text(&self) -> &'static str {
        match self {
            TextureCompatibility::Ideal => "Ideal match",
            TextureCompatibility::Good => "Good match",
            TextureCompatibility::Marginal => "Marginal match",
            TextureCompatibility::Poor => "Poor match",
            TextureCompatibility::Unknown => "Unknown",
        }
    }
}

// ============================================================================
// Assessment Builder
// ============================================================================

/// Count issues across all assessment categories
pub fn count_issues(assessment: &SuitabilityAssessment) -> usize {
    let mut count = 0;

    if assessment.temperature.rating != FitRating::WithinRange {
        count += 1;
    }
    if assessment.moisture.rating != FitRating::WithinRange {
        count += 1;
    }
    if assessment.soil.rating != FitRating::WithinRange {
        count += 1;
    }
    if assessment.texture.rating != FitRating::WithinRange {
        count += 1;
    }

    count
}

/// Check for severe issues that auto-downgrade to NotRecommended
pub fn has_severe_issues(assessment: &SuitabilityAssessment) -> bool {
    // Check tropical nights (year-round heat)
    if let Some(ref comp) = assessment.temperature.tropical_nights_comparison {
        if comp.fit == EnvelopeFit::AboveRange && comp.distance_from_range > 100.0 {
            return true;
        }
    }

    // Check frost days (extreme cold)
    if let Some(ref comp) = assessment.temperature.frost_comparison {
        if comp.fit == EnvelopeFit::AboveRange && comp.distance_from_range > 50.0 {
            return true;
        }
    }

    // Check growing season (far too short)
    if let Some(ref comp) = assessment.temperature.growing_season_comparison {
        if comp.fit == EnvelopeFit::BelowRange && comp.distance_from_range > 60.0 {
            return true;
        }
    }

    // Climate zone NoMatch AND any temperature/moisture out of range
    if assessment.climate_zone.match_type == TierMatchType::NoMatch {
        if assessment.temperature.rating == FitRating::OutOfRange
            || assessment.moisture.rating == FitRating::OutOfRange
        {
            return true;
        }
    }

    false
}

/// Compute overall rating based on climate ceiling and issue counts
pub fn compute_overall_rating(assessment: &SuitabilityAssessment) -> OverallRating {
    // Step 1: Climate zone sets the ceiling
    let ceiling = assessment.climate_zone.rating_ceiling();

    // Step 2: Check for severe issues
    if has_severe_issues(assessment) {
        return OverallRating::NotRecommended;
    }

    // Step 3: Count issues
    let issue_count = count_issues(assessment);

    // Step 4: Compute rating based on issues
    let computed = if issue_count >= 3 {
        OverallRating::Challenging
    } else if issue_count >= 1 {
        OverallRating::Good
    } else {
        OverallRating::Ideal
    };

    // Return the worse of ceiling and computed rating
    ceiling.min(computed)
}
