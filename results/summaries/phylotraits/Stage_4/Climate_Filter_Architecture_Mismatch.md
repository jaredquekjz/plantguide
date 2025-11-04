# Climate Filter Architecture Mismatch - Critical Issue

**Date**: 2025-11-04
**Severity**: HIGH - Architecture mismatch between documentation and implementation
**Status**: NEEDS FIXING before calibration

---

## Executive Summary

**Problem**: Document 4.4 specifies Köppen tier-based architecture, but scripts still use old temperature/precipitation envelope filtering.

**Impact**:
- Calibration sampling wrong (using envelope overlap instead of tier membership)
- Guild scoring has redundant climate filter (frontend already filters by tier)
- Incompatible with planned tier-stratified calibration approach

**Required changes**: 5 scripts need updating

---

## The Architecture Plan (Document 4.4)

### How It Should Work

**Step 1: Frontend Plant Selection**
```
User location (lat, lon) → Köppen zone → Tier
Example: London (51.5, -0.1) → Cfb → Tier 3 (Humid Temperate)

Frontend shows ONLY plants where tier_3_humid_temperate = TRUE
  → 8,619 plants available for guild building
```

**Step 2: Guild Building**
```
User selects 7 plants from the 8,619 pre-filtered plants
All plants guaranteed to be in Tier 3
```

**Step 3: Guild Scoring**
```
Load normalization_params_7plant.json → tier_3_humid_temperate section
Score guild using tier-specific percentiles
NO climate filtering needed (all plants already in same tier)
```

**Step 4: Display**
```
"Your guild scores at 67th percentile compared to 20,000
Humid Temperate guilds from similar climate zones"
```

### Calibration Strategy (Document 4.4 Section "Climate-Stratified Calibration")

**Generate 6 separate calibrations**:
```
For each tier in [tropical, mediterranean, humid_temperate, continental, boreal_polar, arid]:
  1. Filter plants where tier_X = TRUE
  2. Generate 20,000 random guilds from that plant pool
  3. Compute raw scores
  4. Compute percentiles
  5. Save in normalization_params[tier_X]
```

**Output structure**:
```json
{
  "tier_1_tropical": {
    "n1": {"p1": ..., "p50": ..., "p99": ...},
    "n2": {...},
    ...
  },
  "tier_2_mediterranean": {...},
  ...
}
```

---

## Current Implementation (What Scripts Actually Do)

### 1. guild_scorer_v3.py - Climate Filter

**Current logic** (lines 336-420):
```python
def _check_climate_compatibility(plants_data, n_plants):
    # Temperature envelope overlap
    shared_temp_min = plants_data['temp_annual_min'].max()
    shared_temp_max = plants_data['temp_annual_max'].min()
    temp_overlap = shared_temp_max - shared_temp_min

    if temp_overlap < 0:
        veto = True  # No temperature overlap

    # Precipitation envelope overlap
    shared_precip_min = plants_data['precip_annual_min'].max()
    shared_precip_max = plants_data['precip_annual_max'].min()

    if precip_overlap < 0:
        veto = True  # No precipitation overlap

    # Return veto if incompatible
```

**Problems**:
1. ✗ Uses temperature/precipitation ranges (old approach)
2. ✗ Ignores Köppen tier membership flags
3. ✗ Redundant - frontend already ensures plants are in same tier
4. ✗ Can veto valid guilds if plants have wide climate ranges within same tier

**What it should do**:
```python
def _check_climate_compatibility_tier_based(plants_data, n_plants):
    # Simple sanity check: all plants should be in same tier
    # (Frontend guarantees this, but verify for robustness)

    # Get tier columns
    tier_cols = ['tier_1_tropical', 'tier_2_mediterranean',
                 'tier_3_humid_temperate', 'tier_4_continental',
                 'tier_5_boreal_polar', 'tier_6_arid']

    # Check which tier(s) all plants share
    shared_tiers = []
    for tier in tier_cols:
        if (plants_data[tier] == True).all():
            shared_tiers.append(tier)

    if len(shared_tiers) == 0:
        # No shared tier - plants from incompatible climates
        return {
            'veto': True,
            'reason': 'No Shared Climate Tier',
            'message': 'Plants are from different Köppen climate tiers'
        }

    # Success - plants share at least one tier
    return {
        'veto': False,
        'shared_tiers': shared_tiers,
        'primary_tier': shared_tiers[0],  # Use first shared tier
        'message': f'All plants compatible in {shared_tiers[0]}'
    }
```

---

### 2. calibrate_normalizations_simple.py - Sampling

