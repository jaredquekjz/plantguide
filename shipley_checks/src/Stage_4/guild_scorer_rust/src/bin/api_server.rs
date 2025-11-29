// Phase 8.4: API Server Binary Entry Point
//
// Purpose: Start the Axum API server with DataFusion + Polars
// Usage: cargo run --features api --bin api_server

use guild_scorer_rust::{AppState, create_router};
use std::net::SocketAddr;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing (structured logging)
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| {
                    // Default log level: info for our crate, warn for others
                    "guild_scorer_rust=info,tower_http=debug,axum=debug,warn".into()
                }),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!("Starting API server...");

    // Configuration from environment variables
    // Default: shipley_checks/stage4 (local development)
    // Server: /opt/plantguide/data (set via systemd environment)
    let data_dir = std::env::var("DATA_DIR")
        .unwrap_or_else(|_| "shipley_checks/stage4".to_string());

    let climate_tier = std::env::var("CLIMATE_TIER")
        .unwrap_or_else(|_| "tier_3_humid_temperate".to_string());

    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(3000);

    tracing::info!("Configuration:");
    tracing::info!("  DATA_DIR: {}", data_dir);
    tracing::info!("  CLIMATE_TIER: {}", climate_tier);
    tracing::info!("  PORT: {}", port);

    // Initialize application state (loads data, builds indexes)
    tracing::info!("Initializing application state...");
    let state = AppState::new(&data_dir, &climate_tier).await?;
    tracing::info!("Application state initialized successfully");

    // Create router with all endpoints and middleware
    let app = create_router(state);

    // Bind to address
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("Starting server on {}", addr);

    // Start server
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!("Server listening on {}", addr);

    axum::serve(listener, app)
        .await?;

    Ok(())
}
