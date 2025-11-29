//! Local Conditions definition and test locations
//!
//! Defines the LocalConditions struct representing a user's garden conditions,
//! plus 3 hardcoded test locations for prototype validation.

use super::climate_tier::ClimateTier;

/// User's local climate and soil conditions for suitability comparison.
///
/// All values represent annual/typical conditions at a specific location.
/// These are compared against a plant's occurrence envelope (q05/q50/q95).
#[derive(Debug, Clone)]
pub struct LocalConditions {
    /// Location name for display (e.g., "London, UK")
    pub name: String,

    /// Köppen-Geiger climate zone code (e.g., "Cfb")
    pub koppen_zone: String,

    // ========================================================================
    // Temperature (annual values)
    // ========================================================================

    /// Mean temperature of warmest month (°C) - BIO5 equivalent
    pub temp_warmest_month: f64,

    /// Mean temperature of coldest month (°C) - BIO6 equivalent
    pub temp_coldest_month: f64,

    /// Number of frost days per year (days with min temp < 0°C) - FD
    pub frost_days: f64,

    /// Number of tropical nights per year (nights with min temp > 20°C) - TR
    pub tropical_nights: f64,

    /// Growing season length (days with mean temp > 5°C) - GSL
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

/// Singapore - Tropical rainforest climate (Af)
/// Year-round warmth, no frost, high rainfall, year-round growing
pub fn singapore() -> LocalConditions {
    LocalConditions {
        name: "Singapore (Tropical)".to_string(),
        koppen_zone: "Af".to_string(),

        // Temperature
        temp_warmest_month: 31.0,
        temp_coldest_month: 26.0,
        frost_days: 0.0,
        tropical_nights: 365.0,  // Every night is warm
        growing_season_days: 365.0,  // Year-round growing

        // Moisture
        annual_rainfall_mm: 2340.0,  // Very wet
        consecutive_dry_days: 14.0,  // Short dry spells
        consecutive_wet_days: 10.0,

        // Soil (typical tropical laterite)
        soil_ph: 5.5,
        soil_cec: 12.0,
        soil_clay_pct: 35.0,
        soil_sand_pct: 40.0,
    }
}

/// London, UK - Temperate oceanic climate (Cfb)
/// Mild winters, cool summers, moderate rainfall
pub fn london() -> LocalConditions {
    LocalConditions {
        name: "London, UK (Temperate)".to_string(),
        koppen_zone: "Cfb".to_string(),

        // Temperature
        temp_warmest_month: 23.0,
        temp_coldest_month: 4.0,
        frost_days: 45.0,
        tropical_nights: 0.0,  // No warm nights
        growing_season_days: 280.0,

        // Moisture
        annual_rainfall_mm: 600.0,
        consecutive_dry_days: 20.0,
        consecutive_wet_days: 8.0,

        // Soil (typical London clay loam)
        soil_ph: 6.5,
        soil_cec: 20.0,
        soil_clay_pct: 25.0,
        soil_sand_pct: 40.0,
    }
}

/// Helsinki, Finland - Humid continental climate (Dfb)
/// Cold winters, mild summers, moderate rainfall
pub fn helsinki() -> LocalConditions {
    LocalConditions {
        name: "Helsinki, Finland (Boreal)".to_string(),
        koppen_zone: "Dfb".to_string(),

        // Temperature
        temp_warmest_month: 21.0,
        temp_coldest_month: -6.0,
        frost_days: 120.0,  // Many frost days
        tropical_nights: 0.0,
        growing_season_days: 180.0,  // Short growing season

        // Moisture
        annual_rainfall_mm: 650.0,
        consecutive_dry_days: 15.0,
        consecutive_wet_days: 12.0,

        // Soil (typical Finnish sandy loam)
        soil_ph: 5.8,
        soil_cec: 15.0,
        soil_clay_pct: 20.0,
        soil_sand_pct: 50.0,
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
        // 100 - 25 (clay) - 40 (sand) = 35% silt
        assert!((london.soil_silt_pct() - 35.0).abs() < 0.1);
    }
}
