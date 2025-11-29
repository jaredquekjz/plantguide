# Iron-Rust Plant Encyclopedia: Implementation Guide

## 1. Overview

### Core Philosophy

| Principle | Implementation |
|-----------|----------------|
| Single state | Server only, no client state sync |
| Single language | Rust for logic, HTML for presentation |
| Compile-time safety | Askama templates, typed routes, typed extractors |
| Zero npm | Vendored JS files, Tailwind CLI standalone |
| AI-optimized | Compiler errors guide AI, not runtime debugging |

### Stack

| Layer | Technology | Context7 ID |
|-------|------------|-------------|
| Web Framework | Axum 0.7 | `/tokio-rs/axum` |
| HTMX Integration | axum-htmx | `/websites/rs_axum-htmx_axum_htmx` |
| Templates | Askama | `/websites/askama_readthedocs_io-en-stable` |
| Client Interactivity | Alpine.js | `/alpinejs/alpine` |
| AJAX/Navigation | HTMX 2.0 | `/bigskysoftware/htmx` |
| CSS Components | DaisyUI 4 | `/websites/daisyui` |
| CSS Utilities | Tailwind 3 | `/websites/v3_tailwindcss` |
| Drag-and-Drop | SortableJS | Vendored |

### Target Server

| Property | Value |
|----------|-------|
| **Provider** | Digital Ocean |
| **IPv4** | 134.199.166.0 |
| **Region** | Sydney (syd1) |
| **OS** | Ubuntu 24.04.3 LTS |
| **Specs** | 1 vCPU, 1GB RAM, 35GB Intel |
| **SSH** | `ssh root@134.199.166.0` |
| **Browser** | `http://134.199.166.0` |

---

## 2. Phase 1: Server Setup (One-Time)

### 2.1 Initial Server Config

```bash
ssh root@134.199.166.0

# Update system
apt update && apt upgrade -y

# Install essential tools
apt install -y build-essential pkg-config libssl-dev curl git

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source ~/.cargo/env

# Create app directory
mkdir -p /opt/plantguide/{data,assets,templates}
```

### 2.2 Deploy Data Files

**Required Data Files Overview:**

