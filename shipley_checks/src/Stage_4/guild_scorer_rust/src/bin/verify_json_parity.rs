//! Verify JSON/MD Output Parity
//!
//! Generates both MD and JSON outputs for sample plants and compares
//! all key values to ensure parity between the two formats.
//!
//! Run with: cargo run --features api --bin verify_json_parity

#[cfg(feature = "api")]
use guild_scorer_rust::encyclopedia::{
    EncyclopediaGenerator, FungalCounts, OrganismLists,
    OrganismProfile, CategorizedOrganisms, RankedPathogen, BeneficialFungi,
    generate_encyclopedia_data,
};
#[cfg(feature = "api")]
use guild_scorer_rust::encyclopedia::view_models::EncyclopediaPageData;
#[cfg(feature = "api")]
use guild_scorer_rust::query_engine::QueryEngine;
#[cfg(feature = "api")]
use guild_scorer_rust::explanation::unified_taxonomy::{OrganismCategory, OrganismRole};
#[cfg(feature = "api")]
use std::collections::{HashMap, HashSet};
#[cfg(feature = "api")]
use std::fs;
#[cfg(feature = "api")]
use rustc_hash::FxHashMap;
#[cfg(feature = "api")]
use datafusion::arrow::array::{StringArray, LargeStringArray, StringViewArray, Array, Int32Array, Int64Array, UInt64Array};

#[cfg(feature = "api")]
fn get_data_dir() -> String {
    // Use DATA_DIR env var if set, otherwise default to shipley_checks/stage4
    std::env::var("DATA_DIR")
        .unwrap_or_else(|_| "/home/olier/ellenberg/shipley_checks/stage4".to_string())
}

#[cfg(feature = "api")]
const SAMPLE_PLANTS: &[(&str, &str, &str)] = &[
    ("wfo-0000292858", "Quercus_robur", "English Oak"),
    ("wfo-0001005999", "Rosa_canina", "Dog Rose"),
    ("wfo-0000213062", "Trifolium_repens", "White Clover"),
];

// ============================================================================
// Data Loading (reused from generate_sample_encyclopedias.rs)
// ============================================================================

#[cfg(feature = "api")]
fn batch_to_hashmap(
    batches: &[datafusion::arrow::array::RecordBatch],
) -> Option<HashMap<String, serde_json::Value>> {
    if batches.is_empty() || batches[0].num_rows() == 0 {
        return None;
    }
    let mut buf = Vec::new();
    {
        let mut writer = datafusion::arrow::json::ArrayWriter::new(&mut buf);
        for batch in batches {
            writer.write(batch).ok()?;
        }
        writer.finish().ok()?;
    }
    let json_data: Vec<serde_json::Value> = serde_json::from_slice(&buf).ok()?;
    json_data.into_iter().next().and_then(|v| serde_json::from_value(v).ok())
}

#[cfg(feature = "api")]
fn parse_fungal_counts(
    batches: &[datafusion::arrow::array::RecordBatch],
) -> Option<FungalCounts> {
    if batches.is_empty() {
        return None;
    }
    let mut buf = Vec::new();
    {
        let mut writer = datafusion::arrow::json::ArrayWriter::new(&mut buf);
        for batch in batches {
            writer.write(batch).ok()?;
        }
        writer.finish().ok()?;
    }
    let json_data: Vec<serde_json::Value> = serde_json::from_slice(&buf).ok()?;

    let mut amf = 0;
    let mut emf = 0;
    let mut endophytes = 0;
    let mut mycoparasites = 0;
    let mut entomopathogens = 0;
    let mut pathogenic = 0;

    for row in &json_data {
        let guild = row.get("guild")?.as_str()?.to_lowercase();
        let count = row.get("count")?.as_u64()? as usize;

        if guild.contains("amf_fungi") || guild.contains("arbuscular") {
            amf += count;
        } else if guild.contains("emf_fungi") || guild.contains("ectomycorrhiz") {
            emf += count;
        } else if guild.contains("endophytic_fungi") || guild.contains("endophyt") {
            endophytes += count;
        } else if guild.contains("mycoparasite_fungi") || guild.contains("mycoparasit") {
            mycoparasites += count;
        } else if guild.contains("entomopathogenic_fungi") || guild.contains("entomopathogen") {
            entomopathogens += count;
        } else if guild.contains("pathogenic_fungi") || guild == "pathogenic" {
            pathogenic += count;
        }
    }

    if amf + emf + endophytes + mycoparasites + entomopathogens + pathogenic > 0 {
        Some(FungalCounts {
            amf, emf, endophytes, mycoparasites, entomopathogens, pathogenic,
        })
    } else {
        None
    }
}

