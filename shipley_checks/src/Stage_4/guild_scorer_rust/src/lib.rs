//! Guild Scorer Rust Implementation
//!
//! High-performance guild scoring following the modular R architecture.
//!
//! This implementation mirrors the verified R modular structure:
//! - `utils/`: Normalization and organism counting utilities
//! - `data/`: Data loading with Polars
//! - `metrics/`: Individual metric implementations (M1-M7)
//! - `scorer/`: Main guild scorer coordinator
//!
//! Expected performance: 20-25× faster than Python, 8-10× faster than R
//!
//! R reference: shipley_checks/src/Stage_4/guild_scorer_v3_modular.R

pub mod utils;
pub mod data;
pub mod metrics;
pub mod scorer;
pub mod compact_tree;
pub mod explanation;

// Phase 8: DataFusion Query Engine (optional feature)
#[cfg(feature = "api")]
pub mod query_engine;

#[cfg(feature = "api")]
pub mod api_server;

// Suitability cache for fast O(1) envelope lookups
pub mod suitability_cache;

// Phase 8: FST Search Index (optional feature)
#[cfg(feature = "api")]
pub mod search_index;

// Encyclopedia generator module (optional feature)
#[cfg(feature = "api")]
pub mod encyclopedia;

// Phase 9: Web templating and HTMX
#[cfg(feature = "api")]
pub mod web;

// Re-export commonly used types
pub use utils::normalization::{Calibration, CsrCalibration, percentile_normalize, csr_to_percentile};
pub use data::{GuildData, ClimateOrganizer};
pub use metrics::{*, RawScores, compute_raw_scores_for_calibration};
pub use scorer::{GuildScorer, GuildScore};
pub use compact_tree::CompactTree;
pub use explanation::{
    Explanation, BenefitCard, WarningCard, RiskCard, MetricFragment, Severity,
    ExplanationGenerator, MarkdownFormatter, JsonFormatter, HtmlFormatter,
};

#[cfg(feature = "api")]
pub use query_engine::{QueryEngine, PlantFilters};

#[cfg(feature = "api")]
pub use api_server::{AppState, create_router};

#[cfg(feature = "api")]
pub use encyclopedia::EncyclopediaGenerator;

#[cfg(feature = "api")]
pub use search_index::{SearchIndex, PlantRef};

#[cfg(test)]
mod tests {
    #[test]
    fn it_works() {
        assert_eq!(2 + 2, 4);
    }
}
