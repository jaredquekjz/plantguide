# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This R-based scientific pipeline predicts European plant ecological indicator values (EIVE) from functional traits, then converts predictions to gardening recommendations. The pipeline combines structural equation modeling (SEM), phylogenetic analysis, and copula-based uncertainty quantification.

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
