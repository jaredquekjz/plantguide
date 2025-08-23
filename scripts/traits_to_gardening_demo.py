#!/usr/bin/env python3
"""
Simple one-command demo: transform a small group of plant traits (Ellenberg-like
indicator values) into practical gardening requirements. Prints:
  1) Initial traits
  2) Helpful intermediate mappings per axis
  3) Final gardening requirements per plant

Run: python3 scripts/traits_to_gardening_demo.py

Notes
-----
- Uses lightweight, transparent heuristics to map Ellenberg axes (L, M, R, N, T)
  to garden guidance. This is a didactic demo, not a predictive model.
- Ellenberg scales (typical ranges): L 1–9, M 1–12, R 1–9, N 1–9, T 1–9.
"""

from dataclasses import dataclass
from typing import Dict, Tuple, List


@dataclass
class Plant:
    name: str
    L: float  # Light
    M: float  # Moisture
    R: float  # Reaction (pH)
    N: float  # Nutrients
    T: float  # Temperature


def classify_light(L: float) -> str:
    if L >= 7:
        return "full sun (6+ hrs)"
    if 5 <= L < 7:
        return "part sun/part shade (3–6 hrs)"
    if 3 <= L < 5:
        return "bright shade/filtered light"
    return "deep shade"


def classify_moisture(M: float) -> Tuple[str, str]:
    # returns (moisture label, drainage guidance)
    if M >= 9:
        return ("wet to waterlogged", "poorly drained to saturated soils")
    if 7 <= M < 9:
        return ("moist", "consistently moist, avoid drying out")
    if 5 <= M < 7:
        return ("average", "moderately well-drained")
    if 3 <= M < 5:
        return ("dry", "well-drained, low moisture")
    return ("very dry", "very free-draining, gritty soils")


def classify_reaction(R: float) -> Tuple[str, str]:
    # returns (pH label, target range)
    if R >= 7:
        return ("alkaline leaning", "pH ~7.5–8.3")
    if 5 <= R < 7:
        return ("neutral to slightly acidic", "pH ~6.5–7.2")
    if 3 <= R < 5:
        return ("acidic", "pH ~5.0–6.3")
    return ("strongly acidic", "pH ~4.5–5.0")


def classify_nutrients(N: float) -> str:
    if N >= 7:
        return "high fertility (rich soils)"
    if 5 <= N < 7:
        return "average fertility"
    if 3 <= N < 5:
        return "low fertility"
    return "very low fertility (lean soils)"


def classify_temperature(T: float) -> str:
    if T >= 7:
        return "warmth‑loving; protect from late frost"
    if 4 <= T < 7:
        return "temperate; typical garden conditions"
    return "cold‑tolerant; likely hardy"


def watering_plan(moisture_label: str) -> str:
    plan = {
        "wet to waterlogged": "Keep constantly moist; water 3–4x/week in heat.",
        "moist": "Deep water 2–3x/week; do not let fully dry.",
        "average": "Deep water weekly; adjust for heat/rain.",
        "dry": "Deep soak every 10–14 days once established.",
        "very dry": "Minimal irrigation; only during prolonged drought."
    }
    return plan.get(moisture_label, "Deep water weekly; adjust seasonally.")


def fertility_plan(nutrient_label: str) -> str:
    if nutrient_label.startswith("high"):
        return "Incorporate 2–3 cm compost annually; monthly light feed in season."
    if nutrient_label.startswith("average"):
        return "1–2 cm compost in spring; optional mid‑season side‑dress."
    if nutrient_label.startswith("low"):
        return "Lean soils: compost lightly; avoid heavy nitrogen to prevent flop."
    return "Very lean: minimal amendments; favor mulch over fertilizer."


def pH_plan(pH_label: str) -> str:
    if pH_label.startswith("alkaline"):
        return "If local pH < 7, add garden lime gradually; avoid sulfur."
    if pH_label.startswith("neutral"):
        return "No major amendments; maintain organic matter."
    if pH_label.startswith("acidic"):
        return "Use peat‑free acidic compost; avoid lime; elemental sulfur if needed."
    return "Strongly acidic: acidify mix with pine bark/leaf mold; no lime."


