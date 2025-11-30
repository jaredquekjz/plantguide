// Page handlers for HTML rendering with Askama

use axum::response::{Html, IntoResponse};
use axum::extract::{Path, Query, State};
use askama::Template;
use serde::Deserialize;
use std::collections::HashMap;
use crate::AppState;
use crate::encyclopedia::suitability::local_conditions::{self, LocalConditions};
use crate::encyclopedia::view_models::EncyclopediaPageData;
use crate::encyclopedia::view_builder::build_encyclopedia_data;
use crate::encyclopedia::types::{
    OrganismProfile, FungalCounts, BeneficialFungi, CategorizedOrganisms,
};
use datafusion::arrow::array::RecordBatch;
use datafusion::arrow::json::ArrayWriter;
use pulldown_cmark::{Parser, Options, html};

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

// ============================================================================
// Encyclopedia Page
// ============================================================================

#[derive(Template)]
#[template(path = "pages/encyclopedia.html")]
pub struct EncyclopediaPageTemplate {
    pub wfo_id: String,
    pub scientific_name: String,
    pub vernacular_name: Option<String>,
    pub family: String,
    pub location: String,
    pub content_html: String,
}

#[derive(Template)]
#[template(path = "fragments/encyclopedia_content.html")]
pub struct EncyclopediaContentTemplate {
    pub content_html: String,
}

#[derive(Debug, Deserialize)]
pub struct EncyclopediaQuery {
    pub location: Option<String>,
}

/// Convert RecordBatch to HashMap for encyclopedia generator
fn batch_to_hashmap(
    batches: &[datafusion::arrow::array::RecordBatch],
) -> Option<HashMap<String, serde_json::Value>> {
    if batches.is_empty() || batches[0].num_rows() == 0 {
        return None;
    }

    let mut buf = Vec::new();
    {
        let mut writer = datafusion::arrow::json::ArrayWriter::new(&mut buf);
        for batch in batches {
            writer.write(batch).ok()?;
        }
        writer.finish().ok()?;
    }

    let json_data: Vec<serde_json::Value> = serde_json::from_slice(&buf).ok()?;
    json_data
        .into_iter()
        .next()
        .and_then(|v| serde_json::from_value(v).ok())
}

/// Convert RecordBatch to JSON array
fn batches_to_json(batches: &[RecordBatch]) -> Option<Vec<serde_json::Value>> {
    if batches.is_empty() {
        return Some(Vec::new());
    }

    let mut buf = Vec::new();
    {
        let mut writer = ArrayWriter::new(&mut buf);
        for batch in batches {
            writer.write(batch).ok()?;
        }
        writer.finish().ok()?;
    }

    serde_json::from_slice(&buf).ok()
}

/// Parse organism data into OrganismProfile
fn parse_organism_profile(batches: &[RecordBatch]) -> Option<OrganismProfile> {
    let rows = batches_to_json(batches)?;
    if rows.is_empty() {
        return None;
    }

    // Group organisms by source_column (pollinators, herbivores, etc.)
    let mut pollinators: Vec<String> = Vec::new();
    let mut herbivores: Vec<String> = Vec::new();
    let mut predators: Vec<String> = Vec::new();
    let mut fungivores: Vec<String> = Vec::new();

    for row in &rows {
        let source = row.get("source_column")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_lowercase();
        let organism = row.get("organism_taxon")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();

        if organism.is_empty() {
            continue;
        }

        if source.contains("pollinator") {
            pollinators.push(organism);
        } else if source.contains("herbivore") || source.contains("parasite") {
            herbivores.push(organism);
        } else if source.contains("predator") {
            predators.push(organism);
        } else if source.contains("fungivore") {
            fungivores.push(organism);
        }
    }

    // Build categorized lists (simplified - just one category per type)
    let mut profile = OrganismProfile::default();

    if !pollinators.is_empty() {
        profile.total_pollinators = pollinators.len();
        profile.pollinators_by_category.push(CategorizedOrganisms {
            category: "Pollinators".to_string(),
            organisms: pollinators.into_iter().take(10).collect(),
        });
    }

    if !herbivores.is_empty() {
        profile.total_herbivores = herbivores.len();
        profile.herbivores_by_category.push(CategorizedOrganisms {
            category: "Herbivores & Pests".to_string(),
            organisms: herbivores.into_iter().take(10).collect(),
        });
    }

    if !predators.is_empty() {
        profile.total_predators = predators.len();
        profile.predators_by_category.push(CategorizedOrganisms {
            category: "Natural Enemies".to_string(),
            organisms: predators.into_iter().take(10).collect(),
        });
    }

    if !fungivores.is_empty() {
        profile.total_fungivores = fungivores.len();
        profile.fungivores_by_category.push(CategorizedOrganisms {
            category: "Fungivores".to_string(),
            organisms: fungivores.into_iter().take(10).collect(),
        });
    }

    if profile.total_pollinators + profile.total_herbivores + profile.total_predators > 0 {
        Some(profile)
    } else {
        None
    }
}