#[cfg(feature = "api")]
fn parse_organism_lists(
    batches: &[datafusion::arrow::array::RecordBatch],
    master_predators: &HashSet<String>,
) -> Option<OrganismLists> {
    if batches.is_empty() {
        return None;
    }
    let mut buf = Vec::new();
    {
        let mut writer = datafusion::arrow::json::ArrayWriter::new(&mut buf);
        for batch in batches {
            writer.write(batch).ok()?;
        }
        writer.finish().ok()?;
    }
    let json_data: Vec<serde_json::Value> = serde_json::from_slice(&buf).ok()?;

    let mut pollinators = Vec::new();
    let mut herbivores = Vec::new();
    let mut fungivores = Vec::new();
    let mut all_organisms: HashSet<String> = HashSet::new();

    for row in &json_data {
        let source_column = row.get("source_column")?.as_str()?.to_lowercase();
        let organism_taxon = row.get("organism_taxon")?.as_str()?.to_string();

        if organism_taxon.is_empty() {
            continue;
        }

        match source_column.as_str() {
            "pollinators" => pollinators.push(organism_taxon.clone()),
            "herbivores" => herbivores.push(organism_taxon.clone()),
            "fungivores_eats" => fungivores.push(organism_taxon.clone()),
            _ => {}
        }

        all_organisms.insert(organism_taxon);
    }

    let predators: Vec<String> = all_organisms
        .iter()
        .filter(|org| master_predators.contains(&org.to_lowercase()))
        .cloned()
        .collect();

    if pollinators.is_empty() && herbivores.is_empty() && predators.is_empty() && fungivores.is_empty() {
        return None;
    }

    Some(OrganismLists {
        pollinators, herbivores, predators, fungivores,
    })
}

#[cfg(feature = "api")]
fn categorize_organisms(
    lists: &OrganismLists,
    organism_categories: &FxHashMap<String, String>,
) -> OrganismProfile {
    fn group_by_category(
        organisms: &[String],
        role: OrganismRole,
        organism_categories: &FxHashMap<String, String>,
    ) -> Vec<CategorizedOrganisms> {
        let mut category_map: FxHashMap<String, Vec<String>> = FxHashMap::default();

        for org in organisms {
            let category = OrganismCategory::from_name(org, organism_categories, Some(role));
            let category_name = category.display_name().to_string();
            category_map.entry(category_name).or_default().push(org.clone());
        }

        let mut result: Vec<CategorizedOrganisms> = category_map
            .into_iter()
            .map(|(cat, orgs)| CategorizedOrganisms {
                category: cat,
                organisms: orgs,
            })
            .collect();

        result.sort_by(|a, b| {
            let a_is_other = a.category.starts_with("Other");
            let b_is_other = b.category.starts_with("Other");
            match (a_is_other, b_is_other) {
                (true, false) => std::cmp::Ordering::Greater,
                (false, true) => std::cmp::Ordering::Less,
                _ => b.organisms.len().cmp(&a.organisms.len())
                    .then_with(|| a.category.cmp(&b.category))
            }
        });

        result
    }

    OrganismProfile {
        pollinators_by_category: group_by_category(&lists.pollinators, OrganismRole::Pollinator, organism_categories),
        herbivores_by_category: group_by_category(&lists.herbivores, OrganismRole::Herbivore, organism_categories),
        predators_by_category: group_by_category(&lists.predators, OrganismRole::Predator, organism_categories),
        fungivores_by_category: group_by_category(&lists.fungivores, OrganismRole::Predator, organism_categories),
        total_pollinators: lists.pollinators.len(),
        total_herbivores: lists.herbivores.len(),
        total_predators: lists.predators.len(),
        total_fungivores: lists.fungivores.len(),
    }
}

