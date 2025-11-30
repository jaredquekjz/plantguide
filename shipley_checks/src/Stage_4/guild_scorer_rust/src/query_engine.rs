// Phase 8.2: DataFusion Query Engine Module
//
// Purpose: Async SQL query engine for plant ecological data
// Data sources:
//   - Plants: master dataset (phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet, 861 cols)
//   - Organisms: phase0 wide format (for counts) + phase7 flat format (for SQL search)
//   - Fungi: phase0 wide format (for counts) + phase7 flat format (for SQL search)
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

/// Helper enum to handle both StringArray and StringViewArray
#[cfg(feature = "api")]
enum StringColumn<'a> {
    Array(&'a arrow::array::StringArray),
    View(&'a arrow::array::StringViewArray),
}

#[cfg(feature = "api")]
impl<'a> StringColumn<'a> {
    fn value(&self, i: usize) -> &str {
        match self {
            StringColumn::Array(a) => a.value(i),
            StringColumn::View(v) => v.value(i),
        }
    }
}

#[cfg(feature = "api")]
#[derive(Clone)]
pub struct QueryEngine {
    ctx: Arc<SessionContext>,
}

#[cfg(feature = "api")]
impl QueryEngine {
    /// Initialize query engine with master dataset and flattened interaction tables
    ///
    /// Expected directory structure from data_dir:
    ///   - phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet (plants master, 861 cols)
    ///   - phase0_output/organism_profiles_11711.parquet (organisms wide)
    ///   - phase0_output/fungal_guilds_hybrid_11711.parquet (fungi wide)
    ///   - phase7_output/organisms_flat.parquet (organisms flat)
    ///   - phase7_output/fungi_flat.parquet (fungi flat)
    pub async fn new(data_dir: &str) -> DFResult<Self> {
        let ctx = SessionContext::new();

        // Register master plants dataset (Phase 4 output with Köppen + vernaculars)
        let plants_path = format!("{}/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet", data_dir);
        if !Path::new(&plants_path).exists() {
            return Err(DataFusionError::External(
                format!("Master dataset not found: {}\nRun Phase 4 (merge_taxonomy_koppen.py) first.", plants_path).into()
            ));
        }
        ctx.register_parquet(
            "plants",
            &plants_path,
            ParquetReadOptions::default(),
        )
        .await?;

        // Register organisms wide (for counts)
        let organisms_wide_path = format!(
            "{}/phase0_output/organism_profiles_11711.parquet",
            data_dir
        );
        if !Path::new(&organisms_wide_path).exists() {
            return Err(DataFusionError::Plan(format!(
                "Organisms wide parquet not found: {}",
                organisms_wide_path
            )));
        }
        ctx.register_parquet(
            "organisms_wide",
            &organisms_wide_path,
            ParquetReadOptions::default(),
        )
        .await?;

        // Register organisms flat (for SQL search)
        let organisms_flat_path = format!(
            "{}/phase7_output/organisms_flat.parquet",
            data_dir
        );
        if !Path::new(&organisms_flat_path).exists() {
            return Err(DataFusionError::Plan(format!(
                "Organisms flat parquet not found: {}",
                organisms_flat_path
            )));
        }
        ctx.register_parquet(
            "organisms",
            &organisms_flat_path,
            ParquetReadOptions::default(),
        )
        .await?;

        // Register fungi wide (for counts)
        let fungi_wide_path = format!(
            "{}/phase0_output/fungal_guilds_hybrid_11711.parquet",
            data_dir
        );
        if !Path::new(&fungi_wide_path).exists() {
            return Err(DataFusionError::Plan(format!(
                "Fungi wide parquet not found: {}",
                fungi_wide_path
            )));
        }
        ctx.register_parquet(
            "fungi_wide",
            &fungi_wide_path,
            ParquetReadOptions::default(),
        )
        .await?;

        // Register fungi flat (for SQL search)
        let fungi_flat_path = format!(
            "{}/phase7_output/fungi_flat.parquet",
            data_dir
        );
        if !Path::new(&fungi_flat_path).exists() {
            return Err(DataFusionError::Plan(format!(
                "Fungi flat parquet not found: {}",
                fungi_flat_path
            )));
        }
        ctx.register_parquet(
            "fungi",
            &fungi_flat_path,
            ParquetReadOptions::default(),
        )
        .await?;

        // Register predators master list (Phase 7 output)
        let predators_master_path = format!(
            "{}/phase7_output/predators_master.parquet",
            data_dir
        );
        if Path::new(&predators_master_path).exists() {
            ctx.register_parquet(
                "predators_master",
                &predators_master_path,
                ParquetReadOptions::default(),
            )
            .await?;
        }

        // Register pathogens ranked (Phase 7 output with observation counts)
        let pathogens_ranked_path = format!(
            "{}/phase7_output/pathogens_ranked.parquet",
            data_dir
        );
        if Path::new(&pathogens_ranked_path).exists() {
            ctx.register_parquet(
                "pathogens_ranked",
                &pathogens_ranked_path,
                ParquetReadOptions::default(),
            )
            .await?;
        }

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

        // EIVE filters (using master dataset column names with quotes for hyphens)
        if let Some(min) = filters.min_light {
            conditions.push(format!("\"EIVEres-L_complete\" >= {}", min));
        }
        if let Some(max) = filters.max_light {
            conditions.push(format!("\"EIVEres-L_complete\" <= {}", max));
        }
        if let Some(min) = filters.min_moisture {
            conditions.push(format!("\"EIVEres-M_complete\" >= {}", min));
        }
        if let Some(max) = filters.max_moisture {
            conditions.push(format!("\"EIVEres-M_complete\" <= {}", max));
        }
        if let Some(min) = filters.min_temperature {
            conditions.push(format!("\"EIVEres-T_complete\" >= {}", min));
        }
        if let Some(max) = filters.max_temperature {
            conditions.push(format!("\"EIVEres-T_complete\" <= {}", max));
        }
        if let Some(min) = filters.min_nitrogen {
            conditions.push(format!("\"EIVEres-N_complete\" >= {}", min));
        }
        if let Some(max) = filters.max_nitrogen {
            conditions.push(format!("\"EIVEres-N_complete\" <= {}", max));
        }
        if let Some(min) = filters.min_ph {
            conditions.push(format!("\"EIVEres-R_complete\" >= {}", min));
        }
        if let Some(max) = filters.max_ph {
            conditions.push(format!("\"EIVEres-R_complete\" <= {}", max));
        }

        // CSR filters (master uses 0-100 scale, convert filter from 0-1)
        if let Some(min) = filters.min_c {
            conditions.push(format!("C >= {}", min * 100.0));
        }
        if let Some(max) = filters.max_c {
            conditions.push(format!("C <= {}", max * 100.0));
        }
        if let Some(min) = filters.min_s {
            conditions.push(format!("S >= {}", min * 100.0));
        }
        if let Some(max) = filters.max_s {
            conditions.push(format!("S <= {}", max * 100.0));
        }
        if let Some(min) = filters.min_r {
            conditions.push(format!("R >= {}", min * 100.0));
        }
        if let Some(max) = filters.max_r {
            conditions.push(format!("R <= {}", max * 100.0));
        }

        // Maintenance level filter (computed from CSR: S>50=low, C>50=high, else medium)
        if let Some(ref level) = filters.maintenance_level {
            match level.as_str() {
                "low" => conditions.push("S > 50".to_string()),
                "high" => conditions.push("C > 50".to_string()),
                "medium" => conditions.push("(S <= 50 AND C <= 50)".to_string()),
                _ => {}
            }
        }

        // Boolean filters (computed inline from EIVE/CSR)
        if let Some(drought_tolerant) = filters.drought_tolerant {
            if drought_tolerant {
                conditions.push("S > 60".to_string());
            } else {
                conditions.push("S <= 60".to_string());
            }
        }
        if let Some(fast_growing) = filters.fast_growing {
            if fast_growing {
                conditions.push("R > 60".to_string());
            } else {
                conditions.push("R <= 60".to_string());
            }
        }

        // Climate tier filter (skip if not applicable to master)
        if let Some(ref _tier) = filters.climate_tier {
            // Climate tier columns may not be in master - skip for now
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

    /// Simple text search across plant names
    ///
    /// Searches scientific name, vernacular names, family, and genus
    /// Returns structured results suitable for web display
    pub async fn search_plants_text(&self, query: &str, limit: usize) -> DFResult<Vec<PlantSearchResultData>> {
        let escaped = query.replace("'", "''").to_lowercase();

        // Search across multiple fields with OR
        let sql = format!(
            r#"SELECT
                wfo_taxon_id,
                wfo_scientific_name as scientific_name,
                family,
                vernacular_name_en,
                try_growth_form
            FROM plants
            WHERE LOWER(wfo_scientific_name) LIKE '%{escaped}%'
               OR LOWER(vernacular_name_en) LIKE '%{escaped}%'
               OR LOWER(family) LIKE '%{escaped}%'
               OR LOWER(genus) LIKE '%{escaped}%'
            ORDER BY
                CASE
                    WHEN LOWER(wfo_scientific_name) LIKE '{escaped}%' THEN 1
                    WHEN LOWER(vernacular_name_en) LIKE '{escaped}%' THEN 2
                    ELSE 3
                END,
                wfo_scientific_name
            LIMIT {limit}"#,
            escaped = escaped,
            limit = limit
        );

        let batches = self.query(&sql).await?;

        let mut results = Vec::new();
        tracing::debug!("Search returned {} batches", batches.len());
        for batch in &batches {
            tracing::debug!("Batch has {} rows, {} columns", batch.num_rows(), batch.num_columns());

            // Debug: Print column types
            if let Some(col) = batch.column_by_name("wfo_taxon_id") {
                tracing::debug!("wfo_taxon_id type: {:?}", col.data_type());
            }

            // Try StringViewArray first (DataFusion 43+), fallback to StringArray
            let wfo_col = batch.column_by_name("wfo_taxon_id")
                .and_then(|c| c.as_any().downcast_ref::<arrow::array::StringViewArray>()
                    .map(|a| StringColumn::View(a))
                    .or_else(|| c.as_any().downcast_ref::<arrow::array::StringArray>()
                        .map(|a| StringColumn::Array(a))));
            let name_col = batch.column_by_name("scientific_name")
                .and_then(|c| c.as_any().downcast_ref::<arrow::array::StringViewArray>()
                    .map(|a| StringColumn::View(a))
                    .or_else(|| c.as_any().downcast_ref::<arrow::array::StringArray>()
                        .map(|a| StringColumn::Array(a))));
            let family_col = batch.column_by_name("family")
                .and_then(|c| c.as_any().downcast_ref::<arrow::array::StringViewArray>()
                    .map(|a| StringColumn::View(a))
                    .or_else(|| c.as_any().downcast_ref::<arrow::array::StringArray>()
                        .map(|a| StringColumn::Array(a))));
            let vernacular_col = batch.column_by_name("vernacular_name_en")
                .and_then(|c| c.as_any().downcast_ref::<arrow::array::StringViewArray>()
                    .map(|a| StringColumn::View(a))
                    .or_else(|| c.as_any().downcast_ref::<arrow::array::StringArray>()
                        .map(|a| StringColumn::Array(a))));
            let growth_col = batch.column_by_name("try_growth_form")
                .and_then(|c| c.as_any().downcast_ref::<arrow::array::StringViewArray>()
                    .map(|a| StringColumn::View(a))
                    .or_else(|| c.as_any().downcast_ref::<arrow::array::StringArray>()
                        .map(|a| StringColumn::Array(a))));

            tracing::debug!("wfo_col: {:?}, name_col: {:?}, family_col: {:?}",
                wfo_col.is_some(), name_col.is_some(), family_col.is_some());

            if let (Some(wfo), Some(name), Some(family)) = (wfo_col, name_col, family_col) {
                for i in 0..batch.num_rows() {
                    let vernacular_en = vernacular_col.as_ref().and_then(|c| {
                        let v = c.value(i);
                        if v.is_empty() { None } else { Some(v.to_string()) }
                    });
                    let growth_form = growth_col.as_ref().and_then(|c| {
                        let v = c.value(i);
                        if v.is_empty() { None } else { Some(v.to_string()) }
                    });
                    results.push(PlantSearchResultData {
                        wfo_taxon_id: wfo.value(i).to_string(),
                        scientific_name: name.value(i).to_string(),
                        family: family.value(i).to_string(),
                        vernacular_en,
                        growth_form,
                    });
                }
            }
        }

        Ok(results)
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

    /// Get all plant IDs (for static generation)
    pub async fn get_all_plant_ids(&self) -> DFResult<Vec<RecordBatch>> {
        let sql = "SELECT wfo_taxon_id, wfo_scientific_name, family FROM plants ORDER BY wfo_taxon_id";
        self.query(sql).await
    }

    /// Find similar plants based on EIVE Euclidean distance
    pub async fn find_similar(
        &self,
        plant_id: &str,
        top_k: usize,
    ) -> DFResult<Vec<RecordBatch>> {
        let escaped_id = plant_id.replace("'", "''");

        // SQL query: compute Euclidean distance in 5D EIVE space (using master column names)
        let sql = format!(
            r#"
            WITH target AS (
                SELECT
                    "EIVEres-L_complete" as L,
                    "EIVEres-M_complete" as M,
                    "EIVEres-T_complete" as T,
                    "EIVEres-N_complete" as N,
                    "EIVEres-R_complete" as R
                FROM plants
                WHERE wfo_taxon_id = '{}'
            )
            SELECT
                p.*,
                SQRT(
                    POWER(p."EIVEres-L_complete" - t.L, 2) +
                    POWER(p."EIVEres-M_complete" - t.M, 2) +
                    POWER(p."EIVEres-T_complete" - t.T, 2) +
                    POWER(p."EIVEres-N_complete" - t.N, 2) +
                    POWER(p."EIVEres-R_complete" - t.R, 2)
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

    /// Get organisms for a plant (from flat format)
    /// Filter by source_column (original Phase 0 column name: pollinators, herbivores, etc.)
    pub async fn get_organisms(
        &self,
        plant_id: &str,
        source_column: Option<&str>,
    ) -> DFResult<Vec<RecordBatch>> {
        let escaped_id = plant_id.replace("'", "''");

        let type_filter = if let Some(t) = source_column {
            let escaped_type = t.replace("'", "''");
            format!("AND source_column = '{}'", escaped_type)
        } else {
            String::new()
        };

        let sql = format!(
            "SELECT * FROM organisms WHERE plant_wfo_id = '{}' {} ORDER BY source_column",
            escaped_id, type_filter
        );

        self.query(&sql).await
    }

    /// Get fungi for a plant (from flat format)
    /// Filter by source_column (original Phase 0 column name: amf_fungi, emf_fungi, etc.)
    pub async fn get_fungi(
        &self,
        plant_id: &str,
        source_column: Option<&str>,
    ) -> DFResult<Vec<RecordBatch>> {
        let escaped_id = plant_id.replace("'", "''");

        let category_filter = if let Some(cat) = source_column {
            let escaped_cat = cat.replace("'", "''");
            format!("AND source_column = '{}'", escaped_cat)
        } else {
            String::new()
        };

        let sql = format!(
            "SELECT * FROM fungi WHERE plant_wfo_id = '{}' {} ORDER BY source_column",
            escaped_id, category_filter
        );

        self.query(&sql).await
    }

    /// Get organism interaction counts (by source column from flat format)
    pub async fn get_organism_summary(&self, plant_id: &str) -> DFResult<Vec<RecordBatch>> {
        let escaped_id = plant_id.replace("'", "''");

        // Query flat format - source_column preserves original Phase 0 column name
        let sql = format!(
            r#"
            SELECT
                source_column as interaction_type,
                COUNT(*) as count
            FROM organisms
            WHERE plant_wfo_id = '{}'
            GROUP BY source_column
            ORDER BY source_column
            "#,
            escaped_id
        );

        self.query(&sql).await
    }

    /// Get fungal guild counts (by source column from flat format)
    pub async fn get_fungi_summary(&self, plant_id: &str) -> DFResult<Vec<RecordBatch>> {
        let escaped_id = plant_id.replace("'", "''");

        // Query flat format - source_column preserves original Phase 0 column name
        let sql = format!(
            r#"
            SELECT
                source_column as guild,
                COUNT(*) as count
            FROM fungi
            WHERE plant_wfo_id = '{}'
            GROUP BY source_column
            ORDER BY source_column
            "#,
            escaped_id
        );

        self.query(&sql).await
    }

    /// Get all master predators (known pest predators from GloBI)
    /// Returns list of predator taxon names
    pub async fn get_master_predators(&self) -> DFResult<Vec<RecordBatch>> {
        let sql = "SELECT predator_taxon FROM predators_master";
        self.query(sql).await
    }

    /// Get pathogens for a plant with observation counts
    /// Returns pathogen_taxon and observation_count, ordered by count descending
    pub async fn get_pathogens(&self, plant_id: &str, limit: Option<usize>) -> DFResult<Vec<RecordBatch>> {
        let escaped_id = plant_id.replace("'", "''");
        let limit_clause = limit.map(|l| format!("LIMIT {}", l)).unwrap_or_default();

        let sql = format!(
            r#"
            SELECT
                pathogen_taxon,
                observation_count
            FROM pathogens_ranked
            WHERE plant_wfo_id = '{}'
            ORDER BY observation_count DESC
            {}
            "#,
            escaped_id, limit_clause
        );

        self.query(&sql).await
    }

    /// Get beneficial fungi species (mycoparasites and entomopathogens)
    pub async fn get_beneficial_fungi(&self, plant_id: &str) -> DFResult<Vec<RecordBatch>> {
        let escaped_id = plant_id.replace("'", "''");

        let sql = format!(
            r#"
            SELECT
                source_column,
                fungus_taxon
            FROM fungi
            WHERE plant_wfo_id = '{}'
              AND source_column IN ('mycoparasite_fungi', 'entomopathogenic_fungi')
            ORDER BY source_column, fungus_taxon
            "#,
            escaped_id
        );

        self.query(&sql).await
    }
}

/// Result data for text search
#[cfg(feature = "api")]
#[derive(Debug, Clone)]
pub struct PlantSearchResultData {
    pub wfo_taxon_id: String,
    pub scientific_name: String,
    pub family: String,
    pub vernacular_en: Option<String>,
    pub growth_form: Option<String>,
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

    const PROJECT_ROOT: &str = "/home/olier/ellenberg";

    #[tokio::test]
    async fn test_query_engine_initialization() {
        match QueryEngine::new(PROJECT_ROOT).await {
            Ok(engine) => {
                // Verify we can execute a simple query
                let result = engine.query("SELECT COUNT(*) FROM plants").await;
                assert!(result.is_ok(), "Failed to query plants table");
            }
            Err(e) => {
                // If files don't exist, skip test
                println!("Skipping test (data files not found): {}", e);
            }
        }
    }

    #[tokio::test]
    async fn test_search_plants() {
        if let Ok(engine) = QueryEngine::new(PROJECT_ROOT).await {
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
