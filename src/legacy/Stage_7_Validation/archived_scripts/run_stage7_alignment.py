#!/usr/bin/env python3
"""Stage 7 validation: compare Gemini profile narratives with EIVE expectations."""

from __future__ import annotations

import argparse
import json
import logging
import os
from pathlib import Path
from typing import Any, Dict, List, Tuple

import pandas as pd
from google import genai
from google.genai.types import GenerateContentConfig


logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[2]
STAGE7_DATA = REPO_ROOT / "data" / "stage7_validation_eive_labels.csv"
ALIGNMENT_ROOT = REPO_ROOT / "results" / "stage7_alignment"

AXIS_COLUMNS = {
    "L": "EIVEres-L",
    "M": "EIVEres-M",
    "R": "EIVEres-R",
    "N": "EIVEres-N",
    "T": "EIVEres-T",
}


def _safe_get(data: Dict[str, Any], *keys: str, default: str = "") -> Any:
    cur: Any = data
    for key in keys:
        if isinstance(cur, dict) and key in cur:
            cur = cur[key]
        else:
            return default
    return cur


def format_light_section(profile: Dict[str, Any]) -> str:
    env = profile.get("environmental_requirements", {})
    req = env.get("requirements", {})
    tol = env.get("tolerances", {})
    lines: List[str] = []
    for item in req.get("light_requirements", []) or []:
        name = item.get("name")
        min_hours = item.get("min_hours_direct_sunlight_per_day")
        max_hours = item.get("max_hours_direct_sunlight_per_day")
        condition = item.get("condition")
        snippet = f"• {name}"
        if min_hours is not None and max_hours is not None:
            snippet += f" ({min_hours}–{max_hours} h direct sun)"
        if condition:
            snippet += f": {condition}"
        lines.append(snippet)
    shade_tol = tol.get("shade", {}).get("value")
    if shade_tol:
        lines.append(f"• Shade tolerance/tolerance note: {shade_tol}")
    return "\n".join(lines) or "No profile statements about light requirements."


def format_moisture_section(profile: Dict[str, Any]) -> str:
    env = profile.get("environmental_requirements", {})
    req = env.get("requirements", {})
    tol = env.get("tolerances", {})
    lines: List[str] = []
    water = req.get("water_requirement", {})
    if isinstance(water, dict):
        val = water.get("value")
        if val:
            lines.append(f"• Water requirement: {val}")
        precip_min = water.get("min_yearly_precipitation_mm")
        precip_max = water.get("max_yearly_precipitation_mm")
        if precip_min or precip_max:
            lines.append(f"• Precipitation range: {precip_min}–{precip_max} mm/year")
    drought = tol.get("drought", {}).get("value")
    if drought:
        lines.append(f"• Drought tolerance: {drought}")
    micro = _safe_get(profile, "climate_requirements", "requirements", "microclimate_preferences", "value")
    if micro:
        lines.append(f"• Microclimate notes: {micro}")
    return "\n".join(lines) or "No profile statements about moisture requirements."


def format_reaction_section(profile: Dict[str, Any]) -> str:
    env = profile.get("environmental_requirements", {})
    req = env.get("requirements", {})
    lines: List[str] = []
    ph = req.get("ph_range", {})
    if isinstance(ph, dict):
        min_ph = ph.get("min")
        max_ph = ph.get("max")
        if min_ph is not None or max_ph is not None:
            lines.append(f"• Reported pH range: {min_ph}–{max_ph}")
        comments = ph.get("qualitative_comments")
        if comments:
            lines.append(f"• Comments: {comments}")
    soil_types = req.get("soil_types", []) or []
    if soil_types:
        readable = ", ".join(sorted({item.get("name") for item in soil_types if item.get("name")}))
        if readable:
            lines.append(f"• Soil types referenced: {readable}")
    notes = req.get("soil_qualitative_comments")
    if notes:
        lines.append(f"• Soil remarks: {notes}")
    return "\n".join(lines) or "No profile statements about soil reaction/pH."


