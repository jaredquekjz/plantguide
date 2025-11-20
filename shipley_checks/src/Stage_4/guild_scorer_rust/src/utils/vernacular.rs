//! Vernacular name handling utility
//!
//! Selects the best vernacular name based on user preferences:
//! 1. First English name (alphabetical)
//! 2. First Chinese name (alphabetical)
//! 3. None (fallback to scientific name only)

/// Get formatted display name for a plant
///
/// Returns: "Scientific Name (Vernacular Name)" or just "Scientific Name"
pub fn get_display_name(
    scientific_name: &str,
    vernacular_en: Option<&str>,
    vernacular_zh: Option<&str>,
) -> String {
    let vernacular = get_best_vernacular(vernacular_en, vernacular_zh);

    match vernacular {
        Some(v) => format!("{} ({})", scientific_name, v),
        None => scientific_name.to_string(),
    }
}

/// Select best vernacular name
///
/// Logic:
/// - English: Split by ';', trim, sort, take first
/// - Chinese: Split by ';', trim, sort, take first (fallback)
fn get_best_vernacular(
    vernacular_en: Option<&str>,
    vernacular_zh: Option<&str>,
) -> Option<String> {
    // Try English first
    if let Some(en_str) = vernacular_en {
        if !en_str.trim().is_empty() {
            if let Some(best_en) = pick_first_alphabetical(en_str) {
                return Some(best_en);
            }
        }
    }

    // Try Chinese fallback
    if let Some(zh_str) = vernacular_zh {
        if !zh_str.trim().is_empty() {
            if let Some(best_zh) = pick_first_alphabetical(zh_str) {
                return Some(best_zh);
            }
        }
    }

    None
}

/// Parse pipe-separated or semi-colon separated string, sort, and return first
fn pick_first_alphabetical(raw_str: &str) -> Option<String> {
    // Split by semi-colon (most common in this dataset) or pipe (just in case)
    let separators = [';', '|'];
    let mut names: Vec<&str> = raw_str
        .split(|c| separators.contains(&c))
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .collect();

    if names.is_empty() {
        return None;
    }

    names.sort();
    
    // Return the first one
    names.first().map(|s| s.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pick_first_alphabetical() {
        assert_eq!(
            pick_first_alphabetical("Silver Maple; River Maple; White Maple"),
            Some("River Maple".to_string())
        );
        assert_eq!(
            pick_first_alphabetical("  b_name  ; a_name "),
            Some("a_name".to_string())
        );
        assert_eq!(
            pick_first_alphabetical("single_name"),
            Some("single_name".to_string())
        );
        assert_eq!(pick_first_alphabetical(""), None);
        assert_eq!(pick_first_alphabetical("   ;   "), None);
    }

    #[test]
    fn test_get_display_name() {
        assert_eq!(
            get_display_name("Acer saccharinum", Some("Silver Maple; River Maple"), None),
            "Acer saccharinum (River Maple)"
        );
        assert_eq!(
            get_display_name("Acer saccharinum", None, Some("Chinese Name; Another Name")),
            "Acer saccharinum (Another Name)"
        );
        assert_eq!(
            get_display_name("Acer saccharinum", Some(""), Some("Chinese Name")),
            "Acer saccharinum (Chinese Name)"
        );
        assert_eq!(
            get_display_name("Acer saccharinum", None, None),
            "Acer saccharinum"
        );
    }
}
