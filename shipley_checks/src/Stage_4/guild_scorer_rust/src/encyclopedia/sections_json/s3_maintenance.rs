//! S3: Maintenance Profile (JSON)
//!
//! Cloned from sections_md/s3_maintenance.rs with minimal changes.
//! Returns MaintenanceSection struct instead of markdown String.
//!
//! CHANGE LOG from sections_md:
//! - Return type: String → MaintenanceSection
//! - Markdown formatting → struct fields
//! - CsrStrategy enum → CsrStrategy struct (for JSON display)
//! - All helper functions unchanged (logic preserved)
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
use crate::encyclopedia::types::{
    get_str, get_f64, CsrStrategy as CsrStrategyEnum, GrowthFormCategory,
};
use crate::encyclopedia::utils::classify::*;
use crate::encyclopedia::view_models::{
    MaintenanceSection, CsrStrategy, MaintenanceTask, SeasonalNote,
};

/// Generate the S3 Maintenance Profile section.
pub fn generate(data: &HashMap<String, Value>) -> MaintenanceSection {
    // Extract CSR values
    let c = get_f64(data, "C").unwrap_or(0.0);
    let s = get_f64(data, "S").unwrap_or(0.0);
    let r = get_f64(data, "R").unwrap_or(0.0);

    // CSR Strategy (enum for logic, struct for display)
    let csr_strategy_enum = classify_csr_spread(c, s, r);
    let csr_strategy = build_csr_strategy(c, s, r, csr_strategy_enum);

    // Growth form for tasks
    let height_m = get_f64(data, "height_m");
    let growth_form = get_str(data, "try_growth_form");
    let form_category = classify_growth_form(growth_form, height_m);

    // Build tasks from practical considerations
    let leaf_phenology = get_str(data, "try_leaf_phenology");
    let leaf_area = get_f64(data, "LA");
    let seed_mass_log = get_f64(data, "logSM");
    let tasks = build_maintenance_tasks(
        height_m,
        leaf_phenology,
        leaf_area,
        seed_mass_log,
        csr_strategy_enum,
        form_category,
    );

    // Build seasonal notes
    let seasonal_notes = build_seasonal_notes(csr_strategy_enum, form_category, leaf_phenology);

    MaintenanceSection {
        csr_strategy,
        tasks,
        seasonal_notes,
    }
}

/// Build CsrStrategy struct from enum and raw values.
fn build_csr_strategy(c: f64, s: f64, r: f64, strategy: CsrStrategyEnum) -> CsrStrategy {
    let dominant = match strategy {
        CsrStrategyEnum::CDominant => "Competitor".to_string(),
        CsrStrategyEnum::SDominant => "Stress-tolerator".to_string(),
        CsrStrategyEnum::RDominant => "Ruderal".to_string(),
        CsrStrategyEnum::Balanced => "Balanced".to_string(),
    };

    let description = csr_explanation(strategy);

    CsrStrategy {
        c_percent: c,
        s_percent: s,
        r_percent: r,
        dominant,
        description,
    }
}

/// Friendly explanation of CSR strategy for non-specialists.
/// CLONED FROM sections_md - logic unchanged
fn csr_explanation(strategy: CsrStrategyEnum) -> String {
    match strategy {
        CsrStrategyEnum::CDominant => {
            "Vigorous grower that actively spreads and may outcompete neighbours. Needs more attention to keep in check.".to_string()
        }
        CsrStrategyEnum::SDominant => {
            "Built for endurance, not speed. Grows slowly, tolerates neglect, and generally thrives when left alone.".to_string()
        }
        CsrStrategyEnum::RDominant => {
            "Fast-living opportunist. Grows quickly, sets seed, and may not live long. Plan for replacement or let it reseed.".to_string()
        }
        CsrStrategyEnum::Balanced => {
            "Adaptable and moderate in all respects. Neither aggressive nor demanding, it fits well in most garden situations.".to_string()
        }
    }
}

