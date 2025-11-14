#!/usr/bin/env Rscript
#
# Markdown Exporter for Guild Reports (Rust-Compatible Format)
#
# Exports guild scoring results and explanations to markdown format
# matching the exact structure of Rust guild_scorer output.
#

suppressPackageStartupMessages({
  library(glue)
  library(dplyr)
})


#' Export guild report to markdown file (Rust-compatible format)
#'
#' @param guild_result List from GuildScorerV3Modular$score_guild()
#' @param output_path Path to save markdown file
#' @param guild_name Optional guild name for title
export_guild_report_md <- function(guild_result, output_path, guild_name = NULL) {
  md <- ""

  # ============================================================================
  # HEADER
  # ============================================================================

  score <- guild_result$overall_score
  stars <- get_star_rating(score)
  label <- get_score_label(score)

  md <- paste0(md, sprintf("# %s - %s\n\n", stars, label))
  md <- paste0(md, sprintf("**Overall Score:** %.1f/100\n\n", score))
  md <- paste0(md, sprintf("Overall guild compatibility: %.1f/100\n\n", score))

  # ============================================================================
  # CLIMATE COMPATIBILITY
  # ============================================================================

  md <- paste0(md, "## Climate Compatibility\n\n")
  tier_display <- format_climate_tier(guild_result$climate_tier)
  md <- paste0(md, sprintf("✅ All plants compatible with %s\n\n", tier_display))

  # ============================================================================
  # BENEFITS
  # ============================================================================

  md <- paste0(md, "## Benefits\n\n")

  # M1: Phylogenetic Diversity + Pest Profile
  md <- paste0(md, format_m1_section(guild_result))

  # M3: Insect Pest Control + Biocontrol Profile
  md <- paste0(md, format_m3_section(guild_result))

  # M4: Disease Suppression + Pathogen Control Profile
  md <- paste0(md, format_m4_section(guild_result))

  # M5: Beneficial Fungi + Network Profile
  md <- paste0(md, format_m5_section(guild_result))

  # M6: Structural Diversity
  md <- paste0(md, format_m6_section(guild_result))

  # M7: Pollinator Support + Network Profile
  md <- paste0(md, format_m7_section(guild_result))

  # ============================================================================
  # WARNINGS
  # ============================================================================

  md <- paste0(md, format_warnings_section(guild_result))

  # ============================================================================
  # METRICS BREAKDOWN
  # ============================================================================

  md <- paste0(md, format_metrics_breakdown(guild_result))

  # Write to file
  writeLines(md, output_path)

  return(md)
}


# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

get_star_rating <- function(score) {
  if (score >= 90) return("★★★★★")
  if (score >= 80) return("★★★★☆")
  if (score >= 60) return("★★★☆☆")
  if (score >= 40) return("★★☆☆☆")
  if (score >= 20) return("★☆☆☆☆")
  return("☆☆☆☆☆")
}

get_score_label <- function(score) {
  if (score >= 90) return("Exceptional")
  if (score >= 80) return("Excellent")
  if (score >= 60) return("Good")
  if (score >= 40) return("Fair")
  if (score >= 20) return("Poor")
  return("Unsuitable")
}

format_climate_tier <- function(tier) {
  tier_map <- list(
    tier_1_tropical = "Tier 1 (Tropical)",
    tier_2_mediterranean = "Tier 2 (Mediterranean)",
    tier_3_humid_temperate = "Tier 3 (Humid Temperate)",
    tier_4_continental = "Tier 4 (Continental)",
    tier_5_boreal_polar = "Tier 5 (Boreal/Polar)",
    tier_6_arid = "Tier 6 (Arid)"
  )

  if (tier %in% names(tier_map)) {
    return(tier_map[[tier]])
  }
  return(tier)
}


# ==============================================================================
# M1: PHYLOGENETIC DIVERSITY + PEST PROFILE
# ==============================================================================