#[cfg(feature = "api")]
fn load_organism_categories() -> FxHashMap<String, String> {
    // The taxonomy CSV is in the main project root
    let csv_path = "/home/olier/ellenberg/data/taxonomy/kimi_gardener_labels.csv".to_string();
    if let Ok(content) = fs::read_to_string(&csv_path) {
        let mut map = FxHashMap::default();
        for line in content.lines().skip(1) {
            let parts: Vec<&str> = line.split(',').collect();
            if parts.len() >= 4 {
                let genus = parts[0].trim().to_lowercase();
                let category = parts[3].trim().to_string();
                if !genus.is_empty() && !category.is_empty() {
                    map.insert(genus, category);
                }
            }
        }
        if !map.is_empty() {
            return map;
        }
    }
    FxHashMap::default()
}

#[cfg(feature = "api")]
async fn load_master_predator_list(engine: &QueryEngine) -> HashSet<String> {
    match engine.get_master_predators().await {
        Ok(batches) => {
            let mut predators = HashSet::new();
            for batch in &batches {
                if let Some(col) = batch.column_by_name("predator_taxon") {
                    if let Some(arr) = col.as_any().downcast_ref::<StringArray>() {
                        for i in 0..arr.len() {
                            if !arr.is_null(i) {
                                predators.insert(arr.value(i).to_lowercase());
                            }
                        }
                    } else if let Some(arr) = col.as_any().downcast_ref::<LargeStringArray>() {
                        for i in 0..arr.len() {
                            if !arr.is_null(i) {
                                predators.insert(arr.value(i).to_lowercase());
                            }
                        }
                    } else if let Some(arr) = col.as_any().downcast_ref::<StringViewArray>() {
                        for i in 0..arr.len() {
                            if !arr.is_null(i) {
                                predators.insert(arr.value(i).to_lowercase());
                            }
                        }
                    }
                }
            }
            predators
        }
        Err(_) => HashSet::new(),
    }
}

#[cfg(feature = "api")]
async fn parse_pathogens_ranked(
    engine: &QueryEngine,
    plant_id: &str,
    limit: usize,
) -> Option<Vec<RankedPathogen>> {
    let batches = engine.get_pathogens(plant_id, Some(limit)).await.ok()?;
    if batches.is_empty() {
        return None;
    }

    let mut pathogens = Vec::new();
    for batch in &batches {
        let taxon_col = batch.column_by_name("pathogen_taxon")?;
        let count_col = batch.column_by_name("observation_count")?;

        let get_taxon = |i: usize| -> Option<String> {
            if let Some(arr) = taxon_col.as_any().downcast_ref::<StringArray>() {
                if !arr.is_null(i) { Some(arr.value(i).to_string()) } else { None }
            } else if let Some(arr) = taxon_col.as_any().downcast_ref::<LargeStringArray>() {
                if !arr.is_null(i) { Some(arr.value(i).to_string()) } else { None }
            } else if let Some(arr) = taxon_col.as_any().downcast_ref::<StringViewArray>() {
                if !arr.is_null(i) { Some(arr.value(i).to_string()) } else { None }
            } else {
                None
            }
        };

        for i in 0..batch.num_rows() {
            let taxon = match get_taxon(i) {
                Some(t) => t,
                None => continue,
            };

            let count = if let Some(arr) = count_col.as_any().downcast_ref::<Int32Array>() {
                arr.value(i) as usize
            } else if let Some(arr) = count_col.as_any().downcast_ref::<Int64Array>() {
                arr.value(i) as usize
            } else if let Some(arr) = count_col.as_any().downcast_ref::<UInt64Array>() {
                arr.value(i) as usize
            } else {
                1
            };

            pathogens.push(RankedPathogen { taxon, observation_count: count });
        }
    }

    if pathogens.is_empty() { None } else { Some(pathogens) }
}