| Directory | File | Size | Purpose |
|-----------|------|------|---------|
| **phase7_output/** | `organisms_flat.parquet` | 1.5MB | Flattened organism interactions (DataFusion) |
| | `fungi_flat.parquet` | 230KB | Flattened fungal associations (DataFusion) |
| | `pathogens_ranked.parquet` | 79KB | Ranked pathogens for encyclopedia |
| | `predators_master.parquet` | 18KB | Master list of pest predators |
| **phase5_output/** | `normalization_params_7plant.json` | 16KB | Guild scoring calibration (7-plant) |
| | `normalization_params_2plant.json` | 4KB | Guild scoring calibration (2-plant) |
| | `csr_percentile_calibration_global.json` | 1KB | CSR percentile calibration |
| **phase4_output/** | `bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet` | 25MB | Master plant dataset (11,711 species) |
| **phase0_output/** | `organism_profiles_11711.parquet` | 1.8MB | Plant-organism interactions |
| | `fungal_guilds_hybrid_11711.parquet` | 414KB | Plant-fungus associations |
| | `herbivore_predators_11711.parquet` | 50KB | Herbivore → predator lookup |
| | `insect_fungal_parasites_11711.parquet` | 102KB | Herbivore → entomopathogenic fungi lookup (M3) |
| | `pathogen_antagonists_11711.parquet` | 75KB | Pathogen antagonist lookup |
| **phylogeny/** | `compact_tree_11711.bin` | ~2MB | Phylogenetic tree (binary) |
| | `mixgb_wfo_to_tree_mapping_11711.csv` | ~300KB | WFO ID → tree node mapping |
| **taxonomy/** | `kimi_gardener_labels.csv` | 1.6MB | Organism genus → category mapping (encyclopedia S5) |

**Total:** ~34MB (excluding photos, which go to Cloudflare R2)

**Deploy commands** (from `ellenberg/` directory):

```bash
# Phase 7 - DataFusion flattened tables (required)
rsync -avz --progress \
    shipley_checks/stage4/phase7_output/ \
    root@134.199.166.0:/opt/plantguide/data/phase7_output/

# Phase 5 - Calibration parameters (required)
rsync -avz --progress \
    shipley_checks/stage4/phase5_output/ \
    root@134.199.166.0:/opt/plantguide/data/phase5_output/

# Phase 4 - Master plant dataset (required)
rsync -avz --progress \
    shipley_checks/stage4/phase4_output/ \
    root@134.199.166.0:/opt/plantguide/data/phase4_output/

# Phase 0 - Interaction data (required)
rsync -avz --progress \
    shipley_checks/stage4/phase0_output/ \
    root@134.199.166.0:/opt/plantguide/data/phase0_output/

# Phylogeny - Tree data (required for M1 metric)
ssh root@134.199.166.0 "mkdir -p /opt/plantguide/data/phylogeny"
rsync -avz --progress \
    data/stage1/phlogeny/compact_tree_11711.bin \
    data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv \
    root@134.199.166.0:/opt/plantguide/data/phylogeny/

# Taxonomy - Organism categories (required for encyclopedia S5)
ssh root@134.199.166.0 "mkdir -p /opt/plantguide/data/taxonomy"
rsync -avz --progress \
    data/taxonomy/kimi_gardener_labels.csv \
    root@134.199.166.0:/opt/plantguide/data/taxonomy/
```

**Server directory structure after deployment:**

```
/opt/plantguide/data/
├── phase0_output/
│   ├── organism_profiles_11711.parquet
│   ├── fungal_guilds_hybrid_11711.parquet
│   ├── herbivore_predators_11711.parquet
│   ├── insect_fungal_parasites_11711.parquet
│   └── pathogen_antagonists_11711.parquet
├── phase4_output/
│   └── bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet
├── phase5_output/
│   ├── normalization_params_7plant.json
│   ├── normalization_params_2plant.json
│   └── csr_percentile_calibration_global.json
├── phase7_output/
│   ├── organisms_flat.parquet
│   ├── fungi_flat.parquet
│   ├── pathogens_ranked.parquet
│   └── predators_master.parquet
├── phylogeny/
│   ├── compact_tree_11711.bin
│   └── mixgb_wfo_to_tree_mapping_11711.csv
└── taxonomy/
    └── kimi_gardener_labels.csv
```

**Note:** Plant photos (~117,000 images) are NOT deployed to the server. They will be served from Cloudflare R2 CDN (to be configured separately).

### 2.3 Systemd Service

Create `/etc/systemd/system/plantguide.service`:

```ini
[Unit]
Description=Plant Encyclopedia API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/plantguide
ExecStart=/opt/plantguide/api_server
Restart=always
RestartSec=5
Environment=PORT=3000
Environment=RUST_LOG=info
Environment=DATA_DIR=/opt/plantguide/data
Environment=CLIMATE_TIER=tier_3_humid_temperate

[Install]
WantedBy=multi-user.target
```

Enable the service:

```bash
systemctl daemon-reload
systemctl enable plantguide
```

### 2.4 Caddy Reverse Proxy

Install Caddy:

```bash
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install caddy
```

Create `/etc/caddy/Caddyfile`:

```caddyfile
:80 {
    reverse_proxy localhost:3000
    encode gzip zstd
    header /assets/* Cache-Control "public, max-age=31536000"
}
```

Reload: `systemctl reload caddy`

### 2.5 Firewall Setup

```bash
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

### 2.6 Verification

Server setup is complete when:
- [ ] `/opt/plantguide/data/` contains phase0, phase5, phase7 parquet files
- [ ] `systemctl status plantguide` shows service enabled (will fail until binary deployed)
- [ ] `ufw status` shows ports 22, 80, 443 allowed

---

## 3. Phase 2: Local Tooling Setup (One-Time)

Working directory: `shipley_checks/src/Stage_4/guild_scorer_rust/`

### 3.1 Add Cargo Dependencies

Add to `Cargo.toml` under `[dependencies]` (in the `api` feature):

```toml
# Add to existing [dependencies] section
askama = { version = "0.12", features = ["with-axum"], optional = true }
askama_axum = { version = "0.4", optional = true }
axum-htmx = { version = "0.6", optional = true }
urlencoding = { version = "2.1", optional = true }

# Update [features] api section to include new deps
[features]
api = [
    "datafusion",
    "arrow",
    "axum",
    "tokio",
    "tower",
    "tower-http",
    "moka",
    "hyper",
    "tracing",
    "tracing-subscriber",
    "chrono",
    "askama",
    "askama_axum",
    "axum-htmx",
    "urlencoding",
]
```

### 3.2 Download Tailwind CLI

```bash
curl -sLO https://github.com/tailwindlabs/tailwindcss/releases/latest/download/tailwindcss-linux-x64
chmod +x tailwindcss-linux-x64
mv tailwindcss-linux-x64 tailwindcss
```

### 3.3 Download Vendored JS

```bash
mkdir -p assets/js assets/css

# HTMX
curl -sL "https://unpkg.com/htmx.org@2.0.4/dist/htmx.min.js" > assets/js/htmx.min.js

# Alpine.js
curl -sL "https://cdn.jsdelivr.net/npm/alpinejs@3.14.8/dist/cdn.min.js" > assets/js/alpine.min.js

# SortableJS
curl -sL "https://cdn.jsdelivr.net/npm/sortablejs@1.15.6/Sortable.min.js" > assets/js/sortable.min.js

# DaisyUI CSS
curl -sL "https://cdn.jsdelivr.net/npm/daisyui@4/dist/full.min.css" > assets/css/daisyui.css
```

### 3.4 Create Directory Structure

```bash
mkdir -p templates/{pages,components,fragments,partials}
mkdir -p src/web/handlers
```

### 3.5 Create Makefile

```makefile
.PHONY: dev build deploy css watch-css clean

# Development server with auto-reload
dev:
	cargo watch -x 'run --features api' -w src -w templates

# Build debug binary (faster compilation for development)
build:
	cargo build --features api
	./tailwindcss -i input.css -o assets/css/styles.css --minify

# Deploy to DO server
deploy: build
	scp target/debug/api_server root@134.199.166.0:/opt/plantguide/
	rsync -avz --delete assets/ root@134.199.166.0:/opt/plantguide/assets/
	rsync -avz --delete templates/ root@134.199.166.0:/opt/plantguide/templates/
	ssh root@134.199.166.0 "systemctl restart plantguide"
	@echo "Deployed! Access at http://134.199.166.0"

# Build CSS
css:
	./tailwindcss -i input.css -o assets/css/styles.css --minify

# Watch CSS during development
watch-css:
	./tailwindcss -i input.css -o assets/css/styles.css --watch

# Clean
clean:
	cargo clean
	rm -f assets/css/styles.css
```

### 3.6 Create Tailwind Config

Create `tailwind.config.js`:

```javascript
module.exports = {
  content: [
    "./templates/**/*.html",
    "./src/**/*.rs",
  ],
  theme: {
    extend: {},
  },
}
```

Create `input.css`:

```css
@import "./assets/css/daisyui.css";
@tailwind base;
@tailwind components;
@tailwind utilities;
```

### 3.7 Verification

Local tooling is ready when:
- [ ] `cargo build --features api` succeeds
- [ ] `./tailwindcss --help` works
- [ ] `assets/js/` contains htmx.min.js, alpine.min.js, sortable.min.js
- [ ] `assets/css/` contains daisyui.css

---

## 4. Phase 3: Minimal Web Layer (First Deploy)

### 4.1 Create src/routes.rs

```rust
// src/routes.rs
use std::fmt;

