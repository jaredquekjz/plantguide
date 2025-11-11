//! Metric modules for guild scoring
//!
//! Each metric is implemented in its own module following the R architecture.

pub mod m2_growth_compatibility;
pub mod m3_insect_control;
pub mod m4_disease_control;

// Re-export metric functions
pub use m2_growth_compatibility::{calculate_m2, M2Result};
pub use m3_insect_control::{calculate_m3, M3Result};
pub use m4_disease_control::{calculate_m4, M4Result};
