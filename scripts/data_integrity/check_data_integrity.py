#!/usr/bin/env python3
"""Lightweight integrity audit for the canonical phylotraits datasets."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional

import pandas as pd


@dataclass
class CheckResult:
    name: str
    status: str  # PASS, WARN, FAIL
    details: str


class IntegrityAudit:
    def __init__(self) -> None:
        self.results: List[CheckResult] = []

    # --------------------------------------------------------------
    # Helpers
    # --------------------------------------------------------------
    def record(self, name: str, status: str, details: str) -> None:
        self.results.append(CheckResult(name=name, status=status, details=details))

    def _find_species_column(self, df: pd.DataFrame, preferred: Optional[str] = None) -> str:
        if preferred and preferred in df.columns:
            return preferred
        for col in df.columns:
            if "species" in col.lower():
                return col
        raise ValueError("No species-like column found")

    def _slugify(self, value: str) -> str:
        return "".join(ch if ch.isalnum() else "_" for ch in value.lower()).strip("_")

    def _species_set(self, series: pd.Series) -> set[str]:
        return {self._slugify(str(v)) for v in series.astype(str)}

    # --------------------------------------------------------------
    # Checks
    # --------------------------------------------------------------
    def check_trait_tables(self) -> None:
        base_path = Path("artifacts/model_data_bioclim_subset_enhanced.csv")
        imputed_path = Path("artifacts/model_data_bioclim_subset_enhanced_imputed.csv")

        if not base_path.exists():
            self.record("Trait base table", "FAIL", f"Missing {base_path}")
            return

        base = pd.read_csv(base_path)
        base_species_col = self._find_species_column(base, "Species name standardized against TPL")
        base_species = self._species_set(base[base_species_col])

        issues: List[str] = []
        if len(base) != 654:
            issues.append(f"expected 654 rows, found {len(base)}")
        if base[base_species_col].isna().any():
            issues.append("NA species in base table")
        if base[base_species_col].nunique() != len(base):
            issues.append("Duplicate species in base table")

        if issues:
            self.record("Trait base table", "FAIL", "; ".join(issues))
        else:
            self.record("Trait base table", "PASS", "654 species, unique identifiers, no missing names")

        if not imputed_path.exists():
            self.record("Trait imputed table", "FAIL", f"Missing {imputed_path}")
            return

        imp = pd.read_csv(imputed_path)
        imp_species_col = self._find_species_column(imp, "Species name standardized against TPL")
        imp_species = self._species_set(imp[imp_species_col])

        missing_in_imp = base_species - imp_species
        extra_in_imp = imp_species - base_species

        if missing_in_imp or extra_in_imp:
            detail = []
            if missing_in_imp:
                detail.append(f"missing in imputed: {len(missing_in_imp)}")
            if extra_in_imp:
                detail.append(f"unexpected species: {len(extra_in_imp)}")
            self.record("Trait imputed table", "FAIL", "; ".join(detail))
        else:
            imputed_cols = ["Leaf_thickness_mm", "Frost_tolerance_score", "Leaf_N_per_area"]
            na_report = []
            for col in imputed_cols:
                if col in imp.columns and imp[col].isna().any():
                    na_report.append(col)
            status = "PASS" if not na_report else "WARN"
            msg = "species match base table"
            if na_report:
                msg += f"; NA remaining in {', '.join(na_report)}"
            self.record("Trait imputed table", status, msg)

    def check_climate_tables(self) -> None:
        base_path = Path("data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv")
        ai_path = Path("data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv")

        if not base_path.exists() or not ai_path.exists():
            missing = [p for p in [base_path, ai_path] if not p.exists()]
            self.record("Climate summaries", "FAIL", f"Missing files: {', '.join(str(m) for m in missing)}")
            return

        base = pd.read_csv(base_path)
        ai = pd.read_csv(ai_path)
        base_species_col = self._find_species_column(base, "species")
        ai_species_col = self._find_species_column(ai, "species")

        base_species = self._species_set(base[base_species_col])
        ai_species = self._species_set(ai[ai_species_col])

        missing = base_species - ai_species
        extra = ai_species - base_species
        if missing or extra:
            detail = []
            if missing:
                detail.append(f"missing in AI summary: {len(missing)}")
            if extra:
                detail.append(f"unexpected species in AI summary: {len(extra)}")
            self.record("Climate summaries", "FAIL", "; ".join(detail))
        else:
            ai_cols = [c for c in ai.columns if c.startswith("ai_")]
            self.record("Climate summaries", "PASS", f"species match; {len(ai_cols)} AI-derived columns present")

    def check_soil_join(self) -> None:
        soil_summary_path = Path("data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary_global_sg250m_ph_20250916.csv")
        joined_path = Path("data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_phq_sg250m_20250916.csv")

        if not soil_summary_path.exists() or not joined_path.exists():
            missing = [p for p in [soil_summary_path, joined_path] if not p.exists()]
            self.record("Soil join", "WARN", f"Missing files: {', '.join(str(m) for m in missing)}")
            return

        soil = pd.read_csv(soil_summary_path)
        joined = pd.read_csv(joined_path)
        soil_species_col = self._find_species_column(soil)
        joined_species_col = self._find_species_column(joined, "species")

        soil_species = self._species_set(soil[soil_species_col])
        joined_species = self._species_set(joined[joined_species_col])

        missing = soil_species - joined_species
        extra = joined_species - soil_species
        status = "PASS"
        detail = []
        if missing or extra:
            status = "WARN"
            if missing:
                detail.append(f"soil-only species: {len(missing)}")
            if extra:
                detail.append(f"join-only species: {len(extra)}")
        soil_cols = [c for c in joined.columns if c.startswith("ph") or c.startswith("hplus")]
        if soil_cols:
            na_counts = joined[soil_cols].isna().sum()
            problematic = [c for c, v in na_counts.items() if v == len(joined)]
            if problematic:
                status = "WARN"
                detail.append(f"soil columns entirely NA: {', '.join(problematic)}")
        if not detail:
            detail.append(f"{len(soil_cols)} soil columns present")
        self.record("Soil join", status, "; ".join(detail))

    def check_stage1_features(self) -> None:
        axes = {
            "T": Path("artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/T_pk/features.csv"),
            "M": Path("artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/M_pk/features.csv"),
            "L": Path("artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/L_pk/features.csv"),
            "N": Path("artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/N_pk/features.csv"),
            "R": Path("artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917/R_pk/features.csv"),
        }
        master_traits = pd.read_csv(Path("artifacts/model_data_bioclim_subset_enhanced_imputed.csv"))
        master_species = self._species_set(master_traits[self._find_species_column(master_traits, "Species name standardized against TPL")])
        expected_empty = {"ph_rootzone_mean", "hplus_rootzone_mean", "ph_calcareous_any", "ph_calcareous_shallow", "ph_calcareous_deep", "ph_alk_depth_min"}

        for axis, path in axes.items():
            if not path.exists():
                self.record(f"Stage1 features {axis}", "WARN", f"Missing {path}")
                continue
            df = pd.read_csv(path)
            species_col = self._find_species_column(df, "species_normalized")
            species_set = self._species_set(df[species_col])
            missing = master_species - species_set
            extra = species_set - master_species
            status = "PASS"
            detail = [f"rows={len(df)}"]
            if missing or extra:
                status = "WARN"
                if missing:
                    detail.append(f"missing species {len(missing)}")
                if extra:
                    detail.append(f"unexpected species {len(extra)}")
            na_cols = df.isna().sum()
            all_na = [col for col, count in na_cols.items() if count == len(df)]
            unexpected_na = [col for col in all_na if col not in expected_empty]
            if unexpected_na:
                status = "WARN"
                detail.append(f"columns entirely NA: {', '.join(unexpected_na[:5])}")
            self.record(f"Stage1 features {axis}", status, "; ".join(detail))

    def check_stage2_sem_ready(self) -> None:
        sem_path = Path("artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv")
        pcs_path = Path("artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2_pcs.csv")
        if not sem_path.exists() or not pcs_path.exists():
            missing = [p for p in [sem_path, pcs_path] if not p.exists()]
            self.record("Stage2 SEM-ready", "FAIL", f"Missing files: {', '.join(str(m) for m in missing)}")
            return
        sem = pd.read_csv(sem_path)
        pcs = pd.read_csv(pcs_path)
        species_col = self._find_species_column(sem)
        pcs_species_col = self._find_species_column(pcs)
        sem_species = self._species_set(sem[species_col])
        pcs_species = self._species_set(pcs[pcs_species_col])
        mismatch = sem_species ^ pcs_species
        status = "PASS" if not mismatch else "WARN"
        details = [f"rows={len(sem)}"]
        if mismatch:
            details.append(f"species mismatch between SEM and PC tables ({len(mismatch)} entries)")
        for col in [c for c in sem.columns if c.startswith("pc_trait_")]:
            mean = sem[col].mean()
            std = sem[col].std()
            if abs(mean) > 1e-6 or abs(std - 1) > 1e-3:
                status = "WARN"
                details.append(f"{col} mean={mean:.3f} sd={std:.3f}")
        self.record("Stage2 SEM-ready", status, "; ".join(details))

    # --------------------------------------------------------------
    def run(self) -> None:
        self.check_trait_tables()
        self.check_climate_tables()
        self.check_soil_join()
        self.check_stage1_features()
        self.check_stage2_sem_ready()

    def as_dict(self) -> Dict[str, Dict[str, str]]:
        return {
            r.name: {"status": r.status, "details": r.details}
            for r in self.results
        }


def main() -> None:
    parser = argparse.ArgumentParser(description="Canonical data integrity audit")
    parser.add_argument("--output", type=Path, help="Optional path to JSON report")
    args = parser.parse_args()

    audit = IntegrityAudit()
    audit.run()

    for r in audit.results:
        print(f"[{r.status}] {r.name}: {r.details}")

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("w") as fh:
            json.dump(audit.as_dict(), fh, indent=2)

    statuses = {r.status for r in audit.results}
    if "FAIL" in statuses:
        sys.exit(1)


if __name__ == "__main__":
    main()
