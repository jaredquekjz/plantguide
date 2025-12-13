use crate::explanation::types::{BenefitCard, MetricFragment};
use crate::metrics::M3Result;

/// Generate explanation fragment for M3 (Insect Pest Control)
///
/// Measures natural biocontrol via predators and parasitoids.
/// Higher scores indicate more beneficial insects that suppress pests.
/// Lower scores indicate fewer documented biocontrol agents.
pub fn generate_m3_fragment(m3: &M3Result, display_score: f64) -> MetricFragment {
    // Coverage-based interpretation
    let coverage_pct = m3.raw; // Now stores coverage % (0-100)
    let plants_covered = m3.plants_with_biocontrol;
    let total_plants = m3.total_plants;

    let interpretation = if display_score >= 80.0 {
        "Excellent biocontrol - abundant predators and parasitoids provide strong pest suppression"
    } else if display_score >= 60.0 {
        "Good biocontrol - beneficial insects provide meaningful pest suppression"
    } else if display_score >= 40.0 {
        "Moderate biocontrol - some beneficial insects present but coverage may be limited"
    } else {
        "Limited biocontrol - few documented predators/parasitoids, may need supplemental pest management"
    };

    MetricFragment::with_benefit(BenefitCard {
        benefit_type: "insect_control".to_string(),
        metric_code: "M4".to_string(), // Biocontrol is now M4 (2025-12 reorder)
        title: "Natural Insect Pest Control".to_string(),
        message: format!(
            "{}th percentile - {:.0}% coverage ({}/{} plants have biocontrol)",
            display_score.round() as i32,
            coverage_pct,
            plants_covered,
            total_plants
        ),
        detail: format!(
            "Plants attract beneficial insects (predators and parasitoids) that naturally suppress pest populations. {}",
            interpretation
        ),
        evidence: None,
    })
}
