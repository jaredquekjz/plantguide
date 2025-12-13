//! Structural Diversity Profile Analysis
//!
//! Transforms M6Result into a frontend-friendly profile with:
//! - Vertical layers (canopy, understory, shrub, ground)
//! - Plants per layer with height and light preferences
//! - Stratification quality assessment

use serde::{Deserialize, Serialize};
use crate::metrics::M6Result;

/// Light preference classification
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum LightPreference {
    ShadeTolerant,  // EIVE-L < 3.2
    Flexible,       // EIVE-L 3.2-7.47
    SunLoving,      // EIVE-L > 7.47
    Unknown,        // No data
}

impl LightPreference {
    pub fn from_eive_l(light: Option<f64>) -> Self {
        match light {
            Some(l) if l < 3.2 => LightPreference::ShadeTolerant,
            Some(l) if l > 7.47 => LightPreference::SunLoving,
            Some(_) => LightPreference::Flexible,
            None => LightPreference::Unknown,
        }
    }
}

/// A plant in a structural layer
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LayerPlant {
    pub name: String,
    pub height_m: f64,
    pub light_pref: Option<f64>,
    pub light_class: LightPreference,
}

/// A structural layer (canopy, understory, etc.)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StructuralLayer {
    pub name: String,           // "Canopy", "Understory", "Shrub", "Ground"
    pub height_range: String,   // ">15m", "5-15m", "1-5m", "<1m"
    pub plants: Vec<LayerPlant>,
}

/// Structural diversity profile for frontend
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StructuralDiversityProfile {
    /// Total height range in meters
    pub height_range: f64,
    /// Number of unique growth forms
    pub n_forms: usize,
    /// Stratification quality (0-1)
    pub stratification_quality: f64,
    /// Quality label
    pub stratification_label: String,
    /// Form diversity score (0-1)
    pub form_diversity: f64,
    /// Vertical layers with plants
    pub layers: Vec<StructuralLayer>,
    /// Light compatibility counts
    pub shade_tolerant_count: usize,
    pub flexible_count: usize,
    pub sun_loving_count: usize,
}

/// Analyze structural diversity from M6Result
pub fn analyze_structural_diversity(m6: &M6Result) -> Option<StructuralDiversityProfile> {
    // Collect all plants from growth form groups
    let all_plants: Vec<&crate::metrics::m6_structural_diversity::PlantHeight> =
        m6.growth_form_groups.iter().flat_map(|g| g.plants.iter()).collect();

    if all_plants.is_empty() {
        return None;
    }

    // Categorize into layers
    let mut canopy = Vec::new();     // >15m
    let mut understory = Vec::new(); // 5-15m
    let mut shrub = Vec::new();      // 1-5m
    let mut ground = Vec::new();     // <1m

    for plant in &all_plants {
        let layer_plant = LayerPlant {
            name: plant.name.clone(),
            height_m: plant.height_m,
            light_pref: plant.light_pref,
            light_class: LightPreference::from_eive_l(plant.light_pref),
        };

        if plant.height_m >= 15.0 {
            canopy.push(layer_plant);
        } else if plant.height_m >= 5.0 {
            understory.push(layer_plant);
        } else if plant.height_m >= 1.0 {
            shrub.push(layer_plant);
        } else {
            ground.push(layer_plant);
        }
    }

    // Sort each layer by height descending
    canopy.sort_by(|a, b| b.height_m.partial_cmp(&a.height_m).unwrap_or(std::cmp::Ordering::Equal));
    understory.sort_by(|a, b| b.height_m.partial_cmp(&a.height_m).unwrap_or(std::cmp::Ordering::Equal));
    shrub.sort_by(|a, b| b.height_m.partial_cmp(&a.height_m).unwrap_or(std::cmp::Ordering::Equal));
    ground.sort_by(|a, b| b.height_m.partial_cmp(&a.height_m).unwrap_or(std::cmp::Ordering::Equal));

    // Build layers (only include non-empty)
    let mut layers = Vec::new();
    if !canopy.is_empty() {
        layers.push(StructuralLayer {
            name: "Canopy".to_string(),
            height_range: ">15m".to_string(),
            plants: canopy,
        });
    }
    if !understory.is_empty() {
        layers.push(StructuralLayer {
            name: "Understory".to_string(),
            height_range: "5-15m".to_string(),
            plants: understory,
        });
    }
    if !shrub.is_empty() {
        layers.push(StructuralLayer {
            name: "Shrub".to_string(),
            height_range: "1-5m".to_string(),
            plants: shrub,
        });
    }
    if !ground.is_empty() {
        layers.push(StructuralLayer {
            name: "Ground".to_string(),
            height_range: "<1m".to_string(),
            plants: ground,
        });
    }

    // Count light preferences
    let shade_tolerant_count = all_plants.iter()
        .filter(|p| p.light_pref.map_or(false, |l| l < 3.2))
        .count();
    let flexible_count = all_plants.iter()
        .filter(|p| p.light_pref.map_or(false, |l| l >= 3.2 && l <= 7.47))
        .count();
    let sun_loving_count = all_plants.iter()
        .filter(|p| p.light_pref.map_or(false, |l| l > 7.47))
        .count();

    // Quality label
    let stratification_label = if m6.stratification_quality >= 0.8 {
        "Excellent".to_string()
    } else if m6.stratification_quality >= 0.6 {
        "Good".to_string()
    } else if m6.stratification_quality >= 0.4 {
        "Fair".to_string()
    } else {
        "Poor".to_string()
    };

    Some(StructuralDiversityProfile {
        height_range: m6.height_range,
        n_forms: m6.n_forms,
        stratification_quality: m6.stratification_quality,
        stratification_label,
        form_diversity: m6.form_diversity,
        layers,
        shade_tolerant_count,
        flexible_count,
        sun_loving_count,
    })
}