#[cfg(feature = "api")]
async fn parse_beneficial_fungi(
    engine: &QueryEngine,
    plant_id: &str,
) -> Option<BeneficialFungi> {
    let batches = engine.get_beneficial_fungi(plant_id).await.ok()?;
    if batches.is_empty() {
        return None;
    }

    let mut mycoparasites = Vec::new();
    let mut entomopathogens = Vec::new();

    for batch in &batches {
        let source_col = batch.column_by_name("source_column")?;
        let taxon_col = batch.column_by_name("fungus_taxon")?;

        let get_str = |col: &dyn std::any::Any, i: usize| -> Option<String> {
            if let Some(arr) = col.downcast_ref::<StringArray>() {
                if !arr.is_null(i) { Some(arr.value(i).to_string()) } else { None }
            } else if let Some(arr) = col.downcast_ref::<LargeStringArray>() {
                if !arr.is_null(i) { Some(arr.value(i).to_string()) } else { None }
            } else if let Some(arr) = col.downcast_ref::<StringViewArray>() {
                if !arr.is_null(i) { Some(arr.value(i).to_string()) } else { None }
            } else {
                None
            }
        };

        for i in 0..batch.num_rows() {
            let source = get_str(source_col.as_any(), i)?;
            let taxon = get_str(taxon_col.as_any(), i)?;
            match source.as_str() {
                "mycoparasite_fungi" => mycoparasites.push(taxon),
                "entomopathogenic_fungi" => entomopathogens.push(taxon),
                _ => {}
            }
        }
    }

    if mycoparasites.is_empty() && entomopathogens.is_empty() {
        None
    } else {
        Some(BeneficialFungi { mycoparasites, entomopathogens })
    }
}

// ============================================================================
// Discrepancy Tracking
// ============================================================================

#[cfg(feature = "api")]
#[derive(Debug)]
struct Discrepancy {
    section: String,
    field: String,
    md_value: String,
    json_value: String,
}

#[cfg(feature = "api")]
struct ParityChecker {
    discrepancies: Vec<Discrepancy>,
    plant_name: String,
}

#[cfg(feature = "api")]
impl ParityChecker {
    fn new(plant_name: &str) -> Self {
        ParityChecker {
            discrepancies: Vec::new(),
            plant_name: plant_name.to_string(),
        }
    }

    fn check(&mut self, section: &str, field: &str, md_value: &str, json_value: &str) {
        let md_norm = md_value.trim();
        let json_norm = json_value.trim();
        if md_norm != json_norm {
            self.discrepancies.push(Discrepancy {
                section: section.to_string(),
                field: field.to_string(),
                md_value: md_norm.to_string(),
                json_value: json_norm.to_string(),
            });
        }
    }

    fn check_approx(&mut self, section: &str, field: &str, md_value: f64, json_value: f64, tolerance: f64) {
        if (md_value - json_value).abs() > tolerance {
            self.discrepancies.push(Discrepancy {
                section: section.to_string(),
                field: field.to_string(),
                md_value: format!("{:.2}", md_value),
                json_value: format!("{:.2}", json_value),
            });
        }
    }

    fn check_int(&mut self, section: &str, field: &str, md_value: i64, json_value: i64) {
        if md_value != json_value {
            self.discrepancies.push(Discrepancy {
                section: section.to_string(),
                field: field.to_string(),
                md_value: format!("{}", md_value),
                json_value: format!("{}", json_value),
            });
        }
    }

    fn report(&self) -> usize {
        if self.discrepancies.is_empty() {
            println!("  [PASS] {} - All values match", self.plant_name);
        } else {
            println!("  [FAIL] {} - {} discrepancies:", self.plant_name, self.discrepancies.len());
            for d in &self.discrepancies {
                println!("    {} / {}:", d.section, d.field);
                println!("      MD:   \"{}\"", d.md_value);
                println!("      JSON: \"{}\"", d.json_value);
            }
        }
        self.discrepancies.len()
    }
}

// ============================================================================
// MD Parsing Helpers (no regex)
// ============================================================================

#[cfg(feature = "api")]
fn extract_between(md: &str, start: &str, end: &str) -> Option<String> {
    let start_idx = md.find(start)?;
    let after_start = &md[start_idx + start.len()..];
    let end_idx = after_start.find(end)?;
    Some(after_start[..end_idx].trim().to_string())
}

#[cfg(feature = "api")]
fn extract_number(s: &str) -> Option<f64> {
    // Find first number in string
    let mut num_start = None;
    let mut num_end = 0;

    for (i, c) in s.char_indices() {
        if c.is_ascii_digit() || c == '.' || c == '-' {
            if num_start.is_none() {
                num_start = Some(i);
            }
            num_end = i + 1;
        } else if num_start.is_some() {
            break;
        }
    }

    if let Some(start) = num_start {
        let num_str = &s[start..num_end];
        num_str.parse().ok()
    } else {
        None
    }
}

