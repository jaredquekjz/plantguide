//! Section 3: Maintenance Profile (Labor Requirements)
//!
//! Translates CSR strategy and plant traits into practical maintenance advice.
//!
//! Ported from R: shipley_checks/src/encyclopedia/sections/s3_maintenance_profile.R

use crate::encyclopedia::utils::categorization::{
    calculate_maintenance_level, get_csr_category, MaintenanceLevel, CsrCategory,
};

/// Plant data for maintenance profile
pub struct MaintenanceData {
    pub csr_c: Option<f64>,
    pub csr_s: Option<f64>,
    pub csr_r: Option<f64>,
    pub growth_form: Option<String>,
    pub height_m: Option<f64>,
    pub leaf_phenology: Option<String>,
    pub decomposition_rating: Option<f64>,
    pub decomposition_confidence: Option<f64>,
}

/// Generate Section 3: Maintenance Profile
pub fn generate_maintenance_profile(data: &MaintenanceData) -> String {
    let mut sections = Vec::new();

    sections.push("## Maintenance Profile".to_string());

    // Overall maintenance level
    let level = calculate_maintenance_level(
        data.csr_c.unwrap_or(f64::NAN),
        data.csr_s.unwrap_or(f64::NAN),
        data.csr_r.unwrap_or(f64::NAN),
    ).unwrap_or(MaintenanceLevel::Medium);

    sections.push(format!("\n**Maintenance Level: {}**", level.as_str()));

    // Growth rate
    sections.push(generate_growth_rate_advice(data));

    // Seasonal tasks
    sections.push(generate_seasonal_tasks(data));

    // Waste management
    sections.push(generate_waste_management(data));

    // Time commitment
    sections.push(estimate_time_commitment(&level, data));

    sections.join("\n\n")
}

fn generate_growth_rate_advice(data: &MaintenanceData) -> String {
    let (c, s, r) = (
        data.csr_c.unwrap_or(f64::NAN),
        data.csr_s.unwrap_or(f64::NAN),
        data.csr_r.unwrap_or(f64::NAN),
    );

    if c.is_nan() || s.is_nan() || r.is_nan() {
        return "🌿 **Growth Rate**: Unknown".to_string();
    }

    // Normalize
    let (c, s, r) = if c > 1.0 || s > 1.0 || r > 1.0 {
        (c / 100.0, s / 100.0, r / 100.0)
    } else {
        (c, s, r)
    };

    let csr_cat = get_csr_category(c, s, r).unwrap_or(CsrCategory::CSR);

    let (rate, desc) = if c > 0.6 {
        ("Fast", "Vigorous grower, can outcompete neighbors")
    } else if s > 0.6 {
        ("Slow", "Slow but steady growth, compact habit")
    } else if r > 0.6 {
        ("Rapid", "Quick to establish, opportunistic growth")
    } else {
        ("Moderate", "Steady growth rate")
    };

    let pruning = match data.growth_form.as_deref() {
        Some("tree") | Some("shrub") if c > 0.6 => "→ Annual pruning recommended to control vigor",
        Some("tree") | Some("shrub") if s > 0.6 => "→ Minimal pruning needed (every 2-3 years)",
        Some("tree") | Some("shrub") => "→ Prune as needed to maintain shape",
        Some("climber") if c > 0.6 => "→ Requires regular training and pruning",
        Some("climber") => "→ Light pruning to guide growth",
        _ if c > 0.6 => "→ May require cutting back to prevent spreading",
        _ => "→ Cut back after flowering if desired",
    };

    format!(
        "🌿 **Growth Rate**: {} ({} strategy)\n   → {}\n   {}",
        rate,
        csr_cat.as_str(),
        desc,
        pruning
    )
}

fn generate_seasonal_tasks(data: &MaintenanceData) -> String {
    let c = data.csr_c.map(|v| if v > 1.0 { v / 100.0 } else { v });

    let spring = match data.growth_form.as_deref() {
        Some("tree") | Some("shrub") => "Spring: Shape after frost risk passes",
        _ => "Spring: Remove dead growth, apply mulch",
    };

    let summer = match c {
        Some(c) if c > 0.6 => "Summer: Monitor for excessive growth, deadhead spent flowers",
        _ => "Summer: Minimal intervention, occasional deadheading",
    };

    let autumn = match data.leaf_phenology.as_deref() {
        Some("deciduous") => "Autumn: Rake fallen leaves for compost",
        _ => "Autumn: Minimal leaf cleanup (evergreen foliage)",
    };

    let winter = match data.growth_form.as_deref() {
        Some("tree") | Some("shrub") => "Winter: Structural pruning while dormant (if deciduous)",
        _ => "Winter: Protect from frost if tender",
    };

    format!(
        "🍂 **Seasonal Tasks**:\n   → {}\n   → {}\n   → {}\n   → {}",
        spring, summer, autumn, winter
    )
}

