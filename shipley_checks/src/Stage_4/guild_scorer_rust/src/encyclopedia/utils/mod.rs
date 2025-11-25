//! Encyclopedia utility modules
//!
//! - lookup_tables: EIVE semantic bins for label generation
//! - categorization: Height, CSR, confidence classification

pub mod lookup_tables;
pub mod categorization;

pub use lookup_tables::{get_eive_label, EiveAxis};
pub use categorization::{
    categorize_height, categorize_woodiness, categorize_confidence,
    get_csr_category, get_csr_description, map_koppen_to_usda,
};
