//! Encyclopedia Module
//!
//! Generates static plant encyclopedia articles from trait and interaction data.
//! Follows planning docs in docs/stage_4_encyclopedia_rules/
//!
//! ## Sections
//! - S1: Identity Card - Taxonomy, morphology, vernacular names, closest relatives
//! - S2: Growing Requirements - EIVE indicators, climate/soil envelopes
//! - S3: Maintenance Profile - CSR-based maintenance guidance
//! - S4: Ecosystem Services - Pre-calculated service ratings
//! - S5: Biological Interactions - Pollinators, pests, diseases, fungi
//! - S6: Guild Potential - Companion planting guidance (GP1-GP7)
//!
//! ## Public API
//! ```rust,ignore
//! use encyclopedia::{EncyclopediaGenerator, OrganismCounts, FungalCounts};
//!
//! let generator = EncyclopediaGenerator::new();
//! let article = generator.generate(
//!     "wfo-0001005999",
//!     &plant_data,
//!     Some(organism_counts),
//!     Some(fungal_counts),
//! )?;
//! ```

pub mod types;
pub mod utils;
pub mod sections;
pub mod generator;

// Re-export public API
pub use types::{OrganismCounts, FungalCounts, OrganismLists, OrganismProfile, CategorizedOrganisms, RankedPathogen, BeneficialFungi};
pub use sections::s1_identity::{RelatedSpecies, GenusSpeciesInfo};
pub use generator::EncyclopediaGenerator;
