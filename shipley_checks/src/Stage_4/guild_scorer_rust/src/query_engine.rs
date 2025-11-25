// Phase 8.2: DataFusion Query Engine Module
//
// Purpose: Async SQL query engine for Phase 7 parquet files
// Performance: <10ms for plant searches, <20ms for similarity queries

#[cfg(feature = "api")]
use datafusion::prelude::*;
#[cfg(feature = "api")]
use datafusion::error::DataFusionError;
#[cfg(feature = "api")]
use datafusion::arrow::array::RecordBatch;
#[cfg(feature = "api")]
use std::sync::Arc;
#[cfg(feature = "api")]
use std::path::Path;

#[cfg(feature = "api")]
pub type DFResult<T> = Result<T, DataFusionError>;

#[cfg(feature = "api")]
#[derive(Clone)]
pub struct QueryEngine {
    ctx: Arc<SessionContext>,
}

#[cfg(feature = "api")]
impl QueryEngine {
    /// Initialize query engine and register Phase 7 parquets
    pub async fn new(data_dir: &str) -> DFResult<Self> {
        let ctx = SessionContext::new();

        // Register plants table
        let plants_path = format!("{}/plants_searchable_11711.parquet", data_dir);
        if !Path::new(&plants_path).exists() {
            return Err(DataFusionError::Plan(format!(
                "Plants parquet not found: {}",
                plants_path
            )));
        }
        ctx.register_parquet(
            "plants",
            &plants_path,
            ParquetReadOptions::default(),
        )
        .await?;

        // Register organisms table
        let organisms_path = format!("{}/organisms_searchable.parquet", data_dir);
        if !Path::new(&organisms_path).exists() {
            return Err(DataFusionError::Plan(format!(
                "Organisms parquet not found: {}",
                organisms_path
            )));
        }
        ctx.register_parquet(
            "organisms",
            &organisms_path,
            ParquetReadOptions::default(),
        )
        .await?;

        // Register fungi table
        let fungi_path = format!("{}/fungi_searchable.parquet", data_dir);
        if !Path::new(&fungi_path).exists() {
            return Err(DataFusionError::Plan(format!(
                "Fungi parquet not found: {}",
                fungi_path
            )));
        }
        ctx.register_parquet(
            "fungi",
            &fungi_path,
            ParquetReadOptions::default(),
        )
        .await?;

        Ok(Self {
            ctx: Arc::new(ctx),
        })
    }

    /// Raw SQL execution (for advanced queries)
    pub async fn query(&self, sql: &str) -> DFResult<Vec<RecordBatch>> {
        let df = self.ctx.sql(sql).await?;
        df.collect().await
    }

