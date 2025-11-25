//! Encyclopedia Section Generators
//!
//! Each section module generates a specific part of the plant encyclopedia article.

pub mod s1_identity_card;
pub mod s2_growing_requirements;
pub mod s3_maintenance_profile;
pub mod s4_ecosystem_services;
pub mod s5_biological_interactions;
pub mod s6_companion_planting;
pub mod s7_biodiversity_value;

pub use s1_identity_card::generate_identity_card;
pub use s2_growing_requirements::generate_growing_requirements;
pub use s3_maintenance_profile::generate_maintenance_profile;
pub use s4_ecosystem_services::generate_ecosystem_services;
pub use s5_biological_interactions::generate_biological_interactions;
pub use s6_companion_planting::generate_companion_planting;
pub use s7_biodiversity_value::generate_biodiversity_value;
