# Stage 4: NLP-Based Organism Categorization Pipeline

## Overview

Dual-pipeline approach for organism categorization using iNaturalist vernacular names with vector-based semantic classification (Pipeline B) and frequency-based noun extraction (Pipeline A). Agreement between pipelines ensures high-confidence category assignments.

## Current Status

**Completed:** Steps 1-3 (Data preparation, category generation, vector classification)
**Coverage:** 91.2% of genera with English vernaculars (6,978/7,648 genera)
**Pending:** Steps 4-8 (Frequency extraction, agreement checking, manual review, organism labeling, validation)

## Full Pipeline Architecture

```
Target Organisms (13,416 genera)
    ├─ Animals: 10,549 genera (GloBI interactions)
    └─ Plants: 2,910 genera (11.7K species dataset)
        ↓
Step 1: Aggregate iNaturalist Vernaculars ✅
    → Filter to English vernaculars
    → 7,648 genera with English names (57% coverage)
        ↓
Step 2: Generate Functional Categories ✅
    → 241 broad, distinct categories
    → Avoid overlapping subcategories
        ↓
┌───────────────────────────────────────────┐
│     DUAL PIPELINE EXECUTION               │
│                                           │
│  Step 3: Vector Classification ✅         │
│  (Python + vLLM + KaLM embeddings)       │
│  → 91.2% categorized (6,978 genera)      │
│                                           │
│  Step 4: Frequency Extraction ⏳          │
│  (R + udpipe + POS tagging)              │
│  → Extract dominant nouns                 │
└───────────────────────────────────────────┘
        ↓
Step 5: Agreement Checking ⏳
    ├─ Both agree → Accept (high confidence, ~70-80%)
    ├─ Single method → Accept (medium confidence, ~15-20%)
    └─ Disagree → Manual review (~5-10%)
        ↓
Step 6: Manual Review ⏳
    → Review disagreement cases
    → Create final genus→category mapping
        ↓
Step 7: Label All Organisms ⏳
    → Apply genus mapping to 29,846 organisms
    → Handle plants vs animals differently
        ↓
Step 8: Validation & Reports ⏳
    → Coverage statistics
    → Agreement metrics
    → Category distribution
```

## Step 1: Aggregate iNaturalist Vernaculars ✅

**Script:** `src/Stage_4/taxonomy/nlp/01_aggregate_inat_by_genus.R`

**Objective:** Join iNaturalist vernaculars with target genera and aggregate by genus.

**Input:**
- `data/taxonomy/target_genera.parquet` (13,416 combined genera from organisms + plants)
- `data/inaturalist/taxa.csv` (iNaturalist taxonomy)
- `data/taxonomy/inat_vernaculars_all_languages.parquet` (multilingual vernaculars)

**Process:**
1. Load target genera (combined from organisms_vernacular_final.parquet + bill_with_csr_ecoservices_11711.csv)
2. Join with iNaturalist taxa to get taxon IDs
3. Filter to English vernaculars only (`language = 'en'`)
4. Aggregate vernaculars by genus (semicolon-separated string)
5. Count vernaculars and languages per genus

**Output:** `data/taxonomy/genus_vernacular_aggregations.parquet`
- 7,648 genera with English vernaculars
- Columns: genus, kingdom, vernaculars_all, n_vernaculars, n_unique_vernaculars, n_languages

**Results:**
- 7,648 genera with English vernaculars (57% of 13,416 targets)
- 118,044 English vernacular names
- Median: 4 vernaculars per genus
- Kingdom breakdown: 5,066 Animalia, 2,582 Plantae

