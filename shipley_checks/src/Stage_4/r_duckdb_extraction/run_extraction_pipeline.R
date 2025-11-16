#!/usr/bin/env Rscript

cat("================================================================================\n")
cat("PHASE 0: STAGE 4 DATA EXTRACTION PIPELINE (R DuckDB → Rust-Ready Parquets)\n")
cat("================================================================================\n\n")

cat("Purpose: Extract all ecological interaction networks for 11,711 plants\n")
cat("Output: Rust-ready parquet files (DuckDB COPY TO, no R metadata)\n")
cat("Target: guild_scorer_rust can read all files directly (no conversion)\n\n")

script_dir <- "shipley_checks/src/Stage_4/r_duckdb_extraction"

start_time <- Sys.time()

# ============================================================================
# Step 0: Extract known herbivores from full GloBI
# ============================================================================
cat("Step 1/6: Extracting known herbivores from full GloBI...\n")
cat("--------------------------------------------------------------------------\n")
tryCatch({
  source(file.path(script_dir, "00_extract_known_herbivores.R"))
  cat("✓ Script 0 completed\n\n")
}, error = function(e) {
  cat("✗ Script 0 FAILED:", conditionMessage(e), "\n\n")
  quit(status = 1)
})

# ============================================================================
# Step 1: Match herbivores to 11,711 plants
# ============================================================================
cat("Step 2/6: Matching herbivores to 11,711 plants...\n")
cat("--------------------------------------------------------------------------\n")
tryCatch({
  source(file.path(script_dir, "01_match_herbivores_to_plants.R"))
  cat("✓ Script 1 completed\n\n")
}, error = function(e) {
  cat("✗ Script 1 FAILED:", conditionMessage(e), "\n\n")
  quit(status = 1)
})

# ============================================================================
# Step 2: Extract organism profiles (pollinators, herbivores, predators, fungivores)
# ============================================================================
cat("Step 3/6: Extracting organism profiles...\n")
cat("--------------------------------------------------------------------------\n")
tryCatch({
  source(file.path(script_dir, "02_extract_organism_profiles.R"))
  cat("✓ Script 2 completed\n\n")
}, error = function(e) {
  cat("✗ Script 2 FAILED:", conditionMessage(e), "\n\n")
  quit(status = 1)
})

# ============================================================================
# Step 3: Extract fungal guilds (FungalTraits + FunGuild hybrid)
# ============================================================================
cat("Step 4/6: Extracting fungal guilds (FungalTraits + FunGuild hybrid)...\n")
cat("--------------------------------------------------------------------------\n")
tryCatch({
  source(file.path(script_dir, "03_extract_fungal_guilds_hybrid.R"))
  cat("✓ Script 3 completed\n\n")
}, error = function(e) {
  cat("✗ Script 3 FAILED:", conditionMessage(e), "\n\n")
  quit(status = 1)
})

# ============================================================================
# Step 4: Build multitrophic networks (predator, antagonist)
# ============================================================================
cat("Step 5/6: Building multitrophic networks...\n")
cat("--------------------------------------------------------------------------\n")
tryCatch({
  source(file.path(script_dir, "04_build_multitrophic_network.R"))
  cat("✓ Script 4 completed\n\n")
}, error = function(e) {
  cat("✗ Script 4 FAILED:", conditionMessage(e), "\n\n")
  quit(status = 1)
})

# ============================================================================
# Step 5: Extract insect-fungal parasite relationships
# ============================================================================
cat("Step 6/6: Extracting insect-fungal parasite relationships...\n")
cat("--------------------------------------------------------------------------\n")
tryCatch({
  source(file.path(script_dir, "05_extract_insect_fungal_parasites.R"))
  cat("✓ Script 5 completed\n\n")
}, error = function(e) {
  cat("✗ Script 5 FAILED:", conditionMessage(e), "\n\n")
  quit(status = 1)
})

end_time <- Sys.time()
extraction_time <- difftime(end_time, start_time, units = "secs")

cat("================================================================================\n")
cat(sprintf("EXTRACTION COMPLETE (%.1f seconds)\n", as.numeric(extraction_time)))
cat("================================================================================\n\n")

# ============================================================================
# Step 6: Copy to guild_scorer_rust naming convention
# ============================================================================
cat("Step 6.5/7: Creating guild_scorer_rust compatible file names...\n")
cat("--------------------------------------------------------------------------\n")

