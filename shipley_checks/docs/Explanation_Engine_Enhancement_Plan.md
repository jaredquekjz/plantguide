# Explanation Engine Enhancement Plan - DETAILED IMPLEMENTATION

## EIVE R Semantic Binning (Source of Truth)

From original pipeline (`src/Stage_3/generate_100_plants_evaluation.py`):

```python
'R': [
    (0.00, 2.0, "strongly acidic (pH 3-4)"),
    (2.0, 4.0, "acidic (pH 4-5)"),
    (4.0, 5.5, "slightly acidic (pH 5-6)"),
    (5.5, 7.0, "neutral (pH 6-7)"),
    (7.0, 8.5, "alkaline (pH 7-8)"),
    (8.5, 10.0, "strongly alkaline (pH >8)"),
]
```

---

# Enhancement #1: pH Warning with EIVE Semantic Binning

## Step 1: Update Rust Data Structures

**File**: `shipley_checks/src/Stage_4/guild_scorer_rust/src/explanation/soil_ph.rs`

### Current Code (lines 1-30):
```rust
use polars::prelude::*;
use anyhow::Result;
use crate::explanation::types::WarningCard;
use crate::explanation::types::Severity;

pub fn check_soil_ph_compatibility(guild_plants: &DataFrame) -> Result<Option<WarningCard>> {
    // Current simple implementation
    // Returns single warning card if incompatible
}
```

### Replace With:

```rust
use polars::prelude::*;
use anyhow::Result;
use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhCompatibilityWarning {
    pub severity: PhSeverity,
    pub r_range: f64,
    pub min_r: f64,
    pub max_r: f64,
    pub plant_categories: Vec<PhCategory>,
    pub recommendation: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhCategory {
    pub category_name: String,  // e.g. "Acidic (pH 4-5)"
    pub r_range_start: f64,     // 2.0
    pub r_range_end: f64,       // 4.0
    pub plants: Vec<PlantPh>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlantPh {
    pub name: String,
    pub r_value: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PhSeverity {
    Low,     // 1.0-2.0 R units
    Medium,  // 2.0-3.0 R units
    High,    // > 3.0 R units
}

// EIVE R semantic binning (source: Dengler et al. 2023, Hill et al. 1999)
const PH_BINS: [(f64, f64, &str); 6] = [
    (0.0, 2.0, "Strongly Acidic (pH 3-4)"),
    (2.0, 4.0, "Acidic (pH 4-5)"),
    (4.0, 5.5, "Slightly Acidic (pH 5-6)"),
    (5.5, 7.0, "Neutral (pH 6-7)"),
    (7.0, 8.5, "Alkaline (pH 7-8)"),
    (8.5, 10.0, "Strongly Alkaline (pH >8)"),
];

fn get_ph_category_name(r_value: f64) -> String {
    for (lower, upper, label) in &PH_BINS {
        if r_value >= *lower && r_value < *upper {
            return label.to_string();
        }
    }
    // Edge case: exactly 10.0
    PH_BINS.last().unwrap().2.to_string()
}

pub fn check_ph_compatibility(guild_plants: &DataFrame) -> Result<Option<PhCompatibilityWarning>> {
    // Extract R column
    let r_column = match guild_plants.column("R") {
        Ok(col) => col,
        Err(_) => return Ok(None),  // No R data
    };

    let r_series = r_column.f64()?;

    // Filter out null values
    let r_values: Vec<f64> = r_series.into_iter()
        .filter_map(|opt| opt)
        .collect();

    if r_values.is_empty() {
        return Ok(None);
    }

    // Calculate range
    let min_r = r_values.iter().cloned().fold(f64::INFINITY, f64::min);
    let max_r = r_values.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
    let r_range = max_r - min_r;

    // Only warn if range > 1.0 EIVE units
    if r_range <= 1.0 {
        return Ok(None);
    }

    // Get plant names
    let names_column = guild_plants.column("accepted_name")?;
    let names = names_column.str()?;

    // Group plants by pH category
    let mut category_map: std::collections::HashMap<String, Vec<PlantPh>> =
        std::collections::HashMap::new();

    for (idx, r_value) in r_values.iter().enumerate() {
        let plant_name = names.get(idx).unwrap_or("Unknown").to_string();
        let category_name = get_ph_category_name(*r_value);

        category_map.entry(category_name.clone()).or_insert_with(Vec::new).push(PlantPh {
            name: plant_name,
            r_value: *r_value,
        });
    }

    // Convert to sorted PhCategory vec
    let mut plant_categories: Vec<PhCategory> = Vec::new();
    for (lower, upper, label) in &PH_BINS {
        let category_name = label.to_string();
        if let Some(plants) = category_map.get(&category_name) {
            plant_categories.push(PhCategory {
                category_name: category_name.clone(),
                r_range_start: *lower,
                r_range_end: *upper,
                plants: plants.clone(),
            });
        }
    }

    // Determine severity
    let severity = if r_range > 3.0 {
        PhSeverity::High
    } else if r_range > 2.0 {
        PhSeverity::Medium
    } else {
        PhSeverity::Low
    };

    // Generate recommendation
    let has_acidic = plant_categories.iter()
        .any(|cat| cat.r_range_end <= 4.0 && !cat.plants.is_empty());
    let has_alkaline = plant_categories.iter()
        .any(|cat| cat.r_range_start >= 7.0 && !cat.plants.is_empty());

    let recommendation = if has_acidic && has_alkaline {
        format!(
            "These plants have fundamentally incompatible pH requirements (spanning {} EIVE units). \
            Consider: (1) soil amendments (sulfur for acidification, lime for alkalization), \
            (2) zone planting with different soil types, or (3) removing either acid-loving or alkaline-tolerant plants.",
            format!("{:.1}", r_range)
        )
    } else if r_range > 2.0 {
        format!(
            "Moderate pH range ({} EIVE units). Use pH-buffered growing media or amend soil in zones.",
            format!("{:.1}", r_range)
        )
    } else {
        format!(
            "Narrow pH range ({} EIVE units). Moderate adjustments with organic matter should accommodate all plants.",
            format!("{:.1}", r_range)
        )
    };

    Ok(Some(PhCompatibilityWarning {
        severity,
        r_range,
        min_r,
        max_r,
        plant_categories,
        recommendation,
    }))
}
```

