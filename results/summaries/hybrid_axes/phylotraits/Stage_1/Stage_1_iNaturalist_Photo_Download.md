# Stage 1 — iNaturalist Photo Download Workflow (aria2 Optimised)

Date: 2025-10-26  
Maintainer: Stage 1 photo enrichment

## Scope

This document captures a reproducible, high-throughput workflow to harvest Creative Commons photos from the iNaturalist Open Dataset for the Stage 1 shortlist (~11 k taxa).  
Key requirements satisfied here:

- **Original source names** (pre-WorldFlora) drive the taxon lookup so photo archives align with iNaturalist naming.
- **aria2** orchestrates massively parallel downloads, tuned for a 10 Gb s⁻¹ link (≈1.25 GB s⁻¹).
- Outputs include a machine-readable manifest with URLs, licenses, observer data, and per-species download summaries for attribution.

## Prerequisites

Ensure the following tooling is available in the Stage 1 environment:

- `aria2c` ≥ 1.36 (`sudo apt-get install aria2`).
- AWS CLI v2 (`aws --version`) with anonymous S3 access enabled via `--no-sign-request`.
- GNU `parallel` ≥ 2022 (for per-species concurrency control).
- DuckDB ≥ 0.10 (via `conda run -n AI duckdb …`).
- Existing Stage 1 enriched artefacts in `data/stage1/*_worldflora_enriched.parquet`.
- ≥ 1 TB of free disk space for image caches and manifests (11 k taxa × multiple sizes grows quickly).

Recommended environment variables:

```bash
export PROJECT_ROOT=/home/olier/ellenberg
export INAT_STAGING=$PROJECT_ROOT/data/external/inat
export INAT_MANIFEST=$INAT_STAGING/manifests
export INAT_PHOTO_ROOT=$INAT_STAGING/photos_large
```

## Pipeline Overview

1. Extract the **original taxon strings** from Stage 1 enriched datasets.
2. Derive the **Stage 1 shortlist with original names** (multi-source union).
3. Download the **iNaturalist metadata bundle** (taxa, photos, observations, observers).
4. Match shortlist names to **iNaturalist taxon IDs**.
5. Build a **photo manifest** (one row per usable photo).
6. Materialise **per-species aria2 input files** (one download list per species).
7. Launch **aria2 batches** (≈50–100 species concurrently).
8. Produce **QA reports** (success, retries, missing taxa).

Each step is scripted for repeatability and can be rerun incrementally.

### Quick Start (Scripted)

Two helper scripts under `src/Stage_1_Data_Extraction/` wrap the workflow end-to-end:

- `inat_photo_prepare.py`: builds manifests, per-species download lists, and license manifests.
- `inat_photo_download.py`: orchestrates the downloads (defaults to `aria2c`).

Example tmux-friendly invocation:

```bash
tmux new -s inat_prepare_full
# Inside tmux
cd /home/olier/ellenberg
python src/Stage_1_Data_Extraction/inat_photo_prepare.py --log-level INFO \
  |& tee data/external/inat/manifests/inat_prepare_full.log
```

Once the manifest is ready, launch downloads:

```bash
tmux new -s inat_dl_full
cd /home/olier/ellenberg
python src/Stage_1_Data_Extraction/inat_photo_download.py \
  --manifest-dir data/external/inat/manifests \
  --photo-root data/external/inat/photos_large \
  --max-concurrent 75 \
  --connections-per-species 8 \
  --log-level INFO \
  |& tee data/external/inat/manifests/inat_dl_full.log
```

Both scripts deduplicate photo IDs per species, assign deterministic filenames (`{photo_id}_large.{ext}`), and emit `license_manifest.csv` files for attribution.

## Step-by-Step Commands

### 1. Extract Original Names from Enriched Tables

The enriched Parquet files already contain the raw strings fed into WorldFlora (`wfo_original_name`). Extract them once into a consolidated lookup table.

```bash
cd $PROJECT_ROOT
conda run -n AI duckdb -c "
COPY (
  SELECT DISTINCT
    source,
    wfo_taxon_id,
    wfo_original_name AS original_name
  FROM (
    SELECT 'duke' AS source, wfo_taxon_id, wfo_original_name
    FROM read_parquet('data/stage1/duke_worldflora_enriched.parquet')
    UNION ALL
    SELECT 'eive', wfo_taxon_id, wfo_original_name
    FROM read_parquet('data/stage1/eive_worldflora_enriched.parquet')
    UNION ALL
    SELECT 'mabberly', wfo_taxon_id, wfo_original_name
    FROM read_parquet('data/stage1/mabberly_worldflora_enriched.parquet')
    UNION ALL
    SELECT 'try_enhanced', wfo_taxon_id, wfo_original_name
    FROM read_parquet('data/stage1/tryenhanced_worldflora_enriched.parquet')
    UNION ALL
    SELECT 'austraits', wfo_taxon_id, wfo_original_name
    FROM read_parquet('data/stage1/austraits_taxa_worldflora_enriched.parquet')
  )
  WHERE wfo_original_name IS NOT NULL AND trim(wfo_original_name) <> ''
) TO '$INAT_MANIFEST/stage1_original_name_lookup.csv'
(HEADER, DELIMITER ',');
"
```

