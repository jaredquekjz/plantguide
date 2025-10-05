# Legacy Gemini Plant Profile Pipeline

## Purpose
This note documents the archived Gemini-driven workflow living in `plantsdatabase/archive/src_legacy`. The pipeline assembles multi-section plant dossiers using Google Gemini for web-grounded research and synthesis, then packages the results (plus optional sprite artwork) into a final JSON profile. The stages mirror the kinds of environmental descriptors that align with the five Ellenberg indicator axes, making the outputs a useful qualitative cross-check for our EIVE modelling work.

## Source Tree At A Glance
- `run_full_pipeline.py`: top-level orchestrator; controls plant selection, category scope, and stage execution with progress tracking and status files.
- `run_stage[1-8]_*.py`: individual stage drivers, each writing to a dedicated `data/<stage>` directory subtree.
- `archive_processed_plants.py`: housekeeping utility that moves fully processed source files into `archive/00_source` once a consolidated profile exists.
- `prompts/`: category-specific prompt templates used by Stages 1 and 2.
- `data/`: runtime artefacts (source species JSON seed files, stage outputs, evaluation reports, sprites, pipeline status, logs).

The core categories processed in every stage are:
1. `identity_and_physical_characteristics`
2. `distribution_and_conservation`
3. `climate_requirements`
4. `environmental_requirements`
5. `ecological_interactions`
6. `cultivation_and_propagation`
7. `uses_harvest_and_storage`

## Stage Breakdown
1. **Stage 1 – Research (`run_stage1_research.py`)**  
   - Model: `gemini-2.5-flash` running on Vertex AI with the Google Search tool enabled.  
   - Reads prompt template from `prompts/stage1_research/<category>.md`.  
   - For each plant it records the generated research narrative in `data/01_categorical_research/<category>/<slug>_text.json` and captures the full API payload (including grounding metadata) under `full_api/`.  
   - Implements jittered retries for 429/resource exhaustion errors and rejects responses that cite `vertexaisearch` domains (to enforce public web grounding).

2. **Stage 2 – Synthesis (`run_stage2_synthesis.py`)**  
   - Model: `gemini-2.5-flash`.  
   - Loads category-specific synthesis instructions (`prompts/stage2_synthesis/<category>.md`) and a JSON schema stub (`.json`).  
   - Converts Stage 1 text into a structured JSON object saved to `data/02_categorical_synthesis/<category>/<slug>.json`, inserting a provenance identifier (`<slug>:<category>`).  
   - Cleans markdown fenced blocks, validates JSON, and retries on rate limits.

3. **Stage 3 – Provenance (`run_stage3_provenance.py`)**  
   - Parses Stage 1 full API dumps, extracts unique grounding URLs, and writes `data/03_provenance_reports/<category>/<slug>.json`.  
   - Results list canonical sources (title, domain, URI) used by Gemini, supporting auditability of the synthesized claims.

4. **Stage 4 – Assessment Packet (`run_stage4_assessment.py`)**  
   - Builds `data/04_evaluation_reports/<slug>/<category>/assessment.md`, embedding the Stage 1 research JSON and Stage 2 structured output side-by-side for manual review.

5. **Stage 5 – LLM Evaluation (`run_stage5_evaluation.py`)**  
   - Optional, gated by the `--evaluate` switch in the orchestrator.  
   - Model: `gemini-2.5-pro`.  
   - Consumes the assessment packet and original synthesis prompt, then records a scored QA verdict in `evaluation.json` (score 0–10 plus narrative feedback).

6. **Stage 6 – Profile Assembly (`run_stage6_assembly.py`)**  
   - Aggregates all category JSON files into `data/plant_profiles/<slug>.json`.  
   - Top-level keys include the slug plus flattened identity fields; other categories are nested under their respective names.

7. **Stage 7 – Sprite Generation (`run_stage7_sprite_generation.py`)**  
   - Uses `openai` `gpt-image-1` to create a 1024×1024 transparent pixel-art sprite, guided by the identity description pulled from the assembled profile.  
   - Outputs raw artwork to `data/sprites/<slug>.png` (requires `OPENAI_API_KEY`).

8. **Stage 8 – Sprite Scaling (`run_stage8_sprite_scaling.py`)**  
   - Downscales sprites to 64×64 using PIL `Resampling.BOX`, writing `data/sprites_scaled/<slug>.png`.

## Orchestration Notes
- `run_full_pipeline.py` handles batching, concurrency, retries, logging, and status tracking.  
  Key arguments:  
  - `--limit`, `--start-at`, `--end-at`, `--plant-file`: control plant selection from `data/00_source/*.json`.  
  - `--category`: restricts to a single category.  
  - `--stages`: comma list (e.g. `research,synthesis`) for partial reruns.  
  - `--workers`: thread pool size for Stage 1 and 2.  
  - `--parallel-plants`: number of plant pipelines to run concurrently.  
  - `--evaluate`: toggles Stage 5.  
  - `--max-jitter-seconds`: random delay before Stage 1 execution to smooth quota usage.