#[cfg(feature = "api")]
fn extract_count_before(s: &str, pattern: &str) -> Option<i64> {
    // Extract number that appears before a pattern like "pollinator"
    let idx = s.find(pattern)?;
    let before = &s[..idx];
    // Find last number before pattern
    let mut last_num: Option<i64> = None;
    let mut current_num = String::new();

    for c in before.chars() {
        if c.is_ascii_digit() {
            current_num.push(c);
        } else if !current_num.is_empty() {
            if let Ok(n) = current_num.parse() {
                last_num = Some(n);
            }
            current_num.clear();
        }
    }
    if !current_num.is_empty() {
        if let Ok(n) = current_num.parse() {
            last_num = Some(n);
        }
    }
    last_num
}

// ============================================================================
// Section Comparisons
// ============================================================================

#[cfg(feature = "api")]
fn compare_s2_requirements(checker: &mut ParityChecker, md: &str, json: &EncyclopediaPageData) {
    // S2: Light - EIVE-L value
    if let Some(line) = md.lines().find(|l| l.contains("Light preference (EIVE-L)")) {
        if let Some(md_eive) = extract_number(line) {
            if let Some(json_eive) = json.requirements.light.eive_l {
                checker.check_approx("S2", "light.eive_l", md_eive, json_eive, 0.1);
            }
        }
    }

    // Light category
    let light_cats = ["Full sun", "Partial shade", "Deep shade", "Sun to partial shade"];
    for cat in light_cats {
        if md.contains(cat) {
            if !json.requirements.light.category.contains(cat) {
                checker.check("S2", "light.category", cat, &json.requirements.light.category);
            }
            break;
        }
    }

    // S2: Temperature - frost days
    if let Some(line) = md.lines().find(|l| l.contains("Frost Days")) {
        if let Some(md_val) = extract_number(line) {
            for detail in &json.requirements.temperature.details {
                if detail.to_lowercase().contains("frost days") {
                    if let Some(json_val) = extract_number(detail) {
                        checker.check_approx("S2", "temperature.frost_days", md_val, json_val, 5.0);
                        break;
                    }
                }
            }
        }
    }

    // S2: Moisture - annual rainfall
    if let Some(section) = extract_between(md, "### Moisture", "###") {
        if let Some(line) = section.lines().find(|l| l.contains("mm/year")) {
            if let Some(md_val) = extract_number(line) {
                if let Some(ref rainfall) = json.requirements.moisture.rainfall_mm {
                    checker.check_approx("S2", "moisture.rainfall_typical", md_val, rainfall.typical, 50.0);
                }
            }
        }
    }

    // S2: Soil pH
    if let Some(section) = extract_between(md, "### Soil", "---") {
        if let Some(line) = section.lines().find(|l| l.contains("pH") && l.contains("Topsoil")) {
            if let Some(md_val) = extract_number(line) {
                if let Some(ref ph) = json.requirements.soil.ph {
                    checker.check_approx("S2", "soil.ph.value", md_val, ph.value, 0.5);
                }
            }
        }
    }
}

