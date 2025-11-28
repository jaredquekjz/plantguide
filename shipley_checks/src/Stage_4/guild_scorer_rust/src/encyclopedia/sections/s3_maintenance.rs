//! S3: Maintenance Profile
//!
//! Rules for generating maintenance requirements based on CSR strategy.
//! Uses spread-based classification: SPREAD = MAX(C,S,R) - MIN(C,S,R)
//! - If SPREAD < 20%: Balanced (no dominant strategy)
//! - Otherwise: Dominant = axis with highest value
//!
//! Data Sources:
//! - CSR scores: `C`, `S`, `R` (0-100%)
//! - Height: `height_m` (for pruning accessibility)
//! - Growth form: `try_growth_form`
//! - Leaf phenology: `try_leaf_phenology` (for litter management)
//! - Leaf area: `LA` (for litter volume)
//! - Seed mass: `logSM` (for self-seeding potential)

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::*;
use crate::encyclopedia::utils::classify::*;

/// Generate the S3 Maintenance Profile section.
pub fn generate(data: &HashMap<String, Value>) -> String {
    let mut sections = Vec::new();
    sections.push("## Maintenance Profile".to_string());

    // Extract CSR values
    let c = get_f64(data, "C").unwrap_or(0.0);
    let s = get_f64(data, "S").unwrap_or(0.0);
    let r = get_f64(data, "R").unwrap_or(0.0);

    // CSR Strategy display with friendly explanation
    let csr_strategy = classify_csr_spread(c, s, r);
    sections.push(format!(
        "**Growth Strategy**: {} (C {:.0}% / S {:.0}% / R {:.0}%)",
        csr_spread_label(c, s, r), c, s, r
    ));
    sections.push(String::new());
    sections.push(csr_explanation(csr_strategy));

    // Maintenance level
    let height_m = get_f64(data, "height_m");
    let growth_form = get_str(data, "try_growth_form");
    let form_category = classify_growth_form(growth_form, height_m);

    let maint_level = classify_maintenance_level(c, s, r);
    sections.push(String::new());
    sections.push(format!("**Effort Level**: {}", maint_level.label()));

    // Growth behaviour (combines CSR characteristics + form-specific advice)
    sections.push(String::new());
    sections.push("**What to Expect**:".to_string());
    sections.push(growth_behaviour(csr_strategy, form_category));

    // Practical considerations (derived from S1 traits)
    let leaf_phenology = get_str(data, "try_leaf_phenology");
    let leaf_area = get_f64(data, "LA");
    let seed_mass_log = get_f64(data, "logSM");

    let practical = practical_considerations(height_m, leaf_phenology, leaf_area, seed_mass_log, csr_strategy);
    if !practical.is_empty() {
        sections.push(String::new());
        sections.push("**Practical Considerations**:".to_string());
        sections.push(practical);
    }

    // Watch for warnings
    let warnings = watch_for_warnings(csr_strategy, form_category);
    if !warnings.is_empty() {
        sections.push(String::new());
        sections.push("**Watch For**:".to_string());
        sections.push(warnings);
    }

    sections.join("\n")
}

/// Friendly explanation of CSR strategy for non-specialists.
fn csr_explanation(strategy: CsrStrategy) -> String {
    let intro = "*CSR is a key framework in plant ecology that classifies plants by survival strategy: **Competitors** (C) grow fast to dominate space and light, **Stress-tolerators** (S) endure difficult conditions patiently, and **Ruderals** (R) live short lives but reproduce prolifically.*";

    let specific = match strategy {
        CsrStrategy::CDominant => {
            "This plant scores highest in **C (Competitor)** — it's a vigorous grower that will actively spread and may outcompete neighbours. Needs more attention to keep in check."
        }
        CsrStrategy::SDominant => {
            "This plant scores highest in **S (Stress-tolerator)** — it's built for endurance, not speed. Grows slowly, tolerates neglect, and generally thrives when left alone."
        }
        CsrStrategy::RDominant => {
            "This plant scores highest in **R (Ruderal)** — it's a fast-living opportunist. Grows quickly, sets seed, and may not live long. Plan for replacement or let it reseed."
        }
        CsrStrategy::Balanced => {
            "This plant has a **balanced strategy** — it's adaptable and moderate in all respects. Neither aggressive nor demanding, it fits well in most garden situations."
        }
    };

    format!("{}\n\n{}", intro, specific)
}

/// Growth behaviour combining CSR strategy with form-specific advice.
fn growth_behaviour(strategy: CsrStrategy, form: GrowthFormCategory) -> String {
    let strategy_desc = match strategy {
        CsrStrategy::CDominant => {
            "Fast, vigorous grower with high nutrient demand. Benefits from annual feeding."
        }
        CsrStrategy::SDominant => {
            "Slow, steady grower with low nutrient demand."
        }
        CsrStrategy::RDominant => {
            "Rapid but short-lived. Moderate nutrient demand; plan for succession or self-seeding."
        }
        CsrStrategy::Balanced => {
            "Moderate growth rate. Adaptable to range of conditions; responsive to feeding but not demanding."
        }
    };

    let form_advice = composite_matrix_advice(strategy, form);

    format!("{} {}", strategy_desc, form_advice)
}

