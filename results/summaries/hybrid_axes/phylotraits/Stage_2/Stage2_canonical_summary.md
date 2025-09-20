# Stage 2 — Canonical Results (All Axes)

Date: 2025-09-20

## Canonical Runs
- Models: pwSEM (baseline and +phylo), GAM (axis‑specific canonical spec)
- CV: Random 10‑fold (stratified), LOSO (species), Spatial (500 km blocks)

## Summary Table (R² ± sd)

| Axis | pwSEM | pwSEM+phylo | GAM 10‑fold | GAM LOSO | GAM Spatial | Best |
|------|-------|-------------|-------------|----------|-------------|------|
| T | 0.546±0.085 | – | 0.578±0.124 | 0.563±0.038 | 0.554±0.037 | GAM |
| M | 0.359±0.118 | 0.399±0.115 | 0.373±0.115 | 0.394±0.045 | 0.381±0.050 | pwSEM+phylo |
| L | 0.324±0.098 | – | 0.425±0.074 | 0.435±0.030 | 0.410±0.029 | GAM |
| N | 0.444±0.080 | 0.472±0.076 | 0.466±0.079 | 0.459±0.029 | 0.453±0.032 | pwSEM+phylo |
| R | 0.166±0.092 | 0.222±0.077 | 0.237±0.121 | 0.243±0.042 | 0.215±0.040 | pwSEM+phylo |

Notes
- GAM random CV from `results/aic_selection_*/summary.csv`
- LOSO/spatial from `results/aic_selection_*/gam_*_cv_metrics_{loso,spatial}.json`
- pwSEM figures from `all_axes_stage2_complete.md`

## Per‑Axis Canonical Files
- T: `results/summaries/hybrid_axes/phylotraits/Stage_2/T_axis_canonical.md`
- M: `results/summaries/hybrid_axes/phylotraits/Stage_2/M_axis_canonical.md`
- L: `results/summaries/hybrid_axes/phylotraits/Stage_2/L_axis_canonical.md`
- N: `results/summaries/hybrid_axes/phylotraits/Stage_2/N_axis_canonical.md`
- R: `results/summaries/hybrid_axes/phylotraits/Stage_2/R_axis_canonical.md`

## Repro (Makefile targets)
- All axes (AIC/GAM): `make -f Makefile.stage2_structured_regression aic_ALL`
- Axis‑specific (example T): `make -f Makefile.stage2_structured_regression aic_T`
- pwSEM baselines: `make -f Makefile.stage2_structured_regression pwsem_ALL` and `pwsem_phylo_ALL`