#[derive(Debug, Clone)]
pub enum Route {
    Home,
    Search { query: Option<String>, page: Option<u32> },
    Plant { wfo_id: String },
    PlantEncyclopedia { wfo_id: String },
    GuildBuilder,
    FragmentSearchResults { query: String, page: u32 },
    FragmentPlantCard { wfo_id: String },
    FragmentGuildScore,
}

impl Route {
    pub fn url(&self) -> String {
        match self {
            Route::Home => "/".into(),
            Route::Search { query: None, page: None } => "/search".into(),
            Route::Search { query: Some(q), page: None } => {
                format!("/search?q={}", urlencoding::encode(q))
            }
            Route::Search { query: Some(q), page: Some(p) } => {
                format!("/search?q={}&page={}", urlencoding::encode(q), p)
            }
            Route::Search { query: None, page: Some(p) } => {
                format!("/search?page={}", p)
            }
            Route::Plant { wfo_id } => format!("/plant/{}", wfo_id),
            Route::PlantEncyclopedia { wfo_id } => format!("/plant/{}/encyclopedia", wfo_id),
            Route::GuildBuilder => "/guild/builder".into(),
            Route::FragmentSearchResults { query, page } => {
                format!("/fragments/search?q={}&page={}", urlencoding::encode(query), page)
            }
            Route::FragmentPlantCard { wfo_id } => format!("/fragments/plant/{}", wfo_id),
            Route::FragmentGuildScore => "/fragments/guild/score".into(),
        }
    }
}

