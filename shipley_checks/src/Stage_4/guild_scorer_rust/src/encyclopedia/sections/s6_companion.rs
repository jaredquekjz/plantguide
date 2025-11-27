//! S6: Guild Potential (Companion Planting)
//!
//! Static recommendations based on THIS plant's characteristics, derived from
//! GuildBuilder metric logic. Shows the plant's guild-relevant traits and
//! provides companion selection guidance.
//!
//! Data provenance: Biotic interaction data (pests, diseases, pollinators, fungi)
//! are derived from GloBI observation records. Counts reflect the number of
//! distinct species observed interacting with this plant.
//!
//! GP1: Phylogenetic Independence (from M1)
//! GP2: Growth Compatibility (from M2) - uses PERCENTILE-based CSR thresholds
//! GP3: Pest Control Contribution (from M3)
//! GP4: Disease Control Contribution (from M4)
//! GP5: Mycorrhizal Network (from M5)
//! GP6: Structural Role (from M6)
//! GP7: Pollinator Contribution (from M7)

use std::collections::HashMap;
use serde_json::Value;
use crate::encyclopedia::types::*;
use crate::encyclopedia::utils::classify::*;

/// Try to get EIVE value from either column format
fn get_eive(data: &HashMap<String, Value>, axis: &str) -> Option<f64> {
    // Try new format first (plants_searchable), then old format (master dataset)
    get_f64(data, &format!("EIVE_{}_complete", axis))
        .or_else(|| get_f64(data, &format!("EIVEres-{}_complete", axis)))
        .or_else(|| get_f64(data, &format!("EIVE_{}", axis)))
        .or_else(|| get_f64(data, &format!("EIVEres-{}", axis)))
}

/// Generate the S6 Guild Potential section.
pub fn generate(
    data: &HashMap<String, Value>,
    organism_counts: Option<&OrganismCounts>,
    fungal_counts: Option<&FungalCounts>,
) -> String {
    let mut sections = Vec::new();
    sections.push("## Guild Potential".to_string());

    // Summary Card
    sections.push(String::new());
    sections.push(generate_summary_card(data, organism_counts, fungal_counts));

    // GP1: Phylogenetic Independence
    sections.push(String::new());
    sections.push(generate_gp1(data));

    // GP2: Growth Compatibility
    sections.push(String::new());
    sections.push(generate_gp2(data));

    // GP3: Pest Control Contribution
    sections.push(String::new());
    sections.push(generate_gp3(data, organism_counts, fungal_counts));

    // GP4: Disease Control Contribution
    sections.push(String::new());
    sections.push(generate_gp4(fungal_counts));

    // GP5: Mycorrhizal Network
    sections.push(String::new());
    sections.push(generate_gp5(fungal_counts));

    // GP6: Structural Role
    sections.push(String::new());
    sections.push(generate_gp6(data));

    // GP7: Pollinator Contribution
    sections.push(String::new());
    sections.push(generate_gp7(organism_counts));

    // Cautions
    sections.push(String::new());
    sections.push(generate_cautions(data, organism_counts, fungal_counts));

    sections.join("\n")
}

