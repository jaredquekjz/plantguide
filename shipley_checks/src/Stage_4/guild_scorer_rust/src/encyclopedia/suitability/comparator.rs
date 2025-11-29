//! Envelope Comparator
//!
//! Core logic for comparing local conditions against plant occurrence envelopes
//! defined by q05 (5th percentile), q50 (median), and q95 (95th percentile).

/// Result of comparing a local value to a plant's occurrence envelope
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EnvelopeFit {
    /// Local value is below the plant's observed range (local < q05)
    /// E.g., fewer frost days than where the plant typically occurs
    BelowRange,

    /// Local value is within the plant's observed range (q05 <= local <= q95)
    WithinRange,

    /// Local value exceeds the plant's observed range (local > q95)
    /// E.g., more frost days than where the plant typically occurs
    AboveRange,
}

impl EnvelopeFit {
    /// Simple display text
    pub fn display_text(&self) -> &'static str {
        match self {
            EnvelopeFit::BelowRange => "Below observed range",
            EnvelopeFit::WithinRange => "Within observed range",
            EnvelopeFit::AboveRange => "Above observed range",
        }
    }
}

/// Result of envelope comparison with additional context
#[derive(Debug, Clone)]
pub struct EnvelopeComparison {
    /// Whether local is below, within, or above the plant's range
    pub fit: EnvelopeFit,

    /// Local value being compared
    pub local_value: f64,

    /// Plant's 5th percentile (lower boundary)
    pub q05: f64,

    /// Plant's 50th percentile (typical/median)
    pub q50: f64,

    /// Plant's 95th percentile (upper boundary)
    pub q95: f64,

    /// Distance from nearest boundary (0 if within range)
    /// Expressed as absolute units
    pub distance_from_range: f64,

    /// Distance as fraction of the plant's range (q95 - q05)
    /// 0.0 if within range, positive fraction if outside
    pub distance_fraction: f64,
}

impl EnvelopeComparison {
    /// Check if local value is within the plant's typical range
    pub fn is_within_range(&self) -> bool {
        self.fit == EnvelopeFit::WithinRange
    }

    /// Check if local value is significantly outside the range
    /// (more than 50% of the range width beyond the boundary)
    pub fn is_significantly_outside(&self) -> bool {
        self.distance_fraction > 0.5
    }

    /// Check if local value is extremely outside the range
    /// (more than 100% of the range width beyond the boundary)
    pub fn is_extremely_outside(&self) -> bool {
        self.distance_fraction > 1.0
    }

    /// Format the comparison for display
    /// E.g., "45 frost days (plant range: 10-80, typical: 35)"
    pub fn format_with_context(&self, label: &str, unit: &str) -> String {
        let range_str = format!("{:.0}-{:.0}", self.q05, self.q95);
        format!(
            "{}: {:.0}{} (plant range: {}{}, typical: {:.0}{})",
            label, self.local_value, unit, range_str, unit, self.q50, unit
        )
    }
}

/// Compare a local value against a plant's occurrence envelope
///
/// # Arguments
/// * `local` - The local condition value
/// * `q05` - 5th percentile of plant's observed range
/// * `q50` - 50th percentile (median) of plant's observed range
/// * `q95` - 95th percentile of plant's observed range
///
/// # Returns
/// EnvelopeComparison with fit category and distance metrics
pub fn compare_to_envelope(local: f64, q05: f64, q50: f64, q95: f64) -> EnvelopeComparison {
    let range_width = (q95 - q05).max(0.001); // Avoid division by zero

    let (fit, distance) = if local < q05 {
        (EnvelopeFit::BelowRange, q05 - local)
    } else if local > q95 {
        (EnvelopeFit::AboveRange, local - q95)
    } else {
        (EnvelopeFit::WithinRange, 0.0)
    };

    EnvelopeComparison {
        fit,
        local_value: local,
        q05,
        q50,
        q95,
        distance_from_range: distance,
        distance_fraction: distance / range_width,
    }
}

/// Compare with fallback for missing quantile data
/// Returns None if any quantile is missing
pub fn compare_to_envelope_opt(
    local: f64,
    q05: Option<f64>,
    q50: Option<f64>,
    q95: Option<f64>,
) -> Option<EnvelopeComparison> {
    match (q05, q50, q95) {
        (Some(q05), Some(q50), Some(q95)) => Some(compare_to_envelope(local, q05, q50, q95)),
        _ => None,
    }
}

// ============================================================================
// Severity Assessment Helpers
// ============================================================================

/// Threshold categories for temperature-related comparisons
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TemperatureSeverity {
    /// Within or close to observed range
    Acceptable,
    /// Moderately outside range - interventions recommended
    Marginal,
    /// Significantly outside range - major interventions required
    Challenging,
    /// Extremely outside range - not recommended
    Extreme,
}

impl TemperatureSeverity {
    /// Determine severity for frost days (more frost = colder)
    pub fn from_frost_comparison(comp: &EnvelopeComparison) -> Self {
        match comp.fit {
            EnvelopeFit::WithinRange => TemperatureSeverity::Acceptable,
            EnvelopeFit::BelowRange => {
                // Fewer frost days than typical (warmer) - usually fine
                TemperatureSeverity::Acceptable
            }
            EnvelopeFit::AboveRange => {
                // More frost days (colder)
                if comp.distance_from_range > 50.0 {
                    TemperatureSeverity::Extreme
                } else if comp.distance_from_range > 30.0 {
                    TemperatureSeverity::Challenging
                } else if comp.distance_from_range > 10.0 {
                    TemperatureSeverity::Marginal
                } else {
                    TemperatureSeverity::Acceptable
                }
            }
        }
    }

