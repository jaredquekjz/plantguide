use crate::explanation::types::Explanation;
use crate::explanation::pest_analysis::PestProfile;
use crate::explanation::fungi_network_analysis::FungiNetworkProfile;
use crate::explanation::pollinator_network_analysis::PollinatorNetworkProfile;
use crate::explanation::biocontrol_network_analysis::BiocontrolNetworkProfile;
use crate::explanation::pathogen_control_network_analysis::PathogenControlNetworkProfile;

/// Markdown formatter for explanations
pub struct MarkdownFormatter;

impl MarkdownFormatter {
    /// Format explanation as markdown
    pub fn format(explanation: &Explanation) -> String {
        let mut md = String::with_capacity(2048);

        // Title with stars and score
        md.push_str(&format!(
            "# {} - {}\n\n",
            explanation.overall.stars, explanation.overall.label
        ));
        md.push_str(&format!(
            "**Overall Score:** {:.1}/100\n\n",
            explanation.overall.score
        ));
        md.push_str(&format!("{}\n\n", explanation.overall.message));

        // Climate
        md.push_str("## Climate Compatibility\n\n");
        md.push_str(&format!("✅ {}\n\n", explanation.climate.message));

        // Benefits (with interleaved profiles)
        if !explanation.benefits.is_empty() {
            md.push_str("## Benefits\n\n");
            for benefit in &explanation.benefits {
                md.push_str(&format!(
                    "### {} [{}]\n\n",
                    benefit.title, benefit.metric_code
                ));
                md.push_str(&format!("{}  \n", benefit.message));
                md.push_str(&format!("{}  \n\n", benefit.detail));
                if let Some(evidence) = &benefit.evidence {
                    md.push_str(&format!("*Evidence:* {}\n\n", evidence));
                }

                // Insert pest profile after M1 (Phylogenetic Diversity)
                if benefit.metric_code == "M1" {
                    if let Some(pest_profile) = &explanation.pest_profile {
                        Self::format_pest_profile(&mut md, pest_profile);
                    }
                }

                // Insert biocontrol profile after M3 (Insect Pest Control)
                if benefit.metric_code == "M3" {
                    if let Some(biocontrol_profile) = &explanation.biocontrol_network_profile {
                        Self::format_biocontrol_profile(&mut md, biocontrol_profile);
                    }
                }

                // Insert pathogen control profile after M4 (Disease Suppression)
                if benefit.metric_code == "M4" {
                    if let Some(pathogen_profile) = &explanation.pathogen_control_profile {
                        Self::format_pathogen_control_profile(&mut md, pathogen_profile);
                    }
                }

                // Insert fungi profile after M5 (Mycorrhizal Network)
                if benefit.metric_code == "M5" {
                    if let Some(fungi_profile) = &explanation.fungi_network_profile {
                        Self::format_fungi_profile(&mut md, fungi_profile);
                    }
                }

                // Insert pollinator profile after M7 (Pollinator Support)
                if benefit.metric_code == "M7" {
                    if let Some(pollinator_profile) = &explanation.pollinator_network_profile {
                        Self::format_pollinator_profile(&mut md, pollinator_profile);
                    }
                }
            }
        }

        // Warnings
        if !explanation.warnings.is_empty() {
            md.push_str("## Warnings\n\n");
            for warning in &explanation.warnings {
                md.push_str(&format!("{} **{}**\n\n", warning.icon, warning.message));
                md.push_str(&format!("{}  \n", warning.detail));
                md.push_str(&format!("*Advice:* {}\n\n", warning.advice));
            }
        }

        // Risks
        if !explanation.risks.is_empty() {
            md.push_str("## Risks\n\n");
            for risk in &explanation.risks {
                md.push_str(&format!("{} **{}**\n\n", risk.icon, risk.title));
                md.push_str(&format!("{}  \n", risk.message));
                md.push_str(&format!("{}  \n", risk.detail));
                md.push_str(&format!("*Advice:* {}\n\n", risk.advice));
            }
        }

        // Metrics Breakdown
        md.push_str("## Metrics Breakdown\n\n");

        md.push_str("### Universal Indicators\n\n");
        md.push_str("| Metric | Score | Interpretation |\n");
        md.push_str("|--------|-------|----------------|\n");
        for metric in &explanation.metrics_display.universal {
            md.push_str(&format!(
                "| {} - {} | {:.1} | {} |\n",
                metric.code, metric.name, metric.score, metric.interpretation
            ));
        }

        md.push_str("\n### Bonus Indicators\n\n");
        md.push_str("| Metric | Score | Interpretation |\n");
        md.push_str("|--------|-------|----------------|\n");
        for metric in &explanation.metrics_display.bonus {
            md.push_str(&format!(
                "| {} - {} | {:.1} | {} |\n",
                metric.code, metric.name, metric.score, metric.interpretation
            ));
        }

        md.push('\n');
        md
    }