**Run:**
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_4/taxonomy/nlp/01_aggregate_inat_by_genus.R
```

## Step 2: Generate Functional Categories ✅

**Script:** `src/Stage_4/taxonomy/nlp/02_generate_functional_categories.R`

**Objective:** Create curated list of broad, distinct functional categories for vector matching.

**Process:**
1. Define 241 functional categories across ecological domains
2. Avoid overlapping subcategories (e.g., just "bees", not 10 types of bees)
3. Validate for duplicates
4. Save with kingdom and functional_group metadata

**Categories:**
- **Insects** (~70): pollinators (bees, butterflies, moths, flies), herbivores (aphids, beetles, leafhoppers), predators (ladybugs, lacewings), decomposers (termites, dung beetles), other (ants, wasps, crickets)
- **Other Animals** (~70): birds (songbirds, raptors, waterfowl, corvids), mammals (bats, rodents, rabbits, deer), reptiles (lizards, snakes, turtles), amphibians (frogs, salamanders), arachnids (spiders, scorpions), myriapods, mollusks, annelids
- **Plants** (~100): trees (oaks, maples, pines, spruces), shrubs (roses, rhododendrons, blueberries), herbaceous (grasses, sedges, wildflowers), ferns, vines, fruits, vegetables, herbs, aquatic, bryophytes, lichens, algae, succulents

**Output:** `data/taxonomy/functional_categories.parquet`
- 241 categories × 3 columns (category, kingdom, functional_group)

**Run:**
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_4/taxonomy/nlp/02_generate_functional_categories.R
```

## Step 3: Vector Classification (Pipeline B) ✅

**Script:** `src/Stage_4/taxonomy/nlp/03_vector_classification_vllm.py`

**Objective:** Classify genera using semantic vector similarity with SOTA embedding model.

**Model:** KaLM-Embedding-Gemma3-12B-2511 (Tencent)
- **Rank:** #1 on MMTEB leaderboard (Nov 2025)
- **Architecture:** 11.76B parameters, 3840-dimensional embeddings
- **Deployment:** vLLM Docker on NVIDIA RTX 6000 Ada (48GB VRAM)
- **Server:** localhost:8000 (OpenAI-compatible API)

**Process:**
1. **Create category prototypes:** Embed all 241 category names
2. **Batch processing:** Process genera in batches of 128
3. **Embed vernaculars:** Get embeddings for each genus's vernacular string
4. **Cosine similarity:** Compute similarity between each genus and all categories (vectorized)
5. **Threshold filtering:** Accept matches with similarity ≥ 0.5
6. **Store top-3:** Save top 3 category matches with scores for validation

**Output:** `data/taxonomy/vector_classifications_kalm.parquet`
- 7,648 genera × 5 columns
- Columns: genus, vector_category, vector_similarity, vector_top3_categories, vector_top3_scores

**Results:**
- **Categorized:** 6,978 genera (91.2%)
- **Uncategorized:** 670 genera (8.8%)
- **Mean similarity:** 0.623 (well above 0.5 threshold)
- **Processing time:** 2.5 minutes (50 genera/second)
- **Top categories:** moths (852), tulip trees (194), hoverflies (191), ground beetles (184), aphids (171)

**Prerequisites:**
```bash
# Start vLLM Docker server
docker run -d --runtime nvidia --gpus all \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  -p 8000:8000 --ipc=host \
  vllm/vllm-openai:latest \
  --model tencent/KaLM-Embedding-Gemma3-12B-2511 \
  --revision CausalLM --task embed \
  --enforce-eager --trust-remote-code \
  --dtype bfloat16 --gpu-memory-utilization 0.95 \
  --max-model-len 32768
```

**Run:**
```bash
/home/olier/miniconda3/envs/AI/bin/python \
  src/Stage_4/taxonomy/nlp/03_vector_classification_vllm.py
```

## Step 4: Frequency Extraction (Pipeline A) ⏳ PENDING

**Script:** `src/Stage_4/taxonomy/nlp/04_frequency_extraction.R` (to be created)

**Objective:** Extract dominant category terms from vernacular names using linguistic analysis.

**Tool:** udpipe (R NLP library)
- Tokenization, lemmatization, POS tagging
- Pure R implementation (no Python dependency)
- Universal Dependencies English model

**Process:**
1. **Setup udpipe:** Load English language model
2. **Tokenize vernaculars:** Parse each genus's vernacular string
3. **POS tagging:** Identify parts of speech
4. **Extract nouns:** Filter for NOUN tags, use lemma (singular form)
5. **Frequency analysis:** Count noun occurrences across vernaculars
6. **Quality filters:**
   - Exclude generic terms: "insect", "animal", "plant", "tree", "flower"
   - Exclude modifiers: "common", "european", "great", "small"
   - Minimum frequency threshold (e.g., >50% of vernaculars)
7. **Pluralization:** Convert singular noun to plural category (bee → bees)

**Output:** `data/taxonomy/frequency_classifications.parquet`
- Columns: genus, freq_category, freq_noun, freq_count, freq_pct

