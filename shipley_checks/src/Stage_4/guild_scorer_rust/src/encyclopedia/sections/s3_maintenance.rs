//! S3: Maintenance Profile
//!
//! Rules for generating maintenance requirements based on CSR strategy.
//! Uses absolute thresholds for maintenance classification (>60% = dominant).
//!
//! Data Sources:
//! - CSR scores: `C`, `S`, `R` (0-100%)
//! - Height: `height_m`
//! - Growth form: `try_growth_form`

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

    // CSR Strategy display
    let csr_strategy = classify_csr_absolute(c, s, r);
    sections.push(format!(
        "**CSR Strategy**: C {:.0}% / S {:.0}% / R {:.0}% ({})",
        c, s, r, csr_leaning_label(c, s, r)
    ));

    // Growth form and height
    let growth_form = get_str(data, "try_growth_form");
    let height_m = get_f64(data, "height_m");
    let form_category = classify_growth_form(growth_form, height_m);

    sections.push(format!("**Growth Form**: {}", form_category.label()));
    if let Some(h) = height_m {
        sections.push(format!("**Height**: {:.1}m", h));
    }

    // Maintenance level
    let maint_level = classify_maintenance_level(c, s, r);
    let size_mult = size_scaling_multiplier(height_m);
    let base_hours = match maint_level {
        MaintenanceLevel::Low => 1.5,
        MaintenanceLevel::LowMedium => 2.5,
        MaintenanceLevel::Medium => 3.5,
        MaintenanceLevel::MediumHigh => 4.5,
        MaintenanceLevel::High => 6.0,
    };
    let adjusted_hours = base_hours * size_mult;

    sections.push(format!(
        "**Maintenance Level**: {} (~{:.0} hrs/yr)",
        maint_level.label(),
        adjusted_hours
    ));

    // Growth characteristics
    sections.push(String::new());
    sections.push("**Growth Characteristics**:".to_string());
    sections.push(growth_characteristics(csr_strategy, form_category));

    // Form-specific notes (Composite Maintenance Matrix)
    sections.push(String::new());
    sections.push("**Form-Specific Notes**:".to_string());
    sections.push(composite_matrix_advice(csr_strategy, form_category));

    // Seasonal tasks
    sections.push(String::new());
    sections.push("**Seasonal Tasks**:".to_string());
    sections.push(seasonal_tasks(csr_strategy, form_category));

    // Watch for
    let warnings = watch_for_warnings(csr_strategy, form_category);
    if !warnings.is_empty() {
        sections.push(String::new());
        sections.push("**Watch For**:".to_string());
        sections.push(warnings);
    }

    sections.join("\n")
}

/// Get descriptive CSR leaning label.
fn csr_leaning_label(c: f64, s: f64, r: f64) -> &'static str {
    // Using absolute thresholds for S3
    if c > 60.0 && s < 30.0 && r < 30.0 {
        "C-dominant"
    } else if s > 60.0 && c < 30.0 && r < 30.0 {
        "S-dominant"
    } else if r > 60.0 && c < 30.0 && s < 30.0 {
        "R-dominant"
    } else if c > 45.0 && s > 35.0 {
        "CS-intermediate"
    } else if c > 45.0 && r > 35.0 {
        "CR-intermediate"
    } else if s > 45.0 && r > 35.0 {
        "SR-intermediate"
    } else if c > 45.0 {
        "C-leaning"
    } else if s > 45.0 {
        "S-leaning"
    } else if r > 45.0 {
        "R-leaning"
    } else {
        "Balanced"
    }
}

/// Growth characteristics based on CSR strategy.
fn growth_characteristics(strategy: CsrStrategy, _form: GrowthFormCategory) -> String {
    let mut chars = Vec::new();

    match strategy {
        CsrStrategy::CDominant => {
            chars.push("- Fast, vigorous growth");
            chars.push("- High nutrient demand");
            chars.push("- Benefits from annual feeding");
        }
        CsrStrategy::SDominant => {
            chars.push("- Slow, steady growth");
            chars.push("- Low nutrient demand");
            chars.push("- Drought-tolerant once established");
        }
        CsrStrategy::RDominant => {
            chars.push("- Rapid but brief growth");
            chars.push("- Moderate nutrient demand");
            chars.push("- Short-lived; plan for succession");
        }
        CsrStrategy::Balanced => {
            chars.push("- Moderate growth rate");
            chars.push("- Adaptable to range of conditions");
            chars.push("- Responsive to feeding but not demanding");
        }
    }

    chars.join("\n")
}

