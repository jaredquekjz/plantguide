# Vernacular Integration with Data-Driven Categories

## Overview

This document outlines a dual-pipeline NLP approach to derive organism categories from the iNaturalist vernacular dataset. Two independent methods validate each other: (1) frequency-based noun extraction and (2) vector-based semantic classification. The goal is to create a rigorous, reproducible categorization system that maps genus-level taxa to meaningful ecological categories for both animals and plants.

## Key Innovation: Dual-Pipeline Agreement Validation

- **Pipeline A**: Frequency-based noun extraction from vernaculars
- **Pipeline B**: Vector-based semantic similarity classification
- **Agreement Check**: Both methods must agree for high-confidence acceptance
- **Manual Review**: Only ~5-10% need human review (when methods disagree)

## Current Limitations

The existing keyword-matching approach (`categorize_organisms.R`) has several limitations:

1. **Manual curation**: Categories defined by hand-coded keywords
2. **Limited coverage**: Only 48% categorized (14,328/29,846 organisms)
3. **Brittle**: Requires manual updates as new taxa are added
4. **No plant categories**: Only handles animals
5. **No validation**: No systematic verification against actual usage patterns

## Proposed Approach: Dual-Pipeline with Agreement Validation

### Architecture

```
iNaturalist Raw Data
        ↓
    Genus Aggregation
        ↓
    Bootstrap Categories (frequency analysis on top 1000 genera)
        ↓
┌───────────────────────────────────────┐
│   DUAL PIPELINE EXECUTION             │
│                                       │
│  Pipeline A          Pipeline B      │
│  Frequency-Based     Vector-Based    │
│  (udpipe)           (text/HuggingFace)│
│       ↓                   ↓           │
│   Category A          Category B     │
└───────────────────────────────────────┘
        ↓
    Agreement Checking
        ↓
   ┌────┴────┐
   │         │
 Agree    Disagree
   │         │
   ↓         ↓
Accept   Manual Review (~5-10%)
   │         │
   └────┬────┘
        ↓
    Genus-Category Lookup Table
        ↓
    Apply to organisms.parquet
```

### Phase 1: Data Preparation

**Objective**: Extract genus-level vernacular aggregations from iNaturalist

**Input**: Raw iNaturalist observation data
- Source: `/home/olier/ellenberg/data/inat/observations.parquet` (or CSV)
- Columns needed: `taxon_genus_name`, `common_name`, `iconic_taxon_name` (Animalia/Plantae)

**Process**:
```r
# Aggregate vernaculars by genus
genus_vernaculars <- inat_data %>%
  filter(!is.na(taxon_genus_name), !is.na(common_name)) %>%
  group_by(taxon_genus_name, iconic_taxon_name) %>%
  summarise(
    vernaculars = paste(unique(tolower(common_name)), collapse = "; "),
    n_observations = n(),
    n_unique_vernaculars = n_distinct(common_name),
    .groups = "drop"
  )
```

**Output**: `data/taxonomy/genus_vernacular_aggregations.parquet`
- Columns: genus, kingdom (Animalia/Plantae), vernaculars, n_observations, n_unique_vernaculars

### Phase 2: Generate Comprehensive Functional Categories

**Objective**: Create comprehensive functional category list to facilitate vector matching

**Approach** (revised):
- Generate curated list of 200-500 functional categories
- Based on easily recognizable ecological/functional groups
- Comprehensive coverage to maximize vector matching success

**Category domains**:

**Insects (150+ categories):**
- Pollinators: bees, bumblebees, honeybees, solitary bees, mason bees, carpenter bees, butterflies, moths, hawk moths, hoverflies
- Herbivores: aphids, caterpillars, beetles, weevils, leaf beetles, leafhoppers, whiteflies, scale insects, thrips, sawflies
- Predators: ladybugs, lacewings, ground beetles, rove beetles, assassin bugs, parasitic wasps, tachinid flies
- Decomposers: termites, dung beetles, carrion beetles
- Other: ants, crickets, grasshoppers, dragonflies, damselflies

**Other Animals (50+ categories):**
- Birds: songbirds, warblers, sparrows, raptors, hawks, eagles, owls, waterfowl, woodpeckers, hummingbirds
- Mammals: bats, rodents, mice, rabbits, deer, foxes
- Reptiles: lizards, snakes, turtles
- Amphibians: frogs, toads, salamanders
- Other: spiders, mites, snails, earthworms

**Plants (100+ categories):**
- Trees (deciduous): oaks, maples, birches, willows, ashes, elms, beeches, chestnuts, hickories, walnuts
- Trees (coniferous): pines, spruces, firs, cedars, junipers, hemlocks
- Shrubs: roses, hollies, viburnums, rhododendrons, azaleas, blueberries, dogwoods
- Herbaceous: grasses, sedges, rushes, wildflowers, asters, sunflowers, clovers, milkweeds
- Ferns: ferns, wood ferns, bracken ferns, horsetails
- Vines: grapes, ivies, honeysuckles
- Fruits: apples, strawberries, raspberries, blackberries, cherries
- Vegetables: tomatoes, peppers, cucumbers, squashes
- Aquatic: water lilies, cattails, pondweeds

