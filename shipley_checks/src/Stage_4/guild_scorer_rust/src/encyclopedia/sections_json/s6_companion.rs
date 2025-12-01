//! S6: Guild Potential / Companion Planting (JSON) - STUB
//! TODO: Clone from sections_md/s6_companion.rs

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::view_models::CompanionSection;
use crate::encyclopedia::types::{OrganismProfile, FungalCounts};

pub fn generate(
    _data: &HashMap<String, Value>,
    _organism_profile: Option<&OrganismProfile>,
    _fungal_counts: Option<&FungalCounts>,
) -> CompanionSection {
    // TODO: Implement
    CompanionSection::default()
}
