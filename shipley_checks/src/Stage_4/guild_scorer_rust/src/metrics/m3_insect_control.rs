//! METRIC 3: BENEFICIAL INSECT NETWORKS (BIOCONTROL)
//!
//! **PHASE 3 OPTIMIZATION**: Pre-filtered LazyFrame with column projection
//!
//! Scores natural pest control provided by predators and entomopathogenic
//! fungi. Uses pairwise analysis to identify protective relationships
//! between vulnerable and protective plants.
//!
//! **Memory optimization**:
//!   - Old: Receives full organisms_df (11,711 rows), filters to guild, uses all columns
//!   - New: Receives pre-filtered organisms_lazy (7 rows), selects only 5 needed columns
//!   - Savings per metric call: ~11,704 rows × all columns not loaded
//!
//! **Columns needed** (M3 selects these 5):
//!   1. plant_wfo_id - Plant identification
//!   2. herbivores - Pipe-separated herbivore IDs
//!   3. predators_hasHost - Pipe-separated predator IDs (relationship: hasHost)
//!   4. predators_interactsWith - Pipe-separated predator IDs (relationship: interactsWith)
//!   5. predators_adjacentTo - Pipe-separated predator IDs (relationship: adjacentTo)
//!
//! **Plus from fungi_lazy** (1 column):
//!   6. entomopathogenic_fungi - Pipe-separated entomopathogenic fungi IDs
//!
//! R reference: shipley_checks/src/Stage_4/metrics/m3_insect_control.R

use polars::prelude::*;
use rustc_hash::{FxHashMap, FxHashSet};
use anyhow::Result;
use crate::utils::{Calibration, percentile_normalize, materialize_with_columns, filter_to_guild};

/// Column requirements for M3 calculation (from organisms parquet)
pub const REQUIRED_ORGANISM_COLS: &[&str] = &[
    "plant_wfo_id",
    "herbivores",
    "flower_visitors",      // Contains pollinator/predator data
    "predators_hasHost",
    "predators_interactsWith",
    "predators_adjacentTo",
];

/// Column requirements for M3 calculation (from fungi parquet)
pub const REQUIRED_FUNGI_COLS: &[&str] = &[
    "plant_wfo_id",
    "entomopathogenic_fungi",
];

/// Result of M3 calculation
#[derive(Debug)]
pub struct M3Result {
    /// Normalized biocontrol score (scaled by guild size)
    pub raw: f64,
    /// Percentile score (0-100, HIGH = GOOD)
    pub norm: f64,
    /// Total biocontrol before normalization
    pub biocontrol_raw: f64,
    /// Number of mechanisms detected
    pub n_mechanisms: usize,
    /// Map of predator_name → plant_count for network analysis
    pub predator_counts: FxHashMap<String, usize>,
    /// Map of entomopathogenic_fungus_name → plant_count for network analysis
    pub entomo_fungi_counts: FxHashMap<String, usize>,
    /// Count of specific predator matches (herbivore → known predator)
    pub specific_predator_matches: usize,
    /// Count of specific fungi matches (herbivore → known fungus)
    pub specific_fungi_matches: usize,
    /// List of matched (herbivore, predator) pairs
    pub matched_predator_pairs: Vec<(String, String)>,
    /// List of matched (herbivore, fungus) pairs
    pub matched_fungi_pairs: Vec<(String, String)>,
}

