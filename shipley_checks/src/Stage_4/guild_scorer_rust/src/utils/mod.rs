//! Utility modules for guild scoring
//!
//! Contains shared functionality used across multiple metrics:
//! - Normalization: Percentile transformation
//! - Organism counting: Shared organism network analysis

pub mod normalization;
pub mod organism_counter;

// Re-export commonly used types
pub use normalization::{Calibration, CsrCalibration, percentile_normalize, csr_to_percentile};
pub use organism_counter::count_shared_organisms;
