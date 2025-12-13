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
use crate::search_index::SearchIndex;

#[cfg(feature = "api")]
use crate::encyclopedia::{
    EncyclopediaGenerator, OrganismCounts, FungalCounts, OrganismProfile, CategorizedOrganisms,
    OrganismLists, PathogenicFungus, BeneficialFungi, generate_encyclopedia_data,
};

// Direct import for focused suitability computation (skips S1, S3-S6)
#[cfg(feature = "api")]
use crate::encyclopedia::sections_json::s2_requirements;

#[cfg(feature = "api")]
use crate::explanation::unified_taxonomy::{OrganismCategory as TaxonomyCategory, OrganismRole};

#[cfg(feature = "api")]
use std::collections::HashSet;

#[cfg(feature = "api")]
use rustc_hash::FxHashMap;

#[cfg(feature = "api")]
use crate::explanation::{ExplanationGenerator, Explanation};

#[cfg(feature = "api")]
use crate::compact_tree::CompactTree;

#[cfg(feature = "api")]
use crate::encyclopedia::RelatedSpecies;

#[cfg(feature = "api")]
use std::collections::HashMap;

#[cfg(feature = "api")]
use datafusion::arrow::array::{RecordBatch, Array};

#[cfg(feature = "api")]
use datafusion::arrow::json::ArrayWriter;

// ============================================================================
// Phylogenetic Data (for related species)
// ============================================================================

/// Phylogenetic tree + WFO mapping for finding related species
#[cfg(feature = "api")]
pub struct PhyloData {
    tree: CompactTree,
    wfo_to_tip: HashMap<String, String>,
}

#[cfg(feature = "api")]
impl PhyloData {
    /// Load phylogenetic tree and WFO mapping
    /// Note: PhyloData is stored at repo root (data/stage1/), not in data_dir
    pub fn load(_data_dir: &str) -> Option<Self> {
        // PhyloData is at repo root, not in stage4
        let tree_path = "data/stage1/phlogeny/compact_tree_11711.bin";
        let mapping_path = "data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv";

        // Load tree
        let tree = match CompactTree::from_binary(&tree_path) {
            Ok(t) => t,
            Err(e) => {
                tracing::warn!("Failed to load phylo tree: {}", e);
                return None;
            }
        };

        // Load WFO -> tree tip mapping
        let contents = match std::fs::read_to_string(&mapping_path) {
            Ok(c) => c,
            Err(e) => {
                tracing::warn!("Failed to load WFO mapping: {}", e);
                return None;
            }
        };

        let mut wfo_to_tip = HashMap::new();
        for (idx, line) in contents.lines().enumerate() {
            if idx == 0 { continue; } // Skip header
            let parts: Vec<&str> = line.split(',').collect();
            if parts.len() >= 6 {
                let wfo_id = parts[0].to_string();
                let tree_tip = parts[5].to_string();
                if !tree_tip.is_empty() && tree_tip != "NA" {
                    wfo_to_tip.insert(wfo_id, tree_tip);
                }
            }
        }

        tracing::info!("Loaded phylo tree ({} mappings)", wfo_to_tip.len());
        Some(PhyloData { tree, wfo_to_tip })
    }

    /// Get tree tip label for a WFO ID
    fn get_tip(&self, wfo_id: &str) -> Option<&str> {
        self.wfo_to_tip.get(wfo_id).map(|s| s.as_str())
    }
}

// ============================================================================
// Application State
// ============================================================================

#[cfg(feature = "api")]
use crate::suitability_cache::SuitabilityCache;

#[cfg(feature = "api")]
#[derive(Clone)]
pub struct AppState {
    pub query_engine: Arc<QueryEngine>,
    pub guild_scorer: Arc<GuildScorer>,
    pub encyclopedia: Arc<EncyclopediaGenerator>,
    pub cache: Cache<String, serde_json::Value>,
    pub master_predators: Arc<HashSet<String>>,
    pub phylo_data: Option<Arc<PhyloData>>,
    pub search_index: Arc<SearchIndex>,
    pub data_dir: String,
    /// Typed suitability envelopes for O(1) lookups (~60 fields per plant, ~50MB total)
    pub suitability_cache: Arc<SuitabilityCache>,
}

