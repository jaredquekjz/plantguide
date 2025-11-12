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

    // Filter to guild plants
    let guild_df = df.filter(
        &col("plant_wfo_id")
            .is_in(lit(Series::new("ids".into(), plant_ids)))
    )?;

    // Process each plant
    for idx in 0..guild_df.height() {
        // Aggregate organisms from all specified columns
        // Use SmallVec for stack allocation (most plants have < 16 organisms)
        let mut plant_organisms: SmallVec<[String; 16]> = SmallVec::new();

        for col_name in columns {
            if let Ok(col_series) = guild_df.column(col_name) {
                if let Ok(utf8_col) = col_series.str() {
                    if let Some(org_list_opt) = utf8_col.get(idx) {
                        // Parse pipe-separated string
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_count_shared_organisms() {
        // Create mock dataframe
        let plant_ids = Series::new("plant_wfo_id".into(), &["plant_a", "plant_b", "plant_c"]);
        let pollinators = Series::new("pollinators".into(), &[
            "bee_1|bee_2|butterfly_1",
            "bee_1|fly_1",
            "bee_1|butterfly_1|fly_2"
        ]);

        let df = DataFrame::new(vec![plant_ids, pollinators]).unwrap();

        let guild_ids: Vec<String> = vec!["plant_a".into(), "plant_b".into(), "plant_c".into()];
        let counts = count_shared_organisms(&df, &guild_ids, &["pollinators"]).unwrap();

        // bee_1 should appear in all 3 plants
        assert_eq!(counts.get("bee_1"), Some(&3));
        // butterfly_1 should appear in 2 plants (a, c)
        assert_eq!(counts.get("butterfly_1"), Some(&2));
        // bee_2 should appear in 1 plant (a)
        assert_eq!(counts.get("bee_2"), Some(&1));
        // fly_1 should appear in 1 plant (b)
        assert_eq!(counts.get("fly_1"), Some(&1));
    }

    #[test]
    fn test_count_multiple_columns() {
        // Test aggregation across multiple columns
        let plant_ids = Series::new("plant_wfo_id".into(), &["plant_a", "plant_b"]);
        let pollinators = Series::new("pollinators".into(), &["bee_1|bee_2", "bee_1"]);
        let flower_visitors = Series::new("flower_visitors".into(), &["butterfly_1", "bee_1|butterfly_1"]);

        let df = DataFrame::new(vec![plant_ids, pollinators, flower_visitors]).unwrap();

        let guild_ids: Vec<String> = vec!["plant_a".into(), "plant_b".into()];
        let counts = count_shared_organisms(
            &df,
            &guild_ids,
            &["pollinators", "flower_visitors"]
        ).unwrap();

        // bee_1 appears in: plant_a (pollinators), plant_b (pollinators + flower_visitors)
        // After deduplication: 2 plants
        assert_eq!(counts.get("bee_1"), Some(&2));
        // butterfly_1 appears in both plants
        assert_eq!(counts.get("butterfly_1"), Some(&2));
        // bee_2 appears in 1 plant
        assert_eq!(counts.get("bee_2"), Some(&1));
    }
}
