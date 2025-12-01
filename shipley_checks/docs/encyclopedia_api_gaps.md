# Encyclopedia API Enhancement Requirements

This document identifies fields present in the markdown encyclopedia reports but missing from the JSON API.

**Reference files:**
- Markdown: `shipley_checks/stage4/reports/encyclopedia/encyclopedia_Quercus_robur.md`
- API endpoint: `/api/encyclopedia/:wfo_id`

---

## 1. Ecosystem Services (10 metrics missing)

The markdown has detailed ecosystem service ratings with explanations. The API returns only:
```json
"services": {
  "nitrogen_fixer": false,
  "pollinator_score": null,
  "carbon_storage": null,
  "services": []
}
```

### Required additions to API:

| Metric | Markdown Value | Type | Description |
|--------|---------------|------|-------------|
| `npp_score` | 5.0 | float | Net Primary Productivity (1-5 scale) |
| `npp_description` | "Rapid growth produces abundant biomass..." | string | NPP interpretation |
| `decomposition_score` | 4.0 | float | Decomposition Rate (1-5 scale) |
| `decomposition_description` | "Fast litter breakdown returns nutrients..." | string | Decomposition interpretation |
| `nutrient_cycling_score` | 4.0 | float | Nutrient Cycling (1-5 scale) |
| `nutrient_retention_score` | 4.0 | float | Nutrient Retention (1-5 scale) |
| `nutrient_loss_risk` | 3.0 | float | Nutrient Loss Risk (1-5 scale) |
| `biomass_carbon_score` | 4.0 | float | Living Biomass carbon (1-5 scale) |
| `biomass_carbon_description` | "large, dense growth captures significant CO₂" | string | Biomass interpretation |
| `soil_carbon_score` | 3.0 | float | Long-term Soil Carbon (1-5 scale) |
| `total_carbon_score` | 4.0 | float | Total Carbon Benefit (1-5 scale) |
| `erosion_protection_score` | 4.0 | float | Erosion Protection (1-5 scale) |
| `erosion_protection_description` | "Extensive roots and ground cover anchor soil..." | string | Erosion interpretation |
| `garden_value_summary` | "Good choice - good carbon storage..." | string | Overall garden value summary |

---

## 2. Guild Potential (6 subsections missing)

The markdown has extensive guild-building guidance. The API returns only:
```json
"companion": {
  "guild_roles": [{"role": "Mycorrhizal Hub", "explanation": "...", "strength": "Moderate"}],
  "good_companions": [],
  "avoid_with": [],
  "planting_notes": []
}
```

### Required additions to API:

#### 2.1 At-a-Glance Summary Table
```json
"guild_summary": {
  "taxonomy_guidance": "Seek different families",
  "growth_guidance": "Avoid C-C pairs",
  "structure_role": "Canopy (27.1m) - Shade provider",
  "mycorrhizal_guidance": "Connect with EMF plants",
  "pest_summary": "19 pests, 2 predators - Benefits from predator plants",
  "disease_summary": "No documented antagonists",
  "pollinator_summary": "14 species - Typical"
}
```

#### 2.2 Key Principles (array)
```json
"key_principles": [
  "Diversify taxonomy - seek plants from different families than Fagaceae",
  "Growth compatibility - avoid other C-dominant plants at same height",
  "Layer plants - pair with shade-tolerant understory",
  "Fungal network - seek other EMF-associated plants for network benefits"
]
```

#### 2.3 Growth Compatibility Details
```json
"growth_compatibility": {
  "csr_profile": "C: 45% | S: 41% | R: 14%",
  "classification": "C-dominant (Competitor) (spread-based)",
  "growth_form": "Tree",
  "height_m": 27.1,
  "light_preference": 6.2,
  "companion_strategy": "Canopy competitor. Pairs well with shade-tolerant understory (EIVE-L < 5).",
  "avoid_pairing": ["Other C-dominant plants at same layer", "Sun-loving plants in shade zone"]
}
```