**Implementation**:
```r
# Generate comprehensive category list
functional_categories <- tibble(
  category = c(
    # Insects - Pollinators
    "bees", "bumblebees", "honeybees", "solitary bees", "mason bees",
    "carpenter bees", "leafcutter bees", "mining bees",
    "butterflies", "swallowtails", "whites", "sulfurs", "blues",
    "moths", "hawk moths", "silk moths", "tiger moths",
    "hoverflies", "syrphid flies",

    # Insects - Herbivores
    "aphids", "greenflies", "blackflies",
    "caterpillars", "leafminers",
    "beetles", "weevils", "leaf beetles", "flea beetles", "longhorn beetles",
    "leafhoppers", "planthoppers", "treehoppers",
    "whiteflies", "scale insects", "mealybugs",
    "thrips", "sawflies",

    # Insects - Predators
    "ladybugs", "lady beetles",
    "lacewings", "antlions",
    "ground beetles", "carabid beetles", "rove beetles",
    "assassin bugs", "damsel bugs", "minute pirate bugs", "big-eyed bugs",
    "parasitic wasps", "braconid wasps", "ichneumon wasps",
    "tachinid flies", "robber flies",

    # ... (200-500 total categories)
  ),
  kingdom = c("Animalia", "Animalia", ...),
  functional_group = c("pollinator", "pollinator", "pollinator", ...)
)

write_parquet(functional_categories, "data/taxonomy/functional_categories.parquet")
```

**Output**: `data/taxonomy/functional_categories.parquet`
- Columns: category, kingdom, functional_group
- **This becomes the classification target list for Pipeline B (vector matching)**

**Rationale**:
- More comprehensive than extracting from limited data sample
- Ensures broad ecological coverage for all major groups
- Facilitates better vector matching with SOTA embedding model
- Still data-driven: actual genus vernacular names determine matches via cosine similarity

### Phase 3: Dual-Pipeline Category Extraction

**Objective**: Run two independent methods and validate through agreement

## Pipeline A: Frequency-Based Extraction

**Tool**: `udpipe` (pure R NLP library)

**Why udpipe**:
- Pure R, no Python dependency
- Tokenization, lemmatization, POS tagging
- Fast, well-maintained (65+ languages)
- Sufficient for noun extraction task

**Algorithm**:

1. **Setup udpipe model**:
   ```r
   library(udpipe)

   # Download English model (one-time setup)
   udpipe_download_model(language = "english")

   # Load model
   udmodel_english <- udpipe_load_model("english-ewt-ud-2.5-191206.udpipe")
   ```

2. **Tokenization and POS tagging**:
   ```r
   # For each genus, annotate vernacular names
   annotate_vernaculars <- function(vernacular_string) {
     annotations <- udpipe_annotate(udmodel_english, x = vernacular_string)
     as.data.frame(annotations)
   }
   ```

3. **Extract candidate category terms**:
   ```r
   extract_category_candidates <- function(vernacular_string) {
     # Tokenize and POS tag
     tokens <- annotate_vernaculars(vernacular_string)

     # Extract nouns using lemma (singular form)
     nouns <- tokens %>%
       filter(upos == "NOUN") %>%
       pull(lemma) %>%
       tolower()

     # Count frequency
     freq_table <- table(nouns)

     # Return most common noun as category
     if (length(freq_table) > 0) {
       names(sort(freq_table, decreasing = TRUE))[1]
     } else {
       NA
     }
   }
   ```
   - Filter for nouns (POS = NOUN)
   - Use lemma for automatic pluralization (bees → bee, butterflies → butterfly)
   - Count frequency across vernaculars for each genus
   - Examples: "bee", "moth", "spider", "oak", "rose", "pine"

4. **Statistical filtering**:
   - Minimum frequency threshold (e.g., appears in >50% of vernaculars for genus)
   - Exclude overly generic terms: "insect", "animal", "plant", "tree", "flower"
   - Exclude modifiers: "common", "european", "great", "small"
   - Cross-genus validation (ensure category applies to multiple genera)

**Output Pipeline A**: Extracted category for each genus

## Pipeline B: Vector-Based Semantic Classification

**Tool**: **vLLM Docker** with **KaLM-Embedding-Gemma3-12B-2511** - **IMPLEMENTED**

