//! Climate Tier Classification
//!
//! 6-tier Köppen climate grouping matching the guild scorer's tier system.
//! Used as a first-cut filter for plant suitability, heavily weighted in
//! the overall recommendation.
//!
//! Source: guild_scorer_rust/src/data.rs (tier columns)

/// Climate tier groupings (matches guild scorer tier columns)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ClimateTier {
    /// Tier 1: Tropical (Af, Am, Aw)
    /// Year-round warmth, no frost
    Tropical,

    /// Tier 2: Mediterranean (Csa, Csb, Csc)
    /// Dry summers, mild wet winters
    Mediterranean,

    /// Tier 3: Humid Temperate (Cfa, Cfb, Cfc, Cwa, Cwb, Cwc)
    /// Mild, adequate rainfall year-round
    HumidTemperate,

    /// Tier 4: Continental (Dfa, Dfb, Dsa, Dsb, Dwa, Dwb)
    /// Cold winters, warm summers
    Continental,

    /// Tier 5: Boreal/Polar (Dfc, Dfd, Dwc, Dwd, ET, EF)
    /// Short summers, long cold winters
    BorealPolar,

    /// Tier 6: Arid (BWh, BWk, BSh, BSk)
    /// Low rainfall, high evaporation
    Arid,
}

impl ClimateTier {
    /// Convert Köppen zone code to climate tier
    pub fn from_koppen(zone: &str) -> Self {
        let zone = zone.trim();
        let first_char = zone.chars().next();

        match first_char {
            Some('A') => ClimateTier::Tropical,
            Some('B') => ClimateTier::Arid,
            Some('C') => {
                // Mediterranean (Cs*) vs Humid Temperate (Cf*, Cw*)
                if zone.len() >= 2 && zone.chars().nth(1) == Some('s') {
                    ClimateTier::Mediterranean
                } else {
                    ClimateTier::HumidTemperate
                }
            }
            Some('D') => {
                // Continental (warmer D zones) vs Boreal (colder D zones)
                // Dfc, Dfd, Dwc, Dwd = Boreal; Dfa, Dfb, Dsa, Dsb, Dwa, Dwb = Continental
                if zone.len() >= 3 {
                    let third_char = zone.chars().nth(2);
                    if third_char == Some('c') || third_char == Some('d') {
                        ClimateTier::BorealPolar
                    } else {
                        ClimateTier::Continental
                    }
                } else {
                    // Default to Continental for incomplete codes
                    ClimateTier::Continental
                }
            }
            Some('E') => ClimateTier::BorealPolar,
            _ => {
                // Unknown zone - default to Humid Temperate
                ClimateTier::HumidTemperate
            }
        }
    }

    /// Get the tier column name used in plant parquet data
    pub fn parquet_column(&self) -> &'static str {
        match self {
            ClimateTier::Tropical => "tier_1_tropical",
            ClimateTier::Mediterranean => "tier_2_mediterranean",
            ClimateTier::HumidTemperate => "tier_3_humid_temperate",
            ClimateTier::Continental => "tier_4_continental",
            ClimateTier::BorealPolar => "tier_5_boreal_polar",
            ClimateTier::Arid => "tier_6_arid",
        }
    }

    /// Friendly name for display
    pub fn display_name(&self) -> &'static str {
        match self {
            ClimateTier::Tropical => "Tropical",
            ClimateTier::Mediterranean => "Mediterranean",
            ClimateTier::HumidTemperate => "Humid Temperate",
            ClimateTier::Continental => "Continental",
            ClimateTier::BorealPolar => "Boreal/Polar",
            ClimateTier::Arid => "Arid",
        }
    }

    /// Get adjacent (related) climate tiers
    /// Plants in adjacent tiers may adapt with some intervention
    pub fn adjacent_tiers(&self) -> &'static [ClimateTier] {
        match self {
            ClimateTier::Tropical => &[],  // Isolated - no adjacent
            ClimateTier::Mediterranean => &[ClimateTier::HumidTemperate, ClimateTier::Arid],
            ClimateTier::HumidTemperate => &[ClimateTier::Mediterranean, ClimateTier::Continental],
            ClimateTier::Continental => &[ClimateTier::HumidTemperate, ClimateTier::BorealPolar],
            ClimateTier::BorealPolar => &[ClimateTier::Continental],
            ClimateTier::Arid => &[ClimateTier::Mediterranean],
        }
    }

    /// Check if this tier is adjacent to another
    pub fn is_adjacent_to(&self, other: &ClimateTier) -> bool {
        self.adjacent_tiers().contains(other)
    }

    /// Get all tiers
    pub fn all() -> &'static [ClimateTier] {
        &[
            ClimateTier::Tropical,
            ClimateTier::Mediterranean,
            ClimateTier::HumidTemperate,
            ClimateTier::Continental,
            ClimateTier::BorealPolar,
            ClimateTier::Arid,
        ]
    }
}