    /// Search plants by filters
    pub async fn search_plants(&self, filters: &PlantFilters) -> DFResult<Vec<RecordBatch>> {
        let mut conditions = Vec::new();

        // Common name search (case-insensitive substring)
        if let Some(ref name) = filters.common_name {
            let escaped = name.replace("'", "''");
            conditions.push(format!(
                "LOWER(vernacular_names) LIKE LOWER('%{}%')",
                escaped
            ));
        }

        // Latin name search (case-insensitive substring)
        if let Some(ref latin) = filters.latin_name {
            let escaped = latin.replace("'", "''");
            conditions.push(format!(
                "LOWER(wfo_taxon_name) LIKE LOWER('%{}%')",
                escaped
            ));
        }

        // EIVE filters (quoted for case-sensitivity)
        if let Some(min) = filters.min_light {
            conditions.push(format!("\"EIVE_L\" >= {}", min));
        }
        if let Some(max) = filters.max_light {
            conditions.push(format!("\"EIVE_L\" <= {}", max));
        }
        if let Some(min) = filters.min_moisture {
            conditions.push(format!("\"EIVE_M\" >= {}", min));
        }
        if let Some(max) = filters.max_moisture {
            conditions.push(format!("\"EIVE_M\" <= {}", max));
        }
        if let Some(min) = filters.min_temperature {
            conditions.push(format!("\"EIVE_T\" >= {}", min));
        }
        if let Some(max) = filters.max_temperature {
            conditions.push(format!("\"EIVE_T\" <= {}", max));
        }
        if let Some(min) = filters.min_nitrogen {
            conditions.push(format!("\"EIVE_N\" >= {}", min));
        }
        if let Some(max) = filters.max_nitrogen {
            conditions.push(format!("\"EIVE_N\" <= {}", max));
        }
        if let Some(min) = filters.min_ph {
            conditions.push(format!("\"EIVE_R\" >= {}", min));
        }
        if let Some(max) = filters.max_ph {
            conditions.push(format!("\"EIVE_R\" <= {}", max));
        }

        // CSR filters
        if let Some(min) = filters.min_c {
            conditions.push(format!("C_norm >= {}", min));
        }
        if let Some(max) = filters.max_c {
            conditions.push(format!("C_norm <= {}", max));
        }
        if let Some(min) = filters.min_s {
            conditions.push(format!("S_norm >= {}", min));
        }
        if let Some(max) = filters.max_s {
            conditions.push(format!("S_norm <= {}", max));
        }
        if let Some(min) = filters.min_r {
            conditions.push(format!("R_norm >= {}", min));
        }
        if let Some(max) = filters.max_r {
            conditions.push(format!("R_norm <= {}", max));
        }

        // Maintenance level filter
        if let Some(ref level) = filters.maintenance_level {
            let escaped = level.replace("'", "''");
            conditions.push(format!("maintenance_level = '{}'", escaped));
        }

        // Boolean filters
        if let Some(drought_tolerant) = filters.drought_tolerant {
            conditions.push(format!("drought_tolerant = {}", drought_tolerant));
        }
        if let Some(fast_growing) = filters.fast_growing {
            conditions.push(format!("fast_growing = {}", fast_growing));
        }

        // Climate tier filter
        if let Some(ref tier) = filters.climate_tier {
            let escaped = tier.replace("'", "''");
            conditions.push(format!("{} = true", escaped));
        }

        // Build WHERE clause
        let where_clause = if conditions.is_empty() {
            String::new()
        } else {
            format!("WHERE {}", conditions.join(" AND "))
        };

        // Build SQL query
        let limit = filters.limit.unwrap_or(100);
        let sql = format!(
            "SELECT * FROM plants {} LIMIT {}",
            where_clause, limit
        );

        self.query(&sql).await
    }

    /// Get single plant by ID
    pub async fn get_plant(&self, plant_id: &str) -> DFResult<Vec<RecordBatch>> {
        let escaped_id = plant_id.replace("'", "''");
        let sql = format!(
            "SELECT * FROM plants WHERE wfo_taxon_id = '{}'",
            escaped_id
        );
        self.query(&sql).await
    }

    /// Find similar plants based on EIVE Euclidean distance
    pub async fn find_similar(
        &self,
        plant_id: &str,
        top_k: usize,
    ) -> DFResult<Vec<RecordBatch>> {
        let escaped_id = plant_id.replace("'", "''");

        // SQL query: compute Euclidean distance in 6D EIVE space
        let sql = format!(
            r#"
            WITH target AS (
                SELECT
                    EIVE_L, EIVE_M, EIVE_T, EIVE_K, EIVE_N, EIVE_R
                FROM plants
                WHERE wfo_taxon_id = '{}'
            )
            SELECT
                p.*,
                SQRT(
                    POWER(p.EIVE_L - t.EIVE_L, 2) +
                    POWER(p.EIVE_M - t.EIVE_M, 2) +
                    POWER(p.EIVE_T - t.EIVE_T, 2) +
                    POWER(p.EIVE_K - t.EIVE_K, 2) +
                    POWER(p.EIVE_N - t.EIVE_N, 2) +
                    POWER(p.EIVE_R - t.EIVE_R, 2)
                ) AS eive_distance
            FROM plants p, target t
            WHERE p.wfo_taxon_id != '{}'
            ORDER BY eive_distance ASC
            LIMIT {}
            "#,
            escaped_id, escaped_id, top_k
        );

        self.query(&sql).await
    }

    /// Get organisms for a plant
    pub async fn get_organisms(
        &self,
        plant_id: &str,
        interaction_type: Option<&str>,
    ) -> DFResult<Vec<RecordBatch>> {
        let escaped_id = plant_id.replace("'", "''");

        let type_filter = if let Some(t) = interaction_type {
            let escaped_type = t.replace("'", "''");
            format!("AND interaction_type = '{}'", escaped_type)
        } else {
            String::new()
        };

        let sql = format!(
            "SELECT * FROM organisms WHERE plant_wfo_id = '{}' {} ORDER BY interaction_type",
            escaped_id, type_filter
        );

        self.query(&sql).await
    }

