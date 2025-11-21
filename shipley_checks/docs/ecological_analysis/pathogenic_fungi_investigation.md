# Pathogenic Fungi Classification Investigation

**Date:** 2025-11-21
**Issue:** Well-known plant pathogens appearing in "Beneficial Fungi Network" section

## Summary

**CONFIRMED: Data handling issue in Rust code, NOT a data classification error**

The parquet data is correct. These fungi are dual-lifestyle organisms that legitimately appear in BOTH pathogenic_fungi AND saprotrophic_fungi columns. The Rust code only reads the beneficial fungi columns and never checks for pathogenic overlap.

## Investigation Results

### 1. Parquet Data Verification

Queried `fungal_guilds_hybrid_11711.parquet` for problematic fungi:

| Fungus | Plants | Pathogenic | Saprotrophic | Dual-Lifestyle |
|--------|--------|------------|--------------|----------------|
| Colletotrichum | 802 | 802 (100%) | 802 (100%) | 802 (100%) |
| Alternaria | 623 | 623 (100%) | 623 (100%) | 623 (100%) |
| Botrytis | 349 | 349 (100%) | 349 (100%) | 349 (100%) |
| Botryosphaeria | 238 | 238 (100%) | 238 (100%) | 238 (100%) |
| Mycosphaerella | 947 | 947 (100%) | 947 (100%) | 947 (100%) |
| Phyllosticta | 993 | 993 (100%) | 993 (100%) | 993 (100%) |
| Septoria | 1201 | 1201 (100%) | 1201 (100%) | 1201 (100%) |

**Finding:** All problematic fungi appear in BOTH columns for 100% of plants. This is correct dual-lifestyle classification.

### 2. FungalTraits Classification Logic

Reviewed `03_extract_fungal_guilds_hybrid.R` (lines 63-71):

```r
# Guild flags
is_pathogen = (f.primary_lifestyle = 'plant_pathogen' OR
               CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'pathogen'))

is_saprotrophic = (f.primary_lifestyle IN ('wood_saprotroph', 'litter_saprotroph', ...) OR
                   CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'saprotroph') OR
                   CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'decomposer'))
```

**Finding:** FungalTraits (128 mycologists, expert-curated) correctly identifies these as dual-lifestyle fungi. A fungus can be:
- Primary lifestyle: plant_pathogen
- Secondary lifestyle: saprotroph/decomposer

This matches ecological reality - many pathogens also decompose dead plant material.

### 3. Rust Code Issue

Found in `fungi_network_analysis.rs` (lines 240-245, 307):

```rust
let columns = ["amf_fungi", "emf_fungi", "endophytic_fungi", "saprotrophic_fungi"];
```

**Problem:**
- Loads beneficial fungi from these 4 columns ONLY
- NEVER checks if a fungus also appears in `pathogenic_fungi` column
- Result: Dual-lifestyle pathogens treated as beneficial without filtering

**Example:** Colletotrichum
- In parquet: `pathogenic_fungi = ['colletotrichum']` AND `saprotrophic_fungi = ['colletotrichum']`
- Rust reads: Only sees `saprotrophic_fungi` column
- Report shows: "colletotrichum | Saprotrophic | 3 plants" (no pathogen warning)

## Ecological Context

### What are Dual-Lifestyle Fungi?

Many fungi have complex life histories with multiple ecological roles:

1. **Colletotrichum** (Anthracnose pathogen)
   - Primary: Causes leaf spots, fruit rot, stem cankers on living plants
   - Secondary: Decomposes dead plant tissue as saprotroph

2. **Alternaria** (Early blight pathogen)
   - Primary: Causes leaf spots and fruit rot on living plants
   - Secondary: Colonizes and decomposes dead plant material

3. **Botrytis** (Gray mold pathogen)
   - Primary: Causes fruit rot and flower blight
   - Secondary: Actively decomposes senescent plant tissues

### Why FungalTraits is Correct

FungalTraits classifies these as BOTH pathogenic AND saprotrophic because:
- They cause disease on living tissue (pathogenic behavior)
- They actively decompose dead tissue (saprotrophic behavior)
- Their ecological niche spans both roles

This is scientifically accurate dual-lifestyle classification.

## Solution

### Recommended Fix

**Update Rust code to prioritize pathogenic behavior in reporting**

Modify `fungi_network_analysis.rs`:

1. **First pass**: Load all `pathogenic_fungi` for guild plants into exclusion set
2. **Second pass**: When processing beneficial fungi columns, skip any fungus in exclusion set

**Functions to update:**
- `categorize_fungi()` (line 220)
- `build_fungus_to_plants_mapping()` (line 291)

**Logic:**
```rust
// Step 0: Build pathogen exclusion set
let mut pathogen_set: FxHashSet<String> = FxHashSet::default();
for idx in 0..fungi_df.height() {
    if let Some(plant_id) = fungi_plant_col.get(idx) {
        if guild_plant_set.contains(plant_id) {
            if let Ok(col) = fungi_df.column("pathogenic_fungi") {
                if let Ok(list_col) = col.list() {
                    if let Some(list_series) = list_col.get_as_series(idx) {
                        if let Ok(str_series) = list_series.str() {
                            for fungus_opt in str_series.into_iter() {
                                if let Some(fungus) = fungus_opt {
                                    pathogen_set.insert(fungus.trim().to_string());
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// Step 1: Process beneficial columns, exclude pathogens
for col_name in &["amf_fungi", "emf_fungi", "endophytic_fungi", "saprotrophic_fungi"] {
    // ... existing code to load fungi ...
    if !pathogen_set.contains(fungus) {
        // Include in beneficial fungi
        category_map.entry(fungus.to_string()).or_insert(category.clone());
    }
}
```

### Benefits of This Approach

1. **Data-driven filtering** - No hardcoded pathogen lists
2. **Preserves source data** - FungalTraits dual-lifestyle classification remains intact
3. **Correct prioritization** - Pathogenic behavior takes precedence in user-facing reports
4. **Per-guild filtering** - Handles edge cases where a fungus might be pathogenic on some plants but not others

### Impact on M5 Scores

Removing dual-lifestyle pathogens will:
- **Reduce total unique beneficial fungi counts** by ~7 genera (across all reports)
- **Lower M5 raw scores slightly** - but this is ecologically accurate
- **Improve user trust** - No longer showing known pathogens as "beneficial"

The score reduction is justified because these fungi provide a disease risk that outweighs their saprotrophic benefits.

## Conclusion

**The parquet data and FungalTraits classification are scientifically correct.** These fungi truly are dual-lifestyle organisms. The issue is purely a presentation problem in the Rust code - we need to prioritize pathogenic behavior when presenting "beneficial fungi networks" to users.

Fix: Update Rust code to filter out dual-lifestyle pathogens from beneficial fungi displays.