### 2. Attach Original Names to the Stage 1 Shortlist

```bash
conda run -n AI duckdb -c "
COPY (
  SELECT
    sl.wfo_taxon_id,
    sl.wfo_scientific_name,
    lk.source,
    lk.original_name
  FROM read_parquet('data/stage1/stage1_shortlist_with_gbif.parquet') sl
  JOIN read_csv_auto('$INAT_MANIFEST/stage1_original_name_lookup.csv') lk
    ON lk.wfo_taxon_id = sl.wfo_taxon_id
) TO '$INAT_MANIFEST/stage1_shortlist_original_names.parquet'
(FORMAT 'parquet');
"
```

This produces multiple rows per taxon when distinct sources supplied different spellings. Retain all spellings to maximise iNaturalist hit rates.

### 3. Fetch the Latest iNaturalist Metadata Bundle

```bash
mkdir -p $INAT_STAGING/latest
aws s3 --no-sign-request --region us-east-1 \
  cp s3://inaturalist-open-data/metadata/inaturalist-open-data-latest.tar.gz \
  $INAT_STAGING/inaturalist-open-data-latest.tar.gz

tar -xzf $INAT_STAGING/inaturalist-open-data-latest.tar.gz \
    -C $INAT_STAGING/latest
```

Resulting TSV files (tab-delimited, UTF-8): `taxa.csv`, `photos.csv`, `observations.csv`, `observers.csv`.

### 4. Resolve Shortlist Names to iNaturalist Taxon IDs

```bash
conda run -n AI duckdb -c "
COPY (
  SELECT
    s.wfo_taxon_id,
    s.wfo_scientific_name,
    s.source,
    s.original_name,
    t.taxon_id,
    t.name    AS inat_name,
    t.rank,
    t.active
  FROM read_parquet('$INAT_MANIFEST/stage1_shortlist_original_names.parquet') s
  LEFT JOIN read_csv_auto('$INAT_STAGING/latest/taxa.csv',
                          delim='\t', header=TRUE) t
    ON lower(trim(s.original_name)) = lower(trim(t.name))
  WHERE t.rank = 'species' AND t.active = 'true'
) TO '$INAT_MANIFEST/stage1_shortlist_inat_taxa.parquet'
(FORMAT 'parquet');
"
```

Review unmatched rows (where `taxon_id` is NULL) and adjust spellings manually (e.g. replace “subsp.” with “ssp.”) before re-running the join. Maintain a small CSV of overrides and union it into the DuckDB query if needed.

### 5. Construct the Photo Manifest

```bash
conda run -n AI duckdb -c "
COPY (
  SELECT
    it.wfo_taxon_id,
    it.wfo_scientific_name,
    it.source,
    it.original_name,
    it.taxon_id,
    obs.observation_uuid,
    obs.quality_grade,
    obs.observed_on,
    obs.positional_accuracy,
    photos.photo_id,
    photos.extension,
    photos.license,
    obs.observer_id
  FROM read_parquet('$INAT_MANIFEST/stage1_shortlist_inat_taxa.parquet') it
  JOIN read_csv_auto('$INAT_STAGING/latest/observations.csv',
                     delim='\t', header=TRUE) obs
    ON obs.taxon_id = it.taxon_id
  JOIN read_csv_auto('$INAT_STAGING/latest/photos.csv',
                     delim='\t', header=TRUE) photos
    ON photos.observation_uuid = obs.observation_uuid
  WHERE obs.quality_grade IN ('research','needs_id')
) TO '$INAT_MANIFEST/stage1_inat_photo_manifest.parquet'
(FORMAT 'parquet');
"
```

Augment with direct download URLs and observer attribution details:

```bash
conda run -n AI duckdb -c "
COPY (
  SELECT
    m.*,
    obsr.login,
    obsr.name,
    'https://inaturalist-open-data.s3.amazonaws.com/photos/'
      || m.photo_id || '/large.' || m.extension AS photo_url
  FROM read_parquet('$INAT_MANIFEST/stage1_inat_photo_manifest.parquet') m
  LEFT JOIN read_csv_auto('$INAT_STAGING/latest/observers.csv',
                          delim='\t', header=TRUE) obsr
    ON obsr.observer_id = m.observer_id
) TO '$INAT_MANIFEST/stage1_inat_photo_manifest_enriched.parquet'
(FORMAT 'parquet');
"
```

