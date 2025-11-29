// Page handlers for HTML rendering with Askama

use axum::response::{Html, IntoResponse};
use axum::extract::{Query, State};
use askama::Template;
use serde::Deserialize;
use std::sync::Arc;
use crate::AppState;

// ============================================================================
// Home Page
// ============================================================================

#[derive(Template)]
#[template(path = "pages/home.html")]
pub struct HomeTemplate {
    pub title: String,
    pub plant_count_formatted: String,
}

pub async fn home_page() -> impl IntoResponse {
    let template = HomeTemplate {
        title: "Plant Encyclopedia".to_string(),
        plant_count_formatted: "11,711".to_string(),
    };
    Html(template.render().unwrap_or_else(|e| {
        format!("Template error: {}", e)
    }))
}

// ============================================================================
// Search Page
// ============================================================================

#[derive(Template)]
#[template(path = "pages/search.html")]
pub struct SearchPageTemplate {
    pub title: String,
    pub plant_count_formatted: String,
}

pub async fn search_page() -> impl IntoResponse {
    let template = SearchPageTemplate {
        title: "Plant Encyclopedia".to_string(),
        plant_count_formatted: "11,711".to_string(),
    };
    Html(template.render().unwrap_or_else(|e| {
        format!("Template error: {}", e)
    }))
}

// ============================================================================
// Search Results Fragment (HTMX)
// ============================================================================

#[derive(Debug, Clone)]
pub struct PlantSearchResult {
    pub wfo_id: String,
    pub scientific_name: String,
    pub family: String,
    pub vernacular_en: Option<String>,
    pub growth_form: Option<String>,
}

#[derive(Template)]
#[template(path = "fragments/search_results.html")]
pub struct SearchResultsTemplate {
    pub query: String,
    pub results: Vec<PlantSearchResult>,
    pub result_count: usize,
}

#[derive(Debug, Deserialize)]
pub struct SearchQuery {
    pub q: Option<String>,
}

pub async fn search_results(
    State(state): State<AppState>,
    Query(params): Query<SearchQuery>,
) -> impl IntoResponse {
    let query = params.q.unwrap_or_default().trim().to_string();

    // Require at least 2 characters for search
    if query.len() < 2 {
        let template = SearchResultsTemplate {
            query,
            results: vec![],
            result_count: 0,
        };
        return Html(template.render().unwrap_or_else(|e| {
            format!("Template error: {}", e)
        }));
    }

    // Search using DataFusion query engine
    let results = match state.query_engine.search_plants_text(&query, 50).await {
        Ok(plants) => plants
            .into_iter()
            .map(|p| PlantSearchResult {
                wfo_id: p.wfo_taxon_id,
                scientific_name: p.scientific_name,
                family: p.family,
                vernacular_en: p.vernacular_en,
                growth_form: p.growth_form,
            })
            .collect(),
        Err(e) => {
            tracing::error!("Search error: {}", e);
            vec![]
        }
    };

    let result_count = results.len();
    let template = SearchResultsTemplate {
        query,
        results,
        result_count,
    };

    Html(template.render().unwrap_or_else(|e| {
        format!("Template error: {}", e)
    }))
}