#[cfg(feature = "api")]
impl AppState {
    pub async fn new(data_dir: &str, climate_tier: &str) -> anyhow::Result<Self> {
        tracing::info!("Initializing DataFusion query engine...");
        let query_engine = Arc::new(QueryEngine::new(data_dir).await?);

        tracing::info!("Initializing Polars guild scorer...");
        let guild_scorer = Arc::new(GuildScorer::new("7plant", climate_tier, data_dir)?);

        tracing::info!("Initializing encyclopedia generator...");
        let encyclopedia = Arc::new(EncyclopediaGenerator::new());

        tracing::info!("Initializing Moka cache...");
        let cache = Cache::builder()
            .max_capacity(10_000) // 10K entries
            .time_to_live(Duration::from_secs(300)) // 5 min TTL
            .build();

        tracing::info!("Loading master predator list...");
        let master_predators = Arc::new(load_master_predators(&query_engine).await);

        tracing::info!("Loading phylogenetic tree...");
        let phylo_data = PhyloData::load(data_dir).map(Arc::new);

        tracing::info!("Building FST search index...");
        let search_index = Arc::new(SearchIndex::build(&query_engine).await?);

        // Load suitability envelopes directly from parquet (full env columns)
        tracing::info!("Loading suitability envelopes into typed cache...");
        let plants_parquet = format!("{}/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet", data_dir);
        let suitability_cache = Arc::new(SuitabilityCache::from_parquet(&plants_parquet)?);
        tracing::info!("Loaded {} suitability envelopes (~60 fields each)", suitability_cache.len());

        Ok(Self {
            query_engine,
            guild_scorer,
            encyclopedia,
            cache,
            master_predators,
            phylo_data,
            search_index,
            data_dir: data_dir.to_string(),
            suitability_cache,
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

        // Plant endpoints (JSON API)
        // search uses FST for simple name queries (q=, latin_name=), SQL for filtered queries
        .route("/api/plants/search", get(search_plants))
        .route("/api/plants/batch", get(get_plants_batch))
        .route("/api/plants/ids", get(get_all_plant_ids))
        .route("/api/plants/:id", get(get_plant))
        .route("/api/plants/:id/organisms", get(get_organisms))
        .route("/api/plants/:id/fungi", get(get_fungi))
        .route("/api/plants/similar", post(find_similar))

        // Encyclopedia endpoint (JSON)
        .route("/api/encyclopedia/:id", get(get_encyclopedia))

        // Suitability endpoints (JSON)
        // IMPORTANT: batch route must come before :id route (Axum matches in order)
        .route("/api/suitability/batch", post(get_suitability_batch))
        .route("/api/suitability/:id", get(get_suitability))

        // Photo credits endpoint (JSON)
        .route("/api/photo-credits/:id", get(get_photo_credits))

        // Guild scoring endpoints
        .route("/api/guilds/score", post(score_guild))
        .route("/api/guilds/explain", post(explain_guild))

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
    let limit = filters.limit.unwrap_or(20).min(100);

    // Check if this is a simple name query that can use FST
    // Use FST if: `q` is set, OR only `latin_name`/`common_name` + `limit` (no other filters)
    let use_fst = filters.q.is_some() || is_simple_name_query(&filters);

    if use_fst {
        // Use FST index for fast prefix/fuzzy search
        let query = filters.q
            .as_ref()
            .or(filters.latin_name.as_ref())
            .or(filters.common_name.as_ref())
            .map(|s| s.as_str())
            .unwrap_or("");

        if query.is_empty() {
            return Ok(Json(serde_json::json!({
                "rows": 0,
                "data": []
            })));
        }

        // Direct WFO ID lookup (e.g., "wfo-0000123456")
        if query.starts_with("wfo-") {
            if let Some(plant) = state.search_index.get_by_wfo_id(query) {
                let data = vec![serde_json::json!({
                    "wfo_taxon_id": plant.wfo_id,
                    "wfo_scientific_name": plant.scientific_name,
                    "vernacular_name_en": plant.common_name,
                    "family": plant.family,
                    "genus": plant.genus,
                    "tiers": plant.tiers,
                })];
                return Ok(Json(serde_json::json!({
                    "rows": 1,
                    "data": data,
                })));
            } else {
                return Ok(Json(serde_json::json!({
                    "rows": 0,
                    "data": []
                })));
            }
        }

        // Parse tier filter (comma-separated: "1,3,4")
        let tier_filter: Vec<u8> = filters.tiers
            .as_ref()
            .map(|s| s.split(',').filter_map(|t| t.trim().parse().ok()).collect())
            .unwrap_or_default();

        let start = std::time::Instant::now();
        let results = if tier_filter.is_empty() {
            state.search_index.search(query, limit)
        } else {
            state.search_index.search_with_tiers(query, limit, &tier_filter)
        };
        let elapsed = start.elapsed();

        tracing::debug!("FST search '{}' (tiers: {:?}) returned {} results in {:?}",
            query, tier_filter, results.len(), elapsed);

        let data: Vec<serde_json::Value> = results
            .iter()
            .map(|p| {
                serde_json::json!({
                    "wfo_taxon_id": p.wfo_id,
                    "wfo_scientific_name": p.scientific_name,
                    "vernacular_name_en": p.common_name,
                    "family": p.family,
                    "genus": p.genus,
                    "tiers": p.tiers,
                })
            })
            .collect();

        return Ok(Json(serde_json::json!({
            "rows": data.len(),
            "data": data,
            "query_time_us": elapsed.as_micros(),
        })));
    }

    // Complex query with filters - use SQL via DataFusion
    let cache_key = format!("search:{:?}", filters);

    // Check cache
    if let Some(cached) = state.cache.get(&cache_key).await {
        tracing::debug!("Cache hit for search query");
        return Ok(Json(cached));
    }

    // Execute query
    tracing::debug!("Executing SQL plant search query");
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

/// Check if filters only contain name search + limit + tiers (no EIVE/CSR/categorical filters)
/// Note: `tiers` filter is allowed because it's handled post-search in FST path
#[cfg(feature = "api")]
fn is_simple_name_query(filters: &PlantFilters) -> bool {
    // Has some name to search
    let has_name = filters.latin_name.is_some() || filters.common_name.is_some();

    // No complex filters
    let no_eive = filters.min_light.is_none() && filters.max_light.is_none()
        && filters.min_moisture.is_none() && filters.max_moisture.is_none()
        && filters.min_temperature.is_none() && filters.max_temperature.is_none()
        && filters.min_nitrogen.is_none() && filters.max_nitrogen.is_none()
        && filters.min_ph.is_none() && filters.max_ph.is_none();

    let no_csr = filters.min_c.is_none() && filters.max_c.is_none()
        && filters.min_s.is_none() && filters.max_s.is_none()
        && filters.min_r.is_none() && filters.max_r.is_none();

    // Note: `tiers` is NOT checked here - it's allowed and handled in FST post-filter
    let no_categorical = filters.maintenance_level.is_none()
        && filters.drought_tolerant.is_none()
        && filters.fast_growing.is_none()
        && filters.climate_tier.is_none();

    has_name && no_eive && no_csr && no_categorical
}

/// Query params for batch plant lookup
#[cfg(feature = "api")]
#[derive(Debug, serde::Deserialize)]
struct BatchPlantQuery {
    /// Comma-separated WFO IDs (e.g., "wfo-0000721951,wfo-0000955348")
    ids: String,
}

/// Batch plant lookup by WFO IDs - O(1) per plant via hashmap
#[cfg(feature = "api")]
async fn get_plants_batch(
    State(state): State<AppState>,
    Query(params): Query<BatchPlantQuery>,
) -> Result<Json<serde_json::Value>, AppError> {
    let start = std::time::Instant::now();

    let ids: Vec<&str> = params.ids.split(',').map(|s| s.trim()).collect();
    let plants = state.search_index.get_by_wfo_ids(&ids);

    let data: Vec<serde_json::Value> = plants
        .iter()
        .map(|p| {
            serde_json::json!({
                "wfo_id": p.wfo_id,
                "wfo_scientific_name": p.scientific_name,
                "vernacular_name_en": p.common_name,
                "family": p.family,
                "genus": p.genus,
                "tiers": p.tiers,
            })
        })
        .collect();

    let elapsed = start.elapsed();
    tracing::debug!("Batch lookup of {} plants returned {} results in {:?}",
        ids.len(), data.len(), elapsed);

    Ok(Json(serde_json::json!({
        "rows": data.len(),
        "data": data,
        "query_time_us": elapsed.as_micros(),
    })))
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

/// Get all plant IDs (for static generation)
#[cfg(feature = "api")]
async fn get_all_plant_ids(
    State(state): State<AppState>,
) -> Result<Json<serde_json::Value>, AppError> {
    let cache_key = "plant_ids:all".to_string();

    // Check cache
    if let Some(cached) = state.cache.get(&cache_key).await {
        tracing::debug!("Cache hit for all plant IDs");
        return Ok(Json(cached));
    }

    // Execute query - get just the WFO IDs
    tracing::debug!("Fetching all plant IDs");
    let batches = state
        .query_engine
        .get_all_plant_ids()
        .await
        .map_err(|e| AppError::DataFusion(e.to_string()))?;

    // Convert to JSON
    let result = batches_to_json(&batches)?;

    // Cache result (long TTL since IDs don't change)
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

/// Generate full guild explanation with all analysis profiles
#[cfg(feature = "api")]
async fn explain_guild(
    State(state): State<AppState>,
    Json(payload): Json<GuildExplainRequest>,
) -> Result<Json<Explanation>, AppError> {
    let scorer = state.guild_scorer.clone();
    let plant_ids = payload.plant_ids.clone();
    let climate_tier = payload.climate_tier.clone().unwrap_or_else(|| "tier_3_humid_temperate".to_string());
    let guild_size = plant_ids.len();

    tracing::info!("Generating explanation for guild with {} plants", guild_size);

    // CPU-bound work: run in blocking thread pool
    let explanation = tokio::task::spawn_blocking(move || -> anyhow::Result<Explanation> {
        // Score with explanation data (organisms/fungi accessed via scorer.data() to avoid cloning)
        let (guild_score, fragments, guild_plants, m2_result, m3_result, m4_result, m5_result, m6_result, m7_result, ecosystem_services) =
            scorer.score_guild_with_explanation_parallel(&plant_ids)?;

        // Generate complete explanation
        let explanation = ExplanationGenerator::generate(
            &guild_score,
            &guild_plants,
            &climate_tier,
            fragments,
            &m2_result,
            &m3_result,
            &scorer.data().organisms,  // Direct reference, no clone
            &m4_result,
            &m5_result,
            &scorer.data().fungi,      // Direct reference, no clone
            &m6_result,
            &m7_result,
            &scorer.data().organism_categories,
            &ecosystem_services,
            &scorer.data().pathogen_diseases,
        )?;

        Ok(explanation)
    })
    .await
    .map_err(|e| AppError::Internal(format!("Task join error: {}", e)))?
    .map_err(|e| AppError::Internal(format!("Explanation generation error: {}", e)))?;

    Ok(Json(explanation))
}

/// Single plant suitability check - O(1) lookup from SuitabilityCache
///
/// GET /api/suitability/:id?location=london
///
/// Optimizations:
/// - Uses typed SuitabilityCache for O(1) FxHashMap lookup (~60 fields)
/// - Only computes S2 requirements (skips S1, S3-S6 encyclopedia sections)
/// - Moka response cache for repeated requests
#[cfg(feature = "api")]
async fn get_suitability(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Query(params): Query<SuitabilityQuery>,
) -> Result<Json<serde_json::Value>, AppError> {
    let location = params.location.unwrap_or_else(|| "london".to_string());
    let cache_key = format!("suitability:{}:{}", id, location);

    // Check response cache
    if let Some(cached) = state.cache.get(&cache_key).await {
        tracing::debug!("Cache hit for suitability {}:{}", id, location);
        return Ok(Json(cached));
    }

    // O(1) lookup from SuitabilityCache (FxHashMap)
    let plant_data = state.suitability_cache.get(&id)
        .map(|env| env.to_hashmap())
        .ok_or_else(|| AppError::NotFound(format!("Plant {} not found", id)))?;

    // Get local conditions for the location
    let local_conditions = get_local_conditions(&location);

    // FOCUSED: Only compute S2 requirements (skips S1, S3, S4, S5, S6)
    let requirements = s2_requirements::generate(&plant_data, Some(&local_conditions));
    let overall = requirements.overall_suitability.as_ref();

    let result = serde_json::json!({
        "wfo_id": id,
        "location": {
            "name": local_conditions.name,
            "code": location,
            "climate_zone": local_conditions.koppen_zone,
        },
        "overall_score": overall.map(|o| o.score_percent).unwrap_or(50),
        "verdict": overall.map(|o| o.verdict.clone()).unwrap_or_else(|| "Assessment unavailable".to_string()),
        "key_concerns": overall.map(|o| o.key_concerns.clone()).unwrap_or_default(),
        "growing_tips": overall.map(|o| &o.growing_tips).unwrap_or(&vec![]),
        "light": {
            "category": requirements.light.category,
            "eive_l": requirements.light.eive_l,
            "sun_tolerance": requirements.light.sun_tolerance,
        },
        "temperature": {
            "summary": requirements.temperature.summary,
            "comparisons": requirements.temperature.comparisons,
        },
        "moisture": {
            "summary": requirements.moisture.summary,
            "comparisons": requirements.moisture.comparisons,
            "advice": requirements.moisture.advice,
        },
        "soil": {
            "texture": requirements.soil.texture_summary,
            "comparisons": requirements.soil.comparisons,
            "advice": requirements.soil.advice,
        },
    });

    // Cache result
    state.cache.insert(cache_key, result.clone()).await;

    Ok(Json(result))
}

/// Batch suitability check for multiple plants (optimized for guild builder)
///
/// POST /api/suitability/batch
/// Body: { "wfo_ids": ["wfo-xxx", ...], "location": "london" }
///
/// Optimizations:
/// - Single database query for all plants (vs N separate queries)
/// - Local conditions computed once (not per plant)
/// - FOCUSED: Only computes S2 (suitability), skips S1, S3-S6 encyclopedia sections
/// - RAYON: CPU parallelism via par_iter (not async tokio::spawn)
#[cfg(feature = "api")]
async fn get_suitability_batch(
    State(state): State<AppState>,
    Json(req): Json<BatchSuitabilityRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    use rayon::prelude::*;

    let location = req.location.unwrap_or_else(|| "london".to_string());
    let wfo_ids = req.wfo_ids;

    if wfo_ids.is_empty() {
        return Ok(Json(serde_json::json!({
            "location": { "name": location, "code": location.to_lowercase() },
            "results": [],
            "aggregate": { "average_score": 0, "suited_count": 0, "total_count": 0 }
        })));
    }

    let start = std::time::Instant::now();
    tracing::info!("Batch suitability check for {} plants at {}", wfo_ids.len(), location);

    // 1. Get local conditions ONCE (not per plant)
    let local_conditions = get_local_conditions(&location);

    // 2. Check cache for all plants, collect uncached IDs
    let mut cached_results: Vec<(String, serde_json::Value)> = Vec::new();
    let mut uncached_ids: Vec<String> = Vec::new();

    for wfo_id in &wfo_ids {
        let cache_key = format!("suitability:{}:{}", wfo_id, location);
        if let Some(cached) = state.cache.get(&cache_key).await {
            cached_results.push((wfo_id.clone(), cached));
        } else {
            uncached_ids.push(wfo_id.clone());
        }
    }

    tracing::info!("Cache: {} hits, {} misses", cached_results.len(), uncached_ids.len());

    // 3. Get plant envelopes from typed cache (O(1) FxHashMap lookup, ~60 fields each)
    let lookup_start = std::time::Instant::now();
    let plants_to_process: Vec<(String, Option<HashMap<String, serde_json::Value>>)> = uncached_ids
        .iter()
        .map(|id| {
            let envelope_opt = state.suitability_cache.get(id).map(|env| env.to_hashmap());
            (id.clone(), envelope_opt)
        })
        .collect();
    let found_count = plants_to_process.iter().filter(|(_, opt)| opt.is_some()).count();
    tracing::info!("  Envelope lookup: {:?} ({} found)", lookup_start.elapsed(), found_count);

    // 4. Compute suitability using Rayon parallel iterator (CPU-bound, not async)
    let local_for_rayon = local_conditions.clone();
    let location_for_rayon = location.clone();

    // Use spawn_blocking to run Rayon on a blocking thread pool
    let s2_start = std::time::Instant::now();
    let computed_results = tokio::task::spawn_blocking(move || {
        plants_to_process
            .par_iter()
            .map(|(wfo_id, plant_data_opt)| {
                match plant_data_opt {
                    Some(plant_data) => {
                        // FOCUSED: Only compute S2 requirements (skips S1, S3, S4, S5, S6)
                        let requirements = s2_requirements::generate(plant_data, Some(&local_for_rayon));
                        let overall = requirements.overall_suitability.as_ref();

                        let result = serde_json::json!({
                            "wfo_id": wfo_id,
                            "overall_score": overall.map(|o| o.score_percent).unwrap_or(50),
                            "verdict": overall.map(|o| o.verdict.clone()).unwrap_or_else(|| "Assessment unavailable".to_string()),
                            "key_concerns": overall.map(|o| o.key_concerns.clone()).unwrap_or_default(),
                            "growing_tips": overall.map(|o| &o.growing_tips).unwrap_or(&vec![]),
                            "temperature": {
                                "summary": requirements.temperature.summary,
                                "comparisons": requirements.temperature.comparisons,
                            },
                            "moisture": {
                                "summary": requirements.moisture.summary,
                                "comparisons": requirements.moisture.comparisons,
                                "advice": requirements.moisture.advice,
                            },
                            "soil": {
                                "texture": requirements.soil.texture_summary,
                                "comparisons": requirements.soil.comparisons,
                                "advice": requirements.soil.advice,
                            },
                        });

                        Ok((wfo_id.clone(), result, location_for_rayon.clone()))
                    }
                    None => Err(format!("Plant {} not found", wfo_id)),
                }
            })
            .collect::<Vec<_>>()
    })
    .await
    .map_err(|e| AppError::Internal(format!("Rayon task failed: {}", e)))?;
    tracing::info!("  S2 computation: {:?}", s2_start.elapsed());

    // 5. Collect results and update cache
    let mut results: Vec<serde_json::Value> = Vec::with_capacity(wfo_ids.len());
    let mut errors: Vec<serde_json::Value> = Vec::new();
    let mut total_score: u32 = 0;
    let mut suited_count: u32 = 0;

    // Add cached results first
    for (id, result) in cached_results {
        if let Some(score) = result.get("overall_score").and_then(|s| s.as_u64()) {
            total_score += score as u32;
            if score >= 60 {
                suited_count += 1;
            }
        }
        results.push(result);
    }

    // Add computed results and cache them
    for item in computed_results {
        match item {
            Ok((id, result, loc)) => {
                // Cache for next time
                let cache_key = format!("suitability:{}:{}", id, loc);
                state.cache.insert(cache_key, result.clone()).await;

                // Aggregate stats
                if let Some(score) = result.get("overall_score").and_then(|s| s.as_u64()) {
                    total_score += score as u32;
                    if score >= 60 {
                        suited_count += 1;
                    }
                }
                results.push(result);
            }
            Err(e) => {
                errors.push(serde_json::json!({ "error": e }));
            }
        }
    }

    let total_count = results.len() as u32;
    let average_score = if total_count > 0 {
        total_score / total_count
    } else {
        0
    };

    let elapsed = start.elapsed();
    tracing::info!("Batch suitability completed in {:?} ({} plants)", elapsed, total_count);

    // 6. Build location info
    let location_info = serde_json::json!({
        "name": local_conditions.name,
        "code": location.to_lowercase(),
        "climate_zone": local_conditions.climate_tier().display_name(),
        "cec": local_conditions.soil_cec,
        "fertility_level": if local_conditions.soil_cec < 10.0 { "Low" }
                          else if local_conditions.soil_cec < 25.0 { "Medium" }
                          else { "High" },
    });

    Ok(Json(serde_json::json!({
        "location": location_info,
        "results": results,
        "errors": errors,
        "aggregate": {
            "average_score": average_score,
            "suited_count": suited_count,
            "total_count": total_count,
        }
    })))
}

/// Get photo credits for a plant (iNaturalist CC-BY attribution)
#[cfg(feature = "api")]
async fn get_photo_credits(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, AppError> {
    // Read credits JSON file from data_dir/photo_credits/{wfo_id}.json
    let credits_path = format!("{}/photo_credits/{}.json", state.data_dir, id);

    match std::fs::read_to_string(&credits_path) {
        Ok(contents) => {
            let credits: serde_json::Value = serde_json::from_str(&contents)
                .map_err(|e| AppError::Internal(format!("Invalid JSON in credits file: {}", e)))?;
            Ok(Json(credits))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            Err(AppError::NotFound(format!("Photo credits not found for {}", id)))
        }
        Err(e) => {
            Err(AppError::Internal(format!("Failed to read credits file: {}", e)))
        }
    }
}

/// Get LocalConditions for a location name
#[cfg(feature = "api")]
fn get_local_conditions(location: &str) -> crate::encyclopedia::suitability::local_conditions::LocalConditions {
    use crate::encyclopedia::suitability::local_conditions;
    match location.to_lowercase().as_str() {
        "singapore" => local_conditions::singapore(),
        "helsinki" => local_conditions::helsinki(),
        _ => local_conditions::london(), // Default to London
    }
}

/// Generate encyclopedia page for a plant (returns JSON)
#[cfg(feature = "api")]
async fn get_encyclopedia(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Query(params): Query<SuitabilityQuery>,
) -> Result<Json<serde_json::Value>, AppError> {
    // Only use location if explicitly provided - fit badges only make sense for suitability checks
    let location = params.location.clone();
    let cache_key = format!("encyclopedia:{}:{}", id, location.as_deref().unwrap_or("none"));

    // Check cache
    if let Some(cached) = state.cache.get(&cache_key).await {
        tracing::debug!("Cache hit for encyclopedia {}:{:?}", id, location);
        return Ok(Json(cached));
    }

    tracing::debug!("Generating encyclopedia for plant {} at {:?}", id, location);

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

    // 2. Fetch organism data and categorize
    let organism_batches = state.query_engine.get_organisms(&id, None).await.ok();
    let organism_lists = organism_batches
        .as_ref()
        .and_then(|b| parse_organism_lists(b, &state.master_predators));
    let organism_profile = organism_lists.as_ref().map(|lists| {
        categorize_organisms(lists, &state.guild_scorer.data().organism_categories)
    });

    // 3. Fetch fungal counts
    let fungal_batches = state.query_engine.get_fungi_summary(&id).await.ok();
    let fungal_counts = fungal_batches.as_ref().and_then(|b| parse_fungal_counts(b));

    // 4. Fetch pathogenic fungi with disease names (simplified flow)
    let pathogenic_fungi = parse_pathogenic_fungi(&state.query_engine, &id).await;

    // 5. Fetch beneficial fungi
    let beneficial_fungi = parse_beneficial_fungi(&state.query_engine, &id).await;

    // 6. Find related species using precomputed phylogenetic distances
    // Now searches ALL plants (not just same genus) via pairwise_phylo_distances parquet
    let related_species = find_related_species(&state.query_engine, &id).await;

    // 7. Get local conditions for location (only if location explicitly provided)
    let local_conditions = location.as_ref().map(|loc| get_local_conditions(loc));

    // 8. Build encyclopedia data using generator_json with all data
    let encyclopedia_data = generate_encyclopedia_data(
        &id,
        &plant_data,
        organism_profile.as_ref(),
        fungal_counts.as_ref(),
        pathogenic_fungi.as_deref(),
        beneficial_fungi.as_ref(),
        if related_species.is_empty() { None } else { Some(&related_species) },
        local_conditions.as_ref(),
    ).map_err(|e| AppError::Internal(e))?;

    // 9. Serialize to JSON
    let result = serde_json::to_value(&encyclopedia_data)
        .map_err(|e| AppError::Internal(format!("JSON serialization error: {}", e)))?;

    // Cache the result
    state.cache.insert(cache_key, result.clone()).await;

    Ok(Json(result))
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

/// Load master predator list from database (called once at startup)
#[cfg(feature = "api")]
async fn load_master_predators(engine: &QueryEngine) -> HashSet<String> {
    use datafusion::arrow::array::{StringArray, LargeStringArray, StringViewArray};

    match engine.get_master_predators().await {
        Ok(batches) => {
            let mut predators = HashSet::new();
            for batch in &batches {
                if let Some(col) = batch.column_by_name("predator_taxon") {
                    // Try different string array types
                    if let Some(arr) = col.as_any().downcast_ref::<StringArray>() {
                        for i in 0..arr.len() {
                            if !arr.is_null(i) {
                                let val = arr.value(i).to_lowercase();
                                if !val.is_empty() {
                                    predators.insert(val);
                                }
                            }
                        }
                    } else if let Some(arr) = col.as_any().downcast_ref::<LargeStringArray>() {
                        for i in 0..arr.len() {
                            if !arr.is_null(i) {
                                let val = arr.value(i).to_lowercase();
                                if !val.is_empty() {
                                    predators.insert(val);
                                }
                            }
                        }
                    } else if let Some(arr) = col.as_any().downcast_ref::<StringViewArray>() {
                        for i in 0..arr.len() {
                            if !arr.is_null(i) {
                                let val = arr.value(i).to_lowercase();
                                if !val.is_empty() {
                                    predators.insert(val);
                                }
                            }
                        }
                    }
                }
            }
            tracing::info!("Loaded {} master predators", predators.len());
            predators
        }
        Err(e) => {
            tracing::warn!("Failed to load master predators: {}", e);
            HashSet::new()
        }
    }
}

/// Parse organism batches into OrganismLists
#[cfg(feature = "api")]
fn parse_organism_lists(batches: &[RecordBatch], master_predators: &HashSet<String>) -> Option<OrganismLists> {
    if batches.is_empty() {
        return None;
    }

    let json = batches_to_json(batches).ok()?;
    let data = json.get("data")?.as_array()?;

    let mut pollinators = Vec::new();
    let mut herbivores = Vec::new();
    let mut fungivores = Vec::new();
    let mut all_organisms: HashSet<String> = HashSet::new();

    for row in data {
        let source_column = row.get("source_column")?.as_str()?.to_lowercase();
        let organism_taxon = row.get("organism_taxon")?.as_str()?.to_string();

        if organism_taxon.is_empty() {
            continue;
        }

        // Collect by category
        match source_column.as_str() {
            "pollinators" => pollinators.push(organism_taxon.clone()),
            "herbivores" => herbivores.push(organism_taxon.clone()),
            "fungivores_eats" => fungivores.push(organism_taxon.clone()),
            _ => {}
        }

        // Collect ALL organisms for beneficial predator matching
        all_organisms.insert(organism_taxon);
    }

    // Find beneficial predators: organisms that visit this plant AND are known pest predators
    let predators: Vec<String> = all_organisms
        .iter()
        .filter(|org| master_predators.contains(&org.to_lowercase()))
        .cloned()
        .collect();

    if pollinators.is_empty() && herbivores.is_empty() && predators.is_empty() && fungivores.is_empty() {
        return None;
    }

    Some(OrganismLists {
        pollinators,
        herbivores,
        predators,
        fungivores,
    })
}

/// Categorize organisms into groups by taxonomy
#[cfg(feature = "api")]
fn categorize_organisms(
    lists: &OrganismLists,
    organism_categories: &FxHashMap<String, String>,
) -> OrganismProfile {
    fn group_by_category(
        organisms: &[String],
        role: OrganismRole,
        organism_categories: &FxHashMap<String, String>,
    ) -> Vec<CategorizedOrganisms> {
        let mut category_map: FxHashMap<String, Vec<String>> = FxHashMap::default();

        for org in organisms {
            let category = TaxonomyCategory::from_name(org, organism_categories, Some(role));
            let mut category_name = category.display_name().to_string();

            // Clarify that moths/butterflies are caterpillars when shown as herbivores
            // (adult moths/butterflies are pollinators, only larvae eat plants)
            if role == OrganismRole::Herbivore
                && (category_name == "Moths" || category_name == "Butterflies")
            {
                category_name.push_str(" (caterpillars)");
            }

            category_map
                .entry(category_name)
                .or_default()
                .push(org.clone());
        }

        // Sort by count (descending), but "Other" categories at bottom
        let mut result: Vec<CategorizedOrganisms> = category_map
            .into_iter()
            .map(|(cat, orgs)| CategorizedOrganisms {
                category: cat,
                organisms: orgs,
            })
            .collect();

        result.sort_by(|a, b| {
            let a_is_other = a.category.starts_with("Other");
            let b_is_other = b.category.starts_with("Other");
            match (a_is_other, b_is_other) {
                (true, false) => std::cmp::Ordering::Greater,
                (false, true) => std::cmp::Ordering::Less,
                _ => b.organisms.len().cmp(&a.organisms.len())
                    .then_with(|| a.category.cmp(&b.category))
            }
        });

        result
    }

    OrganismProfile {
        pollinators_by_category: group_by_category(&lists.pollinators, OrganismRole::Pollinator, organism_categories),
        herbivores_by_category: group_by_category(&lists.herbivores, OrganismRole::Herbivore, organism_categories),
        predators_by_category: group_by_category(&lists.predators, OrganismRole::Predator, organism_categories),
        fungivores_by_category: group_by_category(&lists.fungivores, OrganismRole::Predator, organism_categories),
        total_pollinators: lists.pollinators.len(),
        total_herbivores: lists.herbivores.len(),
        total_predators: lists.predators.len(),
        total_fungivores: lists.fungivores.len(),
    }
}

/// Parse pathogenic fungi with disease names (simplified flow from fungi_flat + pathogen_diseases)
#[cfg(feature = "api")]
async fn parse_pathogenic_fungi(
    engine: &QueryEngine,
    plant_id: &str,
) -> Option<Vec<PathogenicFungus>> {
    let batches = engine.get_pathogenic_fungi_with_diseases(plant_id).await.ok()?;
    if batches.is_empty() {
        return None;
    }

    let json = batches_to_json(&batches).ok()?;
    let data = json.get("data")?.as_array()?;

    let fungi: Vec<PathogenicFungus> = data.iter().filter_map(|row| {
        let taxon = row.get("fungus_taxon")?.as_str()?.to_string();
        let disease_name = row.get("disease_name")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());
        let disease_type = row.get("disease_type")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());
        Some(PathogenicFungus {
            taxon,
            disease_name,
            disease_type,
        })
    }).collect();

    if fungi.is_empty() { None } else { Some(fungi) }
}

/// Parse beneficial fungi (mycoparasites and entomopathogens)
#[cfg(feature = "api")]
async fn parse_beneficial_fungi(
    engine: &QueryEngine,
    plant_id: &str,
) -> Option<BeneficialFungi> {
    let batches = engine.get_beneficial_fungi(plant_id).await.ok()?;
    if batches.is_empty() {
        return None;
    }

    let json = batches_to_json(&batches).ok()?;
    let data = json.get("data")?.as_array()?;

    let mut mycoparasites = Vec::new();
    let mut entomopathogens = Vec::new();

    for row in data {
        let source = row.get("source_column")?.as_str()?;
        let taxon = row.get("fungus_taxon")?.as_str()?.to_string();

        match source {
            "mycoparasite_fungi" => mycoparasites.push(taxon),
            "entomopathogenic_fungi" => entomopathogens.push(taxon),
            _ => {}
        }
    }

    if mycoparasites.is_empty() && entomopathogens.is_empty() {
        None
    } else {
        Some(BeneficialFungi {
            mycoparasites,
            entomopathogens,
        })
    }
}

/// Find closest related species using precomputed phylogenetic distances
///
/// Uses the pairwise_phylo_distances parquet (136M pairs) for O(1) lookup
/// instead of runtime tree traversal. Searches ALL 11,673 plants, not just same genus.
#[cfg(feature = "api")]
async fn find_related_species(
    engine: &QueryEngine,
    base_wfo_id: &str,
) -> Vec<RelatedSpecies> {
    // Single SQL query with JOIN - searches all plants, not just same genus
    // Use CASE instead of COALESCE to avoid Utf8View/Utf8 type coercion issues
    let query = format!(
        "SELECT
            pd.wfo_id_b AS wfo_id,
            pd.distance,
            p.wfo_scientific_name AS scientific_name,
            CASE WHEN p.vernacular_name_en IS NULL THEN '' ELSE p.vernacular_name_en END AS common_name
         FROM pairwise_phylo_distances pd
         JOIN plants p ON pd.wfo_id_b = p.wfo_taxon_id
         WHERE pd.wfo_id_a = '{}'
         ORDER BY pd.distance ASC
         LIMIT 5",
        base_wfo_id.replace('\'', "''")
    );

    let batches = match engine.query(&query).await {
        Ok(b) => b,
        Err(e) => {
            tracing::warn!("find_related_species query failed for {}: {}", base_wfo_id, e);
            return vec![];
        }
    };

    if batches.is_empty() {
        return vec![];
    }

    // Parse results
    let json = match batches_to_json(&batches) {
        Ok(j) => j,
        Err(e) => {
            tracing::warn!("find_related_species JSON parse failed: {:?}", e);
            return vec![];
        }
    };
    let data = match json.get("data").and_then(|d| d.as_array()) {
        Some(d) => d,
        None => return vec![],
    };

    // Convert to RelatedSpecies
    data.iter()
        .filter_map(|row| {
            let wfo_id = row.get("wfo_id").and_then(|v| v.as_str())?.to_string();
            let scientific_name = row.get("scientific_name").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let distance = row.get("distance").and_then(|v| v.as_f64()).unwrap_or(0.0);

            // Get first common name and title case it
            let common_name = row.get("common_name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .split(';')
                .next()
                .unwrap_or("")
                .trim()
                .split_whitespace()
                .map(|word| {
                    let mut chars = word.chars();
                    match chars.next() {
                        None => String::new(),
                        Some(first) => format!("{}{}", first.to_uppercase(), chars.collect::<String>().to_lowercase()),
                    }
                })
                .collect::<Vec<_>>()
                .join(" ");

            Some(RelatedSpecies {
                wfo_id,
                scientific_name,
                common_name,
                distance,
            })
        })
        .collect()
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
#[derive(serde::Deserialize, Debug)]
struct SuitabilityQuery {
    location: Option<String>,
}

#[cfg(feature = "api")]
#[derive(serde::Deserialize, Debug)]
struct BatchSuitabilityRequest {
    wfo_ids: Vec<String>,
    location: Option<String>,
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

#[cfg(feature = "api")]
#[derive(serde::Deserialize)]
struct GuildExplainRequest {
    plant_ids: Vec<String>,
    climate_tier: Option<String>,  // e.g., "tier_3_humid_temperate"
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