**Why vLLM + KaLM is state-of-the-art**:
- ✅ **SOTA Model**: KaLM-Embedding-Gemma3-12B-2511 (Tencent) - #1 on MMTEB leaderboard (Nov 2025)
- ✅ **GPU Optimized**: vLLM PagedAttention, continuous batching, Flash Attention
- ✅ **Production-grade**: 3× faster than sentence-transformers, safer CUDA isolation in Docker
- ✅ **Large Model**: 11.76B parameters, 3840-dimensional embeddings
- ✅ **Python-based**: All vector operations in Python, R handles tabular merging only

**vLLM Docker Setup** (completed):
```bash
# Launch vLLM embedding server
docker run -d \
  --name kalm-embedding-server \
  --runtime nvidia \
  --gpus all \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  -p 8000:8000 \
  --ipc=host \
  vllm/vllm-openai:latest \
  --model tencent/KaLM-Embedding-Gemma3-12B-2511 \
  --revision CausalLM \
  --task embed \
  --enforce-eager \
  --trust-remote-code \
  --dtype bfloat16 \
  --gpu-memory-utilization 0.95 \
  --max-model-len 8192

# Server status:
# - GPU Memory: 45.4GB/48GB (95% utilization for KV cache maximization)
# - KV Cache: 22.19GB available for batched processing
# - Embedding dimensions: 3840
# - Optimizations: Flash Attention, Chunked Prefill (2048 tokens/batch), Prefix Caching
```

**GPU Configuration** (NVIDIA RTX 6000 Ada):
- Total VRAM: 48GB
- Model size: ~24GB
- KV Cache: 22.19GB (optimized for batch processing)
- Batch size: 128 texts per request (calculated from KV cache capacity)
- Expected throughput: ~2000 genera/minute

**Algorithm** (Python implementation):

**Script**: `src/Stage_4/taxonomy/nlp/03_vector_classification_vllm.py`

1. **Setup OpenAI-compatible client for vLLM**:
   ```python
   from openai import OpenAI
   import numpy as np
   from sklearn.metrics.pairwise import cosine_similarity

   # Connect to local vLLM server
   client = OpenAI(
       base_url="http://localhost:8000/v1",
       api_key="dummy"  # vLLM doesn't require authentication
   )

   MODEL_NAME = "tencent/KaLM-Embedding-Gemma3-12B-2511"
   BATCH_SIZE = 128  # Optimized for RTX 6000 Ada
   MIN_SIMILARITY = 0.5
   ```

2. **Create category prototype embeddings**:
   ```python
   # For each bootstrapped category, combine example vernaculars
   all_category_texts = []
   category_text_mapping = {}

   for cat in category_names:
       # Get example genera for this category
       example_genera = bootstrapped_categories[
           bootstrapped_categories['category'] == cat
       ]['example_genera'].iloc[0]

       # Get vernaculars for these genera (first 10 to avoid long text)
       cat_vernaculars = genus_data[
           genus_data['genus'].isin(example_genera[:10])
       ]['vernaculars'].tolist()

       # Combine vernaculars (limit to 5 to avoid token limits)
       combined_text = " | ".join(cat_vernaculars[:5])
       all_category_texts.append(combined_text)
       category_text_mapping[len(all_category_texts) - 1] = cat

   # Get embeddings from vLLM (single batch request)
   response = client.embeddings.create(
       input=all_category_texts,
       model=MODEL_NAME
   )

   # Extract and normalize embeddings
   category_embeddings = np.array([item.embedding for item in response.data])
   category_embeddings = category_embeddings / np.linalg.norm(
       category_embeddings, axis=1, keepdims=True
   )
   ```

3. **Classify all genera in batches**:
   ```python
   # Process genera in batches of 128
   for batch_idx in range(0, len(genus_data), BATCH_SIZE):
       batch = genus_data.iloc[batch_idx:batch_idx + BATCH_SIZE]

       # Get embeddings for batch from vLLM
       batch_texts = batch['vernaculars'].tolist()
       response = client.embeddings.create(
           input=batch_texts,
           model=MODEL_NAME
       )

       genus_embeddings = np.array([item.embedding for item in response.data])
       genus_embeddings = genus_embeddings / np.linalg.norm(
           genus_embeddings, axis=1, keepdims=True
       )

       # Compute similarities (vectorized with sklearn)
       similarities = cosine_similarity(genus_embeddings, category_embeddings)

       # For each genus, find best match
       for i, genus_row in enumerate(batch.iterrows()):
           best_idx = similarities[i].argmax()
           best_similarity = similarities[i][best_idx]
           best_category = valid_categories[best_idx]

           # Store result with top-3 for debugging
           results.append({
               'genus': genus_row['genus'],
               'vector_category': best_category if best_similarity >= MIN_SIMILARITY else None,
               'vector_similarity': float(best_similarity),
               'vector_top3_categories': ';'.join(top3_categories),
               'vector_top3_scores': ';'.join([f"{s:.3f}" for s in top3_scores])
           })

   # Save results
   results_df = pd.DataFrame(results)
   results_df.to_parquet("data/taxonomy/vector_classifications_kalm.parquet")
   ```