def site_prep(drainage_guidance: str, moisture_label: str) -> str:
    if moisture_label in ("dry", "very dry"):
        return f"Ensure {drainage_guidance}; raise bed or add grit/sand."
    if moisture_label in ("wet to waterlogged",):
        return f"Site tolerates poor drainage; consider bog/edge conditions."
    return f"Provide {drainage_guidance}; add organic matter for structure."


def summarize_requirements(p: Plant) -> Dict[str, str]:
    light = classify_light(p.L)
    moisture_label, drainage = classify_moisture(p.M)
    pH_label, pH_range = classify_reaction(p.R)
    nutrient_label = classify_nutrients(p.N)
    temp_label = classify_temperature(p.T)

    return {
        "Exposure": light,
        "Soil moisture": f"{moisture_label}; {drainage}",
        "Watering": watering_plan(moisture_label),
        "Soil pH": f"{pH_label} ({pH_range}); {pH_plan(pH_label)}",
        "Fertility": f"{nutrient_label}; {fertility_plan(nutrient_label)}",
        "Seasonal": temp_label,
        "Site prep": site_prep(drainage, moisture_label),
    }


def print_initial_traits(plants: List[Plant]) -> None:
    print("\n=== Initial Traits (Ellenberg-like values) ===")
    header = f"{'Plant':<26}  L  M   R  N  T"
    print(header)
    print("-" * len(header))
    for p in plants:
        print(f"{p.name:<26}  {p.L:>1.0f}  {p.M:>2.0f}  {p.R:>2.0f}  {p.N:>1.0f}  {p.T:>1.0f}")


def print_intermediate(plants: List[Plant]) -> None:
    print("\n=== Intermediate Mappings (axis → category) ===")
    for p in plants:
        light = classify_light(p.L)
        moisture_label, drainage = classify_moisture(p.M)
        pH_label, pH_range = classify_reaction(p.R)
        nutrient_label = classify_nutrients(p.N)
        temp_label = classify_temperature(p.T)
        print(f"\n- {p.name}")
        print(f"  • Light (L={p.L:.0f}): {light}")
        print(f"  • Moisture (M={p.M:.0f}): {moisture_label}; {drainage}")
        print(f"  • pH (R={p.R:.0f}): {pH_label} ({pH_range})")
        print(f"  • Nutrients (N={p.N:.0f}): {nutrient_label}")
        print(f"  • Temperature (T={p.T:.0f}): {temp_label}")


def print_final_requirements(plants: List[Plant]) -> None:
    print("\n=== Final Gardening Requirements (per plant) ===")
    for p in plants:
        req = summarize_requirements(p)
        print(f"\n- {p.name}")
        for k, v in req.items():
            print(f"  • {k}: {v}")


def print_rules() -> None:
    print("\n=== Mapping Rules (summary) ===")
    print("Light L: ≥7 full sun; 5–6 part sun/shade; 3–4 bright shade; ≤2 deep shade.")
    print("Moisture M: ≥9 wet; 7–8 moist; 5–6 average; 3–4 dry; ≤2 very dry (drainage guidance accordingly).")
    print("Reaction R (pH): ≥7 alkaline (7.5–8.3); 5–6 neutral/slightly acidic (6.5–7.2); 3–4 acidic (5.0–6.3); ≤2 strongly acidic (4.5–5.0).")
    print("Nutrients N: ≥7 high; 5–6 average; 3–4 low; ≤2 very low.")
    print("Temperature T: ≥7 warmth‑loving; 4–6 temperate; ≤3 cold‑tolerant.")


def main() -> None:
    # Three illustrative plants with simple EIV-like profiles
    plants = [
        Plant(name="Lavandula angustifolia (Lavender)", L=8, M=3, R=7, N=3, T=7),
        Plant(name="Athyrium filix‑femina (Lady fern)", L=3, M=8, R=5, N=6, T=4),
        Plant(name="Rudbeckia hirta (Black‑eyed Susan)", L=7, M=5, R=5, N=5, T=6),
    ]

    print_initial_traits(plants)
    print_intermediate(plants)
    print_final_requirements(plants)
    print_rules()
    print("\nDemo complete.\n")


if __name__ == "__main__":
    main()

