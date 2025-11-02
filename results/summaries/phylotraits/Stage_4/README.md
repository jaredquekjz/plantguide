# Stage 4: Guild Builder Documentation

**Updated**: 2025-11-01
**Status**: Design Phase - Guild Scoring Framework

---

## Document Organization

### Core Framework

**[4.2 Guild Compatibility Framework](4.2_Guild_Compatibility_Framework.md)** ⭐ **START HERE**
- **CRITICAL**: Pairwise averaging is insufficient for guild scoring
- New guild-level overlap scoring approach (not prevalence - focus on shared vulnerabilities)
- **Balanced two-component structure**: negative risks [0, 1] + positive benefits [0, 1] → final [-1, +1]
- 3 negative factors (pathogen/herbivore overlap) + 4 positive factors (cross-benefits, diversity)
- Second-order trophic effects (predator-prey, antagonist-pathogen)
- Equal reachability of +1 and -1 extremes
- DuckDB implementation architecture with complete pseudocode

**[4.5 Fungal Guild Classification - FINAL](4.5_Fungal_Guild_Classification_Final.md)**
- Research-validated hybrid approach (FungalTraits + FunGuild)
- Complete implementation details
- Production results (11,680 plants)
- Data quality and coverage analysis

### Foundation & Analysis

**[4.1 GloBI Data Structure Analysis](4.1_GloBI_Data_Structure_Analysis.md)**
- GloBI database exploration
- Interaction type taxonomy
- Data quality assessment
- Coverage analysis by organism type

**[FungalTraits Dataset Evaluation](FungalTraits_Dataset_Evaluation.md)**
- Database structure and coverage
- Guild classification methodology
- Comparison with FunGuild
- Host specificity data

**[Guild Builder Network Effects Framework](Guild_Builder_Network_Effects_Framework.md)**
- Synergy multiplier design (1.10× to 1.30×)
- Complete fungal network effects
- Multi-guild interactions
- Evidence-based weighting

---

## Critical Discovery: Pairwise Scoring Fails

### The Problem

Initial approach computed pairwise compatibility and averaged for guilds. **This fundamentally fails.**

**Test Results:**
- **Bad Guild** (5 Acacias, 40 shared pathogenic fungi): Score = 0.266
- **Good Guild** (Diverse, minimal overlap): Score = 0.298
- **Difference: Only 0.032** - System cannot distinguish!

### Why It Fails

Pairwise averaging treats these scenarios identically:
- Pathogen X on 1/5 plants (isolated) → affects 4 pairs
- Pathogen X on 5/5 plants (complete overlap) → affects 10 pairs

**Ecologically, complete overlap is catastrophic** (one outbreak destroys entire guild). Pairwise averaging misses this.

### New Approach

**Guild-level overlap scoring:**
- **Overlap** = organisms shared across multiple plants (NOT observational prevalence)
- Focus on shared vulnerabilities: if all plants share same pathogen, one disease outbreak destroys the guild
- **Quadratic penalty**: 2/5 plants = 0.16 penalty, 5/5 plants = 1.00 penalty (6× worse)
- **Second-order effects**: Plant A attracts pests → Plant B attracts predators of those pests = biological control benefit
- Normalize to [-1, +1]: `tanh(raw_score / scaling_factor)`
- Expected discrimination: **40-45× better** (0.032 → 1.25-1.50 difference)

### Two-Component Balanced Scoring

**NEGATIVE FACTORS** (Shared Vulnerabilities) → `negative_risk_score [0, 1]`
1. **Pathogenic Fungi Overlap** (40% of negative) - Shared fungi = disease outbreak risk
2. **Herbivore Overlap** (30% of negative) - Shared pests = pest outbreak risk
3. **Non-Fungal Pathogen Overlap** (30% of negative) - Bacterial/viral shared vulnerabilities

**POSITIVE FACTORS** (Beneficial Interactions) → `positive_benefit_score [0, 1]`
1. **Herbivore Control** (30% of positive) - Biological pest control via:
   - **Specific animal predators** (1.0 weight): Plant B attracts predators of Plant A's specific herbivores
   - **Specific entomopathogenic fungi** (1.0 weight): Plant B hosts fungi that parasitize Plant A's specific herbivores (1,212 insects covered from GloBI)
   - **General entomopathogenic fungi** (0.3 weight): Plant B hosts insect-killing fungi (broad-spectrum)
