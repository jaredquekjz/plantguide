//! Vernacular name handling utility
//!
//! Uses pre-computed display_name from normalized vernaculars (Phase 1)
//! Fallback to runtime normalization for backwards compatibility

/// Get formatted display name for a plant
///
/// Priority:
/// 1. Pre-computed display_name (from Phase 1 normalization)
/// 2. Runtime normalization from vernacular_en/zh (backwards compat)
/// 3. Scientific name only
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

/// Get formatted display name for a plant (optimized with pre-computed display_name)
///
/// This is the preferred function when display_name column is available
///
/// Returns: "Scientific Name (Vernacular Name)" or "Scientific Name (Genus)" or just "Scientific Name"
pub fn get_display_name_optimized(
    scientific_name: &str,
    display_name: Option<&str>,
) -> String {
    match display_name {
        Some(d) if !d.trim().is_empty() && d != scientific_name => {
            format!("{} ({})", scientific_name, d)
        }
        _ => scientific_name.to_string(),
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

/// Parse pipe-separated or semi-colon separated string, sort, and return first in Title Case
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

    // Case-insensitive sort for consistent ordering
    names.sort_by_key(|s| s.to_lowercase());

    // Return the first one in Title Case for consistent capitalization
    names.first().map(|s| to_title_case(s))
}

/// Convert string to Title Case (first letter of each word capitalized)
fn to_title_case(s: &str) -> String {
    s.split_whitespace()
        .map(|word| {
            let mut chars = word.chars();
            match chars.next() {
                None => String::new(),
                Some(first) => {
                    first.to_uppercase().collect::<String>()
                        + &chars.as_str().to_lowercase()
                }
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// Format all vernacular names (not just first) with Title Case and comma separation
///
/// Used for comprehensive display of all common names
///
/// Returns: "Name1, Name2, Name3" (all in Title Case)
pub fn format_all_vernaculars(
    vernacular_en: Option<&str>,
    vernacular_zh: Option<&str>,
) -> String {
    // Try English first
    if let Some(en_str) = vernacular_en {
        if !en_str.trim().is_empty() {
            return format_vernacular_list(en_str);
        }
    }

    // Fallback to Chinese
    if let Some(zh_str) = vernacular_zh {
        if !zh_str.trim().is_empty() {
            return format_vernacular_list(zh_str);
        }
    }

    String::new()
}

/// Format a semicolon-separated list into comma-separated Title Case names
fn format_vernacular_list(raw_str: &str) -> String {
    let names: Vec<String> = raw_str
        .split(';')
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| to_title_case(s))
        .collect();

    names.join(", ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pick_first_alphabetical() {
        // Test case-insensitive sorting + Title Case normalization
        assert_eq!(
            pick_first_alphabetical("Silver Maple; River Maple; White Maple"),
            Some("River Maple".to_string())
        );
        assert_eq!(
            pick_first_alphabetical("Kona Coffee; Arabian Coffee; Arabica Coffee; Coffee"),
            Some("Arabian Coffee".to_string())
        );
        assert_eq!(
            pick_first_alphabetical("Grape Vine; common grape; wine grape"),
            Some("Common Grape".to_string())  // Case-insensitive sort, Title Case output
        );
        assert_eq!(
            pick_first_alphabetical("canker rose; dog rose; Dog-rose"),
            Some("Canker Rose".to_string())  // Lowercase input, Title Case output
        );
        assert_eq!(
            pick_first_alphabetical("  b_name  ; a_name "),
            Some("A_name".to_string())  // Title Case normalization
        );
        assert_eq!(
            pick_first_alphabetical("single_name"),
            Some("Single_name".to_string())  // Title Case
        );
        assert_eq!(pick_first_alphabetical(""), None);
        assert_eq!(pick_first_alphabetical("   ;   "), None);
    }

    #[test]
    fn test_to_title_case() {
        assert_eq!(to_title_case("wild strawberry"), "Wild Strawberry");
        assert_eq!(to_title_case("KONA COFFEE"), "Kona Coffee");
        assert_eq!(to_title_case("canker rose"), "Canker Rose");
        assert_eq!(to_title_case("Dog-rose"), "Dog-rose");  // Hyphenated words not split
        assert_eq!(to_title_case("English oak"), "English Oak");
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
        // Test Title Case normalization
        assert_eq!(
            get_display_name("Vitis vinifera", Some("Grape Vine; common grape; wine grape"), None),
            "Vitis vinifera (Common Grape)"
        );
    }
}
