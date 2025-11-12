#!/usr/bin/env Rscript
#
# Explanation Engine for 7-Metric Framework
#
# Generates user-friendly explanations for guild scores.
# Key change: NO N1/N2 risk cards (replaced by M1 phylogenetic distance)
#

suppressPackageStartupMessages({
  library(glue)
  library(dplyr)
})


#' Generate user-friendly explanation for guild result
#'
#' @param guild_result List from GuildScorerV3Shipley$score_guild()
#' @return List with overall, climate, risks, benefits, warnings, metrics_display
generate_explanation <- function(guild_result) {
  explanation <- list(
    overall = generate_overall_explanation(guild_result$overall_score),
    climate = generate_climate_explanation(guild_result$climate_tier),
    risks = generate_risks_explanation(guild_result),
    benefits = generate_benefits_explanation(guild_result),
    warnings = generate_warnings_explanation(guild_result),
    metrics_display = format_metrics_display(guild_result$metrics)
  )

  return(explanation)
}


#' Generate overall score explanation
generate_overall_explanation <- function(overall_score) {
  # Star rating
  stars <- if (overall_score >= 80) "★★★★★"
           else if (overall_score >= 60) "★★★★☆"
           else if (overall_score >= 40) "★★★☆☆"
           else if (overall_score >= 20) "★★☆☆☆"
           else "★☆☆☆☆"

  label <- if (overall_score >= 80) "Excellent Guild"
           else if (overall_score >= 60) "Good Guild"
           else if (overall_score >= 40) "Neutral Guild"
           else if (overall_score >= 20) "Below Average Guild"
           else "Poor Guild"

  list(
    score = round(overall_score, 1),
    stars = stars,
    label = label,
    message = glue("{round(overall_score, 1)}/100")
  )
}


#' Generate climate compatibility explanation
generate_climate_explanation <- function(climate_tier) {
  tier_names <- list(
    tier_1_tropical = "Tropical (Af, Am, As, Aw)",
    tier_2_mediterranean = "Mediterranean (Csa, Csb, Csc)",
    tier_3_humid_temperate = "Humid Temperate (Cfa, Cfb, Cfc, Cwa, Cwb, Cwc)",
    tier_4_continental = "Continental (Dfa-Dfd, Dwa-Dwd, Dsa-Dsd)",
    tier_5_boreal_polar = "Boreal/Polar (ET, EF)",
    tier_6_arid = "Arid (BWh, BWk, BSh, BSk)"
  )

  tier_display <- tier_names[[climate_tier]]
  if (is.null(tier_display)) tier_display <- climate_tier

  list(
    compatible = TRUE,
    tier = climate_tier,
    tier_display = tier_display,
    message = glue("✓ All plants compatible with {tier_display}")
  )
}


#' Generate risk explanations
#'
#' CRITICAL: NO N1/N2 risk cards in 7-metric framework
#' M1 (phylogenetic distance) replaces pest/pathogen sharing metrics
generate_risks_explanation <- function(guild_result) {
  risks <- list()

  # Default: No specific risks detected
  # (M1 score captures pest/pathogen risk via phylogenetic distance)
  risks[[1]] <- list(
    type = "none",
    severity = "none",
    icon = "✓",
    title = "No Specific Risk Factors Detected",
    message = "Guild metrics show generally compatible plants",
    detail = "Review individual metrics and observed organisms for optimization opportunities",
    advice = "Check metric breakdown for specific guidance"
  )

  return(risks)
}


