# Phase 8: DataFusion API Server Implementation Plan

## Overview

Build a high-performance REST API server combining:
- **DataFusion** for async SQL queries on Phase 7 parquets (90% traffic)
- **Polars** for CPU-bound guild scoring (10% traffic)
- **Axum** web framework on Tokio runtime
- **Moka** for response caching
- **Tower** middleware for compression, CORS, tracing

**Target Performance**: 100K requests/second, <10ms plant search latency, <500ms guild score latency

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Axum API Server                      │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Middleware: Compression, CORS, Tracing          │  │
│  └──────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Moka Cache (10K entries, 5min TTL)              │  │
│  └──────────────────────────────────────────────────┘  │
│  ┌─────────────────┐  ┌──────────────────────────────┐ │
│  │  DataFusion     │  │  Polars Guild Scorer         │ │
│  │  Query Engine   │  │  (via spawn_blocking)        │ │
│  │  (async I/O)    │  │  (CPU-bound)                 │ │
│  └─────────────────┘  └──────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
              ▼                           ▼
   ┌──────────────────────┐    ┌──────────────────────┐
   │  Phase 7 Parquets    │    │  Polars LazyFrames   │
   │  - plants_sql        │    │  - organisms         │
   │  - organisms_sql     │    │  - fungi             │
   │  - fungi_sql         │    │  - traits            │
   └──────────────────────┘    └──────────────────────┘
```

## Phase 8 Sub-Phases

### Phase 8.1: Add Dependencies and Project Structure

**File**: `shipley_checks/src/Stage_4/guild_scorer_rust/Cargo.toml`

Add dependencies:
```toml
[dependencies]
# Web framework
axum = { version = "0.7", features = ["macros"] }
tokio = { version = "1.35", features = ["full"] }
tower = { version = "0.4", features = ["util"] }
tower-http = { version = "0.5", features = ["fs", "compression-gzip", "compression-br", "cors", "trace"] }

# DataFusion
datafusion = "35"
arrow = "51"

# Caching
moka = { version = "0.12", features = ["future"] }

# Serialization
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

# HTTP
hyper = { version = "1.0", features = ["full"] }

# Logging
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
```

Create module structure:
```
guild_scorer_rust/src/
├── lib.rs                 # Existing guild scorer
├── query_engine.rs        # NEW: DataFusion query engine
├── api_server.rs          # NEW: Axum API server
└── bin/
    └── api_server.rs      # NEW: Binary entry point
```

### Phase 8.2: Implement DataFusion Query Engine

**File**: `shipley_checks/src/Stage_4/guild_scorer_rust/src/query_engine.rs`

```rust
use datafusion::prelude::*;
use datafusion::error::Result as DFResult;
use std::sync::Arc;

pub struct QueryEngine {
    ctx: Arc<SessionContext>,
}

impl QueryEngine {
    pub async fn new(data_dir: &str) -> DFResult<Self> {
        let ctx = SessionContext::new();

        // Register Phase 7 parquets
        ctx.register_listing_table(
            "plants",
            &format!("{}/plants_sql.parquet", data_dir),
            ListingTableConfigWithSchema::new(/*...*/),
            None,
        ).await?;

        ctx.register_listing_table(
            "organisms",
            &format!("{}/organisms_sql.parquet", data_dir),
            ListingTableConfigWithSchema::new(/*...*/),
            None,
        ).await?;

        ctx.register_listing_table(
            "fungi",
            &format!("{}/fungi_sql.parquet", data_dir),
            ListingTableConfigWithSchema::new(/*...*/),
            None,
        ).await?;

        Ok(Self { ctx: Arc::new(ctx) })
    }

    // Raw SQL execution
    pub async fn query(&self, sql: &str) -> DFResult<Vec<RecordBatch>> {
        let df = self.ctx.sql(sql).await?;
        df.collect().await
    }

