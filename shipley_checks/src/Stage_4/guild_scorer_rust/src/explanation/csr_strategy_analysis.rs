//! CSR Strategy Profile Analysis for M2 (Growth Compatibility)
//!
//! Analyzes plant CSR strategies, identifies conflicts and compatible groupings.

use serde::{Deserialize, Serialize};
use crate::metrics::m2_growth_compatibility::PlantCsrData;

/// CSR strategy profile showing per-plant breakdown and compatibility analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CsrStrategyProfile {
    /// Per-plant CSR data with vernacular names
    pub plants: Vec<PlantCsrEntry>,

    /// Detected CSR conflicts with explanations
    pub conflicts: Vec<CsrConflict>,

    /// Compatible plant groupings
    pub compatible_groups: Vec<CompatibleGroup>,

    /// Summary counts
    pub summary: CsrSummary,
}

/// Individual plant CSR entry for display
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlantCsrEntry {
    /// Plant display name (with vernacular)
    pub display_name: String,

    /// Dominant strategy label
    pub dominant_strategy: String,

    /// C percentile (0-100)
    pub c_percentile: f64,

    /// S percentile (0-100)
    pub s_percentile: f64,

    /// R percentile (0-100)
    pub r_percentile: f64,

    /// Whether this plant has high C (>75th percentile)
    pub high_c: bool,

    /// Whether this plant has high S (>75th percentile)
    pub high_s: bool,

    /// Whether this plant has high R (>75th percentile)
    pub high_r: bool,
}

/// Detected CSR conflict
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CsrConflict {
    /// Type of conflict (e.g., "C-C", "C-S", "C-R", "R-R")
    pub conflict_type: String,

    /// Plants involved in this conflict
    pub plants: Vec<String>,

    /// Explanation of the conflict
    pub explanation: String,
}

/// Compatible plant grouping
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompatibleGroup {
    /// Strategy shared by this group
    pub strategy: String,

    /// Plants in this group
    pub plants: Vec<String>,

    /// Why they are compatible
    pub reason: String,
}

/// Summary statistics for CSR analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CsrSummary {
    /// Number of Competitive-dominant plants
    pub high_c_count: usize,

    /// Number of Stress-tolerant-dominant plants
    pub high_s_count: usize,

    /// Number of Ruderal-dominant plants
    pub high_r_count: usize,

    /// Number of Mixed-strategy plants
    pub mixed_count: usize,

    /// Total conflicts detected
    pub total_conflicts: f64,
}

/// Generate CSR strategy profile from M2 result data
pub fn analyze_csr_strategies(
    plant_data: &[PlantCsrData],
    total_conflicts: f64,
    high_c_count: usize,
    high_s_count: usize,
    high_r_count: usize,
) -> CsrStrategyProfile {
    const PERCENTILE_THRESHOLD: f64 = 75.0;

    // Build plant entries
    let plants: Vec<PlantCsrEntry> = plant_data
        .iter()
        .map(|p| PlantCsrEntry {
            display_name: p.display_name.clone(),
            dominant_strategy: p.dominant_strategy.clone(),
            c_percentile: p.c_percentile,
            s_percentile: p.s_percentile,
            r_percentile: p.r_percentile,
            high_c: p.c_percentile > PERCENTILE_THRESHOLD,
            high_s: p.s_percentile > PERCENTILE_THRESHOLD,
            high_r: p.r_percentile > PERCENTILE_THRESHOLD,
        })
        .collect();

    // Identify conflicts
    let conflicts = identify_conflicts(&plants);

    // Identify compatible groups
    let compatible_groups = identify_compatible_groups(&plants);

    // Count mixed-strategy plants
    let mixed_count = plant_data
        .iter()
        .filter(|p| p.dominant_strategy == "Mixed")
        .count();

    CsrStrategyProfile {
        plants,
        conflicts,
        compatible_groups,
        summary: CsrSummary {
            high_c_count,
            high_s_count,
            high_r_count,
            mixed_count,
            total_conflicts,
        },
    }
}