    /// Format pest vulnerability profile section
    fn format_pest_profile(md: &mut String, pest_profile: &PestProfile) {
        md.push_str("#### Pest Vulnerability Profile\n\n");
        md.push_str("*Qualitative information about herbivore pests (not used in scoring)*\n\n");

        md.push_str(&format!(
            "**Total unique herbivore species:** {}\n\n",
            pest_profile.total_unique_pests
        ));

        // Shared pests (generalists)
        if !pest_profile.shared_pests.is_empty() {
            md.push_str("**Shared Pests (Generalists)**\n\n");
            md.push_str("These pests attack multiple plants in the guild:\n\n");
            for (i, pest) in pest_profile.shared_pests.iter().enumerate().take(10) {
                md.push_str(&format!(
                    "{}. **{}**: attacks {} plant(s) ({})\n",
                    i + 1,
                    pest.pest_name,
                    pest.plant_count,
                    pest.plants.join(", ")
                ));
            }
            md.push_str("\n");
        } else {
            md.push_str("**No shared pests detected** - Each herbivore attacks only one plant species in this guild, indicating high diversity.\n\n");
        }

        // Top pests by interaction count
        if !pest_profile.top_pests.is_empty() {
            md.push_str("**Top 10 Herbivore Pests**\n\n");
            md.push_str("| Rank | Pest Species | Plants Attacked |\n");
            md.push_str("|------|--------------|------------------|\n");
            for (i, pest) in pest_profile.top_pests.iter().enumerate().take(10) {
                let plant_list = if pest.plants.len() > 3 {
                    format!("{} plants", pest.plants.len())
                } else {
                    pest.plants.join(", ")
                };
                md.push_str(&format!(
                    "| {} | {} | {} |\n",
                    i + 1,
                    pest.pest_name,
                    plant_list
                ));
            }
            md.push_str("\n");
        }

        // Most vulnerable plants
        if !pest_profile.vulnerable_plants.is_empty() {
            md.push_str("**Most Vulnerable Plants**\n\n");
            md.push_str("| Plant | Herbivore Count |\n");
            md.push_str("|-------|------------------|\n");
            for plant in pest_profile.vulnerable_plants.iter().take(5) {
                md.push_str(&format!(
                    "| {} | {} |\n",
                    plant.plant_name,
                    plant.pest_count
                ));
            }
            md.push_str("\n");
        }
    }

