# Stage 4: Guild Builder Documentation

**Updated**: 2025-11-01
**Status**: Production Ready

---

## Document Organization

### Core Implementation

**[4.5 Fungal Guild Classification - FINAL](4.5_Fungal_Guild_Classification_Final.md)** ⭐ **START HERE**
- Research-validated hybrid approach (FungalTraits + FunGuild)
- Complete implementation details
- Production results (11,680 plants)
- Comparison of all approaches
- Recommendation: Use hybrid approach

### Foundation & Design

**[4.1 GloBI Data Structure Analysis](4.1_GloBI_Data_Structure_Analysis.md)**
- GloBI database exploration
- Interaction type taxonomy
- Data quality assessment
- Coverage analysis

**[4.2 Implementation Plan - DuckDB](4.2_Implementation_Plan_DuckDB.md)**
- DuckDB architecture decision
- Performance optimization strategy
- Query design patterns
- Parquet workflows

**[4.3 Guild Builder Design](4.3_Guild_Builder_Design.md)**
- Mathematical compatibility framework
- Multi-trophic network analysis
- Interaction categories and scoring
- Component weights

### Supporting Analysis

**[FungalTraits Dataset Evaluation](FungalTraits_Dataset_Evaluation.md)**
- Database structure and coverage
- Guild classification methodology
- Comparison with FunGuild
- Data quality notes

**[Guild Builder Network Effects Framework](Guild_Builder_Network_Effects_Framework.md)**
- Synergy multiplier design (1.10× to 1.30×)
- Complete fungal network effects
- Multi-guild interactions
- Evidence-based weighting

---

## Quick Reference

### Production Files

**Input Data**:
- GloBI: `data/stage4/globi_interactions_final_dataset_11680.parquet`
- FungalTraits: `data/fungaltraits/fungaltraits.parquet`
- FunGuild: `data/funguild/funguild.parquet`
- Plants: `model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet`

**Output Data** (USE THIS):
- **Fungal Guilds**: `data/stage4/plant_fungal_guilds_hybrid.parquet`

**Scripts**:
- **Production**: `src/Stage_4/01_extract_fungal_guilds_hybrid.py`
- FungalTraits only: `src/Stage_4/01b_extract_fungal_guilds.py`
- FunGuild only: `src/Stage_4/01c_extract_fungal_guilds_funguild_primary.py`

### Coverage Summary

**11,680 plants processed:**
- Pathogenic: 6,989 plants (59.8%)
- Saprotrophic: 4,650 plants (39.8%)
- Endophytic: 1,877 plants (16.1%)
- Biocontrol: 550 plants (4.7%)
- Mycorrhizal: 388 plants (3.3%)

**Data sources:**
- FungalTraits: 99.4% (expert-curated, 128 mycologists)
- FunGuild: 0.6% (fills gaps, confidence-filtered)

---

## Key Decisions

### 1. Hybrid Approach Selected

**Why**: Research-validated (Tanunchai et al. 2022), best overall coverage, superior biocontrol classification

### 2. FungalTraits as Primary

**Why**: Expert-curated, host-specific pathogen info, 138 biocontrol genera vs 5 in FunGuild

### 3. FunGuild Confidence Filtering

**Why**: Research shows "Possible" confidence should be excluded (split ecologies, conflicts)

### 4. Multi-Guild Support

**Why**: Fungi have multiple ecological roles (e.g., Fusarium: pathogen + endophyte)

---

## Next Steps

### Integration with Guild Builder

Update compatibility matrix script to load hybrid results:
```python
fungal_guilds = pd.read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet')
```

Apply 8 fungal components (9-16):
- Pathogenic fungi (negative)
- Mycorrhizal fungi (positive)
- Biocontrol fungi (positive)
- Endophytic fungi (positive)
- Saprotrophic fungi (positive)
- Trichoderma multi-guild (positive)
- Beauveria/Metarhizium enhanced (positive)
- Synergy multiplier (1.10× to 1.30×)

### Future Enhancements

1. Species-level matching (FunGuild has 34% species records)
2. Confidence weighting for FunGuild matches
3. Database version tracking and updates
4. Cross-validation with published associations

---

## References

**Primary**:
Tanunchai et al. (2022) Microbial Ecology
https://doi.org/10.1007/s00248-022-01973-2

**Databases**:
- FungalTraits: https://doi.org/10.1007/s13225-020-00466-2
- FUNGuild: https://doi.org/10.1016/j.funeco.2015.06.006

---

**Last Updated**: 2025-11-01