format_m1_section <- function(guild_result) {
  m1_score <- guild_result$metrics$m1
  faiths_pd <- guild_result$details$m1$faiths_pd

  if (is.null(m1_score) || is.na(m1_score)) return("")

  md <- "### High Phylogenetic Diversity [M1]\n\n"
  md <- paste0(md, sprintf("Plants are distantly related (Faith's PD: %.2f)  \n", faiths_pd))
  md <- paste0(md, "Distant relatives typically share fewer pests and pathogens, reducing disease spread in the guild.  \n\n")
  md <- paste0(md, sprintf("*Evidence:* Phylogenetic diversity score: %.1f/100\n\n", m1_score))

  # Add pest vulnerability profile
  pest_profile <- guild_result$network_profiles$pest_profile
  if (!is.null(pest_profile)) {
    md <- paste0(md, "#### Pest Vulnerability Profile\n\n")
    md <- paste0(md, "*Qualitative information about herbivore pests (not used in scoring)*\n\n")
    md <- paste0(md, sprintf("**Total unique herbivore species:** %d\n\n", pest_profile$total_unique_pests))

    # Check for shared pests
    if (nrow(pest_profile$shared_pests) == 0) {
      md <- paste0(md, "**No shared pests detected** - Each herbivore attacks only one plant species in this guild, indicating high diversity.\n\n")
    } else {
      md <- paste0(md, sprintf("**%d shared pest species detected** - These generalist herbivores attack multiple plants:\n\n", nrow(pest_profile$shared_pests)))
    }

    # Top 10 pests table
    md <- paste0(md, "**Top 10 Herbivore Pests**\n\n")
    md <- paste0(md, "| Rank | Pest Species | Plants Attacked |\n")
    md <- paste0(md, "|------|--------------|------------------|\n")

    if (nrow(pest_profile$top_pests) > 0) {
      for (i in 1:min(10, nrow(pest_profile$top_pests))) {
        pest <- pest_profile$top_pests[i, ]
        md <- paste0(md, sprintf("| %d | %s | %s |\n", i, pest$pest_name, pest$plants))
      }
    }
    md <- paste0(md, "\n")

    # Most vulnerable plants
    if (nrow(pest_profile$vulnerable_plants) > 0) {
      md <- paste0(md, "**Most Vulnerable Plants**\n\n")
      md <- paste0(md, "| Plant | Herbivore Count |\n")
      md <- paste0(md, "|-------|------------------|\n")
      for (i in 1:min(5, nrow(pest_profile$vulnerable_plants))) {
        plant <- pest_profile$vulnerable_plants[i, ]
        md <- paste0(md, sprintf("| %s | %d |\n", plant$plant_name, plant$pest_count))
      }
      md <- paste0(md, "\n")
    }
  }

  return(md)
}


# ==============================================================================
# M3: INSECT PEST CONTROL + BIOCONTROL PROFILE
# ==============================================================================

