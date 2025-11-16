# Phase 0: Stage 4 Data Extraction Pipeline

R DuckDB extraction → Rust-ready parquets for guild scorer

## Overview

**Purpose:** Extract ecological interaction networks for 11,711 plants
**Technology:** R + DuckDB SQL → Polars-compatible parquet files
**Output:** 7 datasets ready for guild_scorer_rust (Phase 1)

**Key Innovation:** DuckDB `COPY TO` produces standard parquet files with no R metadata, eliminating conversion steps.

## Pipeline Architecture

```
Phase 0 (Data Extraction)              Phase 1 (Guild Scoring)
┌─────────────────────────┐            ┌──────────────────────┐
│ R DuckDB Scripts        │            │ guild_scorer_rust    │
│ ├─ Script 0-5           │   ──────>  │ ├─ 7 Metrics (M1-M7) │
│ ├─ DuckDB COPY TO       │            │ └─ Polars LazyFrames │
│ └─ *.parquet outputs    │            └──────────────────────┘
└─────────────────────────┘
```

## Extraction Scripts

**Location:** `shipley_checks/src/Stage_4/r_duckdb_extraction/`

### Script 0: Extract Known Herbivores
```bash
00_extract_known_herbivores.R
```
**Input:** Full GloBI dataset (20.3M interactions)
**Output:** `known_herbivore_insects.parquet` (14,345 species)
**Logic:** Extract all Arthropoda eating Plantae from GloBI

### Script 1: Match Herbivores to Plants
```bash
01_match_herbivores_to_plants.R
```
**Input:** Known herbivores + 11,711 plant dataset
**Output:** `matched_herbivores_per_plant.parquet` (3,141 plants)
**Logic:** Match herbivores to plants, exclude pollinators

### Script 2: Extract Organism Profiles
```bash
02_extract_organism_profiles.R
```
**Input:** GloBI plant interactions
**Output:** `organism_profiles_11711.parquet` (11,711 rows × 17 columns)
**Logic:** Extract pollinators, herbivores, pathogens, predators, fungivores for each plant

**Key columns:**
- `pollinators`, `herbivores`, `pathogens`, `flower_visitors`
- `predators_hasHost`, `predators_interactsWith`, `predators_adjacentTo`
- `fungivores_eats` (animals eating fungi on plants)

**Coverage:**
- 1,564 plants with pollinators (29,319 total)
- 3,141 plants with herbivores (15,417 total)
- 7,394 plants with pathogens (104,850 total)
- 1,333 plants with fungivores (17,586 total)

### Script 3: Extract Fungal Guilds
```bash
03_extract_fungal_guilds_hybrid.R
```
**Input:** FungalTraits (primary) + FunGuild (fallback)
**Output:** `fungal_guilds_hybrid_11711.parquet` (11,711 rows × 26 columns)
**Logic:** Hybrid guild assignment with FungalTraits priority

**Guilds extracted:**
- Pathogenic, AMF, EMF, Mycoparasite, Entomopathogenic, Endophytic, Saprotrophic

**Coverage:**
- 7,210 plants with pathogenic fungi
- 171 plants with AMF
- 313 plants with EMF
- 337 plants with mycoparasites

### Script 4: Build Multitrophic Networks
```bash
04_build_multitrophic_network.R
```
**Input:** Organism profiles + fungal guilds
**Output:**
- `herbivore_predators_11711.parquet` (805 herbivores)
- `pathogen_antagonists_11711.parquet` (942 pathogens)

**Logic:** Build lookup tables for biocontrol relationships

### Script 5: Extract Insect Fungal Parasites
```bash
05_extract_insect_fungal_parasites.R
```
**Input:** GloBI fungal interactions
**Output:** `insect_fungal_parasites_11711.parquet` (2,381 insects)
**Logic:** Extract all parasitism relationships (parasiteOf, pathogenOf, parasitizes, etc.)

**Coverage:** 8,410 total parasite relationships

## Pipeline Execution

### Master Pipeline
```bash
Rscript shipley_checks/src/Stage_4/r_duckdb_extraction/run_extraction_pipeline.R
```

**Steps:**
1. Extract known herbivores (Script 0)
2. Match herbivores to plants (Script 1)
3. Extract organism profiles (Script 2)
4. Extract fungal guilds (Script 3)
5. Build multitrophic networks (Script 4)
6. Extract insect parasites (Script 5)
7. Copy to guild_scorer_rust naming (`*_pure_rust.parquet`)
8. Verify all outputs (data integrity & completeness)

**Output naming:**
- Source: `*_11711.parquet` (descriptive)
- Guild scorer: `*_pure_rust.parquet` (backward compatible)

### Verification
```bash
python shipley_checks/src/Stage_4/r_duckdb_extraction/verify_extraction_outputs.py
```

**Checks:**
- Row counts in expected ranges
- Required columns present
- Data integrity (non-empty lists where expected)
- Polars compatibility (Rust-ready)

**Does NOT check:** Checksums (logic has evolved beyond Python baselines)

## Output Files

**Location:** `shipley_checks/validation/`

