//! Suitability Cache - In-memory typed storage for fast envelope lookups
//!
//! Replaces slow DataFusion SQL queries with O(1) FxHashMap lookups.
//! Stores only the ~60 columns needed for suitability calculations.

use rustc_hash::FxHashMap;
use serde_json::Value;
use std::collections::HashMap;

/// Typed envelope data for suitability calculations (~60 fields vs 861 in full plant record)
#[derive(Debug, Clone, Default)]
pub struct SuitabilityEnvelope {
    // === Light ===
    pub eive_l: Option<f64>,
    pub eive_l_source: Option<String>,
    pub height_m: Option<f64>,

    // === Temperature - BioClim ===
    pub bio5_q05: Option<f64>,  // Warmest month
    pub bio5_q50: Option<f64>,
    pub bio5_q95: Option<f64>,
    pub bio6_q05: Option<f64>,  // Coldest month
    pub bio6_q50: Option<f64>,
    pub bio6_q95: Option<f64>,

    // === Temperature - Agroclimate ===
    pub fd_q05: Option<f64>,    // Frost days
    pub fd_q50: Option<f64>,
    pub fd_q95: Option<f64>,
    pub cfd_q05: Option<f64>,   // Consecutive frost days
    pub cfd_q50: Option<f64>,
    pub cfd_q95: Option<f64>,
    pub su_q50: Option<f64>,    // Summer days
    pub su_q95: Option<f64>,
    pub tr_q05: Option<f64>,    // Tropical nights
    pub tr_q50: Option<f64>,
    pub tr_q95: Option<f64>,
    pub dtr_q05: Option<f64>,   // Diurnal temp range
    pub dtr_q50: Option<f64>,
    pub dtr_q95: Option<f64>,
    pub gsl_q05: Option<f64>,   // Growing season length
    pub gsl_q50: Option<f64>,
    pub gsl_q95: Option<f64>,

    // === Moisture ===
    pub bio12_q05: Option<f64>, // Annual precip
    pub bio12_q50: Option<f64>,
    pub bio12_q95: Option<f64>,
    pub cdd_q05: Option<f64>,   // Consecutive dry days
    pub cdd_q50: Option<f64>,
    pub cdd_q95: Option<f64>,
    pub ww_q05: Option<f64>,    // Warm wet days
    pub ww_q50: Option<f64>,
    pub ww_q95: Option<f64>,
    pub cwd_q05: Option<f64>,   // Consecutive wet days
    pub cwd_q50: Option<f64>,
    pub cwd_q95: Option<f64>,

    // === Soil (0-5cm depth) ===
    pub phh2o_q05: Option<f64>,
    pub phh2o_q50: Option<f64>,
    pub phh2o_q95: Option<f64>,
    pub clay_q05: Option<f64>,
    pub clay_q50: Option<f64>,
    pub clay_q95: Option<f64>,
    pub sand_q05: Option<f64>,
    pub sand_q50: Option<f64>,
    pub sand_q95: Option<f64>,
    pub soc_q05: Option<f64>,
    pub soc_q50: Option<f64>,
    pub soc_q95: Option<f64>,
    pub cec_q05: Option<f64>,
    pub cec_q50: Option<f64>,
    pub cec_q95: Option<f64>,

    // === Soil (5-15cm depth) ===
    pub phh2o_5_15_q05: Option<f64>,
    pub phh2o_5_15_q50: Option<f64>,
    pub phh2o_5_15_q95: Option<f64>,
    pub clay_5_15_q05: Option<f64>,
    pub clay_5_15_q50: Option<f64>,
    pub clay_5_15_q95: Option<f64>,
    pub sand_5_15_q05: Option<f64>,
    pub sand_5_15_q50: Option<f64>,
    pub sand_5_15_q95: Option<f64>,

    // === Climate tier flags ===
    pub tier_1_tropical: bool,
    pub tier_2_mediterranean: bool,
    pub tier_3_humid_temperate: bool,
    pub tier_4_continental: bool,
    pub tier_5_boreal_polar: bool,
    pub tier_6_arid: bool,
}

