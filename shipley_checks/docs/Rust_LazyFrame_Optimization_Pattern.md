# Rust LazyFrame Optimization Pattern

**Date**: 2025-11-17
**Status**: Design Proposal
**Goal**: Establish consistent, safe LazyFrame pattern across all Rust metrics

---

## Problem Statement

LazyFrame's explicit column selection caused M3/M7 bugs because:

1. **Implicit dependencies**: Downstream functions assumed columns existed
2. **Fragile coupling**: Materialization point didn't know all downstream needs
3. **Silent failures**: Missing columns returned empty lists (no errors)
4. **Poor discoverability**: Column requirements scattered across code

---

## Design Principles

### 1. Explicit Column Contracts

Each metric must declare its column requirements upfront:

```rust
pub mod m3_insect_control {
    /// Column requirements for M3 calculation
    pub const REQUIRED_ORGANISM_COLS: &[&str] = &[
        "plant_wfo_id",
        "herbivores",
        "flower_visitors",
        "predators_hasHost",
        "predators_interactsWith",
        "predators_adjacentTo",
    ];

    pub const REQUIRED_FUNGI_COLS: &[&str] = &[
        "plant_wfo_id",
        "entomopathogenic_fungi",
    ];
}
```

### 2. Centralized Column Selection Helper

Create utility for safe LazyFrame materialization:

```rust
// src/utils/lazy_helpers.rs

use polars::prelude::*;

/// Materialize LazyFrame with explicit column list and validation
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
        .with_context(|| format!("{}: Failed to materialize columns", context))?;

    // VALIDATE: Check all expected columns present
    let actual_cols: HashSet<&str> = df.get_column_names()
        .into_iter()
        .collect();

    for &expected in columns {
        if !actual_cols.contains(expected) {
            return Err(anyhow!(
                "{}: Missing expected column '{}'. Available: {:?}",
                context, expected, actual_cols
            ));
        }
    }

    Ok(df)
}
```

### 3. Filter Helper

```rust
/// Filter DataFrame to guild plants with validation
pub fn filter_to_guild(
    df: &DataFrame,
    plant_ids: &[String],
    context: &str,
) -> Result<DataFrame> {
    // Validate plant_wfo_id column exists
    let id_col = df.column("plant_wfo_id")
        .with_context(|| format!("{}: Missing plant_wfo_id column", context))?
        .str()?;

    // Filter
    let id_set: HashSet<_> = plant_ids.iter().collect();
    let mask: BooleanChunked = id_col
        .into_iter()
        .map(|opt| opt.map_or(false, |s| id_set.contains(&s.to_string())))
        .collect();

    df.filter(&mask)
        .with_context(|| format!("{}: Failed to filter to guild", context))
}
```

---

## Refactored Metric Pattern

### Before (Fragile)

```rust
pub fn calculate_m3(...) -> Result<M3Result> {
    // ❌ Implicit column requirements
    let organisms_selected = organisms_lazy
        .clone()
        .select(&[
            col("plant_wfo_id"),
            col("herbivores"),
            // ... hope we got all columns!
        ])
        .collect()?;

    // ❌ No validation
    let guild_organisms = filter_to_guild_inline(&organisms_selected, plant_ids)?;

    // ❌ Silent failure if columns missing
    extract_predator_data(&guild_organisms)?;
}
```

### After (Explicit)

```rust
pub fn calculate_m3(...) -> Result<M3Result> {
    // ✅ Explicit column declaration
    let organisms = materialize_with_columns(
        organisms_lazy,
        REQUIRED_ORGANISM_COLS,
        "M3 organisms",
    )?;

    // ✅ Validated filtering
    let guild_organisms = filter_to_guild(
        &organisms,
        plant_ids,
        "M3",
    )?;

    // ✅ Guaranteed columns present
    extract_predator_data(&guild_organisms)?;
}
```

---

## Implementation Plan

### Phase 1: Create Helper Module ✓ TODO

**File**: `src/utils/lazy_helpers.rs`