### 6. Materialise Per-Species aria2 Input Lists

```bash
mkdir -p $INAT_MANIFEST/species_lists
conda run -n AI duckdb -c "
COPY (
  SELECT
    replace(lower(it.wfo_scientific_name), ' ', '_') AS species_slug,
    it.wfo_taxon_id,
    it.wfo_scientific_name,
    it.original_name,
    it.photo_url,
    it.license,
    it.login,
    it.name    AS observer_name
  FROM read_parquet('$INAT_MANIFEST/stage1_inat_photo_manifest_enriched.parquet') it
) TO '$INAT_MANIFEST/stage1_inat_photo_manifest_enriched.csv'
(HEADER, DELIMITER ',');
"

python - <<'PY'
import csv
import os

manifest = os.environ['INAT_MANIFEST']
photo_root = os.environ['INAT_PHOTO_ROOT']
os.makedirs(photo_root, exist_ok=True)

with open(f"{manifest}/stage1_inat_photo_manifest_enriched.csv", newline='') as fh:
    reader = csv.DictReader(fh)
    species_rows = {}
    for row in reader:
        slug = row['species_slug'].strip()
        if not slug:
            continue
        species_rows.setdefault(slug, []).append(row)

for slug, rows in species_rows.items():
    species_dir = os.path.join(photo_root, slug)
    os.makedirs(species_dir, exist_ok=True)
    list_path = os.path.join(manifest, 'species_lists', f"{slug}.txt")
    with open(list_path, 'w', newline='') as lf, open(os.path.join(species_dir, 'license_manifest.csv'), 'w', newline='') as mf:
        for row in rows:
            lf.write(f"{row['photo_url']}\n")
        writer = csv.DictWriter(
            mf,
            fieldnames=['wfo_taxon_id','wfo_scientific_name','original_name',
                        'photo_url','license','login','observer_name']
        )
        writer.writeheader()
        writer.writerows(rows)
PY
```

Each species now has:

- `species_lists/<species_slug>.txt`: URLs for aria2.
- `photos_large/<species_slug>/license_manifest.csv`: attribution records for downloaded images.

### 7. Launch aria2 Downloads (Parallel by Species)

Set concurrency to match network capacity. Start with 50 species in parallel, each species allowing up to 8 connections per photo (tune as needed).

```bash
MAX_SPECIES=50
CONN_PER_SPECIES=8     # aria2 per-photo connections
aria2_opts=(
  --continue=true
  --max-connection-per-server=$CONN_PER_SPECIES
  --auto-file-renaming=false
  --allow-overwrite=true
  --summary-interval=10
  --file-allocation=none
  --retry-wait=2
  --max-tries=5
)

find $INAT_MANIFEST/species_lists -type f -name '*.txt' \
  | sort \
  | parallel -j $MAX_SPECIES --joblog $INAT_MANIFEST/aria2_species.log \
      "species_slug=\$(basename {} .txt);
       aria2c ${aria2_opts[@]} \
         --dir=$INAT_PHOTO_ROOT/\${species_slug} \
         --input-file={} \
         --save-session=$INAT_PHOTO_ROOT/\${species_slug}/aria2.session"
```

For a stress test, raise `MAX_SPECIES` to 100. Monitor throughput and adjust `CONN_PER_SPECIES` (2–16) to avoid overwhelming the remote endpoint. aria2 progress reports every 10 s; the GNU `parallel` joblog preserves per-species start/stop times.

### 8. Quality Assurance

1. **Session files**: Any residual `.aria2` files inside `photos_large/*` flag incomplete downloads—rerun the same command to resume.
2. **Manifest reconciliation**: Verify counts per species:

   ```bash
   python - <<'PY'
   import csv, os
   manifest = os.environ['INAT_MANIFEST']
   photo_root = os.environ['INAT_PHOTO_ROOT']
   with open(f"{manifest}/stage1_inat_photo_manifest_enriched.csv", newline='') as fh:
       rows = list(csv.DictReader(fh))
   expected = {}
   for r in rows:
       expected.setdefault(r['species_slug'], 0)
       expected[r['species_slug']] += 1
   for slug, exp in expected.items():
       species_dir = os.path.join(photo_root, slug)
       if not os.path.isdir(species_dir):
           print(f"Missing directory: {slug}")
           continue
       actual = sum(
           1 for fn in os.listdir(species_dir)
           if fn.lower().endswith(('.jpg','.jpeg','.png'))
       )
       if actual != exp:
           print(f"{slug}: expected {exp}, found {actual}")
   PY
   ```

