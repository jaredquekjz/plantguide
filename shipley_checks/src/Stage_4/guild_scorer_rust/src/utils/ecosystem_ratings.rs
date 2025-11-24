/// Ecosystem Service Rating Utilities
///
/// Provides conversions between categorical ratings (Very High, High, Moderate, Low, Very Low)
/// and numeric scores (5.0, 4.0, 3.0, 2.0, 1.0) for community-weighted mean calculations.
///
/// Based on Shipley (2025) ecosystem services framework implemented in Stage 3.

/// Convert categorical rating to numeric score
///
/// # Rating Scale
/// - Very High = 5.0
/// - High = 4.0
/// - Moderate = 3.0
/// - Low = 2.0
/// - Very Low = 1.0
/// - Unable to Classify / empty / unknown = NaN
///
/// # Arguments
/// * `rating` - Categorical rating string
///
/// # Returns
/// Numeric score (1.0-5.0) or NaN for invalid/missing ratings
pub fn rating_to_numeric(rating: &str) -> f64 {
    match rating.trim() {
        "Very High" => 5.0,
        "High" => 4.0,
        "Moderate" => 3.0,
        "Low" => 2.0,
        "Very Low" => 1.0,
        "Unable to Classify" | "No Information" | "" => f64::NAN,
        _ => {
            // Unknown rating - return NaN and log warning
            eprintln!("Warning: Unknown ecosystem service rating: '{}'", rating);
            f64::NAN
        }
    }
}

/// Convert numeric score back to categorical rating
///
/// Uses midpoint thresholds:
/// - [4.5, 5.0] → Very High
/// - [3.5, 4.5) → High
/// - [2.5, 3.5) → Moderate
/// - [1.5, 2.5) → Low
/// - [1.0, 1.5) → Very Low
/// - NaN → Unable to Classify
///
/// # Arguments
/// * `score` - Numeric score (typically 1.0-5.0 or NaN)
///
/// # Returns
/// Categorical rating string
pub fn numeric_to_rating(score: f64) -> &'static str {
    if score.is_nan() {
        "Unable to Classify"
    } else if score >= 4.5 {
        "Very High"
    } else if score >= 3.5 {
        "High"
    } else if score >= 2.5 {
        "Moderate"
    } else if score >= 1.5 {
        "Low"
    } else {
        "Very Low"
    }
}

/// Calculate community-weighted mean rating for a guild
///
/// Converts categorical ratings to numeric, calculates mean (excluding NaN),
/// and converts back to categorical rating.
///
/// # Arguments
/// * `ratings` - Slice of categorical rating strings (one per plant in guild)
///
/// # Returns
/// Tuple of (numeric_score, categorical_rating)
/// - numeric_score: Mean of valid ratings (NaN if no valid ratings)
/// - categorical_rating: "Unable to Classify" if no valid ratings, otherwise converted rating
///
/// # Example
/// ```
/// let ratings = vec!["Very High", "High", "High"];
/// let (score, rating) = mean_rating(&ratings);
/// // score ≈ 4.33, rating = "High"
/// ```
pub fn mean_rating(ratings: &[&str]) -> (f64, &'static str) {
    let numeric: Vec<f64> = ratings
        .iter()
        .map(|r| rating_to_numeric(r))
        .filter(|x| !x.is_nan())
        .collect();

    if numeric.is_empty() {
        return (f64::NAN, "Unable to Classify");
    }

    let mean = numeric.iter().sum::<f64>() / numeric.len() as f64;
    (mean, numeric_to_rating(mean))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rating_to_numeric() {
        assert_eq!(rating_to_numeric("Very High"), 5.0);
        assert_eq!(rating_to_numeric("High"), 4.0);
        assert_eq!(rating_to_numeric("Moderate"), 3.0);
        assert_eq!(rating_to_numeric("Low"), 2.0);
        assert_eq!(rating_to_numeric("Very Low"), 1.0);
        assert!(rating_to_numeric("Unable to Classify").is_nan());
        assert!(rating_to_numeric("").is_nan());
    }

    #[test]
    fn test_numeric_to_rating() {
        assert_eq!(numeric_to_rating(5.0), "Very High");
        assert_eq!(numeric_to_rating(4.7), "Very High");
        assert_eq!(numeric_to_rating(4.5), "Very High");
        assert_eq!(numeric_to_rating(4.3), "High");
        assert_eq!(numeric_to_rating(3.5), "High");
        assert_eq!(numeric_to_rating(3.2), "Moderate");
        assert_eq!(numeric_to_rating(2.5), "Moderate");
        assert_eq!(numeric_to_rating(2.2), "Low");
        assert_eq!(numeric_to_rating(1.5), "Low");
        assert_eq!(numeric_to_rating(1.2), "Very Low");
        assert_eq!(numeric_to_rating(f64::NAN), "Unable to Classify");
    }

    #[test]
    fn test_mean_rating_all_same() {
        let ratings = vec!["High", "High", "High"];
        let (score, rating) = mean_rating(&ratings);
        assert_eq!(score, 4.0);
        assert_eq!(rating, "High");
    }

    #[test]
    fn test_mean_rating_mixed() {
        let ratings = vec!["Very High", "High", "High"];
        let (score, rating) = mean_rating(&ratings);
        assert!((score - 4.333).abs() < 0.01); // (5+4+4)/3 ≈ 4.33
        assert_eq!(rating, "High");
    }

    #[test]
    fn test_mean_rating_with_invalid() {
        let ratings = vec!["Very High", "Unable to Classify", "High"];
        let (score, rating) = mean_rating(&ratings);
        assert_eq!(score, 4.5); // (5+4)/2 = 4.5
        assert_eq!(rating, "Very High");
    }

    #[test]
    fn test_mean_rating_all_invalid() {
        let ratings = vec!["Unable to Classify", "Unable to Classify"];
        let (score, rating) = mean_rating(&ratings);
        assert!(score.is_nan());
        assert_eq!(rating, "Unable to Classify");
    }

    #[test]
    fn test_mean_rating_empty() {
        let ratings: Vec<&str> = vec![];
        let (score, rating) = mean_rating(&ratings);
        assert!(score.is_nan());
        assert_eq!(rating, "Unable to Classify");
    }

    #[test]
    fn test_mean_rating_boundary_cases() {
        // Test boundary between High and Very High (4.5)
        let ratings = vec!["Very High", "High", "High", "High"];
        let (score, rating) = mean_rating(&ratings);
        assert_eq!(score, 4.25); // (5+4+4+4)/4 = 4.25
        assert_eq!(rating, "High"); // < 4.5

        // Test exactly at boundary
        let ratings2 = vec!["Very High", "High"];
        let (score2, rating2) = mean_rating(&ratings2);
        assert_eq!(score2, 4.5); // (5+4)/2 = 4.5
        assert_eq!(rating2, "Very High"); // >= 4.5
    }
}
