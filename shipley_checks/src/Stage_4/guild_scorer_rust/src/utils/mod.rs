//! Utility modules for guild scoring
//!
//! Contains shared functionality used across multiple metrics:
//! - Normalization: Percentile transformation
//! - Organism counting: Shared organism network analysis
//! - LazyFrame helpers: Safe materialization with column validation
//! - Ecosystem ratings: Categorical rating conversions for ecosystem services

pub mod normalization;
pub mod organism_counter;
pub mod lazy_helpers;
pub mod vernacular;
pub mod ecosystem_ratings;

// Re-export commonly used types
pub use normalization::{Calibration, CsrCalibration, percentile_normalize, csr_to_percentile};
pub use organism_counter::count_shared_organisms;
pub use lazy_helpers::{materialize_with_columns, filter_to_guild};
pub use vernacular::{get_display_name, get_display_name_optimized};
pub use ecosystem_ratings::{rating_to_numeric, numeric_to_rating, mean_rating};
