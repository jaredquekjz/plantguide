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
  # Star rating (RUST PARITY: 6-level system, generator.rs lines 151-158)
  stars <- if (overall_score >= 90) "★★★★★"
           else if (overall_score >= 80) "★★★★☆"
           else if (overall_score >= 70) "★★★☆☆"
           else if (overall_score >= 60) "★★☆☆☆"
           else if (overall_score >= 50) "★☆☆☆☆"
           else "☆☆☆☆☆"

  label <- if (overall_score >= 90) "Exceptional"
           else if (overall_score >= 80) "Excellent"
           else if (overall_score >= 70) "Good"
           else if (overall_score >= 60) "Fair"
           else if (overall_score >= 50) "Poor"
           else "Unsuitable"

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
#' Generate risk explanations (RUST PARITY)
#' M1 (phylogenetic distance) replaces old N1/N2 pest sharing metrics
generate_risks_explanation <- function(guild_result) {
  risks <- list()
  metrics <- guild_result$metrics
  details <- guild_result$details

  # M1: Pest vulnerability risk (RUST PARITY: generator.rs lines 258-275)
  m1_score <- if (is.null(metrics$m1)) NA else metrics$m1
  if (!is.na(m1_score) && m1_score < 30) {
    faiths_pd <- if (!is.null(details$m1$faiths_pd)) details$m1$faiths_pd else NA

    risks[[length(risks) + 1]] <- list(
      type = "pest_vulnerability",
      severity = "medium",
      icon = "🦠",
      title = "Closely Related Plants",
      message = "Guild contains closely related plants that may share pests",
      detail = if (!is.na(faiths_pd)) {
        glue("Low phylogenetic diversity (Faith's PD: {round(faiths_pd, 2)}) increases pest/pathogen risk")
      } else {
        "Low phylogenetic diversity increases pest/pathogen risk"
      },
      advice = "Consider adding plants from different families to increase diversity"
    )
  }

  # Default: No risks if none detected
  if (length(risks) == 0) {
    risks[[1]] <- list(
      type = "none",
      severity = "none",
      icon = "✓",
      title = "No Specific Risk Factors Detected",
      message = "Guild metrics show generally compatible plants",
      detail = "Review individual metrics and observed organisms for optimization opportunities",
      advice = "Check metric breakdown for specific guidance"
    )
  }

  return(risks)
}