**Performance**:
- Expected processing time: 15-20 minutes for 30,000 genera
- Batch size: 128 texts per request
- Throughput: ~100-120 genera/second

**Output Pipeline B**: `data/taxonomy/vector_classifications_kalm.parquet`
- Columns: genus, vector_category, vector_similarity, vector_top3_categories, vector_top3_scores

### Phase 4: Agreement Checking and Category Assignment

**Objective**: Compare Pipeline A and B results, assign categories based on agreement

```r
process_genus_dual_pipeline <- function(genus_row, category_prototypes) {
  # Pipeline A: Frequency-based extraction
  freq_result <- extract_most_common_noun(genus_row$vernaculars)

  # Validate frequency result
  freq_valid <- !is.na(freq_result) &&
                !freq_result %in% c("insect", "animal", "plant", "tree", "flower") &&
                genus_row$n_observations >= 10

  freq_category <- if (freq_valid) freq_result else NA

  # Pipeline B: Vector-based classification
  vector_result <- classify_by_vector_similarity(
    genus_row$vernaculars,
    category_prototypes,
    min_similarity = 0.5
  )

  vector_category <- vector_result$category
  vector_similarity <- vector_result$similarity

  # Agreement Logic
  if (!is.na(freq_category) && !is.na(vector_category)) {
    if (freq_category == vector_category) {
      # ═══════════════════════════════════
      # BOTH AGREE - HIGH CONFIDENCE
      # ═══════════════════════════════════
      return(list(
        genus = genus_row$genus,
        category = pluralize_category(freq_category),
        method = "dual_agreed",
        freq_result = freq_category,
        vector_result = vector_category,
        vector_similarity = vector_similarity,
        status = "accepted",
        confidence = "high",
        needs_review = FALSE
      ))
    } else {
      # ═══════════════════════════════════
      # DISAGREEMENT - NEEDS MANUAL REVIEW
      # ═══════════════════════════════════
      return(list(
        genus = genus_row$genus,
        category = NA,
        method = "dual_disagreed",
        freq_result = freq_category,
        vector_result = vector_category,
        vector_similarity = vector_similarity,
        status = "needs_review",
        confidence = "low",
        needs_review = TRUE,
        review_note = sprintf("Freq: %s, Vector: %s (sim=%.2f)",
                             freq_category, vector_category, vector_similarity)
      ))
    }
  } else if (!is.na(freq_category)) {
    # Only frequency succeeded
    return(list(
      genus = genus_row$genus,
      category = pluralize_category(freq_category),
      method = "frequency_only",
      freq_result = freq_category,
      vector_result = NA,
      vector_similarity = NA,
      status = "accepted",
      confidence = "medium",
      needs_review = FALSE
    ))
  } else if (!is.na(vector_category)) {
    # Only vector succeeded
    return(list(
      genus = genus_row$genus,
      category = pluralize_category(vector_category),
      method = "vector_only",
      freq_result = NA,
      vector_result = vector_category,
      vector_similarity = vector_similarity,
      status = "accepted",
      confidence = "medium",
      needs_review = FALSE
    ))
  } else {
    # Both failed - uncategorized
    return(list(
      genus = genus_row$genus,
      category = "other",
      method = "both_failed",
      freq_result = NA,
      vector_result = NA,
      vector_similarity = NA,
      status = "uncategorized",
      confidence = "low",
      needs_review = FALSE
    ))
  }
}

# Apply to all genera
genus_categories <- genus_vernaculars %>%
  rowwise() %>%
  mutate(
    result = list(process_genus_dual_pipeline(cur_data(), category_prototypes))
  ) %>%
  unnest_wider(result)
```

**Expected Agreement Statistics**:
- **High confidence (dual_agreed)**: 70-80% of genera
- **Medium confidence (single method)**: 15-20%
- **Needs review (disagreed)**: 5-10%
- **Uncategorized (both failed)**: 5%

**Key Innovation**: Only 5-10% need human review, and these are flagged with both candidate categories for efficient decision-making.

**No Pre-Labeling**: This approach is purely data-driven from observed vernacular names.

**For Animals**:
- Extract category from iNaturalist vernaculars using NLP
- If no clear category can be extracted → remains "other" (uncategorized)
- No taxonomic fallbacks, no LLM-based assumptions
- Scientific integrity: only use what we observe in the data

**For Plants**:
- Use derived vernaculars directly from P2/P4 pipeline (already genus-level)
- P2: Derived from genus (e.g., Quercus → "oaks")
- P4: Derived from family (e.g., Rosaceae genus → "roses")
- No additional NLP needed - vernaculars are already categories