**Current logic** (lines 95-138):
```python
def build_climate_compatibility(plants_df):
    # Build matrix of temperature/precipitation overlap
    for plant_a in plants_df:
        temp_overlap = (
            np.maximum(plant_a['temp_min'], plants_df['temp_min']) <
            np.minimum(plant_a['temp_max'], plants_df['temp_max'])
        )
        precip_overlap = (
            np.maximum(plant_a['precip_min'], plants_df['precip_min']) <
            np.minimum(plant_a['precip_max'], plants_df['precip_max'])
        )
        compatible = temp_overlap & precip_overlap
        compatibility[plant_a] = compatible_ids

def sample_climate_compatible_guild(n_plants, compatibility, all_species):
    # Sample from compatibility matrix
    anchor_id = random.choice(all_species)
    others = random.choice(compatibility[anchor_id], n_plants-1)
    return [anchor_id] + others
```

**Problems**:
1. ✗ Uses envelope compatibility (wrong approach)
2. ✗ Generates single global calibration (should be 6 tier-specific calibrations)
3. ✗ Mixes plants from different biogeographic regions
4. ✗ Output: `normalization_params_7plant.json` (flat structure, not tier-stratified)

**What it should do**:
```python
def main(guild_size=7):
    plants_df = load_dataset()

    tier_names = ['tier_1_tropical', 'tier_2_mediterranean',
                  'tier_3_humid_temperate', 'tier_4_continental',
                  'tier_5_boreal_polar', 'tier_6_arid']

    all_params = {}

    for tier in tier_names:
        print(f"\n{'='*80}")
        print(f"CALIBRATING {tier.upper()}")
        print(f"{'='*80}")

        # Filter plants in this tier
        tier_plants = plants_df[plants_df[tier] == True]
        print(f"  Plant pool: {len(tier_plants):,}")

        if len(tier_plants) < guild_size:
            print(f"  SKIP: Insufficient plants for {guild_size}-plant guilds")
            continue

        # Generate 20,000 random guilds from this tier's plant pool
        guilds = []
        tier_plant_ids = tier_plants['wfo_taxon_id'].values
        for _ in tqdm(range(20000), desc=f"{tier} guilds"):
            guild = random.choice(tier_plant_ids, size=guild_size, replace=False)
            guilds.append(list(guild))

        # Compute raw scores
        raw_scores = {...}
        for guild in tqdm(guilds, desc="Computing scores"):
            scores = compute_raw_scores(guild, ...)
            for key in raw_scores:
                raw_scores[key].append(scores[key])

        # Compute percentiles
        params = {}
        for metric in ['n1', 'n2', 'n4', 'n5', 'n6', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6']:
            params[metric] = {
                'p1': np.percentile(raw_scores[metric + '_raw'], 1),
                'p50': np.percentile(raw_scores[metric + '_raw'], 50),
                'p99': np.percentile(raw_scores[metric + '_raw'], 99),
                # ... all percentiles
            }

        all_params[tier] = params

    # Save tier-stratified parameters
    output_path = Path(f'data/stage4/normalization_params_{guild_size}plant.json')
    with open(output_path, 'w') as f:
        json.dump(all_params, f, indent=2)
```

**Output structure** (tier-stratified):
```json
{
  "tier_1_tropical": {
    "n1": {"p1": 0.001, "p50": 0.023, "p99": 0.345, ...},
    "n2": {"p1": 0.002, "p50": 0.034, "p99": 0.456, ...},
    ...
  },
  "tier_2_mediterranean": {...},
  "tier_3_humid_temperate": {...},
  "tier_4_continental": {...},
  "tier_5_boreal_polar": {...},
  "tier_6_arid": {...}
}
```

---

### 3. guild_scorer_v3.py - Normalization Loading

**Current logic** (lines 59-76):
```python
def __init__(self, calibration_type='7plant'):
    norm_file = 'normalization_params_7plant.json'
    with open(norm_file) as f:
        self.norm_params = json.load(f)

    # Flat structure: self.norm_params['n1'], self.norm_params['p4'], etc.
```

**What it should do**:
```python
def __init__(self, calibration_type='7plant', climate_tier='tier_3_humid_temperate'):
    norm_file = f'normalization_params_{calibration_type}.json'
    with open(norm_file) as f:
        all_params = json.load(f)

    # Load tier-specific parameters
    if climate_tier not in all_params:
        raise ValueError(f"Tier {climate_tier} not found in calibration")

    self.norm_params = all_params[climate_tier]
    self.climate_tier = climate_tier

    print(f"Loaded {calibration_type} calibration for {climate_tier}")
```