fn generate_summary_card(
    data: &HashMap<String, Value>,
    organism_counts: Option<&OrganismCounts>,
    fungal_counts: Option<&FungalCounts>,
) -> String {
    let mut lines = Vec::new();
    lines.push("### At a Glance".to_string());
    lines.push(String::new());
    lines.push("*Quick reference for companion selection. See detailed sections below for full guidance.*".to_string());
    lines.push(String::new());

    // Extract values needed for table and principles
    let family = get_str(data, "family").unwrap_or("Unknown");
    let genus = get_str(data, "genus").unwrap_or("Unknown");
    let c = get_f64(data, "C").unwrap_or(0.0);
    let s = get_f64(data, "S").unwrap_or(0.0);
    let r = get_f64(data, "R").unwrap_or(0.0);
    let csr = classify_csr_percentile(c, s, r);
    let height = get_f64(data, "height_m");
    let layer = classify_structural_layer(height);
    let (amf, emf) = fungal_counts.map(|c| (c.amf, c.emf)).unwrap_or((0, 0));
    let myco = classify_mycorrhizal(amf, emf);
    let herbivores = organism_counts.map(|c| c.herbivores).unwrap_or(0);
    let predators = organism_counts.map(|c| c.predators).unwrap_or(0);
    let entomopath = fungal_counts.map(|c| c.entomopathogens).unwrap_or(0);
    let mycoparasites = fungal_counts.map(|c| c.mycoparasites).unwrap_or(0);
    let pollinators = organism_counts.map(|c| c.pollinators).unwrap_or(0);
    let (poll_level, _) = classify_pollinator_level(pollinators);

    // Summary table with section references
    lines.push("| Aspect | This Plant | Companion Guidance | Details |".to_string());
    lines.push("|--------|------------|-------------------|---------|".to_string());

    lines.push(format!(
        "| **Taxonomy** | {} → {} | Seek different families | [Taxonomy](#taxonomy) |",
        family, genus
    ));

    lines.push(format!(
        "| **Growth Strategy** | C:{:.0}% S:{:.0}% R:{:.0}% | {} | [Growth](#growth-compatibility) |",
        c, s, r, csr_short_guidance(csr)
    ));

    lines.push(format!(
        "| **Structure** | {} ({}) | {} | [Structure](#structural-role) |",
        layer.label(),
        height.map(|h| format!("{:.1}m", h)).unwrap_or_else(|| "?".to_string()),
        structural_short_guidance(layer)
    ));

    lines.push(format!(
        "| **Mycorrhizal** | {} | {} | [Network](#mycorrhizal-network) |",
        myco.label(),
        myco_short_guidance(myco)
    ));

    lines.push(format!(
        "| **Pest Control** | {} pests, {} predators | {} | [Pests](#pest-control) |",
        herbivores,
        predators + entomopath,
        pest_short_guidance(herbivores, predators)
    ));

    lines.push(format!(
        "| **Disease Control** | {} disease fighters | {} | [Disease](#disease-control) |",
        mycoparasites,
        disease_short_guidance(mycoparasites)
    ));

    lines.push(format!(
        "| **Pollinators** | {} species | {} | [Pollinators](#pollinator-support) |",
        pollinators,
        poll_level
    ));

    // Key Companion Principles (merged from old "Top Companion Principles")
    lines.push(String::new());
    lines.push("**Key Principles for This Plant:**".to_string());

    lines.push(format!("1. **Diversify taxonomy** - seek plants from different families than {}", family));

    let csr_guidance = match csr {
        CsrStrategy::CDominant => "avoid other C-dominant plants at same height",
        CsrStrategy::SDominant => "compatible with most strategies",
        CsrStrategy::RDominant => "pair with longer-lived S or balanced plants",
        CsrStrategy::Balanced => "flexible positioning; compatible with most",
    };
    lines.push(format!("2. **Growth compatibility** - {}", csr_guidance));

    let layer_guidance = match layer {
        StructuralLayer::Canopy | StructuralLayer::SubCanopy => "pair with shade-tolerant understory",
        StructuralLayer::TallShrub => "works as mid-layer; ground covers below",
        StructuralLayer::Understory | StructuralLayer::GroundCover => "can grow under taller plants",
    };
    lines.push(format!("3. **Layer plants** - {}", layer_guidance));

    let myco_guidance = match myco {
        MycorrhizalType::AMF => "seek other AMF-associated plants for network benefits",
        MycorrhizalType::EMF => "seek other EMF-associated plants for network benefits",
        MycorrhizalType::Dual => "bridges both network types - very flexible",
        MycorrhizalType::NonMycorrhizal => "no underground network constraints",
    };
    lines.push(format!("4. **Fungal network** - {}", myco_guidance));

    lines.join("\n")
}

fn csr_short_guidance(csr: CsrStrategy) -> &'static str {
    match csr {
        CsrStrategy::CDominant => "Avoid C-C pairs",
        CsrStrategy::SDominant => "Good with most",
        CsrStrategy::RDominant => "Plan succession",
        CsrStrategy::Balanced => "Flexible",
    }
}

fn structural_short_guidance(layer: StructuralLayer) -> &'static str {
    match layer {
        StructuralLayer::Canopy => "Shade provider",
        StructuralLayer::SubCanopy => "Partial shade",
        StructuralLayer::TallShrub => "Mid-layer",
        StructuralLayer::Understory => "Shade user",
        StructuralLayer::GroundCover => "Soil protection",
    }
}

fn myco_short_guidance(myco: MycorrhizalType) -> &'static str {
    match myco {
        MycorrhizalType::AMF => "Connect with AMF plants",
        MycorrhizalType::EMF => "Connect with EMF plants",
        MycorrhizalType::Dual => "Bridges both networks",
        MycorrhizalType::NonMycorrhizal => "No network benefit",
    }
}

