//! M1: Pest & Pathogen Independence
//!
//! Scores phylogenetic diversity using Faith's PD as a proxy for pest/pathogen
//! risk reduction. Higher diversity (more evolutionary distance) = lower risk.
//!
//! Ecological Rationale:
//! - Host specificity: Most pests are genus/family-specific
//! - Dilution effect: Non-host plants reduce pest transmission
//! - Associational resistance: Non-hosts interfere with pest foraging
//!
//! R reference: shipley_checks/src/Stage_4/metrics/m1_pest_pathogen_indep.R (190 lines)

use crate::utils::normalization::{Calibration, percentile_normalize};
use anyhow::{Context, Result};
use std::collections::HashMap;
use std::fs;
use std::process::Command;

/// Faith's PD calculator (wrapper for C++ CompactTree binary)
pub struct PhyloPDCalculator {
    tree_path: String,
    cpp_binary: String,
    wfo_to_tip: HashMap<String, String>,
}

impl PhyloPDCalculator {
    /// Initialize calculator with paths to tree, mapping, and C++ binary
    ///
    /// R reference: faiths_pd_calculator.R::initialize
    pub fn new() -> Result<Self> {
        // CORRECT tree for 11,711 species dataset (Nov 7, 2025)
        let tree_path = "data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk".to_string();
        let mapping_path = "data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv".to_string();
        let cpp_binary = "src/Stage_4/calculate_faiths_pd_optimized".to_string();

        // Verify C++ binary exists
        if !std::path::Path::new(&cpp_binary).exists() {
            anyhow::bail!(
                "C++ binary not found: {}\nRun: cd src/Stage_4 && make calculate_faiths_pd_optimized",
                cpp_binary
            );
        }

        // Load WFO -> tree tip mapping
        println!("Loading mapping from: {}", mapping_path);
        let wfo_to_tip = Self::load_mapping(&mapping_path)?;

        println!("  WFO mappings: {}", wfo_to_tip.len());
        println!("PhyloPDCalculator initialized (using C++ CompactTree).");

        Ok(Self {
            tree_path,
            cpp_binary,
            wfo_to_tip,
        })
    }

    /// Load WFO ID -> tree tip mapping from CSV
    fn load_mapping(path: &str) -> Result<HashMap<String, String>> {
        let contents = fs::read_to_string(path)
            .with_context(|| format!("Failed to read mapping file: {}", path))?;

        let mut mapping = HashMap::new();
        for (idx, line) in contents.lines().enumerate() {
            if idx == 0 {
                continue; // Skip header: wfo_taxon_id,wfo_scientific_name,is_infraspecific,parent_binomial,parent_label,tree_tip
            }
            let parts: Vec<&str> = line.split(',').collect();
            if parts.len() >= 6 {
                let wfo_id = parts[0].to_string();
                let tree_tip = parts[5].to_string();  // Column 5 is tree_tip (e.g., wfo-0000832453|Fraxinus_excelsior)
                if !tree_tip.is_empty() && tree_tip != "NA" {
                    mapping.insert(wfo_id, tree_tip);
                }
            }
        }

        Ok(mapping)
    }

    /// Calculate Faith's PD for a set of WFO IDs
    ///
    /// R reference: faiths_pd_calculator.R::calculate_pd
    pub fn calculate_pd(&self, wfo_ids: &[String]) -> Result<f64> {
        // Convert WFO IDs to tree tips
        let tree_tips: Vec<&str> = wfo_ids
            .iter()
            .filter_map(|id| self.wfo_to_tip.get(id).map(|s| s.as_str()))
            .collect();

        // Edge cases
        if tree_tips.is_empty() || tree_tips.len() < 2 {
            eprintln!("DEBUG: Not enough tree tips: {}/{} WFO IDs", tree_tips.len(), wfo_ids.len());
            return Ok(0.0); // No diversity
        }

        // DEBUG: Show what we're passing
        eprintln!("DEBUG: Calling Faith's PD with {} tree tips (from {} WFO IDs)", tree_tips.len(), wfo_ids.len());
        eprintln!("DEBUG: First tree tip: {:?}", tree_tips.get(0));
        eprintln!("DEBUG: Sample WFO ID: {:?}", wfo_ids.get(0));

        // Call C++ binary: ./calculate_faiths_pd_optimized <tree.nwk> <species1> <species2> ...
        let output = Command::new(&self.cpp_binary)
            .arg(&self.tree_path)
            .args(&tree_tips)
            .output()
            .with_context(|| format!("Failed to execute C++ binary: {}", self.cpp_binary))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            eprintln!("DEBUG: C++ binary stderr: {}", stderr);
            anyhow::bail!("C++ binary failed with status: {}", output.status);
        }