/// Result of tier matching between local climate and plant occurrence
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TierMatchType {
    /// Local tier is in plant's observed tier list
    ExactMatch,

    /// Local tier is adjacent to a plant tier (e.g., Mediterranean ↔ HumidTemperate)
    AdjacentMatch,

    /// Plant not observed in local or adjacent tiers
    NoMatch,
}

impl TierMatchType {
    /// Display text for the match type
    pub fn display_text(&self) -> &'static str {
        match self {
            TierMatchType::ExactMatch => "Plant occurs in your climate zone",
            TierMatchType::AdjacentMatch => "Plant occurs in related climate zones",
            TierMatchType::NoMatch => "Plant not observed in your climate zone or related zones",
        }
    }
}

/// Occurrence fit based on climate tier comparison
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OccurrenceFit {
    /// Plant occurs in locations with your climate
    Observed,

    /// Plant occurs in related climate zones
    Related,

    /// Plant not found in similar climate zones
    NotObserved,
}

impl OccurrenceFit {
    /// Create from tier match type
    pub fn from_match_type(match_type: TierMatchType) -> Self {
        match match_type {
            TierMatchType::ExactMatch => OccurrenceFit::Observed,
            TierMatchType::AdjacentMatch => OccurrenceFit::Related,
            TierMatchType::NoMatch => OccurrenceFit::NotObserved,
        }
    }

    /// Display text
    pub fn display_text(&self) -> &'static str {
        match self {
            OccurrenceFit::Observed => "Observed",
            OccurrenceFit::Related => "Related",
            OccurrenceFit::NotObserved => "Not Observed",
        }
    }
}

/// Compare local climate tier against plant's observed tiers
///
/// # Arguments
/// * `local_tier` - The user's local climate tier
/// * `plant_tiers` - Boolean flags for each tier (from parquet tier columns)
///
/// # Returns
/// Tuple of (TierMatchType, matching tier if exact, closest adjacent if adjacent)
pub fn compare_climate_tiers(
    local_tier: ClimateTier,
    plant_tiers: &PlantTierFlags,
) -> TierMatchType {
    // Check for exact match
    if plant_tiers.has_tier(&local_tier) {
        return TierMatchType::ExactMatch;
    }

    // Check for adjacent match
    for adjacent in local_tier.adjacent_tiers() {
        if plant_tiers.has_tier(adjacent) {
            return TierMatchType::AdjacentMatch;
        }
    }

    TierMatchType::NoMatch
}

/// Plant tier flags from parquet boolean columns
#[derive(Debug, Clone, Default)]
pub struct PlantTierFlags {
    pub tropical: bool,
    pub mediterranean: bool,
    pub humid_temperate: bool,
    pub continental: bool,
    pub boreal_polar: bool,
    pub arid: bool,
}

