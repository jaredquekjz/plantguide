//! Tantivy-based Search Index for Fast Plant Lookup
//!
//! Provides sub-millisecond full-text search with BM25 ranking across:
//! - Scientific names (Latin binomials) - boosted
//! - Common names (English)
//! - Family and genus names
//!
//! Uses Tantivy (Rust's Lucene) for proper relevance ranking without manual tuning.

#[cfg(feature = "api")]
use tantivy::{
    collector::TopDocs,
    query::QueryParser,
    schema::{Schema, Field, TEXT, STORED, STRING, OwnedValue},
    Index, IndexReader, ReloadPolicy, TantivyDocument,
};
#[cfg(feature = "api")]
use datafusion::arrow::array::Array;

/// Reference to a plant in the index
#[cfg(feature = "api")]
#[derive(Debug, Clone, serde::Serialize)]
pub struct PlantRef {
    pub wfo_id: String,
    pub scientific_name: String,
    pub common_name: Option<String>,
    pub family: String,
    pub genus: String,
}

/// Schema field handles
#[cfg(feature = "api")]
struct SearchFields {
    wfo_id: Field,
    scientific_name: Field,
    common_names: Field,
    genus: Field,
    family: Field,
}

/// Tantivy-based search index for fast plant lookup with BM25 ranking
#[cfg(feature = "api")]
pub struct SearchIndex {
    index: Index,
    reader: IndexReader,
    query_parser: QueryParser,
    fields: SearchFields,
    /// All plants for result retrieval
    plants: Vec<PlantRef>,
    /// wfo_id -> plant index for fast lookup
    wfo_to_idx: std::collections::HashMap<String, usize>,
}

#[cfg(feature = "api")]
impl SearchIndex {
    /// Build search index from query engine at startup
    pub async fn build(query_engine: &crate::query_engine::QueryEngine) -> anyhow::Result<Self> {
        use datafusion::arrow::array::{StringArray, StringViewArray};

        tracing::info!("Building Tantivy search index...");
        let start = std::time::Instant::now();

        // Define schema
        let mut schema_builder = Schema::builder();

        // wfo_id as STRING (exact match, stored)
        let wfo_id = schema_builder.add_text_field("wfo_id", STRING | STORED);

        // scientific_name - TEXT for full-text search, STORED for retrieval
        let scientific_name = schema_builder.add_text_field("scientific_name", TEXT | STORED);

        // common_names - TEXT for full-text search (all names concatenated)
        let common_names = schema_builder.add_text_field("common_names", TEXT | STORED);

        // genus - TEXT for full-text search
        let genus = schema_builder.add_text_field("genus", TEXT | STORED);

        // family - TEXT for full-text search
        let family = schema_builder.add_text_field("family", TEXT | STORED);

        let schema = schema_builder.build();

        // Create in-RAM index
        let index = Index::create_in_ram(schema.clone());

        // Get index writer
        let mut index_writer = index.writer(50_000_000)?; // 50MB buffer

        // Query all plants
        let sql = r#"
            SELECT
                wfo_taxon_id,
                wfo_scientific_name,
                vernacular_name_en,
                family,
                genus
            FROM plants
            ORDER BY wfo_scientific_name
        "#;

        let batches = query_engine.query(sql).await?;

        // Collect plants and index documents
        let mut plants: Vec<PlantRef> = Vec::new();
        let mut wfo_to_idx: std::collections::HashMap<String, usize> = std::collections::HashMap::new();

        for batch in &batches {
            let num_rows = batch.num_rows();

            // Helper to get string column
            fn get_string_col<'a>(
                batch: &'a datafusion::arrow::array::RecordBatch,
                name: &str,
            ) -> Option<Box<dyn Fn(usize) -> Option<&'a str> + 'a>> {
                let col = batch.column_by_name(name)?;
                if let Some(arr) = col.as_any().downcast_ref::<StringViewArray>() {
                    Some(Box::new(move |i| {
                        if arr.is_null(i) { None } else { Some(arr.value(i)) }
                    }))
                } else if let Some(arr) = col.as_any().downcast_ref::<StringArray>() {
                    Some(Box::new(move |i| {
                        if arr.is_null(i) { None } else { Some(arr.value(i)) }
                    }))
                } else {
                    None
                }
            }

            let wfo_col = get_string_col(batch, "wfo_taxon_id");
            let sci_col = get_string_col(batch, "wfo_scientific_name");
            let common_col = get_string_col(batch, "vernacular_name_en");
            let family_col = get_string_col(batch, "family");
            let genus_col = get_string_col(batch, "genus");

            if wfo_col.is_none() || sci_col.is_none() {
                continue;
            }

            let wfo_fn = wfo_col.unwrap();
            let sci_fn = sci_col.unwrap();
            let common_fn = common_col.as_ref();
            let family_fn = family_col.as_ref();
            let genus_fn = genus_col.as_ref();

            for i in 0..num_rows {
                let wfo_id_val = match wfo_fn(i) {
                    Some(s) => s.to_string(),
                    None => continue,
                };
                let scientific_name_val = match sci_fn(i) {
                    Some(s) => s.to_string(),
                    None => continue,
                };

                // Get all common names (semicolon-separated), replace ; with space for indexing
                let common_names_raw = common_fn.and_then(|f| f(i)).unwrap_or("");
                let common_names_indexed = common_names_raw.replace(';', " ");

                // First common name for display
                let first_common = common_names_raw
                    .split(';')
                    .next()
                    .map(|s| s.trim())
                    .filter(|s| !s.is_empty())
                    .map(String::from);

                let family_val = family_fn.and_then(|f| f(i)).unwrap_or("").to_string();
                let genus_val = genus_fn.and_then(|f| f(i)).unwrap_or("").to_string();

                // Add document to Tantivy index
                let mut doc = TantivyDocument::new();
                doc.add_text(wfo_id, &wfo_id_val);
                doc.add_text(scientific_name, &scientific_name_val);
                doc.add_text(common_names, &common_names_indexed);
                doc.add_text(genus, &genus_val);
                doc.add_text(family, &family_val);

                index_writer.add_document(doc)?;

                // Store plant reference
                let plant_idx = plants.len();
                wfo_to_idx.insert(wfo_id_val.clone(), plant_idx);

                plants.push(PlantRef {
                    wfo_id: wfo_id_val,
                    scientific_name: scientific_name_val,
                    common_name: first_common,
                    family: family_val,
                    genus: genus_val,
                });
            }
        }