impl fmt::Display for Route {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.url())
    }
}
```

### 4.2 Create src/web/mod.rs

```rust
// src/web/mod.rs
pub mod handlers;
pub mod templates;
```

Create `src/web/handlers/mod.rs`:

```rust
// src/web/handlers/mod.rs
mod pages;

pub use pages::*;
```

Create `src/web/handlers/pages.rs`:

```rust
// src/web/handlers/pages.rs
use axum::response::{Html, IntoResponse};
use askama::Template;

#[derive(Template)]
#[template(path = "pages/home.html")]
pub struct HomeTemplate {
    pub title: String,
    pub plant_count: usize,
}

pub async fn home_page() -> impl IntoResponse {
    let template = HomeTemplate {
        title: "Plant Encyclopedia".to_string(),
        plant_count: 11711,
    };
    Html(template.render().unwrap())
}
```

Create `src/web/templates/mod.rs`:

```rust
// src/web/templates/mod.rs
// Template structs will be added here as we build pages
```

### 4.3 Create templates/base.html

```html
<!DOCTYPE html>
<html lang="en" data-theme="forest">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{% block title %}Plant Encyclopedia{% endblock %}</title>
    <link rel="stylesheet" href="/assets/css/styles.css">
    <script src="/assets/js/htmx.min.js" defer></script>
    <script src="/assets/js/alpine.min.js" defer></script>
</head>
<body class="min-h-screen bg-base-200" hx-boost="true">
    <nav class="navbar bg-base-100 shadow-lg">
        <div class="container mx-auto">
            <a href="/" class="btn btn-ghost text-xl">Plant Encyclopedia</a>
            <div class="flex-1"></div>
            <a href="/search" class="btn btn-ghost">Search</a>
            <a href="/guild/builder" class="btn btn-ghost">Guild Builder</a>
        </div>
    </nav>

    <main id="main-content" class="container mx-auto px-4 py-8">
        {% block content %}{% endblock %}
    </main>

    <footer class="footer footer-center p-4 bg-base-300 text-base-content">
        <p>11,711 European Plants</p>
    </footer>
</body>
</html>
```

### 4.4 Create templates/pages/home.html

```html
{% extends "base.html" %}

{% block title %}{{ title }}{% endblock %}

{% block content %}
<div class="hero min-h-[60vh]">
    <div class="hero-content text-center">
        <div class="max-w-md">
            <h1 class="text-5xl font-bold">Plant Encyclopedia</h1>
            <p class="py-6">
                Explore {{ plant_count }} European plants with ecological data,
                growing guides, and guild compatibility scoring.
            </p>
            <a href="/search" class="btn btn-primary">Search Plants</a>
            <a href="/guild/builder" class="btn btn-secondary ml-2">Build a Guild</a>
        </div>
    </div>
