//! METRIC 4: DISEASE SUPPRESSION (FUNGAL & ANIMAL BIOCONTROL)
//!
//! **PHASE 3 OPTIMIZATION**: Pre-filtered LazyFrame with column projection
//!
//! Scores disease control provided by mycoparasitic fungi AND fungivorous animals.
//! Uses pairwise analysis to identify protective relationships
//! between vulnerable (disease-prone) and protective (biocontrol-hosting) plants.
//!
//! **Memory optimization**:
//!   - Receives pre-filtered fungi_lazy (7 rows), selects only 2 needed columns
//!   - Receives pre-filtered organisms_lazy (7 rows), selects only 1 needed column
//!   - Reuses same LazyFrames as M3 (no redundant filtering!)
//!
//! **Columns needed from fungi_lazy** (2 columns):
//!   1. plant_wfo_id - Plant identification
//!   2. pathogenic_fungi - Pipe-separated pathogen IDs
//!   3. mycoparasite_fungi - Pipe-separated mycoparasite IDs
//!
//! **Columns needed from organisms_lazy** (1 column):
//!   4. fungivores_eats - Pipe-separated fungivorous animal IDs
//!
//! R reference: shipley_checks/src/Stage_4/metrics/m4_disease_control.R

use polars::prelude::*;
use rustc_hash::{FxHashMap, FxHashSet};
use anyhow::Result;
use crate::utils::{Calibration, percentile_normalize};

/// Result of M4 calculation
#[derive(Debug)]
pub struct M4Result {
    /// Normalized pathogen control score (scaled by guild size)
    pub raw: f64,
    /// Percentile score (0-100, HIGH = GOOD)
    pub norm: f64,
    /// Total pathogen control before normalization
    pub pathogen_control_raw: f64,
    /// Number of mechanisms detected
    pub n_mechanisms: usize,
    /// Map of mycoparasite_name → plant_count for network analysis
    pub mycoparasite_counts: FxHashMap<String, usize>,
    /// Map of fungivore_name → plant_count for network analysis
    pub fungivore_counts: FxHashMap<String, usize>,
    /// Map of pathogen_name → plant_count for network analysis
    pub pathogen_counts: FxHashMap<String, usize>,
    /// Count of specific antagonist matches (pathogen → known mycoparasite)
    pub specific_antagonist_matches: usize,
    /// Count of specific fungivore matches (pathogen → known fungivore)
    pub specific_fungivore_matches: usize,
    /// List of matched (pathogen, antagonist) pairs
    pub matched_antagonist_pairs: Vec<(String, String)>,
    /// List of matched (pathogen, fungivore) pairs
    pub matched_fungivore_pairs: Vec<(String, String)>,
}