format_m3_section <- function(guild_result) {
  m3_score <- guild_result$metrics$m3

  if (is.null(m3_score) || is.na(m3_score) || m3_score < 30) return("")

  biocontrol_profile <- guild_result$network_profiles$biocontrol_profile
  n_mechanisms <- guild_result$details$m3$n_mechanisms

  md <- "### Natural Insect Pest Control [M3]\n\n"
  md <- paste0(md, sprintf("Guild provides insect pest control via %d biocontrol mechanisms  \n", n_mechanisms))
  md <- paste0(md, "Plants attract beneficial insects (predators and parasitoids) that naturally suppress pest populations.  \n\n")
  md <- paste0(md, sprintf("*Evidence:* Biocontrol score: %.1f/100, covering %d mechanisms\n\n", m3_score, n_mechanisms))

  if (!is.null(biocontrol_profile)) {
    md <- paste0(md, "#### Biocontrol Network Profile\n\n")
    md <- paste0(md, "*Qualitative information about insect pest control (influences M3 scoring)*\n\n")
    md <- paste0(md, sprintf("**Total unique biocontrol agents:** %d\n",
                            biocontrol_profile$total_unique_predators + biocontrol_profile$total_unique_entomo_fungi))
    md <- paste0(md, sprintf("- %d Animal predators\n", biocontrol_profile$total_unique_predators))
    md <- paste0(md, sprintf("- %d Entomopathogenic fungi\n\n", biocontrol_profile$total_unique_entomo_fungi))

    md <- paste0(md, "**Mechanism Summary:**\n")
    md <- paste0(md, sprintf("- %d Specific predator matches (herbivore → known predator)\n",
                            biocontrol_profile$specific_predator_matches))
    md <- paste0(md, sprintf("- %d Specific fungi matches (herbivore → known entomopathogenic fungus)\n",
                            biocontrol_profile$specific_fungi_matches))
    md <- paste0(md, sprintf("- %d General entomopathogenic fungi interactions (weight 0.2 each)\n\n",
                            biocontrol_profile$general_entomo_fungi_count))

    # Matched predator pairs
    if (nrow(biocontrol_profile$matched_predator_pairs) > 0) {
      md <- paste0(md, "**Matched Herbivore → Predator Pairs:**\n\n")
      md <- paste0(md, "| Herbivore (Pest) | Herbivore Category | Known Predator | Predator Category | Match Type |\n")
      md <- paste0(md, "|------------------|-------------------|----------------|-------------------|------------|\n")
      for (i in 1:nrow(biocontrol_profile$matched_predator_pairs)) {
        pair <- biocontrol_profile$matched_predator_pairs[i, ]
        md <- paste0(md, sprintf("| %s | %s | %s | %s | Specific (weight 1.0) |\n",
                                pair$herbivore, pair$herbivore_category,
                                pair$predator, pair$predator_category))
      }
      md <- paste0(md, "\n")
    }

    # Matched fungi pairs
    if (nrow(biocontrol_profile$matched_fungi_pairs) > 0) {
      md <- paste0(md, "**Matched Herbivore → Entomopathogenic Fungus Pairs:**\n\n")
      md <- paste0(md, "| Herbivore (Pest) | Known Fungus | Match Type |\n")
      md <- paste0(md, "|------------------|--------------|------------|\n")
      for (i in 1:nrow(biocontrol_profile$matched_fungi_pairs)) {
        pair <- biocontrol_profile$matched_fungi_pairs[i, ]
        md <- paste0(md, sprintf("| %s | %s | Specific (weight 1.0) |\n", pair$herbivore, pair$fungus))
      }
      md <- paste0(md, "\n")
    }

    # Network hubs
    if (nrow(biocontrol_profile$hub_plants) > 0) {
      md <- paste0(md, "**Network Hubs (plants attracting most biocontrol):**\n\n")
      md <- paste0(md, "| Plant | Total Predators | Total Fungi | Combined |\n")
      md <- paste0(md, "|-------|----------------|-------------|----------|\n")
      for (i in 1:nrow(biocontrol_profile$hub_plants)) {
        hub <- biocontrol_profile$hub_plants[i, ]
        md <- paste0(md, sprintf("| %s | %d | %d | %d |\n",
                                hub$plant_name, hub$total_predators,
                                hub$total_entomo_fungi, hub$total_biocontrol_agents))
      }
      md <- paste0(md, "\n")
    }
  }

  return(md)
}


# ==============================================================================
# M4: DISEASE SUPPRESSION + PATHOGEN CONTROL PROFILE
# ==============================================================================

format_m4_section <- function(guild_result) {
  m4_score <- guild_result$metrics$m4

  if (is.null(m4_score) || is.na(m4_score) || m4_score < 30) return("")

  pathogen_profile <- guild_result$network_profiles$pathogen_control_profile
  n_mechanisms <- guild_result$details$m4$n_mechanisms

  md <- "### Natural Disease Suppression [M4]\n\n"
  md <- paste0(md, sprintf("Guild provides disease suppression via %d antagonistic fungal mechanisms  \n", n_mechanisms))
  md <- paste0(md, "Plants harbor beneficial fungi that antagonize pathogens, reducing disease incidence through biological control.  \n\n")
  md <- paste0(md, sprintf("*Evidence:* Pathogen control score: %.1f/100, covering %d mechanisms\n\n", m4_score, n_mechanisms))

  if (!is.null(pathogen_profile)) {
    md <- paste0(md, "#### Pathogen Control Network Profile\n\n")
    md <- paste0(md, "*Qualitative information about disease suppression (influences M4 scoring)*\n\n")
    md <- paste0(md, "**Summary:**\n")
    md <- paste0(md, sprintf("- %d unique mycoparasite species (fungi that parasitize other fungi)\n",
                            pathogen_profile$total_unique_mycoparasites))
    md <- paste0(md, sprintf("- %d unique pathogen species in guild\n\n", pathogen_profile$total_unique_pathogens))

    md <- paste0(md, "**Mechanism Summary:**\n")
    md <- paste0(md, sprintf("- %d Specific antagonist matches (pathogen → known mycoparasite, weight 1.0, rarely fires)\n",
                            pathogen_profile$specific_antagonist_matches))
    md <- paste0(md, sprintf("- %d General mycoparasite fungi (primary mechanism, weight 1.0)\n\n",
                            pathogen_profile$general_mycoparasite_count))

    # Matched antagonist pairs
    if (nrow(pathogen_profile$matched_antagonist_pairs) > 0) {
      md <- paste0(md, "**Matched Pathogen → Antagonist Pairs:**\n\n")
      md <- paste0(md, "| Pathogen | Known Antagonist | Match Type |\n")
      md <- paste0(md, "|----------|------------------|------------|\n")
      for (i in 1:nrow(pathogen_profile$matched_antagonist_pairs)) {
        pair <- pathogen_profile$matched_antagonist_pairs[i, ]
        md <- paste0(md, sprintf("| %s | %s | Specific (weight 1.0) |\n", pair$pathogen, pair$antagonist))
      }
      md <- paste0(md, "\n")
    }

    # Network hubs
    if (nrow(pathogen_profile$hub_plants) > 0) {
      md <- paste0(md, "**Network Hubs (plants harboring most mycoparasites):**\n\n")
      md <- paste0(md, "| Plant | Mycoparasites | Pathogens |\n")
      md <- paste0(md, "|-------|---------------|-----------||\n")
      for (i in 1:nrow(pathogen_profile$hub_plants)) {
        hub <- pathogen_profile$hub_plants[i, ]
        md <- paste0(md, sprintf("| %s | %d | %d |\n", hub$plant_name, hub$mycoparasites, hub$pathogens))
      }
      md <- paste0(md, "\n")
    }
  }

  return(md)
}


