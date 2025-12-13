use serde::{Deserialize, Serialize};
use crate::metrics::GuildType;
use crate::explanation::pest_analysis::PestProfile;
use crate::explanation::fungi_network_analysis::FungiNetworkProfile;
use crate::explanation::pollinator_network_analysis::PollinatorNetworkProfile;
use crate::explanation::biocontrol_network_analysis::BiocontrolNetworkProfile;
use crate::explanation::pathogen_control_network_analysis::PathogenControlNetworkProfile;
use crate::explanation::csr_strategy_analysis::CsrStrategyProfile;
use crate::explanation::taxonomic_profile_analysis::TaxonomicProfile;
use crate::explanation::structural_diversity_analysis::StructuralDiversityProfile;

/// Complete explanation for a guild
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Explanation {
    pub overall: OverallExplanation,
    pub climate: ClimateExplanation,
    pub benefits: Vec<BenefitCard>,
    pub warnings: Vec<WarningCard>,
    pub risks: Vec<RiskCard>,
    pub metrics_display: MetricsDisplay,
    pub pest_profile: Option<PestProfile>,
    pub taxonomic_profile: Option<TaxonomicProfile>,
    pub csr_strategy_profile: Option<CsrStrategyProfile>,
    pub fungi_network_profile: Option<FungiNetworkProfile>,
    pub pollinator_network_profile: Option<PollinatorNetworkProfile>,
    pub biocontrol_network_profile: Option<BiocontrolNetworkProfile>,
    pub pathogen_control_profile: Option<PathogenControlNetworkProfile>,
    pub structural_diversity_profile: Option<StructuralDiversityProfile>,
    pub ecosystem_services: Option<Vec<crate::explanation::ecosystem_services::EcosystemServiceCard>>,
}

/// Overall score interpretation with stars
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OverallExplanation {
    pub score: f64,
    pub stars: String,  // "★★★★☆"
    pub label: String,  // "Excellent" / "Good" / "Fair" / "Poor"
    pub message: String,
    /// Guild type classification (M2)
    pub guild_type: GuildType,
    /// Human-readable guild type name
    pub guild_type_display: String,
    /// Environment suitability note for this guild type
    pub guild_type_note: String,
}

/// Climate compatibility information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClimateExplanation {
    pub compatible: bool,
    pub tier: String,         // "tier_3_humid_temperate"
    pub tier_display: String, // "Tier 3 (Humid Temperate)"
    pub message: String,
}

/// Benefit card for positive guild characteristics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BenefitCard {
    pub benefit_type: String, // "phylogenetic_diversity", "mycorrhizal_network", etc.
    pub metric_code: String,  // "M1", "M5", etc.
    pub title: String,
    pub message: String,
    pub detail: String,
    pub evidence: Option<String>,
}

/// Warning card for potential issues
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WarningCard {
    pub warning_type: String, // "csr_conflict", "nitrogen_excess", "ph_incompatible"
    pub severity: Severity,
    pub icon: String, // "⚠️", "⚡", "🚨"
    pub message: String,
    pub detail: String,
    pub advice: String,
}

/// Risk card for significant concerns
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RiskCard {
    pub risk_type: String, // "pest_vulnerability", "disease_risk"
    pub severity: Severity,
    pub icon: String,
    pub title: String,
    pub message: String,
    pub detail: String,
    pub advice: String,
}

/// Severity level for warnings and risks
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum Severity {
    None,
    Info,
    Low,
    Medium,
    High,
}

impl Severity {
    /// Derive severity from a score (0-100)
    pub fn from_score(score: f64) -> Self {
        match score {
            s if s >= 80.0 => Severity::None,
            s if s >= 60.0 => Severity::Low,
            s if s >= 40.0 => Severity::Medium,
            _ => Severity::High,
        }
    }
}

/// Metrics display grouped by category
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricsDisplay {
    pub universal: Vec<MetricCard>, // M1, M2, M3, M4
    pub bonus: Vec<MetricCard>,     // M5, M6, M7
}

/// Individual metric card
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricCard {
    pub code: String,              // "M1"
    pub name: String,              // "Pest & Pathogen Independence"
    pub score: f64,                // Display score (0-100)
    pub raw: f64,                  // Raw score
    pub interpretation: String,    // "Excellent" / "Good" / "Fair" / "Poor"
}

/// Fragment of explanation from a single metric
#[derive(Debug, Clone)]
pub struct MetricFragment {
    pub benefit: Option<BenefitCard>,
    pub warning: Option<WarningCard>,
    pub risk: Option<RiskCard>,
}

impl MetricFragment {
    /// Create an empty fragment
    pub fn empty() -> Self {
        Self {
            benefit: None,
            warning: None,
            risk: None,
        }
    }

    /// Create a fragment with only a benefit
    pub fn with_benefit(benefit: BenefitCard) -> Self {
        Self {
            benefit: Some(benefit),
            warning: None,
            risk: None,
        }
    }

    /// Create a fragment with only a warning
    pub fn with_warning(warning: WarningCard) -> Self {
        Self {
            benefit: None,
            warning: Some(warning),
            risk: None,
        }
    }

    /// Create a fragment with only a risk
    pub fn with_risk(risk: RiskCard) -> Self {
        Self {
            benefit: None,
            warning: None,
            risk: Some(risk),
        }
    }
}
