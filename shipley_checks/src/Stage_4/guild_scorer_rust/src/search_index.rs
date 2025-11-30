//! FST-based Search Index for Fast Plant Lookup
//!
//! Provides sub-millisecond prefix and fuzzy search across:
//! - Scientific names (Latin binomials)
//! - Common names (English)
//! - Family and genus names
//!
//! Memory usage: ~3-5 MB for 11,711 plants (FST compression)
//! Query time: <100 microseconds for prefix, <1ms for fuzzy

#[cfg(feature = "api")]
use fst::{Map, MapBuilder, IntoStreamer, Streamer, Automaton};
#[cfg(feature = "api")]
use fst_levenshtein::Levenshtein;
#[cfg(feature = "api")]
use std::collections::HashMap;
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

/// FST-based search index for fast plant lookup
#[cfg(feature = "api")]
pub struct SearchIndex {
    /// FST mapping normalized search term -> plant index
    fst_map: Map,
    /// All plants (indexed by position)
    plants: Vec<PlantRef>,
    /// Reverse lookup: search term -> list of plant indices (for duplicates)
    term_to_indices: HashMap<String, Vec<usize>>,
    /// Size of FST in bytes (stored at build time)
    fst_size: usize,
}

#[cfg(feature = "api")]
impl SearchIndex {
    /// Build search index from query engine at startup
    pub async fn build(query_engine: &crate::query_engine::QueryEngine) -> anyhow::Result<Self> {
        use datafusion::arrow::array::{StringArray, StringViewArray};

        tracing::info!("Building FST search index...");
        let start = std::time::Instant::now();

        // Query all plants with searchable fields
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

        // Collect all plants
        let mut plants: Vec<PlantRef> = Vec::new();
        let mut search_terms: Vec<(String, usize)> = Vec::new(); // (term, plant_index)

        for batch in &batches {
            let num_rows = batch.num_rows();

            // Helper to get string column (handles both StringArray and StringViewArray)
            fn get_string_col<'a>(batch: &'a datafusion::arrow::array::RecordBatch, name: &str) -> Option<Box<dyn Fn(usize) -> Option<&'a str> + 'a>> {
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
                let wfo_id = match wfo_fn(i) {
                    Some(s) => s.to_string(),
                    None => continue,
                };
                let scientific_name = match sci_fn(i) {
                    Some(s) => s.to_string(),
                    None => continue,
                };

                // Get all common names (semicolon-separated)
                let common_names_raw = common_fn.and_then(|f| f(i)).unwrap_or("");
                let common_names: Vec<String> = common_names_raw
                    .split(';')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect();

                // First common name for display
                let common_name = common_names.first().cloned();

                let family = family_fn.and_then(|f| f(i)).unwrap_or("").to_string();
                let genus = genus_fn.and_then(|f| f(i)).unwrap_or("").to_string();

                let plant_idx = plants.len();

                // Add search terms for this plant
                // 1. Scientific name (normalized)
                let sci_lower = scientific_name.to_lowercase();
                search_terms.push((sci_lower.clone(), plant_idx));

                // 2. Genus only (for "Rosa" matching all Rosa species)
                let genus_lower = genus.to_lowercase();
                if !genus_lower.is_empty() {
                    search_terms.push((genus_lower.clone(), plant_idx));
                }

                // 3. ALL common names (for "coconut", "coconut palm", etc.)
                for cn in &common_names {
                    let cn_lower = cn.to_lowercase();
                    if !cn_lower.is_empty() {
                        // Add full name
                        search_terms.push((cn_lower.clone(), plant_idx));

                        // Also index individual words (for "oak" matching "white oak")
                        for word in cn_lower.split_whitespace() {
                            if word.len() >= 3 && word != &cn_lower {
                                search_terms.push((word.to_string(), plant_idx));
                            }
                        }
                    }
                }

                // 4. Family (for "Rosaceae" searches)
                let family_lower = family.to_lowercase();
                if !family_lower.is_empty() {
                    search_terms.push((family_lower, plant_idx));
                }

                plants.push(PlantRef {
                    wfo_id,
                    scientific_name,
                    common_name,
                    family,
                    genus,
                });
            }
        }

        tracing::info!("Collected {} plants, {} search terms", plants.len(), search_terms.len());

        // Sort terms lexicographically (required for FST)
        search_terms.sort_by(|a, b| a.0.cmp(&b.0));

        // Build term -> indices map (for handling duplicates)
        let mut term_to_indices: HashMap<String, Vec<usize>> = HashMap::new();
        for (term, idx) in &search_terms {
            term_to_indices
                .entry(term.clone())
                .or_default()
                .push(*idx);
        }

