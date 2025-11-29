//! Local Suitability Engine for Encyclopedia
//!
//! Compares user's local climate/soil conditions against a plant's natural
//! occurrence envelope (q05/q50/q95 ranges) and generates location-specific
//! growing advice based on where the plant is observed to grow.
//!
//! ## Key Concept
//! All recommendations are **occurrence-based**: we assess suitability by comparing
//! local conditions against the range of conditions where the plant naturally occurs,
//! not by claiming the plant "needs" or "requires" specific conditions.
//!
//! ## Architecture
//! - `local_conditions.rs` - LocalConditions struct + 3 hardcoded test locations
//! - `climate_tier.rs` - 6-tier Köppen climate classification (from guild scorer)
//! - `comparator.rs` - Core envelope comparison logic (q05/q50/q95)
//! - `assessment.rs` - SuitabilityAssessment output structs
//! - `advice.rs` - Generate friendly markdown advice text

pub mod local_conditions;
pub mod climate_tier;
pub mod comparator;
pub mod assessment;
pub mod advice;

// Re-export public API
pub use local_conditions::LocalConditions;
pub use climate_tier::{ClimateTier, TierMatchType, OccurrenceFit};
pub use comparator::{EnvelopeFit, compare_to_envelope};
pub use assessment::{
    SuitabilityAssessment,
    ClimateZoneAssessment,
    TemperatureSuitability,
    MoistureSuitability,
    SoilSuitability,
    TextureSuitability,
    OverallRating,
    FitRating,
};
pub use advice::generate_suitability_section;
