#!/usr/bin/env Rscript
# Regenerate explanation reports with unified categorization

suppressPackageStartupMessages({
  library(dplyr)
})

# Source guild scorer and export modules
source("shipley_checks/src/Stage_4/guild_scorer_v3_modular.R")
source("shipley_checks/src/Stage_4/export_explanation_md.R")

cat("=== Regenerating Explanation Reports with Unified Categorization ===\n\n")

# Initialize scorer
scorer <- GuildScorerV3Modular$new(
  calibration_type = "7plant",
  climate_tier = "tier_3_humid_temperate"
)

# Test guilds
guilds <- list(
  list(
    name = "forest_garden",
    display_name = "Forest Garden",
    ids = c("wfo-0000832453", "wfo-0000649136", "wfo-0000642673",
            "wfo-0000984977", "wfo-0000241769", "wfo-0000092746", "wfo-0000690499")
  ),
  list(
    name = "competitive_clash",
    display_name = "Competitive Clash",
    ids = c("wfo-0000757278", "wfo-0000944034", "wfo-0000186915",
            "wfo-0000421791", "wfo-0000418518", "wfo-0000841021", "wfo-0000394258")
  ),
  list(
    name = "stress-tolerant",
    display_name = "Stress-Tolerant",
    ids = c("wfo-0000721951", "wfo-0000955348", "wfo-0000901050",
            "wfo-0000956222", "wfo-0000777518", "wfo-0000349035", "wfo-0000209726")
  )
)

# Generate reports
for (guild_info in guilds) {
  cat(sprintf("Generating %s...\n", guild_info$display_name))

  # Score guild
  result <- scorer$score_guild(guild_info$ids)

  # Export to markdown
  output_path <- sprintf("shipley_checks/stage4/reports/r_explanation_%s.md",
                        guild_info$name)
  export_guild_report_md(result, output_path, guild_info$display_name)

  cat(sprintf("  → %s\n", output_path))
}

cat("\n✓ All reports regenerated with unified categorization\n")
cat("✓ Herbivore categories now shown in pest tables\n")
