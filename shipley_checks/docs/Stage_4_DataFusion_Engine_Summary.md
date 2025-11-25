# Stage 4: DataFusion SQL Query Engine

## Overview

Phase 8 implements a high-performance REST API for querying plant ecological data using Apache DataFusion (Rust SQL engine) and Polars for guild scoring. The API serves 11,713 plants with EIVE indicators, CSR strategies, organism interactions, and fungal associations.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Axum REST API                          │
│                      (Port 3000)                            │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │   DataFusion    │  │  Guild Scorer   │  │  Moka Cache │ │
│  │  Query Engine   │  │    (Polars)     │  │   (10K/5m)  │ │
│  └────────┬────────┘  └────────┬────────┘  └─────────────┘ │
│           │                    │                            │
│  ┌────────▼────────────────────▼────────┐                  │
│  │         Phase 7 Parquets             │                  │
│  │  plants_searchable_11711.parquet     │                  │
│  │  organisms_searchable.parquet        │                  │
│  │  fungi_searchable.parquet            │                  │
│  └──────────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

## Data Sources

| Dataset | Records | Columns | Description |
|---------|---------|---------|-------------|
| plants | 11,713 | 68 | Plant encyclopedia with EIVE, CSR, traits, ecosystem services |
| organisms | 290,880 | 9 | Plant-organism interactions (pollinators, pests, biocontrol) |
| fungi | 100,013 | 17 | Plant-fungus associations (mycorrhizal, pathogenic, biocontrol) |

**Source parquets:** `shipley_checks/stage4/phase7_output/`

## API Endpoints

### Health Check
```
GET /health
```

### Plant Search
```
GET /api/plants/search?{filters}&limit=N
```

**EIVE Filters:**
- `min_light`, `max_light` (1-9)
- `min_moisture`, `max_moisture` (1-12)
- `min_temperature`, `max_temperature` (1-9)
- `min_nitrogen`, `max_nitrogen` (1-9)
- `min_ph`, `max_ph` (1-9)

**CSR Filters:**
- `min_c`, `max_c` (0-1, competitive)
- `min_s`, `max_s` (0-1, stress-tolerant)
- `min_r`, `max_r` (0-1, ruderal)

**Boolean Filters:**
- `drought_tolerant`, `fast_growing`

### Single Plant Lookup
```
GET /api/plants/{wfo_id}
```

### Organism Interactions
```
GET /api/plants/{wfo_id}/organisms
GET /api/plants/{wfo_id}/organisms?interaction_type=pollinators
```

Interaction types: `pollinators`, `herbivores`, `predators_hasHost`

### Fungal Associations
```
GET /api/plants/{wfo_id}/fungi
GET /api/plants/{wfo_id}/fungi?guild_category=mycorrhizal
```

Guild categories: `mycorrhizal`, `pathogenic`, `biocontrol`

### Similarity Search
```
POST /api/plants/similar
Body: {"plant_id": "wfo-xxx", "top_k": 10}
```

Returns plants with smallest EIVE Euclidean distance in 6D space.

### Guild Scoring
```
POST /api/guilds/score
Body: {"plant_ids": ["wfo-xxx", "wfo-yyy", ...]}
```

Returns 7-metric guild compatibility score (0-100).

## Performance

**Measured on Docker release build:**

| Endpoint | Cold | Cached |
|----------|------|--------|
| Search | 31ms | 1ms |
| Single plant | 16ms | <1ms |
| Guild scoring | 17-27ms | - |
| Similarity | ~50ms | - |

**Targets:** Search <50ms, Guild scoring <500ms

## Files

```
shipley_checks/src/Stage_4/guild_scorer_rust/
├── src/
│   ├── query_engine.rs      # DataFusion SQL queries
│   ├── api_server.rs        # Axum routes and handlers
│   ├── bin/api_server.rs    # Server entry point
│   └── ...
├── tests/
│   └── api_integration_tests.rs  # 31 integration tests
├── Dockerfile               # Production container
└── docker-compose.yml       # Local deployment
```

## Running

### Local Development
```bash
cd /home/olier/ellenberg
cargo run --manifest-path shipley_checks/src/Stage_4/guild_scorer_rust/Cargo.toml \
  --features api --bin api_server
```

### Docker Production
```bash
cd /home/olier/ellenberg
docker compose -f shipley_checks/src/Stage_4/guild_scorer_rust/docker-compose.yml up --build -d
```

### Integration Tests
```bash
cd /home/olier/ellenberg
cargo test --manifest-path shipley_checks/src/Stage_4/guild_scorer_rust/Cargo.toml \
  --features api --test api_integration_tests
```

## Test Coverage

**31 integration tests covering:**

1. Health check
2. Plant search (no filters, EIVE filters, CSR filters)
3. Single plant lookup (found, not found)
4. Reference plant accuracy (Quercus robur → Fagaceae, Coffea arabica → Rubiaceae)
5. Data integrity (EIVE ranges 1-9/1-12, CSR normalization 0-1)
6. Organism filtering by interaction type
7. Fungi filtering by guild category
8. Similarity search ordering
9. Guild scoring (structure, bounds 0-100, determinism, edge cases)
10. Caching consistency
11. Performance timing (<50ms search, <500ms guild)

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| DATA_DIR | `shipley_checks/stage4/phase7_output` | Parquet data directory |
| CLIMATE_TIER | `tier_3_humid_temperate` | Climate calibration tier |
| PORT | `3000` | Server port |
| RUST_LOG | `info` | Log level |

## Dependencies

- **DataFusion 43.0**: SQL query engine for parquet files
- **Polars 0.46**: DataFrame operations for guild scoring
- **Axum 0.7**: Async web framework
- **Moka**: In-memory cache (10K entries, 5min TTL)
- **Tower-HTTP**: CORS and request tracing middleware