/// Build maintenance tasks from trait data.
/// CLONED FROM sections_md practical_considerations - adapted to return Vec<MaintenanceTask>
fn build_maintenance_tasks(
    height_m: Option<f64>,
    leaf_phenology: Option<&str>,
    leaf_area: Option<f64>,
    seed_mass_log: Option<f64>,
    strategy: CsrStrategyEnum,
    form: GrowthFormCategory,
) -> Vec<MaintenanceTask> {
    let mut tasks = Vec::new();

    // Pruning task based on height
    if let Some(h) = height_m {
        let (name, frequency, importance) = if h >= 15.0 {
            ("Professional pruning", "Every 3-5 years", "Essential")
        } else if h >= 6.0 {
            ("Ladder pruning", "Annually", "Recommended")
        } else if h >= 2.5 {
            ("Formative pruning", "Annually", "Recommended")
        } else {
            ("Light trimming", "As needed", "Optional")
        };
        tasks.push(MaintenanceTask {
            name: name.to_string(),
            frequency: frequency.to_string(),
            importance: importance.to_string(),
        });
    }

    // Spreading/weeding based on seed mass and strategy
    if let Some(log_sm) = seed_mass_log {
        let seed_mg = log_sm.exp();
        if seed_mg < 100.0 || matches!(strategy, CsrStrategyEnum::RDominant) {
            let (name, frequency, importance) = if seed_mg < 10.0 {
                ("Seedling control", "Monthly in growing season", "Essential")
            } else {
                ("Self-sown seedling removal", "Seasonally", "Recommended")
            };
            tasks.push(MaintenanceTask {
                name: name.to_string(),
                frequency: frequency.to_string(),
                importance: importance.to_string(),
            });
        }
    }

    // Leaf litter cleanup for deciduous plants
    if let Some(phenology) = leaf_phenology {
        if phenology.to_lowercase().contains("deciduous") {
            let (name, frequency, importance) = if let Some(la) = leaf_area {
                if la / 100.0 > 50.0 {
                    ("Leaf cleanup", "Weekly in autumn", "Essential")
                } else if la / 100.0 > 15.0 {
                    ("Leaf raking", "Bi-weekly in autumn", "Recommended")
                } else {
                    ("Light debris clearing", "Monthly in autumn", "Optional")
                }
            } else {
                ("Autumn leaf cleanup", "As needed", "Recommended")
            };
            tasks.push(MaintenanceTask {
                name: name.to_string(),
                frequency: frequency.to_string(),
                importance: importance.to_string(),
            });
        }
    }

    // Strategy-specific tasks
    match strategy {
        CsrStrategyEnum::CDominant => {
            match form {
                GrowthFormCategory::Vine => {
                    tasks.push(MaintenanceTask {
                        name: "Vigorous growth control".to_string(),
                        frequency: "2-3 times per season".to_string(),
                        importance: "Essential".to_string(),
                    });
                }
                GrowthFormCategory::Shrub => {
                    tasks.push(MaintenanceTask {
                        name: "Hard pruning for spread control".to_string(),
                        frequency: "Annually".to_string(),
                        importance: "Essential".to_string(),
                    });
                }
                GrowthFormCategory::Herb => {
                    tasks.push(MaintenanceTask {
                        name: "Division to control spread".to_string(),
                        frequency: "Every 1-2 years".to_string(),
                        importance: "Recommended".to_string(),
                    });
                }
                _ => {}
            }
        }
        CsrStrategyEnum::RDominant => {
            tasks.push(MaintenanceTask {
                name: "Plan replacement or allow self-seeding".to_string(),
                frequency: "Every 1-3 years".to_string(),
                importance: "Recommended".to_string(),
            });
        }
        _ => {}
    }

    tasks
}

/// Build seasonal notes based on strategy and form.
/// CLONED FROM sections_md watch_for_warnings - adapted to return Vec<SeasonalNote>
fn build_seasonal_notes(
    strategy: CsrStrategyEnum,
    form: GrowthFormCategory,
    leaf_phenology: Option<&str>,
) -> Vec<SeasonalNote> {
    let mut notes = Vec::new();

    // Spring notes
    match strategy {
        CsrStrategyEnum::CDominant => {
            notes.push(SeasonalNote {
                season: "Spring".to_string(),
                note: "Watch for aggressive early growth; may shade out emerging neighbours".to_string(),
            });
        }
        CsrStrategyEnum::RDominant => {
            notes.push(SeasonalNote {
                season: "Spring".to_string(),
                note: "Check for self-sown seedlings; thin or transplant as needed".to_string(),
            });
        }
        _ => {}
    }

    // Summer notes for vines
    if matches!(form, GrowthFormCategory::Vine) && matches!(strategy, CsrStrategyEnum::CDominant) {
        notes.push(SeasonalNote {
            season: "Summer".to_string(),
            note: "Peak growth period; regular training and cutting back needed".to_string(),
        });
    }

    // Autumn notes for deciduous plants
    if let Some(phenology) = leaf_phenology {
        if phenology.to_lowercase().contains("deciduous") {
            notes.push(SeasonalNote {
                season: "Autumn".to_string(),
                note: "Leaf fall period; clear fallen leaves to prevent disease".to_string(),
            });
        }
    }

    // Winter notes
    match strategy {
        CsrStrategyEnum::SDominant => {
            notes.push(SeasonalNote {
                season: "Winter".to_string(),
                note: "Dormant period; minimal intervention needed".to_string(),
            });
        }
        CsrStrategyEnum::RDominant if matches!(form, GrowthFormCategory::Vine) => {
            notes.push(SeasonalNote {
                season: "Winter".to_string(),
                note: "May die back completely; regrows from base in spring".to_string(),
            });
        }
        _ => {}
    }

    notes
}
