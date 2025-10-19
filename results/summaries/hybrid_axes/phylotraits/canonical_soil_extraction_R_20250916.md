Canonical Soil Extraction — Phylotraits Axis R (2025-09-16)

Overview
- Objective: replace the legacy SoilGrids VRT-based extraction with a canonical workflow built on the global 250 m GeoTIFF tiles, and document why this produces cleaner, more reproducible covariates for hybrid R-axis modelling.
- Context: legacy runs combined VRT mosaics with monthly AI features (`phylotraits_cleanedAI_discovery_gpu_withph_quant_aimonth_vrt_20250916`). We re-ran the preferred "pH + root-zone + quantiles" recipe on the canonical GeoTIFF feed (`phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250916`).

Why the GeoTIFF workflow is canonical
1. Native WGS 84 pixels ➜ The global tiles (`*_global_250m.tif`) are already in geographic coordinates, so every sample is a simple nearest-neighbour lookup. The VRT stack sits in the Interrupted Goode Homolosine grid, forcing `terra`/GDAL to reproject and interpolate on every call.
2. Deterministic values ➜ Pre-warping once removes run-to-run jitter. We measured up to 0.6–0.7 pH unit shifts when letting the VRT warp on demand (e.g. VRT=5.2 vs GeoTIFF=6.1 at 12.9646°E, 56.2747°N).
3. Full coverage ➜ The GeoTIFF cache has no HTTP fetch at runtime and no missing tiles, so `_n_valid` counts stay consistent (VRT runs occasionally returned 0 when a tile failed to download).
4. GDAL best practice ➜ GDAL docs recommend pre-warping big mosaics (`docs/txt/gdal-org-en-stable.txt:19780`, `42595`) to avoid constant reprojection and file-handle churn. SoilGrids’ own README explains the VRT format is meant for browsing, whereas the tile folders contain the authoritative pixels (`files.isric.org/soilgrids/latest/data/README.md`).

Canonical extraction pipeline (reproducible steps)
1. **Download & stage tiles** — Use `soil_pipeline_global` (`Makefile`, lines 358–372) or call `src/Stage_1/Data_Extraction/extract_soilgrids_global_250m.R` directly.
2. **Aggregate to species** — `src/Stage_1/Soil/aggregate_soilgrids_species.R` summarises unique coordinates into means, SDs, quantiles (`data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary_global_sg250m_ph_20250916.csv`).
3. **Join with monthly AI** — `src/Stage_1/Soil/augment_bioclim_summary_with_soil.R --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv --soil_summary data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary_global_sg250m_ph_20250916.csv --output data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_phq_sg250m_20250916.csv`.
4. **Run hybrid export + RF/XGB interpretability** — `bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250916 --axes R --folds 10 --x_exp 2 --k_trunc 0 --run_rf true --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02 --clean_out true --bioclim_summary data/.../species_bioclim_summary_with_aimonth_phq_sg250m_20250916.csv` (run from the `AI` conda env so CUDA toolkits are on-path).

GPU execution rationale
- The Python helper `src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py` now mirrors XGBoost's device="cuda" recipe: every booster uses `tree_method="hist"`, `device="cuda"`, and wraps data in an `xgboost.DMatrix`, so training, prediction, SHAP, and PD stay on the GPU.
- A lightweight `sklearn.model_selection.KFold` loop feeds the booster split-by-split, letting us reuse the same z-scored matrix for SHAP/PD exports and emit mean R² / RMSE to `xgb_R_cv_metrics.json` without fallback warnings.
- `hybrid_trait_bioclim_comprehensive.R` calls `set.seed(123)`; therefore `features.csv` is identical across runs. The small R² change (~0.01) reflects different fold assignments, not the GPU model itself.
- Legacy VRT metrics were backed up in `results/summaries/hybrid_axes/phylotraits/backup_gpu_transition/` and `artifacts/stage3rf_hybrid_interpret/backup_gpu_transition/` before switching to the canonical workflow to avoid confusion.