/// Calculate M3: Beneficial Insect Networks (Biocontrol)
///
/// **PHASE 3 OPTIMIZATION**: Takes pre-filtered LazyFrames
///
/// **Old signature** (pre-Phase 3):
///   ```
///   pub fn calculate_m3(
///       plant_ids: &[String],
///       organisms_df: &DataFrame,  // Full 11,711 rows
///       fungi_df: &DataFrame,      // Full 11,711 rows
///       ...
///   )
///   ```
///   Inside function: filter_to_guild() called twice (redundant!)
///
/// **New signature** (Phase 3):
///   ```
///   pub fn calculate_m3(
///       organisms_lazy: &LazyFrame,  // Already filtered to 7 rows (query plan)
///       fungi_lazy: &LazyFrame,      // Already filtered to 7 rows (query plan)
///       ...
///   )
///   ```
///   No filtering needed - just select columns and collect()
///
/// R reference: m3_insect_control.R::calculate_m3_insect_control
pub fn calculate_m3(
    plant_ids: &[String],        // Guild plant IDs for filtering
    organisms_lazy: &LazyFrame,  // Schema-only scan (from scorer)
    fungi_lazy: &LazyFrame,      // Schema-only scan (from scorer)
    herbivore_predators: &FxHashMap<String, Vec<String>>,
    insect_parasites: &FxHashMap<String, Vec<String>>,
    calibration: &Calibration,
) -> Result<M3Result> {
    let mut biocontrol_raw = 0.0;
    let mut n_mechanisms = 0;
    let mut specific_predator_matches = 0;
    let mut specific_fungi_matches = 0;
    let mut matched_predator_pairs: Vec<(String, String)> = Vec::new();
    let mut matched_fungi_pairs: Vec<(String, String)> = Vec::new();

    // ========================================================================
    // STEP 1: Materialize organisms columns and filter to guild
    // ========================================================================

    let organisms_df = materialize_with_columns(
        organisms_lazy,
        REQUIRED_ORGANISM_COLS,
        "M3 organisms",
    )?;

    let guild_organisms = filter_to_guild(&organisms_df, plant_ids, "plant_wfo_id", "M3 organisms")?;

    // ========================================================================
    // STEP 2: Materialize fungi columns and filter to guild
    // ========================================================================

    let fungi_df = materialize_with_columns(
        fungi_lazy,
        REQUIRED_FUNGI_COLS,
        "M3 fungi",
    )?;

    let guild_fungi = filter_to_guild(&fungi_df, plant_ids, "plant_wfo_id", "M3 fungi")?;

    let n_plants = guild_organisms.height();

    if guild_organisms.height() == 0 {
        return Ok(M3Result {
            raw: 0.0,
            norm: 0.0,
            biocontrol_raw: 0.0,
            n_mechanisms: 0,
            predator_counts: FxHashMap::default(),
            entomo_fungi_counts: FxHashMap::default(),
            specific_predator_matches: 0,
            specific_fungi_matches: 0,
            matched_predator_pairs: Vec::new(),
            matched_fungi_pairs: Vec::new(),
        });
    }

    // Extract organism data into structured format
    let plant_organisms = extract_organism_data(&guild_organisms)?;
    let plant_predators = extract_predator_data(&guild_organisms)?;
    let plant_fungi = extract_fungi_data(&guild_fungi)?;

    // Build set of ALL known predators (from herbivore_predators lookup values)
    let mut known_predators: FxHashSet<String> = FxHashSet::default();
    for predator_list in herbivore_predators.values() {
        for predator in predator_list {
            known_predators.insert(predator.clone());
        }
    }

    // Build set of ALL known entomopathogenic fungi (from insect_parasites lookup values)
    let mut known_entomo_fungi: FxHashSet<String> = FxHashSet::default();
    for fungi_list in insect_parasites.values() {
        for fungus in fungi_list {
            known_entomo_fungi.insert(fungus.clone());
        }
    }

    // Build agent counts: agent_name → number of plants it visits
    // FILTER to only include agents that are known biocontrol agents in lookup tables
    let predator_counts = build_predator_counts(&plant_predators, &known_predators)?;
    let entomo_fungi_counts = build_entomo_fungi_counts(&plant_fungi, &known_entomo_fungi)?;

    // DEBUG: Log organism data for first 3 plants (DISABLED for performance)
    // eprintln!("\n=== M3 DEBUG: Guild organism data ===");
    // for (idx, (plant_id, herbivores)) in plant_organisms.iter().enumerate() {
    //     if idx < 3 {
    //         let predators = plant_predators.get(plant_id).map(|v| v.len()).unwrap_or(0);
    //         let fungi = plant_fungi.get(plant_id).map(|v| v.len()).unwrap_or(0);
    //         eprintln!("Plant {}: herbivores={}, predators={}, fungi={}",
    //             plant_id, herbivores.len(), predators, fungi);
    //     }
    // }
    // eprintln!("Total plants in guild: {}", n_plants);

    // Pairwise analysis: vulnerable plant A vs protective plant B
    for (plant_a_id, herbivores_a) in &plant_organisms {
        if herbivores_a.is_empty() {
            continue; // Skip plants with no herbivores
        }

        for (plant_b_id, _) in &plant_organisms {
            if plant_a_id == plant_b_id {
                continue; // Skip self-comparison
            }

            // Get predators from plant B (exclude herbivores - R parity)
            let predators_b = plant_predators
                .get(plant_b_id)
                .map(|v| v.as_slice())
                .unwrap_or(&[]);

            // MECHANISM 1: Specific animal predators (weight 1.0)
            for herbivore in herbivores_a {
                if let Some(known_predators) = herbivore_predators.get(herbivore) {
                    let matched_preds = find_matches(predators_b, known_predators);
                    if !matched_preds.is_empty() {
                        biocontrol_raw += matched_preds.len() as f64 * 1.0;
                        n_mechanisms += 1;
                        specific_predator_matches += 1;
                        // Track matched pairs
                        for pred in matched_preds {
                            matched_predator_pairs.push((herbivore.clone(), pred));
                        }
                    }
                }
            }

            // MECHANISMS 2 & 3: Entomopathogenic fungi
            if let Some(entomo_b) = plant_fungi.get(plant_b_id) {
                if !entomo_b.is_empty() {
                    // MECHANISM 2: Specific entomopathogenic fungi (weight 1.0)
                    for herbivore in herbivores_a {
                        if let Some(known_parasites) = insect_parasites.get(herbivore) {
                            let matched_fungi = find_matches(entomo_b, known_parasites);
                            if !matched_fungi.is_empty() {
                                biocontrol_raw += matched_fungi.len() as f64 * 1.0;
                                n_mechanisms += 1;
                                specific_fungi_matches += 1;
                                // Track matched pairs
                                for fungus in matched_fungi {
                                    matched_fungi_pairs.push((herbivore.clone(), fungus));
                                }
                            }
                        }
                    }

                    // MECHANISM 3: General entomopathogenic fungi (weight 0.2)
                    biocontrol_raw += entomo_b.len() as f64 * 0.2;
                }
            }
        }
    }

    // Normalize by guild size
    let max_pairs = n_plants * (n_plants - 1);
    let biocontrol_normalized = if max_pairs > 0 {
        biocontrol_raw / max_pairs as f64 * 20.0
    } else {
        0.0
    };

    // DEBUG: Log final values (DISABLED for performance)
    // eprintln!("=== M3 DEBUG: Final calculation ===");
    // eprintln!("biocontrol_raw: {}", biocontrol_raw);
    // eprintln!("max_pairs: {}", max_pairs);
    // eprintln!("biocontrol_normalized: {}", biocontrol_normalized);
    // eprintln!("Mechanism counts: predator={}, fungi={}", specific_predator_matches, specific_fungi_matches);
    // eprintln!("===============================\n");

    // Percentile normalization
    let m3_norm = percentile_normalize(biocontrol_normalized, "p1", calibration, false)?;

    // Deduplicate matched pairs
    matched_predator_pairs.sort_unstable();
    matched_predator_pairs.dedup();
    matched_fungi_pairs.sort_unstable();
    matched_fungi_pairs.dedup();

    Ok(M3Result {
        raw: biocontrol_normalized,
        norm: m3_norm,
        biocontrol_raw,
        n_mechanisms,
        predator_counts,
        entomo_fungi_counts,
        specific_predator_matches,
        specific_fungi_matches,
        matched_predator_pairs,
        matched_fungi_pairs,
    })
}