# ==============================================================================
# M5: BENEFICIAL FUNGI + NETWORK PROFILE
# ==============================================================================

format_m5_section <- function(guild_result) {
  m5_score <- guild_result$metrics$m5

  if (is.null(m5_score) || is.na(m5_score) || m5_score < 30) return("")

  fungi_profile <- guild_result$network_profiles$fungi_network_profile
  network_score <- guild_result$details$m5$network_score
  coverage_ratio <- guild_result$details$m5$coverage_ratio
  n_shared <- guild_result$details$m5$n_shared_fungi

  md <- "### Beneficial Mycorrhizal Network [M5]\n\n"
  md <- paste0(md, sprintf("%d shared mycorrhizal fungal species connect %d plants  \n",
                          n_shared, guild_result$n_plants))
  md <- paste0(md, "Shared mycorrhizal fungi create underground networks that facilitate nutrient exchange, water sharing, and chemical communication between plants.  \n\n")
  md <- paste0(md, sprintf("*Evidence:* Network score: %.1f/100, coverage: %.1f%%\n\n",
                          m5_score, coverage_ratio * 100))

  if (!is.null(fungi_profile)) {
    md <- paste0(md, "#### Beneficial Fungi Network Profile\n\n")
    md <- paste0(md, "*Qualitative information about fungal networks (60% of M5 scoring)*\n\n")
    md <- paste0(md, sprintf("**Total unique beneficial fungi species:** %d\n\n", fungi_profile$total_unique_fungi))

    # Fungal community composition
    md <- paste0(md, "**Fungal Community Composition:**\n\n")
    total <- fungi_profile$fungi_by_category$amf_count +
             fungi_profile$fungi_by_category$emf_count +
             fungi_profile$fungi_by_category$endophytic_count +
             fungi_profile$fungi_by_category$saprotrophic_count

    if (total > 0) {
      md <- paste0(md, sprintf("- %d AMF species (Arbuscular Mycorrhizal) - %.1f%%\n",
                              fungi_profile$fungi_by_category$amf_count,
                              fungi_profile$fungi_by_category$amf_count / total * 100))
      md <- paste0(md, sprintf("- %d EMF species (Ectomycorrhizal) - %.1f%%\n",
                              fungi_profile$fungi_by_category$emf_count,
                              fungi_profile$fungi_by_category$emf_count / total * 100))
      md <- paste0(md, sprintf("- %d Endophytic species - %.1f%%\n",
                              fungi_profile$fungi_by_category$endophytic_count,
                              fungi_profile$fungi_by_category$endophytic_count / total * 100))
      md <- paste0(md, sprintf("- %d Saprotrophic species - %.1f%%\n\n",
                              fungi_profile$fungi_by_category$saprotrophic_count,
                              fungi_profile$fungi_by_category$saprotrophic_count / total * 100))
    }

    # Top network fungi
    if (nrow(fungi_profile$top_fungi) > 0) {
      md <- paste0(md, "**Top Network Fungi (by connectivity):**\n\n")
      md <- paste0(md, "| Rank | Fungus Species | Category | Plants Connected | Network Contribution |\n")
      md <- paste0(md, "|------|----------------|----------|------------------|----------------------|\n")
      for (i in 1:nrow(fungi_profile$top_fungi)) {
        fungus <- fungi_profile$top_fungi[i, ]
        md <- paste0(md, sprintf("| %d | %s | %s | %s | %.1f%% |\n",
                                i, fungus$fungus_name, fungus$category, fungus$plants,
                                fungus$network_contribution * 100))
      }
      md <- paste0(md, "\n")
    }

    # Network hubs
    if (nrow(fungi_profile$hub_plants) > 0) {
      md <- paste0(md, "**Network Hubs (most connected plants):**\n\n")
      md <- paste0(md, "| Plant | Total Fungi | AMF | EMF | Endophytic | Saprotrophic |\n")
      md <- paste0(md, "|-------|-------------|-----|-----|------------|---------------|\n")
      for (i in 1:nrow(fungi_profile$hub_plants)) {
        hub <- fungi_profile$hub_plants[i, ]
        md <- paste0(md, sprintf("| %s | %d | %d | %d | %d | %d |\n",
                                hub$plant_name, hub$fungus_count, hub$amf_count,
                                hub$emf_count, hub$endophytic_count, hub$saprotrophic_count))
      }
      md <- paste0(md, "\n")
    }
  }

  return(md)
}


