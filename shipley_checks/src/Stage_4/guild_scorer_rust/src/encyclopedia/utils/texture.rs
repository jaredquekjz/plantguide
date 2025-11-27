//! USDA Soil Texture Classification
//!
//! Implements polygon-based texture classification using the USDA texture triangle.
//! Based on ggsoiltexture R package (https://github.com/Saryace/ggsoiltexture).
//!
//! Classification uses point-in-polygon (ray casting) algorithm on transformed
//! coordinates where: x = 0.5 * clay + silt, y = clay

/// A vertex in the texture triangle (ternary + transformed Cartesian coordinates)
#[derive(Clone, Copy, Debug)]
pub struct TextureVertex {
    pub clay: f64,
    pub sand: f64,
    pub silt: f64,
    pub x: f64,  // Transformed: 0.5 * clay + silt
    pub y: f64,  // Transformed: clay
}

impl TextureVertex {
    const fn new(clay: f64, sand: f64, silt: f64) -> Self {
        Self {
            clay,
            sand,
            silt,
            x: 0.5 * clay + silt,
            y: clay,
        }
    }
}

/// A USDA texture class defined by its polygon vertices
pub struct TextureClass {
    pub name: &'static str,
    pub vertices: &'static [TextureVertex],
}

/// Result of texture classification
#[derive(Debug, Clone)]
pub struct TextureClassification {
    pub class_name: String,
    pub clay: f64,
    pub sand: f64,
    pub silt: f64,
    pub x: f64,
    pub y: f64,
    pub drainage: &'static str,
    pub water_retention: &'static str,
    pub advice: &'static str,
}

// ============================================================================
// USDA Polygon Definitions (12 classes)
// Source: ggsoiltexture/data-raw/usda_polygons.csv
// ============================================================================

static SAND_VERTICES: &[TextureVertex] = &[
    TextureVertex { clay: 10.0, sand: 90.0, silt: 0.0, x: 5.0, y: 10.0 },
    TextureVertex { clay: 0.0, sand: 100.0, silt: 0.0, x: 0.0, y: 0.0 },
    TextureVertex { clay: 0.0, sand: 85.0, silt: 15.0, x: 15.0, y: 0.0 },
];

static LOAMY_SAND_VERTICES: &[TextureVertex] = &[
    TextureVertex { clay: 15.0, sand: 85.0, silt: 0.0, x: 7.5, y: 15.0 },
    TextureVertex { clay: 10.0, sand: 90.0, silt: 0.0, x: 5.0, y: 10.0 },
    TextureVertex { clay: 0.0, sand: 85.0, silt: 15.0, x: 15.0, y: 0.0 },
    TextureVertex { clay: 0.0, sand: 70.0, silt: 30.0, x: 30.0, y: 0.0 },
];

static SANDY_LOAM_VERTICES: &[TextureVertex] = &[
    TextureVertex { clay: 20.0, sand: 80.0, silt: 0.0, x: 10.0, y: 20.0 },
    TextureVertex { clay: 15.0, sand: 85.0, silt: 0.0, x: 7.5, y: 15.0 },
    TextureVertex { clay: 0.0, sand: 70.0, silt: 30.0, x: 30.0, y: 0.0 },
    TextureVertex { clay: 0.0, sand: 50.0, silt: 50.0, x: 50.0, y: 0.0 },
    TextureVertex { clay: 5.0, sand: 45.0, silt: 50.0, x: 52.5, y: 5.0 },
    TextureVertex { clay: 5.0, sand: 52.5, silt: 42.5, x: 45.0, y: 5.0 },
    TextureVertex { clay: 20.0, sand: 52.5, silt: 27.5, x: 37.5, y: 20.0 },
];

static LOAM_VERTICES: &[TextureVertex] = &[
    TextureVertex { clay: 27.5, sand: 45.0, silt: 27.5, x: 41.25, y: 27.5 },
    TextureVertex { clay: 20.0, sand: 52.5, silt: 27.5, x: 37.5, y: 20.0 },
    TextureVertex { clay: 5.0, sand: 52.5, silt: 42.5, x: 45.0, y: 5.0 },
    TextureVertex { clay: 5.0, sand: 45.0, silt: 50.0, x: 52.5, y: 5.0 },
    TextureVertex { clay: 27.5, sand: 22.5, silt: 50.0, x: 63.75, y: 27.5 },
];

