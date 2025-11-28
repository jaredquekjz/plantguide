// Phase 8.3: Axum API Server Module
//
// Purpose: REST API server combining DataFusion (queries) + Polars (guild scoring)
// Performance target: 100K req/s, <10ms plant search, <500ms guild scoring

#[cfg(feature = "api")]
use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::{IntoResponse, Json},
    routing::{get, post},
    Router,
};

#[cfg(feature = "api")]
use tower_http::{
    compression::CompressionLayer,
    cors::CorsLayer,
    trace::TraceLayer,
};

#[cfg(feature = "api")]
use moka::future::Cache;

#[cfg(feature = "api")]
use std::sync::Arc;

#[cfg(feature = "api")]
use std::time::Duration;

#[cfg(feature = "api")]
use crate::query_engine::{QueryEngine, PlantFilters};

#[cfg(feature = "api")]
use crate::scorer::GuildScorer;

#[cfg(feature = "api")]
use crate::encyclopedia::{EncyclopediaGenerator, OrganismCounts, FungalCounts};

#[cfg(feature = "api")]
use datafusion::arrow::array::RecordBatch;

#[cfg(feature = "api")]
use datafusion::arrow::json::ArrayWriter;

// ============================================================================
// Application State
// ============================================================================

#[cfg(feature = "api")]
#[derive(Clone)]
pub struct AppState {
    pub query_engine: Arc<QueryEngine>,
    pub guild_scorer: Arc<GuildScorer>,
    pub encyclopedia: Arc<EncyclopediaGenerator>,
    pub cache: Cache<String, serde_json::Value>,
}

#[cfg(feature = "api")]
impl AppState {
    pub async fn new(data_dir: &str, climate_tier: &str) -> anyhow::Result<Self> {
        tracing::info!("Initializing DataFusion query engine...");
        let query_engine = Arc::new(QueryEngine::new(data_dir).await?);

        tracing::info!("Initializing Polars guild scorer...");
        let guild_scorer = Arc::new(GuildScorer::new("7plant", climate_tier)?);

        tracing::info!("Initializing encyclopedia generator...");
        let encyclopedia = Arc::new(EncyclopediaGenerator::new());

        tracing::info!("Initializing Moka cache...");
        let cache = Cache::builder()
            .max_capacity(10_000) // 10K entries
            .time_to_live(Duration::from_secs(300)) // 5 min TTL
            .build();

        Ok(Self {
            query_engine,
            guild_scorer,
            encyclopedia,
            cache,
        })
    }
}

// ============================================================================
// Router
// ============================================================================

#[cfg(feature = "api")]
pub fn create_router(state: AppState) -> Router {
    Router::new()
        // Health check
        .route("/health", get(health_check))
        // Plant endpoints
        .route("/api/plants/search", get(search_plants))
        .route("/api/plants/:id", get(get_plant))
        .route("/api/plants/:id/organisms", get(get_organisms))
        .route("/api/plants/:id/fungi", get(get_fungi))
        .route("/api/plants/similar", post(find_similar))
        // Guild endpoints
        .route("/api/guilds/score", post(score_guild))
        // Encyclopedia endpoint
        .route("/api/encyclopedia/:id", get(get_encyclopedia))
        // Middleware (applied in reverse order)
        .layer(CompressionLayer::new()) // gzip + brotli compression
        .layer(CorsLayer::permissive()) // Allow all origins (adjust for production)
        .layer(TraceLayer::new_for_http()) // Request logging
        .with_state(state)
}

// ============================================================================
// Endpoint Handlers
// ============================================================================

#[cfg(feature = "api")]
async fn health_check() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "healthy",
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}

#[cfg(feature = "api")]
async fn search_plants(
    State(state): State<AppState>,
    Query(filters): Query<PlantFilters>,
) -> Result<Json<serde_json::Value>, AppError> {
    // Generate cache key from filters
    let cache_key = format!("search:{:?}", filters);

    // Check cache
    if let Some(cached) = state.cache.get(&cache_key).await {
        tracing::debug!("Cache hit for search query");
        return Ok(Json(cached));
    }

    // Execute query
    tracing::debug!("Executing plant search query");
    let batches = state
        .query_engine
        .search_plants(&filters)
        .await
        .map_err(|e| AppError::DataFusion(e.to_string()))?;

    // Convert to JSON
    let result = batches_to_json(&batches)?;

    // Cache result
    state.cache.insert(cache_key, result.clone()).await;

    Ok(Json(result))
}

