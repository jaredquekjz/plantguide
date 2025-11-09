# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This R-based scientific pipeline predicts European plant ecological indicator values (EIVE) from functional traits, then converts predictions to gardening recommendations. The pipeline combines structural equation modeling (SEM), phylogenetic analysis, and copula-based uncertainty quantification.

## Git Branch Structure

### Main Branch (`main`)
- Contains complete pipeline: src/, results/, data/, shipley_checks/
- Production-ready code and canonical pipeline
- All development work happens here

### Shipley Review Branch (`shipley-review`)
- **SPECIAL PURPOSE**: Clean branch for Bill Shipley's independent verification
- Contains ONLY `shipley_checks/` directory with:
  - `shipley_checks/docs/` - Verification documentation (tracked in git)
  - `shipley_checks/src/` - Bill's verification scripts (tracked in git)
  - `shipley_checks/data/` - Generated datasets (ignored by git)
- Root-level folders (src/, results/, papers/) removed to avoid confusion
- **CRITICAL**: No diffs should exist in `shipley_checks/docs/` and `shipley_checks/src/` between main and shipley-review
- When updating these folders, cherry-pick or manually apply changes to both branches

### Working with shipley_checks/

**Canonical path**: `shipley_checks/` at repository root (NOT `data/shipley_checks/`)

**File structure**:
```
shipley_checks/
├── docs/               # Tracked: Verification documentation (.md, .docx)
├── src/                # Tracked: Bill's R verification scripts
├── stage1_models/      # Ignored: Model artifacts
├── stage2_models/      # Ignored: Model artifacts
├── stage3/             # Ignored: Final datasets
├── imputation/         # Ignored: Imputation outputs
└── wfo_verification/   # Ignored: WFO enriched parquets
```

**Final production dataset**: `shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv`
- 11,711 species × 782 columns
- 100% complete traits + EIVE, 99.88% valid CSR scores
- 10 ecosystem services with confidence levels
- Nitrogen fixation from TRY database (40.3% coverage)

## Environment Setup

### Python Environment (Conda)
**ONLY Python tasks run in conda environment `AI`**

- Use for: XGBoost, scikit-learn, pandas, numpy, all Python ML operations
- Activate: `conda activate AI` or use `conda run -n AI python ...`
- For scripts: `/home/olier/miniconda3/envs/AI/bin/python`
- Contains: XGBoost 3.0.5, scikit-learn, pandas, numpy

### R Environment (Custom Library)
**R scripts use custom library at `.Rlib` with different executables depending on task**

- **Always set**: `R_LIBS_USER=/home/olier/ellenberg/.Rlib`
- **CRITICAL**: Choice of R executable depends on package requirements

#### For Phylogeny Work (V.PhyloMaker2, ape, etc.)
Use **system R** at `/usr/bin/Rscript`:
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_1/build_phylogeny_improved_wfo_mapping.R
```

#### For XGBoost/mixgb Work (requires C++ compilation)
Use **conda AI Rscript** with PATH for compilers:
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  PATH="/home/olier/miniconda3/envs/AI/bin:/usr/bin:/bin" \
  /home/olier/miniconda3/envs/AI/bin/Rscript src/Stage_1/mixgb/mixgb_cv_eval_parameterized.R
```

**Why different executables?**
- System R: Simpler, works for most phylogenetic packages
- Conda AI Rscript: Provides C++ compilers needed for mixgb dependencies (mice, Rfast)
- Both use the same `.Rlib` custom library

### Critical: Output Buffering with nohup

When running long-running jobs with nohup, **DO NOT use `conda run`** - it buffers output. Use direct paths instead.

**Python (nohup):**
```bash
nohup /home/olier/miniconda3/envs/AI/bin/python script.py > log.txt 2>&1 &
```

**R Phylogeny (nohup with system R):**
```bash
nohup env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript script.R > log.txt 2>&1 &
```

**R XGBoost/mixgb (nohup with conda AI Rscript):**
```bash
nohup env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  PATH="/home/olier/miniconda3/envs/AI/bin:/usr/bin:/bin" \
  /home/olier/miniconda3/envs/AI/bin/Rscript script.R > log.txt 2>&1 &
```

## Data Loading and Processing

### MANDATORY: DuckDB for All Dataset Operations