static SILT_LOAM_VERTICES: &[TextureVertex] = &[
    TextureVertex { clay: 27.5, sand: 22.5, silt: 50.0, x: 63.75, y: 27.5 },
    TextureVertex { clay: 0.0, sand: 50.0, silt: 50.0, x: 50.0, y: 0.0 },
    TextureVertex { clay: 0.0, sand: 20.0, silt: 80.0, x: 80.0, y: 0.0 },
    TextureVertex { clay: 12.5, sand: 7.5, silt: 80.0, x: 86.25, y: 12.5 },
    TextureVertex { clay: 12.5, sand: 0.0, silt: 87.5, x: 93.75, y: 12.5 },
    TextureVertex { clay: 27.5, sand: 0.0, silt: 72.5, x: 86.25, y: 27.5 },
];

static SILT_VERTICES: &[TextureVertex] = &[
    TextureVertex { clay: 12.5, sand: 7.5, silt: 80.0, x: 86.25, y: 12.5 },
    TextureVertex { clay: 0.0, sand: 20.0, silt: 80.0, x: 80.0, y: 0.0 },
    TextureVertex { clay: 0.0, sand: 0.0, silt: 100.0, x: 100.0, y: 0.0 },
    TextureVertex { clay: 12.5, sand: 0.0, silt: 87.5, x: 93.75, y: 12.5 },
];

static SANDY_CLAY_LOAM_VERTICES: &[TextureVertex] = &[
    TextureVertex { clay: 35.0, sand: 65.0, silt: 0.0, x: 17.5, y: 35.0 },
    TextureVertex { clay: 20.0, sand: 80.0, silt: 0.0, x: 10.0, y: 20.0 },
    TextureVertex { clay: 20.0, sand: 52.5, silt: 27.5, x: 37.5, y: 20.0 },
    TextureVertex { clay: 27.5, sand: 45.0, silt: 27.5, x: 41.25, y: 27.5 },
    TextureVertex { clay: 35.0, sand: 45.0, silt: 20.0, x: 37.5, y: 35.0 },
];

static CLAY_LOAM_VERTICES: &[TextureVertex] = &[
    TextureVertex { clay: 40.0, sand: 45.0, silt: 15.0, x: 35.0, y: 40.0 },
    TextureVertex { clay: 27.5, sand: 45.0, silt: 27.5, x: 41.25, y: 27.5 },
    TextureVertex { clay: 27.5, sand: 20.0, silt: 52.5, x: 66.25, y: 27.5 },
    TextureVertex { clay: 40.0, sand: 20.0, silt: 40.0, x: 60.0, y: 40.0 },
];

static SILTY_CLAY_LOAM_VERTICES: &[TextureVertex] = &[
    TextureVertex { clay: 40.0, sand: 20.0, silt: 40.0, x: 60.0, y: 40.0 },
    TextureVertex { clay: 27.5, sand: 20.0, silt: 52.5, x: 66.25, y: 27.5 },
    TextureVertex { clay: 27.5, sand: 0.0, silt: 72.5, x: 86.25, y: 27.5 },
    TextureVertex { clay: 40.0, sand: 0.0, silt: 60.0, x: 80.0, y: 40.0 },
];

static SANDY_CLAY_VERTICES: &[TextureVertex] = &[
    TextureVertex { clay: 55.0, sand: 45.0, silt: 0.0, x: 27.5, y: 55.0 },
    TextureVertex { clay: 35.0, sand: 65.0, silt: 0.0, x: 17.5, y: 35.0 },
    TextureVertex { clay: 35.0, sand: 45.0, silt: 20.0, x: 37.5, y: 35.0 },
];

static SILTY_CLAY_VERTICES: &[TextureVertex] = &[
    TextureVertex { clay: 60.0, sand: 0.0, silt: 40.0, x: 70.0, y: 60.0 },
    TextureVertex { clay: 40.0, sand: 20.0, silt: 40.0, x: 60.0, y: 40.0 },
    TextureVertex { clay: 40.0, sand: 0.0, silt: 60.0, x: 80.0, y: 40.0 },
];

static CLAY_VERTICES: &[TextureVertex] = &[
    TextureVertex { clay: 100.0, sand: 0.0, silt: 0.0, x: 50.0, y: 100.0 },
    TextureVertex { clay: 55.0, sand: 45.0, silt: 0.0, x: 27.5, y: 55.0 },
    TextureVertex { clay: 40.0, sand: 45.0, silt: 15.0, x: 35.0, y: 40.0 },
    TextureVertex { clay: 40.0, sand: 20.0, silt: 40.0, x: 60.0, y: 40.0 },
    TextureVertex { clay: 60.0, sand: 0.0, silt: 40.0, x: 70.0, y: 60.0 },
];

