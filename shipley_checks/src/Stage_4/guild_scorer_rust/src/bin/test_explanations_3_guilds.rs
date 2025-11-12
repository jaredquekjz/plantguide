use guild_scorer_rust::{GuildScorer, ExplanationGenerator, MarkdownFormatter, JsonFormatter, HtmlFormatter};
use std::fs;
use std::time::Instant;

fn main() -> anyhow::Result<()> {
    println!("=================================================================");
    println!("GUILD EXPLANATION ENGINE TEST (Rust)");
    println!("=================================================================\n");

    // Initialize scorer
    let scorer = GuildScorer::new("7plant", "tier_3_humid_temperate")?;

    // Test guilds (from Stage_4_Dual_Verification_Pipeline.md)
    let guilds = vec![
        (
            "Forest Garden",
            vec![
                "wfo-0000832453".to_string(),
                "wfo-0000649136".to_string(),
                "wfo-0000642673".to_string(),
                "wfo-0000984977".to_string(),
                "wfo-0000241769".to_string(),
                "wfo-0000092746".to_string(),
                "wfo-0000690499".to_string(),
            ],
            90.467710,
        ),
        (
            "Competitive Clash",
            vec![
                "wfo-0000757278".to_string(),
                "wfo-0000944034".to_string(),
                "wfo-0000186915".to_string(),
                "wfo-0000421791".to_string(),
                "wfo-0000418518".to_string(),
                "wfo-0000841021".to_string(),
                "wfo-0000394258".to_string(),
            ],
            55.441621,
        ),
        (
            "Stress-Tolerant",
            vec![
                "wfo-0000721951".to_string(),
                "wfo-0000955348".to_string(),
                "wfo-0000901050".to_string(),
                "wfo-0000956222".to_string(),
                "wfo-0000777518".to_string(),
                "wfo-0000349035".to_string(),
                "wfo-0000209726".to_string(),
            ],
            45.442341,
        ),
    ];

    let start_time = Instant::now();

    for (guild_name, plant_ids, expected_score) in &guilds {
        println!("\n----------------------------------------------------------------------");
        println!("GUILD: {}", guild_name);
        println!("----------------------------------------------------------------------");

        let guild_start = Instant::now();

        // Score guild with explanation fragments
        let (guild_score, fragments, guild_plants, m5_result, fungi_df) = scorer.score_guild_with_explanation_parallel(plant_ids)?;

        let scoring_time = guild_start.elapsed();

        // Generate complete explanation
        let explanation = ExplanationGenerator::generate(
            &guild_score,
            &guild_plants,
            "tier_3_humid_temperate",
            fragments,
            &m5_result,
            &fungi_df,
        )?;

        let generation_time = guild_start.elapsed() - scoring_time;

        // Format to all 3 formats
        let format_start = Instant::now();

        let markdown = MarkdownFormatter::format(&explanation);
        let markdown_time = format_start.elapsed();

        let json = JsonFormatter::format(&explanation)?;
        let json_time = format_start.elapsed() - markdown_time;

        let html = HtmlFormatter::format(&explanation);
        let html_time = format_start.elapsed() - markdown_time - json_time;

        let total_time = guild_start.elapsed();

        // Write outputs
        let safe_name = guild_name.replace(" ", "_").to_lowercase();
        let output_dir = "shipley_checks/reports/explanations";

        fs::write(
            format!("{}/rust_explanation_{}.md", output_dir, safe_name),
            markdown,
        )?;
        fs::write(
            format!("{}/rust_explanation_{}.json", output_dir, safe_name),
            json,
        )?;
        fs::write(
            format!("{}/rust_explanation_{}.html", output_dir, safe_name),
            html,
        )?;

        println!("\nScores:");
        println!("  Overall:  {:.6} (expected: {:.6})", guild_score.overall_score, expected_score);
        let diff = (guild_score.overall_score - expected_score).abs();
        let status = if diff < 0.0001 { "✅ PERFECT" } else { "⚠️ DIFF" };
        println!("  Difference: {:.6} - {}", diff, status);
        println!("\n  M1 (Pest Independence): {:.2}", guild_score.metrics[0]);
        println!("  M2 (Growth Compat):     {:.2}", guild_score.metrics[1]);
        println!("  M3 (Insect Control):    {:.2}", guild_score.metrics[2]);
        println!("  M4 (Disease Suppress):  {:.2}", guild_score.metrics[3]);
        println!("  M5 (Beneficial Fungi):  {:.2}", guild_score.metrics[4]);
        println!("  M6 (Structural Div):    {:.2}", guild_score.metrics[5]);
        println!("  M7 (Pollinator Supp):   {:.2}", guild_score.metrics[6]);

        println!("\nExplanation Summary:");
        println!("  Rating: {} {}", explanation.overall.stars, explanation.overall.label);
        println!("  Benefits: {}", explanation.benefits.len());
        println!("  Warnings: {}", explanation.warnings.len());
        println!("  Risks:    {}", explanation.risks.len());

        println!("\nPerformance:");
        println!("  Scoring + fragments:  {:>8.3} ms", scoring_time.as_secs_f64() * 1000.0);
        println!("  Explanation gen:      {:>8.3} ms", generation_time.as_secs_f64() * 1000.0);
        println!("  Markdown format:      {:>8.3} ms", markdown_time.as_secs_f64() * 1000.0);
        println!("  JSON format:          {:>8.3} ms", json_time.as_secs_f64() * 1000.0);
        println!("  HTML format:          {:>8.3} ms", html_time.as_secs_f64() * 1000.0);
        println!("  Total:                {:>8.3} ms", total_time.as_secs_f64() * 1000.0);

        println!("\nOutputs written:");
        println!("  {}/rust_explanation_{}.md", output_dir, safe_name);
        println!("  {}/rust_explanation_{}.json", output_dir, safe_name);
        println!("  {}/rust_explanation_{}.html", output_dir, safe_name);
    }

    let total_time = start_time.elapsed();

    println!("\n======================================================================");
    println!("SUMMARY");
    println!("======================================================================");
    println!("Total time (3 guilds × 3 formats): {:.3} ms", total_time.as_secs_f64() * 1000.0);
    println!("Average per guild: {:.3} ms", total_time.as_secs_f64() * 1000.0 / 3.0);
    println!("\n✅ All explanations generated successfully!");
    println!("======================================================================\n");

    Ok(())
}
