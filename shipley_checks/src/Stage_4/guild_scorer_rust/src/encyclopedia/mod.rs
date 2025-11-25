//! Encyclopedia Generator Module
//!
//! Generates plant encyclopedia articles in markdown format.
//! Ported from R implementation: shipley_checks/src/encyclopedia/
//!
//! ## Sections
//! 1. Identity Card - taxonomy, growth form, height, traits
//! 2. Growing Requirements - EIVE indicators, CSR, climate zones
//! 3. Maintenance Profile - CSR-derived labor estimates, seasonal tasks
//! 4. Ecosystem Services - carbon, nitrogen, erosion, nutrient cycling
//! 5. Biological Interactions - pollinators, pests, diseases, fungi
//! 6. Companion Planting (NEW) - guild compatibility scores
//! 7. Biodiversity Value (NEW) - composite organism/fungi richness index

pub mod utils;
pub mod sections;
pub mod generator;

pub use generator::EncyclopediaGenerator;