fn generate_waste_management(data: &MaintenanceData) -> String {
    let s = data.csr_s.map(|v| if v > 1.0 { v / 100.0 } else { v });

    let (decomp_desc, compost, mulch) = if let (Some(rating), Some(conf)) =
        (data.decomposition_rating, data.decomposition_confidence)
    {
        if conf >= 0.5 {
            if rating >= 7.0 {
                ("Fast-decomposing foliage",
                 "Excellent for compost; breaks down quickly",
                 "Good green mulch but short-lived")
            } else if rating >= 4.0 {
                ("Moderate decomposition rate",
                 "Suitable for compost; mix with other materials",
                 "Decent mulch material")
            } else {
                ("Slow-decomposing foliage",
                 "Add to compost in thin layers; may take time",
                 "Excellent for long-lasting mulch")
            }
        } else {
            get_decomp_from_csr(s)
        }
    } else {
        get_decomp_from_csr(s)
    };

    let volume = match data.leaf_phenology.as_deref() {
        Some("deciduous") => "Seasonal leaf drop creates moderate waste volume",
        _ => "Minimal waste volume (evergreen)",
    };

    format!(
        "♻️ **Waste Management**:\n   → {}\n   → {}\n   → {}\n   → {}",
        decomp_desc, compost, mulch, volume
    )
}

fn get_decomp_from_csr(csr_s: Option<f64>) -> (&'static str, &'static str, &'static str) {
    match csr_s {
        Some(s) if s > 0.6 => (
            "Likely slow-decomposing (stress-tolerator strategy)",
            "Tough foliage; shred before composting",
            "Good for long-lasting mulch"
        ),
        _ => (
            "Moderate decomposition rate",
            "Suitable for composting",
            "Can be used as mulch"
        ),
    }
}

fn estimate_time_commitment(level: &MaintenanceLevel, data: &MaintenanceData) -> String {
    let base_minutes: f64 = match level {
        MaintenanceLevel::Low => 15.0,
        MaintenanceLevel::LowMedium => 30.0,
        MaintenanceLevel::Medium => 60.0,
        MaintenanceLevel::MediumHigh => 120.0,
        MaintenanceLevel::High => 240.0,
    };

    let mut minutes = base_minutes;

    // Adjust for growth form
    match data.growth_form.as_deref() {
        Some("tree") | Some("shrub") => minutes *= 1.5,
        Some("climber") => minutes *= 2.0,
        _ => {}
    }

    // Adjust for deciduous
    if data.leaf_phenology.as_deref() == Some("deciduous") {
        minutes *= 1.3;
    }

    let time_text = if minutes < 60.0 {
        format!("~{} minutes per year", minutes.round() as i32)
    } else if minutes < 180.0 {
        format!("~{:.1} hours per year", minutes / 60.0)
    } else {
        format!("~{} hours per year", (minutes / 60.0).round() as i32)
    };

    format!("⏰ **Time Commitment**: {}", time_text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_maintenance_high_c() {
        let data = MaintenanceData {
            csr_c: Some(0.7),
            csr_s: Some(0.2),
            csr_r: Some(0.1),
            growth_form: Some("tree".to_string()),
            height_m: Some(10.0),
            leaf_phenology: Some("deciduous".to_string()),
            decomposition_rating: None,
            decomposition_confidence: None,
        };
        let profile = generate_maintenance_profile(&data);
        assert!(profile.contains("HIGH") || profile.contains("Fast"));
    }

    #[test]
    fn test_maintenance_low_s() {
        let data = MaintenanceData {
            csr_c: Some(0.2),
            csr_s: Some(0.7),
            csr_r: Some(0.1),
            growth_form: Some("shrub".to_string()),
            height_m: Some(2.0),
            leaf_phenology: Some("evergreen".to_string()),
            decomposition_rating: None,
            decomposition_confidence: None,
        };
        let profile = generate_maintenance_profile(&data);
        assert!(profile.contains("LOW") || profile.contains("Slow"));
    }
}
