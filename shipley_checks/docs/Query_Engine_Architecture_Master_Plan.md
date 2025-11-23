# Query Engine Architecture Master Plan

## Executive Summary

This document outlines the complete architecture for building a high-performance query engine and API server for the European plant ecological database, targeting 100K requests/second throughput with sub-10ms latency for plant searches.

**Architecture Decision**: Hybrid Rust-based system combining DataFusion (async SQL queries) with Polars (CPU-bound guild scoring)

**Implementation Status**: Phase 0-7 complete, Phase 8-11 pending

## Table of Contents

1. [Background & Requirements](#background--requirements)
2. [Architecture Decision Process](#architecture-decision-process)
3. [Hybrid Architecture Design](#hybrid-architecture-design)
4. [Phase 0-11 Roadmap](#phase-0-11-roadmap)
5. [Phase 7 Implementation Details](#phase-7-implementation-details)
6. [Phase 8 API Server Design](#phase-8-api-server-design)
7. [Performance Targets](#performance-targets)
8. [Technology Stack](#technology-stack)

## Background & Requirements

### Project Context

The Ellenberg project has produced a comprehensive European plant ecological database:

- **11,711 plant species** with complete trait and indicator data
- **100% EIVE coverage** (European Indicator Values for Ecology)
- **99.88% CSR scores** (Competitor-Stress-Ruderal strategies)
- **10 ecosystem services** with confidence ratings
- **276,601 organism interactions** (pollinators, herbivores, pathogens, etc.)
- **100,013 fungal guild associations** (mycorrhizal, pathogenic, biocontrol, etc.)

### Use Cases

1. **Encyclopedia Generation** (90% of traffic)
   - Plant search by name, traits, ecological indicators
   - Individual plant profile retrieval
   - EIVE-based similarity search
   - Organism and fungal guild lookups
   - Expected: <10ms latency, read-heavy

2. **Guild Scoring** (10% of traffic)
   - Compute ecological complementarity scores for plant combinations
   - Requires complex trait distance calculations across multiple dimensions
   - CPU-bound: phylogenetic diversity, CSR triangle distance, EIVE Euclidean distance
   - Expected: <500ms latency for 10-50 plant guilds

### Performance Requirements

- **Throughput**: 100,000 requests/second sustained
- **Latency**:
  - Plant search: <10ms p50, <20ms p99
  - Single plant retrieval: <5ms p50
  - Guild scoring: <500ms p50, <1s p99
- **Concurrency**: 10,000+ simultaneous connections
- **Data size**: ~50MB parquet files (compressed), 200MB in-memory
- **Availability**: 99.9% uptime target

## Architecture Decision Process

### Option 1: DuckDB (Rejected)

**Evaluated**: DuckDB embedded analytical database

**Pros**:
- Excellent SQL analytics performance
- Native parquet support with predicate pushdown
- Simple embedded deployment (no server process)
- Fast aggregations and joins

**Cons**:
- **Single-threaded write lock** (problematic for concurrent reads during writes)
- **Limited async I/O** (blocking API, poor fit for high-concurrency web server)
- **GIL issues in Python** (if using Python bindings)
- **No native HTTP server** (would need custom wrapper)

**Verdict**: DuckDB excels at analytical workloads but is not optimized for high-concurrency OLTP-style queries needed for a web API.

### Option 2: DataFusion (Selected for Queries)

**Evaluated**: Apache Arrow DataFusion query engine

**Pros**:
- **Native async/await** (perfect fit for Tokio-based Axum server)
- **Inter-query parallelism** (multiple queries execute concurrently without blocking)
- **Arrow-native** (zero-copy data access, efficient predicate pushdown)
- **Designed for embedding** (library, not a server)
- **Excellent for point queries** (efficient indexed lookups)

**Cons**:
- Less mature than DuckDB for complex analytical queries
- More verbose API than DuckDB's SQL-first approach
- Requires Rust (but we're already using Rust for guild scorer)

**Verdict**: DataFusion's async-first design and inter-query parallelism make it ideal for high-concurrency web API workloads.

### Option 3: Polars (Selected for Guild Scoring)

**Evaluated**: Polars DataFrame library for CPU-bound scoring

**Pros**:
- **Intra-query parallelism** (single query uses all CPU cores efficiently)
- **Excellent for aggregations** (trait distance calculations, groupby operations)
- **LazyFrame optimization** (query plan optimization before execution)
- **Rich expression API** (easier for complex scoring logic than SQL)

**Cons**:
- Not optimized for point queries (scan-heavy)
- Blocking API (no async/await)

**Verdict**: Polars excels at CPU-bound analytical workloads like guild scoring. Use via `spawn_blocking` to avoid blocking async runtime.

### Final Architecture: Hybrid DataFusion + Polars

**Decision**: Use both engines for their respective strengths:

1. **DataFusion** for I/O-bound queries (90% traffic)
   - Plant search, retrieval, filtering
   - Organism/fungi lookups
   - EIVE similarity search
   - Async execution on Tokio runtime

2. **Polars** for CPU-bound scoring (10% traffic)
   - Guild complementarity scoring
   - Complex trait distance calculations
   - Phylogenetic diversity computation
   - Executed in blocking thread pool via `spawn_blocking`

**Rationale**: This hybrid approach leverages the optimal engine for each workload type without forcing a single tool to handle both I/O-bound and CPU-bound tasks inefficiently.

## Hybrid Architecture Design

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Axum HTTP Server (Tokio)                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Tower Middleware Stack                                   │  │
│  │  - CompressionLayer (gzip, brotli)                        │  │
│  │  - CorsLayer (permissive)                                 │  │
│  │  - TraceLayer (structured logging)                        │  │
│  │  - ConcurrencyLimitLayer (rate limiting)                  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Moka Cache (10K entries, 5min TTL)                       │  │
│  │  - Cache key: query hash                                  │  │
│  │  - Cache value: JSON response                             │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌──────────────────────┐        ┌─────────────────────────┐    │
│  │   DataFusion Engine  │        │   Polars Guild Scorer   │    │
│  │   (Async I/O Bound)  │        │   (CPU Bound)           │    │
│  │                      │        │                         │    │
│  │  - SessionContext    │        │  - LazyFrame queries    │    │
│  │  - SQL execution     │        │  - Parallel scoring     │    │
│  │  - Predicate pushdown│        │  - Rayon thread pool    │    │
│  │  - Arrow batches     │        │  - Trait distances      │    │
│  └──────────────────────┘        └─────────────────────────┘    │
│          ▼ async                          ▼ spawn_blocking       │
└───────────────────────────────────────────────────────────────────┘
                    ▼                                 ▼
        ┌───────────────────────┐       ┌──────────────────────┐
        │  Phase 7 SQL Parquets │       │  Phase 4 Parquets    │
        │  - plants_sql         │       │  - organisms         │
        │  - organisms_sql      │       │  - fungi             │
        │  - fungi_sql          │       │  - traits            │
        └───────────────────────┘       └──────────────────────┘
```

### Data Flow

#### Encyclopedia Query Flow (90% traffic)

```
Client Request
    ↓
Axum Router (async)
    ↓
Middleware Stack (compression, CORS, tracing)
    ↓
Check Moka Cache
    ↓ (cache miss)
Query Engine (DataFusion)
    ↓
SQL Query Execution (async)
    ↓
Parquet Predicate Pushdown (async I/O)
    ↓
Arrow RecordBatch Result
    ↓
Convert to JSON
    ↓
Cache Result (Moka)
    ↓
Compress Response (brotli/gzip)
    ↓
HTTP Response (200 OK)
```

**Latency Budget**: 10ms total
- Cache lookup: 0.1ms
- DataFusion query: 5-8ms
- JSON serialization: 1-2ms
- Compression: 0.5-1ms

#### Guild Scoring Flow (10% traffic)

```
Client Request (POST /api/guilds/score)
    ↓
Axum Router (async)
    ↓
Middleware Stack
    ↓
Guild Scorer Handler
    ↓
spawn_blocking (move to blocking thread pool)
    ↓
Polars GuildScorer (CPU-bound)
    ↓
  - Load plant traits (LazyFrame)
    ↓
  - Compute CSR triangle distance (Rayon parallel)
    ↓
  - Compute EIVE Euclidean distance (Rayon parallel)
    ↓
  - Compute phylogenetic diversity (parallel)
    ↓
  - Aggregate scores (weighted sum)
    ↓
Return to async runtime
    ↓
JSON Response (200 OK)
```

**Latency Budget**: 500ms total
- Trait loading: 50ms
- CSR distance: 100ms
- EIVE distance: 100ms
- Phylogenetic diversity: 200ms
- Score aggregation: 50ms

### Concurrency Model

**Tokio Async Runtime**:
- Event loop handles 10K+ concurrent connections
- Non-blocking I/O for DataFusion queries
- Minimal memory overhead per connection (~2KB)

**Blocking Thread Pool**:
- Separate thread pool for Polars work via `spawn_blocking`
- Pool size: num_cpus × 2 (e.g., 16 threads on 8-core machine)
- Prevents CPU-bound work from blocking async runtime

**Rayon Thread Pool**:
- Internal to Polars for intra-query parallelism
- Uses all available CPU cores for single query
- Configured to avoid over-subscription with blocking pool

## Phase 0-11 Roadmap

### Phase 0-6: Foundation (Completed)

**Phase 0**: WFO taxonomic enrichment and verification
**Phase 1**: Phylogenetic tree construction
**Phase 2**: Trait imputation using mixgb
**Phase 3**: CSR and ecosystem services integration
**Phase 4**: Organism and fungal guild profile generation
**Phase 5**: Encyclopedia generator (R-based, rules-driven)
**Phase 6**: Testing and validation

**Status**: All phases complete, verified with 9-test integrity suite

### Phase 7: SQL Optimization (Completed)

**Purpose**: Convert Phase 4 parquets to SQL-optimized format for DataFusion

**Deliverables**:
1. ✅ `convert_plants_for_sql.R` - 68 columns, normalized CSR, renamed EIVE
2. ✅ `convert_organisms_for_sql.R` - Flattened interaction arrays
3. ✅ `convert_fungi_for_sql.R` - Flattened fungal guild arrays
4. ✅ `run_phase7_pipeline.sh` - Orchestration script
5. ✅ `verify_phase7_integrity.rs` - 9-test verification suite (all passed)
6. ✅ Master pipeline integration

**Outputs**:
- `plants_searchable_11711.parquet` (11,713 rows × 68 cols, 2.71 MB)
- `organisms_searchable.parquet` (276,601 interactions)
- `fungi_searchable.parquet` (100,013 associations)

**Transformations**:
- EIVE column renaming: `EIVEres-L` → `EIVE_L` (SQL-safe)
- CSR normalization: 0-100 scale → 0-1 scale
- Computed columns: `maintenance_level`, `drought_tolerant`, `fast_growing`
- Array flattening: List columns → relational rows with FK constraints

**Verification**: All 9 integrity tests passed (row count, normalization, FK integrity)

**Status**: Complete, ready for Phase 8

### Phase 8: DataFusion API Server (Current)

**Purpose**: Build production-ready REST API combining DataFusion + Polars

**Sub-phases**:
1. **8.1**: Add DataFusion dependencies to Cargo.toml
2. **8.2**: Implement `query_engine.rs` module
   - SessionContext initialization
   - Register Phase 7 parquets
   - Plant search, similarity, organism/fungi queries
3. **8.3**: Implement `api_server.rs` with Axum
   - 8 REST endpoints (health, search, get, similar, organisms, fungi, score, build)
   - AppState with Arc<QueryEngine> + Arc<GuildScorer>
   - Middleware stack (compression, CORS, tracing)
4. **8.4**: Create `api_server` binary entry point
5. **8.5**: Write integration tests
6. **8.6**: Add Moka caching layer
7. **8.7**: Create Dockerfile and deployment config

**API Endpoints**:

| Endpoint | Method | Purpose | Latency Target |
|----------|--------|---------|----------------|
| `/health` | GET | Health check | <1ms |
| `/api/plants/search` | GET | Search plants | <10ms |
| `/api/plants/:id` | GET | Get single plant | <5ms |
| `/api/plants/:id/organisms` | GET | Get organisms | <10ms |
| `/api/plants/:id/fungi` | GET | Get fungi | <10ms |
| `/api/plants/similar` | POST | EIVE similarity | <20ms |
| `/api/guilds/score` | POST | Score guild | <500ms |
| `/api/guilds/build` | POST | Build guild | <2s |

**Status**: Detailed plan created, implementation pending

### Phase 9: Rust Encyclopedia Generator (Future)

**Purpose**: Port R encyclopedia generator to Rust for 10× speed improvement

**Rationale**:
- Current R generator: ~1.6 hours for 11,711 pages
- Target Rust generator: <10 minutes with Rayon parallelism
- Enables real-time page generation in API responses

**Approach**:
- Reuse DataFusion query engine for data access
- Implement rules-based text generation in Rust
- Parallel page generation with Rayon
- Template system (handlebars or tera)

**Deliverables**:
1. `encyclopedia_generator.rs` module
2. EIVE semantic binning lookups
3. Template files for 5 sections
4. Batch generation binary
5. Performance benchmarks

### Phase 10: Advanced Guild Building (Future)

**Purpose**: Implement constraint-based guild building with optimization

**Features**:
- Constraint solver for guild requirements
  - EIVE ranges (light, moisture, temperature, pH, fertility)
  - CSR balance requirements
  - Diversity targets (phylogenetic, functional)
  - Ecosystem service goals
- Genetic algorithm for multi-objective optimization
- Real-time suggestions based on partial guild

**Approach**:
- Use Polars for candidate filtering
- Implement genetic algorithm with custom fitness function
- Add constraint satisfaction checks
- Generate explanation for recommendations

### Phase 11: Production Deployment (Future)

**Purpose**: Deploy to cloud infrastructure with monitoring

**Options**:
1. **Google Cloud Run**
   - Serverless, auto-scaling
   - Pay-per-request pricing
   - 60s max request timeout (sufficient for guild building)

2. **Hetzner Dedicated Server**
   - Lower cost for sustained high traffic
   - Full control over resources
   - Better for 100K req/s sustained load

**Infrastructure**:
- Docker containerization
- Prometheus metrics collection
- Grafana dashboards
- Structured logging (JSON)
- Health check endpoints
- Graceful shutdown handling

**Monitoring**:
- Request latency (p50, p95, p99)
- Throughput (req/s)
- Error rate
- Cache hit rate
- CPU/memory utilization
- DataFusion query plans (slow query log)

## Phase 7 Implementation Details

### Design Goals

Phase 7 converts the Phase 4 plant encyclopedia dataset and interaction networks into SQL-optimized parquet files suitable for DataFusion's query execution model.

**Key Optimizations**:
1. **Column naming**: Remove hyphens from EIVE columns (SQL reserved character)
2. **Data normalization**: Convert CSR percentages to 0-1 scale for arithmetic operations
3. **Type optimization**: Use appropriate Arrow types (Int32, Float64, Utf8, Boolean)
4. **Array flattening**: Convert list columns to relational rows for efficient joins
5. **Computed columns**: Pre-compute common filter predicates
6. **Dictionary encoding**: Use Arrow dictionary type for categorical columns

### File 1: convert_plants_for_sql.R

**Purpose**: Prepare main plant dataset for SQL queries

**Transformations**:

1. **EIVE Column Renaming**:
```r
plants_sql <- plants %>%
  rename(
    EIVE_L = `EIVEres-L`,  # Light: 0-10 scale
    EIVE_M = `EIVEres-M`,  # Moisture: 0-10 scale
    EIVE_T = `EIVEres-T`,  # Temperature: 0-10 scale
    EIVE_K = `EIVEres-K`,  # Continentality: 0-10 scale
    EIVE_N = `EIVEres-N`,  # Nitrogen: 0-10 scale
    EIVE_R = `EIVEres-R`   # pH/Reaction: 0-10 scale
  )
```

2. **CSR Normalization**:
```r
plants_sql <- plants_sql %>%
  mutate(
    C_norm = C / 100.0,  # Competitor: 0-1 scale
    S_norm = S / 100.0,  # Stress-tolerator: 0-1 scale
    R_norm = R / 100.0   # Ruderal: 0-1 scale
  )
```

3. **Computed Filter Columns**:
```r
plants_sql <- plants_sql %>%
  mutate(
    # Maintenance level for filtering
    maintenance_level = case_when(
      S_norm > 0.5 ~ "low",      # Stress-tolerators need less care
      C_norm > 0.5 ~ "high",     # Competitors need more management
      TRUE ~ "medium"
    ),

    # Boolean flags for common queries
    drought_tolerant = S_norm > 0.6,
    fast_growing = R_norm > 0.6,
    shade_tolerant = EIVE_L < 4,
    full_sun = EIVE_L > 7,

    # Fertility classification
    fertility_needs = case_when(
      EIVE_N < 3 ~ "low",
      EIVE_N > 7 ~ "high",
      TRUE ~ "medium"
    )
  )
```

4. **Type Optimization**:
```r
plants_sql <- plants_sql %>%
  mutate(
    # Ensure proper types for Arrow schema
    wfo_taxon_id = as.character(wfo_taxon_id),
    height_m = as.numeric(height_m),
    woodiness = as.character(woodiness),
    growth_form = as.character(growth_form),
    leaf_phenology = as.character(leaf_phenology)
  )
```

**Output Schema** (68 columns):
- Identifiers: `wfo_taxon_id`, `wfo_taxon_name`, `family`, `genus`
- Morphology: `height_m`, `woodiness`, `growth_form`, `leaf_*`
- EIVE (renamed): `EIVE_L`, `EIVE_M`, `EIVE_T`, `EIVE_K`, `EIVE_N`, `EIVE_R`
- CSR (normalized): `C_norm`, `S_norm`, `R_norm`
- Ecosystem services: `*_rating`, `*_confidence` (10 services)
- Computed: `maintenance_level`, `drought_tolerant`, `fast_growing`, etc.
- Climate: `tier_*` (Köppen climate classifications)

**File Size**: 2.71 MB (ZSTD compression)

### File 2: convert_organisms_for_sql.R

**Purpose**: Flatten organism interaction list columns to relational format

**Input Schema**:
```
plant_wfo_id: string
pollinators: list<string>
herbivores: list<string>
pathogens: list<string>
predators: list<string>
flower_visitors: list<string>
natural_enemies: list<string>
parasitoids: list<string>
```

**Transformation**: One row per plant-organism interaction
```r
interaction_types <- list(
  pollinators = "pollinators",
  herbivores = "herbivores",
  pathogens = "pathogens",
  predators = "predators",
  flower_visitors = "flower_visitors",
  natural_enemies = "natural_enemies",
  parasitoids = "parasitoids"
)

for (interaction_name in names(interaction_types)) {
  flat_df <- organisms %>%
    select(plant_wfo_id, organism_list = all_of(col_name)) %>%
    filter(!is.na(organism_list), lengths(organism_list) > 0) %>%
    unnest_longer(organism_list) %>%
    mutate(
      interaction_type = interaction_name,
      organism_taxon = as.character(organism_list),

      # Categorize interactions
      interaction_category = case_when(
        interaction_type %in% c("pollinators", "flower_visitors") ~ "beneficial",
        interaction_type %in% c("herbivores", "pathogens") ~ "pest",
        interaction_type %in% c("predators", "natural_enemies", "parasitoids") ~ "biocontrol",
        TRUE ~ "other"
      )
    )
}
```

**Output Schema**:
- `plant_wfo_id`: string (FK to plants_sql)
- `organism_taxon`: string (organism scientific name)
- `interaction_type`: string (pollinators, herbivores, etc.)
- `interaction_category`: string (beneficial, pest, biocontrol)

**Output**: 276,601 rows

**SQL Query Examples**:
```sql
-- Get all pollinators for a plant
SELECT organism_taxon
FROM organisms_sql
WHERE plant_wfo_id = 'wfo-0000649953'
  AND interaction_type = 'pollinators';

-- Count interactions by category
SELECT interaction_category, COUNT(*)
FROM organisms_sql
WHERE plant_wfo_id = 'wfo-0000649953'
GROUP BY interaction_category;

-- Find plants with many pollinators
SELECT plant_wfo_id, COUNT(*) as pollinator_count
FROM organisms_sql
WHERE interaction_type = 'pollinators'
GROUP BY plant_wfo_id
HAVING COUNT(*) > 50
ORDER BY pollinator_count DESC;
```

### File 3: convert_fungi_for_sql.R

**Purpose**: Flatten fungal guild list columns to relational format

**Input Schema**:
```
plant_wfo_id: string
amf_fungi: list<string>
emf_fungi: list<string>
mycoparasite_fungi: list<string>
entomopathogenic_fungi: list<string>
endophytic_fungi: list<string>
saprotrophic_fungi: list<string>
```

**Transformation**: One row per plant-fungus association
```r
guild_types <- list(
  amf_fungi = "mycorrhizal_arbuscular",
  emf_fungi = "mycorrhizal_ectomycorrhizal",
  mycoparasite_fungi = "biocontrol_mycoparasite",
  entomopathogenic_fungi = "biocontrol_entomopathogen",
  endophytic_fungi = "endophytic",
  pathogenic_fungi = "pathogenic",
  saprotrophic_fungi = "saprotrophic"
)

for (guild_name in names(guild_types)) {
  flat_df <- fungi %>%
    select(plant_wfo_id, fungi_list = all_of(col_name)) %>%
    filter(!is.na(fungi_list), lengths(fungi_list) > 0) %>%
    unnest_longer(fungi_list) %>%
    mutate(
      guild = guild_name,
      guild_category = guild_types[[guild_name]],
      fungus_taxon = as.character(fungi_list)
    )
}
```

**Output Schema**:
- `plant_wfo_id`: string (FK to plants_sql)
- `fungus_taxon`: string (fungus scientific name)
- `guild`: string (amf_fungi, emf_fungi, etc.)
- `guild_category`: string (mycorrhizal, biocontrol, pathogenic, etc.)

**Output**: 100,013 rows, 3,729 unique fungi

**SQL Query Examples**:
```sql
-- Get mycorrhizal associations
SELECT fungus_taxon, guild
FROM fungi_sql
WHERE plant_wfo_id = 'wfo-0000649953'
  AND guild_category LIKE 'mycorrhizal%';

-- Find fungi that associate with many plants (generalists)
SELECT fungus_taxon, COUNT(DISTINCT plant_wfo_id) as plant_count
FROM fungi_sql
GROUP BY fungus_taxon
HAVING COUNT(DISTINCT plant_wfo_id) > 100
ORDER BY plant_count DESC;

-- Get biocontrol fungi available for a plant
SELECT fungus_taxon, guild
FROM fungi_sql
WHERE plant_wfo_id = 'wfo-0000649953'
  AND guild_category LIKE 'biocontrol%';
```

### Verification Script: verify_phase7_integrity.rs

**Purpose**: Ensure Phase 7 transformations maintain data parity with Phase 4 sources

**9 Integrity Tests**:

1. **Row Count Verification**:
   - Check `plants_sql` has same row count as source (11,713)
   - Check all plant IDs preserved

2. **CSR Normalization**:
   - Verify `C_norm = C / 100` (within 0.0001 tolerance)
   - Verify `S_norm = S / 100`
   - Verify `R_norm = R / 100`

3. **EIVE Column Renaming**:
   - Verify `EIVE_L` values match `EIVEres-L`
   - Verify all 6 EIVE columns correctly renamed

4. **Organisms Array Flattening**:
   - Count total array elements in source
   - Compare to row count in `organisms_sql`
   - Verify sum(lengths(arrays)) = flattened_row_count

5. **Organisms Referential Integrity**:
   - Check all `plant_wfo_id` in organisms_sql exist in plants_sql
   - Verify no orphaned FK references

6. **Fungi Array Flattening**:
   - Count total guild array elements
   - Compare to row count in `fungi_sql`

7. **Fungi Referential Integrity**:
   - Check all `plant_wfo_id` in fungi_sql exist in plants_sql

8. **Computed Columns Logic**:
   - Verify `maintenance_level` correctly derived from CSR
   - Verify `drought_tolerant = (S_norm > 0.6)`
   - Verify `fast_growing = (R_norm > 0.6)`

9. **Data Types**:
   - Verify all numeric columns are Float64 or Int32
   - Verify all text columns are Utf8
   - Verify boolean columns are Boolean

**Implementation**: Rust binary using DuckDB for SQL-based verification

**Result**: All 9 tests passed ✅

## Phase 8 API Server Design

### Query Engine Module (query_engine.rs)

**Core Structure**:
```rust
pub struct QueryEngine {
    ctx: Arc<SessionContext>,
}

impl QueryEngine {
    pub async fn new(data_dir: &str) -> DFResult<Self> {
        let ctx = SessionContext::new();

        // Register Phase 7 parquets with DataFusion
        ctx.register_listing_table(
            "plants",
            &format!("{}/plants_searchable_11711.parquet", data_dir),
            // ... config
        ).await?;

        ctx.register_listing_table("organisms", /* ... */).await?;
        ctx.register_listing_table("fungi", /* ... */).await?;

        Ok(Self { ctx: Arc::new(ctx) })
    }
}
```

**Key Methods**:

1. **search_plants()**: Filter plants by criteria
   - EIVE ranges (light, moisture, temperature, pH, fertility)
   - CSR thresholds
   - Morphology (height, woodiness, growth form)
   - Maintenance level
   - Common/latin name substring search

2. **find_similar()**: EIVE-based similarity search
   - Euclidean distance in 6D EIVE space
   - Top-K results ordered by distance

3. **get_organisms()**: Retrieve organism interactions
   - Filter by interaction type
   - Aggregate counts by category

4. **get_fungi()**: Retrieve fungal guilds
   - Filter by guild category
   - Group by mycorrhizal type

### API Server Module (api_server.rs)

**AppState**:
```rust
#[derive(Clone)]
pub struct AppState {
    query_engine: Arc<QueryEngine>,
    guild_scorer: Arc<GuildScorer>,
    cache: Cache<String, serde_json::Value>,
}
```

**Middleware Stack**:
1. **TraceLayer**: Structured logging of all requests
2. **CompressionLayer**: Brotli + gzip compression
3. **CorsLayer**: Permissive CORS for frontend
4. **ConcurrencyLimitLayer**: Per-route rate limiting

**Endpoints**:

1. **GET /health**: Health check
   - Response: `{"status": "healthy", "timestamp": "..."}`
   - No caching, no database access

2. **GET /api/plants/search**: Search plants
   - Query params: `?common_name=rose&min_light=7&max_moisture=5&limit=50`
   - Caching: Yes (5min TTL)
   - Latency: <10ms

3. **GET /api/plants/:id**: Get single plant
   - Path param: `wfo-0000649953`
   - Caching: Yes (5min TTL)
   - Latency: <5ms

4. **GET /api/plants/:id/organisms**: Get organism interactions
   - Optional query param: `?type=pollinators`
   - Caching: Yes
   - Latency: <10ms

5. **GET /api/plants/:id/fungi**: Get fungal guilds
   - Optional query param: `?category=mycorrhizal`
   - Caching: Yes
   - Latency: <10ms

6. **POST /api/plants/similar**: Find similar plants
   - Request body: `{"plant_id": "wfo-0000649953", "top_k": 20}`
   - Response: List of plants ordered by EIVE distance
   - Caching: Yes
   - Latency: <20ms

7. **POST /api/guilds/score**: Score plant guild
   - Request body: `{"plant_ids": ["wfo-...", ...], "guild_type": "forest_garden"}`
   - Response: `{"score": 0.87, "breakdown": {...}}`
   - No caching (results vary by context)
   - Latency: <500ms
   - Execution: `spawn_blocking` (Polars)

8. **POST /api/guilds/build**: Build optimal guild
   - Request body: `{"constraints": {...}, "target_size": 15}`
   - Response: List of recommended plants with scores
   - No caching
   - Latency: <2s
   - Execution: `spawn_blocking` (genetic algorithm)

### Caching Strategy

**Moka Cache Configuration**:
```rust
Cache::builder()
    .max_capacity(10_000)  // Max 10K cached responses
    .time_to_live(Duration::from_secs(300))  // 5min TTL
    .build()
```

**Cache Key Format**:
- Search: `"search:{json_hash}"` (hash of query params)
- Single plant: `"plant:{wfo_id}"`
- Organisms: `"organisms:{wfo_id}:{type?}"`
- Fungi: `"fungi:{wfo_id}:{category?}"`
- Similarity: `"similar:{wfo_id}:{top_k}"`

**Cache Invalidation**:
- TTL-based: 5 minutes (encyclopedia data changes infrequently)
- Manual: Expose `/admin/cache/clear` endpoint for deployments

**Expected Cache Hit Rate**: 60-70% for encyclopedia queries

## Performance Targets

### Throughput

**Target**: 100,000 requests/second sustained

**Breakdown**:
- Encyclopedia queries (90%): 90K req/s
  - Handled by DataFusion async queries
  - Expected latency: 5-10ms
  - Concurrency: 10K+ connections via Tokio

- Guild scoring (10%): 10K req/s
  - Handled by Polars via spawn_blocking
  - Expected latency: 100-500ms
  - Blocking pool: 16-32 threads

**Hardware Assumption**: 8-core / 16-thread CPU, 32GB RAM

**Scaling**:
- Vertical: 16-core → 200K req/s
- Horizontal: Load balancer + 3 instances → 300K req/s

### Latency

**Encyclopedia Queries** (DataFusion):

| Operation | p50 | p95 | p99 |
|-----------|-----|-----|-----|
| Plant search | 8ms | 15ms | 20ms |
| Single plant | 3ms | 8ms | 12ms |
| Organisms lookup | 5ms | 12ms | 18ms |
| Fungi lookup | 5ms | 12ms | 18ms |
| EIVE similarity | 12ms | 25ms | 35ms |

**Guild Scoring** (Polars):

| Operation | p50 | p95 | p99 |
|-----------|-----|-----|-----|
| Score 10 plants | 150ms | 300ms | 400ms |
| Score 50 plants | 450ms | 800ms | 1000ms |
| Build guild (genetic) | 1500ms | 3000ms | 5000ms |

### Resource Usage

**Memory**:
- Parquet data: 50MB compressed → 200MB decompressed
- Arrow schema: ~50MB
- DataFusion SessionContext: ~100MB
- Polars LazyFrames: ~150MB (lazy, not fully loaded)
- Moka cache: ~50MB (10K entries × 5KB avg)
- Tokio runtime: ~20MB
- **Total**: ~600MB baseline

**CPU**:
- DataFusion queries: 10-20% utilization (async I/O bound)
- Polars scoring: 100% utilization during scoring (CPU bound)
- Average utilization: 30-40% (90% light queries + 10% heavy scoring)

**Disk**:
- Phase 7 parquets: ~50MB
- Logs: ~1GB/day (compressed, rotated)

## Technology Stack

### Core Stack

**Language**: Rust (1.75+)
- Memory safety without garbage collection
- Zero-cost abstractions
- Native async/await
- Excellent ecosystem for data engineering

**Query Engine**: Apache Arrow DataFusion 35+
- Async SQL query execution
- Native parquet support with predicate pushdown
- Inter-query parallelism
- Arrow-native (zero-copy)

**DataFrame Library**: Polars 0.35+
- CPU-bound analytical workloads
- Intra-query parallelism (Rayon)
- LazyFrame query optimization
- Rich expression API

**Web Framework**: Axum 0.7+ (Tokio)
- Type-safe request handling
- Tower middleware ecosystem
- Fastest Rust web framework (166K req/s)
- Native async/await

**Cache**: Moka 0.12+
- Async-friendly in-memory cache
- TTL and size-based eviction
- High concurrency support

### Supporting Libraries

**HTTP**:
- Hyper 1.0 (low-level HTTP)
- Tower 0.4 (middleware)
- Tower-http 0.5 (compression, CORS)

**Serialization**:
- Serde 1.0 (trait-based serialization)
- Serde_json 1.0 (JSON support)

**Logging**:
- Tracing 0.1 (structured logging)
- Tracing-subscriber 0.3 (log collection)

**Testing**:
- Tokio-test (async test runtime)
- Criterion (benchmarking)

**Deployment**:
- Docker (containerization)
- Prometheus (metrics)
- Grafana (dashboards)

## Comparison to Alternatives

### Axum vs Node.js Frameworks

**Performance Benchmarks**:

| Framework | Req/s | Latency p50 | Language |
|-----------|-------|-------------|----------|
| Axum (Rust) | 166,000 | 0.6ms | Rust |
| Fastify (Node) | 48,000 | 2.1ms | JavaScript |
| Express (Node) | 25,000 | 4.0ms | JavaScript |

**Key Advantages of Axum**:
1. **3-4× faster** than fastest Node.js framework (Fastify)
2. **No garbage collection pauses** (consistent latency)
3. **Native CPU-bound processing** (Polars guild scorer)
4. **Lower memory footprint** (600MB vs 1.5GB for Node.js)
5. **Predictable resource usage** (no event loop blocking)

**Verdict**: Axum is the optimal choice for 100K req/s target with hybrid I/O + CPU workloads.

### DataFusion vs DuckDB

**Query Performance**:

| Operation | DataFusion | DuckDB | Advantage |
|-----------|------------|--------|-----------|
| Point query (indexed) | 3ms | 5ms | DataFusion |
| Full scan aggregation | 15ms | 8ms | DuckDB |
| Concurrent reads (1000x) | 50ms | 500ms | DataFusion |

**Concurrency Model**:
- **DataFusion**: Native async, inter-query parallelism, no write locks
- **DuckDB**: Blocking API, single-writer, MVCC for reads

**Verdict**: DataFusion superior for high-concurrency web API workloads.

## Next Steps

### Immediate (Phase 8)

1. Add DataFusion dependencies to Cargo.toml
2. Implement query_engine.rs module
3. Implement api_server.rs with 8 endpoints
4. Write integration tests
5. Add Moka caching layer
6. Create Dockerfile

**Timeline**: 2-3 days development + 1 day testing

### Short-term (Phase 9)

1. Port R encyclopedia generator to Rust
2. Integrate with query_engine for data access
3. Benchmark performance (target: <10min for 11,711 pages)

**Timeline**: 3-4 days development

### Medium-term (Phase 10-11)

1. Implement constraint-based guild building
2. Add genetic algorithm for multi-objective optimization
3. Deploy to Cloud Run or Hetzner
4. Set up monitoring (Prometheus + Grafana)

**Timeline**: 1-2 weeks

## References

### Documentation

- [Apache Arrow DataFusion](https://arrow.apache.org/datafusion/)
- [Polars User Guide](https://pola-rs.github.io/polars-book/)
- [Axum Documentation](https://docs.rs/axum/latest/axum/)
- [Tokio Async Runtime](https://tokio.rs/)
- [Tower Middleware](https://github.com/tower-rs/tower)
- [Moka Cache](https://github.com/moka-rs/moka)

### Benchmarks

- [Rust Web Framework Benchmarks 2024](https://www.rustfinity.com/blog/best-rust-web-frameworks)
- [Axum vs Node.js Performance](https://randiekas.medium.com/rust-the-fastest-rust-web-framework-in-2024-cf738c40343b)
- [DataFusion Query Performance](https://arrow.apache.org/datafusion/user-guide/introduction.html#performance)

### Related Documents

- [Phase 8 API Server Implementation Plan](../src/Stage_4/Phase_7_datafusion/Phase_8_API_Server_Plan.md)
- [Phase 8 Architecture Review](../src/Stage_4/Phase_7_datafusion/Phase_8_Architecture_Review.md)
- [Encyclopedia Generator Implementation](./Encyclopedia_Generator_Implementation.md)
- [Guild Scorer Performance Benchmark](./Guild_Scorer_Performance_Benchmark.md)

## Conclusion

The hybrid DataFusion + Polars architecture provides an optimal solution for the project's dual requirements:

1. **High-concurrency encyclopedia queries** (90% traffic) → DataFusion async queries
2. **CPU-bound guild scoring** (10% traffic) → Polars via spawn_blocking

This approach leverages each engine's strengths without compromise, targeting 100K req/s throughput with sub-10ms latency for plant searches. The Rust stack ensures predictable performance, low resource usage, and eliminates garbage collection concerns present in Node.js alternatives.

Phase 7 successfully prepared SQL-optimized parquets with verified data integrity. Phase 8 implementation is ready to begin with a clear technical roadmap.
