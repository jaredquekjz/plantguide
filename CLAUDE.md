# CLAUDE.md

## Images and Screenshots
**When user asks to look at images/screenshots**: Check `ellenberg/dump/` for the filename.

## Architecture Overview

```
Browser → Cloudflare Access (Google Auth) → Cloudflare CDN → Caddy (443) → Astro (4000) → Rust API (3000)
                                                          → R2 CDN (photos.olier.ai)
```

| Component | Location | Purpose |
|-----------|----------|---------|
| **Domain** | `olier.ai` | Main site (protected by Cloudflare Access) |
| **Photos CDN** | `photos.olier.ai` | R2 bucket with CDN caching |
| **Rust API** | `shipley_checks/src/Stage_4/guild_scorer_rust/` | JSON API on port 3000 |
| **Astro Frontend** | `/home/olier/plantguide-frontend/` | SSR on port 4000 |
| **Server** | `134.199.166.0` (SSH: `root@134.199.166.0`) | Ubuntu 24.04, Sydney |
| **TLS** | `/etc/ssl/cloudflare/olier.ai.pem` | Cloudflare Origin CA (15-year) |

### Cloudflare Access
- Google auth required for browser access
- Service token for API/CLI testing (credentials in `.env`)

## Quick Commands

### Local Development
```bash
./dev.sh                    # Start both API (3000) + frontend (4000)
```

### Deploy Frontend (from plantguide-frontend/)
```bash
./ship "commit message"     # git add/commit/push + build + deploy (~4s)
```

### Deploy Rust API (from ellenberg/)
```bash
./deploy.sh api "message"   # git commit/push + build + deploy
./deploy.sh all "message"   # Deploy both
```

**ALWAYS deploy remotely.** Never test locally unless explicitly instructed. Both scripts commit and push before deploying.

### Sync Data to Remote
```bash
./sync_data.sh              # Purge + upload all data (~463MB)
./sync_data.sh --skip-phylo # Skip 451MB phylo distances (~12MB)
./sync_data.sh --dry-run    # Preview only
```

### Test API Locally
```bash
DATA_DIR=shipley_checks/stage4 cargo run --manifest-path shipley_checks/src/Stage_4/guild_scorer_rust/Cargo.toml --features api --bin api_server
```

### Test Production API
Cloudflare Access blocks direct curl. SSH to server and curl localhost:

```bash
# Search (returns {data: [...]})
ssh root@134.199.166.0 'curl -s "http://localhost:3000/api/plants/search?q=papaya" | jq ".data[0]"'

# Suitability score and tips
ssh root@134.199.166.0 'curl -s "http://localhost:3000/api/encyclopedia/wfo-0000588009?location=singapore" | jq "{score: .requirements.overall_suitability.score_percent, tips: .requirements.overall_suitability.growing_tips}"'

# Filter tips by category
ssh root@134.199.166.0 'curl -s "http://localhost:3000/api/encyclopedia/wfo-0000515026?location=london" | jq "[.requirements.overall_suitability.growing_tips[] | select(.category == \"temperature\")]"'

# Health check
ssh root@134.199.166.0 'curl -s "http://localhost:3000/api/health"'
```

**Endpoints**:
- `/api/plants/search?q=<query>` - Search (response: `{data: [...]}`)
- `/api/encyclopedia/<wfo_id>?location=<city>` - With suitability
- `/api/health` - Health check

**Locations**: `london`, `singapore`, `helsinki` (not lat/lon)

## Encyclopedia System

**Rust sections** (`guild_scorer_rust/src/encyclopedia/sections_json/`):
- `s1_identity.rs` - Plant identity
- `s2_requirements.rs` - Growing requirements
- `s3_maintenance.rs` - Maintenance profile
- `s4_services.rs` - Ecosystem services
- `s5_interactions.rs` - Organisms, fungi, diseases
- `s6_companion.rs` - Guild potential

**Frontend components** (`plantguide-frontend/src/components/encyclopedia/`):
- `S1-Identity.astro` through `S6-Companion.astro`
- `S5-Interactions.svelte` (Svelte 5 for interactivity)

**View models**: `guild_scorer_rust/src/encyclopedia/view_models.rs`

### Adding Phosphor Icons

1. **Verify icon exists**: Check `ellenberg/dump/Pics/phosphor-icons/SVGs/regular/` for available icons
2. **Add to config**: Register in `plantguide-frontend/astro.config.mjs` under `icon.include.ph[]`
3. **Use in component**: `<Icon name="ph:icon-name" class="w-4 h-4" />`

## Data Pipeline

**Master script**: `shipley_checks/src/Stage_4/run_complete_pipeline_phase0_to_4.sh`

**Key parquets** (in `shipley_checks/stage4/`):
- `phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet` - Main plants (11,713)
- `phase7_output/organisms_flat.parquet` - Flattened organisms
- `phase7_output/fungi_flat.parquet` - Flattened fungi
- `phase7_output/pathogens_ranked.parquet` - Disease data

## Environment Setup

### Python (conda AI)
```bash
/home/olier/miniconda3/envs/AI/bin/python script.py
```

### R (system R for phylogeny, conda R for mixgb)
```bash
# Phylogeny
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" /usr/bin/Rscript script.R

# mixgb/XGBoost
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" PATH="/home/olier/miniconda3/envs/AI/bin:$PATH" /home/olier/miniconda3/envs/AI/bin/Rscript script.R
```

### Long-running jobs
Use `nohup` with direct paths (not `conda run` - it buffers output):
```bash
nohup /home/olier/miniconda3/envs/AI/bin/python script.py > log.txt 2>&1 &
```

### Rust
Default to debug builds. Release only when explicitly requested.

## PDF to MMD Conversion

Convert PDFs to Mathpix Markdown (preserves math equations):
```bash
/home/olier/miniconda3/envs/AI/bin/python src/Stage_1/convert_to_mmd.py <pdf_file> [output_file]
```
Requires `MATHPIX_APP_KEY` in `.env`. Output defaults to same directory with `.mmd` extension.

## Data Loading

Always use DuckDB for dataset operations:
```python
import duckdb
con = duckdb.connect()
df = con.execute("SELECT * FROM read_parquet('data.parquet')").fetchdf()
```

## MCP Tools

Use Context7 automatically for library documentation:
1. `mcp__context7__resolve-library-id` to find library
2. `mcp__context7__get-library-docs` to fetch docs

## Style Guidelines

- Plan systematically before executing
- Concise, formal documentation - no caps/emojis/exclamation marks
- No academic citations unless explicitly provided
- Extend existing files rather than creating new ones
- Use nohup for jobs >15 minutes

### Git Commit Messages

**Never include Claude Code sign-offs, co-author tags, or AI attribution in commits.**

Bad (do NOT do this):
```
Fix bug in parser

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

Good:
```
Fix bug in parser
```

Keep commit messages focused on the change itself. No emoji, no AI attribution, no marketing.