/// Parse fungi data into FungalCounts and BeneficialFungi
fn parse_fungi_data(batches: &[RecordBatch]) -> (Option<FungalCounts>, Option<BeneficialFungi>) {
    let rows = match batches_to_json(batches) {
        Some(r) => r,
        None => return (None, None),
    };

    if rows.is_empty() {
        return (None, None);
    }

    let mut counts = FungalCounts::default();
    let mut mycoparasites: Vec<String> = Vec::new();
    let mut entomopathogens: Vec<String> = Vec::new();

    for row in &rows {
        let source = row.get("source_column")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_lowercase();
        let fungus = row.get("fungus_taxon")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();

        if source.contains("amf") || source.contains("arbuscular") {
            counts.amf += 1;
        } else if source.contains("emf") || source.contains("ectomycorrhiz") {
            counts.emf += 1;
        } else if source.contains("endophyt") {
            counts.endophytes += 1;
        } else if source.contains("mycoparasit") {
            counts.mycoparasites += 1;
            if !fungus.is_empty() {
                mycoparasites.push(fungus);
            }
        } else if source.contains("entomopathogen") {
            counts.entomopathogens += 1;
            if !fungus.is_empty() {
                entomopathogens.push(fungus.clone());
            }
        } else if source.contains("pathogenic") {
            counts.pathogenic += 1;
        }
    }

    let has_counts = counts.amf + counts.emf + counts.endophytes +
        counts.mycoparasites + counts.entomopathogens + counts.pathogenic > 0;

    let fungal_counts = if has_counts { Some(counts) } else { None };

    let beneficial = if !mycoparasites.is_empty() || !entomopathogens.is_empty() {
        Some(BeneficialFungi {
            mycoparasites: mycoparasites.into_iter().take(5).collect(),
            entomopathogens: entomopathogens.into_iter().take(5).collect(),
        })
    } else {
        None
    };

    (fungal_counts, beneficial)
}

/// Convert markdown to HTML using pulldown-cmark
fn markdown_to_html(markdown: &str) -> String {
    let mut options = Options::empty();
    options.insert(Options::ENABLE_TABLES);
    options.insert(Options::ENABLE_STRIKETHROUGH);
    options.insert(Options::ENABLE_YAML_STYLE_METADATA_BLOCKS);

    let parser = Parser::new_ext(markdown, options);
    let mut html_output = String::new();
    html::push_html(&mut html_output, parser);
    html_output
}

/// Get LocalConditions for a location name
fn get_local_conditions(location: &str) -> LocalConditions {
    match location.to_lowercase().as_str() {
        "singapore" => local_conditions::singapore(),
        "helsinki" => local_conditions::helsinki(),
        _ => local_conditions::london(), // Default to London
    }
}