</div>
{% endblock %}
```

### 4.5 Extend api_server.rs

Add to existing router in `src/api_server.rs`:

```rust
// Add imports at top
use tower_http::services::ServeDir;

// In create_router(), add these routes:
pub fn create_router(state: AppState) -> Router {
    Router::new()
        // Existing JSON API routes...
        .route("/health", get(health_check))
        .route("/api/plants/search", get(search_plants_json))
        // ... other existing routes ...

        // NEW: HTML pages
        .route("/", get(crate::web::handlers::home_page))

        // NEW: Static assets
        .nest_service("/assets", ServeDir::new("assets"))

        // Existing middleware...
        .layer(CompressionLayer::new())
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}
```

Add module declaration to `src/lib.rs`:

```rust
#[cfg(feature = "api")]
pub mod web;
#[cfg(feature = "api")]
pub mod routes;
```

### 4.6 First Deploy

```bash
make deploy
```

### 4.7 Verification

Phase 3 is complete when:
- [ ] `http://134.199.166.0` shows home page with "Plant Encyclopedia" hero
- [ ] Navigation links appear in header
- [ ] DaisyUI styling is applied (forest theme)

---

## 5. Phase 4: Core Pages

### 5.1 Search Page

Create `templates/pages/search.html`:

```html
{% extends "base.html" %}

{% block title %}Search - Plant Encyclopedia{% endblock %}

{% block content %}
<div class="card bg-base-100 shadow-xl">
    <div class="card-body">
        <h2 class="card-title">Search Plants</h2>

        <input type="search"
               name="q"
               placeholder="Search by species name..."
               class="input input-bordered w-full"
               hx-get="/fragments/search"
               hx-trigger="keyup changed delay:300ms"
               hx-target="#search-results"
               value="{{ query }}">

        <div id="search-results" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mt-4">
            {% for card in cards %}
            {% include "components/plant_card.html" %}
            {% endfor %}
        </div>
    </div>
</div>
{% endblock %}
```

Create `templates/components/plant_card.html`:

```html
<article class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow cursor-pointer"
         hx-get="/plant/{{ wfo_id }}"
         hx-target="#main-content"
         hx-push-url="true">

    <div class="card-body p-4">
        <h2 class="card-title text-lg">
            <em>{{ species }}</em>
        </h2>

        {% if common_name.is_some() %}
        <p class="text-sm opacity-70">{{ common_name.as_ref().unwrap() }}</p>
        {% endif %}

        <p class="text-xs text-base-content/60">{{ family }}</p>

        <div class="flex flex-wrap gap-1 mt-2">
            <div class="badge badge-outline gap-1" title="Light">
                L: {{ eive_light }}
            </div>
            <div class="badge badge-outline gap-1" title="Moisture">
                M: {{ eive_moisture }}
            </div>
            {% if is_nitrogen_fixer %}
            <div class="badge badge-success gap-1">N-Fixer</div>
            {% endif %}
        </div>
    </div>
</article>
```

Create `templates/fragments/search_results.html`:

```html
{% for card in cards %}
{% include "components/plant_card.html" %}
{% endfor %}

{% if cards.is_empty() %}
<div class="col-span-full text-center py-8 text-base-content/50">
    No plants found
</div>
{% endif %}
```

Add handler in `src/web/handlers/pages.rs`:

