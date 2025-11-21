# Comprehensive List Column Audit & Fix Plan

## Objective
Systematically identify and fix ALL instances where code attempts to read Arrow list columns as strings, causing silent failures.

## Phase 1: Data Structure Discovery

### 1.1 Identify All List Columns in DataFrames
**Action**: Create script to inspect actual column types in parquet files

```python
import duckdb
con = duckdb.connect()

# Check organisms parquet
org_schema = con.execute("""
    DESCRIBE SELECT * FROM read_parquet('shipley_checks/phase0_output/organism_profiles_11711.parquet')
""").fetchall()

# Check fungi parquet  
fungi_schema = con.execute("""
    DESCRIBE SELECT * FROM read_parquet('shipley_checks/phase0_output/fungal_guilds_hybrid_11711.parquet')
""").fetchall()

# Filter for VARCHAR[] (list) columns
list_columns = [col for col in schema if 'VARCHAR[]' in col[1] or 'LIST' in col[1].upper()]
```

**Expected list columns**:
- Organisms: `herbivores`, `pollinators`, `predators_*`, `flower_visitors`, `fungivores_*`
- Fungi: `pathogenic_fungi`, `mycoparasite_fungi`, `entomopathogenic_fungi`, `amf_fungi`, `emf_fungi`, `endophytic_fungi`, `saprotrophic_fungi`

### 1.2 Document Current Column Access Patterns
**Search patterns**:
```bash
# Pattern 1: Direct .str() without .list() check
grep -rn 'column(".*").*\.str()' src --include="*.rs"

# Pattern 2: Pipe-split operations (indicates string assumption)
grep -rn "\.split('|')" src --include="*.rs"

# Pattern 3: Direct column access in loops
grep -rn 'get(idx)' src --include="*.rs" | grep 'split'
```

## Phase 2: Systematic Code Analysis

### 2.1 Check All Files Accessing Organism Data
**Files to audit**:
- [ ] `src/metrics/m3_insect_control.rs` - Uses organisms DataFrame
- [ ] `src/metrics/m4_disease_control.rs` - Uses organisms DataFrame  
- [ ] `src/metrics/m7_pollinator_support.rs` - Uses organisms DataFrame
- [ ] `src/explanation/pest_analysis.rs` - **KNOWN BUG** ❌
- [ ] `src/explanation/pollinator_network_analysis.rs` - Verified ✓
- [ ] `src/explanation/biocontrol_network_analysis.rs` - Fixed ✓
- [ ] `src/utils/organism_counter.rs` - Verified ✓

**For each file, verify**:
- Does it access organism columns directly?
- Does it try `.list()` before `.str()`?
- Does it handle both formats with proper fallback?

### 2.2 Check All Files Accessing Fungi Data  
**Files to audit**:
- [ ] `src/metrics/m3_insect_control.rs` - Uses fungi DataFrame
- [ ] `src/metrics/m4_disease_control.rs` - Uses fungi DataFrame
- [ ] `src/metrics/m5_beneficial_fungi.rs` - Uses fungi DataFrame
- [ ] `src/explanation/fungi_network_analysis.rs` - Verified ✓
- [ ] `src/explanation/pathogen_control_network_analysis.rs` - Fixed ✓
- [ ] `src/explanation/biocontrol_network_analysis.rs` - Fixed ✓

### 2.3 Check Data Loading & Transformation
**Files to audit**:
- [ ] `src/data.rs` - DataFrame loading
- [ ] `src/scorer.rs` - DataFrame joins and transformations
- [ ] Any file doing `.select()`, `.with_column()`, or `.join()` operations

**Risk**: Polars operations might convert list columns to strings during joins/selects

## Phase 3: Create Diagnostic Tools

### 3.1 Column Type Verification Script
Create Rust test to verify column types at runtime:

```rust
#[test]
fn verify_column_types() {
    let organisms_df = load_organisms_dataframe();
    let fungi_df = load_fungi_dataframe();
    
    // Check organisms columns
    assert!(organisms_df.column("herbivores").unwrap().dtype() == &DataType::List(_));
    assert!(organisms_df.column("pollinators").unwrap().dtype() == &DataType::List(_));
    // ... etc
    
    // Check fungi columns
    assert!(fungi_df.column("pathogenic_fungi").unwrap().dtype() == &DataType::List(_));
    // ... etc
}
```