## Step 2: Update Warning Generation

**File**: `shipley_checks/src/Stage_4/guild_scorer_rust/src/explanation/generator.rs`

### Find the section that calls `check_soil_ph_compatibility` (around line 80-100)

### Current Code:
```rust
// Check soil pH compatibility
if let Some(warning) = check_soil_ph_compatibility(guild_plants)? {
    warnings.push(warning);
}
```

### Replace With:
```rust
// Check soil pH compatibility (enhanced with EIVE semantic binning)
use crate::explanation::soil_ph::check_ph_compatibility;

if let Some(ph_warning) = check_ph_compatibility(guild_plants)? {
    // Convert PhCompatibilityWarning to WarningCard
    let severity = match ph_warning.severity {
        crate::explanation::soil_ph::PhSeverity::Low => Severity::Low,
        crate::explanation::soil_ph::PhSeverity::Medium => Severity::Medium,
        crate::explanation::soil_ph::PhSeverity::High => Severity::High,
    };

    // Format plant list by category
    let mut detail = format!(
        "Guild plants span {:.1} EIVE units (R: {:.1} to {:.1})\n\n",
        ph_warning.r_range, ph_warning.min_r, ph_warning.max_r
    );

    detail.push_str("Plants have different soil pH requirements:\n\n");

    for category in &ph_warning.plant_categories {
        detail.push_str(&format!("**{}**:\n", category.category_name));
        for plant in &category.plants {
            detail.push_str(&format!("- {} (R: {:.1})\n", plant.name, plant.r_value));
        }
        detail.push_str("\n");
    }

    detail.push_str(&format!("**Severity**: {:?}\n\n", severity));
    detail.push_str(&format!("**Recommendation**: {}", ph_warning.recommendation));

    warnings.push(WarningCard {
        warning_type: "ph_incompatibility".to_string(),
        severity,
        icon: "⚠️".to_string(),
        message: format!(
            "pH Incompatibility: Plants span {:.1} EIVE units (R: {:.1} to {:.1})",
            ph_warning.r_range, ph_warning.min_r, ph_warning.max_r
        ),
        detail,
        advice: ph_warning.recommendation,
    });
}
```

