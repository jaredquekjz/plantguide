//! Local Conditions definition and test locations
//!
//! Defines the LocalConditions struct representing a user's garden conditions,
//! plus 3 hardcoded test locations for prototype validation.
//!
//! ## Units Note
//!
//! AgroClim indicators (frost_days, tropical_nights) are stored as **dekadal means**
//! (average per 10-day period), matching how plant envelope data is stored.
//! This ensures correct comparison (both in same units).
//!
//! For display, these values are converted to annual estimates:
//! - Dekadal counts (FD, TR): multiply by 36 (36 dekads/year)
//! - GSL (growing season): already annual, no conversion

use super::climate_tier::ClimateTier;

/// User's local climate and soil conditions for suitability comparison.
///
/// All values represent conditions at a specific location, in units matching
/// the plant occurrence envelope data (q05/q50/q95) for correct comparison.
#[derive(Debug, Clone)]
pub struct LocalConditions {
    /// Location name for display (e.g., "London, UK")
    pub name: String,

    /// Köppen-Geiger climate zone code (e.g., "Cfb")
    pub koppen_zone: String,

    // ========================================================================
    // Temperature
    // ========================================================================

    /// Mean temperature of warmest month (°C) - BIO5 equivalent
    pub temp_warmest_month: f64,

    /// Mean temperature of coldest month (°C) - BIO6 equivalent
    pub temp_coldest_month: f64,

    /// Frost days - DEKADAL MEAN (not annual). Multiply by 36 for annual estimate.
    /// Days with min temp < 0°C, averaged per 10-day period. FD indicator.
    pub frost_days: f64,

    /// Tropical nights - DEKADAL MEAN (not annual). Multiply by 36 for annual estimate.
    /// Nights with min temp > 20°C, averaged per 10-day period. TR indicator.
    pub tropical_nights: f64,

    /// Growing season length (days) - already annual. GSL indicator.
    pub growing_season_days: f64,

    // ========================================================================
    // Moisture
    // ========================================================================

    /// Annual precipitation (mm) - BIO12 equivalent
    pub annual_rainfall_mm: f64,

    /// Maximum consecutive dry days per year - CDD
    pub consecutive_dry_days: f64,

    /// Maximum consecutive wet days per year - CWD
    pub consecutive_wet_days: f64,

    // ========================================================================
    // Soil (topsoil 0-15cm)
    // ========================================================================

    /// Soil pH (H2O)
    pub soil_ph: f64,

    /// Cation Exchange Capacity (cmol/kg) - fertility indicator
    pub soil_cec: f64,

    /// Clay content (%)
    pub soil_clay_pct: f64,

    /// Sand content (%)
    pub soil_sand_pct: f64,
}

impl LocalConditions {
    /// Get the climate tier for this location
    pub fn climate_tier(&self) -> ClimateTier {
        ClimateTier::from_koppen(&self.koppen_zone)
    }

    /// Calculate silt percentage (100 - clay - sand)
    pub fn soil_silt_pct(&self) -> f64 {
        (100.0 - self.soil_clay_pct - self.soil_sand_pct).max(0.0)
    }
}

// ============================================================================
// Hardcoded Test Locations
// ============================================================================
//
// Data extracted from the same rasters used for plant occurrence sampling:
// - WorldClim 2.1 (1970-2000): BIO5, BIO6, BIO12
// - Copernicus AgroClim (1981-2010 GFDL-ESM2M model): FD, TR, GSL, CDD, CWD
// - SoilGrids 2.0 (0-15cm average): pH, CEC, clay, sand
//
// IMPORTANT: FD and TR values are DEKADAL MEANS (not annual counts).
// This matches plant envelope data format for correct comparison.
// For display, multiply by 36 to get annual estimates.

