// Phase 8.5: API Integration Tests
//
// Purpose: Test all API endpoints with real data + accuracy validation
// Run with: cargo test --features api --test api_integration_tests

#[cfg(feature = "api")]
mod api_tests {
    use axum::{
        body::Body,
        http::{Request, StatusCode},
    };
    use guild_scorer_rust::{AppState, create_router};
    use serde_json::Value;
    use tower::ServiceExt; // for oneshot

    // Helper: Create test app state
    async fn create_test_app() -> Result<axum::Router, Box<dyn std::error::Error>> {
        let data_dir = std::env::var("TEST_DATA_DIR")
            .unwrap_or_else(|_| {
                "/home/olier/ellenberg/shipley_checks/stage4/phase7_output".to_string()
            });

        let state = AppState::new(&data_dir, "tier_3_humid_temperate").await?;
        let app = create_router(state);
        Ok(app)
    }

    // Helper: Parse JSON response
    async fn json_response(response: axum::response::Response) -> Value {
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("Failed to read response body");
        serde_json::from_slice(&body).expect("Failed to parse JSON")
    }

    // =========================================================================
    // Section 1: Health Check
    // =========================================================================

    #[tokio::test]
    async fn test_health_check() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test (Phase 7 data not available): {}", e);
                return;
            }
        };

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/health")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        assert_eq!(body["status"], "healthy");
        assert!(body["timestamp"].is_string());
    }

    // =========================================================================
    // Section 2: Plant Search - Basic Tests
    // =========================================================================

    #[tokio::test]
    async fn test_plant_search_no_filters() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=10")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        assert!(body["rows"].as_u64().unwrap() > 0);
        assert!(body["data"].is_array());
    }

    #[tokio::test]
    async fn test_plant_search_with_filters() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Search for full-light, drought-tolerant plants
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?min_light=7.0&drought_tolerant=true&limit=20")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        let data = body["data"].as_array().unwrap();

        // Verify all results meet criteria
        for plant in data {
            let eive_l = plant["EIVE_L"].as_f64().unwrap();
            assert!(eive_l >= 7.0, "EIVE_L should be >= 7.0, got {}", eive_l);

            if let Some(drought_tolerant) = plant["drought_tolerant"].as_bool() {
                assert!(drought_tolerant, "drought_tolerant should be true");
            }
        }
    }

    // =========================================================================
    // Section 3: Plant Search - EIVE Filtering (from Test Plan)
    // =========================================================================

    #[tokio::test]
    async fn test_search_shade_plants() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Shade plants: max_light=4 (woodland understory)
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?max_light=4&limit=20")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        let data = body["data"].as_array().unwrap();

        assert!(!data.is_empty(), "Should find shade-tolerant plants");

        for plant in data {
            if let Some(eive_l) = plant["EIVE_L"].as_f64() {
                assert!(eive_l <= 4.0, "EIVE_L should be <= 4.0 for shade plants, got {}", eive_l);
            }
        }
    }

    #[tokio::test]
    async fn test_search_acid_soil_plants() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Acid-loving plants: max_ph=4 (heathland/bog)
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?max_ph=4&limit=20")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        let data = body["data"].as_array().unwrap();

        for plant in data {
            if let Some(eive_r) = plant["EIVE_R"].as_f64() {
                assert!(eive_r <= 4.0, "EIVE_R should be <= 4.0 for acid soil plants, got {}", eive_r);
            }
        }
    }

    #[tokio::test]
    async fn test_search_mediterranean_plants() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Mediterranean: high light, low moisture
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?min_light=7&max_moisture=4&limit=20")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        let data = body["data"].as_array().unwrap();

        for plant in data {
            if let Some(eive_l) = plant["EIVE_L"].as_f64() {
                assert!(eive_l >= 7.0, "EIVE_L should be >= 7.0, got {}", eive_l);
            }
            if let Some(eive_m) = plant["EIVE_M"].as_f64() {
                assert!(eive_m <= 4.0, "EIVE_M should be <= 4.0, got {}", eive_m);
            }
        }
    }

    // =========================================================================
    // Section 4: Plant Search - CSR Strategy Filtering
    // =========================================================================

    #[tokio::test]
    async fn test_search_csr_competitive() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Competitive dominants: min_c=0.6
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?min_c=0.6&limit=20")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        let data = body["data"].as_array().unwrap();

        for plant in data {
            if let Some(c_norm) = plant["C_norm"].as_f64() {
                assert!(c_norm >= 0.6, "C_norm should be >= 0.6, got {}", c_norm);
            }
        }
    }

    #[tokio::test]
    async fn test_search_csr_stress_tolerant() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Stress-tolerant: min_s=0.6
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?min_s=0.6&limit=20")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        let data = body["data"].as_array().unwrap();

        for plant in data {
            if let Some(s_norm) = plant["S_norm"].as_f64() {
                assert!(s_norm >= 0.6, "S_norm should be >= 0.6, got {}", s_norm);
            }
        }
    }

    #[tokio::test]
    async fn test_search_csr_ruderal() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Ruderal colonizers: min_r=0.6
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?min_r=0.6&limit=20")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        let data = body["data"].as_array().unwrap();

        for plant in data {
            if let Some(r_norm) = plant["R_norm"].as_f64() {
                assert!(r_norm >= 0.6, "R_norm should be >= 0.6, got {}", r_norm);
            }
        }
    }

    // =========================================================================
    // Section 5: Single Plant Lookup
    // =========================================================================

    #[tokio::test]
    async fn test_get_plant_by_id() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Use a known plant ID
        let plant_id = "wfo-0000649953";

        let response = app
            .oneshot(
                Request::builder()
                    .uri(&format!("/api/plants/{}", plant_id))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let status = response.status();
        assert!(
            status == StatusCode::OK || status == StatusCode::NOT_FOUND,
            "Status should be OK or NOT_FOUND, got {:?}",
            status
        );

        if status == StatusCode::OK {
            let body: Value = json_response(response).await;
            assert!(body["rows"].as_u64().unwrap() > 0);
            let data = body["data"].as_array().unwrap();
            assert_eq!(data[0]["wfo_taxon_id"], plant_id);
        }
    }

    #[tokio::test]
    async fn test_get_plant_not_found() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/plants/nonexistent-id-12345")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::NOT_FOUND);
    }

    // =========================================================================
    // Section 6: Accuracy Validation - Reference Plants
    // =========================================================================

    #[tokio::test]
    async fn test_reference_quercus_robur() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Quercus robur - common oak
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/plants/wfo-0000292858")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        if response.status() == StatusCode::NOT_FOUND {
            eprintln!("Quercus robur (wfo-0000292858) not in dataset, skipping");
            return;
        }

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        let data = body["data"].as_array().unwrap();
        assert!(!data.is_empty(), "Quercus robur should exist");

        let plant = &data[0];
        assert_eq!(plant["family"].as_str().unwrap(), "Fagaceae", "Quercus robur family should be Fagaceae");
        assert_eq!(plant["genus"].as_str().unwrap(), "Quercus", "Genus should be Quercus");
    }

    #[tokio::test]
    async fn test_reference_coffea_arabica() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Coffea arabica - coffee plant
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/plants/wfo-0000910097")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        if response.status() == StatusCode::NOT_FOUND {
            eprintln!("Coffea arabica (wfo-0000910097) not in dataset, skipping");
            return;
        }

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        let data = body["data"].as_array().unwrap();
        assert!(!data.is_empty(), "Coffea arabica should exist");

        let plant = &data[0];
        assert_eq!(plant["family"].as_str().unwrap(), "Rubiaceae", "Coffea arabica family should be Rubiaceae");
    }

    // =========================================================================
    // Section 7: Accuracy Validation - Data Integrity
    // =========================================================================

    #[tokio::test]
    async fn test_eive_value_ranges() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Sample 100 plants and verify EIVE ranges
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=100")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        let data = body["data"].as_array().unwrap();

        for plant in data {
            // EIVE_L: 1-9 (light)
            if let Some(eive_l) = plant["EIVE_L"].as_f64() {
                assert!(eive_l >= 1.0 && eive_l <= 9.0,
                    "EIVE_L should be 1-9, got {}", eive_l);
            }

            // EIVE_M: 1-12 (moisture)
            if let Some(eive_m) = plant["EIVE_M"].as_f64() {
                assert!(eive_m >= 1.0 && eive_m <= 12.0,
                    "EIVE_M should be 1-12, got {}", eive_m);
            }

            // EIVE_T: 1-9 (temperature)
            if let Some(eive_t) = plant["EIVE_T"].as_f64() {
                assert!(eive_t >= 1.0 && eive_t <= 9.0,
                    "EIVE_T should be 1-9, got {}", eive_t);
            }

            // EIVE_N: 1-9 (nitrogen)
            if let Some(eive_n) = plant["EIVE_N"].as_f64() {
                assert!(eive_n >= 1.0 && eive_n <= 9.0,
                    "EIVE_N should be 1-9, got {}", eive_n);
            }

            // EIVE_R: 1-9 (pH/reaction)
            if let Some(eive_r) = plant["EIVE_R"].as_f64() {
                assert!(eive_r >= 1.0 && eive_r <= 9.0,
                    "EIVE_R should be 1-9, got {}", eive_r);
            }
        }
    }

    #[tokio::test]
    async fn test_csr_normalization() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Verify CSR normalized values are in 0-1 range
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=100")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        let data = body["data"].as_array().unwrap();

        for plant in data {
            if let Some(c_norm) = plant["C_norm"].as_f64() {
                assert!(c_norm >= 0.0 && c_norm <= 1.0,
                    "C_norm should be 0-1, got {}", c_norm);
            }
            if let Some(s_norm) = plant["S_norm"].as_f64() {
                assert!(s_norm >= 0.0 && s_norm <= 1.0,
                    "S_norm should be 0-1, got {}", s_norm);
            }
            if let Some(r_norm) = plant["R_norm"].as_f64() {
                assert!(r_norm >= 0.0 && r_norm <= 1.0,
                    "R_norm should be 0-1, got {}", r_norm);
            }
        }
    }

    // =========================================================================
    // Section 8: Similarity Search
    // =========================================================================

    #[tokio::test]
    async fn test_find_similar_plants() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // First get any plant ID
        let search_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=1")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let search_body: Value = json_response(search_response).await;
        let data = search_body["data"].as_array().unwrap();

        if data.is_empty() {
            eprintln!("No plants available for similarity test");
            return;
        }

        let plant_id = data[0]["wfo_taxon_id"].as_str().unwrap();

        // Find similar plants
        let similarity_request = serde_json::json!({
            "plant_id": plant_id,
            "top_k": 5
        });

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/plants/similar")
                    .header("content-type", "application/json")
                    .body(Body::from(similarity_request.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        let similar = body["data"].as_array().unwrap();

        // Should return up to 5 similar plants (excluding the query plant itself)
        assert!(similar.len() <= 5);

        // Verify eive_distance column exists and is sorted ascending
        if similar.len() >= 2 {
            let dist1 = similar[0]["eive_distance"].as_f64().unwrap();
            let dist2 = similar[1]["eive_distance"].as_f64().unwrap();
            assert!(dist1 <= dist2, "Results should be sorted by distance");
        }
    }

    // =========================================================================
    // Section 9: Organism Interactions
    // =========================================================================

    #[tokio::test]
    async fn test_get_organisms() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Get any plant with organisms
        let search_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=10")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let search_body: Value = json_response(search_response).await;
        let data = search_body["data"].as_array().unwrap();

        if data.is_empty() {
            return;
        }

        let plant_id = data[0]["wfo_taxon_id"].as_str().unwrap();

        // Get organisms for this plant
        let response = app
            .oneshot(
                Request::builder()
                    .uri(&format!("/api/plants/{}/organisms", plant_id))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        assert!(body["rows"].is_number());
        assert!(body["data"].is_array());
    }

    #[tokio::test]
    async fn test_organisms_by_type_pollinators() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Get any plant
        let search_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=10")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let search_body: Value = json_response(search_response).await;
        let data = search_body["data"].as_array().unwrap();

        if data.is_empty() {
            return;
        }

        let plant_id = data[0]["wfo_taxon_id"].as_str().unwrap();

        // Filter by interaction type
        let response = app
            .oneshot(
                Request::builder()
                    .uri(&format!("/api/plants/{}/organisms?interaction_type=pollinators", plant_id))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        let organisms = body["data"].as_array().unwrap();

        // Verify all returned organisms are pollinators
        for org in organisms {
            assert_eq!(org["interaction_type"].as_str().unwrap(), "pollinators",
                "Filtered organisms should only be pollinators");
        }
    }

    // =========================================================================
    // Section 10: Fungal Associations
    // =========================================================================

    #[tokio::test]
    async fn test_get_fungi() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Get any plant
        let search_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=10")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let search_body: Value = json_response(search_response).await;
        let data = search_body["data"].as_array().unwrap();

        if data.is_empty() {
            return;
        }

        let plant_id = data[0]["wfo_taxon_id"].as_str().unwrap();

        // Get fungi for this plant
        let response = app
            .oneshot(
                Request::builder()
                    .uri(&format!("/api/plants/{}/fungi", plant_id))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        assert!(body["rows"].is_number());
        assert!(body["data"].is_array());
    }

    #[tokio::test]
    async fn test_fungi_by_guild_mycorrhizal() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Get any plant
        let search_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=10")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let search_body: Value = json_response(search_response).await;
        let data = search_body["data"].as_array().unwrap();

        if data.is_empty() {
            return;
        }

        let plant_id = data[0]["wfo_taxon_id"].as_str().unwrap();

        // Filter by guild category
        let response = app
            .oneshot(
                Request::builder()
                    .uri(&format!("/api/plants/{}/fungi?guild_category=mycorrhizal", plant_id))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        let fungi = body["data"].as_array().unwrap();

        // Verify all returned fungi are mycorrhizal
        for fungus in fungi {
            assert_eq!(fungus["guild_category"].as_str().unwrap(), "mycorrhizal",
                "Filtered fungi should only be mycorrhizal");
        }
    }

    // =========================================================================
    // Section 11: Guild Scoring - Basic
    // =========================================================================

    #[tokio::test]
    async fn test_score_guild() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Get some plant IDs
        let search_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=7")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let search_body: Value = json_response(search_response).await;
        let data = search_body["data"].as_array().unwrap();

        if data.len() < 3 {
            eprintln!("Not enough plants for guild scoring test");
            return;
        }

        let plant_ids: Vec<String> = data
            .iter()
            .take(5)
            .map(|p| p["wfo_taxon_id"].as_str().unwrap().to_string())
            .collect();

        // Score the guild
        let score_request = serde_json::json!({
            "plant_ids": plant_ids
        });

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/guilds/score")
                    .header("content-type", "application/json")
                    .body(Body::from(score_request.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;

        // Verify response structure
        assert_eq!(body["guild_size"], plant_ids.len());
        assert!(body["overall_score"].is_number());

        let metrics = &body["metrics"];
        assert!(metrics["m1_phylogenetic_diversity"].is_number());
        assert!(metrics["m2_csr_balance"].is_number());
        assert!(metrics["m3_eive_compatibility"].is_number());
        assert!(metrics["m4_pollinator_pest_balance"].is_number());
        assert!(metrics["m5_pest_biocontrol"].is_number());
        assert!(metrics["m6_growth_form_diversity"].is_number());
        assert!(metrics["m7_nutrient_cycling"].is_number());
    }

    // =========================================================================
    // Section 12: Guild Scoring - Accuracy Validation
    // =========================================================================

    #[tokio::test]
    async fn test_guild_score_bounds() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Get some plant IDs
        let search_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=5")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let search_body: Value = json_response(search_response).await;
        let data = search_body["data"].as_array().unwrap();

        if data.len() < 3 {
            return;
        }

        let plant_ids: Vec<String> = data
            .iter()
            .take(3)
            .map(|p| p["wfo_taxon_id"].as_str().unwrap().to_string())
            .collect();

        let score_request = serde_json::json!({ "plant_ids": plant_ids });

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/guilds/score")
                    .header("content-type", "application/json")
                    .body(Body::from(score_request.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;

        // Verify overall score is 0-100
        let overall = body["overall_score"].as_f64().unwrap();
        assert!(overall >= 0.0 && overall <= 100.0,
            "Overall score should be 0-100, got {}", overall);

        // Verify all 7 metrics are 0-100
        let metrics = &body["metrics"];
        let metric_names = [
            "m1_phylogenetic_diversity",
            "m2_csr_balance",
            "m3_eive_compatibility",
            "m4_pollinator_pest_balance",
            "m5_pest_biocontrol",
            "m6_growth_form_diversity",
            "m7_nutrient_cycling"
        ];

        for name in &metric_names {
            let score = metrics[name].as_f64().unwrap();
            assert!(score >= 0.0 && score <= 100.0,
                "{} should be 0-100, got {}", name, score);
        }
    }

    #[tokio::test]
    async fn test_guild_score_determinism() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Get some plant IDs
        let search_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=5")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let search_body: Value = json_response(search_response).await;
        let data = search_body["data"].as_array().unwrap();

        if data.len() < 3 {
            return;
        }

        let plant_ids: Vec<String> = data
            .iter()
            .take(3)
            .map(|p| p["wfo_taxon_id"].as_str().unwrap().to_string())
            .collect();

        let score_request = serde_json::json!({ "plant_ids": plant_ids.clone() });

        // First request
        let response1 = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/guilds/score")
                    .header("content-type", "application/json")
                    .body(Body::from(score_request.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        let body1: Value = json_response(response1).await;

        // Second request with same inputs
        let response2 = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/guilds/score")
                    .header("content-type", "application/json")
                    .body(Body::from(score_request.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        let body2: Value = json_response(response2).await;

        // Scores should be identical
        assert_eq!(body1["overall_score"], body2["overall_score"],
            "Same inputs should produce identical scores");
        assert_eq!(body1["metrics"], body2["metrics"],
            "Same inputs should produce identical metric values");
    }

    #[tokio::test]
    async fn test_guild_minimum_size() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Get 3 plant IDs (minimum guild size)
        let search_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=3")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let search_body: Value = json_response(search_response).await;
        let data = search_body["data"].as_array().unwrap();

        if data.len() < 3 {
            return;
        }

        let plant_ids: Vec<String> = data
            .iter()
            .take(3)
            .map(|p| p["wfo_taxon_id"].as_str().unwrap().to_string())
            .collect();

        let score_request = serde_json::json!({ "plant_ids": plant_ids });

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/guilds/score")
                    .header("content-type", "application/json")
                    .body(Body::from(score_request.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        // Minimum guild (3 plants) should still score successfully
        assert_eq!(response.status(), StatusCode::OK);

        let body: Value = json_response(response).await;
        assert_eq!(body["guild_size"], 3);
    }

    #[tokio::test]
    async fn test_guild_empty_returns_error() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Empty guild
        let empty_ids: Vec<String> = vec![];
        let score_request = serde_json::json!({ "plant_ids": empty_ids });

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/guilds/score")
                    .header("content-type", "application/json")
                    .body(Body::from(score_request.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        // Empty guild should return error
        assert!(
            response.status() == StatusCode::BAD_REQUEST ||
            response.status() == StatusCode::UNPROCESSABLE_ENTITY,
            "Empty guild should return error, got {:?}",
            response.status()
        );
    }

    #[tokio::test]
    async fn test_guild_invalid_plant_id() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Mix valid and invalid IDs
        let score_request = serde_json::json!({
            "plant_ids": ["invalid-id-1", "invalid-id-2", "invalid-id-3"]
        });

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/guilds/score")
                    .header("content-type", "application/json")
                    .body(Body::from(score_request.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        // Should return error or partial result
        let status = response.status();
        assert!(
            status == StatusCode::NOT_FOUND ||
            status == StatusCode::BAD_REQUEST ||
            status == StatusCode::OK,  // May succeed with 0 valid plants
            "Invalid plant IDs should be handled gracefully, got {:?}",
            status
        );
    }

    // =========================================================================
    // Section 13: Caching
    // =========================================================================

    #[tokio::test]
    async fn test_caching_works() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Make first request
        let response1 = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?min_light=8.0&limit=5")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let body1: Value = json_response(response1).await;

        // Make identical second request (should hit cache)
        let response2 = app
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?min_light=8.0&limit=5")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let body2: Value = json_response(response2).await;

        // Results should be identical
        assert_eq!(body1, body2);
    }

    // =========================================================================
    // Section 14: Performance Timing Tests
    // =========================================================================

    #[tokio::test]
    async fn test_performance_search_latency() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Warm up
        let _ = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?min_light=7&limit=10")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await;

        // Measure 10 search requests
        let mut durations = Vec::new();
        for _ in 0..10 {
            let start = std::time::Instant::now();
            let response = app
                .clone()
                .oneshot(
                    Request::builder()
                        .uri("/api/plants/search?min_light=7&limit=10")
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            let duration = start.elapsed();
            durations.push(duration);

            assert_eq!(response.status(), StatusCode::OK);
        }

        let avg_ms = durations.iter().map(|d| d.as_millis()).sum::<u128>() / durations.len() as u128;
        let max_ms = durations.iter().map(|d| d.as_millis()).max().unwrap();

        println!("Search latency: avg={}ms, max={}ms", avg_ms, max_ms);

        // Target: <50ms average (relaxed for test environment, production target is <10ms)
        assert!(avg_ms < 50, "Search avg latency should be <50ms, got {}ms", avg_ms);
    }

    #[tokio::test]
    async fn test_performance_single_plant_latency() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Get a plant ID first
        let search_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=1")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let search_body: Value = json_response(search_response).await;
        let data = search_body["data"].as_array().unwrap();
        if data.is_empty() {
            return;
        }
        let plant_id = data[0]["wfo_taxon_id"].as_str().unwrap();

        // Measure 10 single plant lookups
        let mut durations = Vec::new();
        for _ in 0..10 {
            let start = std::time::Instant::now();
            let response = app
                .clone()
                .oneshot(
                    Request::builder()
                        .uri(&format!("/api/plants/{}", plant_id))
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            let duration = start.elapsed();
            durations.push(duration);

            assert_eq!(response.status(), StatusCode::OK);
        }

        let avg_ms = durations.iter().map(|d| d.as_millis()).sum::<u128>() / durations.len() as u128;
        let max_ms = durations.iter().map(|d| d.as_millis()).max().unwrap();

        println!("Single plant latency: avg={}ms, max={}ms", avg_ms, max_ms);

        // Target: <20ms average
        assert!(avg_ms < 20, "Single plant avg latency should be <20ms, got {}ms", avg_ms);
    }

    #[tokio::test]
    async fn test_performance_guild_scoring_latency() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Get plant IDs
        let search_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=7")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let search_body: Value = json_response(search_response).await;
        let data = search_body["data"].as_array().unwrap();
        if data.len() < 5 {
            return;
        }

        let plant_ids: Vec<String> = data
            .iter()
            .take(5)
            .map(|p| p["wfo_taxon_id"].as_str().unwrap().to_string())
            .collect();

        let score_request = serde_json::json!({ "plant_ids": plant_ids });

        // Warm up
        let _ = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/guilds/score")
                    .header("content-type", "application/json")
                    .body(Body::from(score_request.to_string()))
                    .unwrap(),
            )
            .await;

        // Measure 5 guild scoring requests
        let mut durations = Vec::new();
        for _ in 0..5 {
            let start = std::time::Instant::now();
            let response = app
                .clone()
                .oneshot(
                    Request::builder()
                        .method("POST")
                        .uri("/api/guilds/score")
                        .header("content-type", "application/json")
                        .body(Body::from(score_request.to_string()))
                        .unwrap(),
                )
                .await
                .unwrap();
            let duration = start.elapsed();
            durations.push(duration);

            assert_eq!(response.status(), StatusCode::OK);
        }

        let avg_ms = durations.iter().map(|d| d.as_millis()).sum::<u128>() / durations.len() as u128;
        let max_ms = durations.iter().map(|d| d.as_millis()).max().unwrap();

        println!("Guild scoring latency: avg={}ms, max={}ms", avg_ms, max_ms);

        // Target: <500ms average
        assert!(avg_ms < 500, "Guild scoring avg latency should be <500ms, got {}ms", avg_ms);
    }

    #[tokio::test]
    async fn test_performance_similarity_latency() {
        let app = match create_test_app().await {
            Ok(app) => app,
            Err(e) => {
                eprintln!("Skipping test: {}", e);
                return;
            }
        };

        // Get a plant ID
        let search_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/plants/search?limit=1")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        let search_body: Value = json_response(search_response).await;
        let data = search_body["data"].as_array().unwrap();
        if data.is_empty() {
            return;
        }
        let plant_id = data[0]["wfo_taxon_id"].as_str().unwrap();

        let similarity_request = serde_json::json!({
            "plant_id": plant_id,
            "top_k": 10
        });

        // Warm up
        let _ = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/plants/similar")
                    .header("content-type", "application/json")
                    .body(Body::from(similarity_request.to_string()))
                    .unwrap(),
            )
            .await;

        // Measure 5 similarity requests
        let mut durations = Vec::new();
        for _ in 0..5 {
            let start = std::time::Instant::now();
            let response = app
                .clone()
                .oneshot(
                    Request::builder()
                        .method("POST")
                        .uri("/api/plants/similar")
                        .header("content-type", "application/json")
                        .body(Body::from(similarity_request.to_string()))
                        .unwrap(),
                )
                .await
                .unwrap();
            let duration = start.elapsed();
            durations.push(duration);

            assert_eq!(response.status(), StatusCode::OK);
        }

        let avg_ms = durations.iter().map(|d| d.as_millis()).sum::<u128>() / durations.len() as u128;
        let max_ms = durations.iter().map(|d| d.as_millis()).max().unwrap();

        println!("Similarity search latency: avg={}ms, max={}ms", avg_ms, max_ms);

        // Target: <100ms average
        assert!(avg_ms < 100, "Similarity avg latency should be <100ms, got {}ms", avg_ms);
    }
}
