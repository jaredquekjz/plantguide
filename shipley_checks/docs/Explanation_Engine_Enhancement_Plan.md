# Explanation Engine Enhancement Plan - FINAL

## EIVE Semantic Binning for R (Soil pH)

**Source**: Original Python pipeline (`src/Stage_3/generate_100_plants_evaluation.py`)

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

## Enhancement #1: Enhanced pH Range Warning

### Implementation with Correct EIVE Binning

**Rust Structure**:
```rust
#[derive(Debug, Clone)]
pub struct PhCompatibilityWarning {
    pub severity: WarningSeverity,
    pub r_range: f64,                    // Range in R units (EIVE 0-10)
    pub min_r: f64,
    pub max_r: f64,
    pub strongly_acidic: Vec<PlantPh>,   // R: 0.0-2.0
    pub acidic: Vec<PlantPh>,            // R: 2.0-4.0
    pub slightly_acidic: Vec<PlantPh>,   // R: 4.0-5.5
    pub neutral: Vec<PlantPh>,           // R: 5.5-7.0
    pub alkaline: Vec<PlantPh>,          // R: 7.0-8.5
    pub strongly_alkaline: Vec<PlantPh>, // R: 8.5-10.0
    pub recommendation: String,
}

#[derive(Debug, Clone)]
pub struct PlantPh {
    pub name: String,
    pub r_value: f64,
    pub ph_category: String,  // e.g. "acidic (pH 4-5)"
}

#[derive(Debug, Clone, PartialEq)]
pub enum WarningSeverity {
    Low,    // Range 1.0-2.0 R units
    Medium, // Range 2.0-3.0 R units
    High,   // Range > 3.0 R units
}
```

### Detection Algorithm (Rust)

```rust
fn check_ph_compatibility(guild_plants: &DataFrame) -> Result<Option<PhCompatibilityWarning>> {
    // 1. Extract R values (EIVE soil pH indicator)
    let r_column = guild_plants.column("R")?.f64()?;
    let r_values: Vec<f64> = r_column.into_no_null_iter().collect();

    if r_values.is_empty() {
        return Ok(None);
    }

    // 2. Calculate range
    let min_r = *r_values.iter().min_by(|a, b| a.partial_cmp(b).unwrap()).unwrap();
    let max_r = *r_values.iter().max_by(|a, b| a.partial_cmp(b).unwrap()).unwrap();
    let r_range = max_r - min_r;

    // 3. Check if range > 1.0 EIVE units (threshold for warning)
    if r_range <= 1.0 {
        return Ok(None);  // Compatible
    }

    // 4. EIVE semantic binning for R
    let ph_categories = vec![
        (0.0, 2.0, "strongly acidic (pH 3-4)"),
        (2.0, 4.0, "acidic (pH 4-5)"),
        (4.0, 5.5, "slightly acidic (pH 5-6)"),
        (5.5, 7.0, "neutral (pH 6-7)"),
        (7.0, 8.5, "alkaline (pH 7-8)"),
        (8.5, 10.0, "strongly alkaline (pH >8)"),
    ];

    fn get_ph_category(r_value: f64) -> String {
        let categories = vec![
            (0.0, 2.0, "strongly acidic (pH 3-4)"),
            (2.0, 4.0, "acidic (pH 4-5)"),
            (4.0, 5.5, "slightly acidic (pH 5-6)"),
            (5.5, 7.0, "neutral (pH 6-7)"),
            (7.0, 8.5, "alkaline (pH 7-8)"),
            (8.5, 10.0, "strongly alkaline (pH >8)"),
        ];
        for (lower, upper, label) in categories {
            if r_value >= lower && r_value < upper {
                return label.to_string();
            }
        }
        // Edge case: exactly 10.0
        "strongly alkaline (pH >8)".to_string()
    }

    // 5. Categorize plants by pH preference
    let mut strongly_acidic = Vec::new();
    let mut acidic = Vec::new();
    let mut slightly_acidic = Vec::new();
    let mut neutral = Vec::new();
    let mut alkaline = Vec::new();
    let mut strongly_alkaline = Vec::new();

    let names = guild_plants.column("accepted_name")?.str()?;

    for (idx, r_value) in r_values.iter().enumerate() {
        let plant_name = names.get(idx).unwrap().to_string();
        let ph_category = get_ph_category(*r_value);

        let plant_ph = PlantPh {
            name: plant_name,
            r_value: *r_value,
            ph_category: ph_category.clone(),
        };

        if *r_value < 2.0 {
            strongly_acidic.push(plant_ph);
        } else if *r_value < 4.0 {
            acidic.push(plant_ph);
        } else if *r_value < 5.5 {
            slightly_acidic.push(plant_ph);
        } else if *r_value < 7.0 {
            neutral.push(plant_ph);
        } else if *r_value < 8.5 {
            alkaline.push(plant_ph);
        } else {
            strongly_alkaline.push(plant_ph);
        }
    }

    // 6. Determine severity based on range
    let severity = if r_range > 3.0 {
        WarningSeverity::High
    } else if r_range > 2.0 {
        WarningSeverity::Medium
    } else {
        WarningSeverity::Low
    };

    // 7. Generate recommendation
    let recommendation = if (!strongly_acidic.is_empty() || !acidic.is_empty())
                         && (!alkaline.is_empty() || !strongly_alkaline.is_empty()) {
        "These plants have fundamentally incompatible pH requirements. Consider: (1) soil amendments (sulfur for acidification, lime for alkalization), (2) zone planting with different soil types, or (3) removing either acid-loving or alkaline-tolerant plants.".to_string()
    } else if r_range > 2.0 {
        "Moderate pH range. Use pH-buffered growing media or amend soil in zones to meet different requirements.".to_string()
    } else {
        "Narrow pH range. Moderate adjustments with organic matter should accommodate all plants.".to_string()
    };

    Ok(Some(PhCompatibilityWarning {
        severity,
        r_range,
        min_r,
        max_r,
        strongly_acidic,
        acidic,
        slightly_acidic,
        neutral,
        alkaline,
        strongly_alkaline,
        recommendation,
    }))
}
```