def format_nitrogen_section(profile: Dict[str, Any]) -> str:
    env = profile.get("environmental_requirements", {})
    req = env.get("requirements", {})
    comments = req.get("soil_qualitative_comments")
    if comments:
        return f"• Soil fertility hints: {comments}"
    return "No explicit soil fertility or eutrophication statements found."


def format_temperature_section(profile: Dict[str, Any]) -> str:
    clim = profile.get("climate_requirements", {})
    req = clim.get("requirements", {})
    lines: List[str] = []
    opt = req.get("optimal_temperature_range", {})
    if isinstance(opt, dict) and (opt.get("min") is not None or opt.get("max") is not None):
        lines.append(f"• Optimal growing temperature: {opt.get('min')}–{opt.get('max')} °C")
    opt_comments = opt.get("qualitative_comments") if isinstance(opt, dict) else None
    if opt_comments:
        lines.append(f"• Temperature remarks: {opt_comments}")
    hardiness = req.get("hardiness_zone_range", {})
    if isinstance(hardiness, dict) and (hardiness.get("min") is not None or hardiness.get("max") is not None):
        lines.append(f"• Hardiness zones: {hardiness.get('min')}–{hardiness.get('max')}")
    if isinstance(hardiness, dict) and hardiness.get("qualitative_comments"):
        lines.append(f"• Hardiness notes: {hardiness['qualitative_comments']}")
    koppen = req.get("suitable_koppen_zones", {})
    if isinstance(koppen, dict) and koppen.get("value"):
        zones = ", ".join(koppen.get("value"))
        lines.append(f"• Köppen zones: {zones}")
        if koppen.get("qualitative_comments"):
            lines.append(f"• Köppen notes: {koppen['qualitative_comments']}")
    micro = _safe_get(req, "microclimate_preferences", "value")
    if micro:
        lines.append(f"• Microclimate preferences: {micro}")

    heat_section = _safe_get(clim, "tolerances", "heat", default={})
    if isinstance(heat_section, dict):
        heat_comments = heat_section.get("qualitative_comments")
        if heat_comments:
            lines.append(f"• Heat tolerance notes: {heat_comments}")
    elif isinstance(heat_section, str):
        lines.append(f"• Heat tolerance notes: {heat_section}")

    frost_section = _safe_get(req, "frost_sensitivity", default={})
    if isinstance(frost_section, dict):
        frost = frost_section.get("value")
        if frost:
            lines.append(f"• Frost sensitivity: {frost}")
        frost_comments = frost_section.get("qualitative_comments")
        if frost_comments:
            lines.append(f"• Frost notes: {frost_comments}")
    elif isinstance(frost_section, str):
        lines.append(f"• Frost sensitivity: {frost_section}")
    return "\n".join(lines) or "No profile statements about temperature preferences."


AXIS_SUMMARISERS = {
    "L": format_light_section,
    "M": format_moisture_section,
    "R": format_reaction_section,
    "N": format_nitrogen_section,
    "T": format_temperature_section,
}


