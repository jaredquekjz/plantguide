//! LazyFrame materialization helpers with column validation
//!
//! Provides safe, explicit patterns for working with Polars LazyFrames
//! to prevent missing column bugs.

use polars::prelude::*;
use anyhow::{Context, Result, anyhow};
use std::collections::HashSet;

/// Materialize LazyFrame with explicit column list and validation
///
/// # Arguments
/// * `lazy` - LazyFrame to materialize
/// * `columns` - Required column names
/// * `context` - Context for error messages (e.g., "M3 organisms")
///
/// # Returns
/// DataFrame with exactly the specified columns
///
/// # Errors
/// Returns error if:
/// - Materialization fails
/// - Any required column is missing from result
///
/// # Example
/// ```rust
/// let df = materialize_with_columns(
///     &organisms_lazy,
///     &["plant_wfo_id", "herbivores"],
///     "M3 organisms",
/// )?;
/// ```
pub fn materialize_with_columns(
    lazy: &LazyFrame,
    columns: &[&str],
    context: &str,
) -> Result<DataFrame> {
    // Build column expressions
    let col_exprs: Vec<Expr> = columns.iter()
        .map(|&name| col(name))
        .collect();

    // Materialize
    let df = lazy
        .clone()
        .select(&col_exprs)
        .collect()
        .with_context(|| format!("{}: Failed to materialize columns {:?}", context, columns))?;

    // VALIDATE: Check all expected columns present
    let actual_cols: HashSet<String> = df.get_column_names()
        .into_iter()
        .map(|s| s.to_string())
        .collect();

    for &expected in columns {
        if !actual_cols.contains(expected) {
            return Err(anyhow!(
                "{}: Missing expected column '{}'. Available columns: {:?}",
                context, expected, actual_cols
            ));
        }
    }

    Ok(df)
}

/// Filter DataFrame to guild plants with validation
///
/// # Arguments
/// * `df` - DataFrame to filter (must have ID column)
/// * `plant_ids` - Plant IDs to keep
/// * `id_col_name` - Name of the ID column (e.g., "plant_wfo_id" or "wfo_taxon_id")
/// * `context` - Context for error messages (e.g., "M3")
///
/// # Returns
/// Filtered DataFrame containing only rows for specified plants
///
/// # Errors
/// Returns error if:
/// - ID column is missing
/// - Filtering fails
///
/// # Example
/// ```rust
/// let guild_df = filter_to_guild(
///     &organisms_df,
///     &plant_ids,
///     "plant_wfo_id",
///     "M3",
/// )?;
/// ```
pub fn filter_to_guild(
    df: &DataFrame,
    plant_ids: &[String],
    id_col_name: &str,
    context: &str,
) -> Result<DataFrame> {
    // Validate ID column exists
    let id_col = df.column(id_col_name)
        .with_context(|| format!("{}: Missing {} column", context, id_col_name))?
        .str()?;

    // Build filter mask
    let id_set: HashSet<_> = plant_ids.iter().collect();
    let mask: BooleanChunked = id_col
        .into_iter()
        .map(|opt| opt.map_or(false, |s| id_set.contains(&s.to_string())))
        .collect();

    // Apply filter
    df.filter(&mask)
        .with_context(|| format!("{}: Failed to filter to guild plants using column '{}'", context, id_col_name))
}

#[cfg(test)]
mod tests {
    use super::*;
    use polars::prelude::*;

    #[test]
    fn test_materialize_with_columns_success() {
        // Create test LazyFrame
        let df = df![
            "plant_wfo_id" => &["p1", "p2"],
            "herbivores" => &["h1", "h2"],
            "extra_col" => &["e1", "e2"],
        ].unwrap();

        let lazy = df.lazy();

        // Should succeed with valid columns
        let result = materialize_with_columns(
            &lazy,
            &["plant_wfo_id", "herbivores"],
            "test",
        );

        assert!(result.is_ok());
        let materialized = result.unwrap();
        assert_eq!(materialized.width(), 2); // Only 2 columns
        assert_eq!(materialized.height(), 2); // 2 rows
    }

    #[test]
    fn test_materialize_with_columns_missing() {
        let df = df![
            "plant_wfo_id" => &["p1"],
        ].unwrap();

        let lazy = df.lazy();

        // Should error with missing column
        let result = materialize_with_columns(
            &lazy,
            &["missing_column"],
            "test",
        );

        assert!(result.is_err());
        let err_msg = result.unwrap_err().to_string();
        assert!(err_msg.contains("missing_column") || err_msg.contains("not found"));
    }

    #[test]
    fn test_filter_to_guild_success() {
        let df = df![
            "plant_wfo_id" => &["p1", "p2", "p3"],
            "data" => &[1, 2, 3],
        ].unwrap();

        let plant_ids = vec!["p1".to_string(), "p3".to_string()];

        let result = filter_to_guild(&df, &plant_ids, "plant_wfo_id", "test");

        assert!(result.is_ok());
        let filtered = result.unwrap();
        assert_eq!(filtered.height(), 2); // Only p1 and p3
    }

    #[test]
    fn test_filter_to_guild_missing_column() {
        let df = df![
            "wrong_column" => &["p1"],
        ].unwrap();

        let plant_ids = vec!["p1".to_string()];

        let result = filter_to_guild(&df, &plant_ids, "plant_wfo_id", "test");

        assert!(result.is_err());
        let err_msg = result.unwrap_err().to_string();
        assert!(err_msg.contains("plant_wfo_id"));
    }
}