### 3.2 Runtime Column Type Logger
Add debug logging to catch column type mismatches during execution:

```rust
fn safe_column_access(df: &DataFrame, col_name: &str) -> Result<Series> {
    let col = df.column(col_name)?;
    eprintln!("Column '{}' dtype: {:?}", col_name, col.dtype());
    
    if col.dtype().is_list() {
        eprintln!("  → List column detected, use .list() accessor");
    } else if col.dtype().is_string() {
        eprintln!("  → String column detected, use .str() accessor");
    }
    
    Ok(col.clone())
}
```

## Phase 4: Fix All Identified Issues

### 4.1 Standard Fix Pattern
For any function accessing list columns:

```rust
// BEFORE (wrong)
let col = df.column("herbivores")?.str()?;

// AFTER (correct)
let col = df.column("herbivores")?;
if let Ok(list_col) = col.list() {
    // Handle list format
    for idx in 0..df.height() {
        if let Some(list_series) = list_col.get_as_series(idx) {
            if let Ok(str_series) = list_series.str() {
                for item_opt in str_series.into_iter() {
                    if let Some(item) = item_opt {
                        // Process item
                    }
                }
            }
        }
    }
} else if let Ok(str_col) = col.str() {
    // Fallback: pipe-separated string (legacy format)
    for idx in 0..df.height() {
        if let Some(value) = str_col.get(idx) {
            for item in value.split('|').filter(|s| !s.is_empty()) {
                // Process item
            }
        }
    }
}
```

### 4.2 Priority Order for Fixes
1. **Critical** - `pest_analysis.rs` (currently broken, no pest profiles generated)
2. **High** - Any metric calculation (M1-M7) if issues found
3. **Medium** - Network analysis helper functions
4. **Low** - Utility functions, formatters

## Phase 5: Testing & Verification

### 5.1 Unit Tests
Create unit tests for each fixed function:
- Test with list column data
- Test with string column data (legacy)
- Test with empty data
- Test with missing columns

### 5.2 Integration Tests  
- Regenerate all explanation reports
- Verify pest profiles appear
- Verify per-plant counts are accurate
- Compare outputs before/after fixes

### 5.3 Regression Prevention
Add compile-time or runtime checks:
```rust
// Example: Type-safe column accessor
trait SafeColumnAccess {
    fn get_list_column(&self, name: &str) -> Result<ListChunked>;
    fn get_string_column(&self, name: &str) -> Result<Utf8Chunked>;
}
```

## Phase 6: Documentation

### 6.1 Update Code Documentation
Add warnings in comments:
```rust
/// IMPORTANT: The `herbivores` column is a List<String> type in Phase 0-4 parquets.
/// Always try `.list()` first, then fallback to `.str()` for legacy formats.
```

### 6.2 Create Developer Guide
Document:
- Which columns are lists vs strings
- Standard patterns for accessing each type
- Common pitfalls and how to avoid them
- Examples of correct implementations

## Execution Checklist

- [ ] Phase 1: Run column type discovery script
- [ ] Phase 2.1: Audit all organism data access (7 files)
- [ ] Phase 2.2: Audit all fungi data access (6 files)  
- [ ] Phase 2.3: Audit data loading & joins (2 files)
- [ ] Phase 3.1: Create column type verification test
- [ ] Phase 3.2: Add runtime type logging (temporary)
- [ ] Phase 4.1: Fix pest_analysis.rs (critical)
- [ ] Phase 4.2: Fix any other issues found
- [ ] Phase 5.1: Write unit tests for all fixes
- [ ] Phase 5.2: Run integration tests, verify reports
- [ ] Phase 5.3: Add regression prevention measures
- [ ] Phase 6.1: Update code comments
- [ ] Phase 6.2: Write developer guide
- [ ] Final: Remove temporary debug logging
- [ ] Final: Commit all fixes with comprehensive message

## Expected Timeline
- Phase 1-2: 30 minutes (discovery & analysis)
- Phase 3: 20 minutes (diagnostic tools)
- Phase 4: 45 minutes (fixes)
- Phase 5: 30 minutes (testing)
- Phase 6: 15 minutes (documentation)

**Total: ~2.5 hours for complete audit and fix**