/// All USDA texture classes in order (checked first to last)
pub static USDA_TEXTURE_CLASSES: &[TextureClass] = &[
    TextureClass { name: "Sand", vertices: SAND_VERTICES },
    TextureClass { name: "Loamy Sand", vertices: LOAMY_SAND_VERTICES },
    TextureClass { name: "Sandy Loam", vertices: SANDY_LOAM_VERTICES },
    TextureClass { name: "Loam", vertices: LOAM_VERTICES },
    TextureClass { name: "Silt Loam", vertices: SILT_LOAM_VERTICES },
    TextureClass { name: "Silt", vertices: SILT_VERTICES },
    TextureClass { name: "Sandy Clay Loam", vertices: SANDY_CLAY_LOAM_VERTICES },
    TextureClass { name: "Clay Loam", vertices: CLAY_LOAM_VERTICES },
    TextureClass { name: "Silty Clay Loam", vertices: SILTY_CLAY_LOAM_VERTICES },
    TextureClass { name: "Sandy Clay", vertices: SANDY_CLAY_VERTICES },
    TextureClass { name: "Silty Clay", vertices: SILTY_CLAY_VERTICES },
    TextureClass { name: "Clay", vertices: CLAY_VERTICES },
];

// ============================================================================
// Horticultural Properties by Texture Class
// ============================================================================

/// Get drainage, water retention, and advice for a texture class
fn get_texture_properties(class_name: &str) -> (&'static str, &'static str, &'static str) {
    match class_name {
        "Sand" => (
            "Excellent",
            "Very poor",
            "Add organic matter; water frequently; nutrients leach quickly"
        ),
        "Loamy Sand" => (
            "Very good",
            "Poor",
            "Light soil; frequent watering; may need amendments for heavy feeders"
        ),
        "Sandy Loam" => (
            "Good",
            "Fair",
            "Good general-purpose soil; most plants thrive"
        ),
        "Loam" => (
            "Good",
            "Good",
            "Ideal soil; balanced drainage and retention; suits most plants"
        ),
        "Silt Loam" => (
            "Moderate",
            "Good",
            "Rich soil; may compact when wet; avoid overwatering"
        ),
        "Silt" => (
            "Poor",
            "Very good",
            "Compacts easily; improve structure with organic matter; avoid heavy traffic"
        ),
        "Sandy Clay Loam" => (
            "Moderate",
            "Moderate",
            "Variable drainage; benefits from organic amendments"
        ),
        "Clay Loam" => (
            "Slow",
            "High",
            "Heavy but fertile; improve drainage with grit or organic matter"
        ),
        "Silty Clay Loam" => (
            "Slow",
            "High",
            "Fertile but heavy; needs careful water management; avoid waterlogging"
        ),
        "Sandy Clay" => (
            "Poor",
            "High",
            "Difficult texture; prone to waterlogging; amend heavily with organic matter"
        ),
        "Silty Clay" => (
            "Very poor",
            "Very high",
            "Very heavy; challenging drainage; consider raised beds"
        ),
        "Clay" => (
            "Very poor",
            "Very high",
            "Heavy soil; cracks when dry; needs significant amendment for most plants"
        ),
        _ => ("Unknown", "Unknown", ""),
    }
}

// ============================================================================
// Point-in-Polygon Algorithm (Ray Casting)
// ============================================================================

/// Transform ternary coordinates (clay, silt) to Cartesian (x, y)
fn to_cartesian(clay: f64, silt: f64) -> (f64, f64) {
    (0.5 * clay + silt, clay)
}

