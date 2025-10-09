# CSR Rule Verification – Section 2.1

## Scope
- Cross-checked `CSR_methodology_and_ecosystem_services.md` (`2.1 Core Mechanistic Pathways` tables and revised rules) against Bill Shipley’s note `Ecosystem properties and services and CSR strategies.mmd` (`Net primary production` through `Soil erosion`) and the supporting diagrams `NPP.png`, `Litter.png`, `Nutrient.png`, `atmosphere.png`.

## Alignment Review
| Service | Shipley guidance (text + diagram) | Rule outcome (doc + code) | Status |
| --- | --- | --- | --- |
| **NPP** | C highest, R intermediate, S low (`CSR_methodology_and_ecosystem_services.md:146-158`; `Ecosystem properties and services and CSR strategies.mmd:41-51`; `NPP.png`) | Updated rule removes `High` for R-dominant stands; aligns ranges with guidance (`CSR_methodology_and_ecosystem_services.md:487-491`; `compute_rule_based_ecoservices.py:41-48`) | ✅ Updated |
| **Decomposition** | C and R high, S low (`CSR_methodology_and_ecosystem_services.md:162-172`; `Litter.png`) | Rule already mirrored pattern; no change (`CSR_methodology_and_ecosystem_services.md:492-496`; `compute_rule_based_ecoservices.py:51-58`) | ✅ Matches |
| **Nutrient Cycling** | Same as decomposition (`CSR_methodology_and_ecosystem_services.md:192-201`; `Nutrient.png`, left triangle) | Reuses decomposition rule; consistent (`CSR_methodology_and_ecosystem_services.md:497-498`; `compute_rule_based_ecoservices.py:61-62`) | ✅ Matches |
| **Nutrient Retention** | C and S minimise loss, R highest loss (`CSR_methodology_and_ecosystem_services.md:204-214`; `Nutrient.png`, right triangle) | Rule retains high ratings for C/S, low for R (`CSR_methodology_and_ecosystem_services.md:499-503`; `compute_rule_based_ecoservices.py:65-72`) | ✅ Matches |
| **Nutrient Loss** | Low for C & S, high for R (`Ecosystem properties and services and CSR strategies.mmd:77-84`; `Nutrient.png`, right triangle) | Added `S ≥ 50` → `Low` to capture S-end protection while leaving C thresholds intact (`CSR_methodology_and_ecosystem_services.md:504-509`; `compute_rule_based_ecoservices.py:75-86`) | ✅ Updated |
| **Carbon Storage — Biomass** | Living biomass highest at C, moderate at S, low at R (`CSR_methodology_and_ecosystem_services.md:175-183`; `Ecosystem properties and services and CSR strategies.mmd:63-71`) | Replaced pure `rate_band(C)` with mixed C/S thresholds so S-dominant stands return at least `Moderate` (doc/code refs as above: `CSR_methodology_and_ecosystem_services.md:510-515`; `compute_rule_based_ecoservices.py:89-98`) | ✅ Updated |
| **Carbon Storage — Recalcitrant** | S controls recalcitrant pools (`CSR_methodology_and_ecosystem_services.md:185-188`; `atmosphere.png`) | `rate_band(S)` already consistent (`CSR_methodology_and_ecosystem_services.md:516-517`; `compute_rule_based_ecoservices.py:101-102`) | ✅ Matches |
| **Carbon Storage — Total** | High storage at high C and/or S (`CSR_methodology_and_ecosystem_services.md:185-188`; `atmosphere.png`) | Rule already rewarded either high C or S and very low when both low (`CSR_methodology_and_ecosystem_services.md:518-523`; `compute_rule_based_ecoservices.py:105-114`) | ✅ Matches |
| **Erosion Protection** | C best, S intermediate, R poor (`CSR_methodology_and_ecosystem_services.md:218-227`; `Ecosystem properties and services and CSR strategies.mmd:86-88`) | Removed blanket `S ≥ 50 → High`, added `R ≥ 60 → Very Low`; keeps S-dominant stands at `Moderate` (`CSR_methodology_and_ecosystem_services.md:524-529`; `compute_rule_based_ecoservices.py:117-126`) | ✅ Updated |

## Code & Documentation Updates
- Revised rule logic in `src/Stage_3_CSR/compute_rule_based_ecoservices.py:41-126` to reflect Shipley’s rankings.
- Synchronized narrative rules in `CSR_methodology_and_ecosystem_services.md:486-529`.

## Validation
- Ran targeted Python checks on representative CSR mixes to confirm new rules return expected ordinal ratings (command: `python - <<'PY' ...`). Outputs confirm C-dominant stands score highest productivity/storage, R-dominant score highest loss/lowest protection, and S-dominant shift to moderate storage & low loss per Shipley guidance.