#[cfg(feature = "api")]
async fn get_plant(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    let cache_key = format!("plant:{}", id);

    // Check cache
    if let Some(cached) = state.cache.get(&cache_key).await {
        tracing::debug!("Cache hit for plant {}", id);
        return Ok(Json(cached));
    }

    // Execute query
    tracing::debug!("Fetching plant {}", id);
    let batches = state
        .query_engine
        .get_plant(&id)
        .await
        .map_err(|e| AppError::DataFusion(e.to_string()))?;

    // Check if plant exists
    if batches.is_empty() || batches[0].num_rows() == 0 {
        return Err(AppError::NotFound(format!("Plant {} not found", id)));
    }

    // Convert to JSON
    let result = batches_to_json(&batches)?;

    // Cache result
    state.cache.insert(cache_key, result.clone()).await;

    Ok(Json(result))
}

#[cfg(feature = "api")]
async fn get_organisms(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Query(params): Query<OrganismQuery>,
) -> Result<Json<serde_json::Value>, AppError> {
    let cache_key = format!("organisms:{}:{:?}", id, params.interaction_type);

    // Check cache
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(cached));
    }

    // Execute query
    let batches = state
        .query_engine
        .get_organisms(&id, params.interaction_type.as_deref())
        .await
        .map_err(|e| AppError::DataFusion(e.to_string()))?;

    // Convert to JSON
    let result = batches_to_json(&batches)?;

    // Cache result
    state.cache.insert(cache_key, result.clone()).await;

    Ok(Json(result))
}

#[cfg(feature = "api")]
async fn get_fungi(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Query(params): Query<FungiQuery>,
) -> Result<Json<serde_json::Value>, AppError> {
    let cache_key = format!("fungi:{}:{:?}", id, params.guild_category);

    // Check cache
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(cached));
    }

    // Execute query
    let batches = state
        .query_engine
        .get_fungi(&id, params.guild_category.as_deref())
        .await
        .map_err(|e| AppError::DataFusion(e.to_string()))?;

    // Convert to JSON
    let result = batches_to_json(&batches)?;

    // Cache result
    state.cache.insert(cache_key, result.clone()).await;

    Ok(Json(result))
}

#[cfg(feature = "api")]
async fn find_similar(
    State(state): State<AppState>,
    Json(payload): Json<SimilarityRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    let cache_key = format!("similar:{}:{}", payload.plant_id, payload.top_k);

    // Check cache
    if let Some(cached) = state.cache.get(&cache_key).await {
        return Ok(Json(cached));
    }

    // Execute query
    let batches = state
        .query_engine
        .find_similar(&payload.plant_id, payload.top_k)
        .await
        .map_err(|e| AppError::DataFusion(e.to_string()))?;

    // Convert to JSON
    let result = batches_to_json(&batches)?;

    // Cache result
    state.cache.insert(cache_key, result.clone()).await;

    Ok(Json(result))
}

#[cfg(feature = "api")]
async fn score_guild(
    State(state): State<AppState>,
    Json(payload): Json<GuildScoreRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    // CPU-bound work: run in blocking thread pool
    let scorer = state.guild_scorer.clone();
    let guild_size = payload.plant_ids.len();

    tracing::info!("Scoring guild with {} plants", guild_size);

    let result = tokio::task::spawn_blocking(move || {
        // Score the guild (use parallel version for better performance)
        scorer.score_guild_parallel(&payload.plant_ids)
    })
    .await
    .map_err(|e| AppError::Internal(format!("Task join error: {}", e)))?
    .map_err(|e| AppError::Internal(format!("Guild scoring error: {}", e)))?;

    // Convert GuildScore to JSON
    let response = serde_json::json!({
        "guild_size": guild_size,
        "overall_score": result.overall_score,
        "metrics": {
            "m1_phylogenetic_diversity": result.metrics[0],
            "m2_csr_balance": result.metrics[1],
            "m3_eive_compatibility": result.metrics[2],
            "m4_pollinator_pest_balance": result.metrics[3],
            "m5_pest_biocontrol": result.metrics[4],
            "m6_growth_form_diversity": result.metrics[5],
            "m7_nutrient_cycling": result.metrics[6],
        },
        "raw_scores": result.raw_scores,
        "normalized": result.normalized,
    });

    Ok(Json(response))
}