**CRITICAL**: Always use DuckDB for dataset loading, manipulation, and joins. NEVER use pandas for large datasets.

**Why DuckDB:**
- 10-100× faster than pandas for large datasets
- Efficient parquet reading (handles PyArrow compatibility issues)
- SQL-based operations on disk (low memory usage)
- Parallel processing built-in

**Canon workflow:**

1. **Convert CSV to Parquet first:**
```python
import duckdb
con = duckdb.connect()
con.execute("""
    COPY (SELECT * FROM read_csv_auto('data/source.csv'))
    TO 'data/source.parquet' (FORMAT PARQUET, COMPRESSION ZSTD)
""")
```

2. **Load datasets with DuckDB:**
```python
# NOT: df = pd.read_csv('data.csv')  ❌ SLOW
# NOT: df = pd.read_parquet('data.parquet')  ❌ PyArrow issues

# YES: Use DuckDB
df = con.execute("SELECT * FROM read_parquet('data.parquet')").fetchdf()
```

3. **Do joins and aggregations in SQL:**
```python
# NOT: pandas merge/groupby  ❌ SLOW for large data
# YES: DuckDB SQL
result = con.execute("""
    SELECT a.*, b.category
    FROM read_parquet('data_a.parquet') a
    LEFT JOIN read_parquet('data_b.parquet') b ON a.id = b.id
    WHERE a.value > 100
    GROUP BY a.category
""").fetchdf()
```

4. **Avoid Python loops - use SQL:**
```python
# NOT: for plant_id in plants: ... filter/aggregate  ❌ VERY SLOW
# YES: Single SQL query with GROUP BY
result = con.execute("""
    SELECT
        plant_id,
        LIST(DISTINCT genus) as genera,
        COUNT(*) as count
    FROM data
    GROUP BY plant_id
""").fetchdf()
```

**Reference**: See `/home/olier/ellenberg/results/summaries/phylotraits/Stage_1/1.1_Raw_Data_Preparation.md` for canon parquet conversion process.

## Utility Scripts

### PDF to Markdown Conversion

For converting research papers and PDFs to markdown format, use the Mathpix-based converter:

```bash
python src/Stage_1/convert_to_mmd.py papers/input.pdf [optional_output.mmd]
```

**Features:**
- Uses Mathpix API for high-quality PDF to MMD (markdown) conversion
- Preserves mathematical notation, tables, and figures
- Requires `MATHPIX_APP_KEY` environment variable
- Output defaults to same directory with `.mmd` extension
- Processing typically takes 30-60 seconds per paper

**Use cases:**
- Converting research papers for analysis and citation
- Extracting methodology from scientific literature
- Building literature review documentation

## Style

- Always plan your work systematically, based on thorough checks of context, before executing. Always propose industry best practices for code - no short cuts.
- For documentation, aim for concise, formal and technical presentation. Avoid any FULL CAPS or emotional language or exclamation marks and informality. Include repro commands, precise descriptions and figures.
- For documentation, DO NOT include academic references, citations, or DOIs unless they have been explicitly provided in existing documents or user instructions. Do not fabricate or assume sources.
- For user conversation, remain non-technical, systematic and easy to understand.
- For statistical work - ALWAYS use or search for rigorous best practices. If unsure - confirm with user.
- Do not create new files endlessly - aim to use back the same script - adding flags and/or extending the functionality and modularity of an existing script. Or for documentation, aim to extend, instead of to create new documentation unless explcitly asked for.
- Always test your code appropriately BEFORE promising completion or solutions. Clear up any test scripts after use.
- Do not clutter repository - always put things into logical folders and sub-folders (e.g. use the src folder and the summaries folder).
- Execute commands that may take a long while in nohup (15 minutes etc.), and ask user to help monitor. For shorter commands, do not set unrealistic timeouts, then complain things do not work. Set longer timeouts and wait patiently. 

## Git Commit Guidelines

- When creating git commits, DO NOT add Claude Code sign-off or emoji indicators
- Keep commit messages very concise and professional

## Documentation Guidelines

- DO NOT include sign-offs, author attributions, or "Generated by Claude" statements in documentation
- DO NOT include "Maintained By: Claude Code" or similar attribution statements
- Documentation should appear as professional technical documentation without AI attribution
- Focus on content quality, clarity, and technical accuracy
