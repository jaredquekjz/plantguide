#!/usr/bin/env python3
"""Compare normalized Stage 7 profiles with EIVE qualitative expectations."""

from __future__ import annotations

import argparse
import json
import logging
import os
from pathlib import Path
from typing import Iterable

import pandas as pd
from google import genai
from google.genai.types import GenerateContentConfig

try:
    from tqdm import tqdm

    HAVE_TQDM = True
except ImportError:  # pragma: no cover - optional dependency
    HAVE_TQDM = False


logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger("align_stage7")

REPO_ROOT = Path(__file__).resolve().parents[1]
NORMALIZED_DIR = REPO_ROOT / "data" / "stage7_normalized_profiles"
LABELS_CSV = REPO_ROOT / "data" / "stage7_validation_eive_labels.csv"
PROMPT_PATH = REPO_ROOT / "src" / "Stage_7_Validation" / "prompt_alignment_verdict.md"
OUTPUT_DIR = REPO_ROOT / "results" / "stage7_alignment"


AXES = ["L", "M", "R", "N", "T"]


def init_client() -> genai.Client:
    os.environ["GOOGLE_GENAI_USE_VERTEXAI"] = "True"
    client = genai.Client()
    logger.info("Vertex AI client initialised for alignment.")
    return client


def iter_normalized_files(path: Path) -> Iterable[Path]:
    for file in sorted(path.glob("*.json")):
        if file.is_file():
            yield file


def build_expectation_payload(row: pd.Series) -> list[dict[str, str]]:
    payload: list[dict[str, str]] = []
    for axis in AXES:
        label_col = f"{axis}_label"
        value_col = f"EIVEres-{axis}"
        payload.append(
            {
                "axis": axis,
                "label": str(row[label_col]),
                "score": round(float(row[value_col]), 3),
            }
        )
    return payload


def build_prompt(instructions: str, species: str, expectation: list[dict[str, str]], descriptor_json: list[dict]) -> str:
    return (
        f"{instructions.strip()}\n\n"
        f"Plant: {species}\n"
        "EIVE expectations (JSON):\n"
        f"{json.dumps(expectation, ensure_ascii=False)}\n"
        "Stage 7 normalized descriptors (JSON):\n"
        f"{json.dumps(descriptor_json, ensure_ascii=False)}\n"
        "Return the container JSON exactly as specified."
    )


def parse_response(text: str) -> dict:
    raw = text.strip()
    if raw.startswith("```json") and raw.endswith("```"):
        raw = raw[len("```json") : -3].strip()
    elif raw.startswith("```") and raw.endswith("```"):
        raw = raw[3:-3].strip()
    parsed = json.loads(raw)
    if not isinstance(parsed, dict) or "axes" not in parsed:
        raise ValueError("Response missing container JSON with 'axes'.")
    return parsed


