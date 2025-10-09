#!/usr/bin/env python3
"""Merge basket results into encyclopedia profiles as `reliability_basket`.

Reads results/stage7_alignment_baskets/{slug}.json and writes
data/encyclopedia_profiles/{slug}.json with a new block:

  "reliability_basket": { "L": "High|Medium|Low", ... }

Does not modify existing Stage 7 reliability fields; adds alongside them.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict

REPO = Path(__file__).resolve().parents[1]
PROFILES_DIR = REPO / "data/encyclopedia_profiles"
BASKETS_DIR = REPO / "results/stage7_alignment_baskets"


def load_basket(path: Path) -> tuple[Dict[str, str], Dict[str, str], Dict[str, list[str]], str]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    baskets: Dict[str, str] = {}
    reasons: Dict[str, str] = {}
    evidence: Dict[str, list[str]] = {}
    for axis in data.get("axes", []):
        a = axis.get("axis")
        b = axis.get("basket")
        if a and b:
            baskets[a] = b
            reason = axis.get("reason")
            if reason:
                reasons[a] = reason
            ev = axis.get("evidence") or []
            if ev:
                evidence[a] = ev
    summary = data.get("summary", "")
    return baskets, reasons, evidence, summary


def merge_into_profile(
    slug: str,
    baskets: Dict[str, str],
    reasons: Dict[str, str],
    evidence: Dict[str, list[str]],
    summary: str,
    dry_run: bool = False,
) -> bool:
    prof_path = PROFILES_DIR / f"{slug}.json"
    if not prof_path.exists():
        print(f"WARN: profile missing: {slug}")
        return False
    with open(prof_path, "r", encoding="utf-8") as f:
        prof = json.load(f)
    rb = prof.setdefault("reliability_basket", {})
    rr = prof.setdefault("reliability_reason", {})
    re = prof.setdefault("reliability_evidence", {})
    if summary:
        prof["stage7_reliability_summary"] = summary
    changed = False
    for axis, val in baskets.items():
        if rb.get(axis) != val:
            rb[axis] = val
            changed = True
    for axis, text in reasons.items():
        if rr.get(axis) != text:
            rr[axis] = text
            changed = True
    for axis, ev in evidence.items():
        if re.get(axis) != ev:
            re[axis] = ev
            changed = True
    if changed and not dry_run:
        with open(prof_path, "w", encoding="utf-8") as f:
            json.dump(prof, f, ensure_ascii=False, indent=2)
    return changed


def main():
    parser = argparse.ArgumentParser(description="Merge reliability baskets into profiles")
    parser.add_argument("--slugs", help="Comma-separated list of slugs (default: all available baskets)")
    parser.add_argument("--dry-run", action="store_true", help="Only report; do not write files")
    args = parser.parse_args()

    targets = []
    if args.slugs:
        for s in [t.strip() for t in args.slugs.split(",") if t.strip()]:
            p = BASKETS_DIR / f"{s}.json"
            if p.exists():
                targets.append(p)
            else:
                print(f"WARN: basket JSON missing for {s}")
    else:
        targets = sorted(BASKETS_DIR.glob("*.json"))

    changed = []
    for p in targets:
        slug = p.stem
        baskets, reasons, evidence, summary = load_basket(p)
        if not baskets:
            print(f"WARN: no axes in {p}")
            continue
        if merge_into_profile(slug, baskets, reasons, evidence, summary, dry_run=args.dry_run):
            changed.append(slug)

    if changed:
        print("Updated profiles:")
        for s in changed:
            print(f" - {s}")
    else:
        print("No profile changes were made.")


if __name__ == "__main__":
    main()