class AlignmentEvaluator:
    def __init__(self, species: str, profile_path: Path | None = None, output_dir: Path | None = None):
        self.species = species
        self.profile_path_override = profile_path
        self.output_dir = output_dir or ALIGNMENT_ROOT
        self.output_dir.mkdir(parents=True, exist_ok=True)

        self.labels_df = pd.read_csv(STAGE7_DATA)
        try:
            self.row = self._locate_species_row(species)
        except ValueError as err:
            logger.error(str(err))
            raise

        self.profile = self._load_profile()
        self.setup_client()

    def _locate_species_row(self, species: str) -> pd.Series:
        candidates = self.labels_df[self.labels_df["stage2_species"].str.lower() == species.lower()]
        if candidates.empty:
            candidates = self.labels_df[self.labels_df["legacy_slug"].str.lower() == species.lower()]
        if candidates.empty:
            available = sorted(self.labels_df["stage2_species"].unique())
            raise ValueError(f"Species '{species}' not found. Available examples: {available[:10]}...")
        if len(candidates) > 1:
            logger.warning("Multiple rows matched; using the first instance.")
        return candidates.iloc[0]

    def _resolve_profile_path(self) -> Path:
        if self.profile_path_override:
            return Path(self.profile_path_override)
        dest = self.row.get("destination_path")
        if isinstance(dest, str) and dest:
            dest_path = (REPO_ROOT / dest).resolve()
            if dest_path.exists():
                return dest_path
        legacy = self.row.get("legacy_path")
        if isinstance(legacy, str) and legacy:
            legacy_path = Path(legacy)
            if legacy_path.exists():
                return legacy_path
        raise FileNotFoundError("No existing profile JSON found for this species.")

    def _load_profile(self) -> Dict[str, Any]:
        path = self._resolve_profile_path()
        logger.info("Loaded Stage 7 profile from %s", path)
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)

    def setup_client(self) -> None:
        try:
            project_id = os.getenv("GOOGLE_CLOUD_PROJECT")
            if project_id:
                os.environ["GOOGLE_CLOUD_PROJECT"] = project_id
            os.environ["GOOGLE_GENAI_USE_VERTEXAI"] = "True"
            self.client = genai.Client()
            logger.info("Vertex AI client initialised for Stage 7 alignment.")
        except Exception as exc:  # pragma: no cover
            logger.error("Failed to initialise Vertex AI client: %s", exc)
            raise

    def build_prompt(self) -> str:
        expectation_lines: List[str] = []
        evidence_lines: List[str] = []

        for axis, value_col in AXIS_COLUMNS.items():
            eive_value = float(self.row[value_col])
            label = self.row[f"{axis}_label"]
            expectation_lines.append(f"### {axis}\nExpectation: {label} (EIVE score {eive_value:.2f})")

            summariser = AXIS_SUMMARISERS[axis]
            evidence = summariser(self.profile)
            evidence_lines.append(f"### {axis}\n{evidence}")

        expectation_block = "\n\n".join(expectation_lines)
        evidence_block = "\n\n".join(evidence_lines)

        prompt = f"""
You evaluate whether a plant profile matches ecological expectations derived from EIVE (0–10 scale; higher means stronger expression of the factor). For each axis you receive:
1. The numeric EIVE score and corresponding qualitative expectation. 
2. Extracted evidence from the Stage 7 Gemini profile.

Decide if the narrative supports the expectation. Consider whether evidence agrees, partially agrees, conflicts, or is absent.

Report your findings in strict JSON with the structure:
{{
  "summary": "...",
  "axes": [
    {{"axis": "L", "expectation": "...", "verdict": "match|partial|conflict|insufficient", "confidence": float between 0 and 1, "notes": "..."}},
    ...
  ]
}}

Do not include Markdown. Reason concisely in the notes.

---
EIVE expectations:
{expectation_block}

---
Profile evidence:
{evidence_block}
"""
        return prompt.strip()

    def request_alignment(self) -> str | None:
        prompt = self.build_prompt()
        logger.info("Submitting alignment prompt for %s", self.species)
        response = self.client.models.generate_content(
            model="gemini-2.5-pro",
            contents=prompt,
            config=GenerateContentConfig(temperature=0.2),
        )
        return response.text if response else None

    def run(self) -> Path | None:
        output_path = self.output_dir / f"{self.row['legacy_slug'] or self.row['stage2_species']}.json"
        result = self.request_alignment()
        if not result:
            logger.error("LLM returned no response for %s", self.species)
            return None
        with open(output_path, "w", encoding="utf-8") as handle:
            handle.write(result)
        logger.info("Saved alignment verdict to %s", output_path)
        return output_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare Stage 7 Gemini profile with EIVE expectations.")
    parser.add_argument("--species", required=True, help="Stage 2 species name (e.g. 'Abies alba').")
    parser.add_argument(
        "--profile-path",
        help="Optional path to a profile JSON. Overrides the default destination_path from the dataset.",
    )
    parser.add_argument(
        "--output-dir",
        help="Directory for storing the alignment JSON (default: results/stage7_alignment).",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output_dir = Path(args.output_dir) if args.output_dir else None
    evaluator = AlignmentEvaluator(
        species=args.species,
        profile_path=Path(args.profile_path) if args.profile_path else None,
        output_dir=output_dir,
    )
    evaluator.run()


if __name__ == "__main__":  # pragma: no cover
    main()