#[cfg(feature = "api")]
fn compare_s3_maintenance(checker: &mut ParityChecker, md: &str, json: &EncyclopediaPageData) {
    // S3: CSR values - extract from Maintenance Profile section only
    if let Some(section) = extract_between(md, "## Maintenance Profile", "---") {
        // C value - find "C XX%" pattern
        for line in section.lines() {
            if line.contains("C ") && line.contains("%") {
                if let Some(md_c) = extract_number(line) {
                    checker.check_approx("S3", "csr.c_percent", md_c, json.maintenance.csr_strategy.c_percent, 1.0);
                    break;
                }
            }
        }
        // S value
        for line in section.lines() {
            if line.contains("S ") && line.contains("%") && line.contains("/") {
                // Find S value after C in "C 45% / S 41% / R 14%"
                if let Some(s_idx) = line.find("S ") {
                    let after_s = &line[s_idx..];
                    if let Some(md_s) = extract_number(after_s) {
                        checker.check_approx("S3", "csr.s_percent", md_s, json.maintenance.csr_strategy.s_percent, 1.0);
                        break;
                    }
                }
            }
        }
        // R value
        for line in section.lines() {
            if line.contains("R ") && line.contains("%") && line.contains("/") {
                // Find R value after S in "C 45% / S 41% / R 14%"
                if let Some(r_idx) = line.find("R ") {
                    let after_r = &line[r_idx..];
                    if let Some(md_r) = extract_number(after_r) {
                        checker.check_approx("S3", "csr.r_percent", md_r, json.maintenance.csr_strategy.r_percent, 1.0);
                        break;
                    }
                }
            }
        }

        // Maintenance level - look for "Effort Level:" in section
        for line in section.lines() {
            if line.contains("Effort Level") {
                let upper = line.to_uppercase();
                let json_label = json.maintenance.level.label().to_uppercase();
                // Check if the MD line contains the JSON level (case insensitive)
                if !upper.contains(&json_label) {
                    // Extract what MD says
                    let md_level = if upper.contains("MEDIUM-HIGH") {
                        "Medium-High"
                    } else if upper.contains("LOW-MEDIUM") {
                        "Low-Medium"
                    } else if upper.contains("HIGH") {
                        "High"
                    } else if upper.contains("MEDIUM") {
                        "Medium"
                    } else if upper.contains("LOW") {
                        "Low"
                    } else {
                        "Unknown"
                    };
                    checker.check("S3", "maintenance.level", md_level, json.maintenance.level.label());
                }
                break;
            }
        }
    }
}

#[cfg(feature = "api")]
fn compare_s4_services(checker: &mut ParityChecker, md: &str, json: &EncyclopediaPageData) {
    // Nitrogen fixer flag - look specifically in Ecosystem Services section
    // The MD says either "Does not fix atmospheric nitrogen" or indicates it IS a nitrogen fixer
    let md_nfixer = if let Some(section) = extract_between(md, "## Ecosystem Services", "---") {
        // Look for positive indicators of nitrogen fixation
        section.contains("fixes atmospheric nitrogen") ||
        section.contains("is a nitrogen fixer") ||
        section.contains("Nitrogen Fixer: Yes") ||
        // Also check for high N-fixation rating (but not "Unable to Classify")
        (section.contains("Nitrogen Fixation") && !section.contains("Unable to Classify") && !section.contains("Does not fix"))
    } else {
        false
    };

    if md_nfixer != json.services.nitrogen_fixer {
        checker.check(
            "S4",
            "nitrogen_fixer",
            if md_nfixer { "true" } else { "false" },
            if json.services.nitrogen_fixer { "true" } else { "false" },
        );
    }

    // Check ecosystem ratings if present
    if let Some(ref ratings) = json.services.ratings {
        // NPP rating - check that the rating level matches
        if let Some(_score) = ratings.npp.score {
            // The MD format is like "**Net Primary Productivity**: Very High (5.0)"
            if let Some(section) = extract_between(md, "## Ecosystem Services", "---") {
                if let Some(line) = section.lines().find(|l| l.contains("Net Primary Productivity")) {
                    let json_rating = &ratings.npp.rating;
                    if !line.contains(json_rating.as_str()) {
                        checker.check("S4", "npp.rating", line.trim(), json_rating);
                    }
                }
            }
        }
    }
}

