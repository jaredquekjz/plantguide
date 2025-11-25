//! Shared Organism Counter Utility
//!
//! Counts how many plants in a guild share each organism (pollinator, fungus, etc.).
//! Used by M5 (Beneficial Fungi) and M7 (Pollinator Support) for network analysis.
//!
//! R reference: shipley_checks/src/Stage_4/utils/shared_organism_counter.R (98 lines)

use rustc_hash::FxHashMap;
use smallvec::SmallVec;
use polars::prelude::*;
use anyhow::Result;
use std::collections::HashSet;

/// Count organisms shared across plants in a guild
///
/// For each organism, counts how many plants in the guild host/associate with it.
/// Aggregates organisms across multiple columns (e.g., pollinators + flower_visitors).
///
/// Returns a map of organism_id → plant_count
///
/// R reference: shipley_checks/src/Stage_4/utils/shared_organism_counter.R
pub fn count_shared_organisms(
    df: &DataFrame,
    plant_ids: &[String],
    columns: &[&str],
) -> Result<FxHashMap<String, usize>> {
    let mut counts: FxHashMap<String, usize> = FxHashMap::default();

    // Filter to guild plants using boolean mask
    let plant_id_set: HashSet<&String> = plant_ids.iter().collect();
    let plant_col = df.column("plant_wfo_id")?.str()?;
    let mask: BooleanChunked = plant_col
        .into_iter()
        .map(|opt| opt.map_or(false, |s| plant_id_set.contains(&s.to_string())))
        .collect();
    let guild_df = df.filter(&mask)?;

    // Process each plant
    for idx in 0..guild_df.height() {
        // Aggregate organisms from all specified columns
        // Use SmallVec for stack allocation (most plants have < 16 organisms)
        let mut plant_organisms: SmallVec<[String; 16]> = SmallVec::new();

        for col_name in columns {
            if let Ok(col_series) = guild_df.column(col_name) {
                // Phase 0-4 parquets use Arrow list columns (not pipe-separated strings)
                if let Ok(list_col) = col_series.list() {
                    // Handle list column (Phase 0-4 format)
                    if let Some(list_series) = list_col.get_as_series(idx) {
                        if let Ok(str_series) = list_series.str() {
                            for org_opt in str_series.into_iter() {
                                if let Some(org) = org_opt {
                                    if !org.is_empty() {
                                        plant_organisms.push(org.to_string());
                                    }
                                }
                            }
                        }
                    }
                } else if let Ok(utf8_col) = col_series.str() {
                    // Fallback: Handle pipe-separated string (legacy format)
                    if let Some(org_list_opt) = utf8_col.get(idx) {
                        for org in org_list_opt.split('|').filter(|s| !s.is_empty()) {
                            plant_organisms.push(org.to_string());
                        }
                    }
                }
            }
        }

        // Deduplicate organisms for this plant
        plant_organisms.sort_unstable();
        plant_organisms.dedup();

        // Count each organism
        for org in plant_organisms {
            if !org.trim().is_empty() {
                *counts.entry(org).or_insert(0) += 1;
            }
        }
    }

    Ok(counts)
}