    // Plant search by filters
    pub async fn search_plants(&self, filters: PlantFilters) -> DFResult<Vec<RecordBatch>> {
        let mut conditions = Vec::new();

        if let Some(ref name) = filters.common_name {
            conditions.push(format!("vernacular_names LIKE '%{}%'", name));
        }

        if let Some(ref latin) = filters.latin_name {
            conditions.push(format!("wfo_taxon_name LIKE '%{}%'", latin));
        }

        if let Some(min_light) = filters.min_light {
            conditions.push(format!("EIVE_L >= {}", min_light));
        }

        // ... other filters

        let where_clause = if conditions.is_empty() {
            String::new()
        } else {
            format!("WHERE {}", conditions.join(" AND "))
        };

        let sql = format!(
            "SELECT * FROM plants {} LIMIT {}",
            where_clause,
            filters.limit.unwrap_or(100)
        );

        self.query(&sql).await
    }

    // EIVE-based similarity search
    pub async fn find_similar(&self, plant_id: &str, top_k: usize) -> DFResult<Vec<RecordBatch>> {
        let sql = format!(
            r#"
            WITH target AS (
                SELECT EIVE_L, EIVE_M, EIVE_T, EIVE_K, EIVE_N, EIVE_R
                FROM plants
                WHERE wfo_taxon_id = '{}'
            )
            SELECT
                p.*,
                SQRT(
                    POW(p.EIVE_L - t.EIVE_L, 2) +
                    POW(p.EIVE_M - t.EIVE_M, 2) +
                    POW(p.EIVE_T - t.EIVE_T, 2) +
                    POW(p.EIVE_K - t.EIVE_K, 2) +
                    POW(p.EIVE_N - t.EIVE_N, 2) +
                    POW(p.EIVE_R - t.EIVE_R, 2)
                ) AS eive_distance
            FROM plants p, target t
            WHERE p.wfo_taxon_id != '{}'
            ORDER BY eive_distance ASC
            LIMIT {}
            "#,
            plant_id, plant_id, top_k
        );

        self.query(&sql).await
    }

    // Get organisms for plant
    pub async fn get_organisms(&self, plant_id: &str) -> DFResult<Vec<RecordBatch>> {
        let sql = format!(
            "SELECT * FROM organisms WHERE plant_wfo_id = '{}' ORDER BY interaction_type",
            plant_id
        );
        self.query(&sql).await
    }

    // Get fungi for plant
    pub async fn get_fungi(&self, plant_id: &str) -> DFResult<Vec<RecordBatch>> {
        let sql = format!(
            "SELECT * FROM fungi WHERE plant_wfo_id = '{}' ORDER BY guild",
            plant_id
        );
        self.query(&sql).await
    }
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct PlantFilters {
    pub common_name: Option<String>,
    pub latin_name: Option<String>,
    pub min_light: Option<f64>,
    pub max_light: Option<f64>,
    pub min_moisture: Option<f64>,
    pub max_moisture: Option<f64>,
    pub maintenance_level: Option<String>,
    pub drought_tolerant: Option<bool>,
    pub limit: Option<usize>,
}
```

### Phase 8.3: Implement Axum API Server

**File**: `shipley_checks/src/Stage_4/guild_scorer_rust/src/api_server.rs`

```rust
use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::{IntoResponse, Json},
    routing::{get, post},
    Router,
};
use moka::future::Cache;
use std::sync::Arc;
use tokio::task;
use tower_http::{
    compression::CompressionLayer,
    cors::CorsLayer,
    trace::TraceLayer,
};

use crate::query_engine::{QueryEngine, PlantFilters};
use crate::GuildScorer; // Existing Polars-based scorer

// Shared application state
#[derive(Clone)]
pub struct AppState {
    query_engine: Arc<QueryEngine>,
    guild_scorer: Arc<GuildScorer>,
    cache: Cache<String, serde_json::Value>,
}