### Target Output

```markdown
## Warnings

### ⚠️ pH Incompatibility (MEDIUM Severity)

**pH Range**: Guild plants span 3.5 EIVE units (R: 2.5 to 6.0)

Plants have different soil pH requirements that may be difficult to satisfy simultaneously:

**Acidic Plants (pH 4-5)** (R: 2.0-4.0):
- Vaccinium myrtillus (Bilberry) - R value: 2.5

**Slightly Acidic Plants (pH 5-6)** (R: 4.0-5.5):
- Fragaria vesca (Woodland strawberry) - R value: 5.0

**Neutral Plants (pH 6-7)** (R: 5.5-7.0):
- Malus domestica (Apple) - R value: 6.0
- Corylus avellana (Hazel) - R value: 5.8

**EIVE Range**: 3.5 units (R: 2.5 to 6.0)
**Severity**: MEDIUM

**Recommendation**: Moderate pH range. Use pH-buffered growing media or amend soil in zones to meet different requirements.

---

**Understanding EIVE R Values**:
- R: 0-2 = strongly acidic (pH 3-4)
- R: 2-4 = acidic (pH 4-5)
- R: 4-5.5 = slightly acidic (pH 5-6)
- R: 5.5-7 = neutral (pH 6-7)
- R: 7-8.5 = alkaline (pH 7-8)
- R: 8.5-10 = strongly alkaline (pH >8)
```

### Warning Severity Triggers

- **Low** (1.0-2.0 R units): Minor pH adjustments needed
  - Example: All plants in neutral to slightly acidic range
  - Recommendation: Organic matter amendments

- **Medium** (2.0-3.0 R units): Moderate incompatibility
  - Example: Mix of acidic and neutral plants
  - Recommendation: Zone planting or buffered media

- **High** (>3.0 R units): Major incompatibility
  - Example: Mix of strongly acidic and alkaline plants
  - Recommendation: Remove incompatible plants or use separate containers

---

## Enhancement #2: Qualitative Pest Information

### Purpose
Educational section showing pest pressure WITHOUT affecting guild score (M1 already accounts for this through phylogenetic distance).

### Target Output

