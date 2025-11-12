#!/usr/bin/env Rscript
#
# Markdown Exporter for Guild Reports
#
# Exports guild scoring results and explanations to markdown format
#

suppressPackageStartupMessages({
  library(glue)
})


#' Export guild report to markdown file
#'
#' @param guild_result List from GuildScorerV3Shipley$score_guild()
#' @param explanation List from generate_explanation()
#' @param output_path Path to save markdown file
#' @param guild_name Optional guild name for title
export_guild_report_md <- function(guild_result, explanation, output_path, guild_name = NULL) {
  # Build markdown string
  md <- ""

  # Header
  if (!is.null(guild_name)) {
    md <- paste0(md, glue("# Guild Report: {guild_name}\n\n"))
  } else {
    md <- paste0(md, "# Guild Report\n\n")
  }

  md <- paste0(md, glue("## Overall Score: {explanation$overall$score} / 100 {explanation$overall$stars}\n\n"))
  md <- paste0(md, glue("**{explanation$overall$label}**\n\n"))
  md <- paste0(md, "---\n\n")

  # Plants in guild
  md <- paste0(md, "## Plants in Guild\n\n")
  for (i in seq_along(guild_result$plant_ids)) {
    md <- paste0(md, glue("- `{guild_result$plant_ids[i]}` *{guild_result$plant_names[i]}*\n"))
  }
  md <- paste0(md, "\n---\n\n")

  # Climate compatibility
  md <- paste0(md, "## Climate Compatibility\n\n")
  md <- paste0(md, glue("{explanation$climate$message}\n\n"))
  md <- paste0(md, "---\n\n")

  # Risks
  md <- paste0(md, "## Risks\n\n")
  for (risk in explanation$risks) {
    md <- paste0(md, glue("{risk$icon} **{risk$title}**\n\n"))
    if (!is.null(risk$message)) {
      md <- paste0(md, glue("{risk$message}\n\n"))
    }
    if (!is.null(risk$detail)) {
      md <- paste0(md, glue("*{risk$detail}*\n\n"))
    }
  }
  md <- paste0(md, "---\n\n")

  # Benefits
  md <- paste0(md, "## Benefits\n\n")
  if (length(explanation$benefits) > 0) {
    for (benefit in explanation$benefits) {
      md <- paste0(md, glue("✓ **{benefit$title}**\n\n"))
      md <- paste0(md, glue("  {benefit$message}\n\n"))
      if (!is.null(benefit$detail)) {
        md <- paste0(md, glue("  *{benefit$detail}*\n\n"))
      }
      if (!is.null(benefit$evidence)) {
        md <- paste0(md, glue("  Evidence: {benefit$evidence}\n\n"))
      }
    }
  } else {
    md <- paste0(md, "*No significant benefits detected*\n\n")
  }
  md <- paste0(md, "---\n\n")

  # Warnings
  if (length(explanation$warnings) > 0) {
    md <- paste0(md, "## Warnings\n\n")
    for (warning in explanation$warnings) {
      md <- paste0(md, glue("{warning$icon} **{warning$message}**\n\n"))
      if (!is.null(warning$detail)) {
        md <- paste0(md, glue("  {warning$detail}\n\n"))
      }
      if (!is.null(warning$advice)) {
        md <- paste0(md, glue("  *Advice: {warning$advice}*\n\n"))
      }
    }
    md <- paste0(md, "---\n\n")
  }

  # Flags
  if (!is.null(guild_result$flags)) {
    md <- paste0(md, "## Flags\n\n")
    md <- paste0(md, glue("- **Nitrogen Status**: {guild_result$flags$nitrogen}\n"))
    md <- paste0(md, glue("- **Soil pH**: {guild_result$flags$soil_ph}\n"))
    md <- paste0(md, "\n---\n\n")
  }

  # Detailed Metrics
  md <- paste0(md, "## 📊 Detailed Metrics\n\n")

  md <- paste0(md, "### Universal Indicators\n\n")
  md <- paste0(md, "*Available for all plants*\n\n")
  md <- paste0(md, "| Metric | Score |\n")
  md <- paste0(md, "|--------|-------|\n")

  for (metric in explanation$metrics_display$universal) {
    bar <- render_bar_chart(metric$score)
    md <- paste0(md, glue("| {metric$name} | {bar} |\n"))
  }

  md <- paste0(md, "\n### Bonus Indicators\n\n")
  md <- paste0(md, "*Dependent on available interaction data*\n\n")
  md <- paste0(md, "| Metric | Score |\n")
  md <- paste0(md, "|--------|-------|\n")

  for (metric in explanation$metrics_display$bonus) {
    bar <- render_bar_chart(metric$score)
    md <- paste0(md, glue("| {metric$name} | {bar} |\n"))
  }

  md <- paste0(md, "\n---\n\n")

  # Raw scores (for debugging)
  md <- paste0(md, "## Raw Scores (Technical Details)\n\n")
  md <- paste0(md, "| Metric | Raw Score | Percentile Score | Details |\n")
  md <- paste0(md, "|--------|-----------|------------------|----------|\n")

  for (metric_code in c('m1', 'm2', 'm3', 'm4', 'm5', 'm6', 'm7')) {
    raw_val <- guild_result$raw_scores[[metric_code]]
    norm_val <- guild_result$metrics[[metric_code]]
    details_obj <- guild_result$details[[metric_code]]

    # Format details
    if (!is.null(details_obj) && is.list(details_obj)) {
      details_str <- paste(names(details_obj), sapply(details_obj, function(x) {
        if (is.numeric(x)) round(x, 3) else as.character(x)
      }), sep = "=", collapse = "; ")
    } else {
      details_str <- "-"
    }

    md <- paste0(md, glue("| {metric_code} | {round(raw_val, 4)} | {round(norm_val, 1)} | {details_str} |\n"))
  }

  md <- paste0(md, "\n---\n\n")

  # Footer
  md <- paste0(md, glue("*Report generated: {Sys.time()}*\n"))
  md <- paste0(md, glue("*Calibration: {guild_result$n_plants}-plant, Climate tier: {guild_result$climate_tier}*\n"))

  # Write to file
  writeLines(md, output_path)
  cat(glue("✓ Report saved: {output_path}\n"))

  invisible(md)
}


#' Render score as bar chart
#'
#' @param score Numeric score 0-100
#' @param width Number of characters in bar
#' @return String with bar chart representation
render_bar_chart <- function(score, width = 20) {
  # Each character = 5 points
  filled <- floor(score / 5)
  if (filled > width) filled <- width
  if (filled < 0) filled <- 0

  empty <- width - filled

  bar <- paste0(
    strrep("█", filled),
    strrep("░", empty),
    " ",
    sprintf("%.1f", score)
  )

  return(bar)
}