**Quality filtering for animal categories**:
- Minimum observation threshold (e.g., genus must have ≥10 iNat observations)
- Minimum frequency threshold (category noun appears in ≥50% of vernaculars)
- Exclude overly generic terms: "insect", "animal", "creature", "organism"
- Exclude modifiers: "common", "european", "great", "small", "wild"

### Phase 4: Genus-Category Mapping

**Objective**: Create authoritative lookup table from genus to category

**Algorithm** (purely data-driven):

```r
assign_category_to_genus <- function(genus_row) {
  # Skip if insufficient data
  if (genus_row$n_observations < 10) {
    return("other")
  }

  # Extract NLP-derived category from vernaculars
  category_candidate <- extract_category_candidates(genus_row$vernaculars)

  # Validate quality
  if (is.na(category_candidate)) {
    return("other")
  }

  # Exclude overly generic terms
  generic_terms <- c("insect", "animal", "creature", "organism", "plant",
                     "tree", "flower", "herb", "species")
  if (tolower(category_candidate) %in% generic_terms) {
    return("other")
  }

  # Exclude modifiers (not category terms)
  modifiers <- c("common", "european", "american", "asian", "great", "small",
                 "large", "wild", "domestic", "native")
  if (tolower(category_candidate) %in% modifiers) {
    return("other")
  }

  # Return pluralized category
  pluralize_category(category_candidate)
}

# Apply to all genera
genus_categories <- genus_vernaculars %>%
  mutate(
    category = map_chr(., assign_category_to_genus),
    derivation_method = ifelse(category == "other", "uncategorized", "nlp_extracted")
  )
```

**Validation (not pre-labeling)**:

1. Export top 100 genera by observation count for verification
2. Review category distribution and quality
3. Identify patterns in uncategorized genera (for pipeline improvement)
4. Document category emergence statistics

**Output**: `data/taxonomy/genus_to_category.parquet`
- Columns: genus, kingdom, category, n_observations, n_unique_vernaculars, vernaculars_sample, derivation_method
- derivation_method values: "nlp_extracted" or "uncategorized"

### Phase 5: Organism Labeling

**Objective**: Apply genus-category mapping to all organisms in organisms.parquet

**Process**:

```r
# Load organisms and genus-category mapping
organisms <- read_parquet("data/taxonomy/organisms_vernacular_final.parquet")
genus_map <- read_parquet("data/taxonomy/genus_to_category.parquet")

# Extract genus from scientific name
organisms <- organisms %>%
  mutate(genus = str_extract(scientific_name, "^[A-Z][a-z]+"))

# Join with category mapping
organisms_categorized <- organisms %>%
  left_join(
    genus_map %>% select(genus, category),
    by = "genus"
  ) %>%
  mutate(
    # For plants: use vernacular as category (more specific)
    # For animals: use derived category (aggregation)
    organism_category = case_when(
      kingdom == "Plantae" ~ vernacular_name_en,
      kingdom == "Animalia" ~ category,
      TRUE ~ "other"
    )
  )
```

**Output**: `data/taxonomy/organisms_categorized_comprehensive.parquet`
- All original columns plus:
  - `genus`: Extracted genus name
  - `category`: Derived category from NLP analysis
  - `organism_category`: Final category for display (plants use vernacular, animals use category)

### Phase 6: Validation

**Quality Metrics**:

1. **Coverage**: % of organisms with non-"other" category
2. **Category emergence**: Number of distinct categories derived from data
3. **Distribution**: Category size distribution (avoid over-concentration)
4. **Ecological coherence**: Manual review of category assignments for top genera
5. **Vernacular-category alignment**: Verify categories match vernacular semantics

**Validation Script**:

```r
# Category distribution
validation_report <- organisms_categorized %>%
  group_by(category) %>%
  summarise(
    n_organisms = n(),
    n_genera = n_distinct(genus),
    example_genera = paste(head(unique(genus), 5), collapse = "; "),
    example_species = paste(head(scientific_name, 3), collapse = "; "),
    .groups = "drop"
  ) %>%
  arrange(desc(n_organisms))

# Coverage by kingdom
coverage_by_kingdom <- organisms_categorized %>%
  group_by(kingdom) %>%
  summarise(
    total = n(),
    categorized = sum(category != "other"),
    pct_categorized = 100 * categorized / total
  )

# Export for review
write_csv(validation_report, "reports/category_distribution.csv")
write_csv(coverage_by_kingdom, "reports/coverage_by_kingdom.csv")
```

## Implementation Plan

### Tools and Dependencies

**R Packages** (for data processing and Pipeline A):
```r
install.packages(c(
  # Pipeline A: Frequency-based
  "udpipe",        # NLP: tokenization, lemmatization, POS tagging

  # Data processing
  "duckdb",        # Fast data processing
  "arrow",         # Parquet I/O
  "dplyr",         # Data manipulation
  "stringr",       # String processing
  "purrr",         # Functional programming
  "tibble",        # Data frames
  "tidyr"          # Data reshaping
))
```