#### 2.4 Pest Control Section
```json
"pest_control": {
  "pest_count": 19,
  "pest_level": "High",
  "pest_interpretation": "Multiple pest species; monitor closely",
  "predator_count": 2,
  "predator_level": "Low",
  "predator_interpretation": "Few predators observed",
  "recommendations": ["High pest diversity (top 10%)", "Benefits from companions that attract pest predators"]
}
```

#### 2.5 Disease Control Section
```json
"disease_control": {
  "beneficial_fungi_count": 0,
  "recommendations": ["No documented mycoparasitic fungi", "Focus on spacing and airflow for disease prevention"]
}
```

#### 2.6 Mycorrhizal Network Details
```json
"mycorrhizal_network": {
  "association_type": "EMF (Ectomycorrhizal)",
  "species_count": 7,
  "recommendations": ["Other plants with EMF associations", "Can share nutrients and defense signals with EMF-compatible neighbours"],
  "network_type": "Creates forest-type nutrient-sharing network"
}
```

#### 2.7 Structural Role
```json
"structural_role": {
  "layer": "Canopy",
  "height_m": 27.1,
  "growth_form": "Tree",
  "light_preference": 6.2,
  "recommendations": {
    "below": "Shade-tolerant understory plants (EIVE-L < 5)",
    "avoid": "Sun-loving plants in the shade zone"
  },
  "benefits": "Creates significant shade; wind protection for neighbours"
}
```

#### 2.8 Pollinator Support
```json
"pollinator_support": {
  "count": 14,
  "level": "Typical",
  "interpretation": "Average pollinator observations",
  "recommendations": "Good companion for other flowering plants",
  "provides": ["Nectar/pollen source for 14 pollinator species", "Attraction effect may increase visits to neighbouring plants"]
}
```

#### 2.9 Cautions
```json
"cautions": [
  "Avoid clustering multiple Fagaceae plants (shared pests and diseases)",
  "C-dominant strategy: may outcompete slower-growing neighbours"
]
```

---

## 3. Qualitative Interpretations (missing throughout)

The markdown includes plain-English interpretations for every metric. Examples:

### Temperature Interpretations
| Metric | Value | Markdown Interpretation | API Status |
|--------|-------|------------------------|------------|
| Frost days | 62/year | "Long frost season" | Missing |
| Cold spells | 5 consecutive days | "Short cold snaps" | Missing |
| Hot days | 54/year | "Mild summers" | Missing |
| Warm nights | Rare | "Cool nights year-round" | Missing |
| Day-night swing | 10°C | "Temperate - moderate variation" | Missing |
| Growing season | 327 days | "Very long - ranges from 275 to 365 days" | Missing |

### Moisture Interpretations
| Metric | Value | Markdown Interpretation | API Status |
|--------|-------|------------------------|------------|
| Dry spells | 16 days | "Limited - Water during 2+ week dry periods" | Missing |
| Disease pressure | 10 warm-wet days | "Low (dry climate origin) - may be vulnerable to fungal diseases in humid gardens" | Missing |
| Wet spells | 10 days | "Moderate waterlogging tolerance - ensure drainage in heavy soils" | Missing |

### Maintenance Interpretations
| Field | Markdown Value | API Status |
|-------|---------------|------------|
| What to expect | "Fast, vigorous grower with high nutrient demand. Benefits from annual feeding..." | Missing |
| Practical considerations | "Professional arborist needed at 27m mature height" | Missing |
| Watch for | ["May outcompete slower-growing neighbours", "Dense shade may suppress understory plants"] | Missing |

---

## 4. Beneficial Predators & Fungivores (entirely missing)

### Beneficial Predators
The markdown shows:
```
**2 species documented** - natural pest control agents
- **Beetles** (1): Carabus cancellatus
- **Wasps** (1): Eurytoma brunniventris
```

Required API addition:
```json
"beneficial_predators": {
  "total_count": 2,
  "level": "Low",
  "interpretation": "Few predators observed",
  "categories": [
    {"name": "Beetles", "organisms": ["Carabus cancellatus"]},
    {"name": "Wasps", "organisms": ["Eurytoma brunniventris"]}
  ],
  "note": "These beneficial organisms help control pest populations."
}
```

