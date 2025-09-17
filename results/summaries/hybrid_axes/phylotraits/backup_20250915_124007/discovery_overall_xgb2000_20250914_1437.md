Discovery — Overall (2000 trees; lr=0.03) — 20250914_1437

XGB CV R² (no_pk → pk)
- T: 0.544±0.051 → 0.581±0.039
- M: 0.257±0.090 → 0.376±0.084
- L: 0.362±0.085 → 0.358±0.068
- N: 0.446±0.043 → 0.488±0.058
- R: 0.130±0.056 → 0.180±0.092

Repro (all axes)
- `scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu --trait_csv artifacts/model_data_bioclim_subset.csv --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv --axes T,M,L,N,R --run_rf false --run_xgb true --xgb_gpu true --xgb_estimators 2000 --xgb_lr 0.03`