```rust
//! LazyFrame materialization helpers with column validation

use polars::prelude::*;
use anyhow::{Context, Result, anyhow};
use std::collections::HashSet;

/// Materialize LazyFrame with explicit column list and validation
pub fn materialize_with_columns(
    lazy: &LazyFrame,
    columns: &[&str],
    context: &str,
) -> Result<DataFrame> {
    let col_exprs: Vec<Expr> = columns.iter().map(|&n| col(n)).collect();

    let df = lazy
        .clone()
        .select(&col_exprs)
        .collect()
        .with_context(|| format!("{}: Failed to materialize", context))?;

    // Validate all columns present
    let actual: HashSet<&str> = df.get_column_names().into_iter().collect();
    for &expected in columns {
        if !actual.contains(expected) {
            return Err(anyhow!(
                "{}: Missing column '{}'. Have: {:?}",
                context, expected, actual
            ));
        }
    }

    Ok(df)
}

/// Filter DataFrame to guild plants
pub fn filter_to_guild(
    df: &DataFrame,
    plant_ids: &[String],
    context: &str,
) -> Result<DataFrame> {
    let id_col = df.column("plant_wfo_id")
        .with_context(|| format!("{}: No plant_wfo_id", context))?
        .str()?;

    let id_set: HashSet<_> = plant_ids.iter().collect();
    let mask: BooleanChunked = id_col
        .into_iter()
        .map(|opt| opt.map_or(false, |s| id_set.contains(&s.to_string())))
        .collect();

    df.filter(&mask)
        .with_context(|| format!("{}: Filter failed", context))
}
```

### Phase 2: Define Column Requirements ✓ TODO

**For each metric**, add constants at module level:

```rust
// m1_pest_independence.rs
pub const REQUIRED_PLANT_COLS: &[&str] = &["wfo_taxon_id"];

// m2_growth_compatibility.rs
pub const REQUIRED_PLANT_COLS: &[&str] = &[
    "wfo_taxon_id",
    "CSR_C", "CSR_S", "CSR_R",
    "light_pref",
    "height_m",
    "try_growth_form",
];

// m3_insect_control.rs
pub const REQUIRED_ORGANISM_COLS: &[&str] = &[
    "plant_wfo_id",
    "herbivores",
    "flower_visitors",
    "predators_hasHost",
    "predators_interactsWith",
    "predators_adjacentTo",
];
pub const REQUIRED_FUNGI_COLS: &[&str] = &[
    "plant_wfo_id",
    "entomopathogenic_fungi",
];

// m4_disease_control.rs
pub const REQUIRED_FUNGI_COLS: &[&str] = &[
    "plant_wfo_id",
    "pathogenic_fungi",
    "mycoparasite_fungi",
];
pub const REQUIRED_ORGANISM_COLS: &[&str] = &[
    "plant_wfo_id",
    "fungivores_eats",
];

// m5_beneficial_fungi.rs
pub const REQUIRED_FUNGI_COLS: &[&str] = &[
    "plant_wfo_id",
    "amf_fungi",
    "emf_fungi",
    "endophytic_fungi",
    "saprotrophic_fungi",
];

// m6_structural_diversity.rs
pub const REQUIRED_PLANT_COLS: &[&str] = &[
    "wfo_taxon_id",
    "wfo_scientific_name",
    "height_m",
    "light_pref",  // Uses EIVEres-L_complete
    "try_growth_form",
];

// m7_pollinator_support.rs
pub const REQUIRED_ORGANISM_COLS: &[&str] = &[
    "plant_wfo_id",
    "pollinators",
    "flower_visitors",
];
```

### Phase 3: Refactor Each Metric ✓ TODO

**M1**: Already simple (no LazyFrame filtering)

**M2**:
```rust
pub fn calculate_m2(...) -> Result<M2Result> {
    let plants = materialize_with_columns(
        plants_lazy,
        REQUIRED_PLANT_COLS,
        "M2 plants",
    )?;

    let guild_plants = filter_to_guild(&plants, plant_ids, "M2")?;
    // ... rest of calculation
}
```

**M3**:
```rust
pub fn calculate_m3(...) -> Result<M3Result> {
    let organisms = materialize_with_columns(
        organisms_lazy,
        REQUIRED_ORGANISM_COLS,
        "M3 organisms",
    )?;

    let fungi = materialize_with_columns(
        fungi_lazy,
        REQUIRED_FUNGI_COLS,
        "M3 fungi",
    )?;

    let guild_organisms = filter_to_guild(&organisms, plant_ids, "M3")?;
    let guild_fungi = filter_to_guild(&fungi, plant_ids, "M3")?;
    // ... rest
}
```