    /// Format fungi network profile section
    fn format_fungi_profile(md: &mut String, fungi_profile: &FungiNetworkProfile) {
        md.push_str("#### Beneficial Fungi Network Profile\n\n");
        md.push_str("*Qualitative information about fungal networks (60% of M5 scoring)*\n\n");

        md.push_str(&format!(
            "**Total unique beneficial fungi species:** {}\n\n",
            fungi_profile.total_unique_fungi
        ));

        // Fungal diversity by category
        md.push_str("**Fungal Community Composition:**\n\n");
        let total = fungi_profile.total_unique_fungi as f64;
        if total > 0.0 {
            let amf_pct = fungi_profile.fungi_by_category.amf_count as f64 / total * 100.0;
            let emf_pct = fungi_profile.fungi_by_category.emf_count as f64 / total * 100.0;
            let endo_pct = fungi_profile.fungi_by_category.endophytic_count as f64 / total * 100.0;
            let sapro_pct = fungi_profile.fungi_by_category.saprotrophic_count as f64 / total * 100.0;

            md.push_str(&format!("- {} AMF species (Arbuscular Mycorrhizal) - {:.1}%\n",
                fungi_profile.fungi_by_category.amf_count, amf_pct));
            md.push_str(&format!("- {} EMF species (Ectomycorrhizal) - {:.1}%\n",
                fungi_profile.fungi_by_category.emf_count, emf_pct));
            md.push_str(&format!("- {} Endophytic species - {:.1}%\n",
                fungi_profile.fungi_by_category.endophytic_count, endo_pct));
            md.push_str(&format!("- {} Saprotrophic species - {:.1}%\n\n",
                fungi_profile.fungi_by_category.saprotrophic_count, sapro_pct));
        }

        // Top network fungi
        if !fungi_profile.top_fungi.is_empty() {
            md.push_str("**Top Network Fungi (by connectivity):**\n\n");
            md.push_str("| Rank | Fungus Species | Category | Plants Connected | Network Contribution |\n");
            md.push_str("|------|----------------|----------|------------------|----------------------|\n");
            for (i, fungus) in fungi_profile.top_fungi.iter().enumerate() {
                let plant_list = if fungus.plants.len() > 3 {
                    format!("{} plants", fungus.plants.len())
                } else {
                    fungus.plants.join(", ")
                };
                md.push_str(&format!(
                    "| {} | {} | {} | {} | {:.1}% |\n",
                    i + 1,
                    fungus.fungus_name,
                    fungus.category,
                    plant_list,
                    fungus.network_contribution * 100.0
                ));
            }
            md.push_str("\n");
        }

        // Network hubs
        if !fungi_profile.hub_plants.is_empty() {
            md.push_str("**Network Hubs (most connected plants):**\n\n");
            md.push_str("| Plant | Total Fungi | AMF | EMF | Endophytic | Saprotrophic |\n");
            md.push_str("|-------|-------------|-----|-----|------------|---------------|\n");
            for hub in fungi_profile.hub_plants.iter().take(10) {
                md.push_str(&format!(
                    "| {} | {} | {} | {} | {} | {} |\n",
                    hub.plant_name,
                    hub.fungus_count,
                    hub.amf_count,
                    hub.emf_count,
                    hub.endophytic_count,
                    hub.saprotrophic_count
                ));
            }
            md.push_str("\n");
        }
    }

