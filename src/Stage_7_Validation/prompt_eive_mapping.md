# Stage 7 – Profile → EIVE Descriptor Mapping (0–10 Aligned)

You translate a plant’s Stage 7 profile JSON into axis‑specific qualitative descriptors that align with the EIVE 0–10 scale. Do not invent values > 10. Use deterministic rules below. Prefer numeric evidence over vague text. Prefer “prefers/optimal” over “tolerates”.

Input you receive
- EIVE expectation for context (label + score), and
- The profile JSON with fields observed in our data:
  - environmental_requirements.requirements.light_requirements[{name, min_hours_direct_sunlight_per_day, max_hours_direct_sunlight_per_day, condition}]
  - environmental_requirements.tolerances.shade.value
  - environmental_requirements.requirements.water_requirement{value, min_yearly_precipitation_mm, max_yearly_precipitation_mm}
  - environmental_requirements.tolerances.drought.value
  - environmental_requirements.requirements.ph_range{min,max,qualitative_comments}
  - environmental_requirements.requirements.soil_types[{name}], soil_qualitative_comments
  - climate_requirements.requirements.optimal_temperature_range{min,max,qualitative_comments}
  - climate_requirements.requirements.hardiness_zone_range{min,max,qualitative_comments}
  - climate_requirements.requirements.suitable_koppen_zones{value[],qualitative_comments}
  - climate_requirements.requirements.microclimate_preferences{value}
  - climate_requirements.tolerances.heat{qualitative_comments}
  - climate_requirements.requirements.frost_sensitivity{value|qualitative_comments}

Axis‑specific mapping rules (0–10 aligned)
- Light (L)
  - If both hours exist: mean_hours = mean(min,max).
    - mean_hours ≥ 6 → full sun (high L bin).
    - 3–6 → part sun/part shade (mid L bin).
    - <3 → shade (low L bin).
  - Else choose strongest categorical: full sun > part shade > shade tolerant/deep shade.

- Moisture (M) [strictly 0–10]
  - Categorical strength (descending):
    - aquatic/submerged/emergent/shallow water/standing water → top bins (≈ 8.5–10.0).
    - waterlogged/bog/marsh/wet meadow/saturated → high (≈ 7.0–8.5).
    - consistently moist/high humidity/moist valleys → mid‑high (≈ 5.5–7.0).
    - fresh/mesic/well‑drained → mid (≈ 4.0–5.5).
    - dry/drought tolerant/sandy/free‑draining → low (≈ 2.0–4.0).
  - Numeric nudges:
    - precip_max > 1400 → push up 1 tier; precip_max < 750 → push down 1 tier.

- Reaction / pH (R)
  - Numeric precedence if ph_range present:
    - max ≤ 6.3 → acidic (low R bins, ≈ 3–4).
    - 6.4–7.2 overlaps → neutral/slightly acidic (mid R, ≈ 5–6).
    - min ≥ 7.5 → alkaline/calcareous (high R, ≥ 7).
  - Else tokens: acid/peat → acidic; chalk/lime/calcareous/base‑rich → alkaline.

- Nutrients (N)
  - Tokens only:
    - rich/fertile/eutrophic/compost heavy/manure/nitrophilous → high N (≥ 7).
    - intermediate/average → mid N (5–6).
    - poor/lean/oligotrophic/“avoid rich soils” → low N (≤ 3).

- Temperature (T)
  - Prefer hardiness zones:
    - zone_min ≤ 3 → low T (≤ 3).
    - zone_min 4–6 → mid T (≈ 4–6).
    - zone_min ≥ 7 → high T (≥ 7).
  - Else Köppen:
    - Cfb/Dfb → cool temperate (≈ 3–5); Csa/Csb → Mediterranean (≥ 7).
  - Else tokens: cool/montane/subalpine/alpine → low/mid T; warm/mediterranean/submediterranean/heat tolerant → high T.

Output JSON schema (per axis)
Return a compact mapping for each axis using only the fields below.

{
  "axis": "L|M|R|N|T",
  "normalized_label": "full sun|part shade|shade|... (see rules)",
  "evidence_type": "numeric|categorical",
  "key_values": { "hours": float?, "pH_min": float?, "pH_max": float?, "precip_min": float?, "precip_max": float?, "zone_min": int?, "zone_max": int?, "koppen": ["..."]? },
  "quotes": ["verbatim snippets used"],
  "notes": "one‑line rationale"
}

General requirements
- Never propose values > 10 for any axis; you output qualitative labels only.
- Use numeric when present; if numeric and categorical disagree, numeric wins.
- Prefer adult/lifecycle‑wide statements over seedlings‑only or exceptional microclimates.