# ==============================================================================
# M6: STRUCTURAL DIVERSITY
# ==============================================================================

format_m6_section <- function(guild_result) {
  m6_score <- guild_result$metrics$m6

  if (is.null(m6_score) || is.na(m6_score) || m6_score < 50) return("")

  # Note: M6 details would need substantial expansion to match Rust format
  # For now, provide simplified output
  n_forms <- guild_result$details$m6$n_forms

  md <- "### High Structural Diversity [M6]\n\n"
  md <- paste0(md, sprintf("%d growth forms spanning vertical layers  \n", n_forms))
  md <- paste0(md, "Different plant heights create vertical stratification, maximizing light capture and supporting diverse wildlife.  \n\n")
  md <- paste0(md, sprintf("*Evidence:* Structural diversity score: %.1f/100\n\n", m6_score))

  return(md)
}


# ==============================================================================
# M7: POLLINATOR SUPPORT + NETWORK PROFILE
# ==============================================================================

format_m7_section <- function(guild_result) {
  m7_score <- guild_result$metrics$m7

  if (is.null(m7_score) || is.na(m7_score) || m7_score < 30) return("")

  pollinator_profile <- guild_result$network_profiles$pollinator_network_profile
  n_shared <- guild_result$details$m7$n_shared_pollinators

  md <- "### Robust Pollinator Support [M7]\n\n"
  md <- paste0(md, sprintf("%d shared pollinator species  \n", n_shared))
  md <- paste0(md, "Plants attract and support overlapping pollinator communities, ensuring reliable pollination services and promoting pollinator diversity.  \n\n")
  md <- paste0(md, sprintf("*Evidence:* Pollinator support score: %.1f/100\n\n", m7_score))

  if (!is.null(pollinator_profile)) {
    md <- paste0(md, "#### Pollinator Network Profile\n\n")
    md <- paste0(md, "*Qualitative information about pollinator networks (100% of M7 scoring)*\n\n")
    md <- paste0(md, sprintf("**Total unique pollinator species:** %d\n\n", pollinator_profile$total_unique_pollinators))

    # Pollinator community composition
    if (!is.null(pollinator_profile$category_counts) && length(pollinator_profile$category_counts) > 0) {
      md <- paste0(md, "**Pollinator Community Composition:**\n\n")
      total <- sum(unlist(pollinator_profile$category_counts))
      for (cat in names(pollinator_profile$category_counts)) {
        count <- pollinator_profile$category_counts[[cat]]
        md <- paste0(md, sprintf("- %d %s - %.1f%%\n", count, cat, count / total * 100))
      }
      md <- paste0(md, "\n")
    }

    # Check for shared pollinators
    if (nrow(pollinator_profile$shared_pollinators) == 0) {
      md <- paste0(md, "**No shared pollinators detected** - Each pollinator visits only one plant species in this guild.\n\n")
    }

    # Top network pollinators
    if (nrow(pollinator_profile$top_pollinators) > 0) {
      md <- paste0(md, "**Top Network Pollinators (by connectivity):**\n\n")
      md <- paste0(md, "| Rank | Pollinator Species | Category | Plants Connected | Network Contribution |\n")
      md <- paste0(md, "|------|-------------------|----------|------------------|----------------------|\n")
      for (i in 1:nrow(pollinator_profile$top_pollinators)) {
        poll <- pollinator_profile$top_pollinators[i, ]
        # Format plants string
        plant_str <- if (poll$plant_count == 1) "1 plants" else sprintf("%d plants", poll$plant_count)
        md <- paste0(md, sprintf("| %d | %s | %s | %s | %.1f%% |\n",
                                i, poll$pollinator_name, poll$category, plant_str,
                                poll$network_contribution * 100))
      }
      md <- paste0(md, "\n")
    }

    # Network hubs
    if (nrow(pollinator_profile$hub_plants) > 0) {
      md <- paste0(md, "**Network Hubs (most connected plants):**\n\n")
      md <- paste0(md, "| Plant | Total | Bees | Butterflies | Moths | Flies | Beetles | Wasps | Birds | Bats | Other |\n")
      md <- paste0(md, "|-------|-------|------|-------------|-------|-------|---------|-------|-------|------|-------|\n")
      for (i in 1:nrow(pollinator_profile$hub_plants)) {
        hub <- pollinator_profile$hub_plants[i, ]
        md <- paste0(md, sprintf("| %s | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d |\n",
                                hub$plant_name, hub$total, hub$Bees, hub$Butterflies,
                                hub$Moths, hub$Flies, hub$Beetles, hub$Wasps,
                                hub$Birds, hub$Bats, hub$Other))
      }
      md <- paste0(md, "\n")
    }
  }

  return(md)
}


