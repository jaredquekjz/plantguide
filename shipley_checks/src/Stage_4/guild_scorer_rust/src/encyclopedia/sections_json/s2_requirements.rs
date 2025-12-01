//! S2: Growing Requirements (JSON) - STUB
//! TODO: Clone from sections_md/s2_requirements.rs

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::view_models::RequirementsSection;
use crate::encyclopedia::suitability::local_conditions::LocalConditions;

pub fn generate(
    _data: &HashMap<String, Value>,
    _local: Option<&LocalConditions>,
) -> RequirementsSection {
    // TODO: Implement
    RequirementsSection::default()
}