fn pest_short_guidance(herbivores: usize, predators: usize) -> &'static str {
    if predators >= 9 {
        "Strong biocontrol habitat"
    } else if herbivores >= 15 {
        "Benefits from predator plants"
    } else {
        "Typical"
    }
}

fn disease_short_guidance(mycoparasites: usize) -> &'static str {
    if mycoparasites > 0 {
        "Hosts disease fighters"
    } else {
        "No documented antagonists"
    }
}

// ============================================================================
// GP1: Phylogenetic Independence
// ============================================================================

fn generate_gp1(data: &HashMap<String, Value>) -> String {
    let mut lines = Vec::new();
    lines.push("### Taxonomy".to_string());
    lines.push(String::new());

    let family = get_str(data, "family").unwrap_or("Unknown");
    let genus = get_str(data, "genus").unwrap_or("Unknown");

    lines.push(format!("**Family**: {}", family));
    lines.push(format!("**Genus**: {}", genus));
    lines.push(String::new());
    lines.push("**Guild Recommendation**:".to_string());
    lines.push("- Avoid clustering plants from the same genus (highest shared pest risk)".to_string());
    lines.push(format!("- Diversify beyond {} for reduced pathogen transmission", family));
    lines.push("- Greater taxonomic distance = lower shared vulnerability".to_string());

    lines.join("\n")
}

// ============================================================================
// GP2: Growth Compatibility (PERCENTILE-based CSR)
// ============================================================================

fn generate_gp2(data: &HashMap<String, Value>) -> String {
    let mut lines = Vec::new();
    lines.push("### Growth Compatibility".to_string());
    lines.push(String::new());

    let c = get_f64(data, "C").unwrap_or(0.0);
    let s = get_f64(data, "S").unwrap_or(0.0);
    let r = get_f64(data, "R").unwrap_or(0.0);
    let csr = classify_csr_percentile(c, s, r);

    let growth_form = get_str(data, "try_growth_form");
    let height_m = get_f64(data, "height_m");
    let form = classify_growth_form(growth_form, height_m);
    let eive_l = get_eive(data, "L");

    lines.push(format!("**CSR Profile**: C: {:.0}% | S: {:.0}% | R: {:.0}%", c, s, r));
    lines.push(format!("**Classification**: {} (percentile-based)", csr.label()));
    lines.push(format!("**Growth Form**: {}", form.label()));
    if let Some(h) = height_m {
        lines.push(format!("**Height**: {:.1}m", h));
    }
    if let Some(l) = eive_l {
        lines.push(format!("**Light Preference**: EIVE-L {:.1}", l));
    }

    lines.push(String::new());
    lines.push("**Companion Strategy**:".to_string());

    // CSR-specific advice from decision tree
    lines.push(csr_form_advice(csr, form, eive_l));

    // Compatibility matrix note
    lines.push(String::new());
    lines.push(csr_compatibility_note(csr));

    lines.join("\n")
}

fn csr_form_advice(csr: CsrStrategy, form: GrowthFormCategory, eive_l: Option<f64>) -> String {
    match (csr, form) {
        (CsrStrategy::CDominant, GrowthFormCategory::Tree) => {
            "- Canopy competitor. Pairs well with shade-tolerant understory (EIVE-L < 5).\n- Avoid other large C-dominant trees nearby; root and light competition.\n- Vines can use as support without conflict.".to_string()
        }
        (CsrStrategy::CDominant, GrowthFormCategory::Shrub) => {
            "- Vigorous mid-layer. Give wide spacing from other C-dominant shrubs.\n- Good with S-dominant ground covers; provides protection.".to_string()
        }
        (CsrStrategy::CDominant, GrowthFormCategory::Herb) => {
            "- Spreading competitor. May outcompete neighbouring herbs.\n- Best with well-spaced, resilient companions or as solo planting.".to_string()
        }
        (CsrStrategy::CDominant, GrowthFormCategory::Vine) => {
            "- Aggressive climber. Needs robust host tree or structure.\n- May smother less vigorous plants; keep away from delicate shrubs.".to_string()
        }
        (CsrStrategy::SDominant, _) => {
            let light_note = match eive_l {
                Some(l) if l < 3.2 => "- Shade-tolerant. Thrives under C-dominant canopy trees.\n- Ideal understory plant for layered guilds.",
                Some(l) if l > 7.47 => "- Sun-demanding despite S-strategy. Needs open position.\n- Avoid planting under tall C-dominant plants.",
                _ => "- Flexible S-plant. Tolerates range of companions.",
            };
            format!("{}\n- Low competition profile. Pairs well with most strategies.\n- Long-lived and persistent; good structural backbone for guilds.", light_note)
        }
        (CsrStrategy::RDominant, GrowthFormCategory::Herb) => {
            "- Annual/biennial. Good for dynamic, changing plantings.\n- Pair with longer-lived S or balanced plants for continuity.\n- Will not persist; plan for succession or self-seeding.".to_string()
        }
        (CsrStrategy::RDominant, GrowthFormCategory::Vine) => {
            "- May die back; regrows rapidly from base or seed.\n- Pair with longer-lived plants for continuity.".to_string()
        }
        (CsrStrategy::RDominant, _) => {
            "- Short-lived opportunist. Use for seasonal colour or gap-filling.\n- Pair with longer-lived S or balanced plants for continuity.\n- Will not persist; plan for succession.".to_string()
        }
        (CsrStrategy::Balanced, _) => {
            "- Generalist strategy. Compatible with most companion types.\n- Moderate vigour; neither dominates nor is dominated.\n- Flexible in guild positioning.".to_string()
        }
    }
}