# ==============================================================================
# WARNINGS SECTION
# ==============================================================================

format_warnings_section <- function(guild_result) {
  md <- "## Warnings\n\n"

  # Check for pH incompatibility
  # This would need to be expanded based on actual guild_result structure
  # For now, provide placeholder

  md <- paste0(md, "*No critical warnings detected*\n\n")

  return(md)
}


# ==============================================================================
# METRICS BREAKDOWN
# ==============================================================================

format_metrics_breakdown <- function(guild_result) {
  md <- "## Metrics Breakdown\n\n"

  md <- paste0(md, "### Universal Indicators\n\n")
  md <- paste0(md, "| Metric | Score | Interpretation |\n")
  md <- paste0(md, "|--------|-------|----------------|\n")

  metrics <- guild_result$metrics
  for (metric_name in c("m1", "m2", "m3", "m4")) {
    score <- metrics[[metric_name]]
    label <- get_metric_label(metric_name)
    interp <- get_score_interpretation(score)
    md <- paste0(md, sprintf("| %s | %.1f | %s |\n", label, score, interp))
  }

  md <- paste0(md, "\n### Bonus Indicators\n\n")
  md <- paste0(md, "| Metric | Score | Interpretation |\n")
  md <- paste0(md, "|--------|-------|----------------|\n")

  for (metric_name in c("m5", "m6", "m7")) {
    score <- metrics[[metric_name]]
    label <- get_metric_label(metric_name)
    interp <- get_score_interpretation(score)
    md <- paste0(md, sprintf("| %s | %.1f | %s |\n", label, score, interp))
  }

  md <- paste0(md, "\n")

  return(md)
}

get_metric_label <- function(metric_name) {
  labels <- list(
    m1 = "M1 - Pest & Pathogen Independence",
    m2 = "M2 - Growth Compatibility",
    m3 = "M3 - Insect Pest Control",
    m4 = "M4 - Disease Suppression",
    m5 = "M5 - Beneficial Fungi",
    m6 = "M6 - Structural Diversity",
    m7 = "M7 - Pollinator Support"
  )
  return(labels[[metric_name]])
}

get_score_interpretation <- function(score) {
  if (score >= 80) return("Excellent")
  if (score >= 60) return("Good")
  if (score >= 40) return("Fair")
  if (score >= 20) return("Poor")
  return("Very Poor")
}