        // Commit the index
        index_writer.commit()?;

        // Create reader
        let reader = index
            .reader_builder()
            .reload_policy(ReloadPolicy::Manual)
            .try_into()?;

        // Create query parser - search across all text fields
        // Boost scientific_name and genus higher for better relevance
        let mut query_parser = QueryParser::for_index(
            &index,
            vec![scientific_name, common_names, genus, family],
        );

        // Set field boosts: scientific_name and genus are more important
        query_parser.set_field_boost(scientific_name, 3.0);
        query_parser.set_field_boost(genus, 2.5);
        query_parser.set_field_boost(common_names, 1.5);
        query_parser.set_field_boost(family, 1.0);

        let fields = SearchFields {
            wfo_id,
            scientific_name,
            common_names,
            genus,
            family,
        };

        let elapsed = start.elapsed();
        tracing::info!(
            "Tantivy search index built in {:?} ({} plants indexed)",
            elapsed,
            plants.len()
        );

        Ok(Self {
            index,
            reader,
            query_parser,
            fields,
            plants,
            wfo_to_idx,
        })
    }

    /// Search with BM25 ranking
    pub fn search(&self, query: &str, limit: usize) -> Vec<&PlantRef> {
        if query.is_empty() {
            return vec![];
        }

        let searcher = self.reader.searcher();

        // Parse query - handle special characters by escaping or using lenient parsing
        let parsed_query = match self.query_parser.parse_query(query) {
            Ok(q) => q,
            Err(_) => {
                // If query parsing fails (e.g., special chars), try as a simple term query
                // by escaping the query
                let escaped = query
                    .chars()
                    .map(|c| {
                        if "+-&|!(){}[]^\"~*?:\\/".contains(c) {
                            format!("\\{}", c)
                        } else {
                            c.to_string()
                        }
                    })
                    .collect::<String>();

                match self.query_parser.parse_query(&escaped) {
                    Ok(q) => q,
                    Err(_) => return vec![], // Give up if still fails
                }
            }
        };

        // Execute search with BM25 ranking
        let top_docs = match searcher.search(&parsed_query, &TopDocs::with_limit(limit)) {
            Ok(docs) => docs,
            Err(_) => return vec![],
        };

        // Map results back to PlantRef
        let mut results = Vec::with_capacity(top_docs.len());

        for (_score, doc_address) in top_docs {
            if let Ok(doc) = searcher.doc::<TantivyDocument>(doc_address) {
                // Get wfo_id from document
                if let Some(wfo_id) = doc.get_first(self.fields.wfo_id) {
                    // OwnedValue::Str contains the string
                    if let OwnedValue::Str(wfo_str) = wfo_id {
                        if let Some(&idx) = self.wfo_to_idx.get(wfo_str.as_str()) {
                            results.push(&self.plants[idx]);
                        }
                    }
                }
            }
        }

        results
    }

    /// Prefix search (for autocomplete) - uses wildcard query
    pub fn search_prefix(&self, query: &str, limit: usize) -> Vec<&PlantRef> {
        if query.is_empty() {
            return vec![];
        }

        // For short queries, append wildcard for prefix matching
        let query_with_wildcard = if query.len() >= 2 {
            format!("{}*", query)
        } else {
            query.to_string()
        };

        self.search(&query_with_wildcard, limit)
    }

    /// Fuzzy search (allows typos) - uses fuzzy query syntax
    pub fn search_fuzzy(&self, query: &str, limit: usize) -> Vec<&PlantRef> {
        if query.is_empty() || query.len() < 3 {
            return self.search(query, limit);
        }

        // Tantivy fuzzy syntax: term~1 for 1 edit distance
        let fuzzy_query = format!("{}~1", query);
        self.search(&fuzzy_query, limit)
    }

    /// Get index statistics
    pub fn stats(&self) -> SearchIndexStats {
        let searcher = self.reader.searcher();
        let num_docs = searcher.num_docs() as usize;

        SearchIndexStats {
            plant_count: self.plants.len(),
            indexed_docs: num_docs,
            // Tantivy doesn't expose index size easily for in-RAM index
            index_bytes: 0,
        }
    }
}

#[cfg(feature = "api")]
#[derive(Debug, serde::Serialize)]
pub struct SearchIndexStats {
    pub plant_count: usize,
    pub indexed_docs: usize,
    pub index_bytes: usize,
}