fn csr_compatibility_note(csr: CsrStrategy) -> String {
    match csr {
        CsrStrategy::CDominant => {
            "**Avoid Pairing With**: Other C-dominant plants at same layer (competition). Sun-loving plants in shade zone.".to_string()
        }
        CsrStrategy::SDominant => {
            "**Good Companions**: Most strategies work well. C-dominant canopy trees if shade-tolerant.".to_string()
        }
        CsrStrategy::RDominant => {
            "**Good Companions**: S-dominant or balanced plants for continuity. Other R-plants for dynamic seasonal display.".to_string()
        }
        CsrStrategy::Balanced => {
            "**Good Companions**: Compatible with all CSR types. Flexible positioning.".to_string()
        }
    }
}

// ============================================================================
// GP3: Pest Control Contribution
// ============================================================================

fn generate_gp3(
    _data: &HashMap<String, Value>,
    organism_counts: Option<&OrganismCounts>,
    fungal_counts: Option<&FungalCounts>,
) -> String {
    let mut lines = Vec::new();
    lines.push("### Pest Control".to_string());
    lines.push(String::new());

    let herbivores = organism_counts.map(|c| c.herbivores).unwrap_or(0);
    let predators = organism_counts.map(|c| c.predators).unwrap_or(0);
    let entomopath = fungal_counts.map(|c| c.entomopathogens).unwrap_or(0);

    let (pest_level, pest_advice) = classify_pest_level(herbivores);
    let (pred_level, pred_advice) = classify_predator_level(predators);

    lines.push(format!("**Observed Pests**: {} species ({}) - {}", herbivores, pest_level, pest_advice));
    lines.push(String::new());
    lines.push("**Observed Beneficial Predators**:".to_string());
    lines.push(format!("- {} predatory species observed ({}) - {}", predators, pred_level, pred_advice));
    if entomopath > 0 {
        lines.push(format!("- {} insect-killing fungi observed", entomopath));
    }

    lines.push(String::new());
    lines.push("**Guild Recommendations**:".to_string());

    // Decision tree
    if herbivores >= 15 {
        lines.push("- High pest diversity (top 10%). Benefits from companions that attract pest predators.".to_string());
    } else if herbivores >= 6 {
        lines.push("- Above-average pest observations. Diverse plantings help maintain natural balance.".to_string());
    } else {
        lines.push("- Typical pest observations. Standard companion planting applies.".to_string());
    }

    if predators >= 29 {
        lines.push("- Excellent predator habitat (top 10%). This plant attracts many beneficial insects that protect neighbours.".to_string());
    } else if predators >= 9 {
        lines.push("- Good predator habitat. Contributes beneficial insects to the garden.".to_string());
    }

    if entomopath > 0 {
        lines.push(format!("- Hosts {} insect-killing fungi that may help control pests on neighbouring plants.", entomopath));
    }

    lines.join("\n")
}

// ============================================================================
// GP4: Disease Control Contribution
// ============================================================================