- Per-plant status is persisted in `data/pipeline_status/<slug>.json`; successes are moved to `data/pipeline_status/processed/`. Logs follow the same pattern under `logs/`. A consolidated `logs/failures.log` is generated if any stage errors occur.

- `archive_processed_plants.py` can move completed source seed files into `archive/00_source/` based on the presence of a finished profile, preventing unwanted reruns.

## Required Environment
- Google Vertex AI project configured with Gemini Search grounding access: set `GOOGLE_CLOUD_PROJECT` and `GOOGLE_GENAI_USE_VERTEXAI=True`.  
- For sprite generation, export `OPENAI_API_KEY`.  
- Python dependencies include `google-genai`, `openai`, `rich`, `tqdm`, and `Pillow`; installation historically managed via the legacy environment (see repository `requirements` if reinstating the pipeline).

## Outputs And How They Help EIVE Workflows
- **Stage 1 narratives** highlight light, moisture, soil, temperature, and nutrient descriptors pulled from top-ranked public sources (floras, horticulture sites, conservation databases). These can be text-mined to validate axis-specific predictions from our GAM/XGBoost models.  
- **Stage 2 structured JSON** normalises the evidence into machine-readable slots across the seven categories, easing comparisons across species.  
- **Stage 3 provenance reports** provide traceability so we can cite or double-check any statement used in cross-validation.  
- The **assembled profile** (`data/plant_profiles/*.json`) acts as a ready-to-query knowledge base for species-level annotations that can complement Ellenberg-derived insights.  
- Sprite stages are optional for modelling, but reveal how the original project packaged plant knowledge into end-user assets.

## Validation Integration Ideas
- **Automate axis cross-checks:** Parse Stage 2 JSON (light, climate, soil folders) to label descriptors like `full sun`, `constant moisture`, or `alkaline soils`, then score alignment with our T/M/R/L predictions.
- **Weight evidence confidence:** Count unique domains in Stage 1 grounding files to decide whether a claim (e.g., drought tolerance) is strongly supported before treating it as validation evidence.
- **Harvest numeric thresholds:** Pull explicit values (°C minima, irrigation frequency, pH ranges) from Stage 1 text to benchmark model outputs that forecast extreme Ellenberg scores.
- **Surface disagreement queues:** Diff the structured summaries against Stage 2 canonical predictions; route mismatches into a review list to decide whether the model or legacy web evidence needs correction.
- **Refresh on demand:** Re-run Stage 1+2 for targeted species to capture updated horticultural guidance whenever we rerun GAM/XGBoost tuning cycles.

## Re-running The Legacy Pipeline
Example: rebuild climate and environmental summaries for a single plant.
```bash
cd /home/olier/plantsdatabase/archive/src_legacy
python run_full_pipeline.py \
  --plant-file 12.json \
  --category climate_requirements \
  --stages research,synthesis,provenance,assessment \
  --workers 2 \
  --parallel-plants 1
```
For bulk refreshes, adjust `--limit`, `--parallel-plants`, and enable `--evaluate` if automatic QA scoring is desired. Inspect `data/04_evaluation_reports/<slug>/<category>/assessment.md` plus `evaluation.json` before trusting any synthesized claims.

## Migration Considerations
- Prompts live outside the stage scripts, so updating research/synthesis rules requires editing `prompts/stage*/<category>` without touching code.  
- The pipeline assumes JSON source seeds in `data/00_source` with at least a `scientific_name`.  
- To adapt for new environmental axes (e.g., explicit Ellenberg T/M/R values), clone a category or revise the Stage 2 schema to emit those fields directly.  
- Because Gemini responses remain stochastic, keep the status/log directories under version control or archive them to monitor drift when regenerating outputs.


## Stage 7 Validation Dataset
- **Matched species:** `data/stage7_validation_mapping.csv` links the 405 Stage 2 species to legacy Gemini slugs and profile paths.
- **Qualitative EIVE bins:** generated in `data/mappings/{L,M,R,N,T}_bins.csv`. Each table stores the median 0–10 score and numeric cut-offs for the classic Ellenberg-style descriptions.
- **Combined output:** `data/stage7_validation_eive_labels.csv` merges the matched species with their EIVE scores and the qualitative labels for each axis.
- **Reproduction:**
  ```bash
  cd /home/olier/ellenberg
  python scripts/build_stage7_validation_labels.py
  ```
  This script regenerates the label dataset (and relies on the bin tables above).
  ```bash
  python src/Stage_7_Validation/run_stage7_alignment.py --species "Abies alba"
  ```
  Generates an LLM alignment verdict comparing the Stage 7 profile with the EIVE-based expectations.
