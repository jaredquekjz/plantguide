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

### Rust Environment
**Rust compilation for guild scorer development**

- **Default**: Use debug builds for faster iteration during development
- **Release builds**: ONLY when explicitly instructed by user

**Debug build (default)**:
```bash
cd shipley_checks/src/Stage_4/guild_scorer_rust
cargo build
cargo run --bin test_3_guilds_parallel
```

**Release build (only when requested)**:
```bash
cd shipley_checks/src/Stage_4/guild_scorer_rust
cargo build --release
cargo run --release --bin test_3_guilds_parallel
```

**Why debug by default:**
- Faster compilation (5-10 seconds vs 2+ minutes)
- Faster iteration for development
- Sufficient for testing correctness and parity
- Release builds only needed for final performance validation

### Development Server (Digital Ocean)
**Remote droplet for Rust/HTMX frontend development and deployment**

| Property | Value |
|----------|-------|
| **IPv4** | 134.199.166.0 |
| **Private IP** | 10.126.0.2 |
| **Region** | Sydney (syd1) |
| **OS** | Ubuntu 24.04.3 LTS |
| **Specs** | 1 vCPU, 1GB RAM, 35GB Intel |

**SSH Access:**
```bash
ssh root@134.199.166.0
```

**Purpose:** Hosts the Iron-Rust frontend (Axum + HTMX + Askama + DaisyUI) for the plant encyclopedia and guild builder application.

**Full deployment plan:** See `shipley_checks/docs/iron_rust_deployment_plan.md`

#### Development Workflow (MANDATORY)

**Always follow this sequence when developing the web frontend:**

1. **Test locally first** - Run the API server locally with proper DATA_DIR
2. **Build** - Compile after local tests pass
3. **Deploy** - Upload binary/templates to server
4. **Test remotely** - Verify on production server

```bash
# 1. Test locally (from project root /home/olier/ellenberg)
DATA_DIR=shipley_checks/stage4 cargo run --manifest-path shipley_checks/src/Stage_4/guild_scorer_rust/Cargo.toml --features api --bin api_server

# 2. Build after local tests pass (from project root)
cargo build --manifest-path shipley_checks/src/Stage_4/guild_scorer_rust/Cargo.toml --features api

# 3. Deploy (stop service, upload, restart)
cd shipley_checks/src/Stage_4/guild_scorer_rust
ssh root@134.199.166.0 "systemctl stop plantguide"
scp target/debug/api_server root@134.199.166.0:/opt/plantguide/
rsync -avz --delete templates/ root@134.199.166.0:/opt/plantguide/templates/
ssh root@134.199.166.0 "systemctl start plantguide"

# 4. Test remotely
ssh root@134.199.166.0 "curl http://localhost:3000/health"
```

**Why local testing first:**
- Faster debug cycle (no network latency)
- Full error messages and stack traces
- Can use debugger and add println! statements
- Server has limited resources (1GB RAM)

#### Quick Deployment Commands

**Deploy binary (from guild_scorer_rust/):**
```bash
# Build debug locally (faster compilation, use for development)
cargo build --features api

# Deploy to server (stop first to unlock binary)
ssh root@134.199.166.0 "systemctl stop plantguide"
scp target/debug/api_server root@134.199.166.0:/opt/plantguide/

# Restart service
ssh root@134.199.166.0 "systemctl start plantguide"
```

**Quick sync assets/templates only (no Rust rebuild):**
```bash
rsync -avz --delete assets/ root@134.199.166.0:/opt/plantguide/assets/
rsync -avz --delete templates/ root@134.199.166.0:/opt/plantguide/templates/
ssh root@134.199.166.0 "systemctl restart plantguide"
```

**Deploy data files (one-time, from ellenberg/):**
```bash
rsync -avz --progress shipley_checks/stage4/phase7_output/ root@134.199.166.0:/opt/plantguide/data/phase7_output/
rsync -avz --progress shipley_checks/stage4/phase5_output/ root@134.199.166.0:/opt/plantguide/data/phase5_output/
rsync -avz --progress shipley_checks/stage4/phase0_output/ root@134.199.166.0:/opt/plantguide/data/phase0_output/
```

#### Browser Testing

- **Direct port access:** `http://134.199.166.0:3000`
- **Via Caddy (port 80):** `http://134.199.166.0`

#### Server Management

```bash
# Check service status
ssh root@134.199.166.0 "systemctl status plantguide"

# View live logs
ssh root@134.199.166.0 "journalctl -u plantguide -f"

# Health check
ssh root@134.199.166.0 "curl http://localhost:3000/health"
```

#### Server Directory Structure

```
/opt/plantguide/
├── api_server              # Binary (deployed from local build)
├── data/                   # Parquet files
│   ├── phase0_output/
│   ├── phase5_output/
│   └── phase7_output/
├── assets/                 # CSS/JS (synced from local)
│   ├── css/styles.css
│   └── js/{htmx,alpine,sortable}.min.js
└── templates/              # HTML templates (if external)
```

### Frontend Repository (ASH Stack)

