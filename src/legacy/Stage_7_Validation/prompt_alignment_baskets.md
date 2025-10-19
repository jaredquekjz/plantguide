# Stage 7 — Reliability Baskets (High/Medium/Low)

You receive expert EIVE expectations and a normalized evidence summary for a plant. For each axis {L, M, R, N, T}, select exactly one reliability basket for the expert EIVE expectation based on the normalized evidence.

Key principles
- Expert EIVE values are the anchor. Prefer them unless evidence is decisively contradictory.
- Adult-plant context dominates. Seedling-only or exceptional microclimate evidence reduces certainty, not flips it.
- Prefer numeric evidence (hours of sun, pH, precipitation, hardiness zones, Köppen) over vague text.
- Treat categorical quotes in the evidence list (e.g., “Very shade tolerant”) as supportive signals; combine them with numeric counterpoints before deciding.
- Keep it simple: output only a basket, one reason, and up to two short evidence snippets.

Basket definitions
- High: Evidence clearly aligns with the EIVE expectation.
  - Typically numeric agreement or explicit categorical match without strong contradictions.
- Medium: Mixed signals or limited/juvenile/edge-case evidence; or a single apparent contradiction that isn’t decisively numeric for mature plants.
  - Use Medium by default when there is some contradiction but not strong, repeated, numeric adult-level contradiction.
- Example: If EIVE expects "shade" but evidence cites ~6–8 hours sun *and* maintains shade tolerance (e.g., seedlings persist in canopy shade), choose Medium, not Low.
- When both supportive shade tolerance statements and brighter hour counts appear together, treat as mixed evidence → Medium (reserve Low for cases with *only* contradictory adult evidence).
- Low: Strong, repeated, adult-context numeric contradictions against the EIVE expectation, or multiple authoritative categorical statements that clearly oppose it.
  - Only choose Low when supportive evidence is absent or clearly outweighed by multiple adult numeric contradictions.
  - Never choose Low if at least one supportive quote exists alongside the contradiction—downgrade to Medium instead.

Special handling
- If evidence lists both “prefers/optimal” and “tolerates” classes, treat “prefers/optimal” as stronger.
- Numeric trumps vague tokens; a single well-bounded numeric statement (e.g., 6–8 h direct sun; pH 7.2–7.8) outweighs generic prose.
- Do not downscore to Low based on seedling-only shade/water notes if adult evidence supports the EIVE value.

Input payloads
- EIVE expectations: JSON with five entries, each `{"axis":"L|M|R|N|T","label":"text","score":float}`.
- Evidence: normalized JSON array with items per axis (categorical/ numeric keys already extracted for you).

Output JSON schema (strict)
{
  "summary": "1–2 short lines across axes",
  "axes": [
    {
      "axis": "L|M|R|N|T",
      "expectation": "<EIVE label> (EIVE <score>)",
      "basket": "High|Medium|Low",
      "reason": "Concise 1-line rationale",
      "evidence": ["snippet1", "snippet2"]
    },
    {five total}
  ]
}

Constraints
- Output strict JSON only (no code fences).
- Use at most two short evidence strings per axis; prefer numeric ranges if available.
- When a supportive categorical quote exists alongside a contradictory number, include one of each so the rationale stays balanced.
- Never infer new numbers; only use those present in evidence.
- The `reason` field must follow this template verbatim, adjusting the bracketed content only: `Summary of information found online shows that <concise evidence insight>. Expert assigned (or predicted) EIVE value shows that <expectation label>. Therefore the reliability is <High|Medium|Low> because <short justification>.`