3. **Licenses**: `license_manifest.csv` files encapsulate the required attribution data per species. Spot-check a few records and retain them alongside the photos in versioned storage.

4. **Bandwidth**: Use `nload` or `iftop` to ensure total throughput stays within acceptable bounds. Adjust `MAX_SPECIES` accordingly.

## Operational Notes

- Re-running Step 7 is idempotent: aria2 resumes partial files using the saved session.
- Consider nightly deltas: cache the previous metadata bundle and diff `taxon_id` assignments to spot renames.
- When publishing derived products, cite the iNaturalist Open Dataset and include photographer credit exactly as per the `license` column.
- Archive the enriched manifest (`stage1_inat_photo_manifest_enriched.parquet`) in long-term storage; it is the source of truth for provenance.

## Next Steps

- Integrate a Makefile target wrapping Steps 4–7 for turnkey execution.
- Attach automatic image QA (resolution checks, corrupt file detection) before downstream use.
- Evaluate storing the photos in object storage (e.g. MinIO) with metadata from the manifest for easier pipeline integration.


## Size-Ranked Top-10 Photo Selection (Research Grade, CC0/CC-BY)

The `stage1_inat_top10_size_rank.parquet` manifest now stores the ten largest images per shortlist taxon, limited to research-grade observations with open licences.

Steps to reproduce:

1. **Filter research-grade, CC0/CC-BY photos**
   ```sql
   CREATE OR REPLACE TABLE inat_photos_rg_open AS
   SELECT p.*, meta.width, meta.height
   FROM read_parquet('data/external/inat/manifests/stage1_inat_photo_manifest_wfo_enriched_with_filename.parquet') p
   JOIN read_csv_auto('data/external/inat/latest/inaturalist-open-data-20250927/photos.csv', delim='	', header=TRUE) meta
     ON meta.photo_id = p.photo_id
   WHERE p.wfo_taxon_id IN (
           SELECT wfo_taxon_id FROM read_parquet('data/stage1/stage1_shortlist_with_gbif_ge30.parquet')
       )
     AND p.quality_grade = 'research'
     AND p.license IN ('CC0', 'CC-BY');
   ```

2. **Keep only species with >10 qualifying photos**
   ```sql
   CREATE OR REPLACE TABLE candidate_species AS
   SELECT wfo_taxon_id
   FROM inat_photos_rg_open
   GROUP BY wfo_taxon_id
   HAVING COUNT(*) > 10;
   ```

3. **Rank by pixel area, select top 10**
   ```sql
   CREATE OR REPLACE TABLE inat_top10_by_size AS
   SELECT * FROM (
       SELECT p.*, ROW_NUMBER() OVER (
           PARTITION BY p.wfo_taxon_id
           ORDER BY (p.width * p.height) DESC,
                    p.photo_id ASC
       ) AS rn
       FROM inat_photos_rg_open p
       WHERE p.wfo_taxon_id IN (SELECT wfo_taxon_id FROM candidate_species)
   ) ranked
   WHERE rn <= 10;
   ```

4. **Join back to shortlist and write final manifest**
   ```sql
   COPY (
     SELECT stge.wfo_taxon_id,
            stge.canonical_name AS stage1_wfo_name,
            top.photo_id,
            top.photo_filename,
            top.photo_url,
            top.license,
            top.login,
            top.observer_name,
            top.width,
            top.height,
            (top.width * top.height) AS area_pixels,
            top.rn
     FROM read_parquet('data/stage1/stage1_shortlist_with_gbif_ge30.parquet') stge
     JOIN read_parquet('data/external/inat/manifests/inat_top10_by_size.parquet') top
       ON lower(trim(stge.wfo_taxon_id)) = lower(trim(top.wfo_taxon_id))
   ) TO 'data/external/inat/manifests/stage1_inat_top10_size_rank.parquet'
     (FORMAT PARQUET, COMPRESSION ZSTD);
   ```

5. **Regenerate per-species download lists**
   Run `/tmp/inat_lists_top10.py` to build
   `data/external/inat/manifests/species_lists_top10/*.txt` and
   `photos_large/<slug>/license_manifest.csv`, each capped at 10 entries.

**Coverage snapshot**
- 10 107 shortlist taxa have >10 qualifying photos.
- Exactly 10 photos retained per taxon (101 070 rows total).
- Largest files top the ranking (e.g., *Afrocarpus falcatus* images at 19.96 MP).
- Licence manifests now include width, height, pixel area, and the rank (1–10).