**Location**: `/home/olier/plantguide-frontend/` (separate git repository)

The frontend is a separate Astro + Svelte + HTMX project that consumes the Rust JSON API. This follows the ASH Stack pattern where:
- **Rust** (port 3000): Pure JSON API (headless) - data and logic only
- **Astro** (port 4000): ALL HTML rendering, SSR orchestration
- **HTMX**: Simple HTML fragment swapping (search, location switching)
- **Svelte**: Complex widgets only (Guild Builder)

**Stack:**
- Astro 4.x with Node SSR adapter
- Svelte 5 for interactive islands
- DaisyUI + Tailwind CSS (Night Garden theme)
- Bits UI for accessible Svelte components
- HTMX for HTML-over-the-wire interactions

**Local Development (Recommended):**
```bash
# From ellenberg repo root - starts BOTH Rust API and Astro frontend
cd /home/olier/ellenberg
./dev.sh
```

This script:
1. Kills any existing processes on ports 3000/4000
2. Starts Rust API (port 3000) and waits for it to be healthy
3. Starts Astro frontend (port 4000) with `--host` flag for network access
4. Ctrl+C stops both services cleanly

**Access locally:**
- http://localhost:4000 (frontend)
- http://192.168.1.103:4000 (from other machines on network)

**Manual start (if needed):**
```bash
# Terminal 1: Rust API
DATA_DIR=shipley_checks/stage4 cargo run --manifest-path shipley_checks/src/Stage_4/guild_scorer_rust/Cargo.toml --features api --bin api_server

# Terminal 2: Astro frontend
cd /home/olier/plantguide-frontend
npm run dev -- --host
```

**Deployment (use deploy.sh script):**
```bash
# From ellenberg repo root - deploys both API and frontend
./deploy.sh all

# Or deploy individually
./deploy.sh api       # Rust API only
./deploy.sh frontend  # Astro frontend only
```

**Manual frontend deployment (if needed):**
```bash
cd /home/olier/plantguide-frontend
npm run build
rsync -avz --delete dist/ root@134.199.166.0:/opt/plantguide-frontend/dist/
ssh root@134.199.166.0 "systemctl restart plantguide-frontend"
```

**Server paths:**
- API: `/opt/plantguide/` (binary, templates, data)
- Frontend: `/opt/plantguide-frontend/dist/` (Astro SSR)

**API Flow:**
```
Browser → Caddy (80) → Astro (4000) → Rust API (3000) → Parquet files
                ↓
         HTMX swaps HTML fragments from Astro endpoints
```

## Stage 4: Guild Builder & Encyclopedia Pipeline

**Master Script (ground truth)**: `shipley_checks/src/Stage_4/run_complete_pipeline_phase0_to_4.sh`

This master script orchestrates all phases of the guild scoring and encyclopedia generation pipeline. Always reference this script to understand the canonical extraction logic and data flow.

**Pipeline Phases:**
- **Phase 0**: GloBI interaction extraction (organisms, fungi, predator networks)
- **Phase 1**: Multilingual vernacular names (iNaturalist)
- **Phase 2**: Kimi AI organism categorization
- **Phase 3**: Köppen climate distributions
- **Phase 4**: Final dataset assembly
- **Phase 7**: DataFusion flattening for Rust (organisms_flat, fungi_flat, predators_master)

**Key Output Parquets** (in `shipley_checks/stage4/`):
- `phase0_output/organism_profiles_11711.parquet` - Plant-organism interactions
- `phase0_output/fungal_guilds_hybrid_11711.parquet` - Plant-fungus associations
- `phase0_output/herbivore_predators_11711.parquet` - Herbivore → predator lookup
- `phase7_output/organisms_flat.parquet` - Flattened for Rust queries
- `phase7_output/fungi_flat.parquet` - Flattened fungal data
- `phase7_output/predators_master.parquet` - Master list of pest predators

**Rust Components** (in `shipley_checks/src/Stage_4/guild_scorer_rust/`):
- `src/query_engine.rs` - DataFusion SQL queries on parquets
- `src/encyclopedia/` - Encyclopedia article generation
- `src/bin/generate_sample_encyclopedias.rs` - Sample article generator

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

## MCP Tools and External Services

### Context7 Library Documentation (MANDATORY)

**CRITICAL**: Always use Context7 MCP tools when I need code generation, setup or configuration steps, or library/API documentation. This means you should automatically use the Context7 MCP tools to resolve library id and get library docs without me having to explicitly ask.

**Use Context7 for:**
- Code generation (getting API usage examples, best practices)
- Setup/configuration steps for libraries
- Library documentation and reference
- Understanding library capabilities and features

**Workflow:**
1. Use `mcp__context7__resolve-library-id` to find the library ID
2. Use `mcp__context7__get-library-docs` with the resolved ID to fetch documentation
3. Apply documentation to generate accurate, up-to-date code

**Example libraries to use Context7 for:**
- Rust: datafusion, axum, tokio, polars, arrow
- Python: duckdb, pandas, scikit-learn, xgboost
- R: arrow, dplyr, ggplot2

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