/// Singapore - Tropical rainforest climate (Af)
/// Coordinates: 1.35°N, 103.82°E
pub fn singapore() -> LocalConditions {
    LocalConditions {
        name: "Singapore (Tropical)".to_string(),
        koppen_zone: "Af".to_string(),

        // Temperature (WorldClim 2.1)
        temp_warmest_month: 30.6,   // BIO5
        temp_coldest_month: 22.8,   // BIO6

        // Agroclimate (Copernicus 1981-2010) - FD/TR are dekadal means
        frost_days: 0.0,            // FD dekadal mean (×36 = 0 annual)
        tropical_nights: 10.1,      // TR dekadal mean (×36 = 364 annual)
        growing_season_days: 365.0, // GSL (already annual)

        // Moisture
        annual_rainfall_mm: 2302.0, // BIO12
        consecutive_dry_days: 8.6,  // CDD
        consecutive_wet_days: 36.3, // CWD

        // Soil (SoilGrids 0-15cm)
        soil_ph: 4.9,
        soil_cec: 14.7,
        soil_clay_pct: 37.5,
        soil_sand_pct: 33.8,
    }
}

/// London, UK - Temperate oceanic climate (Cfb)
/// Coordinates: 51.47°N, 0.45°W (climate) / 51.35°N, 0.30°W (soil - Surrey)
pub fn london() -> LocalConditions {
    LocalConditions {
        name: "London, UK (Temperate)".to_string(),
        koppen_zone: "Cfb".to_string(),

        // Temperature (WorldClim 2.1)
        temp_warmest_month: 22.9,   // BIO5
        temp_coldest_month: 2.0,    // BIO6

        // Agroclimate (Copernicus 1981-2010) - FD/TR are dekadal means
        frost_days: 1.7,            // FD dekadal mean (×36 = 61 annual)
        tropical_nights: 0.0,       // TR dekadal mean (×36 = 0 annual)
        growing_season_days: 305.0, // GSL (already annual)

        // Moisture
        annual_rainfall_mm: 593.0,  // BIO12
        consecutive_dry_days: 11.8, // CDD
        consecutive_wet_days: 8.2,  // CWD

        // Soil (SoilGrids 0-15cm, Surrey rural area)
        soil_ph: 6.1,
        soil_cec: 32.0,
        soil_clay_pct: 29.1,
        soil_sand_pct: 31.9,
    }
}

/// Helsinki, Finland - Humid continental climate (Dfb)
/// Coordinates: 60.17°N, 24.94°E
pub fn helsinki() -> LocalConditions {
    LocalConditions {
        name: "Helsinki, Finland (Boreal)".to_string(),
        koppen_zone: "Dfb".to_string(),

        // Temperature (WorldClim 2.1)
        temp_warmest_month: 20.5,   // BIO5
        temp_coldest_month: -8.1,   // BIO6

        // Agroclimate (Copernicus 1981-2010) - FD/TR are dekadal means
        frost_days: 4.5,            // FD dekadal mean (×36 = 162 annual)
        tropical_nights: 0.0,       // TR dekadal mean (×36 = 0 annual)
        growing_season_days: 170.5, // GSL (already annual)

        // Moisture
        annual_rainfall_mm: 649.0,  // BIO12
        consecutive_dry_days: 13.8, // CDD
        consecutive_wet_days: 7.3,  // CWD

        // Soil (typical Finnish sandy loam - no SoilGrids coverage)
        soil_ph: 5.5,
        soil_cec: 12.0,
        soil_clay_pct: 15.0,
        soil_sand_pct: 55.0,
    }
}

/// Get all test locations
pub fn test_locations() -> Vec<LocalConditions> {
    vec![singapore(), london(), helsinki()]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_climate_tiers() {
        assert_eq!(singapore().climate_tier(), ClimateTier::Tropical);
        assert_eq!(london().climate_tier(), ClimateTier::HumidTemperate);
        assert_eq!(helsinki().climate_tier(), ClimateTier::Continental);
    }

    #[test]
    fn test_silt_calculation() {
        let london = london();
        // 100 - 29.1 (clay) - 31.9 (sand) = 39% silt
        assert!((london.soil_silt_pct() - 39.0).abs() < 0.1);
    }
}