pub async fn encyclopedia_page(
    State(state): State<AppState>,
    Path(wfo_id): Path<String>,
    Query(params): Query<EncyclopediaQuery>,
) -> impl IntoResponse {
    let location = params.location.unwrap_or_else(|| "london".to_string());
    let local_conditions = get_local_conditions(&location);

    // Get plant data from QueryEngine
    let plant_batches = match state.query_engine.get_plant(&wfo_id).await {
        Ok(batches) => batches,
        Err(e) => {
            tracing::error!("Failed to get plant {}: {}", wfo_id, e);
            return Html(format!("Plant not found: {}", wfo_id));
        }
    };

    let plant_data = match batch_to_hashmap(&plant_batches) {
        Some(data) => data,
        None => {
            return Html(format!("Plant not found: {}", wfo_id));
        }
    };

    // Extract display fields
    let scientific_name = plant_data
        .get("wfo_scientific_name")
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown")
        .to_string();

    let vernacular_name = plant_data
        .get("vernacular_name_en")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string());

    let family = plant_data
        .get("family")
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown")
        .to_string();

    // Generate encyclopedia markdown with suitability
    let markdown = match state.encyclopedia.generate_with_suitability(
        &wfo_id,
        &plant_data,
        None,  // organism_counts
        None,  // fungal_counts
        None,  // organism_profile
        None,  // ranked_pathogens
        None,  // beneficial_fungi
        None,  // related_species
        0,     // genus_species_count
        &local_conditions,
    ) {
        Ok(md) => md,
        Err(e) => {
            tracing::error!("Failed to generate encyclopedia: {}", e);
            format!("# Error\n\nFailed to generate encyclopedia: {}", e)
        }
    };

    // Convert markdown to HTML
    let content_html = markdown_to_html(&markdown);

    // Return full page template
    let template = EncyclopediaPageTemplate {
        wfo_id,
        scientific_name,
        vernacular_name,
        family,
        location,
        content_html,
    };

    Html(template.render().unwrap_or_else(|e| {
        format!("Template error: {}", e)
    }))
}

// ============================================================================
// Encyclopedia Page V2 (with structured view models)
// ============================================================================

#[derive(Template)]
#[template(path = "pages/encyclopedia_v2.html")]
pub struct EncyclopediaV2Template {
    pub data: EncyclopediaPageData,
}

pub async fn encyclopedia_page_v2(
    State(state): State<AppState>,
    Path(wfo_id): Path<String>,
    Query(params): Query<EncyclopediaQuery>,
) -> impl IntoResponse {
    let location = params.location.unwrap_or_else(|| "london".to_string());
    let local_conditions = get_local_conditions(&location);

    // Get plant data from QueryEngine
    let plant_batches = match state.query_engine.get_plant(&wfo_id).await {
        Ok(batches) => batches,
        Err(e) => {
            tracing::error!("Failed to get plant {}: {}", wfo_id, e);
            return Html(format!("Plant not found: {}", wfo_id));
        }
    };

    let plant_data = match batch_to_hashmap(&plant_batches) {
        Some(data) => data,
        None => {
            return Html(format!("Plant not found: {}", wfo_id));
        }
    };

    // Fetch organism data (pollinators, herbivores, predators)
    let organism_profile = match state.query_engine.get_organisms(&wfo_id, None).await {
        Ok(batches) => parse_organism_profile(&batches),
        Err(e) => {
            tracing::warn!("Failed to get organisms for {}: {}", wfo_id, e);
            None
        }
    };

    // Fetch fungi data (mycorrhizae, beneficial fungi)
    let (fungal_counts, beneficial_fungi) = match state.query_engine.get_fungi(&wfo_id, None).await {
        Ok(batches) => parse_fungi_data(&batches),
        Err(e) => {
            tracing::warn!("Failed to get fungi for {}: {}", wfo_id, e);
            (None, None)
        }
    };

    // Build encyclopedia data using view models
    let data = build_encyclopedia_data(
        &wfo_id,
        &plant_data,
        organism_profile.as_ref(),
        fungal_counts.as_ref(),
        None,  // ranked_pathogens (TODO: fetch from pathogens table)
        beneficial_fungi.as_ref(),
        None,  // related_species (TODO: fetch similar plants)
        0,     // genus_species_count
        Some(&local_conditions),
    );

    let template = EncyclopediaV2Template { data };

    Html(template.render().unwrap_or_else(|e| {
        format!("Template error: {}", e)
    }))
}