# Guild scorer expects *_pure_rust.parquet naming
# Copy _11711.parquet → _pure_rust.parquet for backward compatibility

file.copy(
  "shipley_checks/validation/organism_profiles_11711.parquet",
  "shipley_checks/validation/organism_profiles_pure_rust.parquet",
  overwrite = TRUE
)

file.copy(
  "shipley_checks/validation/fungal_guilds_hybrid_11711.parquet",
  "shipley_checks/validation/fungal_guilds_pure_rust.parquet",
  overwrite = TRUE
)

file.copy(
  "shipley_checks/validation/herbivore_predators_11711.parquet",
  "shipley_checks/validation/herbivore_predators_pure_rust.parquet",
  overwrite = TRUE
)

file.copy(
  "shipley_checks/validation/pathogen_antagonists_11711.parquet",
  "shipley_checks/validation/pathogen_antagonists_pure_rust.parquet",
  overwrite = TRUE
)

file.copy(
  "shipley_checks/validation/insect_fungal_parasites_11711.parquet",
  "shipley_checks/validation/insect_fungal_parasites_pure_rust.parquet",
  overwrite = TRUE
)

cat("✓ Created guild_scorer_rust compatible file names\n")
cat("  - organism_profiles_pure_rust.parquet\n")
cat("  - fungal_guilds_pure_rust.parquet\n")
cat("  - herbivore_predators_pure_rust.parquet\n")
cat("  - pathogen_antagonists_pure_rust.parquet\n")
cat("  - insect_fungal_parasites_pure_rust.parquet\n\n")

# ============================================================================
# Step 7: Verify all outputs
# ============================================================================
cat("Step 7/7: Verifying outputs (data integrity & completeness)...\n")
cat("--------------------------------------------------------------------------\n")

verification_script <- file.path(script_dir, "verify_extraction_outputs.py")
python_path <- "/home/olier/miniconda3/envs/AI/bin/python"

result <- system2(
  python_path,
  args = verification_script,
  stdout = TRUE,
  stderr = TRUE
)

# Print verification output
cat(paste(result, collapse = "\n"))
cat("\n")

# Check exit code
exit_code <- attr(result, "status")
if (!is.null(exit_code) && exit_code != 0) {
  cat("\n")
  cat("================================================================================\n")
  cat("✗ PHASE 0 VERIFICATION FAILED\n")
  cat("================================================================================\n")
  quit(status = 1)
}

total_time <- difftime(Sys.time(), start_time, units = "secs")

cat("\n")
cat("================================================================================\n")
cat("✓ PHASE 0 COMPLETE: ALL RUST-READY PARQUETS VERIFIED\n")
cat("================================================================================\n\n")

cat(sprintf("Total pipeline time: %.1f seconds\n\n", as.numeric(total_time)))

cat("Outputs (shipley_checks/validation/):\n")
cat("  1. known_herbivore_insects.parquet       - 14K+ herbivore species\n")
cat("  2. matched_herbivores_per_plant.parquet  - 3K+ plants with herbivores\n")
cat("  3. organism_profiles_11711.parquet       - 11,711 plants × organisms\n")
cat("  4. fungal_guilds_hybrid_11711.parquet    - 11,711 plants × fungi\n")
cat("  5. herbivore_predators_11711.parquet     - Herbivore → predator network\n")
cat("  6. pathogen_antagonists_11711.parquet    - Pathogen → antagonist network\n")
cat("  7. insect_fungal_parasites_11711.parquet - Insect → parasite network\n\n")

cat("All parquets:\n")
cat("  ✓ DuckDB COPY TO format (no R metadata)\n")
cat("  ✓ Polars-compatible (Rust-ready)\n")
cat("  ✓ Data integrity validated\n")
cat("  ✓ Ready for guild_scorer_rust\n\n")

cat("To run individual scripts:\n")
cat("  Rscript shipley_checks/src/Stage_4/r_duckdb_extraction/00_extract_known_herbivores.R\n")
cat("  Rscript shipley_checks/src/Stage_4/r_duckdb_extraction/01_match_herbivores_to_plants.R\n")
cat("  # ... etc\n\n")

cat("To verify outputs:\n")
cat("  python shipley_checks/src/Stage_4/r_duckdb_extraction/verify_extraction_outputs.py\n\n")