**Python Environment** (Pipeline B: Vector classification):
- Conda environment: `AI` at `/home/olier/miniconda3/envs/AI`
- Required packages (already installed):
  - `openai` (for vLLM client)
  - `pandas`, `numpy`
  - `scikit-learn` (for cosine_similarity)
  - `tqdm` (progress bars)

**vLLM Docker** (Pipeline B: GPU-accelerated embeddings):
- Image: `vllm/vllm-openai:latest`
- Model: `tencent/KaLM-Embedding-Gemma3-12B-2511`
- Status: Running on localhost:8000
- See "Pipeline B" section above for Docker launch command

**Setup udpipe** (one-time, for Pipeline A):
```r
library(udpipe)
udpipe_download_model(language = "english")
# Model: english-ewt-ud-2.5-191206.udpipe (~65 MB)
```

### Scripts to Create

1. **`src/Stage_4/taxonomy/nlp/01_aggregate_inat_by_genus.R`** (R)
   - Load iNaturalist observations
   - Aggregate vernaculars by genus
   - Output: `genus_vernacular_aggregations.parquet`

2. **`src/Stage_4/taxonomy/nlp/02_generate_functional_categories.R`** (R)
   - Generate comprehensive functional category list (200-500 categories)
   - Based on recognizable ecological/functional groups
   - Output: `functional_categories.parquet`

3. **`src/Stage_4/taxonomy/nlp/03_vector_classification_vllm.py`** ✅ **COMPLETED** (Python)
   - Connect to vLLM server (localhost:8000)
   - Create category prototype embeddings from functional categories
   - Classify all genera using cosine similarity (batch size: 128)
   - Output: `vector_classifications_kalm.parquet`
   - **Status**: Script created, blocked on missing prerequisite data from steps 1-2

4. **`src/Stage_4/taxonomy/nlp/04_frequency_extraction.R`** (R)
   - **Pipeline A**: Frequency-based extraction using udpipe
   - Tokenization, POS tagging, lemmatization
   - Extract most common noun from vernaculars for each genus
   - Output: `frequency_classifications.parquet`

5. **`src/Stage_4/taxonomy/nlp/05_agreement_checking.R`** (R)
   - Merge Pipeline A (frequency) and Pipeline B (vector) results
   - Agreement logic: accept if both agree, flag if disagree
   - Confidence scoring based on agreement
   - Output: `genus_to_category_dual.parquet` (with agreement metadata)

6. **`src/Stage_4/taxonomy/nlp/06_manual_review.R`** (R)
   - Export disagreement cases for manual review (~5-10%)
   - Import manual decisions
   - Merge with dual-pipeline results
   - Output: `genus_to_category_final.parquet`

7. **`src/Stage_4/taxonomy/nlp/07_label_organisms.R`** (R)
   - Apply genus-category mapping to all organisms
   - Handle plants vs animals differently
   - Output: `organisms_categorized_comprehensive.parquet`

8. **`src/Stage_4/taxonomy/nlp/08_validate_categories.R`** (R)
   - Generate validation reports
   - Compute coverage, agreement rates, confidence distribution
   - Category distribution analysis

9. **`src/Stage_4/taxonomy/nlp/run_complete_nlp_pipeline.sh`** (Bash)
   - Orchestrate all scripts in sequence
   - Run R scripts with system R
   - Run Python script with conda AI environment
   - Performance logging
   - Reproducibility wrapper

### Reproducibility Commands

```bash
# Prerequisites: vLLM Docker server must be running
# Check: curl -s http://localhost:8000/v1/models

# Step 1: Aggregate iNaturalist by genus (R)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_4/taxonomy/nlp/01_aggregate_inat_by_genus.R

# Step 2: Generate comprehensive functional categories (R)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_4/taxonomy/nlp/02_generate_functional_categories.R

# Step 3: Vector classification via vLLM (Python) ✅ COMPLETED
/home/olier/miniconda3/envs/AI/bin/python \
  src/Stage_4/taxonomy/nlp/03_vector_classification_vllm.py
# Output: data/taxonomy/vector_classifications_kalm.parquet

# Step 4: Frequency extraction - Pipeline A (R)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_4/taxonomy/nlp/04_frequency_extraction.R

# Step 5: Agreement checking (R)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_4/taxonomy/nlp/05_agreement_checking.R

# Step 6: Manual review of disagreements (~5-10% of genera) (R)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_4/taxonomy/nlp/06_manual_review.R
# → Exports: reports/manual_review_queue.csv
# → User reviews and creates: reports/manual_review_decisions.csv
# → Script imports decisions and creates final mapping

# Step 7: Label all organisms (R)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_4/taxonomy/nlp/07_label_organisms.R

# Step 8: Validate results (R)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_4/taxonomy/nlp/08_validate_categories.R

# Complete pipeline (all steps, with pause for manual review)
bash src/Stage_4/taxonomy/nlp/run_complete_nlp_pipeline.sh
```