## Step 3: Test the pH Warning

Create test file: `shipley_checks/src/Stage_4/guild_scorer_rust/src/bin/test_ph_warning.rs`

```rust
use guild_scorer_rust::GuildScorer;
use anyhow::Result;

fn main() -> Result<()> {
    println!("Testing pH Warning with EIVE Semantic Binning");
    println!("=".repeat(60));

    let scorer = GuildScorer::new("7plant", "tier_3_humid_temperate")?;

    // Test guild with wide pH range
    // Vaccinium (R~2), Malus (R~6), Clematis (R~8)
    let test_guilds = vec![
        ("Wide pH Range", vec![
            "wfo-0001393790", // Vaccinium myrtillus (acidic)
            "wfo-0000832453", // Malus domestica (neutral)
            "wfo-0000268706", // Clematis vitalba (alkaline)
        ]),
        ("Narrow pH Range", vec![
            "wfo-0000832453", // Malus domestica
            "wfo-0000649136", // Corylus avellana
            "wfo-0000642673", // Castanea sativa
        ]),
    ];

    for (name, plant_ids) in test_guilds {
        println!("\n{}", "=".repeat(60));
        println!("Test: {}", name);
        println!("{}", "=".repeat(60));

        let (score, fragments, guild_plants) = scorer.score_guild_with_explanation_parallel(&plant_ids)?;

        // Check pH warning
        use guild_scorer_rust::check_ph_compatibility;
        if let Some(warning) = check_ph_compatibility(&guild_plants)? {
            println!("\n✅ pH Warning Triggered:");
            println!("  Range: {:.1} R units ({:.1} to {:.1})",
                     warning.r_range, warning.min_r, warning.max_r);
            println!("  Severity: {:?}", warning.severity);
            println!("\n  Plant Categories:");
            for cat in &warning.plant_categories {
                println!("    - {}: {} plants", cat.category_name, cat.plants.len());
                for plant in &cat.plants {
                    println!("      • {} (R: {:.1})", plant.name, plant.r_value);
                }
            }
            println!("\n  Recommendation: {}", warning.recommendation);
        } else {
            println!("\n✓ No pH warning (compatible range)");
        }
    }

    Ok(())
}
```

Add to `Cargo.toml`:
```toml
[[bin]]
name = "test_ph_warning"
path = "src/bin/test_ph_warning.rs"
```

Run test:
```bash
cd shipley_checks/src/Stage_4/guild_scorer_rust
cargo build --release --bin test_ph_warning
cd /home/olier/ellenberg
./shipley_checks/src/Stage_4/guild_scorer_rust/target/release/test_ph_warning
```

---

# Enhancement #2: Pest Profile (Shared Pests + Top 10)

## Step 1: Find the Herbivore Data

First, check what data we actually have:

```bash
cd /home/olier/ellenberg

# Find herbivore files
find shipley_checks -name "*herbivore*" -name "*.parquet" -o -name "*herbivore*" -name "*.csv" 2>/dev/null

# Check structure
/home/olier/miniconda3/envs/AI/bin/python << 'EOF'
import pandas as pd

# Try different locations
files = [
    'shipley_checks/validation/matched_herbivores_per_plant_python_VERIFIED.csv',
    'shipley_checks/validation/known_herbivore_insects_python_VERIFIED.csv',
]

for f in files:
    try:
        df = pd.read_csv(f, nrows=5)
        print(f"\n=== {f} ===")
        print(f"Columns: {list(df.columns)}")
        print(df.head(3))
    except Exception as e:
        print(f"Could not read {f}: {e}")
EOF
```

## Step 2: Create Pest Analysis Module

**File**: `shipley_checks/src/Stage_4/guild_scorer_rust/src/explanation/pest_analysis.rs` (NEW)

