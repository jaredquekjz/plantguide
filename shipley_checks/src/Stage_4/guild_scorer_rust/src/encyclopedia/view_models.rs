//! View Models for Encyclopedia API
//!
//! Structured data types for JSON API responses.
//! These are shared between Rust backend and Astro frontend via Typeshare.

use serde::Serialize;
use typeshare::typeshare;

/// Suitability fit level for visual badges
#[typeshare]
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Default)]
pub enum FitLevel {
    Optimal,   // Green - within Q25-Q75
    Good,      // Blue - within Q05-Q95
    Marginal,  // Amber - within Q01-Q99
    Outside,   // Red - outside range
    #[default]
    Unknown,   // Grey - no data
}

impl FitLevel {
    pub fn css_class(&self) -> &'static str {
        match self {
            FitLevel::Optimal => "bg-emerald-100 text-emerald-800 dark:bg-emerald-900 dark:text-emerald-200",
            FitLevel::Good => "bg-sky-100 text-sky-800 dark:bg-sky-900 dark:text-sky-200",
            FitLevel::Marginal => "bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200",
            FitLevel::Outside => "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
            FitLevel::Unknown => "bg-base-200 text-base-content/60",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            FitLevel::Optimal => "Ideal",
            FitLevel::Good => "Good",
            FitLevel::Marginal => "Marginal",
            FitLevel::Outside => "Outside",
            FitLevel::Unknown => "Unknown",
        }
    }

    pub fn icon(&self) -> &'static str {
        match self {
            FitLevel::Optimal => "check-circle",
            FitLevel::Good => "check",
            FitLevel::Marginal => "alert-triangle",
            FitLevel::Outside => "x-circle",
            FitLevel::Unknown => "help-circle",
        }
    }
}

// ============================================================================
// S1: Identity Card
// ============================================================================

/// Complete identity card data for the hero section
#[typeshare]
#[derive(Debug, Clone, Serialize, Default)]
pub struct IdentityCard {
    pub wfo_id: String,
    pub scientific_name: String,
    pub common_names: Vec<String>,
    pub chinese_names: Option<String>,
    pub family: String,
    pub genus: String,
    pub growth_type: String,
    pub growth_icon: GrowthIcon,
    pub native_climate: Option<String>,
    pub height: Option<HeightInfo>,
    pub leaf: Option<LeafInfo>,
    pub seed: Option<SeedInfo>,
    pub relatives: Vec<RelativeSpecies>,
    pub genus_species_count: usize,
}

#[typeshare]
#[derive(Debug, Clone, Copy, Serialize, Default)]
pub enum GrowthIcon {
    #[default]
    Tree,
    Shrub,
    Herb,
    Vine,
    Grass,
}

impl GrowthIcon {
    pub fn svg_path(&self) -> &'static str {
        match self {
            GrowthIcon::Tree => r#"<path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10Z"/><path d="M2 21c0-3 1.85-5.36 5.08-6C9.5 14.52 12 13 13 12"/>"#,
            GrowthIcon::Shrub => r#"<path d="M12 3a3 3 0 0 0-3 3c0 1.5 1 2.5 2 3.5-2.5.5-4 2-4 4 0 2.5 2 4.5 5 4.5s5-2 5-4.5c0-2-1.5-3.5-4-4 1-1 2-2 2-3.5a3 3 0 0 0-3-3Z"/><path d="M12 14v7"/>"#,
            GrowthIcon::Herb => r#"<path d="M12 2a5 5 0 0 1 5 5c0 2.5-2 4-5 5-3-1-5-2.5-5-5a5 5 0 0 1 5-5Z"/><path d="M12 12v10"/><path d="M9 18c-2 0-4-1-4-3s2-3 4-3"/><path d="M15 18c2 0 4-1 4-3s-2-3-4-3"/>"#,
            GrowthIcon::Vine => r#"<path d="M4 4c4 0 6 2 8 6 2-4 4-6 8-6"/><path d="M12 10c0 4 0 8 0 12"/><path d="M8 14c-2-2-4-2-4 0s2 4 4 4"/><path d="M16 14c2-2 4-2 4 0s-2 4-4 4"/>"#,
            GrowthIcon::Grass => r#"<path d="M12 22V10"/><path d="M6 22v-8c0-2 2-4 4-4"/><path d="M18 22v-8c0-2-2-4-4-4"/><path d="M9 6c0-2 1.5-4 3-4s3 2 3 4-1.5 4-3 4-3-2-3-4Z"/>"#,
        }
    }
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct HeightInfo {
    pub meters: f64,
    pub description: String, // e.g., "Large tree, needs significant space"
}

