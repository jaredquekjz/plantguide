//! Shared data types for encyclopedia generation.
//!
//! Data sources:
//! - Plant data: HashMap from Phase 7 parquet columns
//! - Organism counts: Parsed from organism_profiles_11711.parquet
//! - Fungal counts: Parsed from fungal_guilds_hybrid_11711.parquet

use std::collections::HashMap;
use serde_json::Value;

/// Organism interaction counts from GloBI data.
/// Source: organism_profiles_11711.parquet
#[derive(Debug, Clone, Default)]
pub struct OrganismCounts {
    pub pollinators: usize,
    pub visitors: usize,
    pub herbivores: usize,
    pub pathogens: usize,
    pub predators: usize,
}

/// Organism interaction lists with actual species names.
/// Source: organism_profiles_11711.parquet (list columns)
#[derive(Debug, Clone, Default)]
pub struct OrganismLists {
    pub pollinators: Vec<String>,
    pub herbivores: Vec<String>,  // Includes parasites (host plant relationships)
    pub predators: Vec<String>,   // Beneficial insects that prey on pests
    pub fungivores: Vec<String>,  // Organisms that eat fungi (biocontrol for pathogenic fungi)
}

impl OrganismLists {
    /// Convert to counts for backward compatibility
    pub fn to_counts(&self) -> OrganismCounts {
        OrganismCounts {
            pollinators: self.pollinators.len(),
            visitors: 0, // Not tracked in lists
            herbivores: self.herbivores.len(),
            pathogens: 0, // Not tracked in lists (see FungalCounts)
            predators: self.predators.len(),
        }
    }
}

/// Organisms grouped by category for display
#[derive(Debug, Clone, Default)]
pub struct CategorizedOrganisms {
    pub category: String,
    pub organisms: Vec<String>,
}

/// Full organism profile with categorization for encyclopedia display
#[derive(Debug, Clone, Default)]
pub struct OrganismProfile {
    pub pollinators_by_category: Vec<CategorizedOrganisms>,
    pub herbivores_by_category: Vec<CategorizedOrganisms>,
    pub predators_by_category: Vec<CategorizedOrganisms>,
    pub fungivores_by_category: Vec<CategorizedOrganisms>,
    pub total_pollinators: usize,
    pub total_herbivores: usize,
    pub total_predators: usize,
    pub total_fungivores: usize,
}

/// Fungal association counts from FungalTraits/FunGuild data.
/// Source: fungal_guilds_hybrid_11711.parquet
#[derive(Debug, Clone, Default)]
pub struct FungalCounts {
    pub amf: usize,
    pub emf: usize,
    pub endophytes: usize,
    pub mycoparasites: usize,
    pub entomopathogens: usize,
    pub pathogenic: usize,  // Plant pathogenic fungi (diseases)
}

/// Pathogen with observation count (from GloBI pathogenOf/parasiteOf records)
/// Source: pathogens_ranked.parquet (Phase 7)
#[derive(Debug, Clone)]
pub struct RankedPathogen {
    pub taxon: String,
    pub observation_count: usize,
}

/// Pathogen with observation count and disease name (joined with Phase 7b)
/// Source: pathogens_ranked.parquet LEFT JOIN pathogen_diseases.parquet
#[derive(Debug, Clone)]
pub struct RankedPathogenWithDisease {
    pub taxon: String,
    pub observation_count: usize,
    pub disease_name: Option<String>,
    pub disease_type: Option<String>,
}

/// Pathogenic fungus with disease name (simplified flow - no observation counts)
/// Source: fungi_flat.parquet (pathogenic_fungi) LEFT JOIN pathogen_diseases.parquet
#[derive(Debug, Clone)]
pub struct PathogenicFungus {
    pub taxon: String,
    pub disease_name: Option<String>,
    pub disease_type: Option<String>,
}

/// Beneficial fungi species (biocontrol agents)
/// Source: fungi_flat.parquet (mycoparasite_fungi, entomopathogenic_fungi)
#[derive(Debug, Clone, Default)]
pub struct BeneficialFungi {
    pub mycoparasites: Vec<String>,      // Attack plant diseases
    pub entomopathogens: Vec<String>,    // Kill pest insects
}

/// CSR strategy classification (Grime's C-S-R triangle).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum CsrStrategy {
    CDominant,    // Competitor: C percentile > 75 (raw > 41.3%)
    SDominant,    // Stress-tolerator: S percentile > 75 (raw > 72.2%)
    RDominant,    // Ruderal: R percentile > 75 (raw > 47.6%)
    Balanced,     // No single strategy dominant
}

impl CsrStrategy {
    pub fn label(&self) -> &'static str {
        match self {
            CsrStrategy::CDominant => "C-dominant (Competitor)",
            CsrStrategy::SDominant => "S-dominant (Stress-tolerator)",
            CsrStrategy::RDominant => "R-dominant (Ruderal)",
            CsrStrategy::Balanced => "Balanced",
        }
    }
}