### Fungivores (Disease Control)
The markdown shows:
```
**54 species documented** - organisms that eat fungi
- **Snails & Slugs** (10): Monadenia fidelis, Ariolimax buttoni, ...
- **Beetles** (7): Triplax dissimulator, Cis bilamellatus, ...
- **Squirrels** (4): Tamiasciurus hudsonicus, Sciurus carolinensis, ...
- **Flies** (2): Drosophila ceratostoma, Mycodiplosis erysiphes
- **Other Predators** (31): ...
```

Required API addition:
```json
"fungivores": {
  "total_count": 54,
  "interpretation": "Fungivores help control plant diseases by consuming pathogenic fungi",
  "categories": [
    {"name": "Snails & Slugs", "count": 10, "organisms": ["Monadenia fidelis", "..."]},
    {"name": "Beetles", "count": 7, "organisms": ["Triplax dissimulator", "..."]},
    {"name": "Squirrels", "count": 4, "organisms": ["Tamiasciurus hudsonicus", "..."]},
    {"name": "Flies", "count": 2, "organisms": ["Drosophila ceratostoma", "..."]},
    {"name": "Other Predators", "count": 31, "organisms": ["..."]}
  ],
  "note": "They provide natural disease suppression in the garden ecosystem."
}
```

---

## 5. Soil Texture Details (missing)

The markdown shows detailed soil characterization:

```
**Texture**
| Component | Typical | Range |
| Sand | 44% | 33-59% |
| Silt | 36% | 15-55% |
| Clay | 20% | 12-26% |

**USDA Class**: Loam
*Drainage: Good | Water retention: Good*

**Triangle Coordinates**: x=45.9, y=20.3

**Profile Average (0-200cm)**
| pH | 6.5 | 5.3-7.7 |
| CEC (cmol/kg) | 20 | 14-26 |
| SOC (g/kg) | 12 | 6-27 |
```

Required API addition:
```json
"soil_texture": {
  "sand_percent": {"typical": 44, "min": 33, "max": 59},
  "silt_percent": {"typical": 36, "min": 15, "max": 55},
  "clay_percent": {"typical": 20, "min": 12, "max": 26},
  "usda_class": "Loam",
  "drainage": "Good",
  "water_retention": "Good",
  "interpretation": "Ideal soil; balanced drainage and retention; suits most plants",
  "triangle_x": 45.9,
  "triangle_y": 20.3
},
"soil_fertility": {
  "cec": {"typical": 22, "min": 19, "max": 33, "unit": "cmol/kg"},
  "cec_interpretation": "Good retention - soil holds fertilizer well; benefits from annual feeding",
  "organic_carbon": {"typical": 41, "min": 22, "max": 77, "unit": "g/kg"}
},
"soil_profile_200cm": {
  "ph": {"typical": 6.5, "min": 5.3, "max": 7.7},
  "cec": {"typical": 20, "min": 14, "max": 26},
  "soc": {"typical": 12, "min": 6, "max": 27}
}
```

---

## 6. CSR Data Discrepancy

**Critical issue:** The markdown and API show different CSR values for the same plant.

| Source | C | S | R | Dominant |
|--------|---|---|---|----------|
| Markdown | 45% | 41% | 14% | C-dominant (Competitor) |
| API | 33.3% | 33.3% | 33.3% | Balanced |

This needs investigation - the Rust API may be using different source data than the markdown generator.

---

## Implementation Priority

### High Priority (Core Encyclopedia)
1. Ecosystem Services metrics (10 fields)
2. Guild Potential detailed subsections
3. Beneficial predators and fungivores
4. CSR data consistency fix

### Medium Priority (Enhanced UX)
5. Qualitative interpretations throughout
6. Soil texture details
7. Temperature/moisture detailed interpretations

### Low Priority (Polish)
8. Section preambles/educational context
9. Data source attribution in API

---

---

## Root Cause Analysis

### The Data EXISTS - It's Just Not Exposed

The markdown generator (`encyclopedia/sections/s4_services.rs`) reads rich data from:
```rust
get_str(data, "npp_rating");
get_str(data, "decomposition_rating");
get_str(data, "nutrient_cycling_rating");
// ... 10 ecosystem service fields
```