**Expected Results:**
- ~80-85% extraction rate
- Independent validation of vector classification

## Step 5: Agreement Checking ⏳ PENDING

**Script:** `src/Stage_4/taxonomy/nlp/05_agreement_checking.R` (to be created)

**Objective:** Compare Pipeline A (frequency) and Pipeline B (vector) results.

**Agreement Logic:**

1. **Both agree:** High confidence, accept category
   - Expected: 70-80% of genera
   - Status: "accepted", confidence: "high"

2. **Single method:** Medium confidence, accept single result
   - Expected: 15-20% of genera
   - Status: "accepted", confidence: "medium"

3. **Disagree:** Flag for manual review
   - Expected: 5-10% of genera
   - Status: "needs_review", confidence: "low"
   - Include both candidates for user decision

4. **Both failed:** Uncategorized
   - Status: "uncategorized", confidence: "low"
   - Category: "other"

**Output:** `data/taxonomy/genus_categories_dual.parquet`
- Columns: genus, category, method, freq_result, vector_result, vector_similarity, status, confidence, needs_review

## Step 6: Manual Review ⏳ PENDING

**Script:** `src/Stage_4/taxonomy/nlp/06_manual_review.R` (to be created)

**Objective:** Review disagreement cases and create final genus→category mapping.

**Process:**
1. **Export disagreements:** Filter genera where status = "needs_review"
2. **Create review queue:** CSV with genus, freq_result, vector_result, similarity, example_vernaculars
3. **User review:** Manual categorization of ~5-10% of genera
4. **Import decisions:** Read user-created decisions file
5. **Merge results:** Combine auto-accepted + manual decisions
6. **Final mapping:** Create authoritative genus→category lookup

**Output:**
- `reports/manual_review_queue.csv` (for user review)
- `reports/manual_review_decisions.csv` (user-created)
- `data/taxonomy/genus_to_category_final.parquet` (final mapping)

## Step 7: Label Organisms ⏳ PENDING

**Script:** `src/Stage_4/taxonomy/nlp/07_label_organisms.R` (to be created)

**Objective:** Apply genus→category mapping to all 29,846 organisms.

**Input:**
- `data/taxonomy/organisms_vernacular_final.parquet` (29,846 organisms)
- `data/taxonomy/genus_to_category_final.parquet` (genus mapping)

**Process:**
1. **Extract genus:** Parse genus from scientific_name
2. **Join mapping:** Left join genus_to_category on genus
3. **Handle plants vs animals:**
   - **Plants:** Use vernacular_name_en as display category (more specific)
   - **Animals:** Use derived category from NLP (aggregated)
4. **Assign organism_category:** Final category for each organism

**Output:** `data/taxonomy/organisms_categorized_comprehensive.parquet`
- All 29,846 organisms with new columns: genus, category, organism_category

## Step 8: Validation & Reports ⏳ PENDING

**Script:** `src/Stage_4/taxonomy/nlp/08_validate_categories.R` (to be created)

**Objective:** Generate validation reports and quality metrics.

**Validation Metrics:**

1. **Coverage:**
   - % organisms categorized (non-"other")
   - By kingdom (Animalia, Plantae)
   - By source dataset

2. **Agreement:**
   - % dual agreement (Pipeline A + B)
   - % single method only
   - % manual review needed

3. **Category Distribution:**
   - Top 20 categories by organism count
   - Category size distribution (avoid over-concentration)
   - Kingdom-specific distributions

4. **Quality Checks:**
   - Genera with low similarity scores (<0.5)
   - Category-genus coherence spot checks
   - Vernacular-category alignment validation

**Output Reports:**
- `reports/category_coverage.csv`
- `reports/category_distribution.csv`
- `reports/agreement_statistics.csv`
- `reports/quality_checks.csv`

## Master Orchestration Script

**Script:** `src/Stage_4/taxonomy/nlp/run_complete_nlp_pipeline.sh`

**Executes all 8 steps sequentially with error handling.**

**Prerequisites Check:**
- vLLM server running (localhost:8000)
- R environment (`/home/olier/ellenberg/.Rlib`)
- Python conda AI environment
- Required packages installed