/// Extract organism data: plant_id → list of all animals
/// Aggregates herbivores, flower_visitors, and all predator types
fn extract_organism_data(df: &DataFrame) -> Result<FxHashMap<String, Vec<String>>> {
    let mut map: FxHashMap<String, Vec<String>> = FxHashMap::default();
    let plant_ids = df.column("plant_wfo_id")?.str()?;

    // Columns to aggregate for each plant
    let columns = [
        "herbivores",
        "flower_visitors",
        "predators_hasHost",
        "predators_interactsWith",
        "predators_adjacentTo",
    ];

    for idx in 0..df.height() {
        if let Some(plant_id) = plant_ids.get(idx) {
            let mut organisms = Vec::new();

            for col_name in &columns {
                if let Ok(col) = df.column(col_name) {
                    // Phase 0-4 parquets use Arrow list columns
                    if let Ok(list_col) = col.list() {
                        if let Some(list_series) = list_col.get_as_series(idx) {
                            if let Ok(str_series) = list_series.str() {
                                for org_opt in str_series.into_iter() {
                                    if let Some(org) = org_opt {
                                        if !org.is_empty() {
                                            organisms.push(org.to_string());
                                        }
                                    }
                                }
                            }
                        }
                    } else if let Ok(str_col) = col.str() {
                        // Fallback: pipe-separated strings (legacy format)
                        if let Some(value) = str_col.get(idx) {
                            for org in value.split('|').filter(|s| !s.is_empty()) {
                                organisms.push(org.to_string());
                            }
                        }
                    }
                }
            }

            // Deduplicate
            organisms.sort_unstable();
            organisms.dedup();

            map.insert(plant_id.to_string(), organisms);
        }
    }

    Ok(map)
}

