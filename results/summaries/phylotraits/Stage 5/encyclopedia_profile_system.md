# Stage 5: Encyclopedia Profile System

**Date:** 2025-10-04
**Purpose:** Generate frontend-ready JSON profiles for encyclopedia display combining all validated data sources

## Overview

The encyclopedia profile system produces compact, standardized JSON files optimized for web frontend consumption. Each profile combines:
- **Actual EIVE values** (expert-given) from the dataset
- **Stage 7 reliability metrics** (when available)
- **GloBI interaction networks**
- **GBIF occurrence coordinates** for map display
- **Functional traits** and taxonomy

## Architecture

### Directory Structure

```
src/Stage_8_Encyclopedia/
└── generate_encyclopedia_profiles.py          # Profile generator script

data/encyclopedia_profiles/
├── {species-slug}.json × 654 files           # Generated profiles (14.6 MB total)
└── [Frontend ready for direct consumption]

results/summaries/hybrid_axes/phylotraits/Stage 5/
└── encyclopedia_profile_system.md            # This documentation
```

### Data Flow

```
Comprehensive Dataset (654 species × 243 cols)
    ↓
[Stage_8_Encyclopedia/generate_encyclopedia_profiles.py]
    ├─ Extract actual EIVE values
    ├─ Extract Stage 7 reliability (if available)
    ├─ Extract GloBI interactions
    ├─ Load GBIF coordinates (on-demand)
    └─ Format taxonomy + traits
    ↓
Encyclopedia Profiles (654 JSON files)
    └─ Frontend engine consumption
```

## Profile Schema

Each encyclopedia profile (`data/encyclopedia_profiles/{slug}.json`):

```json
{
  "species": "Abies alba",
  "slug": "abies-alba",
  "taxonomy": {
    "family": "Pinaceae",
    "genus": "Abies",
    "species": "Abies alba"
  },
  "eive": {
    "values": {
      "L": 3.04,      // Light (0-10)
      "M": 5.18,      // Moisture (0-10)
      "R": 5.31,      // Reaction/pH (0-10)
      "N": 4.90,      // Nitrogen (0-10)
      "T": 3.68       // Temperature (0-10)
    },
    "labels": {
      "L": "shade plant (mostly <5% relative illumination)",
      "M": "moist; upper range of fresh soils",
      "R": "moderately acidic soils; occasional neutral/basic",
      "N": "intermediate fertility",
      "T": "moderately cool to moderately warm (montane-submontane)"
    },
    "source": "expert"   // These are actual values, not predictions
  },
  "reliability": {      // Stage 7 validation (if available, otherwise null)
    "L": {
      "verdict": "conflict",
      "score": 1.0,
      "label": "High",
      "confidence": 1.0
    },
    // ... M, R, N, T
  },
  "traits": {
    "growth_form": "tree",
    "woodiness": "woody",
    "height_m": 42.07,
    "leaf_type": "needleleaved",
    "phenology": "evergreen",
    "mycorrhizal": "Pure_EM"
  },
  "interactions": {
    "pollination": {
      "records": 0,
      "partners": 0,
      "top_partners": null
    },
    "herbivory": {...},
    "pathogen": {...}
  },
  "occurrences": {
    "count": 136,
    "coordinates": [
      {
        "lat": 38.61306,
        "lon": -90.25917,
        "year": 1862,
        "country": "US"
      },
      // ... up to 1000 coords (subsampled for performance)
    ]
  }
}
```

## Key Features

### 1. Actual vs. Predicted EIVE

The 654-species dataset contains **expert-given EIVE values** (not predictions). The `EIVEres-*` columns represent actual ecological indicator values from authoritative sources.

**Coverage:** 652/654 species have actual EIVE values (99.7%)

**Fallback logic (if needed):**
```python
# Current implementation uses actual values directly
eive_value = row.get('EIVEres-L')  # Expert-given value

# If missing (2 species), would fallback to predictions
# (No prediction columns currently in dataset)
```

### 2. Reliability Integration

**Stage 7 validation metrics** included when available:
- **10/654 species** currently have reliability scores
- Remaining 644 species have `reliability: null`
- Verdicts: match | partial | conflict | insufficient
- Scores: 0.0–1.0 quantitative reliability
- Labels: High | Medium | Low | Conflict | Unknown

### 3. Coordinate Subsampling

GBIF coordinates limited to **max 1000 per species** for frontend performance:
- If species has >1000 occurrences → random sample of 1000
- Preserves temporal and spatial diversity
- Average: 143 coordinates per species

### 4. Compact JSON Format

**Optimizations:**
- Numbers rounded to 2 decimal places
- Null values used (not empty strings)
- Array format for coordinates (not nested objects)
- No redundant metadata

**Result:** Average profile size **~22 KB** (manageable for web delivery)

## Generation Scripts

### Location

`src/Stage_8_Encyclopedia/generate_encyclopedia_profiles.py`

### Usage

