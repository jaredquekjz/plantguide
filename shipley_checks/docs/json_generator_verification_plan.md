# JSON Generator Verification Plan

Verify that `sections_json/` produces equivalent output to `sections_md/` for S2-S6.
(S1 identity was adapted separately and is intentionally different.)

## Line Count Comparison

| Section | MD Lines | JSON Lines | Notes |
|---------|----------|------------|-------|
| S2 Requirements | 1147 | 608 | JSON smaller (no markdown tables) |
| S3 Maintenance | 265 | 300 | Similar |
| S4 Services | 290 | 350 | Similar |
| S5 Interactions | 425 | 291 | JSON smaller (no markdown lists) |
| S6 Companion | 638 | 625 | Similar |

---

## Phase 1: Logic Diff (Code Review)

For each section, verify these match between MD and JSON versions:

### Checklist per Section

- [ ] **Data extraction**: Same `get_str()`, `get_f64()`, `get_bool()` calls
- [ ] **Thresholds**: Same numeric boundaries for classifications
- [ ] **Match arms**: Same enum variants and conditions
- [ ] **Helper functions**: Same calculation logic
- [ ] **Default values**: Same fallbacks when data missing

### S2: Requirements

| Component | Key Logic to Verify |
|-----------|---------------------|
| Light | EIVE_L thresholds (1-3 shade, 4-6 partial, 7-9 full sun) |
| Temperature | EIVE_T interpretation, frost zones |
| Moisture | EIVE_M bands, drought/waterlogging |
| Soil pH | EIVE_R thresholds, acidity categories |
| Soil Nutrients | EIVE_N interpretation |
| Suitability | Comparison logic against LocalConditions |

### S3: Maintenance

| Component | Key Logic to Verify |
|-----------|---------------------|
| CSR Classification | C/S/R thresholds (0.5 dominant, etc.) |
| Watering Needs | CSR-based derivation |
| Fertilizing | CSR-based derivation |
| Pruning | CSR + growth form logic |
| Pest/Disease | Derived from organism data |

### S4: Services

| Component | Key Logic to Verify |
|-----------|---------------------|
| 10 service ratings | Pre-calculated field extraction |
| Confidence levels | Rating interpretation (0-20, 20-40, etc.) |
| Text descriptions | Consistent interpretation |

### S5: Interactions

| Component | Key Logic to Verify |
|-----------|---------------------|
| Pollinator grouping | Category extraction from OrganismProfile |
| Herbivore grouping | Same |
| Fungal summaries | FungalCounts interpretation |
| Pathogen display | RankedPathogen handling |
| Mycorrhizal type | MycorrhizalType detection |

### S6: Companion

| Component | Key Logic to Verify |
|-----------|---------------------|
| GP1 Structural Layer | get_structural_layer() logic |
| GP2 CSR Balance | CSR compatibility rules |
| GP3 Mycorrhizal | AMF/EMF/Dual/Non detection |
| GP4 Pollinator | Pollinator sharing advice |
| GP5 Pest Biocontrol | Predator detection logic |
| GP6 Disease Control | Mycoparasite/entomopathogen logic |
| GP7 Nutrient Cycling | N-fixer + decomposer logic |

---

## Phase 2: Output Parity Testing

### Test Strategy

Create a Rust test binary that:
1. Loads 3-5 diverse test plants (tree, herb, grass, succulent, etc.)
2. Runs both MD and JSON generators with same inputs
3. Parses MD output to extract key values
4. Compares against JSON struct values
5. Reports any discrepancies

### Test Plants (diverse coverage)

| WFO ID | Species | Reason |
|--------|---------|--------|
| wfo-0000289386 | Quercus acutissima | Tree, EMF, high organism data |
| wfo-0001130737 | Lavandula angustifolia | Herb, pollinators, aromatic |
| wfo-0000738442 | Trifolium repens | N-fixer, AMF, ground cover |
| wfo-0001107095 | Festuca rubra | Grass, stress-tolerant |
| wfo-0001297323 | Aloe vera | Succulent, non-mycorrhizal |

### Comparison Points per Section

#### S2: Requirements
- `light.category` matches MD "Light Requirements:" text
- `temperature.summary` matches MD "Temperature:" section
- `soil.ph_category` matches MD pH interpretation
- `overall_suitability.score_percent` matches MD suitability score

#### S3: Maintenance
- `csr_classification` matches MD CSR category text
- `watering.frequency` matches MD watering guidance
- `fertilizing.approach` matches MD fertilizer advice

#### S4: Services
- All 10 `rating` values match MD emoji counts (star extraction)
- `confidence` values match MD confidence text

#### S5: Interactions
- `pollinators_by_category` count matches MD pollinator list length
- `herbivores_by_category` count matches MD herbivore list length
- `fungal_summary.mycorrhizal_type` matches MD mycorrhizal text

#### S6: Companion
- `guild_details.structural_layer` matches MD GP1 text
- `guild_details.csr_balance.classification` matches MD GP2 text
- `guild_details.mycorrhizal_compatibility.type` matches MD GP3 text

---

## Phase 3: Implementation

### Step 1: Code Review Diffs

```bash
# Generate side-by-side diffs for manual review
diff -y sections_md/s2_requirements.rs sections_json/s2_requirements.rs | less
```

### Step 2: Create Test Binary

```rust
// src/bin/verify_json_parity.rs
// Loads test plants, runs both generators, compares output
```

### Step 3: Run Verification

```bash
cargo run --bin verify_json_parity
```

---

## Acceptance Criteria

- [ ] All threshold values identical between MD and JSON
- [ ] All classification logic produces same categories
- [ ] All helper function calculations match
- [ ] Test plants produce equivalent structured data
- [ ] No regressions in edge cases (missing data, nulls)