impl AppState {
    pub async fn new(data_dir: &str) -> anyhow::Result<Self> {
        let query_engine = Arc::new(QueryEngine::new(data_dir).await?);
        let guild_scorer = Arc::new(GuildScorer::new(data_dir)?);

        // Moka cache: 10K entries, 5min TTL
        let cache = Cache::builder()
            .max_capacity(10_000)
            .time_to_live(std::time::Duration::from_secs(300))
            .build();

        Ok(Self {
            query_engine,
            guild_scorer,
            cache,
        })
    }
}

// Build router with all endpoints
pub fn create_router(state: AppState) -> Router {
    Router::new()
        .route("/health", get(health_check))
        .route("/api/plants/search", get(search_plants))
        .route("/api/plants/:id", get(get_plant))
        .route("/api/plants/:id/organisms", get(get_organisms))
        .route("/api/plants/:id/fungi", get(get_fungi))
        .route("/api/plants/similar", post(find_similar))
        .route("/api/guilds/score", post(score_guild))
        .route("/api/guilds/build", post(build_guild))
        .layer(CompressionLayer::new())
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

// Health check endpoint
async fn health_check() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "healthy",
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}

// Search plants by filters
async fn search_plants(
    State(state): State<AppState>,
    Query(filters): Query<PlantFilters>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let cache_key = format!("search:{:?}", filters);

    // Check cache
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(cached));
    }

    // Execute query
    let batches = state.query_engine.search_plants(filters)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let result = batches_to_json(&batches);
    state.cache.insert(cache_key, result.clone()).await;

    Ok(Json(result))
}

// Get single plant by ID
async fn get_plant(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let cache_key = format!("plant:{}", id);

    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(cached));
    }

    let sql = format!("SELECT * FROM plants WHERE wfo_taxon_id = '{}'", id);
    let batches = state.query_engine.query(&sql)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    if batches.is_empty() || batches[0].num_rows() == 0 {
        return Err((StatusCode::NOT_FOUND, format!("Plant {} not found", id)));
    }

    let result = batches_to_json(&batches);
    state.cache.insert(cache_key, result.clone()).await;

    Ok(Json(result))
}

// Get organisms for plant
async fn get_organisms(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let batches = state.query_engine.get_organisms(&id)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(batches_to_json(&batches)))
}

// Get fungi for plant
async fn get_fungi(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let batches = state.query_engine.get_fungi(&id)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(batches_to_json(&batches)))
}

// Find similar plants
async fn find_similar(
    State(state): State<AppState>,
    Json(payload): Json<SimilarityRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let batches = state.query_engine.find_similar(&payload.plant_id, payload.top_k)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(batches_to_json(&batches)))
}

// Score guild (CPU-bound Polars work via spawn_blocking)
async fn score_guild(
    State(state): State<AppState>,
    Json(payload): Json<GuildScoreRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let scorer = state.guild_scorer.clone();

    // Run CPU-bound work in blocking thread pool
    let result = task::spawn_blocking(move || {
        scorer.score_guild(&payload.plant_ids, &payload.guild_type)
    })
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(serde_json::json!(result)))
}

// Build guild (CPU-bound Polars work)
async fn build_guild(
    State(state): State<AppState>,
    Json(payload): Json<GuildBuildRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let scorer = state.guild_scorer.clone();

    let result = task::spawn_blocking(move || {
        scorer.build_guild(&payload.constraints)
    })
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(serde_json::json!(result)))
}

// Request/Response types
#[derive(serde::Deserialize)]
struct SimilarityRequest {
    plant_id: String,
    top_k: usize,
}

#[derive(serde::Deserialize)]
struct GuildScoreRequest {
    plant_ids: Vec<String>,
    guild_type: String,
}

#[derive(serde::Deserialize)]
struct GuildBuildRequest {
    constraints: serde_json::Value,
}