        // Deduplicate terms for FST (FST requires unique keys)
        let mut unique_terms: Vec<(String, u64)> = Vec::new();
        let mut last_term = String::new();
        for (term, idx) in search_terms {
            if term != last_term {
                unique_terms.push((term.clone(), idx as u64));
                last_term = term;
            }
        }

        // Build FST
        let mut builder = MapBuilder::memory();
        for (term, idx) in &unique_terms {
            builder.insert(term.as_bytes(), *idx)?;
        }
        let fst_bytes = builder.into_inner()?;
        let fst_size = fst_bytes.len();
        let fst_map = Map::from_bytes(fst_bytes)?;

        let elapsed = start.elapsed();
        tracing::info!(
            "FST search index built in {:?} ({} plants, {} unique terms, {} bytes)",
            elapsed,
            plants.len(),
            unique_terms.len(),
            fst_size
        );

        Ok(Self {
            fst_map,
            plants,
            term_to_indices,
            fst_size,
        })
    }

    /// Prefix search (fast, for typeahead)
    pub fn search_prefix(&self, query: &str, limit: usize) -> Vec<&PlantRef> {
        if query.is_empty() {
            return vec![];
        }

        let query_lower = query.to_lowercase();

        // Use FST prefix automaton
        let prefix = fst::automaton::Str::new(&query_lower).starts_with();
        let mut stream = self.fst_map.search(prefix).into_stream();

        let mut seen_wfo: std::collections::HashSet<&str> = std::collections::HashSet::new();
        let mut results: Vec<&PlantRef> = Vec::new();

        // Collect matching plant indices
        while let Some((term, _idx)) = stream.next() {
            // Get all plants for this term
            if let Ok(term_str) = std::str::from_utf8(term) {
                if let Some(indices) = self.term_to_indices.get(term_str) {
                    for &plant_idx in indices {
                        if plant_idx < self.plants.len() {
                            let plant = &self.plants[plant_idx];
                            if seen_wfo.insert(&plant.wfo_id) {
                                results.push(plant);
                                if results.len() >= limit {
                                    return results;
                                }
                            }
                        }
                    }
                }
            }
        }

        results
    }

    /// Fuzzy search (allows typos)
    pub fn search_fuzzy(&self, query: &str, max_distance: u32, limit: usize) -> Vec<&PlantRef> {
        if query.is_empty() {
            return vec![];
        }

        let query_lower = query.to_lowercase();

        // Build Levenshtein automaton
        let lev = match Levenshtein::new(&query_lower, max_distance) {
            Ok(l) => l,
            Err(_) => return self.search_prefix(query, limit), // Fallback to prefix
        };

        let mut stream = self.fst_map.search(lev).into_stream();

        let mut seen_wfo: std::collections::HashSet<&str> = std::collections::HashSet::new();
        let mut results: Vec<&PlantRef> = Vec::new();

        while let Some((term, _idx)) = stream.next() {
            if let Ok(term_str) = std::str::from_utf8(term) {
                if let Some(indices) = self.term_to_indices.get(term_str) {
                    for &plant_idx in indices {
                        if plant_idx < self.plants.len() {
                            let plant = &self.plants[plant_idx];
                            if seen_wfo.insert(&plant.wfo_id) {
                                results.push(plant);
                                if results.len() >= limit {
                                    return results;
                                }
                            }
                        }
                    }
                }
            }
        }

        results
    }

    /// Combined search: prefix first, then fuzzy if few results
    pub fn search(&self, query: &str, limit: usize) -> Vec<&PlantRef> {
        // Try prefix search first (fastest)
        let prefix_results = self.search_prefix(query, limit);

        if prefix_results.len() >= limit / 2 {
            return prefix_results;
        }

        // If few prefix results, try fuzzy with 1 typo
        if query.len() >= 3 {
            let fuzzy_results = self.search_fuzzy(query, 1, limit);
            if fuzzy_results.len() > prefix_results.len() {
                return fuzzy_results;
            }
        }

        prefix_results
    }

    /// Get index statistics
    pub fn stats(&self) -> SearchIndexStats {
        SearchIndexStats {
            plant_count: self.plants.len(),
            term_count: self.term_to_indices.len(),
            fst_bytes: self.fst_size,
        }
    }
}

#[cfg(feature = "api")]
#[derive(Debug, serde::Serialize)]
pub struct SearchIndexStats {
    pub plant_count: usize,
    pub term_count: usize,
    pub fst_bytes: usize,
}
