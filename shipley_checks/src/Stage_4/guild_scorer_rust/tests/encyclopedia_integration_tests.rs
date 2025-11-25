//! Encyclopedia Integration Tests
//!
//! Generates full encyclopedia articles for 3 well-known plants as sanity checks.
//! These tests verify the entire pipeline from DataFusion query to markdown generation.

#[cfg(feature = "api")]
mod tests {
    use guild_scorer_rust::encyclopedia::EncyclopediaGenerator;
    use guild_scorer_rust::encyclopedia::sections::s5_biological_interactions::{
        FungalCounts, OrganismCounts,
    };
    use guild_scorer_rust::query_engine::QueryEngine;
    use std::collections::HashMap;

    const DATA_DIR: &str = "/home/olier/ellenberg/shipley_checks/stage4/phase7_output";

    // Test plants representing different growth forms and ecological strategies
    const TEST_PLANTS: &[(&str, &str, &str)] = &[
        ("wfo-0000292858", "Quercus robur", "Large deciduous tree, ectomycorrhizal"),
        ("wfo-0001005999", "Rosa canina", "Shrub with many pollinators"),
        ("wfo-0000213062", "Trifolium repens", "Nitrogen-fixing herbaceous legume"),
    ];

    /// Convert Arrow RecordBatch to HashMap via JSON
    fn batch_to_hashmap(
        batches: &[datafusion::arrow::array::RecordBatch],
    ) -> Option<HashMap<String, serde_json::Value>> {
        if batches.is_empty() || batches[0].num_rows() == 0 {
            return None;
        }

        // Use Arrow's JSON writer
        let mut buf = Vec::new();
        {
            let mut writer = datafusion::arrow::json::ArrayWriter::new(&mut buf);
            for batch in batches {
                writer.write(batch).ok()?;
            }
            writer.finish().ok()?;
        }

        // Parse JSON array and take first row
        let json_data: Vec<serde_json::Value> = serde_json::from_slice(&buf).ok()?;
        json_data
            .into_iter()
            .next()
            .and_then(|v| serde_json::from_value(v).ok())
    }