    /// Determine severity for tropical nights (more warm nights = hotter)
    pub fn from_tropical_nights_comparison(comp: &EnvelopeComparison) -> Self {
        match comp.fit {
            EnvelopeFit::WithinRange => TemperatureSeverity::Acceptable,
            EnvelopeFit::BelowRange => {
                // Fewer warm nights - usually fine for plants
                TemperatureSeverity::Acceptable
            }
            EnvelopeFit::AboveRange => {
                // More warm nights than typical
                if comp.distance_from_range > 100.0 {
                    TemperatureSeverity::Extreme
                } else if comp.distance_from_range > 50.0 {
                    TemperatureSeverity::Challenging
                } else if comp.distance_from_range > 20.0 {
                    TemperatureSeverity::Marginal
                } else {
                    TemperatureSeverity::Acceptable
                }
            }
        }
    }

    /// Determine severity for growing season (shorter = more challenging)
    pub fn from_growing_season_comparison(comp: &EnvelopeComparison) -> Self {
        match comp.fit {
            EnvelopeFit::WithinRange => TemperatureSeverity::Acceptable,
            EnvelopeFit::AboveRange => {
                // Longer growing season - might lack dormancy
                if comp.distance_from_range > 60.0 {
                    TemperatureSeverity::Challenging
                } else {
                    TemperatureSeverity::Acceptable
                }
            }
            EnvelopeFit::BelowRange => {
                // Shorter growing season
                if comp.distance_from_range > 60.0 {
                    TemperatureSeverity::Extreme
                } else if comp.distance_from_range > 30.0 {
                    TemperatureSeverity::Challenging
                } else {
                    TemperatureSeverity::Marginal
                }
            }
        }
    }
}

/// Threshold categories for moisture comparisons
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MoistureSeverity {
    /// Within or close to observed range
    Acceptable,
    /// Drier or wetter - regular intervention needed
    Marginal,
    /// Significantly drier/wetter - intensive intervention
    Challenging,
    /// Extremely different - may not be viable
    Extreme,
}

impl MoistureSeverity {
    /// Determine severity for annual rainfall
    pub fn from_rainfall_comparison(comp: &EnvelopeComparison) -> Self {
        match comp.fit {
            EnvelopeFit::WithinRange => MoistureSeverity::Acceptable,
            EnvelopeFit::BelowRange => {
                // Drier than typical
                let ratio = comp.local_value / comp.q05.max(1.0);
                if ratio < 0.5 {
                    MoistureSeverity::Extreme
                } else if ratio < 0.75 {
                    MoistureSeverity::Challenging
                } else {
                    MoistureSeverity::Marginal
                }
            }
            EnvelopeFit::AboveRange => {
                // Wetter than typical
                let ratio = comp.local_value / comp.q95.max(1.0);
                if ratio > 2.0 {
                    MoistureSeverity::Extreme
                } else if ratio > 1.5 {
                    MoistureSeverity::Challenging
                } else {
                    MoistureSeverity::Marginal
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_within_range() {
        let comp = compare_to_envelope(50.0, 30.0, 50.0, 70.0);
        assert_eq!(comp.fit, EnvelopeFit::WithinRange);
        assert_eq!(comp.distance_from_range, 0.0);
        assert!(comp.is_within_range());
    }

    #[test]
    fn test_below_range() {
        let comp = compare_to_envelope(20.0, 30.0, 50.0, 70.0);
        assert_eq!(comp.fit, EnvelopeFit::BelowRange);
        assert_eq!(comp.distance_from_range, 10.0); // 30 - 20 = 10
        assert!(!comp.is_within_range());
    }

    #[test]
    fn test_above_range() {
        let comp = compare_to_envelope(80.0, 30.0, 50.0, 70.0);
        assert_eq!(comp.fit, EnvelopeFit::AboveRange);
        assert_eq!(comp.distance_from_range, 10.0); // 80 - 70 = 10
    }

    #[test]
    fn test_distance_fraction() {
        // Range is 30-70, width = 40
        // Local is 90, distance = 20, fraction = 20/40 = 0.5
        let comp = compare_to_envelope(90.0, 30.0, 50.0, 70.0);
        assert!((comp.distance_fraction - 0.5).abs() < 0.01);
        assert!(comp.is_significantly_outside());
        assert!(!comp.is_extremely_outside());

        // Local is 110, distance = 40, fraction = 40/40 = 1.0
        let comp2 = compare_to_envelope(110.0, 30.0, 50.0, 70.0);
        assert!((comp2.distance_fraction - 1.0).abs() < 0.01);
        assert!(comp2.is_extremely_outside());
    }

    #[test]
    fn test_frost_severity() {
        // Within range
        let comp = compare_to_envelope(45.0, 30.0, 50.0, 70.0);
        assert_eq!(TemperatureSeverity::from_frost_comparison(&comp), TemperatureSeverity::Acceptable);

        // Slightly more frost than typical
        let comp = compare_to_envelope(85.0, 30.0, 50.0, 70.0);
        assert_eq!(TemperatureSeverity::from_frost_comparison(&comp), TemperatureSeverity::Marginal);

        // Much more frost
        let comp = compare_to_envelope(120.0, 30.0, 50.0, 70.0);
        assert_eq!(TemperatureSeverity::from_frost_comparison(&comp), TemperatureSeverity::Extreme);
    }
}