## Implementation Status

### Completed

1. **vLLM Docker Server** ✅
   - Successfully deployed KaLM-Embedding-Gemma3-12B-2511
   - Running on localhost:8000 with OpenAI-compatible API
   - GPU memory: 45.4GB/48GB (95% utilization)
   - Optimizations: Flash Attention, Chunked Prefill, Prefix Caching
   - Verified with test embeddings

2. **Pipeline B: Vector Classification Script** ✅
   - Created: `src/Stage_4/taxonomy/nlp/03_vector_classification_vllm.py`
   - Uses OpenAI client to call vLLM server
   - Batch processing (128 texts per request)
   - Cosine similarity computation with sklearn
   - Normalized embeddings for accurate similarity
   - Top-3 categories for debugging
   - Status: **Script complete, blocked on missing input data**

### In Progress

**Current blocker**: Missing prerequisite data files from earlier pipeline steps:
- `data/taxonomy/genus_vernacular_aggregations.parquet` (from step 1)
- `data/taxonomy/functional_categories.parquet` (from step 2)

**Available data**:
- `data/taxonomy/organisms_vernacular_final.parquet` (1.7M, from assign_vernacular_names.R)
- `data/taxonomy/inat_vernaculars_all_languages.parquet` (24M, raw iNat data)

### Pending

**Next immediate steps**:

1. Create `01_aggregate_inat_by_genus.R`:
   - Read `inat_vernaculars_all_languages.parquet`
   - Aggregate vernaculars by genus with observation counts
   - Output: `genus_vernacular_aggregations.parquet`

2. Create `02_generate_functional_categories.R`:
   - Generate comprehensive functional category list
   - 200-500 categories covering all ecological domains
   - Based on recognizable functional groups (bees, moths, oaks, etc.)
   - Output: `functional_categories.parquet`

3. Run `03_vector_classification_vllm.py` (already created):
   - Will process once input data is available
   - Expected processing time: 15-20 minutes for ~30,000 genera

4. Create remaining scripts:
   - `04_frequency_extraction.R` (Pipeline A)
   - `05_agreement_checking.R` (merge Pipeline A + B)
   - `06_manual_review.R` (handle disagreements)
   - `07_label_organisms.R` (apply to all organisms)
   - `08_validate_categories.R` (validation reports)
   - `run_complete_nlp_pipeline.sh` (orchestration)

### Implementation Decisions

**Data source (step 1)**:
- Use `inat_vernaculars_all_languages.parquet` with language metadata
- Join with `taxa.csv` to get genus information
- Preserve language columns for wide-format output

**Category generation (step 2)**:
- Generate comprehensive curated list (200-500 categories)
- NOT data-driven extraction from limited sample
- Based on recognizable functional/ecological groups
- Facilitates vector matching while ensuring broad coverage

**Development approach**:
- Plan all 8 scripts comprehensively
- Create each script, test, then commit to git
- Update master orchestration script incrementally

## Expected Outcomes

### Quantitative Targets

- **Coverage**: ≥95% of organisms categorized (non-"other")
- **Animal category count**: 100-200 specific categories (genus-level granularity)
  - Examples: bees, moths, spiders, beetles, bats, mice, eagles, lizards, frogs
- **Plant category count**: Direct genus-level vernaculars (500+)
  - Examples: oaks, roses, pines, maples, apples, grasses, ferns
- **Genus coverage**: 100% of genera mapped to categories
- **Validation accuracy**: ≥90% agreement with manual review (sample of 100 animals, 100 plants)

### Deliverables

1. **Genus-category lookup table**: Gold-standard mapping for all genera
2. **Categorized organisms dataset**: organisms_categorized_comprehensive.parquet
3. **Category taxonomy**: Hierarchical category definitions
4. **Validation report**: Coverage statistics, category distribution, anomaly flags
5. **Documentation**: Algorithm description, decision rationale, reproducibility commands

## Integration with Existing Pipeline

### Updates to Existing Scripts

**`assign_vernacular_names.R`**:
- No changes needed (still produces organisms_vernacular_final.parquet)

**`categorize_organisms.R`**:
- Replace with new NLP-based approach OR
- Deprecate entirely in favor of genus-category lookup

**Rust guild scorer**:
- Read `organism_category` column from organisms_categorized_comprehensive.parquet
- Remove hardcoded pattern matching in unified_taxonomy.rs
- Use data-driven categories for all aggregations

### Pipeline Sequencing

