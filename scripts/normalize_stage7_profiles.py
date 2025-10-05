#!/usr/bin/env python3
"""Normalize Stage 7 qualitative profiles into axis-aligned JSON via Gemini Flash 2.5.

Reads all JSON profiles from `data/stage7_validation_profiles/` and, for each plant,
asks Gemini (Flash 2.5) to produce a concise, normalized mapping for L, M, R, N, T
axes per the rules in `src/Stage_7_Validation/prompt_eive_mapping.md`.

Outputs one JSON per input in `data/stage7_normalized_profiles/` by default.

Environment:
- Uses Vertex AI via ADC. Ensure one of the following before running:
  - export GOOGLE_APPLICATION_CREDENTIALS=/home/olier/ellenberg/service_account.json
  - or `gcloud auth application-default login` and set GOOGLE_CLOUD_PROJECT
"""

from __future__ import annotations

import argparse
import json
import logging
import os
from pathlib import Path
from typing import Iterable

from google import genai
from google.genai.types import GenerateContentConfig

try:
    from tqdm import tqdm

    HAVE_TQDM = True
except ImportError:  # pragma: no cover - optional dependency
    HAVE_TQDM = False


logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger("normalize_stage7")

REPO_ROOT = Path(__file__).resolve().parents[1]
INPUT_DIR = REPO_ROOT / "data" / "stage7_validation_profiles"
OUTPUT_DIR = REPO_ROOT / "data" / "stage7_normalized_profiles"
PROMPT_PATH = REPO_ROOT / "src" / "Stage_7_Validation" / "prompt_eive_mapping.md"


def init_client() -> genai.Client:
    os.environ["GOOGLE_GENAI_USE_VERTEXAI"] = "True"
    client = genai.Client()
    logger.info("Vertex AI client initialised (Gemini 2.5 Flash).")
    return client


def build_prompt(profile_json: dict, system_instructions: str) -> str:
    # Keep the instructions deterministic; request strict JSON array for 5 axes.
    enforcement = (
        "Strict formatting rules for output (must follow):\n"
        "- Output MUST be raw JSON only (no code fences, no markdown).\n"
        "- The root MUST be an array with exactly 5 objects (axes L,M,R,N,T).\n"
        "- In each object, the field `quotes` MUST be an array of strings only.\n"
        "  Do not include key:value pairs or objects in `quotes`; embed numbers as text.\n"
    )
    return (
        f"{system_instructions.strip()}\n\n{enforcement}\n"
        "Return a strict JSON array with exactly five entries (for axes L, M, R, N, T)\n"
        "using the Output JSON schema. Do not include any prose outside the JSON.\n\n"
        "Profile JSON follows. Use only its evidence; do not invent:\n"
        f"{json.dumps(profile_json, ensure_ascii=False)}\n"
    )


def iter_input_files(input_dir: Path) -> Iterable[Path]:
    for p in sorted(input_dir.glob("*.json")):
        if p.is_file():
            yield p


def extract_json_text(text: str) -> str:
    # Best-effort extraction: if model returns code fences, strip them.
    t = text.strip()
    if t.startswith("```json") and t.endswith("```"):
        t = t[len("```json"):].strip()
        t = t[:-3].strip()
    elif t.startswith("```") and t.endswith("```"):
        t = t[3:-3].strip()
    return t


def normalize_one(client: genai.Client, model: str, system_instructions: str, input_path: Path, output_path: Path, overwrite: bool) -> bool:
    if output_path.exists() and not overwrite:
        logger.info("Skip (exists): %s", output_path)
        return True
    try:
        with open(input_path, "r", encoding="utf-8") as h:
            profile = json.load(h)
    except Exception as exc:
        logger.error("Failed to read %s: %s", input_path, exc)
        return False

    prompt = build_prompt(profile, system_instructions)
    try:
        resp = client.models.generate_content(
            model=model,
            contents=prompt,
            config=GenerateContentConfig(temperature=0.1),
        )
    except Exception as exc:
        logger.error("Model call failed for %s: %s", input_path.name, exc)
        return False

    if not resp or not getattr(resp, "text", None):
        logger.error("Empty response for %s", input_path.name)
        return False
    raw_text = resp.text
    json_text = extract_json_text(raw_text)
    try:
        parsed = json.loads(json_text)
        if not isinstance(parsed, list) or len(parsed) != 5:
            raise ValueError("Expected a JSON array with 5 axis entries.")
    except Exception as exc:
        # Save raw for inspection
        debug_path = output_path.with_suffix(".raw.txt")
        debug_path.parent.mkdir(parents=True, exist_ok=True)
        debug_path.write_text(raw_text, encoding="utf-8")
        logger.error("Response not valid JSON for %s; saved raw to %s (%s)", input_path.name, debug_path, exc)
        return False

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as h:
        json.dump(parsed, h, ensure_ascii=False, indent=2)
    logger.info("Wrote %s", output_path)
    return True


def main() -> None:
    ap = argparse.ArgumentParser(description="Normalize Stage 7 profiles with Gemini 2.5 Flash.")
    ap.add_argument("--input-dir", default=str(INPUT_DIR), help="Directory of qualitative profiles (JSON).")
    ap.add_argument("--output-dir", default=str(OUTPUT_DIR), help="Directory to write normalized JSON mappings.")
    ap.add_argument("--first", type=int, default=0, help="Only process first N files (0 = all).")
    ap.add_argument("--overwrite", action="store_true", help="Overwrite existing outputs.")
    ap.add_argument("--model", default="gemini-2.5-flash", help="Gemini model to use (default: gemini-2.5-flash).")
    args = ap.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if not input_dir.exists():
        raise SystemExit(f"Input dir not found: {input_dir}")
    if not PROMPT_PATH.exists():
        raise SystemExit(f"Prompt file missing: {PROMPT_PATH}")

    system_instructions = PROMPT_PATH.read_text(encoding="utf-8")
    client = init_client()

    files = list(iter_input_files(input_dir))
    if args.first and args.first > 0:
        files = files[: args.first]
    total = len(files)
    logger.info("Found %d profile(s) in %s", total, input_dir)

    ok = 0
    progress = tqdm(total=total, desc="Normalizing profiles", unit="species") if HAVE_TQDM else None
    try:
        for idx, path in enumerate(files, 1):
            out_path = output_dir / path.name
            if not HAVE_TQDM:
                logger.info("[%d/%d] Normalizing %s", idx, total, path.name)
            success = normalize_one(
                client,
                args.model,
                system_instructions,
                path,
                out_path,
                overwrite=args.overwrite,
            )
            if success:
                ok += 1
            if progress:
                progress.update(1)
                progress.set_postfix(success=ok, failed=idx - ok)
    finally:
        if progress:
            progress.close()

    logger.info("Completed: %d/%d successful", ok, total)


if __name__ == "__main__":  # pragma: no cover
    main()