    /// Parse organism counts from summary query results
    fn parse_organism_counts(
        batches: &[datafusion::arrow::array::RecordBatch],
    ) -> Option<OrganismCounts> {
        if batches.is_empty() {
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

        let mut pollinators = 0;
        let mut visitors = 0;
        let mut herbivores = 0;
        let mut pathogens = 0;
        let mut predators = 0;

        for row in &json_data {
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

    /// Parse fungal counts from summary query results
    fn parse_fungal_counts(
        batches: &[datafusion::arrow::array::RecordBatch],
    ) -> Option<FungalCounts> {
        if batches.is_empty() {
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

        let mut amf = 0;
        let mut emf = 0;
        let mut endophytes = 0;
        let mut mycoparasites = 0;
        let mut entomopathogens = 0;

        for row in &json_data {
            let guild = row.get("guild")?.as_str()?.to_lowercase();
            let count = row.get("count")?.as_u64()? as usize;

            if guild.contains("arbuscular") || guild.contains("amf") {
                amf += count;
            } else if guild.contains("ectomycorrhiz") || guild.contains("emf") {
                emf += count;
            } else if guild.contains("endophyt") {
                endophytes += count;
            } else if guild.contains("mycoparasit") || guild.contains("hyperparasit") {
                mycoparasites += count;
            } else if guild.contains("entomopathogen") || guild.contains("insect_pathogen") {
                entomopathogens += count;
            }
        }

        if amf + emf + endophytes + mycoparasites + entomopathogens > 0 {
            Some(FungalCounts {
                amf,
                emf,
                endophytes,
                mycoparasites,
                entomopathogens,
            })
        } else {
            None
        }
    }

    /// Generate encyclopedia for a single plant and return markdown
    async fn generate_encyclopedia_for_plant(
        engine: &QueryEngine,
        generator: &EncyclopediaGenerator,
        wfo_id: &str,
    ) -> Result<String, String> {
        // Fetch plant data
        let plant_batches = engine
            .get_plant(wfo_id)
            .await
            .map_err(|e| format!("Failed to fetch plant: {}", e))?;

        let plant_data = batch_to_hashmap(&plant_batches)
            .ok_or_else(|| format!("Plant {} not found", wfo_id))?;

        // Fetch organism counts
        let organism_counts = engine
            .get_organism_summary(wfo_id)
            .await
            .ok()
            .and_then(|b| parse_organism_counts(&b));

        // Fetch fungal counts
        let fungal_counts = engine
            .get_fungi_summary(wfo_id)
            .await
            .ok()
            .and_then(|b| parse_fungal_counts(&b));

        // Generate encyclopedia
        generator.generate(wfo_id, &plant_data, organism_counts, fungal_counts)
    }

    // =========================================================================
    // Integration Tests - Generate Full Encyclopedia Articles
    // =========================================================================

    #[tokio::test]
    async fn test_encyclopedia_quercus_robur() {
        let engine = QueryEngine::new(DATA_DIR).await.expect("Failed to init QueryEngine");
        let generator = EncyclopediaGenerator::new();

        let (wfo_id, name, _desc) = TEST_PLANTS[0];
        let markdown = generate_encyclopedia_for_plant(&engine, &generator, wfo_id)
            .await
            .expect("Failed to generate encyclopedia");

        // Print full article for visual inspection
        println!("\n================================================================================");
        println!("ENCYCLOPEDIA: {} ({})", name, wfo_id);
        println!("================================================================================\n");
        println!("{}", markdown);
        println!("\n================================================================================\n");

        // Verify expected sections
        assert!(markdown.contains("Quercus robur"), "Should contain scientific name");
        assert!(markdown.contains("Fagaceae"), "Should contain family");
        assert!(markdown.contains("## Growing Requirements"), "Should have growing section");
        assert!(markdown.contains("## Maintenance"), "Should have maintenance section");
        assert!(markdown.contains("## Ecosystem Services"), "Should have ecosystem section");
        assert!(markdown.contains("## Biological Interactions"), "Should have interactions section");

        // Oak-specific checks
        assert!(
            markdown.contains("EIVE-L") || markdown.contains("Light"),
            "Should have light requirements"
        );
    }

    #[tokio::test]
    async fn test_encyclopedia_rosa_canina() {
        let engine = QueryEngine::new(DATA_DIR).await.expect("Failed to init QueryEngine");
        let generator = EncyclopediaGenerator::new();

        let (wfo_id, name, _desc) = TEST_PLANTS[1];
        let markdown = generate_encyclopedia_for_plant(&engine, &generator, wfo_id)
            .await
            .expect("Failed to generate encyclopedia");

        // Print full article for visual inspection
        println!("\n================================================================================");
        println!("ENCYCLOPEDIA: {} ({})", name, wfo_id);
        println!("================================================================================\n");
        println!("{}", markdown);
        println!("\n================================================================================\n");

        // Verify expected sections
        assert!(markdown.contains("Rosa canina"), "Should contain scientific name");
        assert!(markdown.contains("Rosaceae"), "Should contain family");
        assert!(markdown.contains("## Growing Requirements"), "Should have growing section");
        assert!(markdown.contains("## Maintenance"), "Should have maintenance section");

        // Rose-specific checks - likely has pollinator data
        assert!(
            markdown.contains("Pollinator") || markdown.contains("🐝"),
            "Rose should have pollinator info"
        );
    }

    #[tokio::test]
    async fn test_encyclopedia_trifolium_repens() {
        let engine = QueryEngine::new(DATA_DIR).await.expect("Failed to init QueryEngine");
        let generator = EncyclopediaGenerator::new();

        let (wfo_id, name, _desc) = TEST_PLANTS[2];
        let markdown = generate_encyclopedia_for_plant(&engine, &generator, wfo_id)
            .await
            .expect("Failed to generate encyclopedia");

        // Print full article for visual inspection
        println!("\n================================================================================");
        println!("ENCYCLOPEDIA: {} ({})", name, wfo_id);
        println!("================================================================================\n");
        println!("{}", markdown);
        println!("\n================================================================================\n");

        // Verify expected sections
        assert!(markdown.contains("Trifolium repens"), "Should contain scientific name");
        assert!(markdown.contains("Leguminosae") || markdown.contains("Fabaceae"), "Should contain family");
        assert!(markdown.contains("## Growing Requirements"), "Should have growing section");
        assert!(markdown.contains("## Ecosystem Services"), "Should have ecosystem section");

        // Clover-specific checks - should have fertility info (mentions nitrogen in EIVE-N)
        assert!(
            markdown.contains("EIVE-N") || markdown.contains("Fertility"),
            "Clover should have fertility/nitrogen requirements info"
        );
    }

    /// Test that generates all 3 encyclopedias and prints them sequentially
    #[tokio::test]
    async fn test_encyclopedia_all_three_plants() {
        let engine = QueryEngine::new(DATA_DIR).await.expect("Failed to init QueryEngine");
        let generator = EncyclopediaGenerator::new();

        println!("\n");
        println!("╔══════════════════════════════════════════════════════════════════════════════╗");
        println!("║           ENCYCLOPEDIA INTEGRATION TEST - 3 WELL-KNOWN PLANTS               ║");
        println!("╚══════════════════════════════════════════════════════════════════════════════╝");

        for (wfo_id, name, desc) in TEST_PLANTS {
            println!("\n");
            println!("┌──────────────────────────────────────────────────────────────────────────────┐");
            println!("│ {} - {}", name, desc);
            println!("│ WFO ID: {}", wfo_id);
            println!("└──────────────────────────────────────────────────────────────────────────────┘");
            println!();

            match generate_encyclopedia_for_plant(&engine, &generator, wfo_id).await {
                Ok(markdown) => {
                    println!("{}", markdown);

                    // Basic sanity checks
                    assert!(!markdown.is_empty(), "Encyclopedia should not be empty");
                    assert!(markdown.contains(name), "Should contain plant name");
                    assert!(markdown.contains("##"), "Should have markdown headers");
                }
                Err(e) => {
                    panic!("Failed to generate encyclopedia for {}: {}", name, e);
                }
            }

            println!("\n------------------------------------------------------------------------------");
        }

        println!("\n✓ All 3 encyclopedia articles generated successfully\n");
    }
}