#' Generate benefit explanations
generate_benefits_explanation <- function(guild_result) {
  benefits <- list()
  metrics <- guild_result$metrics
  details <- guild_result$details

  # M1: Evolutionary Distance Benefits
  m1_score <- if (is.null(metrics$m1)) NA else metrics$m1
  if (!is.na(m1_score) && m1_score > 50) {
    faiths_pd <- if (is.null(details$m1$faiths_pd)) 0 else details$m1$faiths_pd
    benefits[[length(benefits) + 1]] <- list(
      type = "evolutionary_distance",
      title = "Evolutionary Distance Benefits",
      message = glue("M1 Score: {round(m1_score, 1)}/100"),
      detail = "Phylogenetically distant plants reduce shared pest/pathogen risk",
      evidence = glue("Faith's PD: {round(faiths_pd, 2)}")
    )
  }

  # M5: Beneficial Fungi Networks
  m5_score <- if (is.null(metrics$m5)) NA else metrics$m5
  if (!is.na(m5_score) && m5_score > 30) {
    plants_with_fungi <- if (is.null(details$m5$plants_with_fungi)) 0 else details$m5$plants_with_fungi
    n_shared_fungi <- if (is.null(details$m5$n_shared_fungi)) 0 else details$m5$n_shared_fungi
    benefits[[length(benefits) + 1]] <- list(
      type = "beneficial_fungi",
      title = "Shared Beneficial Fungi Networks",
      message = glue("M5 Score: {round(m5_score, 1)}/100"),
      detail = glue("{plants_with_fungi} plants connected through beneficial fungi"),
      evidence = glue("{n_shared_fungi} shared fungal species")
    )
  }

  # M6: Structural Diversity
  m6_score <- if (is.null(metrics$m6)) NA else metrics$m6
  if (!is.na(m6_score) && m6_score > 50) {
    n_forms <- if (is.null(details$m6$n_forms)) 0 else details$m6$n_forms
    benefits[[length(benefits) + 1]] <- list(
      type = "structural_diversity",
      title = "Vertical Space Utilization",
      message = glue("M6 Score: {round(m6_score, 1)}/100"),
      detail = glue("{n_forms} growth forms utilize different height layers"),
      evidence = if (!is.null(details$m6$forms) && length(details$m6$forms) > 0) {
        paste(details$m6$forms, collapse = ", ")
      } else {
        "Diverse heights"
      }
    )
  }

  # M7: Pollinator Support
  m7_score <- if (is.null(metrics$m7)) NA else metrics$m7
  if (!is.na(m7_score) && m7_score > 30) {
    n_shared_pollinators <- if (is.null(details$m7$n_shared_pollinators)) 0 else details$m7$n_shared_pollinators
    pollinators <- if (is.null(details$m7$pollinators)) character(0) else details$m7$pollinators
    benefits[[length(benefits) + 1]] <- list(
      type = "pollinator_support",
      title = "Shared Pollinator Network",
      message = glue("M7 Score: {round(m7_score, 1)}/100"),
      detail = glue("{n_shared_pollinators} pollinator species serve multiple plants"),
      evidence = if (length(pollinators) > 0) {
        paste(pollinators, collapse = ", ")
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


#' Compute pH compatibility from guild plants (RUST PARITY)
#'
#' @param guild_plants Data frame with wfo_scientific_name and eive_r columns
#' @return List with flag, severity, message, r_min, r_max, r_range
compute_ph_compatibility <- function(guild_plants) {
  # Extract EIVE R values (soil reaction indicator)
  eive_r_values <- guild_plants$eive_r[!is.na(guild_plants$eive_r)]

  # Need at least 2 plants with pH data
  if (length(eive_r_values) < 2) {
    return(list(
      flag = "Insufficient data",
      severity = "info",
      message = NULL,
      r_min = NA,
      r_max = NA,
      r_range = NA
    ))
  }

  # Calculate pH range
  r_min <- min(eive_r_values)
  r_max <- max(eive_r_values)
  r_range <- r_max - r_min

  # Determine severity based on Rust thresholds (scorer.rs lines 365-392)
  if (r_range < 1.0) {
    return(list(
      flag = "Compatible",
      severity = "none",
      message = NULL,
      r_min = r_min,
      r_max = r_max,
      r_range = r_range
    ))
  } else if (r_range < 2.0) {
    severity <- "info"
    flag <- "Minor incompatibility"
  } else if (r_range < 3.0) {
    severity <- "warning"
    flag = "Moderate incompatibility"
  } else {
    severity <- "critical"
    flag <- "Strong incompatibility"
  }

  # Generate detailed message with plant pH categories
  message <- generate_ph_warning_message(guild_plants, r_min, r_max, r_range)

  return(list(
    flag = flag,
    severity = severity,
    message = message,
    r_min = r_min,
    r_max = r_max,
    r_range = r_range
  ))
}


#' Generate pH warning message with plant categories (RUST PARITY)
#'
#' @param guild_plants Data frame with plant data
#' @param r_min Minimum EIVE R value
#' @param r_max Maximum EIVE R value
#' @param r_range pH range
#' @return Formatted warning message
generate_ph_warning_message <- function(guild_plants, r_min, r_max, r_range) {
  # Map EIVE R to pH categories (Rust generator.rs lines 234-250)
  get_ph_category <- function(r_value) {
    if (is.na(r_value)) return("Unknown")
    if (r_value <= 2) return("Strongly Acidic (pH 3-4)")
    if (r_value <= 4) return("Acidic (pH 4-5)")
    if (r_value <= 5) return("Slightly Acidic (pH 5-6)")
    if (r_value <= 7) return("Neutral (pH 6-7)")
    if (r_value <= 8) return("Alkaline (pH 7-8)")
    return("Strongly Alkaline (pH 8-9)")
  }

  # Build plant list with pH categories
  plants_with_ph <- guild_plants %>%
    filter(!is.na(eive_r)) %>%
    mutate(ph_category = sapply(eive_r, get_ph_category)) %>%
    select(wfo_scientific_name, eive_r, ph_category) %>%
    arrange(eive_r)

  plant_list <- paste0("- ", plants_with_ph$wfo_scientific_name, ": ",
                      plants_with_ph$ph_category, collapse = "\n")

  message <- glue(
    "EIVE R range: {round(r_min, 1)}-{round(r_max, 1)} (difference: {round(r_range, 1)} units)\n\n",
    "Plant pH preferences:\n{plant_list}\n\n",
    "Advice: ",
    if (r_range >= 3.0) {
      "Strong pH incompatibility. These plants have very different pH needs. Use separate zones with pH amendments or reconsider plant selection."
    } else if (r_range >= 2.0) {
      "Moderate pH incompatibility. Use soil amendments to adjust pH for different zones."
    } else {
      "Minor pH differences. Most plants should coexist with minimal pH adjustment."
    }
  )

  return(message)
}


#' Generate warnings
generate_warnings_explanation <- function(guild_result) {
  warnings <- list()
  details <- guild_result$details
  flags <- guild_result$flags
  guild_plants <- guild_result$guild_plants  # Needed for pH computation

  # M2: CSR conflicts (RUST PARITY: only check conflicts>0, not M2 score)
  m2_conflicts <- if (is.null(details$m2$n_conflicts)) 0 else details$m2$n_conflicts

  if (!is.na(m2_conflicts) && m2_conflicts > 0) {
    conflict_types <- c()
    high_c <- if (is.null(details$m2$high_c)) 0 else details$m2$high_c
    high_s <- if (is.null(details$m2$high_s)) 0 else details$m2$high_s
    high_r <- if (is.null(details$m2$high_r)) 0 else details$m2$high_r

    if (high_c >= 2) {
      conflict_types <- c(conflict_types, glue("{high_c} Competitive plants (C-C conflicts)"))
    }
    if (high_c > 0 && high_s > 0) {
      conflict_types <- c(conflict_types, "C-S conflicts detected")
    }
    if (high_c > 0 && high_r > 0) {
      conflict_types <- c(conflict_types, "C-R conflicts detected")
    }

    if (length(conflict_types) > 0) {
      warnings[[length(warnings) + 1]] <- list(
        type = "csr_conflict",
        severity = "medium",
        icon = "⚠",
        message = "CSR Strategy Conflicts Detected",
        detail = paste(conflict_types, collapse = "; "),
        advice = "Plants may compete for resources - monitor growth patterns"
      )
    }
  }

  # N5: Nitrogen fixation (RUST PARITY: threshold >2, nitrogen.rs lines 17-25)
  n_fixers <- if (!is.null(guild_plants) && "nitrogen_fixation" %in% colnames(guild_plants)) {
    sum(guild_plants$nitrogen_fixation %in% c("Yes", "yes", "Y"), na.rm = TRUE)
  } else {
    0
  }

  if (n_fixers > 2) {
    warnings[[length(warnings) + 1]] <- list(
      type = "nitrogen_excess",
      severity = "medium",
      icon = "⚠️",
      message = glue("{n_fixers} nitrogen-fixing plants may over-fertilize"),
      detail = "Excess nitrogen can favor fast-growing weeds and reduce soil biodiversity",
      advice = "Reduce to 1-2 nitrogen fixers or add nitrogen-demanding plants"
    )
  }

  # N6: pH compatibility (RUST PARITY: compute from guild plants)
  ph_result <- if (!is.null(guild_plants)) {
    compute_ph_compatibility(guild_plants)
  } else {
    list(flag = "Compatible", severity = "none", message = NULL)
  }

  if (!is.null(ph_result$message) && ph_result$flag != "Compatible") {
    # Map severity to icon
    icon <- if (ph_result$severity == "critical") "🔴"
           else if (ph_result$severity == "warning") "⚠️"
           else "ℹ️"

    warnings[[length(warnings) + 1]] <- list(
      type = "ph_incompatible",
      severity = ph_result$severity,
      icon = icon,
      message = "pH Incompatibility Detected",
      detail = ph_result$message,
      advice = NULL  # Advice already in message
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