// Helper: Convert Arrow RecordBatches to JSON
fn batches_to_json(batches: &[arrow::record_batch::RecordBatch]) -> serde_json::Value {
    // TODO: Implement Arrow -> JSON conversion
    serde_json::json!({
        "rows": batches.iter().map(|b| b.num_rows()).sum::<usize>(),
        "data": [] // Placeholder
    })
}
```

### Phase 8.4: Binary Entry Point

**File**: `shipley_checks/src/Stage_4/guild_scorer_rust/src/bin/api_server.rs`

```rust
use guild_scorer_rust::api_server::{create_router, AppState};
use std::net::SocketAddr;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,axum=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Data directory from environment or default
    let data_dir = std::env::var("DATA_DIR")
        .unwrap_or_else(|_| "./shipley_checks/stage3".to_string());

    // Initialize application state
    tracing::info!("Initializing application state...");
    let state = AppState::new(&data_dir).await?;

    // Create router
    let app = create_router(state);

    // Start server
    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));
    tracing::info!("Starting server on {}", addr);

    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await?;

    Ok(())
}
```

### Phase 8.5: Testing Strategy

Create test suite covering:

1. **Unit tests** for QueryEngine methods
2. **Integration tests** for API endpoints using Axum's testing utilities
3. **Benchmark tests** for 100K req/s validation
4. **Load tests** using tools like `wrk` or `oha`

**File**: `shipley_checks/src/Stage_4/guild_scorer_rust/tests/api_tests.rs`

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::StatusCode;
    use tower::ServiceExt;

    #[tokio::test]
    async fn test_health_check() {
        let state = AppState::new("./test_data").await.unwrap();
        let app = create_router(state);

        let response = app
            .oneshot(Request::builder().uri("/health").body(Body::empty()).unwrap())
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_search_plants() {
        // Test plant search endpoint
    }

    #[tokio::test]
    async fn test_guild_scoring() {
        // Test guild scoring endpoint with spawn_blocking
    }
}
```

### Phase 8.6: Performance Optimization Checklist

- [ ] Enable DataFusion predicate pushdown (automatic)
- [ ] Use Arrow IPC format for zero-copy serialization where possible
- [ ] Configure Moka cache size based on memory profiling
- [ ] Add connection pooling if needed
- [ ] Use `spawn_blocking` thread pool sizing based on CPU cores
- [ ] Add rate limiting via `ConcurrencyLimitLayer`
- [ ] Enable HTTP/2 for multiplexing
- [ ] Add metrics collection (Prometheus/OpenTelemetry)

### Phase 8.7: Deployment Configuration

**File**: `shipley_checks/src/Stage_4/guild_scorer_rust/Dockerfile`

```dockerfile
FROM rust:1.75 as builder
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release --bin api_server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/api_server /usr/local/bin/
COPY shipley_checks/stage3 /data
ENV DATA_DIR=/data
EXPOSE 3000
CMD ["api_server"]
```

**Environment variables**:
- `DATA_DIR`: Path to Phase 7 parquets
- `RUST_LOG`: Logging level (info, debug, trace)
- `PORT`: Server port (default 3000)
- `CACHE_SIZE`: Moka cache max entries (default 10000)
- `CACHE_TTL_SECS`: Cache TTL in seconds (default 300)

## Expected Outcomes

### Performance Metrics
- Plant search: <10ms p50, <20ms p99
- Guild scoring: <500ms p50, <1s p99
- Throughput: 100K req/s sustained (verified via load testing)
- Memory: <2GB for typical workload

### API Endpoints

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

## Next Steps After Phase 8

1. **Phase 9**: Port encyclopedia generator from R to Rust using DataFusion
2. **Phase 10**: Implement advanced guild building with genetic algorithms
3. **Phase 11**: Production deployment (Cloud Run or Hetzner)
4. **Phase 12**: Add WebSocket support for real-time updates
5. **Phase 13**: Build web UI frontend

## References

- DataFusion docs: https://arrow.apache.org/datafusion/
- Axum docs: https://docs.rs/axum/latest/axum/
- Moka caching: https://github.com/moka-rs/moka
- Tower middleware: https://github.com/tower-rs/tower