/// Growth form categories for guild analysis.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum GrowthFormCategory {
    Tree,        // height > 5m or growth_form contains "tree"
    Shrub,       // height 1-5m
    Herb,        // height < 1m
    Vine,        // growth_form contains "vine" or "liana"
}

impl GrowthFormCategory {
    pub fn label(&self) -> &'static str {
        match self {
            GrowthFormCategory::Tree => "Tree",
            GrowthFormCategory::Shrub => "Shrub",
            GrowthFormCategory::Herb => "Herb/Ground cover",
            GrowthFormCategory::Vine => "Vine/Climber",
        }
    }
}

/// Structural layer based on height.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum StructuralLayer {
    Canopy,      // > 10m
    SubCanopy,   // 5-10m
    TallShrub,   // 2-5m
    Understory,  // 0.5-2m
    GroundCover, // < 0.5m
}

impl StructuralLayer {
    pub fn label(&self) -> &'static str {
        match self {
            StructuralLayer::Canopy => "Canopy",
            StructuralLayer::SubCanopy => "Sub-canopy",
            StructuralLayer::TallShrub => "Tall shrub layer",
            StructuralLayer::Understory => "Understory",
            StructuralLayer::GroundCover => "Ground cover",
        }
    }
}

/// Mycorrhizal association type.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum MycorrhizalType {
    AMF,            // Arbuscular only
    EMF,            // Ectomycorrhizal only
    Dual,           // Both AMF and EMF
    NonMycorrhizal, // Neither documented
}

impl MycorrhizalType {
    pub fn label(&self) -> &'static str {
        match self {
            MycorrhizalType::AMF => "AMF (Arbuscular)",
            MycorrhizalType::EMF => "EMF (Ectomycorrhizal)",
            MycorrhizalType::Dual => "Dual (AMF + EMF)",
            MycorrhizalType::NonMycorrhizal => "Undocumented",
        }
    }
}

/// Maintenance level derived from CSR strategy.
#[derive(Debug, Clone, Copy)]
pub enum MaintenanceLevel {
    Low,
    LowMedium,
    Medium,
    MediumHigh,
    High,
}

impl MaintenanceLevel {
    pub fn label(&self) -> &'static str {
        match self {
            MaintenanceLevel::Low => "LOW",
            MaintenanceLevel::LowMedium => "LOW-MEDIUM",
            MaintenanceLevel::Medium => "MEDIUM",
            MaintenanceLevel::MediumHigh => "MEDIUM-HIGH",
            MaintenanceLevel::High => "HIGH",
        }
    }

    pub fn hours_per_year(&self) -> &'static str {
        match self {
            MaintenanceLevel::Low => "1-2 hrs/yr",
            MaintenanceLevel::LowMedium => "2-3 hrs/yr",
            MaintenanceLevel::Medium => "3-4 hrs/yr",
            MaintenanceLevel::MediumHigh => "4-5 hrs/yr",
            MaintenanceLevel::High => "5-7 hrs/yr",
        }
    }
}

// ============================================================================
// Helper functions for extracting values from HashMap<String, Value>
// ============================================================================

/// Extract a string value from the plant data HashMap.
pub fn get_str<'a>(data: &'a HashMap<String, Value>, key: &str) -> Option<&'a str> {
    data.get(key).and_then(|v| v.as_str())
}

/// Extract an f64 value from the plant data HashMap.
/// Handles both numeric JSON values and string-encoded numbers (from Arrow serialization).
pub fn get_f64(data: &HashMap<String, Value>, key: &str) -> Option<f64> {
    data.get(key).and_then(|v| {
        // Try numeric first
        v.as_f64().or_else(|| {
            // Fall back to parsing string
            v.as_str().and_then(|s| s.parse::<f64>().ok())
        })
    })
}

/// Extract a usize value from the plant data HashMap.
/// Handles both numeric JSON values and string-encoded numbers.
pub fn get_usize(data: &HashMap<String, Value>, key: &str) -> Option<usize> {
    data.get(key).and_then(|v| {
        v.as_u64().map(|n| n as usize).or_else(|| {
            v.as_str().and_then(|s| s.parse::<usize>().ok())
        })
    })
}

/// Format an optional f64 value with specified decimal places.
pub fn fmt_f64(val: Option<f64>, decimals: usize) -> String {
    match val {
        Some(v) => format!("{:.prec$}", v, prec = decimals),
        None => "—".to_string(),
    }
}

/// Format an optional f64 value as a percentage.
pub fn fmt_pct(val: Option<f64>) -> String {
    match val {
        Some(v) => format!("{:.1}%", v),
        None => "—".to_string(),
    }
}