```markdown
## Guild Pest Profile (Informational)

*This information is for awareness only and does not affect the guild score. The M1 metric already accounts for pest/pathogen risk through phylogenetic distance.*

### Shared Pests Across Plants

**Pests affecting multiple plants in guild**:

- **Aphids (Aphididae)** → Affects 3 plants
  - Plants: Malus domestica, Sambucus nigra, Hedera helix
  - Total interactions: 45

- **Spider mites (Tetranychidae)** → Affects 2 plants
  - Plants: Malus domestica, Corylus avellana
  - Total interactions: 28

### Top 10 Most Connected Pests

Pests with highest number of plant-pest interactions in this guild:

1. **Aphids (Aphididae)** - 45 interactions (3 plants affected)
2. **Spider mites (Tetranychidae)** - 28 interactions (2 plants affected)
3. **Scale insects (Coccidae)** - 22 interactions (2 plants affected)
4. **Leaf miners (Agromyzidae)** - 18 interactions (1 plant affected)
5. **Whiteflies (Aleyrodidae)** - 15 interactions (2 plants affected)
6. **Thrips (Thripidae)** - 12 interactions (1 plant affected)
7. **Caterpillars (Lepidoptera larvae)** - 10 interactions (2 plants affected)
8. **Leafhoppers (Cicadellidae)** - 9 interactions (1 plant affected)
9. **Sawflies (Tenthredinidae)** - 7 interactions (1 plant affected)
10. **Weevils (Curculionidae)** - 6 interactions (1 plant affected)

**Interpretation**: This guild has 2 highly generalist pests (aphids, spider mites) that could spread easily between plants. However, the M1 phylogenetic diversity score (58.6/100) suggests moderate evolutionary distance, which helps limit pest sharing. The biocontrol mechanisms (M3: 100.0/100) provide natural predators for these common pests.
```

### Data Structure (Rust)

```rust
#[derive(Debug, Clone)]
pub struct PestProfile {
    pub shared_pests: Vec<SharedPest>,     // Pests affecting 2+ plants
    pub top_pests: Vec<TopPest>,           // Top 10 by interaction count
    pub total_pest_species: usize,
    pub generalist_count: usize,           // Pests affecting 3+ plants
}

#[derive(Debug, Clone)]
pub struct SharedPest {
    pub family: String,
    pub plant_count: usize,
    pub plants: Vec<String>,               // Plant names
    pub total_interactions: usize,
}

#[derive(Debug, Clone)]
pub struct TopPest {
    pub family: String,
    pub interaction_count: usize,
    pub plant_count: usize,
    pub plants: Vec<String>,
}
```

---

## Implementation Priority

1. **pH Warning Enhancement** (1 hour) - Use EIVE semantic binning
2. **M6 Structural Diversity** (1 hour) - Growth forms with plant lists
3. **Pest Profile** (1.5 hours) - Shared pests + top 10
4. **M5 Fungi Networks** (1.5 hours) - Network-forming vs unique
5. **M7 Pollinator Networks** (1.5 hours) - Generalist vs specialist
6. **M3/M4 Details** (1 hour) - Biocontrol and antagonist specifics
7. **R Parity** (1.5 hours) - Mirror all changes in R
8. **Testing** (1 hour) - Validate parity and outputs

**Total Estimate**: 6-8 hours

---

## R Implementation (Parity Required)

The R implementation must use the same EIVE semantic binning:

```r
EIVE_R_BINS <- list(
  c(0.0, 2.0, "strongly acidic (pH 3-4)"),
  c(2.0, 4.0, "acidic (pH 4-5)"),
  c(4.0, 5.5, "slightly acidic (pH 5-6)"),
  c(5.5, 7.0, "neutral (pH 6-7)"),
  c(7.0, 8.5, "alkaline (pH 7-8)"),
  c(8.5, 10.0, "strongly alkaline (pH >8)")
)

get_ph_category <- function(r_value) {
  for (i in 1:length(EIVE_R_BINS)) {
    bin <- EIVE_R_BINS[[i]]
    if (r_value >= bin[1] && r_value < bin[2]) {
      return(bin[3])
    }
  }
  # Edge case: exactly 10.0
  return(EIVE_R_BINS[[length(EIVE_R_BINS)]][3])
}
```

---

## Next Steps

1. ✅ Verified EIVE semantic binning from original pipeline
2. Update pH warning implementation in Rust (`soil_ph.rs`)
3. Update pH warning in R (`explanation_engine_7metric.R`)
4. Implement pest profile analysis
5. Test with 3 guilds to verify correct pH categorization
6. Validate parity between R and Rust outputs