```rust
use polars::prelude::*;
use anyhow::Result;
use serde::{Serialize, Deserialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PestProfile {
    pub shared_pests: Vec<SharedPest>,
    pub top_pests: Vec<TopPest>,
    pub total_pest_species: usize,
    pub generalist_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharedPest {
    pub family: String,
    pub plant_count: usize,
    pub plants: Vec<String>,
    pub total_interactions: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopPest {
    pub family: String,
    pub interaction_count: usize,
    pub plant_count: usize,
    pub plants: Vec<String>,
}

pub fn analyze_guild_pests(
    guild_plants: &DataFrame,
    all_organisms: &DataFrame
) -> Result<Option<PestProfile>> {
    // 1. Get plant IDs from guild
    let guild_plant_ids: Vec<String> = guild_plants
        .column("plant_id")?
        .str()?
        .into_iter()
        .filter_map(|opt| opt.map(|s| s.to_string()))
        .collect();

    if guild_plant_ids.is_empty() {
        return Ok(None);
    }

    // 2. Filter organisms table to guild plants only
    // Assuming organisms has columns: plant_id, herbivore_family, interaction_count
    let guild_organisms = all_organisms.filter(
        &all_organisms.column("plant_id")?
            .str()?
            .into_iter()
            .map(|opt| opt.map(|s| guild_plant_ids.contains(&s.to_string())).unwrap_or(false))
            .collect::<BooleanChunked>()
    )?;

    if guild_organisms.height() == 0 {
        return Ok(None);  // No pest data
    }

    // 3. Build pest-to-plants mapping
    let mut pest_to_plants: HashMap<String, Vec<(String, usize)>> = HashMap::new();

    let plant_ids = guild_organisms.column("plant_id")?.str()?;
    let herbivores = guild_organisms.column("herbivore_family")?.str()?;
    let interactions = guild_organisms.column("interaction_count")?.u32()?;

    for idx in 0..guild_organisms.height() {
        let plant_id = plant_ids.get(idx).unwrap().to_string();
        let herbivore = herbivores.get(idx).unwrap().to_string();
        let interaction_count = interactions.get(idx).unwrap_or(1) as usize;

        // Get plant name
        let plant_name = get_plant_name(guild_plants, &plant_id)?;

        pest_to_plants
            .entry(herbivore)
            .or_insert_with(Vec::new)
            .push((plant_name, interaction_count));
    }

    // 4. Identify shared pests (2+ plants)
    let mut shared_pests: Vec<SharedPest> = pest_to_plants
        .iter()
        .filter(|(_, plants)| plants.len() >= 2)
        .map(|(pest, plant_interactions)| {
            let plant_names: Vec<String> = plant_interactions
                .iter()
                .map(|(name, _)| name.clone())
                .collect();
            let total_interactions: usize = plant_interactions
                .iter()
                .map(|(_, count)| count)
                .sum();

            SharedPest {
                family: pest.clone(),
                plant_count: plant_interactions.len(),
                plants: plant_names,
                total_interactions,
            }
        })
        .collect();

    // Sort by plant_count desc, then by interactions desc
    shared_pests.sort_by(|a, b| {
        b.plant_count.cmp(&a.plant_count)
            .then(b.total_interactions.cmp(&a.total_interactions))
    });

    // 5. Get top 10 pests by interaction count
    let mut all_pests: Vec<TopPest> = pest_to_plants
        .iter()
        .map(|(pest, plant_interactions)| {
            let plant_names: Vec<String> = plant_interactions
                .iter()
                .map(|(name, _)| name.clone())
                .collect();
            let total_interactions: usize = plant_interactions
                .iter()
                .map(|(_, count)| count)
                .sum();

            TopPest {
                family: pest.clone(),
                interaction_count: total_interactions,
                plant_count: plant_interactions.len(),
                plants: plant_names,
            }
        })
        .collect();

    all_pests.sort_by_key(|p| std::cmp::Reverse(p.interaction_count));
    let top_pests: Vec<TopPest> = all_pests.into_iter().take(10).collect();

    // 6. Calculate statistics
    let generalist_count = shared_pests.iter()
        .filter(|p| p.plant_count >= 3)
        .count();

    Ok(Some(PestProfile {
        shared_pests,
        top_pests,
        total_pest_species: pest_to_plants.len(),
        generalist_count,
    }))
}

fn get_plant_name(guild_plants: &DataFrame, plant_id: &str) -> Result<String> {
    let ids = guild_plants.column("plant_id")?.str()?;
    let names = guild_plants.column("accepted_name")?.str()?;

    for idx in 0..guild_plants.height() {
        if ids.get(idx).unwrap() == plant_id {
            return Ok(names.get(idx).unwrap().to_string());
        }
    }

    Ok("Unknown".to_string())
}
```