**Usage**:
```python
# Frontend detects user tier
user_tier = detect_tier_from_location(lat, lon)  # Returns 'tier_3_humid_temperate'

# Initialize scorer with tier
scorer = GuildScorerV3(calibration_type='7plant', climate_tier=user_tier)

# Score guild (all plants pre-filtered to be in user_tier)
result = scorer.score_guild(plant_ids)
```

---

### 4. explanation_engine.py - Climate Messages

**Current messages** (lines 93-120):
```python
if reason == 'No temperature overlap':
    message = "These plants have incompatible temperature ranges..."

if reason == 'No precipitation overlap':
    message = "These plants have incompatible precipitation ranges..."
```

**What it should say** (tier-based):
```python
if reason == 'No Shared Climate Tier':
    message = """
    These plants are from different climate zones:
    - Plant A: Tropical (Köppen Af/Am/Aw)
    - Plant B: Temperate (Köppen Cfb)

    They cannot grow together because their climate requirements don't overlap.
    Please select plants from the same climate tier.
    """
```

---

### 5. compatibility_matrix.py - Pairwise Scoring

**Current approach**: No climate filtering (assumes all 11,680 × 11,679 pairs are valid)

**Tier-aware approach**: Still compute all pairs, but add tier compatibility component
```python
# Component 9: Climate tier compatibility (negative if different tiers)
shared_tiers = set(plant_a_tiers) & set(plant_b_tiers)
if len(shared_tiers) == 0:
    climate_penalty = -1.0  # No shared tier
elif len(shared_tiers) >= 3:
    climate_penalty = 0.0   # Highly compatible (3+ shared tiers)
else:
    climate_penalty = -0.3  # Marginal compatibility (1-2 shared tiers)
```

**Note**: Plant Doctor can still show cross-tier pairs, but penalize incompatible climates.

---

## Data Availability Check

### Do we have tier columns?

✓ YES:
```
model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet

Columns:
- tier_1_tropical (boolean)
- tier_2_mediterranean (boolean)
- tier_3_humid_temperate (boolean)
- tier_4_continental (boolean)
- tier_5_boreal_polar (boolean)
- tier_6_arid (boolean)
- n_koppen_zones (1-29 zones per plant)
- tier_memberships_json (detailed info)
```

### Tier distribution:
```
Tier 1 (Tropical):          1,633 plants (14.0%)
Tier 2 (Mediterranean):     4,036 plants (34.6%)
Tier 3 (Humid Temperate):   8,619 plants (73.8%) ← Largest
Tier 4 (Continental):       4,367 plants (37.4%)
Tier 5 (Boreal/Polar):      1,059 plants (9.1%)
Tier 6 (Arid):              2,759 plants (23.6%)

Total assignments: 22,473 (> 11,680 due to multi-assignment)
```

**Multi-assignment**: Many plants belong to multiple tiers (e.g., Quercus robur in both Tier 3 and Tier 4).

---

## Required Changes Summary

| Script | Current Status | Required Change | Priority |
|--------|---------------|-----------------|----------|
| **calibrate_normalizations_simple.py** | ✗ Uses envelope overlap | Change to tier-based sampling, generate 6 calibrations | CRITICAL |
| **guild_scorer_v3.py** | ✗ Uses envelope filter | Simplify to tier sanity check, load tier-specific params | CRITICAL |
| **explanation_engine.py** | ✗ Envelope-based messages | Update climate veto messages for tiers | HIGH |
| **compatibility_matrix.py** | ⚠ No climate check | Add tier compatibility component | MEDIUM |
| **test_guilds_v3.py** | ⚠ May have envelope tests | Update tests to use tier-based logic | MEDIUM |

---

## Implementation Plan

### Phase 1: Update Calibration (CRITICAL)

**File**: `src/Stage_4/calibrate_normalizations_simple.py`

**Changes**:
1. Remove `build_climate_compatibility()` function
2. Replace with tier-based sampling loop
3. Generate 6 separate calibrations (one per tier)
4. Output tier-stratified JSON structure

**Time estimate**: 2 hours coding + 6 hours running (20K guilds × 6 tiers × 2 sizes = 240K guilds)

### Phase 2: Update Guild Scorer (CRITICAL)

**File**: `src/Stage_4/guild_scorer_v3.py`

**Changes**:
1. Update `__init__()` to accept `climate_tier` parameter
2. Load tier-specific normalization params
3. Simplify `_check_climate_compatibility()` to tier sanity check
4. Update data loading query to include tier columns

**Time estimate**: 1 hour