/// Composite Maintenance Matrix: CSR × Growth Form advice.
/// From S3 planning doc.
fn composite_matrix_advice(strategy: CsrStrategy, form: GrowthFormCategory) -> String {
    match (strategy, form) {
        // C-dominant combinations
        (CsrStrategy::CDominant, GrowthFormCategory::Tree) => {
            "Annual thinning to allow light below; may cast dense shade. Monitor for structural dominance; neighbours may struggle. High nutrient uptake; nearby plants may need supplemental feeding.".to_string()
        }
        (CsrStrategy::CDominant, GrowthFormCategory::Shrub) => {
            "Hard prune annually to control spread; suckering common. Give wide spacing; aggressive root competition likely. Contain with root barriers if space is limited.".to_string()
        }
        (CsrStrategy::CDominant, GrowthFormCategory::Herb) => {
            "Division every 1-2 years to control spread. Edge beds to prevent invasion of adjacent areas. Heavy feeders; enrich soil annually.".to_string()
        }
        (CsrStrategy::CDominant, GrowthFormCategory::Vine) => {
            "Aggressive growers; may damage supports or smother host plants. Regular cutting back (2-3 times per growing season). Do not plant near buildings without robust control measures.".to_string()
        }

        // S-dominant combinations
        (CsrStrategy::SDominant, GrowthFormCategory::Tree) => {
            "Long establishment period (5-10 years); patience required. Avoid fertiliser; naturally conservative nutrient cycling. Formative pruning in youth only; minimal intervention thereafter.".to_string()
        }
        (CsrStrategy::SDominant, GrowthFormCategory::Shrub) => {
            "Drought-tolerant once established; minimal watering. Shape only if aesthetically needed; avoid hard pruning. Slow recovery from damage; protect during establishment.".to_string()
        }
        (CsrStrategy::SDominant, GrowthFormCategory::Herb) => {
            "Near-zero maintenance; leave undisturbed. Avoid overwatering; adapted to poor soils. May decline if conditions become too rich.".to_string()
        }
        (CsrStrategy::SDominant, GrowthFormCategory::Vine) => {
            "Slow to establish; train carefully in first years. Once established, minimal intervention required. Avoid fertiliser; will not respond well to rich conditions.".to_string()
        }

        // R-dominant combinations
        (CsrStrategy::RDominant, GrowthFormCategory::Tree) => {
            "Unusual combination; likely pioneer species. Short-lived for a tree; plan for replacement. Fast initial growth, then decline.".to_string()
        }
        (CsrStrategy::RDominant, GrowthFormCategory::Shrub) => {
            "Often short-lived (3-5 years); plan for replacement. Self-seeding may require management. Remove spent growth promptly; encourages new growth.".to_string()
        }
        (CsrStrategy::RDominant, GrowthFormCategory::Herb) => {
            "Annuals or short-lived perennials; replant each year or allow self-sowing. Deadhead to extend flowering or allow seeding depending on preference. Collect seed before removal for next season.".to_string()
        }
        (CsrStrategy::RDominant, GrowthFormCategory::Vine) => {
            "May die back completely in winter; cut to base. Rapid spring regrowth from base or seed. Short-lived perennials or tender; protect or replant annually.".to_string()
        }

        // Balanced combinations
        (CsrStrategy::Balanced, _) => {
            "Standard garden care applies. Adaptable to range of conditions. Moderate vigour; manageable with annual attention. Responsive to feeding but not demanding.".to_string()
        }
    }
}

/// Seasonal tasks based on CSR strategy.
fn seasonal_tasks(strategy: CsrStrategy, form: GrowthFormCategory) -> String {
    let mut tasks = Vec::new();

    match strategy {
        CsrStrategy::CDominant => {
            tasks.push("- **Spring**: Feed generously, shape if needed");
            tasks.push("- **Summer**: Water in dry spells, manage spread");
            tasks.push("- **Autumn**: Hard prune if required, mulch");
            tasks.push("- **Winter**: Plan containment for vigorous growth");
        }
        CsrStrategy::SDominant => {
            tasks.push("- **Spring**: Minimal intervention, check health");
            tasks.push("- **Summer**: Water only in severe drought");
            tasks.push("- **Autumn**: Light tidy if needed");
            tasks.push("- **Winter**: Protect only if borderline hardy");
        }
        CsrStrategy::RDominant => {
            match form {
                GrowthFormCategory::Herb => {
                    tasks.push("- **Spring**: Sow/plant replacements");
                    tasks.push("- **Summer**: Deadhead, collect seed");
                    tasks.push("- **Autumn**: Clear spent growth, save seed");
                    tasks.push("- **Winter**: Plan succession planting");
                }
                _ => {
                    tasks.push("- **Spring**: Check for winter losses, replant");
                    tasks.push("- **Summer**: Enjoy rapid growth, deadhead");
                    tasks.push("- **Autumn**: Remove spent material");
                    tasks.push("- **Winter**: Protect tender growth or accept losses");
                }
            }
        }
        CsrStrategy::Balanced => {
            tasks.push("- **Spring**: Feed, shape if needed");
            tasks.push("- **Summer**: Water in dry spells");
            tasks.push("- **Autumn**: Mulch, tidy");
            tasks.push("- **Winter**: Protect if borderline hardy");
        }
    }

    tasks.join("\n")
}

/// Warnings based on CSR strategy and form.
fn watch_for_warnings(strategy: CsrStrategy, form: GrowthFormCategory) -> String {
    let mut warnings = Vec::new();

    match strategy {
        CsrStrategy::CDominant => {
            warnings.push("- May outcompete slower neighbours");
            warnings.push("- Give adequate space for mature spread");
            match form {
                GrowthFormCategory::Vine => {
                    warnings.push("- Can damage structures if unchecked");
                }
                GrowthFormCategory::Tree => {
                    warnings.push("- Dense shade may exclude understory");
                }
                _ => {}
            }
        }
        CsrStrategy::RDominant => {
            warnings.push("- Short-lived; plan for replacement");
            warnings.push("- May self-seed prolifically");
        }
        _ => {}
    }

    warnings.join("\n")
}