## Step 3: Add Pest Profile to Explanation

**File**: `shipley_checks/src/Stage_4/guild_scorer_rust/src/explanation/generator.rs`

Add after benefits section:

```rust
// Add pest profile section (informational only)
use crate::explanation::pest_analysis::analyze_guild_pests;

pub fn generate_pest_profile_section(
    pest_profile: &PestProfile,
    m1_score: f64,
    m3_score: f64,
) -> String {
    let mut md = String::from("## Guild Pest Profile (Informational)\n\n");
    md.push_str("*This information is for awareness only and does not affect the guild score. ");
    md.push_str("The M1 metric already accounts for pest/pathogen risk through phylogenetic distance.*\n\n");

    // Shared pests
    if !pest_profile.shared_pests.is_empty() {
        md.push_str("### Shared Pests Across Plants\n\n");
        md.push_str("**Pests affecting multiple plants in guild**:\n\n");

        for pest in pest_profile.shared_pests.iter().take(5) {
            md.push_str(&format!(
                "- **{}** → Affects {} plants\n",
                pest.family, pest.plant_count
            ));
            md.push_str(&format!("  - Plants: {}\n", pest.plants.join(", ")));
            md.push_str(&format!("  - Total interactions: {}\n\n", pest.total_interactions));
        }
    }

    // Top 10 pests
    md.push_str("### Top 10 Most Connected Pests\n\n");
    md.push_str("Pests with highest number of plant-pest interactions in this guild:\n\n");

    for (idx, pest) in pest_profile.top_pests.iter().enumerate() {
        md.push_str(&format!(
            "{}. **{}** - {} interactions ({} plants affected)\n",
            idx + 1, pest.family, pest.interaction_count, pest.plant_count
        ));
    }

    // Interpretation
    md.push_str(&format!(
        "\n**Interpretation**: This guild has {} highly generalist pests ",
        pest_profile.generalist_count
    ));

    if pest_profile.generalist_count > 0 {
        md.push_str("that could spread easily between plants. ");
    }

    md.push_str(&format!(
        "The M1 phylogenetic diversity score ({:.1}/100) ", m1_score
    ));

    if m1_score > 60.0 {
        md.push_str("suggests good evolutionary distance, which helps limit pest sharing. ");
    } else {
        md.push_str("suggests moderate evolutionary distance. ");
    }

    if m3_score > 50.0 {
        md.push_str(&format!(
            "The biocontrol mechanisms (M3: {:.1}/100) provide natural predators for these pests.",
            m3_score
        ));
    }

    md.push_str("\n\n");
    md
}
```

---

# Enhancement #3: M6 Growth Form Details

## Step 1: Update M6 Result Structure

**File**: `shipley_checks/src/Stage_4/guild_scorer_rust/src/metrics/m6_structural_diversity.rs`

### Find M6Result struct (around line 10-20)

### Current:
```rust
pub struct M6Result {
    pub raw_score: f64,
    pub normalized: f64,
    pub n_forms: usize,
    pub forms: Vec<String>,
    pub stratification_quality: f64,
}
```

### Add:
```rust
#[derive(Debug, Clone)]
pub struct GrowthFormGroup {
    pub form_name: String,
    pub plants: Vec<PlantHeight>,
    pub height_range: (f64, f64),
}

#[derive(Debug, Clone)]
pub struct PlantHeight {
    pub name: String,
    pub height_m: f64,
}

// Update M6Result to include detailed groups
pub struct M6Result {
    pub raw_score: f64,
    pub normalized: f64,
    pub n_forms: usize,
    pub forms: Vec<String>,
    pub stratification_quality: f64,
    pub height_range_m: f64,
    pub growth_form_groups: Vec<GrowthFormGroup>,  // NEW
}
```