fn generate_gp4(fungal_counts: Option<&FungalCounts>) -> String {
    let mut lines = Vec::new();
    lines.push("### Disease Control".to_string());
    lines.push(String::new());

    let mycoparasites = fungal_counts.map(|c| c.mycoparasites).unwrap_or(0);

    // Note: pathogenic_fungi_count should come from extended data
    // For now we note that data may not be in the FungalCounts struct
    lines.push("**Observed Disease Fighters**:".to_string());
    lines.push(format!("- {} beneficial fungi that attack plant diseases", mycoparasites));

    lines.push(String::new());
    lines.push("**Guild Recommendations**:".to_string());

    if mycoparasites > 0 {
        lines.push("- Hosts beneficial fungi that attack plant diseases - may help protect neighbouring plants.".to_string());
    } else {
        lines.push("- No documented mycoparasitic fungi. Focus on spacing and airflow for disease prevention.".to_string());
    }

    lines.join("\n")
}

// ============================================================================
// GP5: Mycorrhizal Network
// ============================================================================

fn generate_gp5(fungal_counts: Option<&FungalCounts>) -> String {
    let mut lines = Vec::new();
    lines.push("### Mycorrhizal Network".to_string());
    lines.push(String::new());

    let (amf, emf) = fungal_counts.map(|c| (c.amf, c.emf)).unwrap_or((0, 0));
    let myco = classify_mycorrhizal(amf, emf);

    lines.push(format!("**Observed Association**: {}", myco.label()));
    if amf > 0 {
        lines.push(format!("- {} AMF species documented", amf));
    }
    if emf > 0 {
        lines.push(format!("- {} EMF species documented", emf));
    }

    lines.push(String::new());
    lines.push("**Guild Recommendations**:".to_string());

    match myco {
        MycorrhizalType::AMF => {
            lines.push("- **Network-compatible plants**: Other plants with AMF associations".to_string());
            lines.push("- **Network bonus**: Can share phosphorus and carbon with AMF-compatible neighbours".to_string());
            lines.push("- **Soil tip**: Minimize tillage to preserve fungal hyphal connections".to_string());
        }
        MycorrhizalType::EMF => {
            lines.push("- **Network-compatible plants**: Other plants with EMF associations".to_string());
            lines.push("- **Network bonus**: Can share nutrients and defense signals with EMF-compatible neighbours".to_string());
            lines.push("- Creates forest-type nutrient-sharing network".to_string());
        }
        MycorrhizalType::Dual => {
            lines.push("- **Network-compatible plants**: Can connect to both AMF and EMF network types".to_string());
            lines.push("- Versatile guild member - bridges different plant communities".to_string());
        }
        MycorrhizalType::NonMycorrhizal => {
            lines.push("- Non-mycorrhizal or undocumented. May not participate in underground fungal networks.".to_string());
            lines.push("- No network conflict, but no documented network benefit from CMN.".to_string());
        }
    }

    lines.join("\n")
}

// ============================================================================
// GP6: Structural Role
// ============================================================================

fn generate_gp6(data: &HashMap<String, Value>) -> String {
    let mut lines = Vec::new();
    lines.push("### Structural Role".to_string());
    lines.push(String::new());

    let height_m = get_f64(data, "height_m");
    let growth_form = get_str(data, "try_growth_form");
    let eive_l = get_eive(data, "L");

    let layer = classify_structural_layer(height_m);
    let form = classify_growth_form(growth_form, height_m);

    lines.push(format!("**Layer**: {} ({:.1}m)", layer.label(), height_m.unwrap_or(0.0)));
    lines.push(format!("**Growth Form**: {}", form.label()));
    if let Some(l) = eive_l {
        lines.push(format!("**Light Preference**: EIVE-L {:.1}", l));
    }

    lines.push(String::new());
    lines.push("**Guild Recommendations**:".to_string());

    // Decision tree based on layer
    match layer {
        StructuralLayer::Canopy => {
            lines.push("- **Below this plant**: Shade-tolerant understory plants (EIVE-L < 5)".to_string());
            lines.push("- **Avoid pairing with**: Sun-loving plants in the shade zone".to_string());
            lines.push("- Creates significant shade; wind protection for neighbours".to_string());
        }
        StructuralLayer::SubCanopy => {
            lines.push("- **Below this plant**: Ground covers, shade-tolerant shrubs".to_string());
            lines.push("- Provides partial shade, benefits from canopy protection".to_string());
        }
        StructuralLayer::TallShrub => {
            lines.push("- **Below this plant**: Low herbs, ground covers".to_string());
            lines.push("- **Above this plant**: Tolerates taller trees above".to_string());
            lines.push("- Mid-structure role in layered plantings".to_string());
        }
        StructuralLayer::Understory => {
            let light_advice = match eive_l {
                Some(l) if l < 3.2 => "Shade-adapted. Thrives under trees/tall shrubs.",
                Some(l) if l > 7.47 => "Sun-loving. Needs open position, not under canopy.",
                _ => "Flexible. Tolerates range of light conditions.",
            };
            lines.push(format!("- {}", light_advice));
        }
        StructuralLayer::GroundCover => {
            lines.push("- **Role**: Soil protection, weed suppression".to_string());
            lines.push("- **Pair with**: Any taller plants (provides living mulch)".to_string());
        }
    }

    // Vine-specific
    if form == GrowthFormCategory::Vine {
        lines.push("- **Climber**: Needs vertical structure from trees or tall shrubs".to_string());
    }

    lines.join("\n")
}

