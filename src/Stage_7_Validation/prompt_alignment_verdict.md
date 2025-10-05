# Stage 7 – Alignment Verdict (Quantitative + Categorical)

You compare EIVE expectations (0–10 continuous; never > 10) with a Stage 7 plant profile. For each axis {L, M, R, N, T} you must extract evidence, compute quantitative scores, and output both numeric ratings and categorical labels.

Evidence extraction (per axis)
- support_count: number of clauses that clearly support the expected label.
- contradict_count: number of clauses that clearly contradict the expected label.
- strength: strong|moderate|weak
  - strong = any aligned numeric evidence (hours of sun, pH, precipitation, hardiness zones, Köppen, temperatures).
  - moderate = explicit categorical class (e.g., “full sun”, “calcareous”, “shallow water”).
  - weak = vague, unqualified text without numbers.
- applicability: general|limited
  - general = adult/lifecycle-wide; limited = seedlings-only, exceptional microclimate, rare/edge conditions.
- numeric_advantage: true|false
  - true if ≥1 aligned numeric item supports the expectation AND no stronger numeric contradicts it.
- prefer_vs_tolerate_bias: prefer|neutral|tolerate
  - prefer if “prefers/optimal” statements back the expected label and opposing text is mostly “tolerates”.
- has_conflict: true|false
  - true if there is both strong support and strong contradiction present.

Quantitative scoring (deterministic)
- strength_weight: map strength to a numeric weight
  - strong = 1.0; moderate = 0.6; weak = 0.3
- support_weighted, contradict_weighted
  - support_weighted = support_count × strength_weight
  - contradict_weighted = contradict_count × strength_weight
- specificity_score ∈ [0, 2]
  - 2 if numeric evidence used; 1 if explicit categorical class; 0 otherwise.
- reliability_score ∈ [0, 1]
  - base = (specificity_score) / 2  // applicability score removed
  - if numeric_advantage: base += 0.2
  - if has_conflict: base -= 0.2
  - reliability_score = round(clamp(base, 0, 1), 3)
  - Define clamp(x, a, b) = min(max(x, a), b)
- verdict_numeric ∈ {1.0, 0.5, 0.0, null}
  - map(match)=1.0, map(partial)=0.5, map(conflict)=0.0, map(insufficient)=null
- confidence ∈ [0, 1]
  - confidence = reliability_score  // numeric agreement removed

Verdict + reliability labels (categorical)
- Choose exactly one verdict in {match|partial|conflict|insufficient} using the qualitative rules below.
- Choose one reliability label in {High|Medium|Low|Conflict|Unknown} using the rubric.

Verdict rules (deterministic order)
- No evidence
  - If support_count = 0 AND contradict_count = 0 → verdict=insufficient.
- Clear Match
  - If support_count ≥ 1 AND contradict_count = 0 AND strength=strong AND applicability=general → verdict=match.
- Strong Match
  - If support_count ≥ 1 AND contradict_count = 0 AND (strength=strong OR (strength=moderate AND applicability=general)) → verdict=match.
- Provisional Match
  - If support_count ≥ 1 AND contradict_count = 0 AND strength=weak → verdict=match.
- Mixed, Favor Expectation
  - If support_count ≥ 1 AND contradict_count ≥ 1 AND (numeric_advantage=true OR prefer_vs_tolerate_bias=prefer) → verdict=match.
- Mixed, Ambiguous
  - If support_count ≥ 1 AND contradict_count ≥ 1 AND numeric_advantage=false AND prefer_vs_tolerate_bias≠prefer → verdict=partial.
- Clear Conflict
  - If support_count = 0 AND contradict_count ≥ 1 AND (strength=strong OR contradict_count ≥ 2 with moderate phrases) → verdict=conflict.
- Weak Conflict
  - If support_count = 0 AND contradict_count ≥ 1 AND strength=weak → verdict=conflict.

Reliability label rules
- High:
  - verdict==match AND reliability_score ≥ 0.75 AND has_conflict==false
- Medium:
  - (verdict==match AND 0.5 ≤ reliability_score < 0.75) OR (verdict==partial AND reliability_score ≥ 0.5)
- Low:
  - (verdict in {match, partial} AND reliability_score < 0.5)
- Conflict:
  - verdict==conflict AND (has_conflict==true)
- Unknown:
  - verdict==insufficient

Scale reminders and per‑axis classification (0–10 only)
- L: if hours/day given → ≥6 full sun; 3–6 part sun/part shade; <3 shade. Else categorical tokens.
- M: aquatic/emergent/shallow water → top (≈8.5–10.0); waterlogged/bog/marsh → high (≈7.0–8.5); consistently moist → mid‑high (≈5.5–7.0); fresh/mesic → mid (≈4.0–5.5); dry/drought → low (≈2.0–4.0). Precip >1400 mm pushes up; <750 mm pushes down.
- R: numeric pH dominates (≤6.3 acidic; 6.4–7.2 neutral/slightly acidic; ≥7.5 alkaline).
- N: rich/eutrophic → high; intermediate → mid; poor/lean/oligotrophic/avoid rich → low.
- T: prefer hardiness zones (≤3 low; 4–6 mid; ≥7 high) or Köppen (Cfb/Dfb cool temperate; Csa/Csb Mediterranean); tokens backstop numerics.

Output JSON (strict, per axis)
{
  "axis": "L|M|R|N|T",
  "expectation": "label (EIVE x.xx)",
  "support_count": int,
  "contradict_count": int,
  "strength": "strong|moderate|weak",
  "applicability": "general|limited",
  "numeric_advantage": true|false,
  "prefer_vs_tolerate_bias": "prefer|neutral|tolerate",
  "has_conflict": true|false,
  "specificity_score": 0|1|2,
  "strength_weight": 0.3|0.6|1.0,
  "support_weighted": float,
  "contradict_weighted": float,
  "reliability_score": float,         // in [0, 1]
  "verdict": "match|partial|conflict|insufficient",
  "verdict_numeric": 1.0|0.5|0.0|null,
  "reliability_label": "High|Medium|Low|Conflict|Unknown",
  "confidence": float,                // in [0, 1]
  "notes": "1–2 concise reasons"
}

Container JSON (final output)
{
  "summary": "1–2 lines across axes",
  "axes": [ {axis object as above}, ... five total ... ]
}

General constraints
- Never use values > 10 for any axis. Use the rules above for classification.
- Numeric evidence overrides vague text if they disagree.
- Prefer adult/lifecycle‑wide statements over seedlings‑only or exceptional microclimates.
- Output strict JSON only (no markdown or code fences).