2. **Pathogen Control** (30% of positive) - Biological disease control via:
   - **Specific antagonist fungi** (1.0 weight): Plant B hosts fungi that attack Plant A's specific pathogens
   - **General mycoparasite fungi** (0.3 weight): Plant B hosts fungal parasites (broad-spectrum)
3. **Shared Beneficial Fungi** (25% of positive) - Positive overlap via:
   - Mycorrhizae (AMF + EMF): nutrient exchange networks
   - Endophytes: disease suppression, stress tolerance
   - Saprotrophs: nutrient cycling, soil health
4. **Taxonomic Diversity** (15% of positive) - Different families = lower transmission risk

**FINAL SCORE**: `guild_score = positive_benefit_score - negative_risk_score`
- Range: [-1, +1]
- -1.0 = Maximum risk, no benefits (catastrophic)
- +1.0 = Maximum benefits, minimal risks (excellent)
- **Equal reachability of both extremes**

See [4.2 Guild Compatibility Framework](4.2_Guild_Compatibility_Framework.md) for complete design.

---

## Production Data Files

### Input Data

- GloBI: `data/stage4/globi_interactions_final_dataset_11680.parquet`
- FungalTraits: `data/fungaltraits/fungaltraits.parquet`
- FunGuild: `data/funguild/funguild.parquet`
- Plants: `model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet`

### Output Data (Production Ready)

**Fungal Guilds**:
- `data/stage4/plant_fungal_guilds_hybrid.parquet` ✓ USE THIS

**Organism Profiles**:
- `data/stage4/plant_organism_profiles.parquet` - herbivores, pathogens, pollinators per plant
- `data/stage4/herbivore_predators.parquet` - animal predator-prey relationships
- `data/stage4/insect_fungal_parasites.parquet` **NEW** - herbivore→fungal parasite relationships (1,212 insects/mites)
- `data/stage4/pathogen_antagonists.parquet` - pathogen→antagonist relationships

**Compatibility Matrix** (Legacy - pairwise only):
- `data/stage4/compatibility_matrix_full.parquet` (Not yet generated)
- ⚠️ Current implementation averages pairs - insufficient for guild scoring

### Scripts

**Fungal Guild Extraction:**
- Production: `src/Stage_4/01_extract_fungal_guilds_hybrid.py` ✓
- FungalTraits only: `src/Stage_4/01b_extract_fungal_guilds.py`
- FunGuild only: `src/Stage_4/01c_extract_fungal_guilds_funguild_primary.py`

**Organism Profiles:**
- `src/Stage_4/01_extract_organism_profiles.py` ✓
- `src/Stage_4/02_build_multitrophic_network.py` ✓
- `src/Stage_4/03_compute_cross_plant_benefits.py` ✓

**Compatibility Matrix** (Legacy):
- `src/Stage_4/04_compute_compatibility_matrix.py` (Pairwise only)

**Guild Scorer** (Planned):
- `src/Stage_4/05_compute_guild_compatibility.py` (Not yet implemented)

---

## Coverage Summary

### Fungal Guilds (11,680 plants)

- Pathogenic: 6,989 plants (59.8%)
- Saprotrophic: 4,650 plants (39.8%)
- Endophytic: 1,877 plants (16.1%)
- Biocontrol: 550 plants (4.7%)
- Mycorrhizal: 388 plants (3.3%)

**Data sources:**
- FungalTraits: 99.4% (expert-curated, 128 mycologists)
- FunGuild: 0.6% (fills gaps, confidence-filtered)

### Organism Interactions (Production)

**Test subset (100 plants):**
- Pollinators: 2% (2 plants) - sparse coverage
- Herbivores: 50% (50 plants)
- Pathogens: 17% (17 plants)

**Production (11,680 plants):**
- Pollinators: 13.3% (1,558 plants)
- Herbivores: 38.4% (4,486 plants)
- Pathogens: 14.5% (1,688 plants)

---

## Implementation Status

### Phase 1: Data Extraction ✓ Complete

- [x] Organism profiles (pollinators, herbivores, pathogens)
- [x] Fungal guilds (hybrid FungalTraits + FunGuild)
- [x] Multi-trophic networks (predator-prey relationships)
- [x] Cross-plant benefits (biological control)

