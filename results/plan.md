# Planting Guides + Ecosystem Vision — Collaboration Plan

Purpose — Produce thousands of planting guides derived from fundamental science (traits → SEM/MAG → copulas → gardening), then expand to ecosystem services, CSR strategies, and a science-based guild builder using GloBI and GBIF. Approach Prof. Bill Shipley with a polished core, a clear vision, and concrete collaboration asks.

## Objectives
- Build credible, reproducible planting guides at scale from trait-based predictions on EIVE axes (L, T, M, R, N).
- Use copulas to handle cross-axis dependence and power joint, multi-criteria suitability decisions.
- Expand to ecosystem service tags, CSR (Grime) tendencies, and guild recommendations informed by interactions (GloBI) and occurrences (GBIF).
- Invite Prof. Shipley as statistical collaborator to sharpen methodology and guide the next phase.

## Near-Term (1–2 weeks)
- Tidy-Up Targets (before outreach)
  - Tag a clean Run 8 snapshot: equations, residual districts (mag_copulas.json), diagnostics (tau/tails/CV log-copula), Stage 6 outputs.
  - One-pagers: (a) Model summary (DAG/MAG, forms, composite logic, fit); (b) Copulas addendum (pairs, adequacy, value); (c) Gardening integration with 2 sample species.
  - Repro guide: 3 commands (export → copulas → Stage 6).
  - Caveats/next: modest R² axes (e.g., R), why joint modeling mitigates risk, and clear items to improve with Shipley.
- Batch Guides MVP (Stage 7)
  - Script: `src/Stage_7_Guides/build_guides.R` to render Markdown per species under `results/guides/`.
  - Content per species: axis predictions + bins + confidence + borderline; joint scenario table (SunnyNeutral, ShadeWetAcidic, etc.); short “care profile”.
  - Make target: `make guides` to generate in batches.
- Showcase Pack for Shipley
  - 2–3 page brief (DAG, equations, d-sep, Run 7 metrics, copula diagnostics, 2 sample guides).
  - Mini ablation: independence vs copula joint log-score on a tiny holdout slice.

## Mid-Term (3–6 weeks)
- Ecosystem Services v1 (rule-based, transparent)
  - Pollinator support, water regulation/soil stabilization, nutrient enrichment, shade provision — derived from axes/traits with uncertainty notes.
- CSR Strategies (Grime)
  - Map LES/SIZE and disturbance/stress proxies to C/S/R lean with probabilities or confidence tiers.
- GloBI + GBIF Integration (data plumbing)
  - Cached ingestion scripts for occurrences (GBIF) and interactions (GloBI); presence summaries and interaction panels in guides.
- Guild Builder (Phase 2)
  - Compatibility engine: hard axis filters + joint constraints; soft scoring for LES/SIZE complementarity + GloBI edges.
  - Preset multi-objective profiles (Pollinator Patch, Wet Border, Shade Guild).

## Outreach Packet (lean and compelling)
- Cover note (1 paragraph): the problem, your solution, why him.
- “Shipley Brief” (2–3 pages):
  - Objective: traits → EIVE via SEM/MAG → copulas → multi-criteria decisions.
  - Diagram: the DAG and shared submodels (`LES ~ SIZE + logSSD`; `SIZE ~ logSSD`).
  - Final forms: per-axis equations and rationale.
  - Fit + diagnostics: R² by axis; copula pairs (ρ) and adequacy (tau, tails, CV log-copula).
  - Practical layer: Stage 6 joint suitability examples (2 scenarios × 2 species).
  - Open questions: where his expertise sharpens the system immediately (see below).
  - Collaboration ask: scope, deliverables, timeline, recognition/compensation.
- Appendix (links): repo paths to scripts, results, and how to run.