impl SuitabilityEnvelope {
    /// Convert to HashMap<String, Value> for compatibility with s2_requirements::generate()
    pub fn to_hashmap(&self) -> HashMap<String, Value> {
        let mut map = HashMap::new();

        // Helper to insert Option<f64>
        macro_rules! insert_f64 {
            ($key:expr, $val:expr) => {
                if let Some(v) = $val {
                    map.insert($key.to_string(), Value::from(v));
                }
            };
        }

        // Helper to insert Option<String>
        macro_rules! insert_str {
            ($key:expr, $val:expr) => {
                if let Some(ref v) = $val {
                    map.insert($key.to_string(), Value::from(v.clone()));
                }
            };
        }

        // Light
        insert_f64!("EIVEres-L", self.eive_l);
        insert_f64!("EIVE_L", self.eive_l);
        insert_f64!("EIVEres-L_complete", self.eive_l);
        insert_f64!("EIVE_L_complete", self.eive_l);
        insert_str!("EIVEres-L_source", self.eive_l_source);
        insert_f64!("height_m", self.height_m);

        // Temperature - BioClim
        insert_f64!("wc2.1_30s_bio_5_q05", self.bio5_q05);
        insert_f64!("wc2.1_30s_bio_5_q50", self.bio5_q50);
        insert_f64!("wc2.1_30s_bio_5_q95", self.bio5_q95);
        insert_f64!("wc2.1_30s_bio_6_q05", self.bio6_q05);
        insert_f64!("wc2.1_30s_bio_6_q50", self.bio6_q50);
        insert_f64!("wc2.1_30s_bio_6_q95", self.bio6_q95);

        // Temperature - Agroclimate
        insert_f64!("FD_q05", self.fd_q05);
        insert_f64!("FD_q50", self.fd_q50);
        insert_f64!("FD_q95", self.fd_q95);
        insert_f64!("CFD_q05", self.cfd_q05);
        insert_f64!("CFD_q50", self.cfd_q50);
        insert_f64!("CFD_q95", self.cfd_q95);
        insert_f64!("SU_q50", self.su_q50);
        insert_f64!("SU_q95", self.su_q95);
        insert_f64!("TR_q05", self.tr_q05);
        insert_f64!("TR_q50", self.tr_q50);
        insert_f64!("TR_q95", self.tr_q95);
        insert_f64!("DTR_q05", self.dtr_q05);
        insert_f64!("DTR_q50", self.dtr_q50);
        insert_f64!("DTR_q95", self.dtr_q95);
        insert_f64!("GSL_q05", self.gsl_q05);
        insert_f64!("GSL_q50", self.gsl_q50);
        insert_f64!("GSL_q95", self.gsl_q95);

        // Moisture
        insert_f64!("wc2.1_30s_bio_12_q05", self.bio12_q05);
        insert_f64!("wc2.1_30s_bio_12_q50", self.bio12_q50);
        insert_f64!("wc2.1_30s_bio_12_q95", self.bio12_q95);
        insert_f64!("CDD_q05", self.cdd_q05);
        insert_f64!("CDD_q50", self.cdd_q50);
        insert_f64!("CDD_q95", self.cdd_q95);
        insert_f64!("WW_q05", self.ww_q05);
        insert_f64!("WW_q50", self.ww_q50);
        insert_f64!("WW_q95", self.ww_q95);
        insert_f64!("CWD_q05", self.cwd_q05);
        insert_f64!("CWD_q50", self.cwd_q50);
        insert_f64!("CWD_q95", self.cwd_q95);

        // Soil 0-5cm
        insert_f64!("phh2o_0_5cm_q05", self.phh2o_q05);
        insert_f64!("phh2o_0_5cm_q50", self.phh2o_q50);
        insert_f64!("phh2o_0_5cm_q95", self.phh2o_q95);
        insert_f64!("clay_0_5cm_q05", self.clay_q05);
        insert_f64!("clay_0_5cm_q50", self.clay_q50);
        insert_f64!("clay_0_5cm_q95", self.clay_q95);
        insert_f64!("sand_0_5cm_q05", self.sand_q05);
        insert_f64!("sand_0_5cm_q50", self.sand_q50);
        insert_f64!("sand_0_5cm_q95", self.sand_q95);
        insert_f64!("soc_0_5cm_q05", self.soc_q05);
        insert_f64!("soc_0_5cm_q50", self.soc_q50);
        insert_f64!("soc_0_5cm_q95", self.soc_q95);
        insert_f64!("cec_0_5cm_q05", self.cec_q05);
        insert_f64!("cec_0_5cm_q50", self.cec_q50);
        insert_f64!("cec_0_5cm_q95", self.cec_q95);

        // Soil 5-15cm
        insert_f64!("phh2o_5_15cm_q05", self.phh2o_5_15_q05);
        insert_f64!("phh2o_5_15cm_q50", self.phh2o_5_15_q50);
        insert_f64!("phh2o_5_15cm_q95", self.phh2o_5_15_q95);
        insert_f64!("clay_5_15cm_q05", self.clay_5_15_q05);
        insert_f64!("clay_5_15cm_q50", self.clay_5_15_q50);
        insert_f64!("clay_5_15cm_q95", self.clay_5_15_q95);
        insert_f64!("sand_5_15cm_q05", self.sand_5_15_q05);
        insert_f64!("sand_5_15cm_q50", self.sand_5_15_q50);
        insert_f64!("sand_5_15cm_q95", self.sand_5_15_q95);

        // Climate tiers
        map.insert("tier_1_tropical".to_string(), Value::from(self.tier_1_tropical));
        map.insert("tier_2_mediterranean".to_string(), Value::from(self.tier_2_mediterranean));
        map.insert("tier_3_humid_temperate".to_string(), Value::from(self.tier_3_humid_temperate));
        map.insert("tier_4_continental".to_string(), Value::from(self.tier_4_continental));
        map.insert("tier_5_boreal_polar".to_string(), Value::from(self.tier_5_boreal_polar));
        map.insert("tier_6_arid".to_string(), Value::from(self.tier_6_arid));

        map
    }
}