/// Calculate M4: Disease Suppression (Fungal & Animal Biocontrol)
///
/// **PHASE 3 OPTIMIZATION**: Reuses fungi and organisms LazyFrames from scorer
///
/// R reference: m4_disease_control.R::calculate_m4_disease_control
pub fn calculate_m4(
    plant_ids: &[String],        // Guild plant IDs for filtering
    organisms_lazy: &LazyFrame,  // Schema-only scan (from scorer, reused from M3!)
    fungi_lazy: &LazyFrame,      // Schema-only scan (from scorer, reused from M3!)
    pathogen_antagonists: &FxHashMap<String, Vec<String>>,
    calibration: &Calibration,
) -> Result<M4Result> {
    let mut pathogen_control_raw = 0.0;
    let mut n_mechanisms = 0;
    let mut specific_antagonist_matches = 0;
    let mut specific_fungivore_matches = 0;
    let mut matched_antagonist_pairs: Vec<(String, String)> = Vec::new();
    let mut matched_fungivore_pairs: Vec<(String, String)> = Vec::new();

    // STEP 1a: Materialize fungi columns
    let fungi_selected = fungi_lazy
        .clone()
        .select(&[
            col("plant_wfo_id"),
            col("pathogenic_fungi"),
            col("mycoparasite_fungi"),
        ])
        .collect()?;  // Execute: loads only 3 columns × 11,711 rows

    // STEP 1b: Materialize organisms columns (fungivores)
    let organisms_selected = organisms_lazy
        .clone()
        .select(&[
            col("plant_wfo_id"),
            col("fungivores_eats"),
        ])
        .collect()?;  // Execute: loads only 2 columns × 11,711 rows

    // STEP 2: Filter to guild plants
    use std::collections::HashSet;
    let id_set: HashSet<_> = plant_ids.iter().collect();

    let id_col = fungi_selected.column("plant_wfo_id")?.str()?;
    let mask: BooleanChunked = id_col
        .into_iter()
        .map(|opt| opt.map_or(false, |s| id_set.contains(&s.to_string())))
        .collect();
    let guild_fungi = fungi_selected.filter(&mask)?;

    let id_col_org = organisms_selected.column("plant_wfo_id")?.str()?;
    let mask_org: BooleanChunked = id_col_org
        .into_iter()
        .map(|opt| opt.map_or(false, |s| id_set.contains(&s.to_string())))
        .collect();
    let guild_organisms = organisms_selected.filter(&mask_org)?;

    let n_plants = guild_fungi.height();

    if guild_fungi.height() == 0 {
        return Ok(M4Result {
            raw: 0.0,
            norm: 0.0,
            pathogen_control_raw: 0.0,
            n_mechanisms: 0,
            mycoparasite_counts: FxHashMap::default(),
            fungivore_counts: FxHashMap::default(),
            pathogen_counts: FxHashMap::default(),
            specific_antagonist_matches: 0,
            specific_fungivore_matches: 0,
            matched_antagonist_pairs: Vec::new(),
            matched_fungivore_pairs: Vec::new(),
        });
    }

    // Extract data into structured format
    let plant_pathogens = extract_column_data(&guild_fungi, "pathogenic_fungi")?;
    let plant_mycoparasites = extract_column_data(&guild_fungi, "mycoparasite_fungi")?;
    let plant_fungivores = extract_column_data(&guild_organisms, "fungivores_eats")?;

    // Build agent counts: agent_name → number of plants
    let mycoparasite_counts = build_agent_counts(&plant_mycoparasites)?;
    let fungivore_counts = build_agent_counts(&plant_fungivores)?;
    let pathogen_counts = build_agent_counts(&plant_pathogens)?;

    // Pairwise analysis: vulnerable plant A vs protective plant B
    for (plant_a_id, pathogens_a) in &plant_pathogens {
        if pathogens_a.is_empty() {
            continue; // Skip plants with no pathogens
        }

        for (plant_b_id, mycoparasites_b) in &plant_mycoparasites {
            if plant_a_id == plant_b_id || mycoparasites_b.is_empty() {
                continue; // Skip self-comparison and plants without mycoparasites
            }

            // MECHANISM 1: Specific antagonist matches (weight 1.0) - RARELY FIRES
            for pathogen in pathogens_a {
                if let Some(known_antagonists) = pathogen_antagonists.get(pathogen) {
                    let matched_ants = find_matches(mycoparasites_b, known_antagonists);
                    if !matched_ants.is_empty() {
                        pathogen_control_raw += matched_ants.len() as f64 * 1.0;
                        n_mechanisms += 1;
                        specific_antagonist_matches += 1;
                        // Track matched pairs
                        for antagonist in matched_ants {
                            matched_antagonist_pairs.push((pathogen.clone(), antagonist));
                        }
                    }
                }
            }

            // MECHANISM 2: General mycoparasites (weight 1.0) - PRIMARY MECHANISM
            // If plant A has any pathogens AND plant B has any mycoparasites
            pathogen_control_raw += mycoparasites_b.len() as f64 * 1.0;
            n_mechanisms += 1;
        }

        // MECHANISM 3: General fungivores eating pathogens (weight 0.2) - R parity
        // All fungivores can consume pathogenic fungi (non-specific)
        for (plant_b_id, fungivores_b) in &plant_fungivores {
            if plant_a_id == plant_b_id || fungivores_b.is_empty() {
                continue; // Skip self-comparison and plants without fungivores
            }

            // General fungivores (weight 0.2 per fungivore)
            if !pathogens_a.is_empty() && !fungivores_b.is_empty() {
                pathogen_control_raw += fungivores_b.len() as f64 * 0.2;
            }
        }
    }

    // Normalize by guild size
    let max_pairs = n_plants * (n_plants - 1);
    let pathogen_control_normalized = if max_pairs > 0 {
        pathogen_control_raw / max_pairs as f64 * 10.0
    } else {
        0.0
    };

    // Percentile normalization
    let m4_norm = percentile_normalize(pathogen_control_normalized, "p2", calibration, false)?;

    // Deduplicate matched pairs
    matched_antagonist_pairs.sort_unstable();
    matched_antagonist_pairs.dedup();
    matched_fungivore_pairs.sort_unstable();
    matched_fungivore_pairs.dedup();

    Ok(M4Result {
        raw: pathogen_control_normalized,
        norm: m4_norm,
        pathogen_control_raw,
        n_mechanisms,
        mycoparasite_counts,
        fungivore_counts,
        pathogen_counts,
        specific_antagonist_matches,
        specific_fungivore_matches,
        matched_antagonist_pairs,
        matched_fungivore_pairs,
    })
}

