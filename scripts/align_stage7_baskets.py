#!/usr/bin/env python3
"""Gemini Flash: assign High/Medium/Low reliability baskets per axis for EIVE.

Inputs per species (by slug):
 - Encyclopedia profile: data/encyclopedia_profiles/{slug}.json (use expert EIVE values/labels)
 - Normalized descriptors: data/stage7_normalized_profiles/{slug}.json
 - Prompt: src/Stage_7_Validation/prompt_alignment_baskets.md

Outputs:
 - results/stage7_alignment_baskets/{slug}.json with simple basket JSON.

Notes:
 - This is intentionally forgiving: expert EIVE is the anchor; contradictions default to Medium unless decisively numeric for adults.
 - Uses gemini-2.0-flash by default.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Iterable, List, Dict, Any

from google import genai
from google.genai.types import GenerateContentConfig

REPO = Path(__file__).resolve().parents[1]
PROFILES_DIR = REPO / "data/encyclopedia_profiles"
NORMALIZED_DIR = REPO / "data/stage7_normalized_profiles"
PROMPT_PATH = REPO / "src/Stage_7_Validation/prompt_alignment_baskets.md"
OUTPUT_DIR = REPO / "results/stage7_alignment_baskets"

AXES = ["L", "M", "R", "N", "T"]


def derive_label(axis: str, score: float | None, raw_label: str | None) -> str:
    if raw_label:
        cleaned = raw_label.strip()
        if cleaned:
            return cleaned
    if score is None:
        return ""
    value = float(score)
    axis = axis.upper()
    if axis == "L":
        if value < 3:
            return "shade plant (mostly <5% relative illumination)"
        if value < 5.5:
            return "partial shade / dappled light"
        return "full sun (≥6 hours direct light)"
    if axis == "M":
        if value < 3:
            return "dry, drought-prone soils"
        if value < 4.5:
            return "fresh, well-drained soils"
        if value < 6.5:
            return "constantly moist or damp but not wet"
        return "wet or waterlogged soils"
    if axis == "R":
        if value < 3:
            return "strongly acidic soils"
        if value < 4.5:
            return "acidic soils"
        if value < 5.5:
            return "moderately acidic soils"
        if value < 6.5:
            return "neutral to slightly acidic soils"
        if value < 7.5:
            return "neutral to slightly alkaline soils"
        return "alkaline soils"
    if axis == "N":
        if value < 2.5:
            return "very lean, low-nutrient soils"
        if value < 4:
            return "lean or moderately poor soils"
        if value < 5.5:
            return "intermediate fertility soils"
        return "rich, nutrient-dense soils"
    if axis == "T":
        if value < 3:
            return "cold to montane climates"
        if value < 5:
            return "moderately cool to moderately warm (montane-submontane)"
        return "warm; colline to mild northern areas"
    return ""


def init_client() -> genai.Client:
    os.environ.setdefault("GOOGLE_GENAI_USE_VERTEXAI", "True")
    return genai.Client()


def build_expectations_from_profile(profile: dict) -> List[Dict[str, Any]]:
    out = []
    eive_vals = (profile.get("eive") or {}).get("values") or {}
    eive_labels = (profile.get("eive") or {}).get("labels") or {}
    for axis in AXES:
        score = eive_vals.get(axis)
        label = derive_label(axis, score if score is not None else None, eive_labels.get(axis))
        if score is None and not label:
            # still provide a placeholder to keep five axes; model can reason 'Low' due to lack of anchor
            out.append({"axis": axis, "label": "", "score": None})
        else:
            out.append({"axis": axis, "label": label, "score": float(score) if score is not None else None})
    return out


def build_prompt(instructions: str, species: str, expectation: List[Dict[str, Any]], descriptor_json: List[Dict[str, Any]]) -> str:
    return (
        f"{instructions.strip()}\n\n"
        f"Plant: {species}\n"
        "EIVE expectations (JSON):\n"
        f"{json.dumps(expectation, ensure_ascii=False)}\n"
        "Stage 7 normalized evidence (JSON):\n"
        f"{json.dumps(descriptor_json, ensure_ascii=False)}\n"
        "Return the container JSON exactly as specified."
    )


def parse_response(text: str) -> dict:
    raw = text.strip()
    if raw.startswith("```json") and raw.endswith("```"):
        raw = raw[len("```json") : -3].strip()
    elif raw.startswith("```") and raw.endswith("```"):
        raw = raw[3:-3].strip()
    return json.loads(raw)


def main() -> None:
    parser = argparse.ArgumentParser(description="Assign High/Medium/Low reliability baskets per axis using Gemini Flash.")
    parser.add_argument("--slugs", help="Comma-separated list of slugs (default: all normalized profiles)")
    parser.add_argument("--model", default="gemini-2.0-flash", help="Gemini model (default: gemini-2.0-flash)")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing outputs")
    args = parser.parse_args()

    if not PROMPT_PATH.exists():
        raise SystemExit(f"Prompt missing: {PROMPT_PATH}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    targets: List[Path]
    if args.slugs:
        targets = []
        for s in [t.strip() for t in args.slugs.split(",") if t.strip()]:
            p = NORMALIZED_DIR / f"{s}.json"
            if p.exists():
                targets.append(p)
            else:
                print(f"WARN: normalized descriptors not found for {s}")
    else:
        targets = sorted(NORMALIZED_DIR.glob("*.json"))

    instructions = PROMPT_PATH.read_text(encoding="utf-8")
    client = init_client()

    for file_path in targets:
        slug = file_path.stem
        output_path = OUTPUT_DIR / f"{slug}.json"
        if output_path.exists() and not args.overwrite:
            continue

        prof_path = PROFILES_DIR / f"{slug}.json"
        if not prof_path.exists():
            print(f"WARN: encyclopedia profile missing for {slug}; skipping")
            continue

        with open(file_path, "r", encoding="utf-8") as f:
            descriptor_json = json.load(f)
        with open(prof_path, "r", encoding="utf-8") as f:
            prof = json.load(f)

        species = prof.get("species") or slug
        expectation = build_expectations_from_profile(prof)
        prompt = build_prompt(instructions, species, expectation, descriptor_json)

        try:
            resp = client.models.generate_content(
                model=args.model,
                contents=prompt,
                config=GenerateContentConfig(temperature=0.1),
            )
        except Exception as exc:
            print(f"ERROR model call failed for {slug}: {exc}")
            continue

        if not resp or not getattr(resp, "text", None):
            print(f"ERROR empty model response for {slug}")
            continue

        try:
            parsed = parse_response(resp.text)
        except Exception as exc:
            raw_path = output_path.with_suffix(".raw.txt")
            raw_path.write_text(resp.text, encoding="utf-8")
            print(f"ERROR invalid JSON for {slug}; saved raw to {raw_path}: {exc}")
            continue

        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(parsed, f, ensure_ascii=False, indent=2)
        print(f"Wrote {output_path}")


if __name__ == "__main__":
    main()