## Collaboration Scope — What to Ask Shipley To Shape First
- Copula families and districts: when Gaussian suffices vs t/Clayton/Gumbel; criteria for family selection; district size limits.
- Measurement model: LES composite vs latent scoring in lavaan and alignment with theory.
- Multigroup structure: if/when to model family/woodiness/mycorrhiza; interpretability vs complexity.
- Fit testing and claims: best practice for d-sep with dependent errors; preferred cross-checks.
- External robustness: minimal design for regional/phylogenetic holdout; sign stability.
- Engagement shape:
  - Phase 1 (2–3 sessions): model review + recommendations; short memo.
  - Phase 2 (4–6 weeks): targeted upgrades (families, multigroup, measurement alignment), milestone demo.
  - Recognition: co-authorship on a methods note; acknowledgments in guides; consulting rate per session.

## Vision Roadmap (expanded)
- Thousands of explainable guides built from first principles (traits → EIVE → garden requirements).
- Layered data for context and compatibility (GBIF presence, GloBI interactions).
- Science-based guild builder: copula-aware joint suitability + interaction-aware sets, with rationale.

## Data & Engineering Practices
- Formats
  - Predictions: `results/mag_predictions_*.csv`
  - Joint: `results/garden_joint_summary.csv` and per-species joint columns in `results/garden_requirements_*.csv`
  - Guides: `results/guides/<species>.md`
- Templating: RMarkdown/whisker; simple, auditable templates.
- Performance: batch rendering; cache joint calculations; `--species_filter` for quick runs.
- Repro (current core):
  - Export Run 8 equations: `Rscript src/Stage_4_SEM_Analysis/export_mag_artifacts.R --input_csv artifacts/model_data_complete_case_with_myco.csv --out_dir results --version Run8`
  - Fit copulas: `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise_copula.R --input_csv artifacts/model_data_complete_case_with_myco.csv --out_dir results --auto_detect_districts true --rho_min 0.15 --fdr_q 0.05 --copulas gaussian --select_by AIC`
  - Joint presets: `Rscript src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R --predictions_csv results/mag_predictions_no_eive.csv --copulas_json results/mag_copulas.json --metrics_dir artifacts/stage4_sem_piecewise_run7 --presets_csv results/garden_joint_presets_defaults.csv --nsim 20000 --summary_csv results/garden_joint_summary.csv`

## Sample Email (draft)
Subject: Traits → SEM/MAG → Copulas → Gardening: collaboration invitation

Dear Prof. Shipley,

I’ve built a working pipeline that starts from plant traits, fits a MAG/SEM structure aligned with your framework, models residual dependencies with copulas, and turns the results into multi‑criteria gardening recommendations with joint probabilities. I’d be honored to get your guidance to sharpen it.

I’ve attached a 2–3 page brief with the DAG, equations, diagnostics, and a couple of example outputs. If this looks interesting, I’d love to engage you as a consultant to review the model choices (copula families, measurement vs composites, multigroup structure) and help chart the next phase (ecosystem services, CSR strategies, and a guild builder using GloBI/GBIF).

Would you be open to a 30‑minute call next week? I’m happy to work around your schedule and can share a minimal repro bundle if you’d like to poke the code.

Thank you for considering — your work directly inspired this.

Warm regards,
[Your Name]
[Contact]

## Open Questions (for Shipley)
- Which dependence structures matter most here — tails, asymmetry — and how to detect them reliably?
- When is a latent LES measurement warranted vs composite scores for predictive stability?
- What’s a minimal, robust multigroup design for this dataset (family/woodiness/mycorrhiza)?
- Best practice to present d‑sep with dependent errors and avoid over-claiming.
- How to structure an external/phylogenetic holdout that is meaningful yet feasible.

## Next Actions (checklist)
- [ ] Finalize Run 8 snapshot; ensure `results/mag_copulas.json`, diagnostics, and Stage 6 outputs are clean.
- [ ] Implement `src/Stage_7_Guides/build_guides.R` and generate 5 sample guides.
- [ ] Draft and export the 2–3 page “Shipley Brief”.
- [ ] Send outreach email with the brief and links to the reproducible bundle.
- [ ] Schedule initial consultation; align on Phase 1 scope and deliverables.