/// Composite Maintenance Matrix: CSR × Growth Form advice.
fn composite_matrix_advice(strategy: CsrStrategy, form: GrowthFormCategory) -> String {
    match (strategy, form) {
        // C-dominant combinations
        (CsrStrategy::CDominant, GrowthFormCategory::Tree) => {
            "May cast dense shade; thin annually to allow light below. High nutrient uptake may affect neighbours.".to_string()
        }
        (CsrStrategy::CDominant, GrowthFormCategory::Shrub) => {
            "Hard prune annually to control spread. Give wide spacing; root competition likely.".to_string()
        }
        (CsrStrategy::CDominant, GrowthFormCategory::Herb) => {
            "Divide every 1-2 years to control spread. Edge beds to prevent invasion.".to_string()
        }
        (CsrStrategy::CDominant, GrowthFormCategory::Vine) => {
            "Aggressive; may damage supports or smother hosts. Cut back 2-3 times per season.".to_string()
        }

        // S-dominant combinations
        (CsrStrategy::SDominant, GrowthFormCategory::Tree) => {
            "Long establishment period (5-10 years). Avoid fertiliser; formative pruning in youth only.".to_string()
        }
        (CsrStrategy::SDominant, GrowthFormCategory::Shrub) => {
            "Minimal watering once established. Shape only if needed; avoid hard pruning.".to_string()
        }
        (CsrStrategy::SDominant, GrowthFormCategory::Herb) => {
            "Near-zero maintenance; leave undisturbed. May decline if conditions too rich.".to_string()
        }
        (CsrStrategy::SDominant, GrowthFormCategory::Vine) => {
            "Slow to establish; train carefully in first years. Minimal intervention once settled.".to_string()
        }

        // R-dominant combinations
        (CsrStrategy::RDominant, GrowthFormCategory::Tree) => {
            "Unusual; likely pioneer species. Short-lived for a tree; plan replacement.".to_string()
        }
        (CsrStrategy::RDominant, GrowthFormCategory::Shrub) => {
            "Often short-lived (3-5 years). Self-seeding may need management.".to_string()
        }
        (CsrStrategy::RDominant, GrowthFormCategory::Herb) => {
            "Annual or short-lived perennial. Allow self-sowing or replant yearly.".to_string()
        }
        (CsrStrategy::RDominant, GrowthFormCategory::Vine) => {
            "May die back completely in winter. Rapid spring regrowth from base or seed.".to_string()
        }

        // Balanced combinations
        (CsrStrategy::Balanced, _) => {
            "Standard garden care applies. Moderate vigour; manageable with annual attention.".to_string()
        }
    }
}

/// Practical considerations derived from S1 trait data.
fn practical_considerations(
    height_m: Option<f64>,
    leaf_phenology: Option<&str>,
    leaf_area: Option<f64>,
    seed_mass_log: Option<f64>,
    strategy: CsrStrategy,
) -> String {
    let mut considerations = Vec::new();

    // Pruning accessibility based on height
    if let Some(h) = height_m {
        let pruning = if h >= 15.0 {
            format!("**Pruning**: Professional arborist needed at {:.0}m mature height", h)
        } else if h >= 6.0 {
            format!("**Pruning**: Ladder work required at {:.0}m; consider access", h)
        } else if h >= 2.5 {
            format!("**Pruning**: Reachable with long-handled tools at {:.1}m", h)
        } else {
            format!("**Pruning**: Easy access at {:.1}m; hand tools sufficient", h)
        };
        considerations.push(pruning);
    }

    // Spreading/seeding based on seed mass
    if let Some(log_sm) = seed_mass_log {
        let seed_mg = log_sm.exp();
        let seeding = if seed_mg < 1.0 {
            "**Spreading**: Dust-like seeds blow everywhere; expect baby plants popping up throughout the garden"
        } else if seed_mg < 10.0 {
            "**Spreading**: Tiny seeds; new plants will appear on their own; pull unwanted ones"
        } else if seed_mg < 100.0 {
            "**Spreading**: Small seeds; occasional new plants may appear nearby"
        } else if seed_mg < 1000.0 {
            "**Spreading**: Medium seeds don't travel far; birds may carry them around"
        } else {
            "**Spreading**: Large seeds stay close to parent; squirrels and birds may bury them elsewhere"
        };

        // Only show spreading note if relevant (R-dominant or small seeds)
        if seed_mg < 100.0 || matches!(strategy, CsrStrategy::RDominant) {
            considerations.push(seeding.to_string());
        }
    }

    // Leaf litter based on phenology + leaf area
    if let Some(phenology) = leaf_phenology {
        let is_deciduous = phenology.to_lowercase().contains("deciduous");
        if is_deciduous {
            let litter_desc = if let Some(la) = leaf_area {
                let area_cm2 = la / 100.0;
                if area_cm2 > 50.0 {
                    "**Leaf litter**: Deciduous with large leaves; significant autumn cleanup"
                } else if area_cm2 > 15.0 {
                    "**Leaf litter**: Deciduous with medium leaves; moderate autumn raking"
                } else {
                    "**Leaf litter**: Deciduous with small leaves; light autumn debris"
                }
            } else {
                "**Leaf litter**: Deciduous; expect autumn leaf drop"
            };
            considerations.push(litter_desc.to_string());
        }
    }

    considerations.join("\n")
}

/// Warnings based on CSR strategy and form.
fn watch_for_warnings(strategy: CsrStrategy, form: GrowthFormCategory) -> String {
    let mut warnings = Vec::new();

    match strategy {
        CsrStrategy::CDominant => {
            warnings.push("- May outcompete slower-growing neighbours");
            match form {
                GrowthFormCategory::Vine => {
                    warnings.push("- Can damage structures if unchecked");
                }
                GrowthFormCategory::Tree => {
                    warnings.push("- Dense shade may suppress understory plants");
                }
                _ => {}
            }
        }
        CsrStrategy::RDominant => {
            warnings.push("- Short-lived; plan for replacement or allow self-seeding");
        }
        _ => {}
    }

    warnings.join("\n")
}