### Update calculate_m6 function:

Find where M6Result is constructed and add:

```rust
// Group plants by growth form
let mut form_groups: HashMap<String, Vec<PlantHeight>> = HashMap::new();

for row in guild_plants.iter() {
    let plant_name = row.column("accepted_name").unwrap().str().unwrap().get(0).unwrap().to_string();
    let growth_form = row.column("growth_form").unwrap().str().unwrap().get(0).unwrap().to_string();
    let height = row.column("height_m").unwrap().f64().unwrap().get(0).unwrap();

    form_groups.entry(growth_form).or_insert_with(Vec::new).push(PlantHeight {
        name: plant_name,
        height_m: height,
    });
}

// Convert to GrowthFormGroup vec
let growth_form_groups: Vec<GrowthFormGroup> = form_groups
    .into_iter()
    .map(|(form_name, plants)| {
        let heights: Vec<f64> = plants.iter().map(|p| p.height_m).collect();
        let min_height = heights.iter().cloned().fold(f64::INFINITY, f64::min);
        let max_height = heights.iter().cloned().fold(f64::NEG_INFINITY, f64::max);

        GrowthFormGroup {
            form_name,
            plants,
            height_range: (min_height, max_height),
        }
    })
    .collect();
```

## Step 2: Update M6 Fragment Generator

**File**: `shipley_checks/src/Stage_4/guild_scorer_rust/src/explanation/fragments/m6_fragment.rs`

Add detailed formatting:

```rust
pub fn generate_m6_fragment(m6: &M6Result, display_score: f64) -> MetricFragment {
    if display_score > 50.0 {
        let mut detail = format!(
            "Vertical stratification across {} growth forms ({:.1}m range):\n\n",
            m6.n_forms, m6.height_range_m
        );

        detail.push_str("**Growth Form Distribution**:\n");
        for group in &m6.growth_form_groups {
            detail.push_str(&format!(
                "- **{}** ({:.1}m-{:.1}m): ",
                group.form_name, group.height_range.0, group.height_range.1
            ));

            let plant_list: Vec<String> = group.plants.iter()
                .map(|p| format!("{} ({:.1}m)", p.name, p.height_m))
                .collect();

            detail.push_str(&plant_list.join(", "));
            detail.push_str("\n");
        }

        detail.push_str(&format!(
            "\n*Evidence:* Structural diversity score: {:.1}/100, stratification quality: {:.2}",
            display_score, m6.stratification_quality
        ));

        MetricFragment::with_benefit(BenefitCard {
            benefit_type: "structural_diversity".to_string(),
            metric_code: "M6".to_string(),
            title: "High Structural Diversity".to_string(),
            message: format!(
                "{} growth forms spanning {:.1}m height range",
                m6.n_forms, m6.height_range_m
            ),
            detail,
            evidence: Some(format!("Stratification quality: {:.2}", m6.stratification_quality)),
        })
    } else {
        MetricFragment::empty()
    }
}
```

---

# Testing Strategy

## Test 1: pH Warning (use known R values)

```bash
cd /home/olier/ellenberg

# Check R values for test plants
/home/olier/miniconda3/envs/AI/bin/python << 'EOF'
import pandas as pd

df = pd.read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_11711.parquet')

test_plants = {
    'Vaccinium myrtillus': 'wfo-0001393790',  # Expect R~2 (acidic)
    'Malus domestica': 'wfo-0000832453',       # Expect R~6 (neutral)
    'Clematis vitalba': 'wfo-0000268706',      # Expect R~8 (alkaline)
}

for name, wfo_id in test_plants.items():
    row = df[df['plant_id'] == wfo_id]
    if not row.empty:
        r_val = row['R'].values[0]
        print(f"{name}: R = {r_val:.1f}")
EOF

# Then run Rust test
./shipley_checks/src/Stage_4/guild_scorer_rust/target/release/test_ph_warning
```

## Test 2: Complete Explanation

```bash
# Run full explanation test with enhancements
./shipley_checks/src/Stage_4/guild_scorer_rust/target/release/test_explanations_3_guilds

# Check output files
cat shipley_checks/reports/explanations/rust_explanation_forest_garden.md
```