**Generate all species:**
```bash
cd /home/olier/ellenberg
python src/Stage_8_Encyclopedia/generate_encyclopedia_profiles.py
```

**Generate single species:**
```bash
python src/Stage_8_Encyclopedia/generate_encyclopedia_profiles.py --species "Abies alba"
```

**Skip coordinates (faster generation):**
```bash
python src/Stage_8_Encyclopedia/generate_encyclopedia_profiles.py --skip-coords
```

**Test mode (first N species):**
```bash
python src/Stage_8_Encyclopedia/generate_encyclopedia_profiles.py --limit 10
```

### Regeneration

Profiles auto-regenerate when:
- Comprehensive dataset updated
- New GBIF occurrences added
- Stage 7 reliability scores completed (395 pending)

Simply rerun the generation script to update all profiles.

## Frontend Integration

### Profile Access Pattern

```javascript
// Fetch profile for species
const response = await fetch(`/data/encyclopedia_profiles/abies-alba.json`);
const profile = await response.json();

// Display EIVE values with labels
profile.eive.values.L    // 3.04
profile.eive.labels.L    // "shade plant..."

// Check reliability
if (profile.reliability) {
  const lightReliability = profile.reliability.L;
  // Show badge: verdict="conflict", score=1.0, label="High"
}

// Render map with coordinates
profile.occurrences.coordinates.forEach(coord => {
  addMarker(coord.lat, coord.lon, coord.year, coord.country);
});
```

### Performance Considerations

**Total data: 14.6 MB** across 654 files
- Individual profile: ~22 KB average
- Coordinates: ~15 KB per profile (if present)
- Can be served directly (no backend processing needed)

**Optimization options:**
1. Gzip compression (reduces to ~4 MB)
2. CDN caching
3. Lazy-load coordinates (separate endpoint)

## Statistics

| Metric | Value |
|--------|-------|
| Total profiles | 654 |
| Total file size | 14.6 MB |
| Average profile size | 22.3 KB |
| Species with EIVE | 652 (99.7%) |
| Species with reliability | 10 (1.5%) |
| Species with GBIF coords | 646 (98.8%) |
| Average coords per species | 143 |
| Max coords per profile | 1000 (subsampled) |

## Validation Status

✅ **All 654 profiles generated successfully**

**Sample validation (first 100 species):**
- EIVE values: 100/100 ✓
- Taxonomy: 100/100 ✓
- Traits: 100/100 ✓
- Coordinates: 98/100 ✓
- Reliability: 1/100 (expected – only 10 species have validation data)

## Integration with Pipeline Stages

### Source Data
- **Stage 1:** EIVE predictions (not used – actual values preferred)
- **Stage 2:** SEM modeling (not used – actual values preferred)
- **Stage 3:** GloBI integration → `interactions` section
- **Stage 4:** Gemini profiles → Stage 7 validation source
- **Stage 7:** Reliability scoring → `reliability` section
- **Comprehensive dataset:** Primary data source

### Output Consumption
- **Frontend engine:** Direct JSON consumption
- **API endpoints:** Can serve profiles as-is
- **Mobile apps:** Lightweight JSON suitable for mobile
- **Data exports:** Machine-readable format

## Future Enhancements

1. **Complete Stage 7 alignment** → 395 more species with reliability
2. **Add climate niche data** → Bioclim envelopes for range maps
3. **Phenology calendars** → Flowering/fruiting timelines
4. **Conservation status** → IUCN red list integration
5. **Images** → Link to plant photos/illustrations
6. **Common names** → Multilingual vernacular names
7. **Uses/applications** → Economic/medicinal/ornamental

## Maintenance

### Update Workflow

When source data changes:

```bash
# 1. Update comprehensive dataset
python scripts/build_comprehensive_dataset.py

# 2. Regenerate encyclopedia profiles
python src/Stage_8_Encyclopedia/generate_encyclopedia_profiles.py

# 3. Validate output
ls -lh data/encyclopedia_profiles/ | wc -l  # Should be 654
```

### Monitoring

Check profile generation logs:
```bash
tail -f /tmp/encyclopedia_generation.log
```

Validate random sample:
```bash
python -c "import json; print(json.load(open('data/encyclopedia_profiles/abies-alba.json'))['eive'])"
```

## Documentation Locations

**Primary:** `results/summaries/hybrid_axes/phylotraits/Stage 5/encyclopedia_profile_system.md` (this file)

**Related:**
- Canonical data summary: `results/summaries/hybrid_axes/phylotraits/canonical_data_preparation_summary.md`
- Comprehensive dataset schema: `data/comprehensive_dataset_schema.md`
- GBIF linking: `data/gbif_linking_documentation.md`
- Stage 7 validation: `results/summaries/hybrid_axes/phylotraits/Stage 4/README.md`

---

**Generated:** 2025-10-04
**Script:** `src/Stage_8_Encyclopedia/generate_encyclopedia_profiles.py`
**Output:** `data/encyclopedia_profiles/*.json` (654 files, 14.6 MB)