```rust
use axum::extract::{Query, State};
use axum_htmx::HxRequest;
use crate::AppState;

#[derive(serde::Deserialize)]
pub struct SearchParams {
    pub q: Option<String>,
    pub page: Option<u32>,
}

#[derive(Template)]
#[template(path = "pages/search.html")]
pub struct SearchTemplate {
    pub query: String,
    pub cards: Vec<PlantCardData>,
}

#[derive(Template)]
#[template(path = "fragments/search_results.html")]
pub struct SearchResultsFragment {
    pub cards: Vec<PlantCardData>,
}

pub struct PlantCardData {
    pub wfo_id: String,
    pub species: String,
    pub common_name: Option<String>,
    pub family: String,
    pub eive_light: f64,
    pub eive_moisture: f64,
    pub is_nitrogen_fixer: bool,
}

pub async fn search_page(
    State(state): State<AppState>,
    HxRequest(is_htmx): HxRequest,
    Query(params): Query<SearchParams>,
) -> impl IntoResponse {
    let query = params.q.unwrap_or_default();

    // Use existing query engine
    let plants = state.query_engine
        .search_plants_by_name(&query, params.page.unwrap_or(1), 20)
        .await
        .unwrap_or_default();

    let cards: Vec<PlantCardData> = plants.iter().map(|p| PlantCardData {
        wfo_id: p.wfo_id.clone(),
        species: p.species.clone(),
        common_name: p.common_name.clone(),
        family: p.family.clone(),
        eive_light: p.eive_light,
        eive_moisture: p.eive_moisture,
        is_nitrogen_fixer: p.is_nitrogen_fixer,
    }).collect();

    if is_htmx {
        Html(SearchResultsFragment { cards }.render().unwrap())
    } else {
        Html(SearchTemplate { query, cards }.render().unwrap())
    }
}
```

Add route:

```rust
.route("/search", get(crate::web::handlers::search_page))
.route("/fragments/search", get(crate::web::handlers::search_page))
```

### 5.2 Plant Detail Page

Create `templates/pages/plant_detail.html`:

```html
{% extends "base.html" %}

{% block title %}{{ species }} - Plant Encyclopedia{% endblock %}

{% block content %}
<div class="card bg-base-100 shadow-xl">
    <div class="card-body">
        <h1 class="text-3xl font-bold"><em>{{ species }}</em></h1>

        {% if common_name.is_some() %}
        <p class="text-xl opacity-70">{{ common_name.as_ref().unwrap() }}</p>
        {% endif %}

        <div class="divider"></div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
                <h3 class="text-lg font-semibold mb-2">Taxonomy</h3>
                <p><strong>Family:</strong> {{ family }}</p>
                <p><strong>WFO ID:</strong> {{ wfo_id }}</p>
            </div>

            <div>
                <h3 class="text-lg font-semibold mb-2">Growing Conditions</h3>
                <p><strong>Light (EIVE):</strong> {{ eive_light }}</p>
                <p><strong>Moisture (EIVE):</strong> {{ eive_moisture }}</p>
                <p><strong>Temperature (EIVE):</strong> {{ eive_temperature }}</p>
            </div>
        </div>

        <div class="card-actions justify-end mt-6">
            <a href="/plant/{{ wfo_id }}/encyclopedia" class="btn btn-primary">
                View Encyclopedia Article
            </a>
        </div>
    </div>
</div>
{% endblock %}
```

### 5.3 Encyclopedia Page

Create `templates/pages/encyclopedia.html`:

```html
{% extends "base.html" %}

{% block title %}{{ species }} Encyclopedia - Plant Encyclopedia{% endblock %}

{% block content %}
<article class="prose prose-lg max-w-none">
    {{ content_html|safe }}
</article>

<div class="mt-8">
    <a href="/plant/{{ wfo_id }}" class="btn btn-outline">Back to Plant Details</a>
</div>
{% endblock %}
```

Handler:

```rust
pub async fn encyclopedia_page(
    State(state): State<AppState>,
    Path(wfo_id): Path<String>,
) -> impl IntoResponse {
    // Use existing encyclopedia generator
    let plant_data = state.query_engine.get_plant(&wfo_id).await.unwrap();
    let markdown = state.encyclopedia.generate(&wfo_id, &plant_data, None, None, None, None, None, None, 0).unwrap();

    // Convert markdown to HTML (use pulldown-cmark or similar)
    let content_html = markdown_to_html(&markdown);

    let template = EncyclopediaTemplate {
        wfo_id,
        species: plant_data.species.clone(),
        content_html,
    };

    Html(template.render().unwrap())
}
```

### 5.4 Verification

