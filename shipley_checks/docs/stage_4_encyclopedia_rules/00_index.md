# Encyclopedia Rules Index

Reference documentation for the Stage 4 Rust encyclopedia generator.

## Engine Section Mapping

| Engine Module | Reference Document | Data Sources |
|---------------|-------------------|--------------|
| `s1_identity_card.rs` | [s1_identity_card.md](s1_identity_card.md) | WFO taxonomy, TRY traits, Phase 0 |
| `s2_growing_requirements.rs` | [s2_growing_requirements.md](s2_growing_requirements.md) | WorldClim, SoilGrids, EIVE |
| `s3_maintenance_profile.rs` | [s3_maintenance_profile.md](s3_maintenance_profile.md) | CSR scores |
| `s4_ecosystem_services.rs` | [s4_ecosystem_services.md](s4_ecosystem_services.md) | Pre-calculated ratings |
| `s5_biological_interactions.rs` | [s5_biological_interactions.md](s5_biological_interactions.md) | GloBI organisms |
| `s6_companion_planting.rs` | [s6_companion_planting.md](s6_companion_planting.md) | Guild synergies |

## Scientific Foundation

### Two Complementary Occurrence-Based Perspectives

The encyclopedia integrates two complementary data sources that both describe **where plants naturally occur**:

**Perspective A: Environmental Envelope (WorldClim/SoilGrids)**
- Source: ~145 million georeferenced GBIF occurrence records
- Output: q05/q50/q95 percentiles (tolerance limits)
- Use: "Will this plant survive in my conditions?"

**Perspective B: EIVE (Ecological Indicator Values for Europe)**
- Source: 31 regional phytosociological systems harmonised to 0-10 scale
- Output: Niche position and width for L, M, T, R, N
- Use: "Will this plant thrive and compete well?"

### Triangulation Principle

When both sources agree, confidence is high. When they diverge, the plant survives broadly but performs best in preferred conditions.

| Question | Use This Source |
|----------|-----------------|
| "Will it survive?" | Environmental envelope (q05/q95) |
| "Will it thrive?" | EIVE niche position |
| "Actual temp/rainfall values?" | Environmental envelope |
| "Shade or sun?" | EIVE-L |
| "Watering needs?" | EIVE-M + precipitation envelope |

### Our Validation (Stage 2 XGBoost)

| EIVE Axis | R² | Accuracy ±1 |
|-----------|-----|-------------|
| T (Temperature) | 0.806 | 93.5% |
| M (Moisture) | 0.661 | 89.3% |
| L (Light) | 0.587 | 87.3% |
| N (Nitrogen) | 0.610 | 80.7% |
| R (Reaction) | 0.437 | 81.2% |

## Dataset Columns Reference

Key columns from Phase 0 parquet (`bill_with_csr_ecoservices_11711_*.parquet`):

**Identity**: `wfo_taxon_id`, `wfo_scientific_name`, `family`, `genus`

**Traits**: `height_m`, `try_growth_form`, `try_leaf_phenology`, `try_woodiness`, `life_form_simple`

**EIVE**: `EIVEres-L`, `EIVEres-M`, `EIVEres-T`, `EIVEres-R`, `EIVEres-N` (plus `_source`, `_imputed` variants)

**CSR**: `C`, `S`, `R`

**Climate**: `wc2.1_30s_bio_*`, `TNn_*`, `TXx_*`, `CDD_*`, `SU_*`, `TR_*`, etc.

**Soil**: `phh2o_0_5cm_*`, `clay_0_5cm_*`, `sand_0_5cm_*`, `cec_0_5cm_*`, `soc_0_5cm_*`, `nitrogen_0_5cm_*`, `bdod_0_5cm_*`

**Ecosystem Services**: `carbon_total_rating`, `nitrogen_fixation_rating`, `erosion_protection_rating`, `npp_rating`, `decomposition_rating`, `nutrient_cycling_rating`, etc. (all with `_confidence` variants)

## References

- Dengler J, et al. (2023) EIVE 1.0 - Ellenberg-type indicator values for European vascular plants
- Pierce S, et al. (2017) A global method for calculating plant CSR ecological strategies
- WorldClim 2.1, SoilGrids 2.0, GloBI