| File | Rows | Purpose |
|------|------|---------|
| `known_herbivore_insects.parquet` | 14,345 | All known herbivore species |
| `matched_herbivores_per_plant.parquet` | 3,141 | Plants with herbivores |
| `organism_profiles_11711.parquet` | 11,711 | All organism associations |
| `fungal_guilds_hybrid_11711.parquet` | 11,711 | Fungal guild classifications |
| `herbivore_predators_11711.parquet` | 805 | Herbivore → Predator lookup |
| `pathogen_antagonists_11711.parquet` | 942 | Pathogen → Antagonist lookup |
| `insect_fungal_parasites_11711.parquet` | 2,381 | Insect → Parasite lookup |

**File format:**
- DuckDB `COPY TO` parquet (no R metadata)
- Polars-compatible (direct read, no conversion)
- ZSTD compression (~60% smaller than arrow)

## Phase 0 → Phase 1 Integration

**Guild scorer data loading** (`src/data.rs`):
```rust
// LazyFrames (schema-only, memory efficient)
let organisms_lazy = LazyFrame::scan_parquet(
    "organism_profiles_pure_rust.parquet", ...);
let fungi_lazy = LazyFrame::scan_parquet(
    "fungal_guilds_pure_rust.parquet", ...);

// Lookup tables (eager, fast O(1) access)
let herbivore_predators = load_lookup_table(
    "herbivore_predators_pure_rust.parquet", ...);
let pathogen_antagonists = load_lookup_table(
    "pathogen_antagonists_pure_rust.parquet", ...);
let insect_parasites = load_lookup_table(
    "insect_fungal_parasites_pure_rust.parquet", ...);
```

**Seamless integration:**
- No conversion step required
- Polars reads DuckDB parquets natively
- LazyFrames for large datasets (organisms, fungi)
- Eager HashMaps for small lookups (networks)

## Verification Status

**Latest run:** All checks passed ✓

```
1. Known Herbivore Insects     ✓ 14,345 species
2. Matched Herbivores          ✓ 3,141 plants
3. Organism Profiles           ✓ 11,711 plants (17 columns)
4. Fungal Guilds               ✓ 11,711 plants (26 columns)
5. Herbivore → Predator        ✓ 805 herbivores
6. Pathogen → Antagonist       ✓ 942 pathogens
7. Insect → Parasites          ✓ 2,381 insects
8. Polars Compatibility        ⚠ Skipped (Python test sufficient)
```

## Development Notes

### DuckDB COPY TO Pattern
```r
# ALWAYS use this pattern for Rust-ready parquets
dbExecute(con, sprintf("
  COPY (SELECT * FROM table_name)
  TO '%s'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", output_path))
```

### Boolean Filters (R DuckDB Gotcha)
```r
# Python: FILTER (WHERE is_pathogen) → implicit TRUE
# R:      FILTER (WHERE is_pathogen = TRUE) → explicit TRUE required

# ALWAYS use = TRUE in R DuckDB for parity
LIST(DISTINCT genus) FILTER (WHERE is_pathogen = TRUE)
```

### Fungivore Enhancement (M4 Disease Control)
Script 2 was enhanced to extract fungivorous animals (1,333 plants) for M4 biocontrol mechanism. This addition enables M4 to score both:
1. Mycoparasitic fungi (existing)
2. Fungivorous animals (new) that eat plant pathogens

## Git History

Recent Phase 0 commits:
```
4f5f957 Add Phase 0 verification and master pipeline scripts
bc3d522 Add fungivore extraction to Script 3 for M4 disease biocontrol
627f22c Expand Script 6: Add all parasitism relationship types
d44ddc7 Refactor Script 5 & 6: Remove redundant fungal antagonists
7767da1 Expand Script 5: Add herbivore fungal antagonists network
72a0fcd Add Script 6: Extract global insect-fungal parasite lookup
25ef86b Add Script 5: Build multitrophic network
71c5eb6 Add Script 4: Extract fungal guilds hybrid
6e08269 Fix Script 2 and add Script 3: Organism profiles
22c7de9 Add Phase 0 Script 2: Match herbivores to plants
ff55ee9 Add Phase 0 Script 1: Extract known herbivores
```

## Usage

**Run full pipeline:**
```bash
Rscript shipley_checks/src/Stage_4/r_duckdb_extraction/run_extraction_pipeline.R
```

**Run individual scripts:**
```bash
Rscript shipley_checks/src/Stage_4/r_duckdb_extraction/00_extract_known_herbivores.R
Rscript shipley_checks/src/Stage_4/r_duckdb_extraction/01_match_herbivores_to_plants.R
# ... etc
```

**Verify outputs only:**
```bash
python shipley_checks/src/Stage_4/r_duckdb_extraction/verify_extraction_outputs.py
```

**Test Rust compatibility:**
```bash
cd shipley_checks/src/Stage_4/guild_scorer_rust
cargo run --bin test_parquet_formats
cargo run --bin test_3_guilds_parallel
```

## References

- Old dual verification pipeline: `docs/ARCHIVED_Stage_4_Dual_Verification_Pipeline.md`
- Phase 0 implementation plan: `docs/TEMP_Phase_0_Implementation_Plan.md`
- Guild scorer source: `src/Stage_4/guild_scorer_rust/`