Phase 4 is complete when:
- [ ] `/search` shows search input with live results
- [ ] Clicking a plant card navigates to detail page
- [ ] `/plant/{wfo_id}/encyclopedia` shows encyclopedia article

---

## 6. Phase 5: Guild Builder

### 6.1 Guild Builder Page

Create `templates/pages/guild_builder.html`:

```html
{% extends "base.html" %}

{% block title %}Guild Builder - Plant Encyclopedia{% endblock %}

{% block content %}
<div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
    <!-- Search panel -->
    <div class="lg:col-span-2">
        <div class="card bg-base-100 shadow">
            <div class="card-body">
                <h2 class="card-title">Find Plants</h2>

                <input type="search"
                       name="q"
                       placeholder="Search plants..."
                       class="input input-bordered w-full"
                       hx-get="/fragments/search"
                       hx-trigger="keyup changed delay:300ms"
                       hx-target="#search-results">

                <div id="search-results" class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
                </div>
            </div>
        </div>
    </div>

    <!-- Guild panel -->
    <div class="lg:col-span-1">
        <div class="card bg-base-100 shadow sticky top-4">
            <div class="card-body">
                <h2 class="card-title">Your Guild</h2>

                <ul id="guild-plant-list"
                    class="space-y-2 min-h-[200px] bg-base-200 rounded-lg p-4"
                    x-data
                    x-init="new Sortable($el, {
                        animation: 150,
                        onEnd: () => htmx.trigger('#guild-plant-list', 'guild-updated')
                    })"
                    hx-post="/fragments/guild/score"
                    hx-trigger="guild-updated"
                    hx-include="[name='plant_id']"
                    hx-target="#guild-score">

                    <li class="text-center text-base-content/50 py-8" id="empty-state">
                        Add plants to build your guild
                    </li>
                </ul>

                <div id="guild-score" class="mt-4">
                    <!-- Score loaded via HTMX -->
                </div>
            </div>
        </div>
    </div>
</div>

<script src="/assets/js/sortable.min.js"></script>
{% endblock %}
```

### 6.2 Score Display Component

Create `templates/components/guild_score.html`:

```html
<div class="stats shadow w-full">
    <div class="stat">
        <div class="stat-title">Guild Score</div>
        <div class="stat-value text-primary">{{ overall_score }}%</div>
        <div class="stat-desc">{{ score_label }}</div>
    </div>
</div>

<div class="space-y-2 mt-4">
    {% for metric in metrics %}
    <div class="flex justify-between items-center">
        <span class="text-sm">{{ metric.name }}</span>
        <div class="badge {{ metric.color_class }}">{{ metric.value }}%</div>
    </div>
    {% endfor %}
</div>
```

Handler:

```rust
pub async fn score_guild(
    State(state): State<AppState>,
    HxRequest(is_htmx): HxRequest,
    Json(payload): Json<GuildScoreRequest>,
) -> impl IntoResponse {
    let scorer = state.guild_scorer.clone();
    let plant_ids = payload.plant_ids.clone();

    let result = tokio::task::spawn_blocking(move || {
        scorer.score_guild_parallel(&plant_ids)
    }).await.unwrap().unwrap();

    let template = GuildScoreTemplate {
        overall_score: result.overall_score,
        score_label: score_to_label(result.overall_score),
        metrics: vec![
            MetricData { name: "Phylogenetic Diversity".into(), value: result.metrics[0], color_class: color_for_value(result.metrics[0]) },
            MetricData { name: "Growth Compatibility".into(), value: result.metrics[1], color_class: color_for_value(result.metrics[1]) },
            MetricData { name: "Insect Control".into(), value: result.metrics[2], color_class: color_for_value(result.metrics[2]) },
            MetricData { name: "Disease Control".into(), value: result.metrics[3], color_class: color_for_value(result.metrics[3]) },
            MetricData { name: "Beneficial Fungi".into(), value: result.metrics[4], color_class: color_for_value(result.metrics[4]) },
            MetricData { name: "Structural Diversity".into(), value: result.metrics[5], color_class: color_for_value(result.metrics[5]) },
            MetricData { name: "Pollinator Support".into(), value: result.metrics[6], color_class: color_for_value(result.metrics[6]) },
        ],
    };

    Html(template.render().unwrap())
}

fn score_to_label(score: f64) -> String {
    match score as u32 {
        0..=30 => "Needs Work",
        31..=50 => "Basic",
        51..=70 => "Good",
        71..=85 => "Great",
        _ => "Excellent",
    }.to_string()
}

fn color_for_value(value: f64) -> String {
    match value as u32 {
        0..=30 => "badge-error",
        31..=60 => "badge-warning",
        61..=80 => "badge-info",
        _ => "badge-success",
    }.to_string()
}
```