/// Extract fungi data: plant_id → entomopathogenic fungi list
fn extract_fungi_data(df: &DataFrame) -> Result<FxHashMap<String, Vec<String>>> {
    let mut map: FxHashMap<String, Vec<String>> = FxHashMap::default();

    if df.height() == 0 {
        return Ok(map);
    }

    let plant_ids = df.column("plant_wfo_id")?.str()?;

    if let Ok(entomo_col) = df.column("entomopathogenic_fungi") {
        // Phase 0-4 parquets use Arrow list columns
        if let Ok(list_col) = entomo_col.list() {
            for idx in 0..df.height() {
                if let Some(plant_id) = plant_ids.get(idx) {
                    if let Some(list_series) = list_col.get_as_series(idx) {
                        if let Ok(str_series) = list_series.str() {
                            let fungi: Vec<String> = str_series
                                .into_iter()
                                .filter_map(|opt| opt.map(|s| s.to_string()))
                                .filter(|s| !s.is_empty())
                                .collect();

                            if !fungi.is_empty() {
                                map.insert(plant_id.to_string(), fungi);
                            }
                        }
                    }
                }
            }
        } else if let Ok(str_col) = entomo_col.str() {
            // Fallback: pipe-separated strings (legacy format)
            for idx in 0..df.height() {
                if let (Some(plant_id), Some(fungi_str)) = (plant_ids.get(idx), str_col.get(idx)) {
                    let fungi: Vec<String> = fungi_str
                        .split('|')
                        .filter(|s| !s.is_empty())
                        .map(|s| s.to_string())
                        .collect();

                    if !fungi.is_empty() {
                        map.insert(plant_id.to_string(), fungi);
                    }
                }
            }
        }
    }

    Ok(map)
}