def main() -> None:
    parser = argparse.ArgumentParser(description="Compare normalized Stage 7 profiles to EIVE expectations.")
    parser.add_argument("--input-dir", default=str(NORMALIZED_DIR), help="Directory of normalized axis descriptors.")
    parser.add_argument("--output-dir", default=str(OUTPUT_DIR), help="Directory to write alignment verdicts.")
    parser.add_argument("--labels-csv", default=str(LABELS_CSV), help="Stage 7 validation labels CSV.")
    parser.add_argument("--species", help="Optional specific species name (Stage 2 naming).")
    parser.add_argument("--slug", help="Optional legacy slug (overrides --species).")
    parser.add_argument("--first", type=int, default=0, help="Process only first N files (0 = all).")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing outputs.")
    parser.add_argument("--model", default="gemini-2.5-pro", help="Gemini model to use (default: gemini-2.5-pro).")
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    labels_path = Path(args.labels_csv)

    if not input_dir.exists():
        raise SystemExit(f"Normalized input dir not found: {input_dir}")
    if not labels_path.exists():
        raise SystemExit(f"Labels CSV not found: {labels_path}")
    if not PROMPT_PATH.exists():
        raise SystemExit(f"Prompt instructions missing: {PROMPT_PATH}")

    labels_df = pd.read_csv(labels_path)

    if args.slug:
        candidates = labels_df[labels_df["legacy_slug"].str.lower() == args.slug.lower()]
    elif args.species:
        candidates = labels_df[labels_df["stage2_species"].str.lower() == args.species.lower()]
    else:
        candidates = None

    files: list[Path]
    if candidates is not None:
        if candidates.empty:
            raise SystemExit("Specified species/slug not found in labels CSV.")
        slug = candidates.iloc[0]["legacy_slug"]
        target = input_dir / f"{slug}.json"
        if not target.exists():
            raise SystemExit(f"Normalized descriptor missing: {target}")
        files = [target]
    else:
        files = list(iter_normalized_files(input_dir))
        if args.first > 0:
            files = files[: args.first]

    if not files:
        logger.info("No normalized profiles to process.")
        return

    instructions = PROMPT_PATH.read_text(encoding="utf-8")
    client = init_client()

    output_dir.mkdir(parents=True, exist_ok=True)

    processed = 0
    progress = tqdm(total=len(files), desc="Aligning profiles", unit="species") if HAVE_TQDM else None
    try:
        for idx, file_path in enumerate(files, 1):
            slug = file_path.stem
            row = labels_df[labels_df["legacy_slug"] == slug]
            if row.empty:
                logger.warning("No labels row for slug %s; skipping", slug)
                if progress:
                    progress.update(1)
                    progress.set_postfix(success=processed, failed=idx - processed)
                continue
            row = row.iloc[0]
            species = row["stage2_species"]

            output_path = output_dir / f"{slug}.json"
            if output_path.exists() and not args.overwrite:
                logger.info("[%d/%d] Skip existing %s", idx, len(files), output_path.name)
                if progress:
                    progress.update(1)
                    progress.set_postfix(success=processed, failed=idx - processed)
                continue

            with open(file_path, "r", encoding="utf-8") as handle:
                descriptor_json = json.load(handle)

            expectation_payload = build_expectation_payload(row)
            prompt = build_prompt(instructions, species, expectation_payload, descriptor_json)

            if not HAVE_TQDM:
                logger.info("[%d/%d] Aligning %s (%s)", idx, len(files), species, slug)
            try:
                response = client.models.generate_content(
                    model=args.model,
                    contents=prompt,
                    config=GenerateContentConfig(temperature=0.1),
                )
            except Exception as exc:
                logger.error("Model call failed for %s: %s", slug, exc)
                if progress:
                    progress.update(1)
                    progress.set_postfix(success=processed, failed=idx - processed)
                continue

            if not response or not getattr(response, "text", None):
                logger.error("Empty response for %s", slug)
                if progress:
                    progress.update(1)
                    progress.set_postfix(success=processed, failed=idx - processed)
                continue

            try:
                parsed = parse_response(response.text)
            except Exception as exc:
                raw_path = output_path.with_suffix(".raw.txt")
                raw_path.write_text(response.text, encoding="utf-8")
                logger.error("Invalid JSON for %s; saved raw to %s (%s)", slug, raw_path, exc)
                if progress:
                    progress.update(1)
                    progress.set_postfix(success=processed, failed=idx - processed)
                continue

            with open(output_path, "w", encoding="utf-8") as handle:
                json.dump(parsed, handle, ensure_ascii=False, indent=2)
            logger.info("Wrote %s", output_path)
            processed += 1
            if progress:
                progress.update(1)
                progress.set_postfix(success=processed, failed=idx - processed)
    finally:
        if progress:
            progress.close()

    logger.info("Completed: %d/%d successful", processed, len(files))


if __name__ == "__main__":  # pragma: no cover
    main()
