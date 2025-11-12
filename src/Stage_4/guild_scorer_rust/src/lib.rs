//! Guild Scorer Rust Implementation
//!
//! High-performance guild scoring following the modular R architecture.
//!
//! This implementation mirrors the verified R modular structure:
//! - `utils/`: Normalization and organism counting utilities
//! - `metrics/`: Individual metric implementations (M1-M7)
//!
//! Expected performance: 20-25× faster than Python, 8-10× faster than R
//!
//! R reference: shipley_checks/src/Stage_4/guild_scorer_v3_modular.R

pub mod utils;

// Re-export commonly used types
pub use utils::{Calibration, CsrCalibration, percentile_normalize, csr_to_percentile};

#[cfg(test)]
mod tests {
    #[test]
    fn it_works() {
        assert_eq!(2 + 2, 4);
    }
}