### 6.3 Verification

Phase 5 is complete when:
- [ ] `/guild/builder` shows search + guild panels
- [ ] Plants can be added to guild
- [ ] Drag-and-drop reordering works
- [ ] Score updates after changes

---

## 7. Phase 6: Polish

### 7.1 Loading States

Add to `templates/base.html`:

```html
<style>
    .htmx-request .htmx-indicator {
        display: inline-block;
    }
    .htmx-indicator {
        display: none;
    }
</style>
```

Add loading indicator to search input:

```html
<span class="htmx-indicator loading loading-spinner loading-sm"></span>
```

### 7.2 Error Handling

Create error template:

```rust
#[derive(Template)]
#[template(path = "pages/error.html")]
pub struct ErrorTemplate {
    pub message: String,
    pub status_code: u16,
}

impl IntoResponse for AppError {
    fn into_response(self) -> axum::response::Response {
        let (status, message) = match self {
            AppError::NotFound => (StatusCode::NOT_FOUND, "Plant not found"),
            AppError::Internal(e) => (StatusCode::INTERNAL_SERVER_ERROR, "Server error"),
        };

        let template = ErrorTemplate {
            message: message.to_string(),
            status_code: status.as_u16(),
        };

        (status, Html(template.render().unwrap())).into_response()
    }
}
```

### 7.3 Mobile Responsive

DaisyUI responsive classes are already used:
- `grid-cols-1 md:grid-cols-2 lg:grid-cols-3`
- `lg:col-span-2`

Test on mobile viewport.

### 7.4 Verification

Phase 6 is complete when:
- [ ] Loading spinners appear during HTMX requests
- [ ] Error pages display gracefully
- [ ] Site is usable on mobile viewport

---

## 8. Operations Reference

### 8.1 Development Commands

```bash
# Local development (two terminals)
make dev         # Terminal 1: Rust server with auto-reload
make watch-css   # Terminal 2: Tailwind CSS watcher

# Build only
make build       # Debug build
make css         # CSS only
```

### 8.2 Deployment Commands

```bash
# Full deploy (build + copy + restart)
make deploy

# Quick sync (assets/templates only, no Rust rebuild)
rsync -avz --delete assets/ root@134.199.166.0:/opt/plantguide/assets/
rsync -avz --delete templates/ root@134.199.166.0:/opt/plantguide/templates/
ssh root@134.199.166.0 "systemctl restart plantguide"
```

### 8.3 Server Management

```bash
# Service control
ssh root@134.199.166.0 "systemctl status plantguide"
ssh root@134.199.166.0 "systemctl restart plantguide"
ssh root@134.199.166.0 "journalctl -u plantguide -f"

# Health check
ssh root@134.199.166.0 "curl http://localhost:3000/health"
```

### 8.4 Context7 IDs for AI Assistance

When generating code, fetch docs from:

| Library | Context7 ID |
|---------|-------------|
| HTMX | `/bigskysoftware/htmx` |
| Axum-HTMX | `/websites/rs_axum-htmx_axum_htmx` |
| Askama | `/websites/askama_readthedocs_io-en-stable` |
| Alpine.js | `/alpinejs/alpine` |
| DaisyUI | `/websites/daisyui` |
| Tailwind | `/websites/v3_tailwindcss` |
| Axum | `/tokio-rs/axum` |
