Discovery — Overall (T,M,L,N,R) — RF + XGB (GPU) — 20250914_1413

CV Metrics (XGB)
- T: no_pk R²=0.542±0.063, pk R²=0.575±0.043
- M: no_pk R²=0.236±0.085, pk R²=0.376±0.084
- L: no_pk R²=0.353±0.094, pk R²=0.358±0.068
- N: no_pk R²=0.444±0.045, pk R²=0.488±0.058
- R: no_pk R²=0.111±0.077, pk R²=0.180±0.092

Repro (one‑shot Stage 1)
- 4 axes (T,M,L,N): `conda run -n AI make stage1_discovery DISC_LABEL=phylotraits_cleanedAI_discovery_gpu DISC_AXES=T,M,L,N DISC_FOLDS=10 DISC_X_EXP=2 DISC_KTRUNC=0 DISC_XGB_GPU=true`
- 5 axes (T,M,L,N,R): `conda run -n AI make stage1_discovery_5axes DISC_LABEL=phylotraits_cleanedAI_discovery_gpu DISC_FOLDS=10 DISC_X_EXP=2 DISC_KTRUNC=0 DISC_XGB_GPU=true`

Where to look
- Root: artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/<AXIS>_{nopk,pk}
- Logs: artifacts/hybrid_tmux_logs/{label}_<timestamp>