Key artefacts
- Bioclim+soil summary (original canonical): `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_phq_sg250m_20250916.csv` (rows=1008, cols=89).
- Bioclim+soil summary (bilinear warp): `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_phq_sg250m_bilinear_20250917.csv`.
- Feature exports: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_{20250916,20250917}/R_{nopk,pk}/features.csv`.
- XGB metrics: matching `xgb_R_cv_metrics.json` files inside the respective run folders (see table).
- Logs: `artifacts/hybrid_tmux_logs/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250916_20250917_005049/` (original) and `artifacts/hybrid_tmux_logs/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_bilinear_20250917_073210/` (bilinear).

Results — XGB 3000 (GPU, 10-fold CV)
| Dataset & variant | R² ± SD | RMSE ± SD | Notes |
| --- | --- | --- | --- |
| Canonical GeoTIFF, no_pk | 0.164 ± 0.053 | 1.461 ± 0.123 | Features=84 with quantiles/root-zone. |
| Canonical GeoTIFF, pk | 0.225 ± 0.070 | 1.408 ± 0.145 | Adds `p_phylo`; GPU CV now recorded via built-in helper. |
| Canonical GeoTIFF (bilinear), no_pk | 0.156 ± 0.050 | 1.467 ± 0.121 | Uses bilinear-resampled SoilGrids rasters (this run). |
| Canonical GeoTIFF (bilinear), pk | 0.217 ± 0.070 | 1.415 ± 0.146 | Same features + `p_phylo`; GPU-only pipeline. |
| All SoilGrids predictors, no_pk | 0.170 ± 0.055 | 1.457 ± 0.145 | All soil layers (clay, SOC, CEC, etc.); negligible lift over canonical stack. |
| All SoilGrids predictors, pk | 0.229 ± 0.079 | 1.405 ± 0.159 | Slight +0.004 R² vs canonical pk; remains noise-level. |
| Legacy VRT + quantiles, no_pk | 0.194 ± 0.068 | 1.435 ± 0.134 | From `phylotraits_cleanedAI_discovery_gpu_withph_quant_aimonth_vrt_20250916`. |
| Legacy VRT + quantiles, pk | 0.249 ± 0.072 | 1.385 ± 0.145 | Slight edge from on-the-fly smoothing, at cost of reproducibility. |

Interpretation
- Performance gap (~0.02–0.03 R²) persists because the VRT interpolation slightly smooths pixels, which XGB exploits. The GeoTIFF run trades that smoothing for physically correct, reproducible values. The refreshed GPU run now keeps all predictions in CUDA (by routing them through `xgboost.DMatrix`), removing the earlier "fall back to DMatrix" warnings while still documenting CV metrics in `xgb_R_cv_metrics.json`.
- Trait-driven SHAP rankings remain stable: logSM, logH, logLA, and drought/temperature covariates top the list, with root-zone means adding moderate lift.
- Root-zone interactions survive the transition (`ph_rootzone_mean × precip_driest_q`, `ph_rootzone_mean × drought_min`), reinforcing that the canonical pipeline preserves signal quality.

Recommendations
1. Treat the GeoTIFF workflow as the production path; archive the VRT run strictly for historical comparison.
2. If higher R² is required, explore modest smoothing (e.g. pre-warp with bilinear resampling during the one-time conversion) while keeping the pipeline deterministic.
3. A full SoilGrids dump (`conda run -n AI bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_withsoil_all_sg250m_20250917 --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_soilall_sg250m_20250916.csv --axes R --run_rf true --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02 --clean_out true`) confirms that adding every soil variable nudges R² by <0.005; stick to the curated pH stack for clarity.
4. Document downstream scripts so they point at `...with_aimonth_phq_sg250m_20250916.csv` and not the VRT-derived tables.

---

## Canonical Soil Datasets — Encyclopedia Integration (2025-10-05)

### Comprehensive Soil Summary (All Metrics)
**Location**: `data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary.csv`

**Purpose**: Comprehensive soil dataset containing ALL SoilGrids 250m metrics for encyclopedia profile generation and frontend display.

**Coverage**: 654 species with sufficient GBIF occurrence data

**Soil Variables** (6 depth layers: 0-5cm, 5-15cm, 15-30cm, 30-60cm, 60-100cm, 100-200cm):
- **pH (phh2o)**: Soil reaction in water (dimensionless)
- **Organic matter (soc)**: Soil organic carbon (g/kg)
- **Clay content (clay)**: Fine particles < 0.002mm (%)
- **Sand content (sand)**: Coarse particles 0.05-2mm (%)
- **Nutrient capacity (cec)**: Cation exchange capacity (cmol(+)/kg)
- **Nitrogen (nitrogen)**: Total nitrogen content (g/kg)
- **Bulk density (bdod)**: Soil compaction (g/cm³)

**Statistics per variable/depth**: `mean`, `sd`, `p10`, `p50` (median), `p90`, `n_valid`

**Data quality fields**:
- `n_occurrences`: Total GBIF occurrences used
- `n_unique_coords`: Unique coordinate locations sampled
- `has_sufficient_data`: Boolean flag for minimum data threshold

### pH-Only Summary (R Axis Modeling)
**Location**: `data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary_global_sg250m_ph_20250916.csv`

**Purpose**: pH-only subset for R axis XGBoost modeling (cleaner feature space)

**Variables**: Only `phh2o` at 6 depth layers with statistics

### Encyclopedia Profile Integration
The comprehensive soil dataset (`species_soil_summary.csv`) is loaded by:
- **Profile generator**: `src/Stage_8_Encyclopedia/generate_encyclopedia_profiles.py` (line 31)
- **Legacy generator**: `scripts/generate_plant_profile.py` (line 29)

**Profile structure** (`data/encyclopedia_profiles/{slug}.json`):
```json
{
  "soil": {
    "pH": {
      "surface_0_5cm": {"mean": 5.5, "p10": 4.8, "median": 5.6, "p90": 6.4, "sd": 0.8},
      "shallow_5_15cm": {...},
      "medium_15_30cm": {...},
      "deep_30_60cm": {...},
      "very_deep_60_100cm": {...},
      "subsoil_100_200cm": {...}
    },
    "metrics": [
      {
        "key": "organic_matter",
        "label": "Organic matter",
        "units": "g/kg",
        "description": "Stored plant material that keeps soil springy and full of life.",
        "topsoil": {"mean": 43.1},   // Avg of 0-5, 5-15, 15-30 cm
        "subsoil": {"mean": 7.9},    // Avg of 30-60, 60-100 cm
        "deep": {"mean": 5.5}        // Avg of 100-200 cm
      },
      // ... 5 more metrics (clay, sand, cec, nitrogen, bdod)
    ],
    "data_quality": {
      "n_occurrences": 743,
      "n_unique_coords": 676,
      "has_sufficient_data": true
    }
  }
}
```

**Frontend display**: `olier-farm/src/components/SoilConditionsDisplay.tsx`
- pH visualization at multiple depths with color-coded scales
- Soil texture triangle (clay/sand/silt composition)
- Nutrient capacity gauges
- Contextual gardening narratives

### File Lineage
1. **Raw extraction**: `src/Stage_1/Data_Extraction/extract_soilgrids_global_250m.R`
   - Downloads SoilGrids GeoTIFF tiles to `data/soilgrids_250m_global/`
   - Extracts at GBIF occurrence coordinates
   - Outputs: `data/bioclim_extractions_bioclim_first/occurrences/{species}/soil_summary.csv`

2. **Species aggregation**: `src/Stage_1/Soil/aggregate_soilgrids_species.R`
   - Aggregates occurrence-level data to species-level statistics
   - Outputs: `data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary_global_all_20250916.csv`

3. **Symlink to canonical**:
   ```bash
   ln -s species_soil_summary_global_all_20250916.csv species_soil_summary.csv
   ```
   - Creates stable filename for downstream scripts
   - Points to most recent canonical extraction

4. **Encyclopedia profiles**: `src/Stage_8_Encyclopedia/generate_encyclopedia_profiles.py`
   - Reads `species_soil_summary.csv`
   - Formats soil metrics by depth zone (topsoil/subsoil/deep)
   - Embeds in JSON profiles for Firestore upload

### Canonical Dataset Declaration
**For R axis modeling**: Use `species_bioclim_summary_with_aimonth_phq_sg250m_20250916.csv` (pH-only)

**For encyclopedia profiles**: Use `species_soil_summary.csv` → `species_soil_summary_global_all_20250916.csv` (all metrics)

**Rationale**: Encyclopedia profiles need full soil context for gardening recommendations (texture, nutrients, compaction), while XGBoost modeling benefits from focused pH feature space.
