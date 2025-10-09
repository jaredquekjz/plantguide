#!/usr/bin/env python3
"""Generate gardening advice prompts for Stage 7 using Gemini."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any, Dict, List, Optional

from google import genai
from google.genai.types import GenerateContentConfig

REPO = Path(__file__).resolve().parents[1]
PROFILES_DIR = REPO / "data/encyclopedia_profiles"
RESULTS_DIR = REPO / "results/stage7_gardening_advice"
PROMPT_DIR = REPO / "src/Stage_7_Validation"

PROMPT_CLIMATE = PROMPT_DIR / "prompt_gardening_climate.md"
PROMPT_SOIL = PROMPT_DIR / "prompt_gardening_soil.md"
PROMPT_INTERACTIONS = PROMPT_DIR / "prompt_gardening_interactions.md"
PROMPT_STRATEGY = PROMPT_DIR / "prompt_gardening_strategy_services.md"

TOP_PARTNER_LIMIT = 10
ALL_FOCUSES = ["climate", "soil", "ecological_interactions", "strategy_services"]


def init_client() -> genai.Client:
    os.environ.setdefault("GOOGLE_GENAI_USE_VERTEXAI", "True")
    return genai.Client()


def parse_response(text: str) -> Dict[str, Any]:
    raw = text.strip()
    if not raw:
        raise ValueError("empty response")
    if raw.startswith("```json") and raw.endswith("```"):
        raw = raw[len("```json") : -3].strip()
    elif raw.startswith("```") and raw.endswith("```"):
        raw = raw[3:-3].strip()
    return json.loads(raw)


def read_common_name(profile: Dict[str, Any]) -> Optional[str]:
    common = profile.get("common_names")
    if isinstance(common, dict):
        primary = common.get("primary")
        if isinstance(primary, str) and primary.strip():
            return primary.strip()
        alternatives = common.get("alternatives")
        if isinstance(alternatives, list):
            for item in alternatives:
                if isinstance(item, str) and item.strip():
                    return item.strip()
    return None


def top_partners(partners: Optional[List[str]], limit: int = TOP_PARTNER_LIMIT) -> Optional[List[str]]:
    if not partners:
        return None
    sliced = [p.strip() for p in partners if isinstance(p, str) and p.strip()]
    if not sliced:
        return None
    return sliced[:limit]


def build_climate_payload(profile: Dict[str, Any], slug: str) -> Dict[str, Any]:
    eive = profile.get("eive") or {}
    values = eive.get("values") or {}
    labels = eive.get("labels") or {}
    reliability = profile.get("reliability") or {}
    reliability_reason = profile.get("reliability_reason") or {}
    axes = ("L", "M", "T")
    return {
        "species": profile.get("species") or slug,
        "common_name": read_common_name(profile),
        "slug": slug,
        "eive": {
            "values": {k: values.get(k) for k in axes},
            "labels": {k: labels.get(k) for k in axes},
        },
        "reliability": {k: reliability.get(k) for k in axes},
        "reliability_reason": {k: reliability_reason.get(k) for k in axes},
        "bioclim": profile.get("bioclim"),
    }


def build_soil_payload(profile: Dict[str, Any], slug: str) -> Dict[str, Any]:
    eive = profile.get("eive") or {}
    values = eive.get("values") or {}
    labels = eive.get("labels") or {}
    reliability = profile.get("reliability") or {}
    reliability_reason = profile.get("reliability_reason") or {}
    axes = ("R", "N")
    return {
        "species": profile.get("species") or slug,
        "common_name": read_common_name(profile),
        "slug": slug,
        "eive": {
            "values": {k: values.get(k) for k in axes},
            "labels": {k: labels.get(k) for k in axes},
        },
        "reliability": {k: reliability.get(k) for k in axes},
        "reliability_reason": {k: reliability_reason.get(k) for k in axes},
        "soil": profile.get("soil"),
    }


def build_interactions_payload(profile: Dict[str, Any], slug: str) -> Dict[str, Any]:
    interactions = profile.get("interactions") or {}
    eive = profile.get("eive") or {}
    labels = eive.get("labels") or {}
    reliability = profile.get("reliability") or {}
    reliability_reason = profile.get("reliability_reason") or {}
    axes = ("L", "M", "R", "N", "T")

    def prepare(section: str) -> Dict[str, Any]:
        data = interactions.get(section) or {}
        # Limit partner list to the top N entries to avoid oversized prompts.
        top = top_partners(data.get("top_partners"))
        return {
            "records": data.get("records"),
            "partners": data.get("partners"),
            "top_partners": top,
        }

    return {
        "species": profile.get("species") or slug,
        "common_name": read_common_name(profile),
        "slug": slug,
        "eive": {
            "values": {k: (eive.get("values") or {}).get(k) for k in axes},
            "labels": {k: labels.get(k) for k in axes},
        },
        "reliability": {k: reliability.get(k) for k in axes},
        "reliability_reason": {k: reliability_reason.get(k) for k in axes},
        "interactions": {
            "pollination": prepare("pollination"),
            "herbivory": prepare("herbivory"),
            "pathogen": prepare("pathogen"),
        },
        "notes": None,
    }


def build_strategy_payload(profile: Dict[str, Any], slug: str) -> Dict[str, Any]:
    eive = profile.get("eive") or {}
    reliability = profile.get("reliability") or {}
    reliability_reason = profile.get("reliability_reason") or {}
    return {
        "species": profile.get("species") or slug,
        "common_name": read_common_name(profile),
        "slug": slug,
        "csr": profile.get("csr"),
        "eco_services": profile.get("eco_services"),
        "eive": {
            "values": eive.get("values"),
            "labels": eive.get("labels"),
        },
        "reliability": reliability,
        "reliability_reason": reliability_reason,
    }


def run_prompt(
    client: genai.Client,
    model: str,
    prompt_text: str,
    payload: Dict[str, Any],
    temperature: float,
) -> str:
    message = f"{prompt_text.strip()}\n\nSpecies payload:\n{json.dumps(payload, ensure_ascii=False)}"
    response = client.models.generate_content(
        model=model,
        contents=message,
        config=GenerateContentConfig(
            temperature=temperature,
            response_mime_type="application/json",
        ),
    )
    if not response or not getattr(response, "text", None):
        raise ValueError("model returned no text")
    return response.text


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate gardening advice prompts using Gemini.")
    parser.add_argument("--slugs", help="Comma-separated list of species slugs. Default: all encyclopedia profiles.")
    parser.add_argument("--model", default="gemini-2.5-pro", help="Gemini model to use (default: gemini-2.5-pro).")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing outputs.")
    parser.add_argument("--temperature", type=float, default=0.35, help="Sampling temperature (default: 0.35).")
    parser.add_argument(
        "--focuses",
        help="Comma-separated list of focus blocks to regenerate (climate, soil, ecological_interactions, strategy_services). Default: all",
    )
    args = parser.parse_args()

    missing_prompts = [
        path
        for path in (PROMPT_CLIMATE, PROMPT_SOIL, PROMPT_INTERACTIONS, PROMPT_STRATEGY)
        if not path.exists()
    ]
    if missing_prompts:
        raise SystemExit(f"Missing prompt files: {', '.join(str(p) for p in missing_prompts)}")

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    if args.slugs:
        targets = [slug.strip() for slug in args.slugs.split(",") if slug.strip()]
    else:
        targets = sorted(p.stem for p in PROFILES_DIR.glob("*.json"))

    if not targets:
        raise SystemExit("No species targets found.")

    client = init_client()

    if args.focuses:
        focus_list = [f.strip() for f in args.focuses.split(",") if f.strip()]
        invalid = [f for f in focus_list if f not in ALL_FOCUSES]
        if invalid:
            raise SystemExit(f"Invalid focus name(s): {', '.join(invalid)}. Valid options: {', '.join(ALL_FOCUSES)}")
        focuses = focus_list
    else:
        focuses = ALL_FOCUSES

    total = len(targets)
    for idx, slug in enumerate(targets, start=1):
        print(f"[{idx}/{total}] Starting {slug} …", flush=True)
        output_path = RESULTS_DIR / f"{slug}.json"
        if output_path.exists() and not args.overwrite:
            print(f"[{idx}/{total}] Skipping {slug} (exists; use --overwrite to regenerate)", flush=True)
            continue

        profile_path = PROFILES_DIR / f"{slug}.json"
        if not profile_path.exists():
            print(f"WARN: encyclopedia profile missing for {slug}; skipping")
            continue

        with open(profile_path, "r", encoding="utf-8") as handle:
            profile = json.load(handle)

        payloads: Dict[str, Dict[str, Any]] = {}
        if "climate" in focuses:
            payloads["climate"] = build_climate_payload(profile, slug)
        if "soil" in focuses:
            payloads["soil"] = build_soil_payload(profile, slug)
        if "ecological_interactions" in focuses:
            payloads["ecological_interactions"] = build_interactions_payload(profile, slug)
        if "strategy_services" in focuses:
            payloads["strategy_services"] = build_strategy_payload(profile, slug)

        prompts = {
            "climate": PROMPT_CLIMATE.read_text(encoding="utf-8"),
            "soil": PROMPT_SOIL.read_text(encoding="utf-8"),
            "ecological_interactions": PROMPT_INTERACTIONS.read_text(encoding="utf-8"),
            "strategy_services": PROMPT_STRATEGY.read_text(encoding="utf-8"),
        }

        existing_output: Dict[str, Any] = {}
        if output_path.exists() and not args.overwrite:
            try:
                existing_output = json.loads(output_path.read_text(encoding="utf-8"))
            except Exception:
                existing_output = {}
        elif output_path.exists():
            try:
                existing_output = json.loads(output_path.read_text(encoding="utf-8"))
            except Exception:
                existing_output = {}

        outputs: Dict[str, Any] = existing_output or {}
        outputs["species"] = profile.get("species")
        outputs["slug"] = slug

        for focus in focuses:
            prompt_text = prompts[focus]
            raw_text: Optional[str] = None
            try:
                raw_text = run_prompt(client, args.model, prompt_text, payloads[focus], args.temperature)
                result = parse_response(raw_text)
                outputs[f"{focus}_advice"] = result
                if f"{focus}_advice_error" in outputs:
                    outputs.pop(f"{focus}_advice_error", None)
                print(f"[{idx}/{total}]   ✓ {focus} advice ready", flush=True)
            except Exception as exc:
                outputs[f"{focus}_advice_error"] = str(exc)
                debug_bundle = {
                    "payload": payloads[focus],
                    "raw_text": raw_text,
                }
                raw_path = output_path.with_suffix(f".{focus}.raw.json")
                raw_path.write_text(json.dumps(debug_bundle, ensure_ascii=False, indent=2), encoding="utf-8")
                print(f"[{idx}/{total}]   ✗ {focus} failed: {exc}", flush=True)

        with open(output_path, "w", encoding="utf-8") as handle:
            json.dump(outputs, handle, ensure_ascii=False, indent=2)
        print(f"[{idx}/{total}] Finished {slug} → {output_path}", flush=True)


if __name__ == "__main__":
    main()
