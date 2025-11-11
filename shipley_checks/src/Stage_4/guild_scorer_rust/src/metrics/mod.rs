//! Metric modules for guild scoring
//!
//! Each metric is implemented in its own module following the R architecture.

pub mod m2_growth_compatibility;

// Re-export metric functions
pub use m2_growth_compatibility::{calculate_m2, M2Result};
