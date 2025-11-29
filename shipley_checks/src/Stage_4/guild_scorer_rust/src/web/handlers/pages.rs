// Page handlers for HTML rendering with Askama

use axum::response::{Html, IntoResponse};
use askama::Template;

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