    /// Format pollinator network profile section
    fn format_pollinator_profile(md: &mut String, pollinator_profile: &PollinatorNetworkProfile) {
        md.push_str("#### Pollinator Network Profile\n\n");
        md.push_str("*Qualitative information about pollinator networks (100% of M7 scoring)*\n\n");

        md.push_str(&format!(
            "**Total unique pollinator species:** {}\n\n",
            pollinator_profile.total_unique_pollinators
        ));

        // Pollinator diversity by category
        md.push_str("**Pollinator Community Composition:**\n\n");
        let total = pollinator_profile.total_unique_pollinators as f64;
        if total > 0.0 {
            let honey_bees_pct = pollinator_profile.pollinators_by_category.honey_bees_count as f64 / total * 100.0;
            let bumblebees_pct = pollinator_profile.pollinators_by_category.bumblebees_count as f64 / total * 100.0;
            let solitary_bees_pct = pollinator_profile.pollinators_by_category.solitary_bees_count as f64 / total * 100.0;
            let hover_flies_pct = pollinator_profile.pollinators_by_category.hover_flies_count as f64 / total * 100.0;
            let muscid_flies_pct = pollinator_profile.pollinators_by_category.muscid_flies_count as f64 / total * 100.0;
            let mosquitoes_pct = pollinator_profile.pollinators_by_category.mosquitoes_count as f64 / total * 100.0;
            let other_flies_pct = pollinator_profile.pollinators_by_category.other_flies_count as f64 / total * 100.0;
            let butterflies_pct = pollinator_profile.pollinators_by_category.butterflies_count as f64 / total * 100.0;
            let moths_pct = pollinator_profile.pollinators_by_category.moths_count as f64 / total * 100.0;
            let pollen_beetles_pct = pollinator_profile.pollinators_by_category.pollen_beetles_count as f64 / total * 100.0;
            let other_beetles_pct = pollinator_profile.pollinators_by_category.other_beetles_count as f64 / total * 100.0;
            let wasps_pct = pollinator_profile.pollinators_by_category.wasps_count as f64 / total * 100.0;
            let birds_pct = pollinator_profile.pollinators_by_category.birds_count as f64 / total * 100.0;
            let bats_pct = pollinator_profile.pollinators_by_category.bats_count as f64 / total * 100.0;
            let other_pct = pollinator_profile.pollinators_by_category.other_count as f64 / total * 100.0;

            if pollinator_profile.pollinators_by_category.honey_bees_count > 0 {
                md.push_str(&format!("- {} Honey Bees - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.honey_bees_count, honey_bees_pct));
            }
            if pollinator_profile.pollinators_by_category.bumblebees_count > 0 {
                md.push_str(&format!("- {} Bumblebees - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.bumblebees_count, bumblebees_pct));
            }
            if pollinator_profile.pollinators_by_category.solitary_bees_count > 0 {
                md.push_str(&format!("- {} Solitary Bees - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.solitary_bees_count, solitary_bees_pct));
            }
            if pollinator_profile.pollinators_by_category.hover_flies_count > 0 {
                md.push_str(&format!("- {} Hover Flies - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.hover_flies_count, hover_flies_pct));
            }
            if pollinator_profile.pollinators_by_category.muscid_flies_count > 0 {
                md.push_str(&format!("- {} Muscid Flies - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.muscid_flies_count, muscid_flies_pct));
            }
            if pollinator_profile.pollinators_by_category.mosquitoes_count > 0 {
                md.push_str(&format!("- {} Mosquitoes - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.mosquitoes_count, mosquitoes_pct));
            }
            if pollinator_profile.pollinators_by_category.other_flies_count > 0 {
                md.push_str(&format!("- {} Other Flies - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.other_flies_count, other_flies_pct));
            }
            if pollinator_profile.pollinators_by_category.butterflies_count > 0 {
                md.push_str(&format!("- {} Butterflies - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.butterflies_count, butterflies_pct));
            }
            if pollinator_profile.pollinators_by_category.moths_count > 0 {
                md.push_str(&format!("- {} Moths - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.moths_count, moths_pct));
            }
            if pollinator_profile.pollinators_by_category.pollen_beetles_count > 0 {
                md.push_str(&format!("- {} Pollen Beetles - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.pollen_beetles_count, pollen_beetles_pct));
            }
            if pollinator_profile.pollinators_by_category.other_beetles_count > 0 {
                md.push_str(&format!("- {} Other Beetles - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.other_beetles_count, other_beetles_pct));
            }
            if pollinator_profile.pollinators_by_category.wasps_count > 0 {
                md.push_str(&format!("- {} Wasps - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.wasps_count, wasps_pct));
            }
            if pollinator_profile.pollinators_by_category.birds_count > 0 {
                md.push_str(&format!("- {} Birds - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.birds_count, birds_pct));
            }
            if pollinator_profile.pollinators_by_category.bats_count > 0 {
                md.push_str(&format!("- {} Bats - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.bats_count, bats_pct));
            }
            if pollinator_profile.pollinators_by_category.other_count > 0 {
                md.push_str(&format!("- {} Other - {:.1}%\n",
                    pollinator_profile.pollinators_by_category.other_count, other_pct));
            }
            md.push_str("\n");
        }

        // Shared pollinators
        if !pollinator_profile.shared_pollinators.is_empty() {
            md.push_str("**Shared Pollinators (visiting ≥2 plants):**\n\n");
            md.push_str(&format!("{} pollinator species are shared across multiple plants in this guild.\n\n",
                pollinator_profile.shared_pollinators.len()));
        } else {
            md.push_str("**No shared pollinators detected** - Each pollinator visits only one plant species in this guild.\n\n");
        }

        // Top network pollinators
        if !pollinator_profile.top_pollinators.is_empty() {
            md.push_str("**Top Network Pollinators (by connectivity):**\n\n");
            md.push_str("| Rank | Pollinator Species | Category | Plants Connected | Network Contribution |\n");
            md.push_str("|------|-------------------|----------|------------------|----------------------|\n");
            for (i, pollinator) in pollinator_profile.top_pollinators.iter().enumerate() {
                md.push_str(&format!(
                    "| {} | {} | {} | {} plants | {:.1}% |\n",
                    i + 1,
                    pollinator.pollinator_name,
                    pollinator.category.display_name(),
                    pollinator.plant_count,
                    pollinator.network_contribution * 100.0
                ));
            }
            md.push_str("\n");
        }

        // Network hubs
        if !pollinator_profile.hub_plants.is_empty() {
            md.push_str("**Network Hubs (most connected plants):**\n\n");
            md.push_str("| Plant | Total | Honey Bees | Bumblebees | Solitary Bees | Hover Flies | Muscid Flies | Mosquitoes | Other Flies | Butterflies | Moths | Pollen Beetles | Other Beetles | Wasps | Birds | Bats | Other |\n");
            md.push_str("|-------|-------|------------|------------|---------------|-------------|--------------|------------|-------------|-------------|-------|----------------|---------------|-------|-------|------|-------|\n");
            for hub in pollinator_profile.hub_plants.iter().take(10) {
                md.push_str(&format!(
                    "| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |\n",
                    hub.plant_name,
                    hub.pollinator_count,
                    hub.honey_bees_count,
                    hub.bumblebees_count,
                    hub.solitary_bees_count,
                    hub.hover_flies_count,
                    hub.muscid_flies_count,
                    hub.mosquitoes_count,
                    hub.other_flies_count,
                    hub.butterflies_count,
                    hub.moths_count,
                    hub.pollen_beetles_count,
                    hub.other_beetles_count,
                    hub.wasps_count,
                    hub.birds_count,
                    hub.bats_count,
                    hub.other_count
                ));
            }
            md.push_str("\n");
        }
    }

    /// Format biocontrol network profile section
    fn format_biocontrol_profile(md: &mut String, biocontrol_profile: &BiocontrolNetworkProfile) {
        md.push_str("#### Verified Biocontrol Relationships\n\n");

        // Show matched predator pairs
        if !biocontrol_profile.matched_predator_pairs.is_empty() {
            md.push_str(&format!(
                "**{} Herbivore → Predator matches found:**\n\n",
                biocontrol_profile.matched_predator_pairs.len()
            ));
            md.push_str("| Herbivore (Pest) | Herbivore Category | Known Predator | Predator Category | Match Type |\n");
            md.push_str("|------------------|-------------------|----------------|-------------------|------------|\n");
            for pair in biocontrol_profile.matched_predator_pairs.iter().take(20) {
                md.push_str(&format!(
                    "| {} | {} | {} | {} | Specific (weight 1.0) |\n",
                    pair.herbivore,
                    pair.herbivore_category.display_name(),
                    pair.predator,
                    pair.predator_category.display_name()
                ));
            }
            if biocontrol_profile.matched_predator_pairs.len() > 20 {
                md.push_str(&format!(
                    "\n*Showing 20 of {} total matches*\n",
                    biocontrol_profile.matched_predator_pairs.len()
                ));
            }
            md.push_str("\n");
        }

        // Show matched fungi pairs
        if !biocontrol_profile.matched_fungi_pairs.is_empty() {
            md.push_str("**Matched Herbivore → Entomopathogenic Fungus Pairs:**\n\n");
            md.push_str("| Herbivore (Pest) | Entomopathogenic Fungus | Match Type |\n");
            md.push_str("|------------------|------------------------|------------|\n");
            for (herbivore, fungus) in biocontrol_profile.matched_fungi_pairs.iter().take(20) {
                md.push_str(&format!(
                    "| {} | {} | Specific (weight 1.0) |\n",
                    herbivore, fungus
                ));
            }
            if biocontrol_profile.matched_fungi_pairs.len() > 20 {
                md.push_str(&format!(
                    "\n*Showing 20 of {} total matches*\n",
                    biocontrol_profile.matched_fungi_pairs.len()
                ));
            }
            md.push_str("\n");
        }

        // Top predators
        if !biocontrol_profile.top_predators.is_empty() {
            md.push_str("**Top Animal Predators (by connectivity):**\n\n");
            md.push_str("| Rank | Predator Species | Plants Visited | Network Contribution |\n");
            md.push_str("|------|------------------|----------------|----------------------|\n");
            for (i, agent) in biocontrol_profile.top_predators.iter().enumerate() {
                md.push_str(&format!(
                    "| {} | {} | {} plants | {:.1}% |\n",
                    i + 1,
                    agent.agent_name,
                    agent.plant_count,
                    agent.network_contribution * 100.0
                ));
            }
            md.push_str("\n");
        }

        // Top entomopathogenic fungi
        if !biocontrol_profile.top_entomo_fungi.is_empty() {
            md.push_str("**Top Entomopathogenic Fungi (by connectivity):**\n\n");
            md.push_str("| Rank | Fungus Species | Plants Hosting | Network Contribution |\n");
            md.push_str("|------|----------------|----------------|----------------------|\n");
            for (i, agent) in biocontrol_profile.top_entomo_fungi.iter().enumerate() {
                md.push_str(&format!(
                    "| {} | {} | {} plants | {:.1}% |\n",
                    i + 1,
                    agent.agent_name,
                    agent.plant_count,
                    agent.network_contribution * 100.0
                ));
            }
            md.push_str("\n");
        }

        // Network hubs
        if !biocontrol_profile.hub_plants.is_empty() {
            md.push_str("**Network Hubs (plants attracting most biocontrol):**\n\n");
            md.push_str("| Plant | Total Predators | Total Fungi | Combined |\n");
            md.push_str("|-------|----------------|-------------|----------|\n");
            for hub in biocontrol_profile.hub_plants.iter().take(10) {
                md.push_str(&format!(
                    "| {} | {} | {} | {} |\n",
                    hub.plant_name,
                    hub.total_predators,
                    hub.total_entomo_fungi,
                    hub.total_biocontrol_agents
                ));
            }
            md.push_str("\n");
        }
    }

    /// Format pathogen control network profile section
    fn format_pathogen_control_profile(md: &mut String, pathogen_profile: &PathogenControlNetworkProfile) {
        md.push_str("#### Pathogen Control Network Profile\n\n");
        md.push_str("*Qualitative information about disease suppression (influences M4 scoring)*\n\n");

        md.push_str("**Summary:**\n");
        md.push_str(&format!("- {} unique mycoparasite species (fungi that parasitize other fungi)\n", pathogen_profile.total_unique_mycoparasites));
        md.push_str(&format!("- {} unique pathogen species in guild\n\n", pathogen_profile.total_unique_pathogens));

        md.push_str("**Mechanism Summary:**\n");
        md.push_str(&format!("- {} Specific antagonist matches (pathogen → known mycoparasite, weight 1.0, rarely fires)\n", pathogen_profile.specific_antagonist_matches));
        md.push_str(&format!("- {} General mycoparasite fungi (primary mechanism, weight 1.0)\n\n", pathogen_profile.general_mycoparasite_count));

        // Show matched antagonist pairs
        if !pathogen_profile.matched_antagonist_pairs.is_empty() {
            md.push_str("**Matched Pathogen → Mycoparasite Pairs:**\n\n");
            md.push_str("| Pathogen | Known Antagonist (Mycoparasite) | Match Type |\n");
            md.push_str("|----------|----------------------------------|------------|\n");
            for (pathogen, antagonist) in pathogen_profile.matched_antagonist_pairs.iter().take(20) {
                md.push_str(&format!(
                    "| {} | {} | Specific (weight 1.0) |\n",
                    pathogen, antagonist
                ));
            }
            if pathogen_profile.matched_antagonist_pairs.len() > 20 {
                md.push_str(&format!(
                    "\n*Showing 20 of {} total matches*\n",
                    pathogen_profile.matched_antagonist_pairs.len()
                ));
            }
            md.push_str("\n");
        }

        // Top mycoparasites
        if !pathogen_profile.top_mycoparasites.is_empty() {
            md.push_str("**Top Mycoparasites (by connectivity):**\n\n");
            md.push_str("| Rank | Mycoparasite Species | Plants Hosting | Network Contribution |\n");
            md.push_str("|------|---------------------|----------------|----------------------|\n");
            for (i, agent) in pathogen_profile.top_mycoparasites.iter().enumerate() {
                md.push_str(&format!(
                    "| {} | {} | {} plants | {:.1}% |\n",
                    i + 1,
                    agent.mycoparasite_name,
                    agent.plant_count,
                    agent.network_contribution * 100.0
                ));
            }
            md.push_str("\n");
        }

        // Network hubs
        if !pathogen_profile.hub_plants.is_empty() {
            md.push_str("**Network Hubs (plants harboring most mycoparasites):**\n\n");
            md.push_str("| Plant | Mycoparasites | Pathogens |\n");
            md.push_str("|-------|---------------|-----------||\n");
            for hub in pathogen_profile.hub_plants.iter().take(10) {
                md.push_str(&format!(
                    "| {} | {} | {} |\n",
                    hub.plant_name,
                    hub.mycoparasite_count,
                    hub.pathogen_count
                ));
            }
            md.push_str("\n");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::explanation::types::*;

    #[test]
    fn test_format_basic() {
        let explanation = Explanation {
            overall: OverallExplanation {
                score: 85.0,
                stars: "★★★★☆".to_string(),
                label: "Excellent".to_string(),
                message: "Overall guild compatibility: 85.0/100".to_string(),
            },
            climate: ClimateExplanation {
                compatible: true,
                tier: "tier_3_humid_temperate".to_string(),
                tier_display: "Tier 3 (Humid Temperate)".to_string(),
                message: "All plants compatible with Tier 3 (Humid Temperate)".to_string(),
            },
            benefits: vec![],
            warnings: vec![],
            risks: vec![],
            metrics_display: MetricsDisplay {
                universal: vec![
                    MetricCard {
                        code: "M1".to_string(),
                        name: "Pest & Pathogen Independence".to_string(),
                        score: 90.0,
                        raw: 0.1,
                        interpretation: "Excellent".to_string(),
                    },
                ],
                bonus: vec![],
            },
            pest_profile: None,
        };

        let md = MarkdownFormatter::format(&explanation);

        assert!(md.contains("# ★★★★☆ - Excellent"));
        assert!(md.contains("**Overall Score:** 85.0/100"));
        assert!(md.contains("## Climate Compatibility"));
        assert!(md.contains("## Metrics Breakdown"));
        assert!(md.contains("M1 - Pest & Pathogen Independence"));
    }

    #[test]
    fn test_format_with_warnings() {
        let explanation = Explanation {
            overall: OverallExplanation {
                score: 60.0,
                stars: "★★☆☆☆".to_string(),
                label: "Fair".to_string(),
                message: "Overall guild compatibility: 60.0/100".to_string(),
            },
            climate: ClimateExplanation {
                compatible: true,
                tier: "tier_3_humid_temperate".to_string(),
                tier_display: "Tier 3 (Humid Temperate)".to_string(),
                message: "All plants compatible with Tier 3 (Humid Temperate)".to_string(),
            },
            benefits: vec![],
            warnings: vec![WarningCard {
                warning_type: "nitrogen_excess".to_string(),
                severity: Severity::Medium,
                icon: "⚠️".to_string(),
                message: "3 nitrogen-fixing plants may over-fertilize".to_string(),
                detail: "Excess nitrogen can favor fast-growing weeds".to_string(),
                advice: "Reduce to 1-2 nitrogen fixers".to_string(),
            }],
            risks: vec![],
            metrics_display: MetricsDisplay {
                universal: vec![],
                bonus: vec![],
            },
            pest_profile: None,
        };

        let md = MarkdownFormatter::format(&explanation);

        assert!(md.contains("## Warnings"));
        assert!(md.contains("⚠️ **3 nitrogen-fixing plants may over-fertilize**"));
        assert!(md.contains("*Advice:* Reduce to 1-2 nitrogen fixers"));
    }
}