#[cfg(feature = "api")]
fn compare_s5_interactions(checker: &mut ParityChecker, md: &str, json: &EncyclopediaPageData) {
    // S5: Pollinator count
    if let Some(section) = extract_between(md, "### Pollinators", "###") {
        if let Some(md_count) = extract_count_before(&section, "pollinator") {
            checker.check_int("S5", "pollinators.total_count", md_count, json.interactions.pollinators.total_count as i64);
        }
    }

    // S5: Herbivore count
    if let Some(section) = extract_between(md, "### Herbivores", "###") {
        if let Some(md_count) = extract_count_before(&section, "pest") {
            checker.check_int("S5", "herbivores.total_count", md_count, json.interactions.herbivores.total_count as i64);
        } else if let Some(md_count) = extract_count_before(&section, "herbivore") {
            checker.check_int("S5", "herbivores.total_count", md_count, json.interactions.herbivores.total_count as i64);
        }
    }

    // S5: Pollinator level classification
    let poll_levels = ["Exceptional", "Very High", "Above average", "Typical", "Low", "Minimal"];
    if let Some(section) = extract_between(md, "### Pollinators", "###") {
        for level in poll_levels {
            if section.contains(&format!("**{}**", level)) {
                if !json.interactions.pollinators.level.contains(level) {
                    checker.check("S5", "pollinators.level", level, &json.interactions.pollinators.level);
                }
                break;
            }
        }
    }

    // S5: Disease level classification
    let disease_levels = ["High", "Above average", "Typical", "Low"];
    if let Some(section) = extract_between(md, "### Diseases", "###") {
        for level in disease_levels {
            if section.contains(&format!("**{}**", level)) {
                if !json.interactions.diseases.disease_level.contains(level) {
                    checker.check("S5", "diseases.disease_level", level, &json.interactions.diseases.disease_level);
                }
                break;
            }
        }
    }

    // S5: Mycorrhizal type
    let myco_types = ["EMF", "AMF", "Dual", "Non-mycorrhizal"];
    for mtype in myco_types {
        if md.contains(mtype) && md.to_lowercase().contains("mycorrhiz") {
            if !json.interactions.mycorrhizal_type.contains(mtype) {
                // Allow "Non-mycorrhizal" to match "None"
                if !(mtype == "Non-mycorrhizal" && json.interactions.mycorrhizal_type.contains("Non")) {
                    checker.check("S5", "mycorrhizal_type", mtype, &json.interactions.mycorrhizal_type);
                }
            }
            break;
        }
    }

    // S5: Pathogen count
    if let Some(section) = extract_between(md, "### Diseases", "###") {
        if let Some(md_count) = extract_count_before(&section, "pathogen") {
            checker.check_int("S5", "diseases.pathogen_count", md_count, json.interactions.diseases.pathogen_count as i64);
        } else if let Some(md_count) = extract_count_before(&section, "disease") {
            checker.check_int("S5", "diseases.pathogen_count", md_count, json.interactions.diseases.pathogen_count as i64);
        }
    }
}

#[cfg(feature = "api")]
fn compare_s6_companion(checker: &mut ParityChecker, md: &str, json: &EncyclopediaPageData) {
    // S6: Structural layer
    if let Some(ref details) = json.companion.guild_details {
        // Structural layer - look in GP1 section
        if let Some(section) = extract_between(md, "### GP1", "###") {
            let layers = ["Canopy", "Understory", "Shrub", "Herbaceous", "Ground Cover"];
            for layer in layers {
                if section.contains(layer) {
                    if !details.structural_role.layer.contains(layer) {
                        checker.check("S6", "structural_role.layer", layer, &details.structural_role.layer);
                    }
                    break;
                }
            }
        }

        // CSR classification dominant - look in GP2 section
        if let Some(section) = extract_between(md, "### GP2", "###") {
            // Find which dominant type is mentioned
            let md_dominant = if section.contains("C-dominant") || section.contains("C dominant") {
                "C-dominant"
            } else if section.contains("S-dominant") || section.contains("S dominant") {
                "S-dominant"
            } else if section.contains("R-dominant") || section.contains("R dominant") {
                "R-dominant"
            } else if section.contains("Competitor") && !section.contains("Stress") && !section.contains("Ruderal") {
                "Competitor"
            } else if section.contains("Stress-tolerator") {
                "Stress-tolerator"
            } else if section.contains("Ruderal") {
                "Ruderal"
            } else {
                ""
            };

            if !md_dominant.is_empty() {
                let json_csr = &details.growth_compatibility.classification;
                // Check if JSON contains the same dominant type
                let json_matches = json_csr.contains("C-dominant") && md_dominant.contains("C") ||
                                   json_csr.contains("S-dominant") && md_dominant.contains("S-dominant") ||
                                   json_csr.contains("R-dominant") && md_dominant.contains("R-dominant") ||
                                   json_csr.contains("Competitor") && md_dominant == "Competitor" ||
                                   json_csr.contains("Stress-tolerator") && md_dominant == "Stress-tolerator" ||
                                   json_csr.contains("Ruderal") && md_dominant == "Ruderal";
                if !json_matches {
                    checker.check("S6", "growth_compatibility.classification", md_dominant, json_csr);
                }
            }
        }

        // Mycorrhizal network type - look in GP3 section
        if let Some(section) = extract_between(md, "### GP3", "###") {
            let net_types = ["EMF", "AMF", "Dual", "Non-mycorrhizal"];
            for ntype in net_types {
                if section.contains(ntype) {
                    let json_net = &details.mycorrhizal_network.network_type;
                    if !json_net.contains(ntype) {
                        checker.check("S6", "mycorrhizal_network.network_type", ntype, json_net);
                    }
                    break;
                }
            }
        }
    }
}