/// Filter DataFrame to guild plants
fn filter_to_guild(df: &DataFrame, plant_ids: &[String], col: &str) -> Result<DataFrame> {
    let plant_id_set: FxHashSet<&String> = plant_ids.iter().collect();
    let plant_col = df.column(col)?.str()?;
    let mask: BooleanChunked = plant_col
        .into_iter()
        .map(|opt| opt.map_or(false, |s| plant_id_set.contains(&s.to_string())))
        .collect();
    Ok(df.filter(&mask)?)
}

/// Extract single column data: plant_id → list of fungi
fn extract_column_data(
    df: &DataFrame,
    col_name: &str,
) -> Result<FxHashMap<String, Vec<String>>> {
    let mut map: FxHashMap<String, Vec<String>> = FxHashMap::default();

    let plant_ids = df.column("plant_wfo_id")?.str()?;

    if let Ok(col) = df.column(col_name) {
        // Phase 0-4 parquets use Arrow list columns
        if let Ok(list_col) = col.list() {
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
        } else if let Ok(str_col) = col.str() {
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

/// Build agent_name → plant_count mapping
fn build_agent_counts(plant_agents: &FxHashMap<String, Vec<String>>) -> Result<FxHashMap<String, usize>> {
    let mut counts: FxHashMap<String, usize> = FxHashMap::default();

    for agents in plant_agents.values() {
        for agent in agents {
            *counts.entry(agent.clone()).or_insert(0) += 1;
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
        let list_a = vec!["fungus1".to_string(), "fungus2".to_string()];
        let list_b = vec!["fungus2".to_string(), "fungus3".to_string()];

        assert_eq!(count_matches(&list_a, &list_b), 1);
    }

    #[test]
    fn test_count_matches_none() {
        let list_a = vec!["fungus1".to_string()];
        let list_b = vec!["fungus2".to_string()];

        assert_eq!(count_matches(&list_a, &list_b), 0);
    }

    #[test]
    fn test_count_matches_multiple() {
        let list_a = vec!["f1".to_string(), "f2".to_string(), "f3".to_string()];
        let list_b = vec!["f1".to_string(), "f2".to_string(), "f4".to_string()];

        assert_eq!(count_matches(&list_a, &list_b), 2);
    }
}