/// Extract predator data: plant_id → list of predators only
/// Uses flower_visitors + 3 predator columns (R parity)
fn extract_predator_data(df: &DataFrame) -> Result<FxHashMap<String, Vec<String>>> {
    let mut map: FxHashMap<String, Vec<String>> = FxHashMap::default();
    let plant_ids = df.column("plant_wfo_id")?.str()?;

    // DEBUG: Check available columns (DISABLED for performance)
    // eprintln!("\n=== extract_predator_data: Available columns ===");
    // for col_name in df.get_column_names() {
    //     eprintln!("  - {}", col_name);
    // }
    // eprintln!("================================================\n");

    // DEBUG: Check first plant
    let debug_plant_id = "wfo-0000241769";

    // Predator columns (match R: flower_visitors + 3 predator types)
    let predator_columns = [
        "flower_visitors",
        "predators_hasHost",
        "predators_interactsWith",
        "predators_adjacentTo",
    ];

    for idx in 0..df.height() {
        if let Some(plant_id) = plant_ids.get(idx) {
            let mut predators = Vec::new();
            let is_debug_plant = plant_id == debug_plant_id;

            for col_name in &predator_columns {
                let mut col_count = 0;
                if let Ok(col) = df.column(col_name) {
                    // Phase 0-4 parquets use Arrow list columns
                    if let Ok(list_col) = col.list() {
                        if let Some(list_series) = list_col.get_as_series(idx) {
                            if let Ok(str_series) = list_series.str() {
                                for org_opt in str_series.into_iter() {
                                    if let Some(org) = org_opt {
                                        if !org.is_empty() {
                                            predators.push(org.to_string());
                                            col_count += 1;
                                        }
                                    }
                                }
                            }
                        }
                    } else if let Ok(str_col) = col.str() {
                        // Fallback: pipe-separated strings (legacy format)
                        if let Some(value) = str_col.get(idx) {
                            for org in value.split('|').filter(|s| !s.is_empty()) {
                                predators.push(org.to_string());
                                col_count += 1;
                            }
                        }
                    }
                }

                if is_debug_plant {
                    eprintln!("  extract_predator_data: {} from {}: {} items",
                        plant_id, col_name, col_count);
                }
            }

            // Deduplicate
            predators.sort_unstable();
            predators.dedup();

            if is_debug_plant {
                eprintln!("  extract_predator_data: {} TOTAL (after dedup): {} predators\n",
                    plant_id, predators.len());
            }

            map.insert(plant_id.to_string(), predators);
        }
    }

    Ok(map)
}

/// Build predator_name → plant_count mapping
/// FILTERS to only include agents that appear in the known_predators set (from lookup table)
fn build_predator_counts(
    plant_predators: &FxHashMap<String, Vec<String>>,
    known_predators: &FxHashSet<String>,
) -> Result<FxHashMap<String, usize>> {
    let mut counts: FxHashMap<String, usize> = FxHashMap::default();

    for predators in plant_predators.values() {
        for predator in predators {
            // ONLY count if this agent is a known predator in the lookup table
            if known_predators.contains(predator) {
                *counts.entry(predator.clone()).or_insert(0) += 1;
            }
        }
    }

    Ok(counts)
}

/// Build entomo_fungi_name → plant_count mapping
/// FILTERS to only include fungi that appear in the known_entomo_fungi set (from lookup table)
fn build_entomo_fungi_counts(
    plant_fungi: &FxHashMap<String, Vec<String>>,
    known_entomo_fungi: &FxHashSet<String>,
) -> Result<FxHashMap<String, usize>> {
    let mut counts: FxHashMap<String, usize> = FxHashMap::default();

    for fungi in plant_fungi.values() {
        for fungus in fungi {
            // ONLY count if this fungus is a known entomopathogenic fungus in the lookup table
            if known_entomo_fungi.contains(fungus) {
                *counts.entry(fungus.clone()).or_insert(0) += 1;
            }
        }
    }

    Ok(counts)
}

/// Find which elements from list_a are in list_b and return them
fn find_matches(list_a: &[String], list_b: &[String]) -> Vec<String> {
    let set_b: FxHashSet<&String> = list_b.iter().collect();
    list_a.iter()
        .filter(|item| set_b.contains(item))
        .map(|s| s.clone())
        .collect()
}

/// Count how many elements from list_a are in list_b (kept for backward compatibility)
fn count_matches(list_a: &[String], list_b: &[String]) -> usize {
    find_matches(list_a, list_b).len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_count_matches() {
        let list_a = vec!["pred1".to_string(), "pred2".to_string(), "pred3".to_string()];
        let list_b = vec!["pred2".to_string(), "pred4".to_string()];

        assert_eq!(count_matches(&list_a, &list_b), 1); // Only pred2 matches
    }

    #[test]
    fn test_count_matches_multiple() {
        let list_a = vec!["pred1".to_string(), "pred2".to_string()];
        let list_b = vec!["pred1".to_string(), "pred2".to_string(), "pred3".to_string()];

        assert_eq!(count_matches(&list_a, &list_b), 2); // Both match
    }

    #[test]
    fn test_count_matches_none() {
        let list_a = vec!["pred1".to_string()];
        let list_b = vec!["pred2".to_string()];

        assert_eq!(count_matches(&list_a, &list_b), 0); // No matches
    }
}