/// In-memory cache of suitability envelopes indexed by WFO ID
pub struct SuitabilityCache {
    envelopes: FxHashMap<String, SuitabilityEnvelope>,
}

impl SuitabilityCache {
    /// Load suitability envelopes directly from parquet file
    ///
    /// Loads only the ~60 columns needed for suitability calculations,
    /// not the full 859 columns in the parquet.
    pub fn from_parquet(path: &str) -> anyhow::Result<Self> {
        use polars::prelude::*;

        // Define columns needed for suitability calculations (original names)
        let columns = vec![
            col("wfo_taxon_id"),
            // Light
            col("EIVEres-L"),
            col("EIVEres-L_source"),
            col("height_m"),
            // Temperature - BioClim
            col("wc2.1_30s_bio_5_q05"),
            col("wc2.1_30s_bio_5_q50"),
            col("wc2.1_30s_bio_5_q95"),
            col("wc2.1_30s_bio_6_q05"),
            col("wc2.1_30s_bio_6_q50"),
            col("wc2.1_30s_bio_6_q95"),
            // Temperature - Agroclimate
            col("FD_q05"),
            col("FD_q50"),
            col("FD_q95"),
            col("CFD_q05"),
            col("CFD_q50"),
            col("CFD_q95"),
            col("SU_q50"),
            col("SU_q95"),
            col("TR_q05"),
            col("TR_q50"),
            col("TR_q95"),
            col("DTR_q05"),
            col("DTR_q50"),
            col("DTR_q95"),
            col("GSL_q05"),
            col("GSL_q50"),
            col("GSL_q95"),
            // Moisture
            col("wc2.1_30s_bio_12_q05"),
            col("wc2.1_30s_bio_12_q50"),
            col("wc2.1_30s_bio_12_q95"),
            col("CDD_q05"),
            col("CDD_q50"),
            col("CDD_q95"),
            col("WW_q05"),
            col("WW_q50"),
            col("WW_q95"),
            col("CWD_q05"),
            col("CWD_q50"),
            col("CWD_q95"),
            // Soil 0-5cm
            col("phh2o_0_5cm_q05"),
            col("phh2o_0_5cm_q50"),
            col("phh2o_0_5cm_q95"),
            col("clay_0_5cm_q05"),
            col("clay_0_5cm_q50"),
            col("clay_0_5cm_q95"),
            col("sand_0_5cm_q05"),
            col("sand_0_5cm_q50"),
            col("sand_0_5cm_q95"),
            col("soc_0_5cm_q05"),
            col("soc_0_5cm_q50"),
            col("soc_0_5cm_q95"),
            col("cec_0_5cm_q05"),
            col("cec_0_5cm_q50"),
            col("cec_0_5cm_q95"),
            // Soil 5-15cm
            col("phh2o_5_15cm_q05"),
            col("phh2o_5_15cm_q50"),
            col("phh2o_5_15cm_q95"),
            col("clay_5_15cm_q05"),
            col("clay_5_15cm_q50"),
            col("clay_5_15cm_q95"),
            col("sand_5_15cm_q05"),
            col("sand_5_15cm_q50"),
            col("sand_5_15cm_q95"),
            // Climate tiers
            col("tier_1_tropical"),
            col("tier_2_mediterranean"),
            col("tier_3_humid_temperate"),
            col("tier_4_continental"),
            col("tier_5_boreal_polar"),
            col("tier_6_arid"),
        ];

        let df = LazyFrame::scan_parquet(path, Default::default())?
            .select(&columns)
            .collect()?;

        Ok(Self::from_dataframe(&df))
    }

