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

// Re-export metric functions
pub use m1_pest_pathogen_indep::{calculate_m1, PhyloPDCalculator, M1Result};
pub use m2_growth_compatibility::{calculate_m2, M2Result};
pub use m3_insect_control::{calculate_m3, M3Result};
pub use m4_disease_control::{calculate_m4, M4Result};
pub use m5_beneficial_fungi::{calculate_m5, M5Result};
pub use m6_structural_diversity::{calculate_m6, M6Result};
pub use m7_pollinator_support::{calculate_m7, M7Result};