// ============================================================================
// GP7: Pollinator Contribution
// ============================================================================

fn generate_gp7(organism_counts: Option<&OrganismCounts>) -> String {
    let mut lines = Vec::new();
    lines.push("### Pollinator Support".to_string());
    lines.push(String::new());

    let pollinators = organism_counts.map(|c| c.pollinators).unwrap_or(0);
    let (level, interpretation) = classify_pollinator_level(pollinators);

    lines.push(format!("**Observed Pollinators**: {} species ({})", pollinators, level));
    lines.push(interpretation.to_string());

    lines.push(String::new());
    lines.push("**Guild Recommendations**:".to_string());

    // Decision tree
    if pollinators >= 45 {
        lines.push("- Pollinator hotspot (top 10%). Central to garden pollination success.".to_string());
        lines.push("- Benefits ALL flowering neighbours through strong attraction effect.".to_string());
    } else if pollinators >= 20 {
        lines.push("- Strong pollinator magnet. Valuable addition to any garden.".to_string());
    } else if pollinators >= 6 {
        lines.push("- Typical pollinator observations. Good companion for other flowering plants.".to_string());
    } else if pollinators >= 2 {
        lines.push("- Few pollinators observed. May have specialist visitors not yet documented.".to_string());
        lines.push("- Consider pairing with pollinator-rich plants for better cross-pollination.".to_string());
    } else {
        lines.push("- Little or no pollinator data in GloBI. Likely a data gap - most flowering plants attract pollinators.".to_string());
    }

    lines.push(String::new());
    lines.push("**This Plant Provides**:".to_string());
    lines.push(format!("- Nectar/pollen source for {} pollinator species", pollinators));
    if pollinators >= 6 {
        lines.push("- Attraction effect may increase visits to neighbouring plants".to_string());
    }

    lines.join("\n")
}

// ============================================================================
// Cautions Section
// ============================================================================

fn generate_cautions(
    data: &HashMap<String, Value>,
    _organism_counts: Option<&OrganismCounts>,
    _fungal_counts: Option<&FungalCounts>,
) -> String {
    let mut lines = Vec::new();

    let family = get_str(data, "family").unwrap_or("Unknown");
    let c = get_f64(data, "C").unwrap_or(0.0);
    let s = get_f64(data, "S").unwrap_or(0.0);
    let r = get_f64(data, "R").unwrap_or(0.0);
    let csr = classify_csr_percentile(c, s, r);
    let eive_l = get_eive(data, "L");

    let mut cautions = Vec::new();
    cautions.push(format!("- Avoid clustering multiple {} plants (shared pests and diseases)", family));

    if csr == CsrStrategy::CDominant {
        cautions.push("- C-dominant strategy: may outcompete slower-growing neighbours".to_string());
    }

    if csr == CsrStrategy::RDominant {
        cautions.push("- R-dominant strategy: short-lived, plan for succession or self-seeding".to_string());
    }

    if let Some(l) = eive_l {
        if l > 7.47 {
            cautions.push("- Sun-loving: will struggle or fail under canopy shade".to_string());
        } else if l < 3.2 {
            cautions.push("- Shade-adapted: may struggle in full sun without canopy protection".to_string());
        }
    }

    if !cautions.is_empty() {
        lines.push("### Cautions".to_string());
        lines.push(String::new());
        for c in cautions {
            lines.push(c);
        }
    }

    lines.join("\n")
}