    /// Load suitability envelopes from a pre-loaded Polars DataFrame
    fn from_dataframe(df: &polars::frame::DataFrame) -> Self {
        use polars::prelude::*;

        let mut envelopes = FxHashMap::default();
        let n_rows = df.height();

        // Get column accessors
        let wfo_col = df.column("wfo_taxon_id").ok();

        // Helper to get f64 column (with i64 fallback via cast)
        // Returns owned ChunkedArray to handle both f64 and cast i64 uniformly
        macro_rules! get_col {
            ($name:expr) => {{
                df.column($name).ok().and_then(|c| {
                    // Try f64 first - clone to own
                    if let Ok(f) = c.f64() {
                        return Some(f.clone());
                    }
                    // Try casting from i64
                    if let Ok(i) = c.i64() {
                        let cast_series = i.cast(&DataType::Float64).ok()?;
                        return Some(cast_series.f64().ok()?.clone());
                    }
                    None
                })
            }};
        }

        // Helper to get value from optional chunked array at index
        macro_rules! get_val {
            ($col:expr, $i:expr) => {
                $col.as_ref().and_then(|c| c.get($i))
            };
        }

        // Helper to get bool column
        macro_rules! get_bool_col {
            ($name:expr) => {
                df.column($name).ok().and_then(|c| c.bool().ok())
            };
        }

        // Helper to get string column
        macro_rules! get_str_col {
            ($name:expr) => {
                df.column($name).ok().and_then(|c| c.str().ok())
            };
        }

        // Pre-fetch all columns
        let eive_l = get_col!("EIVEres-L").or_else(|| get_col!("EIVE_L"));
        let eive_l_source = get_str_col!("EIVEres-L_source");
        let height_m = get_col!("height_m");

        let bio5_q05 = get_col!("wc2.1_30s_bio_5_q05");
        let bio5_q50 = get_col!("wc2.1_30s_bio_5_q50");
        let bio5_q95 = get_col!("wc2.1_30s_bio_5_q95");
        let bio6_q05 = get_col!("wc2.1_30s_bio_6_q05");
        let bio6_q50 = get_col!("wc2.1_30s_bio_6_q50");
        let bio6_q95 = get_col!("wc2.1_30s_bio_6_q95");

        let fd_q05 = get_col!("FD_q05");
        let fd_q50 = get_col!("FD_q50");
        let fd_q95 = get_col!("FD_q95");
        let cfd_q05 = get_col!("CFD_q05");
        let cfd_q50 = get_col!("CFD_q50");
        let cfd_q95 = get_col!("CFD_q95");
        let su_q50 = get_col!("SU_q50");
        let su_q95 = get_col!("SU_q95");
        let tr_q05 = get_col!("TR_q05");
        let tr_q50 = get_col!("TR_q50");
        let tr_q95 = get_col!("TR_q95");
        let dtr_q05 = get_col!("DTR_q05");
        let dtr_q50 = get_col!("DTR_q50");
        let dtr_q95 = get_col!("DTR_q95");
        let gsl_q05 = get_col!("GSL_q05");
        let gsl_q50 = get_col!("GSL_q50");
        let gsl_q95 = get_col!("GSL_q95");

        let bio12_q05 = get_col!("wc2.1_30s_bio_12_q05");
        let bio12_q50 = get_col!("wc2.1_30s_bio_12_q50");
        let bio12_q95 = get_col!("wc2.1_30s_bio_12_q95");
        let cdd_q05 = get_col!("CDD_q05");
        let cdd_q50 = get_col!("CDD_q50");
        let cdd_q95 = get_col!("CDD_q95");
        let ww_q05 = get_col!("WW_q05");
        let ww_q50 = get_col!("WW_q50");
        let ww_q95 = get_col!("WW_q95");
        let cwd_q05 = get_col!("CWD_q05");
        let cwd_q50 = get_col!("CWD_q50");
        let cwd_q95 = get_col!("CWD_q95");

        let phh2o_q05 = get_col!("phh2o_0_5cm_q05");
        let phh2o_q50 = get_col!("phh2o_0_5cm_q50");
        let phh2o_q95 = get_col!("phh2o_0_5cm_q95");
        let clay_q05 = get_col!("clay_0_5cm_q05");
        let clay_q50 = get_col!("clay_0_5cm_q50");
        let clay_q95 = get_col!("clay_0_5cm_q95");
        let sand_q05 = get_col!("sand_0_5cm_q05");
        let sand_q50 = get_col!("sand_0_5cm_q50");
        let sand_q95 = get_col!("sand_0_5cm_q95");
        let soc_q05 = get_col!("soc_0_5cm_q05");
        let soc_q50 = get_col!("soc_0_5cm_q50");
        let soc_q95 = get_col!("soc_0_5cm_q95");
        let cec_q05 = get_col!("cec_0_5cm_q05");
        let cec_q50 = get_col!("cec_0_5cm_q50");
        let cec_q95 = get_col!("cec_0_5cm_q95");

        let phh2o_5_15_q05 = get_col!("phh2o_5_15cm_q05");
        let phh2o_5_15_q50 = get_col!("phh2o_5_15cm_q50");
        let phh2o_5_15_q95 = get_col!("phh2o_5_15cm_q95");
        let clay_5_15_q05 = get_col!("clay_5_15cm_q05");
        let clay_5_15_q50 = get_col!("clay_5_15cm_q50");
        let clay_5_15_q95 = get_col!("clay_5_15cm_q95");
        let sand_5_15_q05 = get_col!("sand_5_15cm_q05");
        let sand_5_15_q50 = get_col!("sand_5_15cm_q50");
        let sand_5_15_q95 = get_col!("sand_5_15cm_q95");

        let tier_1 = get_bool_col!("tier_1_tropical");
        let tier_2 = get_bool_col!("tier_2_mediterranean");
        let tier_3 = get_bool_col!("tier_3_humid_temperate");
        let tier_4 = get_bool_col!("tier_4_continental");
        let tier_5 = get_bool_col!("tier_5_boreal_polar");
        let tier_6 = get_bool_col!("tier_6_arid");

        // Build envelopes row by row
        for i in 0..n_rows {
            let wfo_id = wfo_col
                .and_then(|c| c.str().ok())
                .and_then(|s| s.get(i))
                .map(|s| s.to_string());

            if let Some(wfo_id) = wfo_id {
                let envelope = SuitabilityEnvelope {
                    eive_l: get_val!(eive_l, i),
                    eive_l_source: eive_l_source.as_ref().and_then(|c| c.get(i)).map(|s| s.to_string()),
                    height_m: get_val!(height_m, i),

                    bio5_q05: get_val!(bio5_q05, i),
                    bio5_q50: get_val!(bio5_q50, i),
                    bio5_q95: get_val!(bio5_q95, i),
                    bio6_q05: get_val!(bio6_q05, i),
                    bio6_q50: get_val!(bio6_q50, i),
                    bio6_q95: get_val!(bio6_q95, i),

                    fd_q05: get_val!(fd_q05, i),
                    fd_q50: get_val!(fd_q50, i),
                    fd_q95: get_val!(fd_q95, i),
                    cfd_q05: get_val!(cfd_q05, i),
                    cfd_q50: get_val!(cfd_q50, i),
                    cfd_q95: get_val!(cfd_q95, i),
                    su_q50: get_val!(su_q50, i),
                    su_q95: get_val!(su_q95, i),
                    tr_q05: get_val!(tr_q05, i),
                    tr_q50: get_val!(tr_q50, i),
                    tr_q95: get_val!(tr_q95, i),
                    dtr_q05: get_val!(dtr_q05, i),
                    dtr_q50: get_val!(dtr_q50, i),
                    dtr_q95: get_val!(dtr_q95, i),
                    gsl_q05: get_val!(gsl_q05, i),
                    gsl_q50: get_val!(gsl_q50, i),
                    gsl_q95: get_val!(gsl_q95, i),

                    bio12_q05: get_val!(bio12_q05, i),
                    bio12_q50: get_val!(bio12_q50, i),
                    bio12_q95: get_val!(bio12_q95, i),
                    cdd_q05: get_val!(cdd_q05, i),
                    cdd_q50: get_val!(cdd_q50, i),
                    cdd_q95: get_val!(cdd_q95, i),
                    ww_q05: get_val!(ww_q05, i),
                    ww_q50: get_val!(ww_q50, i),
                    ww_q95: get_val!(ww_q95, i),
                    cwd_q05: get_val!(cwd_q05, i),
                    cwd_q50: get_val!(cwd_q50, i),
                    cwd_q95: get_val!(cwd_q95, i),

                    phh2o_q05: get_val!(phh2o_q05, i),
                    phh2o_q50: get_val!(phh2o_q50, i),
                    phh2o_q95: get_val!(phh2o_q95, i),
                    clay_q05: get_val!(clay_q05, i),
                    clay_q50: get_val!(clay_q50, i),
                    clay_q95: get_val!(clay_q95, i),
                    sand_q05: get_val!(sand_q05, i),
                    sand_q50: get_val!(sand_q50, i),
                    sand_q95: get_val!(sand_q95, i),
                    soc_q05: get_val!(soc_q05, i),
                    soc_q50: get_val!(soc_q50, i),
                    soc_q95: get_val!(soc_q95, i),
                    cec_q05: get_val!(cec_q05, i),
                    cec_q50: get_val!(cec_q50, i),
                    cec_q95: get_val!(cec_q95, i),

                    phh2o_5_15_q05: get_val!(phh2o_5_15_q05, i),
                    phh2o_5_15_q50: get_val!(phh2o_5_15_q50, i),
                    phh2o_5_15_q95: get_val!(phh2o_5_15_q95, i),
                    clay_5_15_q05: get_val!(clay_5_15_q05, i),
                    clay_5_15_q50: get_val!(clay_5_15_q50, i),
                    clay_5_15_q95: get_val!(clay_5_15_q95, i),
                    sand_5_15_q05: get_val!(sand_5_15_q05, i),
                    sand_5_15_q50: get_val!(sand_5_15_q50, i),
                    sand_5_15_q95: get_val!(sand_5_15_q95, i),

                    tier_1_tropical: tier_1.as_ref().and_then(|c| c.get(i)).unwrap_or(false),
                    tier_2_mediterranean: tier_2.as_ref().and_then(|c| c.get(i)).unwrap_or(false),
                    tier_3_humid_temperate: tier_3.as_ref().and_then(|c| c.get(i)).unwrap_or(false),
                    tier_4_continental: tier_4.as_ref().and_then(|c| c.get(i)).unwrap_or(false),
                    tier_5_boreal_polar: tier_5.as_ref().and_then(|c| c.get(i)).unwrap_or(false),
                    tier_6_arid: tier_6.as_ref().and_then(|c| c.get(i)).unwrap_or(false),
                };

                envelopes.insert(wfo_id, envelope);
            }
        }

        SuitabilityCache { envelopes }
    }

    /// Get envelope for a plant ID
    pub fn get(&self, wfo_id: &str) -> Option<&SuitabilityEnvelope> {
        self.envelopes.get(wfo_id)
    }

    /// Number of plants in cache
    pub fn len(&self) -> usize {
        self.envelopes.len()
    }

    /// Check if cache is empty
    pub fn is_empty(&self) -> bool {
        self.envelopes.is_empty()
    }
}