    /// Get fungi for a plant
    pub async fn get_fungi(
        &self,
        plant_id: &str,
        guild_category: Option<&str>,
    ) -> DFResult<Vec<RecordBatch>> {
        let escaped_id = plant_id.replace("'", "''");

        let category_filter = if let Some(cat) = guild_category {
            let escaped_cat = cat.replace("'", "''");
            format!("AND guild_category = '{}'", escaped_cat)
        } else {
            String::new()
        };

        let sql = format!(
            "SELECT * FROM fungi WHERE plant_wfo_id = '{}' {} ORDER BY guild",
            escaped_id, category_filter
        );

        self.query(&sql).await
    }

    /// Get organism interaction counts aggregated by type
    pub async fn get_organism_summary(&self, plant_id: &str) -> DFResult<Vec<RecordBatch>> {
        let escaped_id = plant_id.replace("'", "''");

        let sql = format!(
            r#"
            SELECT
                interaction_type,
                interaction_category,
                COUNT(*) as count
            FROM organisms
            WHERE plant_wfo_id = '{}'
            GROUP BY interaction_type, interaction_category
            ORDER BY interaction_type
            "#,
            escaped_id
        );

        self.query(&sql).await
    }

    /// Get fungal guild counts aggregated by category
    pub async fn get_fungi_summary(&self, plant_id: &str) -> DFResult<Vec<RecordBatch>> {
        let escaped_id = plant_id.replace("'", "''");

        let sql = format!(
            r#"
            SELECT
                guild,
                guild_category,
                COUNT(*) as count
            FROM fungi
            WHERE plant_wfo_id = '{}'
            GROUP BY guild, guild_category
            ORDER BY guild
            "#,
            escaped_id
        );

        self.query(&sql).await
    }
}

/// Plant search filters
#[cfg(feature = "api")]
#[derive(Debug, Clone, Default, serde::Deserialize)]
pub struct PlantFilters {
    pub common_name: Option<String>,
    pub latin_name: Option<String>,

    // EIVE filters (0-10 scale)
    pub min_light: Option<f64>,
    pub max_light: Option<f64>,
    pub min_moisture: Option<f64>,
    pub max_moisture: Option<f64>,
    pub min_temperature: Option<f64>,
    pub max_temperature: Option<f64>,
    pub min_nitrogen: Option<f64>,
    pub max_nitrogen: Option<f64>,
    pub min_ph: Option<f64>,
    pub max_ph: Option<f64>,

    // CSR filters (0-1 scale)
    pub min_c: Option<f64>,
    pub max_c: Option<f64>,
    pub min_s: Option<f64>,
    pub max_s: Option<f64>,
    pub min_r: Option<f64>,
    pub max_r: Option<f64>,

    // Categorical filters
    pub maintenance_level: Option<String>,  // "low", "medium", "high"
    pub drought_tolerant: Option<bool>,
    pub fast_growing: Option<bool>,
    pub climate_tier: Option<String>,  // "tier_1_tropical", etc.

    // Pagination
    pub limit: Option<usize>,
}

#[cfg(test)]
#[cfg(feature = "api")]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_query_engine_initialization() {
        // This test requires Phase 7 parquets to exist
        let data_dir = "/home/olier/ellenberg/shipley_checks/stage4/phase7_output";

        match QueryEngine::new(data_dir).await {
            Ok(engine) => {
                // Verify we can execute a simple query
                let result = engine.query("SELECT COUNT(*) FROM plants").await;
                assert!(result.is_ok(), "Failed to query plants table");
            }
            Err(e) => {
                // If files don't exist, skip test
                println!("Skipping test (Phase 7 files not found): {}", e);
            }
        }
    }

    #[tokio::test]
    async fn test_search_plants() {
        let data_dir = "/home/olier/ellenberg/shipley_checks/stage4/phase7_output";

        if let Ok(engine) = QueryEngine::new(data_dir).await {
            let filters = PlantFilters {
                min_light: Some(7.0),
                max_moisture: Some(5.0),
                limit: Some(10),
                ..Default::default()
            };

            let result = engine.search_plants(&filters).await;
            assert!(result.is_ok(), "Search query failed: {:?}", result.err());
        }
    }
}