/// Identify CSR conflicts between plants
fn identify_conflicts(plants: &[PlantCsrEntry]) -> Vec<CsrConflict> {
    let mut conflicts = Vec::new();

    // Collect high-C, high-S, high-R plants
    let high_c: Vec<&PlantCsrEntry> = plants.iter().filter(|p| p.high_c).collect();
    let high_s: Vec<&PlantCsrEntry> = plants.iter().filter(|p| p.high_s).collect();
    let high_r: Vec<&PlantCsrEntry> = plants.iter().filter(|p| p.high_r).collect();

    // C-C conflicts (multiple competitive plants competing for same resources)
    if high_c.len() >= 2 {
        conflicts.push(CsrConflict {
            conflict_type: "C-C".to_string(),
            plants: high_c.iter().map(|p| p.display_name.clone()).collect(),
            explanation: "Multiple competitive plants may compete intensely for light, nutrients, and space. Consider spatial separation or staggered planting times.".to_string(),
        });
    }

    // C-S conflicts (competitive plants may shade out stress-tolerant sun-lovers)
    if !high_c.is_empty() && !high_s.is_empty() {
        let c_plants: Vec<String> = high_c.iter().map(|p| p.display_name.clone()).collect();
        let s_plants: Vec<String> = high_s.iter().map(|p| p.display_name.clone()).collect();

        conflicts.push(CsrConflict {
            conflict_type: "C-S".to_string(),
            plants: [c_plants, s_plants].concat(),
            explanation: "Competitive plants may shade out stress-tolerant plants unless the stress-tolerant plants are shade-adapted or have significant height separation.".to_string(),
        });
    }

    // C-R conflicts (competitive plants may outcompete ruderals)
    if !high_c.is_empty() && !high_r.is_empty() {
        let c_plants: Vec<String> = high_c.iter().map(|p| p.display_name.clone()).collect();
        let r_plants: Vec<String> = high_r.iter().map(|p| p.display_name.clone()).collect();

        conflicts.push(CsrConflict {
            conflict_type: "C-R".to_string(),
            plants: [c_plants, r_plants].concat(),
            explanation: "Competitive plants may suppress ruderal species. Ruderals thrive in disturbed areas - consider giving them dedicated gaps or edges.".to_string(),
        });
    }

    // R-R conflicts (mild - multiple ruderals competing for disturbed areas)
    if high_r.len() >= 2 {
        conflicts.push(CsrConflict {
            conflict_type: "R-R".to_string(),
            plants: high_r.iter().map(|p| p.display_name.clone()).collect(),
            explanation: "Multiple ruderal plants may compete for disturbed areas, but this is generally a mild conflict.".to_string(),
        });
    }

    conflicts
}

/// Identify compatible plant groupings
fn identify_compatible_groups(plants: &[PlantCsrEntry]) -> Vec<CompatibleGroup> {
    let mut groups = Vec::new();

    // Group by dominant strategy
    let competitive: Vec<&PlantCsrEntry> = plants
        .iter()
        .filter(|p| p.dominant_strategy.contains("Competitive") || p.dominant_strategy == "C-leaning")
        .collect();

    let stress_tolerant: Vec<&PlantCsrEntry> = plants
        .iter()
        .filter(|p| p.dominant_strategy.contains("Stress-tolerant") || p.dominant_strategy == "S-leaning")
        .collect();

    let ruderal: Vec<&PlantCsrEntry> = plants
        .iter()
        .filter(|p| p.dominant_strategy.contains("Ruderal") || p.dominant_strategy == "R-leaning")
        .collect();

    let mixed: Vec<&PlantCsrEntry> = plants
        .iter()
        .filter(|p| p.dominant_strategy == "Mixed")
        .collect();

    // Add compatible groups (single strategy type = compatible)
    if competitive.len() == 1 {
        groups.push(CompatibleGroup {
            strategy: "Competitive".to_string(),
            plants: competitive.iter().map(|p| p.display_name.clone()).collect(),
            reason: "Single competitive plant - no competition conflict".to_string(),
        });
    }

    if stress_tolerant.len() >= 1 && competitive.is_empty() {
        groups.push(CompatibleGroup {
            strategy: "Stress-tolerant".to_string(),
            plants: stress_tolerant.iter().map(|p| p.display_name.clone()).collect(),
            reason: "Stress-tolerant plants without competitive dominants - compatible niche".to_string(),
        });
    }

    if ruderal.len() >= 1 && competitive.is_empty() {
        groups.push(CompatibleGroup {
            strategy: "Ruderal".to_string(),
            plants: ruderal.iter().map(|p| p.display_name.clone()).collect(),
            reason: "Ruderal plants without competitive dominants - can exploit gaps".to_string(),
        });
    }

    if !mixed.is_empty() {
        groups.push(CompatibleGroup {
            strategy: "Mixed".to_string(),
            plants: mixed.iter().map(|p| p.display_name.clone()).collect(),
            reason: "Balanced CSR strategies - flexible resource use".to_string(),
        });
    }

    groups
}
