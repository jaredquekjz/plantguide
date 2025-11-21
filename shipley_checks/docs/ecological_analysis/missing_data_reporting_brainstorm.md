# Brainstorm: Reporting Missing Interaction Data

## The Challenge

"We don't know what we don't know" - How to report data completeness when:
1. Zero interactions could mean:
   - Truly no interactions (ecologically valid)
   - No data available (data gap)
   - Species not yet studied
2. We can't distinguish between these cases without external knowledge

## Potential Approaches

### Option 1: Data Coverage Indicators (Simple)

Add coverage quality indicators based on observable patterns:

**Heuristics:**
- **High confidence**: Species with >10 interactions of ANY type (well-studied)
- **Medium confidence**: Species with 1-10 interactions (some data)
- **Low confidence / No data**: Species with 0 interactions (unstudied OR truly isolated)

**Implementation:**
```rust
let data_quality = if total_interactions > 10 {
    "Well-studied species"
} else if total_interactions > 0 {
    "Limited interaction data"
} else {
    "No interaction data available"
};
```

**Display:**
```markdown
**Network Hubs (most connected plants):**
| Plant | Total Fungi | Data Quality |
|-------|-------------|--------------|
| Fraxinus excelsior | 99 | Well-studied |
| Deutzia scabra | 0 | No data available ⚠ |
```

---

### Option 2: Regional/Taxonomic Coverage Metadata

Track coverage by region and taxonomy in a lookup table:

**Create coverage metadata:**
```python
coverage_stats = {
    "Europe": {"fungi": 0.75, "pollinators": 0.82, "herbivores": 0.68},
    "North America": {"fungi": 0.71, "pollinators": 0.79, "herbivores": 0.72},
    "Asia": {"fungi": 0.42, "pollinators": 0.51, "herbivores": 0.55},
    "South America": {"fungi": 0.18, "pollinators": 0.22, "herbivores": 0.31},
    "Hawaii": {"fungi": 0.08, "pollinators": 0.12, "herbivores": 0.15},
    "Australia": {"fungi": 0.15, "pollinators": 0.19, "herbivores": 0.28},
}
```

**Add native range to plants dataset, display coverage:**
```markdown
### Data Quality Notes

⚠️ **Limited data coverage for non-temperate species:**
- 3 Hawaiian endemic species: ~10% GloBI coverage (expect sparse data)
- 2 South American species: ~20% coverage
- 2 European species: ~75% coverage (high confidence)
```

---

### Option 3: Comparison to Expected Patterns

Use ecological priors to flag unlikely zeros:

**Ecological expectations:**
- Flowering plants → should have SOME pollinators
- Trees/shrubs → should have SOME herbivores
- All plants → should have SOME fungi (extremely rare to have zero)

**Flag suspicious zeros:**
```rust
let warnings = vec![];
if has_flowers && pollinator_count == 0 {
    warnings.push("Flowering plant with no pollinator data - likely data gap");
}
if is_woody && herbivore_count == 0 {
    warnings.push("Woody plant with no herbivore data - likely data gap");
}
if fungus_count == 0 {
    warnings.push("No fungal association data - likely data gap");
}
```

---

### Option 4: Interaction Network Density (Statistical)

Calculate network density for guild and flag sparse plants:

**For each guild:**
```python
avg_fungi_per_plant = total_unique_fungi / n_plants
network_density = actual_connections / possible_connections

for plant in guild:
    if plant.fungi_count < 0.1 * avg_fungi_per_plant:
        flag_as_likely_data_gap(plant)
```

**Display:**
```markdown
**Network Hubs:**
| Plant | Fungi | Status |
|-------|-------|--------|
| Fraxinus excelsior | 99 | Hub |
| Vitis vinifera | 279 | Super-hub |
| Deutzia scabra | 0 | Likely data gap ⚠ |
| Rubus moorei | 0 | Likely data gap ⚠ |
```

---

### Option 5: External Validation Dataset

Maintain a curated list of "minimum expected interactions" from literature:

**Create validation dataset:**
```csv
family,min_expected_fungi,min_expected_pollinators,min_expected_herbivores
Rosaceae,5,3,8
Fabaceae,10,5,12
Asteraceae,3,8,15
...
```

**Flag violations:**
```rust
let expected = get_minimum_expected(plant.family);
if plant.fungi < expected.min_fungi {
    warn("Below expected minimum for {family} - possible data gap");
}
```

---

### Option 6: Hybrid Approach (Recommended)

Combine multiple signals for robustness:

**Scoring system:**
```python
def calculate_data_confidence(plant, guild_context):
    score = 0.0

    # Signal 1: Absolute count (well-studied species)
    if plant.total_interactions > 20:
        score += 0.4
    elif plant.total_interactions > 5:
        score += 0.2

    # Signal 2: Relative to guild average
    if plant.total_interactions > 0.5 * guild_avg:
        score += 0.3

    # Signal 3: Regional coverage
    region_coverage = get_region_coverage(plant.native_range)
    score += 0.3 * region_coverage

    return score  # 0.0 (no confidence) to 1.0 (high confidence)
```

**Display with confidence indicator:**
```markdown
| Plant | Fungi | Confidence |
|-------|-------|------------|
| Vitis vinifera | 279 | ████████░░ 80% |
| Deutzia scabra | 0 | ██░░░░░░░░ 20% |
```

---

## Recommended Implementation

**Phase 1 (Quick win):**
- Option 1: Add simple data quality indicators based on interaction counts
- Add footnote: "⚠️ Zero values may indicate data gaps rather than true absence"

**Phase 2 (Medium-term):**
- Option 6: Hybrid confidence scoring
- Track coverage by native range (Europe: high, tropics: low)

**Phase 3 (Long-term):**
- Option 5: Curate minimum expected interactions from literature
- Build coverage metadata from GloBI's source studies

---

## Example Report Output (Phase 1)

```markdown
#### Beneficial Fungi Network Profile

**Total unique beneficial fungi species:** 147

**Network Hubs (most connected plants):**
| Plant | Total Fungi | AMF | EMF | Endophytic | Saprotrophic | Data Quality |
|-------|-------------|-----|-----|------------|--------------|--------------|
| Fraxinus excelsior | 99 | 1 | 1 | 20 | 77 | Well-studied ✓ |
| Diospyros kaki | 45 | 0 | 0 | 7 | 38 | Well-studied ✓ |
| Mercurialis perennis | 22 | 0 | 1 | 0 | 21 | Well-studied ✓ |
| Deutzia scabra | 0 | 0 | 0 | 0 | 0 | No data ⚠ |
| Rubus moorei | 0 | 0 | 0 | 0 | 0 | No data ⚠ |

⚠️ **Data Completeness Note:** Zero interaction counts may indicate missing data rather than true ecological absence. GloBI coverage is highest for European/North American species (~75%), lower for Asian ornamentals (~40%), and minimal for Hawaiian/Australian endemics (~10-15%).
```

---

## Questions for User

1. **Preferred approach:** Simple indicators (Option 1) or more sophisticated confidence scoring (Option 6)?

2. **Display location:**
   - Per-metric (in each network profile section)?
   - Summary section at end of report?
   - Both?

3. **Threshold for "no data" warning:**
   - Flag ALL zeros?
   - Only flag zeros for well-studied taxonomic groups?
   - Only flag when MOST guild members have data?

4. **Native range data:**
   - Do we have native range/origin in the dataset?
   - Worth adding for coverage estimates?