impl PlantTierFlags {
    /// Check if plant has a specific tier
    pub fn has_tier(&self, tier: &ClimateTier) -> bool {
        match tier {
            ClimateTier::Tropical => self.tropical,
            ClimateTier::Mediterranean => self.mediterranean,
            ClimateTier::HumidTemperate => self.humid_temperate,
            ClimateTier::Continental => self.continental,
            ClimateTier::BorealPolar => self.boreal_polar,
            ClimateTier::Arid => self.arid,
        }
    }

    /// Get list of tiers where plant is observed
    pub fn observed_tiers(&self) -> Vec<ClimateTier> {
        let mut tiers = Vec::new();
        if self.tropical { tiers.push(ClimateTier::Tropical); }
        if self.mediterranean { tiers.push(ClimateTier::Mediterranean); }
        if self.humid_temperate { tiers.push(ClimateTier::HumidTemperate); }
        if self.continental { tiers.push(ClimateTier::Continental); }
        if self.boreal_polar { tiers.push(ClimateTier::BorealPolar); }
        if self.arid { tiers.push(ClimateTier::Arid); }
        tiers
    }

    /// Format observed tiers as comma-separated string
    pub fn observed_tiers_text(&self) -> String {
        self.observed_tiers()
            .iter()
            .map(|t| t.display_name())
            .collect::<Vec<_>>()
            .join(", ")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_koppen_to_tier() {
        assert_eq!(ClimateTier::from_koppen("Af"), ClimateTier::Tropical);
        assert_eq!(ClimateTier::from_koppen("Am"), ClimateTier::Tropical);
        assert_eq!(ClimateTier::from_koppen("BWh"), ClimateTier::Arid);
        assert_eq!(ClimateTier::from_koppen("BSk"), ClimateTier::Arid);
        assert_eq!(ClimateTier::from_koppen("Csa"), ClimateTier::Mediterranean);
        assert_eq!(ClimateTier::from_koppen("Csb"), ClimateTier::Mediterranean);
        assert_eq!(ClimateTier::from_koppen("Cfb"), ClimateTier::HumidTemperate);
        assert_eq!(ClimateTier::from_koppen("Cfa"), ClimateTier::HumidTemperate);
        assert_eq!(ClimateTier::from_koppen("Dfb"), ClimateTier::Continental);
        assert_eq!(ClimateTier::from_koppen("Dfa"), ClimateTier::Continental);
        assert_eq!(ClimateTier::from_koppen("Dfc"), ClimateTier::BorealPolar);
        assert_eq!(ClimateTier::from_koppen("Dfd"), ClimateTier::BorealPolar);
        assert_eq!(ClimateTier::from_koppen("ET"), ClimateTier::BorealPolar);
    }

    #[test]
    fn test_adjacency() {
        let mediterranean = ClimateTier::Mediterranean;
        assert!(mediterranean.is_adjacent_to(&ClimateTier::HumidTemperate));
        assert!(mediterranean.is_adjacent_to(&ClimateTier::Arid));
        assert!(!mediterranean.is_adjacent_to(&ClimateTier::Tropical));
        assert!(!mediterranean.is_adjacent_to(&ClimateTier::BorealPolar));

        // Tropical is isolated
        assert!(ClimateTier::Tropical.adjacent_tiers().is_empty());
    }

    #[test]
    fn test_tier_matching() {
        let plant = PlantTierFlags {
            tropical: false,
            mediterranean: true,
            humid_temperate: true,
            continental: false,
            boreal_polar: false,
            arid: false,
        };

        // Exact match
        assert_eq!(
            compare_climate_tiers(ClimateTier::Mediterranean, &plant),
            TierMatchType::ExactMatch
        );

        // Adjacent match (Continental is adjacent to HumidTemperate)
        assert_eq!(
            compare_climate_tiers(ClimateTier::Continental, &plant),
            TierMatchType::AdjacentMatch
        );

        // No match
        assert_eq!(
            compare_climate_tiers(ClimateTier::Tropical, &plant),
            TierMatchType::NoMatch
        );
    }
}