But the JSON API's `view_models.rs` has a SIMPLIFIED struct:
```rust
pub struct EcosystemServices {
    pub services: Vec<ServiceCard>,  // Empty array!
    pub nitrogen_fixer: bool,
    pub pollinator_score: Option<u8>,  // null
    pub carbon_storage: Option<String>,  // null
}
```

The view_builder never populates `services` with the 10 ecosystem ratings that the markdown generator uses.

### Files to Modify

1. **`encyclopedia/view_models.rs`** - Add new structs:
   - `EcosystemRatings` with all 10 service fields
   - `GuildPotentialDetails` with 6 subsections
   - `SoilTextureDetails` with sand/silt/clay percentages

2. **`encyclopedia/view_builder.rs`** - Populate the new fields from base data

3. **`encyclopedia/sections/s4_services.rs`** - Already has the rating descriptions, reuse for JSON

---

## Specific Rust Changes Required

### 1. Add EcosystemRatings to view_models.rs

```rust
#[derive(Debug, Clone, Serialize)]
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

#[derive(Debug, Clone, Serialize)]
pub struct ServiceRating {
    pub score: f64,           // 1.0 - 5.0
    pub rating: String,       // "Very High", "High", "Moderate", "Low", "Very Low"
    pub description: String,  // Human-readable explanation
}
```

### 2. Add GuildPotentialDetails to view_models.rs

```rust
#[derive(Debug, Clone, Serialize)]
pub struct GuildPotentialDetails {
    pub summary_table: GuildSummaryTable,
    pub key_principles: Vec<String>,
    pub growth_compatibility: GrowthCompatibility,
    pub pest_control: PestControlAnalysis,
    pub disease_control: DiseaseControlAnalysis,
    pub mycorrhizal_network: MycorrhizalNetworkAnalysis,
    pub structural_role: StructuralRoleAnalysis,
    pub pollinator_support: PollinatorSupportAnalysis,
    pub cautions: Vec<String>,
}
```

### 3. Add SoilTextureDetails to view_models.rs

```rust
#[derive(Debug, Clone, Serialize)]
pub struct SoilTextureDetails {
    pub sand_percent: RangeValue,
    pub silt_percent: RangeValue,
    pub clay_percent: RangeValue,
    pub usda_class: String,
    pub drainage: String,
    pub water_retention: String,
    pub triangle_x: f64,
    pub triangle_y: f64,
}
```

### 4. Update EcosystemServices struct

```rust
pub struct EcosystemServices {
    pub ratings: EcosystemRatings,  // NEW: All 10 ratings
    pub nitrogen_fixer: bool,
    pub pollinator_score: Option<u8>,
    pub carbon_storage: Option<String>,
    pub services: Vec<ServiceCard>,  // Keep for backwards compat
}
```

### 5. Update CompanionSection struct

```rust
pub struct CompanionSection {
    pub guild_roles: Vec<GuildRole>,
    pub guild_details: Option<GuildPotentialDetails>,  // NEW: Detailed analysis
    pub good_companions: Vec<CompanionPlant>,
    pub avoid_with: Vec<String>,
    pub planting_notes: Vec<String>,
}
```

---

## Implementation Priority

### Phase 1: Core Ecosystem Data (High Impact)
1. Add `EcosystemRatings` struct with all 10 ratings
2. Update `view_builder.rs` to read from base data HashMap
3. Frontend: Display all 10 ecosystem service cards

### Phase 2: Guild Potential (High Value for Guild Builder)
4. Add `GuildPotentialDetails` struct
5. Populate from existing guild analysis functions
6. Frontend: Display detailed guild-building guidance

### Phase 3: Soil & Temperature Details (Medium Impact)
7. Add `SoilTextureDetails` struct
8. Add temperature interpretation fields
9. Frontend: Display detailed soil/temp profiles

### Phase 4: Beneficial Organisms (Complete Picture)
10. Add beneficial predators to InteractionsSection
11. Add fungivores to InteractionsSection
12. Frontend: Display full organism network
