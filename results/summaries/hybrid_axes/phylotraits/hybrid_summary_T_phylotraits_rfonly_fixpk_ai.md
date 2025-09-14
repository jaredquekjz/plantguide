Axis T — Non‑SoilGrid RF‑Only (with monthly AI) — p_k vs no p_k

Metrics (5×3 CV)
- RF‑only (no p_k): 0.524 ± 0.044
- RF‑only (+ p_k): 0.538 ± 0.042
- SEM baseline (traits‑only): 0.216 ± 0.071

Notes
- Temperature benefits moderately from p_k and far exceeds the SEM baseline under RF.
- Monthly aridity indicators (ai_*) are present and meaningful; see interpretability artifacts for PDP curves.

Artifacts
- JSON: artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_fixpk_ai/T/comprehensive_results_T.json
- JSON (pk): artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_fixpk_ai_pk/T/comprehensive_results_T.json
- Interpretability (RF; PDP/ICE/2D/H²): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_fixpk/T_nopk and T_pk