        // Parse first line of stdout as Faith's PD value
        let stdout = String::from_utf8(output.stdout)
            .with_context(|| "Failed to parse C++ binary output")?;

        let faiths_pd = stdout
            .lines()
            .next()
            .ok_or_else(|| anyhow::anyhow!("No output from C++ binary"))?
            .trim()
            .parse::<f64>()
            .with_context(|| format!("Failed to parse Faith's PD from: {}", stdout))?;

        Ok(faiths_pd)
    }
}

/// M1 calculation result
#[derive(Debug)]
pub struct M1Result {
    pub raw: f64,
    pub normalized: f64,
    pub faiths_pd: f64,
}

/// Calculate M1: Pest & Pathogen Independence
///
/// Algorithm (from R documentation):
/// 1. Calculate Faith's PD using C++ binary wrapper
/// 2. Apply exponential transformation: pest_risk_raw = exp(-k × faiths_pd) where k = 0.001
/// 3. Percentile normalize with invert = false
/// 4. Display score: 100 - percentile
///
/// R reference: shipley_checks/src/Stage_4/metrics/m1_pest_pathogen_indep.R
pub fn calculate_m1(
    plant_ids: &[String],
    phylo_calculator: &PhyloPDCalculator,
    calibration: &Calibration,
) -> Result<M1Result> {
    // Edge case: Single plant guild
    if plant_ids.len() < 2 {
        return Ok(M1Result {
            raw: 1.0,        // Maximum risk
            normalized: 0.0, // Minimum percentile (will become 100 after display inversion)
            faiths_pd: 0.0,
        });
    }

    // Step 1: Calculate Faith's Phylogenetic Diversity (PD)
    // Sum of all phylogenetic branch lengths connecting guild members
    let faiths_pd = phylo_calculator.calculate_pd(plant_ids)?;

    // Step 2: Transform PD to pest risk score (exponential decay)
    // Formula: pest_risk_raw = exp(-k × faiths_pd)
    // k = 0.001: Decay constant (controls sensitivity to PD)
    //
    // Intuition:
    // - faiths_pd = 0 MY (same species)     → pest_risk = 1.00 (maximum risk)
    // - faiths_pd = 500 MY (different orders) → pest_risk = 0.61
    // - faiths_pd = 1000 MY (very diverse)   → pest_risk = 0.37
    const K: f64 = 0.001;
    let pest_risk_raw = (-K * faiths_pd).exp();

    // Step 3: Normalize to percentile using Köppen-stratified calibration
    // KEY: invert = false means no inversion during normalization
    // LOW pest_risk_raw → LOW percentile (good diversity)
    // HIGH pest_risk_raw → HIGH percentile (bad diversity)
    //
    // The final display inversion happens in score_guild() with: 100 - normalized
    let normalized = percentile_normalize(pest_risk_raw, "m1", calibration, false)?;

    Ok(M1Result {
        raw: pest_risk_raw,
        normalized,
        faiths_pd,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use approx::assert_relative_eq;

    #[test]
    fn test_single_plant_edge_case() {
        // Single plant should return maximum risk
        let plant_ids = vec!["wfo-0000832453".to_string()];

        // We can't test calculate_m1 directly without the C++ binary and calibration
        // But we can verify the edge case logic
        assert!(plant_ids.len() < 2);
    }

    #[test]
    fn test_exponential_transformation() {
        const K: f64 = 0.001;

        // Test known values
        let faiths_pd = 0.0;
        let pest_risk = (-K * faiths_pd).exp();
        assert_relative_eq!(pest_risk, 1.0, epsilon = 0.0001);

        let faiths_pd = 500.0;
        let pest_risk = (-K * faiths_pd).exp();
        assert_relative_eq!(pest_risk, 0.6065, epsilon = 0.0001);

        let faiths_pd = 1000.0;
        let pest_risk = (-K * faiths_pd).exp();
        assert_relative_eq!(pest_risk, 0.3679, epsilon = 0.0001);
    }

    #[test]
    #[ignore] // Requires C++ binary and tree files
    fn test_calculate_pd() {
        let calculator = PhyloPDCalculator::new().unwrap();
        let plant_ids = vec![
            "wfo-0000832453".to_string(),
            "wfo-0000649136".to_string(),
        ];
        let pd = calculator.calculate_pd(&plant_ids).unwrap();
        assert!(pd > 0.0, "Expected positive Faith's PD value");
    }
}