**Execution Flow:**
```bash
# Step 1: R - Aggregate iNaturalist vernaculars
# Step 2: R - Generate functional categories
# Step 3: Python - Vector classification via vLLM
# Step 4: R - Frequency extraction via udpipe
# Step 5: R - Agreement checking
# Step 6: R - Manual review (pauses for user input)
# Step 7: R - Label all organisms
# Step 8: R - Generate validation reports
```

**Run:**
```bash
bash src/Stage_4/taxonomy/nlp/run_complete_nlp_pipeline.sh
```

## Current Coverage & Results

**Genera Coverage:**
- **Target genera:** 13,416 (10,549 animals + 2,910 plants)
- **With English vernaculars:** 7,648 (57%)
- **Categorized by vector:** 6,978 (91.2% of vernacular genera, 52% of all targets)
- **Without English vernaculars:** 5,768 (43%)
  - With other languages: 1,908 (zh-CN, ja, ko, ru, European)
  - No vernaculars at all: 3,975

**Quality Metrics:**
- **Mean cosine similarity:** 0.623
- **Median similarity:** 0.620
- **Similarity threshold:** 0.5

**Top 10 Categories:**
1. moths: 852 genera (11.1%)
2. tulip trees: 194 (2.5%)
3. hoverflies: 191 (2.5%)
4. ground beetles: 184 (2.4%)
5. aphids: 171 (2.2%)
6. grasses: 155 (2.0%)
7. leafhoppers: 154 (2.0%)
8. assassin bugs: 136 (1.8%)
9. weevils: 131 (1.7%)
10. caterpillars: 131 (1.7%)

## Limitations & Considerations

1. **English-only approach:**
   - 43% of genera have no English vernaculars
   - Bias toward North American/European taxa
   - Community-contributed quality variation

2. **Category granularity:**
   - Broad categories (241 total)
   - Trade-off: semantic clarity vs ecological detail
   - Some nuance lost in aggregation

3. **iNaturalist bias:**
   - Charismatic/accessible species overrepresented
   - Rare/cryptic species underrepresented
   - Observer accessibility patterns

4. **Uncategorized organisms:**
   - 5,768 genera without English vernaculars
   - Options: Use scientific names, family-level fallback, or leave uncategorized

## Next Immediate Steps

1. **Create Step 4 script:** Frequency extraction using udpipe
2. **Create Step 5 script:** Agreement checking logic
3. **Test dual-pipeline:** Run Steps 4-5 on sample genera
4. **Create Steps 6-8:** Manual review, organism labeling, validation
5. **Full pipeline test:** Execute complete run_complete_nlp_pipeline.sh
6. **Update Rust guild scorer:** Use organism_category column from final output

## Files Generated

```
data/taxonomy/
├── target_genera.parquet                      # 13,416 combined genera ✅
├── genus_vernacular_aggregations.parquet      # 7,648 with English vernaculars ✅
├── functional_categories.parquet              # 241 categories ✅
├── vector_classifications_kalm.parquet        # 6,978 categorized (Pipeline B) ✅
├── frequency_classifications.parquet          # Pipeline A (pending) ⏳
├── genus_categories_dual.parquet              # Agreement results (pending) ⏳
├── genus_to_category_final.parquet            # Final mapping (pending) ⏳
└── organisms_categorized_comprehensive.parquet # 29,846 labeled organisms (pending) ⏳

reports/
├── manual_review_queue.csv                    # For user review (pending) ⏳
├── manual_review_decisions.csv                # User decisions (pending) ⏳
├── category_coverage.csv                      # Validation (pending) ⏳
├── category_distribution.csv                  # Validation (pending) ⏳
├── agreement_statistics.csv                   # Validation (pending) ⏳
└── quality_checks.csv                         # Validation (pending) ⏳
```

## Dependencies

**R Packages:**
- duckdb (data processing)
- arrow (parquet I/O)
- dplyr, stringr, purrr, tibble, tidyr
- udpipe (NLP - for Step 4)

**Python Packages:**
- openai (vLLM client)
- pandas, numpy
- scikit-learn (cosine_similarity)
- tqdm

**Infrastructure:**
- vLLM Docker (GPU inference server)
- NVIDIA GPU with 48GB VRAM
- R custom library: `/home/olier/ellenberg/.Rlib`
- Python conda environment: `/home/olier/miniconda3/envs/AI`
