# Stage 2 — SEM Run 4: lavaan Co‑adapted (reference)

Date: 2025-08-22

Run 4 was a lavaan‑focused run introducing co‑adaptation (LES↔SIZE, LES↔logSSD) while keeping Mycorrhiza grouping and the composite‑proxy CV. There is no pwSEM rerun for this stage. This file simply replicates and points to the original Run 4 summary.

Primary summary (canonical)
- Path: `results/summaries/summarypiecewise/stage_sem_run4_summary.md`
- Contents: lavaan multi‑group fits with co‑adapted LES; CV via composite proxies; n≥30 per myco group; seed=42; 10×5 CV.

Key points carried over
- Co‑adaptation improved information criteria (ΔAIC/ΔBIC markedly lower vs Run 3) for L/M/R/N despite modest absolute fit indices.
- Mycorrhiza grouping preserved; analyses filtered to groups with n≥30 for stable estimation.
- Piecewise models were unchanged from Run 3 in this stage; latent SEM (lavaan) is the focus.

Phylogenetic robustness
- As documented in the original Run 4 summary, phylogenetic GLS checks were applied to Run 3 forms and indicate robustness of core directions and practical significance. No additional reruns are needed here.

Notes
- For continuity from Run 3 (pwSEM), treat Run 4 as a lavaan reference checkpoint rather than a pwSEM stage.
- If consolidated metrics are needed, use the lavaan exports under `artifacts/stage4_sem_lavaan_run4/` and the main CSV at `artifacts/stage4_sem_summary_run4/sem_metrics_summary_main.csv` as listed in the canonical summary.

This is a reference entry; see the canonical file for full details.
