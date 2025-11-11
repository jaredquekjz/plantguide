//! Data Loading and Management
//!
//! Handles loading plant, organism, and fungi datasets using Polars.
//! Mimics R implementation with parity-checked CSV/Parquet sources.
//!
//! R reference: shipley_checks/src/Stage_4/guild_scorer_v3_modular.R (lines 123-179)

use polars::prelude::*;
use rustc_hash::FxHashMap;
use anyhow::{Context, Result};

/// Main data holder for guild scoring
///
/// Contains all datasets loaded from shipley_checks/ directory
pub struct GuildData {
    /// Plant metadata (CSR, heights, Köppen tiers)
    pub plants: DataFrame,

    /// Plant-organism associations (herbivores, pollinators, etc.)
    pub organisms: DataFrame,

    /// Plant-fungi associations (pathogens, AMF, EMF, etc.)
    pub fungi: DataFrame,

    /// Herbivore ID → Vector of predator IDs
    pub herbivore_predators: FxHashMap<String, Vec<String>>,

    /// Herbivore ID → Vector of entomopathogenic fungi IDs
    pub insect_parasites: FxHashMap<String, Vec<String>>,

    /// Pathogen ID → Vector of antagonist fungi IDs
    pub pathogen_antagonists: FxHashMap<String, Vec<String>>,
}

impl GuildData {
    /// Load all datasets from shipley_checks directory
    ///
    /// R reference: guild_scorer_v3_modular.R::load_datasets()
    pub fn load() -> Result<Self> {
        println!("Loading datasets (parity-checked CSV/Parquet files)...");

        // Plants - from shared parquet (stage 3 output)
        let plants = Self::load_plants(
            "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet"
        )?;

        // Organisms - from R-generated CSV
        let organisms = Self::load_organisms(
            "shipley_checks/validation/organism_profiles_pure_r.csv"
        )?;

        // Fungi - from R-generated CSV
        let fungi = Self::load_fungi(
            "shipley_checks/validation/fungal_guilds_pure_r.csv"
        )?;

        // Biocontrol lookup tables
        let herbivore_predators = Self::load_lookup_table(
            "shipley_checks/validation/herbivore_predators_pure_r.csv",
            "herbivore",
            "predators",
        )?;

        let insect_parasites = Self::load_lookup_table(
            "shipley_checks/validation/insect_fungal_parasites_pure_r.csv",
            "herbivore",
            "entomopathogenic_fungi",
        )?;

        let pathogen_antagonists = Self::load_lookup_table(
            "shipley_checks/validation/pathogen_antagonists_pure_r.csv",
            "pathogen",
            "antagonists",
        )?;

        println!("  Plants: {}", plants.height());
        println!("  Organisms: {}", organisms.height());
        println!("  Fungi: {}", fungi.height());
        println!("  Herbivore predators: {}", herbivore_predators.len());
        println!("  Insect parasites: {}", insect_parasites.len());
        println!("  Pathogen antagonists: {}", pathogen_antagonists.len());

        Ok(GuildData {
            plants,
            organisms,
            fungi,
            herbivore_predators,
            insect_parasites,
            pathogen_antagonists,
        })
    }

    /// Load plant metadata from parquet
    ///
    /// R reference: guild_scorer_v3_modular.R lines 127-135
    fn load_plants(path: &str) -> Result<DataFrame> {
        let df = LazyFrame::scan_parquet(path, Default::default())
            .with_context(|| format!("Failed to scan parquet: {}", path))?
            .select(&[
                col("wfo_taxon_id"),
                col("wfo_scientific_name"),
                col("family"),
                col("genus"),
                col("height_m"),
                col("try_growth_form"),
                col("C").alias("CSR_C"),
                col("S").alias("CSR_S"),
                col("R").alias("CSR_R"),
                col("EIVEres-L").alias("light_pref"),
                col("tier_1_tropical"),
                col("tier_2_mediterranean"),
                col("tier_3_humid_temperate"),
                col("tier_4_continental"),
                col("tier_5_boreal_polar"),
                col("tier_6_arid"),
            ])
            .collect()
            .with_context(|| "Failed to load plants parquet")?;

        Ok(df)
    }

    /// Load organism associations from CSV
    ///
    /// Columns with pipe-separated lists are kept as strings for now.
    /// Parsing happens in count_shared_organisms utility.
    ///
    /// R reference: guild_scorer_v3_modular.R lines 151-153
    fn load_organisms(path: &str) -> Result<DataFrame> {
        CsvReadOptions::default()
            .with_has_header(true)
            .try_into_reader_with_file_path(Some(path.into()))
            .with_context(|| format!("Failed to create CSV reader: {}", path))?
            .finish()
            .with_context(|| "Failed to load organisms CSV")
    }

    /// Load fungi associations from CSV
    ///
    /// R reference: guild_scorer_v3_modular.R lines 156-159
    fn load_fungi(path: &str) -> Result<DataFrame> {
        CsvReadOptions::default()
            .with_has_header(true)
            .try_into_reader_with_file_path(Some(path.into()))
            .with_context(|| format!("Failed to create CSV reader: {}", path))?
            .finish()
            .with_context(|| "Failed to load fungi CSV")
    }

    /// Load lookup table: Key → Pipe-separated values
    ///
    /// Example: herbivore_id → "predator1|predator2|predator3"
    ///
    /// R reference: guild_scorer_v3_modular.R lines 162-172
    fn load_lookup_table(
        path: &str,
        key_col: &str,
        value_col: &str,
    ) -> Result<FxHashMap<String, Vec<String>>> {
        let df = CsvReadOptions::default()
            .with_has_header(true)
            .try_into_reader_with_file_path(Some(path.into()))
            .with_context(|| format!("Failed to create CSV reader: {}", path))?
            .finish()
            .with_context(|| format!("Failed to load lookup table: {}", path))?;

        let mut map = FxHashMap::default();

        let key_series = df.column(key_col)
            .with_context(|| format!("Column '{}' not found", key_col))?
            .str()
            .with_context(|| format!("Column '{}' is not string type", key_col))?;

        let value_series = df.column(value_col)
            .with_context(|| format!("Column '{}' not found", value_col))?
            .str()
            .with_context(|| format!("Column '{}' is not string type", value_col))?;

        for idx in 0..df.height() {
            if let (Some(key), Some(value_str)) = (key_series.get(idx), value_series.get(idx)) {
                let values: Vec<String> = value_str
                    .split('|')
                    .filter(|s| !s.is_empty())
                    .map(|s| s.to_string())
                    .collect();

                if !values.is_empty() {
                    map.insert(key.to_string(), values);
                }
            }
        }

        Ok(map)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[ignore] // Requires data files to be present
    fn test_load_data() {
        let data = GuildData::load().expect("Failed to load data");
        assert!(data.plants.height() > 0);
        assert!(data.organisms.height() > 0);
        assert!(data.fungi.height() > 0);
    }
}