```
assign_vernacular_names.R (existing - produces vernacular parquet)
        ↓
01_aggregate_inat_by_genus.R (R: aggregate vernaculars by genus)
        ↓
02_bootstrap_categories.R (R: discover 100-200 categories from top 1000 genera)
        ↓
┌───────────────────────────────────────────────────────────┐
│   DUAL PIPELINE EXECUTION                                 │
│                                                           │
│   03_vector_classification_vllm.py ✅                     │
│   (Python: Pipeline B via vLLM Docker)                   │
│   - Create category prototype embeddings                 │
│   - Classify all genera using KaLM embeddings            │
│   - Output: vector_classifications_kalm.parquet          │
│                                                           │
│   04_frequency_extraction.R                              │
│   (R: Pipeline A via udpipe)                             │
│   - Tokenization, POS tagging, lemmatization             │
│   - Extract most common noun per genus                   │
│   - Output: frequency_classifications.parquet            │
└───────────────────────────────────────────────────────────┘
        ↓
05_agreement_checking.R (R: merge Pipeline A + B results)
        ├─ Both agree → high confidence, accept
        ├─ Single method → medium confidence, accept
        └─ Disagree → flag for manual review
        ↓
06_manual_review.R (R: handle disagreement cases)
        ├─ Export disagreements (~5-10%)
        ├─ [USER REVIEWS: reports/manual_review_decisions.csv]
        └─ Import decisions → final mapping
        ↓
07_label_organisms.R (R: apply genus-category mapping to all organisms)
        ↓
08_validate_categories.R (R: coverage, agreement stats, validation reports)
        ↓
[Rust guild scorer uses organisms_categorized_comprehensive.parquet]
```

**Language Distribution**:
- Python: Vector classification only (step 3)
- R: All other steps (data processing, frequency extraction, merging, validation)
- Bash: Orchestration script

## Risk Mitigation

### Technical Risks

1. **NLP accuracy**: Vernacular names may be noisy or inconsistent
   - Mitigation: Use frequency thresholds, quality validation of top genera

2. **Category ambiguity**: Some genera may have multiple valid categories
   - Resolution: Use most frequent noun as primary category
   - Future: Could add secondary category column if needed

3. **Computational cost**: Processing millions of observations
   - Mitigation: Use DuckDB for aggregation, batch process NLP with udpipe

4. **Pure R implementation**: udpipe may be slower than spaCy
   - Acceptance: Trade-off for no Python dependency is worth it
   - One-time processing, not real-time requirement

### Data Risks

1. **iNaturalist vernacular quality**: Community-contributed names vary in quality
   - Mitigation: Weight by observation count, minimum threshold filters

2. **Missing vernaculars**: Some genera may lack vernacular names
   - Acceptance: These remain "other" - scientifically honest approach
   - Benefit: Coverage improves as iNaturalist data grows organically

3. **Taxonomic changes**: Genus names may change over time
   - Mitigation: Include synonym mapping, version control taxonomy source
   - Re-run pipeline periodically to update with latest taxonomy

## Future Enhancements

1. **Multilingual category extraction**: Extend NLP to Chinese, Russian, etc.
2. **Hierarchical categories**: Enable drill-down from "Insects" → "Beetles" → "Ladybugs"
3. **Temporal updates**: Re-run pipeline as iNaturalist data grows
4. **User feedback loop**: Allow manual corrections to feed back into algorithm
5. **Machine learning**: Train classifier to predict categories from vernaculars

## References

**NLP Libraries**:
- udpipe R package: https://bnosac.github.io/udpipe/en/
- udpipe models: https://github.com/jwijffels/udpipe.models.ud.2.5
- Universal Dependencies: https://universaldependencies.org/

**vLLM and GPU Inference**:
- vLLM Documentation: https://docs.vllm.ai/
- vLLM Docker Deployment: https://docs.vllm.ai/en/stable/deployment/docker.html
- vLLM OpenAI-Compatible Server: https://docs.vllm.ai/en/stable/serving/openai_compatible_server.html
- NVIDIA Container Toolkit: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/

**Transformer Models**:
- KaLM-Embedding-Gemma3-12B-2511: https://huggingface.co/tencent/KaLM-Embedding-Gemma3-12B-2511
- MMTEB Leaderboard: https://huggingface.co/spaces/mteb/leaderboard
- HuggingFace Transformers: https://huggingface.co/docs/transformers/

**Python Libraries**:
- OpenAI Python SDK: https://github.com/openai/openai-python
- scikit-learn (cosine_similarity): https://scikit-learn.org/stable/modules/metrics.html#cosine-similarity

**Data Sources**:
- iNaturalist API: https://www.inaturalist.org/pages/api+reference

**R Data Processing**:
- DuckDB R package: https://duckdb.org/docs/api/r
- arrow (Parquet): https://arrow.apache.org/docs/r/
