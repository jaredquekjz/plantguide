# Kimi AI Organism Categorization Pipeline

## Overview

Uses Kimi API (Moonshot) to generate gardener-friendly category labels for animal genera. Categories are used for report aggregation (e.g., "25% Bees, 30% Butterflies").

## Pipeline Steps

### Step 0: Pre-filter to Animals Only

**Script:** `00_prefilter_animals_only.py`

**What it does:**
- Loads `organisms_categorized_comprehensive.parquet` (30,096 organisms)
- Filters to **Metazoa kingdom only** (17,592 animals)
- Removes all Plantae, Fungi, and unknown kingdoms
- Saves to `organisms_animals_only.parquet`

**Output:**
- 17,592 animals across 7,206 unique genera
- 100% animals, 0% plants

**Run:**
```bash
/home/olier/miniconda3/envs/AI/bin/python src/Stage_4/taxonomy/nlp/00_prefilter_animals_only.py
```

### Step 1: Kimi API Categorization

**Script:** `06_kimi_gardener_labels.py`

**What it does:**
- Loads pre-filtered animals-only parquet
- Loads English + Chinese vernaculars for each genus
- Sends concurrent requests to Kimi API
- Generates generic category labels (e.g., "Bees", "Moths", "Butterflies")

**Configuration:**
- **Model:** `kimi-k2-turbo-preview` (validated at 100% accuracy on test set)
- **max_tokens:** 200
- **Concurrency:** 10 concurrent requests
- **Test mode:** `TEST_MODE = True` processes first 100 genera only

**Input:**
- `organisms_animals_only.parquet` (17,592 animals, 7,206 genera)
- `genus_vernacular_aggregations.parquet` (English names)
- `genus_vernacular_aggregations_chinese.parquet` (Chinese names)

**Output CSV columns:**
- `genus` - Genus name
- `english_vernacular` - Full English vernacular names (semicolon-separated)
- `chinese_vernacular` - Full Chinese vernacular names (semicolon-separated)
- `kimi_label` - Category label from Kimi (e.g., "Bees", "Moths")
- `success` - True/False
- `error` - Error message if failed

**Run (test mode - first 100 genera):**
```bash
export MOONSHOT_API_KEY="your-key-here"
/home/olier/miniconda3/envs/AI/bin/python src/Stage_4/taxonomy/nlp/06_kimi_gardener_labels.py
```

**Run (full production):**
```bash
# Edit script: set TEST_MODE = False
export MOONSHOT_API_KEY="your-key-here"
/home/olier/miniconda3/envs/AI/bin/python src/Stage_4/taxonomy/nlp/06_kimi_gardener_labels.py
```

## Key Features

### 1. Animals Only (No Plants)

Pre-filtering ensures **zero plants** in the dataset:
- Uses `kingdom == 'Metazoa'` filter
- Removes all 12 Plantae organisms
- Removes all 18 Fungi organisms
- Removes 12,474 organisms with unknown kingdom

### 2. Bilingual Input

Kimi receives **both English AND Chinese** vernaculars simultaneously:
```
Genus: Xylocopa
English names: large carpenter bees; eastern carpenter bee; valley carpenter bee
Chinese names: 中华木蜂; 中华绒木蜂; 加州木蜂
```

This improves accuracy through cross-language validation.

### 3. Category-Focused Prompt

Prompt explicitly requests **generic categories** for report aggregation:
- "duckweed weevil" → "Weevils" (NOT "Duckweed weevil")
- "carpenter bee" → "Bees" (NOT "Carpenter bees")
- Output format: plural, 1-2 words max

### 4. Full Vernacular Output

Output CSV contains **full vernacular names** (not truncated):
- All English names concatenated with semicolons
- All Chinese names concatenated with semicolons
- Kimi label for categorization

### 5. Test Mode

`TEST_MODE = True` processes only first 100 genera for validation before full run.

## Validation Results

**Test set:** 15 compound name cases where vector embeddings failed

**Kimi accuracy:** 15/15 correct (100%)
**Vector accuracy:** 7/15 correct (46.7%)

**Critical fixes:**
- "duckweed weevil" → Kimi: "Weevils" ✓ (vector: "duckweeds" ✗)
- "sugar maple borer" → Kimi: "Beetles" ✓ (vector: "maples" ✗)
- "fruit bat" → Kimi: "Bats" ✓ (vector: "strawberries" ✗)

See: `reports/taxonomy/kimi_compound_name_test_30.csv`

## Production Deployment

### Prerequisites

```bash
# Set API key permanently
echo 'export MOONSHOT_API_KEY="your-key-here"' >> ~/.bashrc
source ~/.bashrc
```

### Full Pipeline

```bash
# Step 0: Pre-filter to animals only (run once)
/home/olier/miniconda3/envs/AI/bin/python \
  src/Stage_4/taxonomy/nlp/00_prefilter_animals_only.py

# Step 1: Test mode (first 100 genera)
# Edit 06_kimi_gardener_labels.py: TEST_MODE = True
/home/olier/miniconda3/envs/AI/bin/python \
  src/Stage_4/taxonomy/nlp/06_kimi_gardener_labels.py

# Review output, then run full production
# Edit 06_kimi_gardener_labels.py: TEST_MODE = False
/home/olier/miniconda3/envs/AI/bin/python \
  src/Stage_4/taxonomy/nlp/06_kimi_gardener_labels.py
```

### Expected Performance

**Processing time:**
- 10 concurrent requests
- ~1 second per request
- 7,206 genera / 10 = 721 batches
- ~12-15 minutes total

**Output:**
- `data/taxonomy/kimi_gardener_labels.csv`
- ~7,206 rows (one per genus)
- Columns: genus, english_vernacular, chinese_vernacular, kimi_label, success, error

## Files

```
src/Stage_4/taxonomy/nlp/
├── 00_prefilter_animals_only.py          # Pre-filter to Metazoa only
├── 06_kimi_gardener_labels.py            # Main Kimi API script
├── 07_kimi_compound_name_test.py         # Test script (15 tricky cases)
└── README_KIMI_PIPELINE.md               # This file

data/taxonomy/
├── organisms_categorized_comprehensive.parquet  # Source (30K organisms)
├── organisms_animals_only.parquet               # Pre-filtered (17.6K animals)
├── genus_vernacular_aggregations.parquet        # English vernaculars
├── genus_vernacular_aggregations_chinese.parquet # Chinese vernaculars
└── kimi_gardener_labels.csv                     # Output

reports/taxonomy/
├── kimi_compound_name_test_30.csv        # Validation results
└── kimi_compound_name_validation.md      # Validation analysis
```

## Model Configuration

**Model:** `kimi-k2-turbo-preview`
- Proven 100% accuracy on compound name test cases
- Fast response time (~1 second)
- Low token usage (categories are 1-2 words)

**Alternative (NOT recommended):** `kimi-k2-thinking`
- Requires 500 max_tokens (uses ~170 tokens for reasoning)
- Slower and more expensive
- No accuracy improvement over turbo model

## Next Steps

1. Run test mode (100 genera) for final validation
2. Review sample outputs
3. Set `TEST_MODE = False` for production
4. Run full pipeline on 7,206 genera
5. Validate output CSV quality
6. Integrate labels into guild scorer