#' Generate benefit explanations
generate_benefits_explanation <- function(guild_result) {
  benefits <- list()
  metrics <- guild_result$metrics
  details <- guild_result$details

  # M1: Evolutionary Distance Benefits
  if (metrics$m1 > 50) {
    benefits[[length(benefits) + 1]] <- list(
      type = "evolutionary_distance",
      title = "Evolutionary Distance Benefits",
      message = glue("M1 Score: {round(metrics$m1, 1)}/100"),
      detail = "Phylogenetically distant plants reduce shared pest/pathogen risk",
      evidence = glue("Faith's PD: {round(details$m1$faiths_pd, 2)}")
    )
  }

  # M5: Beneficial Fungi Networks
  if (metrics$m5 > 30) {
    benefits[[length(benefits) + 1]] <- list(
      type = "beneficial_fungi",
      title = "Shared Beneficial Fungi Networks",
      message = glue("M5 Score: {round(metrics$m5, 1)}/100"),
      detail = glue("{details$m5$plants_with_fungi} plants connected through beneficial fungi"),
      evidence = glue("{details$m5$n_shared_fungi} shared fungal species")
    )
  }

  # M6: Structural Diversity
  if (metrics$m6 > 50) {
    benefits[[length(benefits) + 1]] <- list(
      type = "structural_diversity",
      title = "Vertical Space Utilization",
      message = glue("M6 Score: {round(metrics$m6, 1)}/100"),
      detail = glue("{details$m6$n_forms} growth forms utilize different height layers"),
      evidence = if (!is.null(details$m6$forms) && length(details$m6$forms) > 0) {
        paste(details$m6$forms, collapse = ", ")
      } else {
        "Diverse heights"
      }
    )
  }

  # M7: Pollinator Support
  if (metrics$m7 > 30) {
    benefits[[length(benefits) + 1]] <- list(
      type = "pollinator_support",
      title = "Shared Pollinator Network",
      message = glue("M7 Score: {round(metrics$m7, 1)}/100"),
      detail = glue("{details$m7$n_shared_pollinators} pollinator species serve multiple plants"),
      evidence = if (length(details$m7$pollinators) > 0) {
        paste(details$m7$pollinators, collapse = ", ")
      } else {
        "Multiple pollinators"
      }
    )
  }

  # If no benefits, add a placeholder
  if (length(benefits) == 0) {
    benefits[[1]] <- list(
      type = "minimal",
      title = "Limited Beneficial Interactions",
      message = "Guild shows basic compatibility",
      detail = "Consider adding plants with higher diversity scores"
    )
  }

  return(benefits)
}


#' Generate warnings
generate_warnings_explanation <- function(guild_result) {
  warnings <- list()
  details <- guild_result$details
  flags <- guild_result$flags

  # M2: CSR conflicts
  if (guild_result$metrics$m2 < 60 && details$m2$n_conflicts > 0) {
    conflict_types <- c()
    if (details$m2$high_c >= 2) {
      conflict_types <- c(conflict_types, glue("{details$m2$high_c} Competitive plants (C-C conflicts)"))
    }
    if (details$m2$high_c > 0 && details$m2$high_s > 0) {
      conflict_types <- c(conflict_types, "C-S conflicts detected")
    }
    if (details$m2$high_c > 0 && details$m2$high_r > 0) {
      conflict_types <- c(conflict_types, "C-R conflicts detected")
    }

    warnings[[length(warnings) + 1]] <- list(
      type = "csr_conflict",
      severity = "medium",
      icon = "⚠",
      message = "CSR Strategy Conflicts Detected",
      detail = paste(conflict_types, collapse = "; "),
      advice = "Plants may compete for resources - monitor growth patterns"
    )
  }

  # N5: Nitrogen fixation
  if (flags$nitrogen != "None") {
    warnings[[length(warnings) + 1]] <- list(
      type = "nitrogen_fixation",
      severity = "info",
      icon = "ℹ",
      message = glue("Nitrogen-Fixing Plants Present: {flags$nitrogen}"),
      detail = "These plants can enrich soil nitrogen",
      advice = "Consider reducing nitrogen fertilizer for this guild"
    )
  }

  # N6: pH compatibility
  if (flags$soil_ph != "Compatible") {
    warnings[[length(warnings) + 1]] <- list(
      type = "ph_incompatible",
      severity = "high",
      icon = "⚠",
      message = "pH Incompatibility Detected",
      detail = glue("Plants have conflicting pH requirements: {flags$soil_ph}"),
      advice = "Some plants may struggle - check soil pH and amend accordingly"
    )
  }

  return(warnings)
}


#' Format metrics for display (grouped)
format_metrics_display <- function(metrics) {
  # Universal indicators (available for all plants)
  universal <- list(
    list(name = "Pest Pathogen Indep (M1)", score = metrics$m1, code = "m1"),
    list(name = "Structural Diversity (M6)", score = metrics$m6, code = "m6"),
    list(name = "Growth Compatibility (M2)", score = metrics$m2, code = "m2")
  )

  # Bonus indicators (dependent on available data)
  bonus <- list(
    list(name = "Beneficial Fungi (M5)", score = metrics$m5, code = "m5"),
    list(name = "Disease Control (M4)", score = metrics$m4, code = "m4"),
    list(name = "Insect Control (M3)", score = metrics$m3, code = "m3"),
    list(name = "Pollinator Support (M7)", score = metrics$m7, code = "m7")
  )

  list(universal = universal, bonus = bonus)
}