impl HeightInfo {
    pub fn meters_display(&self) -> String {
        format!("{:.1}m", self.meters)
    }
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct LeafInfo {
    pub leaf_type: String,   // Broadleaved, Needleleaved
    pub area_cm2: f64,
    pub description: String, // e.g., "Medium-sized"
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct SeedInfo {
    pub mass_g: f64,
    pub description: String, // e.g., "Medium seeds, bird food"
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct RelativeSpecies {
    pub wfo_id: String,
    pub scientific_name: String,
    pub common_name: String,
    pub relatedness: String, // "Close", "Moderate", "Distant"
    pub distance: f64,       // Raw phylogenetic distance (sum of branch lengths)
}

// ============================================================================
// S2: Growing Requirements
// ============================================================================

#[typeshare]
#[derive(Debug, Clone, Serialize, Default)]
pub struct RequirementsSection {
    pub light: LightRequirement,
    pub temperature: TemperatureSection,
    pub moisture: MoistureSection,
    pub soil: SoilSection,
    pub overall_suitability: Option<OverallSuitability>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct LightRequirement {
    pub eive_l: Option<f64>,
    pub category: String,      // "Full sun", "Partial shade", etc.
    pub description: String,   // Friendly explanation
    pub icon_fill_percent: u8, // 0-100 for visual indicator
    pub source_attribution: Option<String>, // Source of EIVE-L value (expert/imputed)
}

impl LightRequirement {
    pub fn eive_display(&self) -> Option<String> {
        self.eive_l.map(|v| format!("{:.1}", v))
    }
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct TemperatureSection {
    pub summary: String,
    pub details: Vec<String>,
    pub comparisons: Vec<ComparisonRow>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct MoistureSection {
    pub summary: String,
    pub rainfall_mm: Option<RangeValue>,
    pub dry_spell_days: Option<RangeValue>,
    pub wet_spell_days: Option<RangeValue>,
    pub comparisons: Vec<ComparisonRow>,
    pub advice: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct SoilSection {
    pub texture_summary: String,
    pub texture_details: Option<SoilTextureDetails>,  // Detailed sand/silt/clay
    // Topsoil (0-15cm) - the amendable layer
    pub ph: Option<SoilParameter>,
    pub fertility: Option<SoilParameter>,
    pub organic_carbon: Option<SoilParameter>,
    // Profile average (0-200cm) - underlying conditions
    pub profile_ph: Option<SoilParameter>,
    pub profile_fertility: Option<SoilParameter>,
    pub profile_organic_carbon: Option<SoilParameter>,
    pub comparisons: Vec<ComparisonRow>,
    pub advice: Vec<String>,
}

/// Detailed soil texture breakdown
#[derive(Debug, Clone, Serialize, Default)]
pub struct SoilTextureDetails {
    pub sand: TextureComponent,
    pub silt: TextureComponent,
    pub clay: TextureComponent,
    pub usda_class: String,        // "Loam", "Sandy Loam", etc.
    pub drainage: String,          // "Good", "Moderate", "Poor"
    pub water_retention: String,   // "Good", "Moderate", "Poor"
    pub interpretation: String,    // Human-readable summary
    pub triangle_x: Option<f64>,   // For soil texture triangle visualization
    pub triangle_y: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct TextureComponent {
    pub typical: f64,
    pub min: f64,
    pub max: f64,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct RangeValue {
    pub typical: f64,
    pub min: f64,
    pub max: f64,
    pub unit: String,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct SoilParameter {
    pub value: f64,
    pub range: String,
    pub interpretation: String,
}

impl SoilParameter {
    pub fn value_display(&self) -> String {
        format!("{:.1}", self.value)
    }
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ComparisonRow {
    pub parameter: String,
    pub local_value: String,
    pub plant_range: String,
    pub fit: FitLevel,
}

#[typeshare]
#[derive(Debug, Clone, Serialize, Default)]
pub struct OverallSuitability {
    pub location_name: String,
    pub score_percent: u8,
    pub verdict: String,      // "Excellent match", "Good with care", etc.
    pub key_concerns: Vec<String>,
    pub key_advantages: Vec<String>,
}

// ============================================================================
// S3: Maintenance Profile
// ============================================================================

#[derive(Debug, Clone, Serialize, Default)]
pub struct MaintenanceSection {
    pub level: MaintenanceLevel,
    pub csr_strategy: CsrStrategy,
    pub tasks: Vec<MaintenanceTask>,
    pub seasonal_notes: Vec<SeasonalNote>,
}

#[derive(Debug, Clone, Copy, Serialize, Default)]
pub enum MaintenanceLevel {
    #[default]
    Low,
    LowMedium,
    Medium,
    MediumHigh,
    High,
}

impl MaintenanceLevel {
    pub fn label(&self) -> &'static str {
        match self {
            MaintenanceLevel::Low => "Low",
            MaintenanceLevel::LowMedium => "Low-Medium",
            MaintenanceLevel::Medium => "Medium",
            MaintenanceLevel::MediumHigh => "Medium-High",
            MaintenanceLevel::High => "High",
        }
    }

    pub fn css_class(&self) -> &'static str {
        match self {
            MaintenanceLevel::Low => "bg-emerald-100 text-emerald-800 dark:bg-emerald-900 dark:text-emerald-200",
            MaintenanceLevel::LowMedium => "bg-teal-100 text-teal-800 dark:bg-teal-900 dark:text-teal-200",
            MaintenanceLevel::Medium => "bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200",
            MaintenanceLevel::MediumHigh => "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200",
            MaintenanceLevel::High => "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
        }
    }

    pub fn hours_per_year(&self) -> &'static str {
        match self {
            MaintenanceLevel::Low => "1-2 hrs/year",
            MaintenanceLevel::LowMedium => "2-3 hrs/year",
            MaintenanceLevel::Medium => "3-4 hrs/year",
            MaintenanceLevel::MediumHigh => "4-5 hrs/year",
            MaintenanceLevel::High => "5-7 hrs/year",
        }
    }
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct CsrStrategy {
    pub c_percent: f64,
    pub s_percent: f64,
    pub r_percent: f64,
    pub dominant: String,    // "Competitor", "Stress-tolerator", "Ruderal", "Balanced"
    pub description: String, // What this means for gardening
}

impl CsrStrategy {
    pub fn c_display(&self) -> String {
        format!("{:.0}%", self.c_percent)
    }
    pub fn s_display(&self) -> String {
        format!("{:.0}%", self.s_percent)
    }
    pub fn r_display(&self) -> String {
        format!("{:.0}%", self.r_percent)
    }
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct MaintenanceTask {
    pub name: String,
    pub frequency: String,
    pub importance: String, // "Essential", "Recommended", "Optional"
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct SeasonalNote {
    pub season: String,
    pub note: String,
}

// ============================================================================
// S4: Ecosystem Services
// ============================================================================

#[derive(Debug, Clone, Serialize, Default)]
pub struct EcosystemServices {
    pub ratings: Option<EcosystemRatings>,  // All 10 ecosystem service ratings
    pub services: Vec<ServiceCard>,
    pub nitrogen_fixer: bool,
    pub pollinator_score: Option<u8>,
    pub carbon_storage: Option<String>,
}

/// All 10 ecosystem service ratings from CSR-derived calculations
#[derive(Debug, Clone, Serialize, Default)]
pub struct EcosystemRatings {
    pub npp: ServiceRating,
    pub decomposition: ServiceRating,
    pub nutrient_cycling: ServiceRating,
    pub nutrient_retention: ServiceRating,
    pub nutrient_loss_risk: ServiceRating,
    pub carbon_biomass: ServiceRating,
    pub carbon_recalcitrant: ServiceRating,
    pub carbon_total: ServiceRating,
    pub erosion_protection: ServiceRating,
    pub nitrogen_fixation: ServiceRating,
    pub garden_value_summary: String,
}

/// Individual service rating with score and description
#[derive(Debug, Clone, Serialize, Default)]
pub struct ServiceRating {
    pub score: Option<f64>,       // 1.0 - 5.0 scale
    pub rating: String,           // "Very High", "High", "Moderate", "Low", "Very Low"
    pub description: String,      // Human-readable explanation
}

impl EcosystemServices {
    /// Returns true if pollinator_score > 60
    pub fn is_pollinator_magnet(&self) -> bool {
        self.pollinator_score.map_or(false, |s| s > 60)
    }
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ServiceCard {
    pub name: String,
    pub icon: ServiceIcon,
    pub value: String,
    pub description: String,
    pub confidence: String, // "High", "Medium", "Low"
}

#[derive(Debug, Clone, Copy, Serialize, Default)]
pub enum ServiceIcon {
    #[default]
    Pollination,
    CarbonStorage,
    SoilHealth,
    WaterRetention,
    Biodiversity,
    PestControl,
    Erosion,
    Shade,
    Food,
    Medicine,
}

impl ServiceIcon {
    pub fn svg_path(&self) -> &'static str {
        match self {
            ServiceIcon::Pollination => r#"<path d="M12 7.5a4.5 4.5 0 1 1 4.5 4.5M12 7.5A4.5 4.5 0 1 0 7.5 12M12 7.5V3m0 9.5L16 16m-4-4-4 4"/>"#,
            ServiceIcon::CarbonStorage => r#"<circle cx="12" cy="12" r="10"/><path d="M12 16v-4m0 0V8m0 4h4m-4 0H8"/>"#,
            ServiceIcon::SoilHealth => r#"<path d="M2 22 16 8m0 0 6-6m-6 6v6m0-6h6"/>"#,
            ServiceIcon::WaterRetention => r#"<path d="M12 2.69l5.66 5.66a8 8 0 1 1-11.31 0z"/>"#,
            ServiceIcon::Biodiversity => r#"<path d="M18 8c0 4-6 10-6 10S6 12 6 8a6 6 0 0 1 12 0"/><circle cx="12" cy="8" r="2"/>"#,
            ServiceIcon::PestControl => r#"<path d="M12 2a10 10 0 1 0 10 10 4 4 0 0 1-5-5 4 4 0 0 1-5-5"/><path d="M8.5 8.5v.01"/><path d="M16 15.5v.01"/><path d="M12 12v.01"/><path d="M11 17v.01"/><path d="M7 14v.01"/>"#,
            ServiceIcon::Erosion => r#"<path d="M2 22h20"/><path d="M3 22V8l4-2v16"/><path d="M11 22V2l4 2v18"/><path d="M19 22V8l4-2"/>"#,
            ServiceIcon::Shade => r#"<circle cx="12" cy="12" r="4"/><path d="M12 4v2"/><path d="M12 18v2"/><path d="M4 12h2"/><path d="M18 12h2"/>"#,
            ServiceIcon::Food => r#"<path d="M17 8c-4 0-8 4-8 8"/><path d="M6 8c4 0 8 4 8 8"/><path d="M12 4c0 4-4 8-8 8"/><path d="M12 4c0 4 4 8 8 8"/>"#,
            ServiceIcon::Medicine => r#"<path d="m9 9 6 6"/><path d="m15 9-6 6"/><rect width="12" height="12" x="6" y="6" rx="2"/>"#,
        }
    }

    pub fn color(&self) -> &'static str {
        match self {
            ServiceIcon::Pollination => "amber",
            ServiceIcon::CarbonStorage => "emerald",
            ServiceIcon::SoilHealth => "stone",
            ServiceIcon::WaterRetention => "sky",
            ServiceIcon::Biodiversity => "violet",
            ServiceIcon::PestControl => "rose",
            ServiceIcon::Erosion => "orange",
            ServiceIcon::Shade => "yellow",
            ServiceIcon::Food => "lime",
            ServiceIcon::Medicine => "pink",
        }
    }
}

// ============================================================================
// S5: Biological Interactions
// ============================================================================

#[derive(Debug, Clone, Serialize, Default)]
pub struct InteractionsSection {
    pub pollinators: OrganismGroup,
    pub herbivores: OrganismGroup,
    pub beneficial_predators: OrganismGroup,  // Natural pest control agents
    pub fungivores: OrganismGroup,            // Organisms that eat fungi (disease control)
    pub diseases: DiseaseGroup,
    pub beneficial_fungi: FungiGroup,
    pub mycorrhizal_type: String,
    pub mycorrhizal_details: Option<MycorrhizalDetails>,
}

/// Detailed mycorrhizal association info
#[derive(Debug, Clone, Serialize, Default)]
pub struct MycorrhizalDetails {
    pub association_type: String,    // "EMF", "AMF", "Dual", "None"
    pub species_count: usize,
    pub description: String,
    pub gardening_tip: String,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct OrganismGroup {
    pub title: String,
    pub icon: String,
    pub total_count: usize,
    pub categories: Vec<OrganismCategory>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct OrganismCategory {
    pub name: String,
    pub organisms: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct DiseaseGroup {
    pub pathogens: Vec<PathogenInfo>,
    pub resistance_notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct PathogenInfo {
    pub name: String,
    pub observation_count: usize,
    pub severity: String, // "Common", "Occasional", "Rare"
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct FungiGroup {
    pub mycoparasites: Vec<String>,
    pub entomopathogens: Vec<String>,
    pub endophytes_count: usize,
}

// ============================================================================
// S6: Companion Planting / Guild Potential
// ============================================================================

#[derive(Debug, Clone, Serialize, Default)]
pub struct CompanionSection {
    pub guild_roles: Vec<GuildRole>,
    pub guild_details: Option<GuildPotentialDetails>,  // Detailed guild analysis
    pub good_companions: Vec<CompanionPlant>,
    pub avoid_with: Vec<String>,
    pub planting_notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct GuildRole {
    pub role: String,        // "Nitrogen fixer", "Pollinator attractor", etc.
    pub strength: String,    // "Strong", "Moderate", "Weak"
    pub explanation: String,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct CompanionPlant {
    pub name: String,
    pub reason: String,
}

/// Detailed guild potential analysis matching markdown output
#[derive(Debug, Clone, Serialize, Default)]
pub struct GuildPotentialDetails {
    pub summary: GuildSummary,
    pub key_principles: Vec<String>,
    pub growth_compatibility: GrowthCompatibility,
    pub pest_control: PestControlAnalysis,
    pub disease_control: DiseaseControlAnalysis,
    pub mycorrhizal_network: MycorrhizalAnalysis,
    pub structural_role: StructuralRole,
    pub pollinator_support: PollinatorSupport,
    pub cautions: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct GuildSummary {
    pub taxonomy_guidance: String,
    pub growth_guidance: String,
    pub structure_role: String,
    pub mycorrhizal_guidance: String,
    pub pest_summary: String,
    pub disease_summary: String,
    pub pollinator_summary: String,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct GrowthCompatibility {
    pub csr_profile: String,           // "C: 45% | S: 41% | R: 14%"
    pub classification: String,        // "C-dominant (Competitor)"
    pub growth_form: String,
    pub height_m: f64,
    pub light_preference: f64,
    pub companion_strategy: String,
    pub avoid_pairing: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct PestControlAnalysis {
    pub pest_count: usize,
    pub pest_level: String,            // "High", "Moderate", "Low"
    pub pest_interpretation: String,
    pub predator_count: usize,
    pub predator_level: String,
    pub predator_interpretation: String,
    pub recommendations: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct DiseaseControlAnalysis {
    pub beneficial_fungi_count: usize,
    pub recommendations: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct MycorrhizalAnalysis {
    pub association_type: String,
    pub species_count: usize,
    pub network_type: String,
    pub recommendations: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct StructuralRole {
    pub layer: String,
    pub height_m: f64,
    pub growth_form: String,
    pub light_preference: f64,
    pub understory_recommendations: String,
    pub avoid_recommendations: String,
    pub benefits: String,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct PollinatorSupport {
    pub count: usize,
    pub level: String,
    pub interpretation: String,
    pub recommendations: String,
    pub benefits: Vec<String>,
}

// ============================================================================
// Full Encyclopedia Page
// ============================================================================

#[typeshare]
#[derive(Debug, Clone, Serialize, Default)]
pub struct EncyclopediaPageData {
    pub identity: IdentityCard,
    pub requirements: RequirementsSection,
    pub maintenance: MaintenanceSection,
    pub services: EcosystemServices,
    pub interactions: InteractionsSection,
    pub companion: CompanionSection,
    pub location: LocationInfo,
}

#[typeshare]
#[derive(Debug, Clone, Serialize, Default)]
pub struct LocationInfo {
    pub name: String,
    pub code: String,  // "london", "singapore", "helsinki"
    pub climate_zone: String,
}