---

# R Implementation (Parity)

**File**: `shipley_checks/src/Stage_4/explanation_engine_7metric.R`

Add at top:

```r
# EIVE R semantic binning (source: Dengler et al. 2023, Hill et al. 1999)
EIVE_R_BINS <- list(
  list(lower = 0.0, upper = 2.0, label = "Strongly Acidic (pH 3-4)"),
  list(lower = 2.0, upper = 4.0, label = "Acidic (pH 4-5)"),
  list(lower = 4.0, upper = 5.5, label = "Slightly Acidic (pH 5-6)"),
  list(lower = 5.5, upper = 7.0, label = "Neutral (pH 6-7)"),
  list(lower = 7.0, upper = 8.5, label = "Alkaline (pH 7-8)"),
  list(lower = 8.5, upper = 10.0, label = "Strongly Alkaline (pH >8)")
)

get_ph_category <- function(r_value) {
  for (bin in EIVE_R_BINS) {
    if (r_value >= bin$lower && r_value < bin$upper) {
      return(bin$label)
    }
  }
  # Edge case: exactly 10.0
  return(EIVE_R_BINS[[length(EIVE_R_BINS)]]$label)
}
```

Update `generate_warnings_explanation`:

```r
# Enhanced pH check
if (!is.null(guild_result$flags$soil_ph_detail)) {
  ph_detail <- guild_result$flags$soil_ph_detail

  if (ph_detail$r_range > 1.0) {
    # Group plants by category
    plant_categories <- list()

    for (i in 1:nrow(guild_plants)) {
      r_val <- guild_plants$R[i]
      if (!is.na(r_val)) {
        category <- get_ph_category(r_val)
        plant_name <- guild_plants$accepted_name[i]

        if (!(category %in% names(plant_categories))) {
          plant_categories[[category]] <- list()
        }
        plant_categories[[category]] <- c(
          plant_categories[[category]],
          sprintf("%s (R: %.1f)", plant_name, r_val)
        )
      }
    }

    # Format warning
    detail <- sprintf(
      "Guild plants span %.1f EIVE units (R: %.1f to %.1f)\n\n",
      ph_detail$r_range, ph_detail$min_r, ph_detail$max_r
    )

    detail <- paste0(detail, "Plants have different soil pH requirements:\n\n")

    for (category in names(plant_categories)) {
      detail <- paste0(detail, sprintf("**%s**:\n", category))
      for (plant in plant_categories[[category]]) {
        detail <- paste0(detail, sprintf("- %s\n", plant))
      }
      detail <- paste0(detail, "\n")
    }

    warnings[[length(warnings) + 1]] <- list(
      type = "ph_incompatibility",
      severity = ph_detail$severity,
      icon = "⚠️",
      message = sprintf(
        "pH Incompatibility: Plants span %.1f EIVE units",
        ph_detail$r_range
      ),
      detail = detail,
      advice = ph_detail$recommendation
    )
  }
}
```

---

# Implementation Order

1. ✅ **pH Warning** (1-2 hours)
   - Highest value, easiest to test
   - Clear data source (R column exists)
   - Validates EIVE binning approach

2. **M6 Growth Forms** (1 hour)
   - Data already available in guild_plants
   - Straightforward grouping logic
   - Good warm-up for more complex features

3. **Pest Profile** (2-3 hours)
   - Need to verify herbivore data structure first
   - More complex data joins
   - Integration with explanation generator

4. **M5/M7 Networks** (2-3 hours each)
   - Similar algorithms
   - Can reuse network analysis pattern

5. **M3/M4 Details** (1-2 hours)
   - Depends on data availability check

6. **R Parity** (ongoing)
   - Implement R version after each Rust feature
   - Test parity immediately

---

# Success Criteria

- ✅ pH warning shows correct EIVE categories
- ✅ Plants grouped by pH preference (strongly acidic to strongly alkaline)
- ✅ Severity calculated correctly (Low/Medium/High)
- ✅ Recommendations match severity level
- ✅ R and Rust generate identical output
- ✅ Parity maintained on all 3 test guilds
