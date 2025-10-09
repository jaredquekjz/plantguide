# Stage 7 Validation - Canonical Prompts

This directory contains the canonical prompts for Stage 7 validation of EIVE (Ecological Indicator Values for Europe) reliability assessment.

## Canonical Workflow

Stage 7 relies on two prompt families: **reliability scoring** and **gardening advice**.

## Authentication Setup (Vertex AI Gemini 2.5 Pro)

All Stage 7 scripts call Gemini through **Vertex AI** using Application Default Credentials.  
Follow one of the two options before running any prompts:

1. **Reuse the Olier Farm service account key (local runs)**  
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS=/home/olier/olier-farm/backend/serviceAccountKey.json
   export GOOGLE_CLOUD_PROJECT=olier-farm
   export GOOGLE_CLOUD_LOCATION=us-central1
   ```
   These are the same credentials used by `/home/olier/olier-farm/backend` (see `backend/vertex-ai-setup.md`).

2. **Use gcloud ADC instead**  
   ```bash
   gcloud auth application-default login --project olier-farm
   export GOOGLE_CLOUD_LOCATION=us-central1
   ```

Verify that Vertex AI access is working:
```bash
python - <<'PY'
from google.auth import default
creds, proj = default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
print("ADC OK for project:", proj)
PY
```
If this fails, fix credentials before attempting the Stage 7 generators.

### Reliability Prompts

1. **`prompt_alignment_baskets.md`**  
   **Purpose**: Assign High/Medium/Low reliability baskets for each EIVE axis.  
   **Used by**: `/home/olier/ellenberg/scripts/align_stage7_baskets.py`  
   **Output**: `/home/olier/ellenberg/results/stage7_alignment_baskets/{slug}.json`  
   **Summary**: Enforces the three-line justification format that contrasts Stage 7 evidence with expert expectations for axes `L`, `M`, `R`, `N`, and `T`.

2. **`prompt_alignment_verdict.md`**  
   **Purpose**: Produce verdicts matching web evidence with expert EIVE values.  
   **Used by**: `/home/olier/ellenberg/scripts/align_stage7_profiles.py`  
   **Output**: Alignment verdict blocks stored alongside Stage 7 profiles.  
   **Summary**: Confirms whether each evidence fragment supports, partially supports, conflicts, or is insufficient relative to the EIVE scales.

3. **`prompt_eive_mapping.md`**  
   **Purpose**: Map normalized descriptors back to Ellenberg axes.  
  **Used by**: `/home/olier/ellenberg/scripts/normalize_stage7_profiles.py`  
   **Output**: Normalized descriptor JSON (Stage 7 evidence packets).  
   **Summary**: Forces every descriptor to land on a canonical axis label so subsequent prompts can reason over consistent bins.

### Gardening Advice Prompts

Generated from the final encyclopedia profiles in `/home/olier/ellenberg/data/encyclopedia_profiles/{slug}.json` (see `docs/ENCYCLOPEDIA_DATA_AND_COMPONENTS.md` for data lineage):

4. **`prompt_gardening_climate.md`**  
   **Purpose**: Turn `bioclim` summaries plus `EIVE L/M/T` into light, moisture, and temperature tips.  
   **Used by**: `/home/olier/ellenberg/scripts/generate_stage7_gardening_advice.py`  
   **Summary**: Requests 3–5 JSON-formatted recommendations, each citing the relevant Ellenberg labels and climate statistics, with optional warnings based on reliability scores.

5. **`prompt_gardening_soil.md`**  
   **Purpose**: Translate SoilGrids depth metrics and `EIVE R/N` into soil preparation guidance.  
   **Used by**: `/home/olier/ellenberg/scripts/generate_stage7_gardening_advice.py`  
   **Summary**: Demands actionable tips covering pH management, fertility amendments, and structure cues, grounded in depth-layer trends and reliability labels.

6. **`prompt_gardening_interactions.md`**  
   **Purpose**: Surface pollinator, herbivore, and pathogen advice from GloBI top-partner lists.  
   **Used by**: `/home/olier/ellenberg/scripts/generate_stage7_gardening_advice.py`  
   **Summary**: Requires at least one recommendation per interaction category, repeating partner strings and record counts verbatim to anchor scouting or companion-planting actions.

7. **`prompt_gardening_strategy_services.md`**  
   **Purpose**: Connect CSR percentages and ecosystem service ratings to planting design roles.  
   **Used by**: `/home/olier/ellenberg/scripts/generate_stage7_gardening_advice.py`  
   **Summary**: Guides Gemini toward 3–4 strategy statements that tie CSR balance, ecosystem service strengths, and Ellenberg context into community planting advice.

### Gemini Input Bundles

- **Climate advice**: Scientific/common names, slug, `EIVE` axes `L/M/T` with labels, associated reliability verdicts, and the full `bioclim` temperature/precipitation/aridity summary (including occurrence coverage flags).
- **Soil advice**: Same identifiers, `EIVE` axes `R/N` with labels, reliability verdicts, and the entire `soil` block (depth-layer pH, texture metrics, nutrient capacity, nitrogen, organic matter, bulk density, and sampling quality flags).
- **Ecological interactions advice**: Identifiers plus per-category (`pollination`, `herbivory`, `pathogen`) record counts, partner counts, and the top 10 partner strings (truncated to safeguard prompt length). No additional Stage 7 relationship data is included.
- **Strategy & services advice**: Identifiers, `csr` percentages, complete `eco_services` rating/confidence matrix, and all `EIVE` values/labels so the model can cross-reference site fit.

## Complete Pipeline

1. **Normalize profiles**: `normalize_stage7_profiles.py` → uses `prompt_eive_mapping.md`
2. **Generate baskets**: `align_stage7_baskets.py` → uses `prompt_alignment_baskets.md`
3. **Merge into profiles**: `merge_baskets_into_profiles.py` → adds reliability data to encyclopedia
4. **Upload to Firestore**: `src/Stage_8_Encyclopedia/upload_test_profiles.py` → deploys to production
5. **(Optional) Build gardening advice**: `generate_stage7_gardening_advice.py` → calls all four gardening prompts and stores structured tips per species

## Archived Scripts

Non-canonical scripts have been moved to `archived_scripts/`:
- `match_legacy_profiles.py` - Legacy profile matching
- `predict_stage2_best_models.R` - Stage 2 R predictions
- `run_stage7_alignment.py` - Old alignment runner

## Key Outputs

- **Baskets JSON**: `/home/olier/ellenberg/results/stage7_alignment_baskets/{slug}.json`
- **Summary CSV**: `/home/olier/ellenberg/results/stage7_alignment_baskets_summary.csv`
- **Updated Profiles**: `/home/olier/ellenberg/data/encyclopedia_profiles/{slug}.json`
- **Gardening Advice JSON**: `/home/olier/ellenberg/results/stage7_gardening_advice/{slug}.json` (contains `*_advice` blocks for climate, soil, ecological interactions, and strategy/services)

The reliability data includes both `reliability_basket` (High/Medium/Low) and `reliability_reason` (detailed explanation) fields that are displayed in the Olier Farm encyclopedia interface.
