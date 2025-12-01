//! Encyclopedia JSON section modules.
//!
//! Each section corresponds to a planning doc in docs/stage_4_encyclopedia_rules/
//! Returns typed structs (from view_models.rs) instead of markdown strings.
//!
//! Cloned from sections_md/ with minimal changes:
//! - Return type: String → struct
//! - Markdown formatting → struct fields

pub mod s1_identity;
pub mod s2_requirements;
pub mod s3_maintenance;
pub mod s4_services;
pub mod s5_interactions;
pub mod s6_companion;