### Phase 3: Update Explanation Engine (HIGH)

**File**: `src/Stage_4/explanation_engine.py`

**Changes**:
1. Update veto explanation messages for tier-based logic
2. Add tier names to climate compatibility messages

**Time estimate**: 30 minutes

### Phase 4: Update Compatibility Matrix (MEDIUM)

**File**: `src/Stage_4/04_compute_compatibility_matrix.py`

**Changes**:
1. Add tier compatibility scoring component
2. Update formula to include climate tier penalty

**Time estimate**: 1 hour + re-run (2-3 hours)

### Phase 5: Update Documentation (HIGH)

**Files**: `4.4_Unified_Percentile_Framework.md`, `4.5_Data_Flow_and_Integration.md`

**Changes**:
1. Mark old envelope approach as deprecated
2. Emphasize tier-based architecture
3. Update all code examples to show tier usage

**Time estimate**: 1 hour

---

## Why This Matters

### Without tier-based calibration:

**Problem 1: Biased percentiles**
```
Generate 10,000 guilds (all climates mixed):
  - 7,000 from Tier 3 (Humid Temperate, 73.8% of plants)
  - 1,400 from Tier 1 (Tropical, 14.0% of plants)
  - 1,600 from other tiers

User in tropics gets guild with 3 shared pathogenic fungi:
  → Scored against mostly-temperate guilds
  → Percentile = 85th (looks good!)
  → Reality: In tropical context, this is 50th percentile (mediocre)
```

**Problem 2: Ecologically invalid comparisons**
```
Tropical guild: Orchids + Palms + Bromeliads
  → High pathogen overlap (tropical fungi diversity)
  → Scored poorly against temperate guilds (fewer pathogens)
  → User discouraged from valid tropical polyculture
```

**Problem 3: Frontend-backend mismatch**
```
Frontend: "Here are 8,619 Humid Temperate plants for your guild"
Backend: *computes score using all-climate percentiles*
User: "Why is my score so low? I followed your recommendations!"
```

### With tier-based calibration:

**Benefit 1: Fair comparisons**
```
Tropical guild → Scored against 20,000 tropical guilds
Temperate guild → Scored against 20,000 temperate guilds
User sees: "67th percentile for Humid Temperate climate"
```

**Benefit 2: Ecologically valid**
```
High pathogen overlap in tropics? Normal.
High pathogen overlap in boreal zone? Unusual.
Score reflects climate-appropriate expectations.
```

**Benefit 3: Frontend-backend alignment**
```
Frontend filters by tier → Backend scores by tier
Consistent user experience, predictable results.
```

---

## Testing Strategy

### Before tier changes:
```bash
# Current behavior (should show envelope-based vetoes)
python src/Stage_4/guild_scorer_v3.py

# Test mixed-climate guild
test_guild = [
    'wfo-tropical-palm',
    'wfo-temperate-oak',
    'wfo-boreal-spruce'
]
# Expected: Climate veto (no temp/precip overlap)
```

### After tier changes:
```bash
# Tier-aware behavior
scorer = GuildScorerV3(calibration_type='7plant', climate_tier='tier_3_humid_temperate')
test_guild = ['wfo-oak', 'wfo-maple', 'wfo-birch']  # All Tier 3
# Expected: No veto, scored with Tier 3 percentiles

# Mixed tier guild
test_guild_mixed = ['wfo-oak', 'wfo-palm']  # Tier 3 + Tier 1
# Expected: Veto "No Shared Climate Tier"
```

---

## Questions for User

1. **Calibration timing**: Should we fix calibration BEFORE or AFTER other changes?
   - Option A: Fix all scripts first, then run calibration once
   - Option B: Run quick test calibration now to verify approach

2. **Tier selection**: How should frontend detect user tier?
   - Option A: User location (lat/lon) → Köppen lookup → tier
   - Option B: User manually selects climate type (dropdown)
   - Option C: Both options available

3. **Multi-tier plants**: How to handle plants in multiple tiers?
   - Current: Plant can be in 1-6 tiers simultaneously
   - Guild scoring: Use tier where ALL plants overlap
   - Example: Oak (Tier 3+4) + Maple (Tier 3+4) → Score with Tier 3 or Tier 4?

4. **Backwards compatibility**: Keep old envelope filter as fallback?
   - If calibration file lacks tier structure → fall back to envelope
   - Or: Require tier-stratified calibration (error if missing)

---

**Document Status**: CRITICAL ISSUE IDENTIFIED - Awaiting decision on implementation approach

**Next Action**: Get user approval on implementation plan, then execute Phase 1 (calibration update)