### Phase 2: Guild Scoring Framework ⏳ In Progress

- [x] Identify pairwise averaging failure
- [x] Design guild-level prevalence approach
- [x] Normalized [-1, +1] scoring architecture
- [ ] Implement `05_compute_guild_compatibility.py`
- [ ] Test on bad/good guilds
- [ ] Validate discrimination improvement

### Phase 3: Calibration & Production 📋 Planned

- [ ] Collect ground truth guilds (Three Sisters, All-Solanaceae, etc.)
- [ ] Optimize component weights via regression
- [ ] Cross-validate on test set
- [ ] Production deployment

---

## Key Architectural Decisions

### 1. Guild-Level vs Pairwise Scoring

**Decision**: Use guild-level prevalence metrics, not pairwise averaging

**Rationale**: Pairwise averaging cannot capture:
- Disease cascades (pathogen jumping across guild)
- Guild-wide prevalence (pathogen on 80% vs 20%)
- Network synergies (all plants connected by mycorrhizae)

### 2. Normalized [-1, +1] Scoring

**Decision**: Normalize all components with tanh(), weighted sum

**Rationale**:
- Prevents unbounded scores
- Enables cross-guild comparison
- Clear user interpretation (+1 = excellent, -1 = disaster)

### 3. FungalTraits + FunGuild Hybrid

**Decision**: FungalTraits primary (99.4%), FunGuild fallback (0.6%)

**Rationale**:
- Research-validated (Tanunchai et al. 2022)
- Superior biocontrol classification (138 vs 5 genera)
- Host-specific pathogen data available

### 4. DuckDB for All Data Operations

**Decision**: Use DuckDB for prevalence counting, aggregation, guild analysis

**Rationale**:
- 10-100× faster than pandas
- Efficient parquet handling
- SQL-based guild prevalence queries

---

## Test Guilds for Validation

### Bad Guild: 5 Acacia Species

Plants:
- Acacia koa (`wfo-0000173762`)
- Acacia auriculiformis (`wfo-0000173754`)
- Acacia melanoxylon (`wfo-0000204086`)
- Acacia mangium (`wfo-0000202567`)
- Acacia harpophylla (`wfo-0000186352`)

Characteristics:
- 40 shared pathogenic fungi (Ganoderma, Armillaria, Meliola on 4-5 plants)
- 6 shared herbivores
- Same genus (low diversity)
- Expected score: **-0.75 to -0.85** (disaster)

### Good Guild: Taxonomically Diverse

Plants:
- Abrus precatorius (`wfo-0000178702`) - Fabaceae
- Abies concolor (`wfo-0000511077`) - Pinaceae
- Acacia koa (`wfo-0000173762`) - Fabaceae
- Abutilon grandifolium (`wfo-0000511941`) - Malvaceae
- Abelmoschus moschatus (`wfo-0000510888`) - Malvaceae

Characteristics:
- Only 5 shared pathogenic fungi (low prevalence)
- 12 shared saprotrophic fungi (beneficial)
- Zero shared herbivores
- High taxonomic diversity
- Expected score: **+0.45 to +0.60** (good)

---

## Next Steps

### Immediate: Implement Guild Scorer

1. Create `src/Stage_4/05_compute_guild_compatibility.py`
2. Implement prevalence counting with DuckDB
3. Test on bad/good guilds above
4. Validate 38× discrimination improvement

### Short-term: Calibration

1. Collect 50+ ground truth guilds
2. Optimize component weights
3. Cross-validate
4. Document final weights

### Long-term: Production Integration

1. Replace `guild_builder_prototype.py` with new scorer
2. Add guild score to frontend
3. Performance optimization
4. User documentation

---

## References

**Fungal Classification:**
- Tanunchai et al. (2022) *Microbial Ecology* - https://doi.org/10.1007/s00248-022-01973-2
- FungalTraits: https://doi.org/10.1007/s13225-020-00466-2
- FUNGuild: https://doi.org/10.1016/j.funeco.2015.06.006

**Ecological Framework:**
- Multi-trophic interactions (predator-prey cascades)
- Disease epidemiology (prevalence-based risk)
- Mycorrhizal network ecology

---

**Last Updated**: 2025-11-01
**Status**: Guild scoring framework designed, implementation pending
