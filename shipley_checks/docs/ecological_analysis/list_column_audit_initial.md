# Guild Scorer List Column Audit Summary

## Issue: Functions trying to read list columns as strings fail silently

### Root Cause
Several functions attempt to access DataFrame columns containing organism/fungi interaction data using `.str()` without first trying `.list()`. Since the data is in Arrow list format, these fail silently and return empty/zero results.

### Confirmed Issues

#### 1. ✅ FIXED: Network Analysis Per-Plant Count Functions
**Status**: Fixed in commit a6a8219

**Files**:
- `src/explanation/pathogen_control_network_analysis.rs`
  - `count_mycoparasites_for_plant()` - FIXED
  - `count_pathogens_for_plant()` - FIXED
- `src/explanation/biocontrol_network_analysis.rs`
  - `count_predators_for_plant()` - FIXED  
  - `count_entomo_fungi_for_plant()` - FIXED

**Impact**: Guild-level summaries showed correct counts but per-plant tables showed all zeros.

#### 2. ❌ NEW BUG FOUND: Pest Profile Analysis
**Status**: NOT FIXED - Currently broken

**File**: `src/explanation/pest_analysis.rs`
**Function**: `analyze_guild_pests()`
**Line**: 52-54

**Code**:
```rust
let herbivores_col = match guild_plants.column("herbivores") {
    Ok(col) => col.str()?,  // ❌ Only tries string format
    Err(_) => return Ok(None),
};
```

**Impact**: Pest profiles are NEVER generated in explanation reports. The function fails silently when trying to read the list column as string, returns `Ok(None)`, and no error is shown to user.

**Expected behavior**: Should try `.list()` first, then fallback to `.str()`

### Correctly Implemented (No Issues)

#### ✅ Metric Calculations
- `src/metrics/m3_insect_control.rs` - Correctly handles list columns
- `src/metrics/m4_disease_control.rs` - Uses `extract_column_data()` which handles both formats
- `src/metrics/m5_beneficial_fungi.rs` - Likely handles list columns (need to verify)

#### ✅ Network Analysis (Guild Level)
- `src/explanation/fungi_network_analysis.rs` - Correctly handles list columns
- `src/explanation/pollinator_network_analysis.rs` - Correctly handles both formats
- `src/explanation/biocontrol_network_analysis.rs` - Guild-level analysis works (only per-plant counts were broken, now fixed)

#### ✅ Utility Functions  
- `src/utils/organism_counter.rs` - Correctly handles list columns first

### Recommended Fix for pest_analysis.rs

Replace lines 51-55 with:
```rust
// Check if herbivores column exists
let herbivores_col = match guild_plants.column("herbivores") {
    Ok(col) => {
        // Try list column first (Phase 0-4 format)
        if col.list().is_ok() {
            col
        } else if col.str().is_ok() {
            col
        } else {
            return Ok(None);
        }
    }
    Err(_) => return Ok(None),
};
```

Then update the processing loop (lines 63-87) to handle both list and string formats, similar to the pattern in `fungi_network_analysis.rs`.

### Testing Plan

1. Fix `pest_analysis.rs` to handle list columns
2. Rebuild and regenerate explanation reports
3. Verify pest profiles appear in reports
4. Check that shared pests, top pests, and vulnerable plants are populated