/// Generate encyclopedia page for a plant
#[cfg(feature = "api")]
async fn get_encyclopedia(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<impl IntoResponse, AppError> {
    let cache_key = format!("encyclopedia:{}", id);

    // Check cache for pre-generated markdown
    if let Some(cached) = state.cache.get(&cache_key).await {
        tracing::debug!("Cache hit for encyclopedia {}", id);
        if let Some(markdown) = cached.as_str() {
            return Ok((
                [("Content-Type", "text/markdown; charset=utf-8")],
                markdown.to_string(),
            ));
        }
    }

    tracing::debug!("Generating encyclopedia for plant {}", id);

    // 1. Fetch plant data
    let plant_batches = state
        .query_engine
        .get_plant(&id)
        .await
        .map_err(|e| AppError::DataFusion(e.to_string()))?;

    if plant_batches.is_empty() || plant_batches[0].num_rows() == 0 {
        return Err(AppError::NotFound(format!("Plant {} not found", id)));
    }

    // Convert plant batch to JSON then HashMap
    let plant_json = batches_to_json(&plant_batches)?;
    let plant_data: std::collections::HashMap<String, serde_json::Value> = plant_json
        .get("data")
        .and_then(|d| d.as_array())
        .and_then(|arr| arr.first())
        .and_then(|obj| serde_json::from_value(obj.clone()).ok())
        .ok_or_else(|| AppError::Internal("Failed to parse plant data".to_string()))?;

    // 2. Fetch organism summary for counts
    let organism_counts = match state.query_engine.get_organism_summary(&id).await {
        Ok(batches) => parse_organism_counts(&batches),
        Err(_) => None,
    };

    // 3. Fetch fungi summary for counts
    let fungal_counts = match state.query_engine.get_fungi_summary(&id).await {
        Ok(batches) => parse_fungal_counts(&batches),
        Err(_) => None,
    };

    // 4. Generate encyclopedia markdown
    // Note: OrganismProfile, ranked_pathogens, beneficial_fungi, related_species not yet implemented in API
    let markdown = state
        .encyclopedia
        .generate(&id, &plant_data, organism_counts, fungal_counts, None, None, None, None, 0)
        .map_err(|e| AppError::Internal(e))?;

    // Cache the result
    state.cache.insert(cache_key, serde_json::json!(markdown)).await;

    Ok((
        [("Content-Type", "text/markdown; charset=utf-8")],
        markdown,
    ))
}

/// Parse organism summary batches into OrganismCounts
#[cfg(feature = "api")]
fn parse_organism_counts(batches: &[RecordBatch]) -> Option<OrganismCounts> {
    if batches.is_empty() {
        return None;
    }

    let json = batches_to_json(batches).ok()?;
    let data = json.get("data")?.as_array()?;

    let mut pollinators = 0;
    let mut visitors = 0;
    let mut herbivores = 0;
    let mut pathogens = 0;
    let mut predators = 0;

    for row in data {
        let interaction_type = row.get("interaction_type")?.as_str()?;
        let count = row.get("count")?.as_u64()? as usize;

        match interaction_type.to_lowercase().as_str() {
            "pollinator" | "pollinators" => pollinators += count,
            "visitor" | "visitors" | "flower_visitor" => visitors += count,
            "herbivore" | "herbivores" => herbivores += count,
            "pathogen" | "pathogens" | "pathogenic" => pathogens += count,
            "predator" | "predators" | "natural_enemy" => predators += count,
            _ => {}
        }
    }

    // Only return if we have any data
    if pollinators + visitors + herbivores + pathogens + predators > 0 {
        Some(OrganismCounts {
            pollinators,
            visitors,
            herbivores,
            pathogens,
            predators,
        })
    } else {
        None
    }
}

/// Parse fungi summary batches into FungalCounts
#[cfg(feature = "api")]
fn parse_fungal_counts(batches: &[RecordBatch]) -> Option<FungalCounts> {
    if batches.is_empty() {
        return None;
    }

    let json = batches_to_json(batches).ok()?;
    let data = json.get("data")?.as_array()?;

    let mut amf = 0;
    let mut emf = 0;
    let mut endophytes = 0;
    let mut mycoparasites = 0;
    let mut entomopathogens = 0;
    let mut pathogenic = 0;

    for row in data {
        let guild = row.get("guild")?.as_str()?.to_lowercase();
        let count = row.get("count")?.as_u64()? as usize;

        if guild.contains("arbuscular") || guild.contains("amf_fungi") {
            amf += count;
        } else if guild.contains("ectomycorrhiz") || guild.contains("emf_fungi") {
            emf += count;
        } else if guild.contains("endophyt") {
            endophytes += count;
        } else if guild.contains("mycoparasit") || guild.contains("hyperparasit") {
            mycoparasites += count;
        } else if guild.contains("entomopathogen") || guild.contains("insect_pathogen") {
            entomopathogens += count;
        } else if guild.contains("pathogenic_fungi") || guild == "pathogenic" {
            // Plant pathogenic fungi (diseases) - must check after entomopathogenic
            pathogenic += count;
        }
    }

    // Only return if we have any data
    if amf + emf + endophytes + mycoparasites + entomopathogens + pathogenic > 0 {
        Some(FungalCounts {
            amf,
            emf,
            endophytes,
            mycoparasites,
            entomopathogens,
            pathogenic,
        })
    } else {
        None
    }
}

// ============================================================================
// Request/Response Types
// ============================================================================

#[cfg(feature = "api")]
#[derive(serde::Deserialize, Debug)]
struct OrganismQuery {
    interaction_type: Option<String>,
}

#[cfg(feature = "api")]
#[derive(serde::Deserialize, Debug)]
struct FungiQuery {
    guild_category: Option<String>,
}

#[cfg(feature = "api")]
#[derive(serde::Deserialize)]
struct SimilarityRequest {
    plant_id: String,
    #[serde(default = "default_top_k")]
    top_k: usize,
}

#[cfg(feature = "api")]
fn default_top_k() -> usize {
    20
}

#[cfg(feature = "api")]
#[derive(serde::Deserialize)]
struct GuildScoreRequest {
    plant_ids: Vec<String>,
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Convert Arrow RecordBatches to JSON
#[cfg(feature = "api")]
fn batches_to_json(batches: &[RecordBatch]) -> Result<serde_json::Value, AppError> {
    if batches.is_empty() {
        return Ok(serde_json::json!({
            "rows": 0,
            "data": []
        }));
    }

    // Use Arrow's JSON writer
    let mut buf = Vec::new();
    {
        let mut writer = ArrayWriter::new(&mut buf);
        for batch in batches {
            writer
                .write(batch)
                .map_err(|e| AppError::Arrow(e.to_string()))?;
        }
        writer.finish().map_err(|e| AppError::Arrow(e.to_string()))?;
    }

    // Parse the JSON array
    let json_data: Vec<serde_json::Value> = serde_json::from_slice(&buf)
        .map_err(|e| AppError::Internal(format!("JSON parse error: {}", e)))?;

    let total_rows: usize = batches.iter().map(|b| b.num_rows()).sum();

    Ok(serde_json::json!({
        "rows": total_rows,
        "data": json_data
    }))
}

// ============================================================================
// Error Handling
// ============================================================================

#[cfg(feature = "api")]
#[derive(Debug)]
enum AppError {
    DataFusion(String),
    Arrow(String),
    Internal(String),
    NotFound(String),
}

#[cfg(feature = "api")]
impl IntoResponse for AppError {
    fn into_response(self) -> axum::response::Response {
        let (status, message) = match self {
            AppError::DataFusion(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg),
            AppError::Arrow(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg),
            AppError::Internal(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg),
            AppError::NotFound(msg) => (StatusCode::NOT_FOUND, msg),
        };

        let body = Json(serde_json::json!({
            "error": message
        }));

        (status, body).into_response()
    }
}

// ============================================================================
// Additional Dependencies (for chrono timestamp)
// ============================================================================

// Note: Need to add chrono to Cargo.toml if not already present