// ============================================================================
// Main
// ============================================================================

#[cfg(feature = "api")]
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    println!("=================================================================");
    println!("JSON/MD Output Parity Verification");
    println!("=================================================================\n");

    // Initialize
    let data_dir = get_data_dir();
    println!("Using data directory: {}\n", data_dir);
    let engine = QueryEngine::new(&data_dir).await?;
    let md_generator = EncyclopediaGenerator::new();
    let organism_categories = load_organism_categories();
    let master_predators = load_master_predator_list(&engine).await;

    println!("Loaded {} organism categories, {} master predators\n",
             organism_categories.len(), master_predators.len());

    let mut total_discrepancies = 0;

    for (wfo_id, filename, description) in SAMPLE_PLANTS {
        println!("Checking: {} ({})", filename.replace('_', " "), description);

        // Load plant data
        let plant_batches = engine.get_plant(wfo_id).await?;
        let plant_data = batch_to_hashmap(&plant_batches)
            .ok_or_else(|| anyhow::anyhow!("Plant {} not found", wfo_id))?;

        // Load organism data
        let organism_lists = engine
            .get_organisms(wfo_id, None)
            .await
            .ok()
            .and_then(|b| parse_organism_lists(&b, &master_predators));

        let organism_profile = organism_lists
            .as_ref()
            .map(|lists| categorize_organisms(lists, &organism_categories));

        let organism_counts = organism_lists
            .as_ref()
            .map(|lists| lists.to_counts());

        // Load fungal data
        let fungal_counts = engine
            .get_fungi_summary(wfo_id)
            .await
            .ok()
            .and_then(|b| parse_fungal_counts(&b));

        let ranked_pathogens = parse_pathogens_ranked(&engine, wfo_id, 10).await;
        let beneficial_fungi = parse_beneficial_fungi(&engine, wfo_id).await;

        // Generate MD
        let md_output = md_generator.generate(
            wfo_id,
            &plant_data,
            organism_counts.clone(),
            fungal_counts.clone(),
            organism_profile.clone(),
            ranked_pathogens.clone(),
            beneficial_fungi.clone(),
            None, // no relatives for this test
            0,
        ).map_err(|e| anyhow::anyhow!(e))?;

        // Generate JSON
        let json_output = generate_encyclopedia_data(
            wfo_id,
            &plant_data,
            organism_profile.as_ref(),
            fungal_counts.as_ref(),
            ranked_pathogens.as_deref(),
            beneficial_fungi.as_ref(),
            None, // no relatives
            0,
            None, // no local conditions
        ).map_err(|e| anyhow::anyhow!(e))?;

        // Compare
        let mut checker = ParityChecker::new(&format!("{} ({})", filename, description));

        compare_s2_requirements(&mut checker, &md_output, &json_output);
        compare_s3_maintenance(&mut checker, &md_output, &json_output);
        compare_s4_services(&mut checker, &md_output, &json_output);
        compare_s5_interactions(&mut checker, &md_output, &json_output);
        compare_s6_companion(&mut checker, &md_output, &json_output);

        total_discrepancies += checker.report();
        println!();
    }

    println!("=================================================================");
    if total_discrepancies == 0 {
        println!("RESULT: All checks passed - MD and JSON outputs are equivalent");
    } else {
        println!("RESULT: {} total discrepancies found", total_discrepancies);
    }
    println!("=================================================================");

    Ok(())
}

#[cfg(not(feature = "api"))]
fn main() {
    eprintln!("This binary requires the 'api' feature. Run with: cargo run --features api --bin verify_json_parity");
}
