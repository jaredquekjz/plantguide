Axis M — Non‑SoilGrid RF‑Only (with monthly AI) — p_k vs no p_k

Metrics (5×3 CV)
- RF‑only (no p_k): 0.227 ± 0.071
- RF‑only (+ p_k): 0.317 ± 0.066
- SEM baseline (traits‑only): 0.357 ± 0.121

Notes
- p_k substantially improves Moisture relative to no p_k, but SEM still leads — indicating structured trait–climate combinations capture signal beyond RF-only.
- Monthly AI dryness features are now included; several (ai_roll3_min, ai_month_min, ai_month_p10) rank highly in RF importance and display clear PDP slopes.

Artifacts
- JSON: artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_fixpk_ai/M/comprehensive_results_M.json
- JSON (pk): artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_fixpk_ai_pk/M/comprehensive_results_M.json
- Interpretability (RF; PDP/ICE/2D/H²): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_fixpk/M_nopk and M_pk