**M4, M5, M6, M7**: Similar pattern

### Phase 4: Add Tests ✓ TODO

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_column_validation() {
        // Create LazyFrame missing required column
        let lazy = ...;

        // Should error with clear message
        let result = materialize_with_columns(
            &lazy,
            &["missing_col"],
            "test",
        );

        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("Missing column"));
    }
}
```

---

## Benefits

### 1. Discoverability
```rust
// Clear at top of file what columns are needed
pub const REQUIRED_ORGANISM_COLS: &[&str] = &[...];
```

### 2. Validation
```rust
// Runtime error if column missing (not silent failure)
materialize_with_columns(...)?;  // Errors immediately if column absent
```

### 3. Maintainability
```rust
// Add column in ONE place
pub const REQUIRED_COLS: &[&str] = &[
    "existing",
    "new_column",  // ← Add here, automatic everywhere
];
```

### 4. Documentation
```rust
// Self-documenting dependencies
/// M3 requires:
/// - REQUIRED_ORGANISM_COLS from organisms parquet
/// - REQUIRED_FUNGI_COLS from fungi parquet
pub fn calculate_m3(...) -> Result<M3Result>
```

---

## Migration Strategy

### Step 1: Add Helper Module (Non-Breaking)
- Create `src/utils/lazy_helpers.rs`
- Add to `mod.rs`
- No existing code affected

### Step 2: Add Column Constants (Non-Breaking)
- Add `pub const REQUIRED_*_COLS` to each metric
- Document current behavior
- No existing code affected

### Step 3: Refactor One Metric at a Time
- M1 (simplest)
- M2
- M3, M4, M5, M6, M7
- Test after each

### Step 4: Remove Old Inline Code
- Delete inline `.select()` calls
- Delete inline filter logic
- Centralized in helpers

---

## Future Enhancements

### 1. Compile-Time Validation (const generics)

```rust
struct ColumnSet<const N: usize> {
    names: [&'static str; N],
}

impl<const N: usize> ColumnSet<N> {
    const fn new(names: [&'static str; N]) -> Self {
        Self { names }
    }
}

const M3_ORGANISM_COLS: ColumnSet<6> = ColumnSet::new([
    "plant_wfo_id",
    "herbivores",
    // ... compile-time array
]);
```

### 2. Column Dependency Graph

```rust
// Auto-generate required columns from all metrics
pub fn get_all_organism_cols() -> HashSet<&'static str> {
    [
        m3::REQUIRED_ORGANISM_COLS,
        m4::REQUIRED_ORGANISM_COLS,
        m7::REQUIRED_ORGANISM_COLS,
    ]
    .iter()
    .flat_map(|&cols| cols.iter())
    .copied()
    .collect()
}
```

### 3. Lazy Column Union

```rust
// Materialize UNION of all metric requirements
let all_organism_cols = get_all_organism_cols();
let organisms = materialize_with_columns(
    organisms_lazy,
    &all_organism_cols.iter().copied().collect::<Vec<_>>(),
    "All metrics",
)?;

// Pass to all metrics (they filter to what they need)
```

---

## Performance Considerations

### Current (After M3/M7 Fix)
- M3: 6 organism columns
- M7: 3 organism columns
- **Total**: 6 columns loaded (if sequential)

### Optimized (Shared Materialization)
- Load organism columns ONCE with union of M3 + M7 requirements
- Pass same DataFrame to both metrics
- **Benefit**: Avoid redundant I/O

### Memory Trade-off
- **More columns**: Slightly higher memory (6 cols vs 3 for M7)
- **Fewer I/O ops**: Only one `.collect()` instead of two
- **Net win**: For 11,711 rows, memory difference negligible vs I/O savings

---

## Conclusion

LazyFrame pattern with explicit column contracts provides:
- ✅ **Safety**: Runtime validation prevents silent failures
- ✅ **Clarity**: Column requirements documented at module level
- ✅ **Maintainability**: Centralized column lists
- ✅ **Performance**: Optimized I/O with minimal memory cost

**Next Steps:**
1. Review this design
2. Implement helper module
3. Migrate metrics one by one
4. Validate parity maintained throughout