/// Ray casting algorithm for point-in-polygon test.
/// Returns true if point (x, y) is inside the polygon defined by vertices.
fn point_in_polygon(x: f64, y: f64, vertices: &[TextureVertex]) -> bool {
    let n = vertices.len();
    if n < 3 {
        return false;
    }

    let mut inside = false;
    let mut j = n - 1;

    for i in 0..n {
        let xi = vertices[i].x;
        let yi = vertices[i].y;
        let xj = vertices[j].x;
        let yj = vertices[j].y;

        // Check if ray from point crosses edge
        if ((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
            inside = !inside;
        }
        j = i;
    }

    inside
}

// ============================================================================
// Public Classification Functions
// ============================================================================

/// Classify soil texture from clay, sand, and silt percentages.
/// Returns None if inputs are invalid (don't sum to ~100%).
pub fn classify_texture(clay: f64, sand: f64, silt: f64) -> Option<TextureClassification> {
    // Validate input: must sum to approximately 100%
    let sum = clay + sand + silt;
    if (sum - 100.0).abs() > 1.0 {
        return None;
    }

    // Ensure non-negative values
    if clay < 0.0 || sand < 0.0 || silt < 0.0 {
        return None;
    }

    let (x, y) = to_cartesian(clay, silt);

    // Test each texture class polygon
    for class in USDA_TEXTURE_CLASSES.iter() {
        if point_in_polygon(x, y, class.vertices) {
            let (drainage, retention, advice) = get_texture_properties(class.name);
            return Some(TextureClassification {
                class_name: class.name.to_string(),
                clay,
                sand,
                silt,
                x,
                y,
                drainage,
                water_retention: retention,
                advice,
            });
        }
    }

    // Edge case: point exactly on boundary - try centroid approximation
    // Return most likely class based on dominant component
    let fallback_class = if clay > 40.0 {
        "Clay"
    } else if sand > 70.0 {
        if sand > 85.0 { "Sand" } else { "Loamy Sand" }
    } else if silt > 70.0 {
        if silt > 80.0 { "Silt" } else { "Silt Loam" }
    } else {
        "Loam"
    };

    let (drainage, retention, advice) = get_texture_properties(fallback_class);
    Some(TextureClassification {
        class_name: fallback_class.to_string(),
        clay,
        sand,
        silt,
        x,
        y,
        drainage,
        water_retention: retention,
        advice,
    })
}

/// Classify texture from clay and sand only (calculates silt).
pub fn classify_texture_from_clay_sand(clay: f64, sand: f64) -> Option<TextureClassification> {
    let silt = 100.0 - clay - sand;
    if silt < 0.0 {
        return None;
    }
    classify_texture(clay, sand, silt)
}

/// Get polygon vertices for a texture class (for UI rendering).
pub fn get_class_vertices(class_name: &str) -> Option<&'static [TextureVertex]> {
    USDA_TEXTURE_CLASSES
        .iter()
        .find(|c| c.name == class_name)
        .map(|c| c.vertices)
}

/// Get all texture class names.
pub fn get_all_class_names() -> Vec<&'static str> {
    USDA_TEXTURE_CLASSES.iter().map(|c| c.name).collect()
}

// ============================================================================
// Markdown Output Helpers
// ============================================================================

/// Generate a markdown texture table with sand/silt/clay and classification.
pub fn texture_table_markdown(
    sand_q50: f64,
    silt_q50: f64,
    clay_q50: f64,
    sand_range: Option<(f64, f64)>,
    silt_range: Option<(f64, f64)>,
    clay_range: Option<(f64, f64)>,
) -> String {
    let mut lines = Vec::new();

    // Table header
    lines.push("| Component | Typical | Range |".to_string());
    lines.push("|-----------|---------|-------|".to_string());

    // Sand row
    let sand_range_str = sand_range
        .map(|(lo, hi)| format!("{:.0}-{:.0}%", lo, hi))
        .unwrap_or_else(|| "-".to_string());
    lines.push(format!("| Sand | {:.0}% | {} |", sand_q50, sand_range_str));

    // Silt row
    let silt_range_str = silt_range
        .map(|(lo, hi)| format!("{:.0}-{:.0}%", lo, hi))
        .unwrap_or_else(|| "-".to_string());
    lines.push(format!("| Silt | {:.0}% | {} |", silt_q50, silt_range_str));

    // Clay row
    let clay_range_str = clay_range
        .map(|(lo, hi)| format!("{:.0}-{:.0}%", lo, hi))
        .unwrap_or_else(|| "-".to_string());
    lines.push(format!("| Clay | {:.0}% | {} |", clay_q50, clay_range_str));

    lines.push(String::new());

    // Classification
    if let Some(classification) = classify_texture(clay_q50, sand_q50, silt_q50) {
        lines.push(format!("**USDA Texture Class**: {}", classification.class_name));
        lines.push(format!("*{} - {}*", classification.class_name, classification.advice));
        lines.push(String::new());
        lines.push(format!(
            "**Triangle Coordinates**: (x: {:.1}, y: {:.1})",
            classification.x, classification.y
        ));
    }

    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sand_classification() {
        let result = classify_texture(5.0, 92.0, 3.0);
        assert!(result.is_some());
        assert_eq!(result.unwrap().class_name, "Sand");
    }

    #[test]
    fn test_loam_classification() {
        let result = classify_texture(20.0, 40.0, 40.0);
        assert!(result.is_some());
        assert_eq!(result.unwrap().class_name, "Loam");
    }

    #[test]
    fn test_clay_classification() {
        let result = classify_texture(60.0, 20.0, 20.0);
        assert!(result.is_some());
        assert_eq!(result.unwrap().class_name, "Clay");
    }

    #[test]
    fn test_invalid_sum() {
        let result = classify_texture(30.0, 30.0, 30.0); // Sums to 90
        assert!(result.is_none());
    }

    #[test]
    fn test_from_clay_sand() {
        let result = classify_texture_from_clay_sand(25.0, 35.0);
        assert!(result.is_some());
        // 25% clay, 35% sand, 40% silt -> Loam
        assert_eq!(result.unwrap().class_name, "Loam");
    }
}
