R ?= Rscript

# Defaults for Stage 5
EQ_JSON        ?= results/MAG_Run8/mag_equations.json
RECIPE_JSON    ?= results/MAG_Run8/composite_recipe.json
GAM_L_RDS      ?= results/MAG_Run8/sem_pwsem_L_full_model.rds
MAG_INPUT      ?= data/new_traits.csv
MAG_OUTPUT     ?= results/mag_predictions_no_eive.csv

# Blending defaults
MAG_OUTPUT_BLEND ?= results/mag_predictions_blended.csv
PHYLO_NEWICK     ?= data/phylogeny/eive_try_tree.nwk
REF_EIVE         ?= artifacts/model_data_complete_case_with_myco.csv
REF_SPECIES_COL  ?= wfo_accepted_name
TARGET_SPECIES_COL ?= species
ALPHA_PER_AXIS   ?= L=0.25,T=0.25,M=0.25,R=0.25,N=0.25
X_EXP            ?= 2
K_TRUNC          ?= 0

# Stage 6 defaults
PRED_CSV       ?= $(MAG_OUTPUT_BLEND)
RECS_OUT       ?= results/gardening/garden_requirements_no_eive.csv
COPULAS_JSON   ?= results/MAG_Run8/mag_copulas.json
METRICS_DIR    ?= artifacts/stage4_sem_pwsem_run7_pureles
PRESETS        ?= results/gardening/garden_joint_presets_defaults.csv
SUMMARY_CSV    ?= results/gardening/garden_joint_summary.csv
PRESETS_NOR    ?= results/gardening/garden_presets_no_R.csv
SUMMARY_CSV_NOR ?= results/gardening/garden_joint_summary_no_R.csv

.PHONY: mag_predict mag_predict_blended stage6_requirements stage6_joint_default stage6_joint_noR copy_gbif extract_bioclim extract_bioclim_r clean_extract_bioclim clean_extract_bioclim_v2 clean_extract_bioclim_py clean_extract_bioclim_minimal setup_r_env predownload bioclim_first
.PHONY: try_extract_traits
.PHONY: try_merge_enhanced_full try_merge_enhanced_subset

# One-liner: SEM/MAG predictions only (no blending)
mag_predict:
	$(R) src/Stage_5_Apply_Mean_Structure/apply_mean_structure.R \
	  --input_csv $(MAG_INPUT) \
	  --output_csv $(MAG_OUTPUT) \
	  --equations_json $(EQ_JSON) \
	  --composites_json $(RECIPE_JSON) \
	  --gam_L_rds $(GAM_L_RDS)

# One-liner: SEM/MAG + phylogenetic blending (alpha per axis)
mag_predict_blended:
	$(R) src/Stage_5_Apply_Mean_Structure/apply_mean_structure.R \
	  --input_csv $(MAG_INPUT) \
	  --output_csv $(MAG_OUTPUT_BLEND) \
	  --equations_json $(EQ_JSON) \
	  --composites_json $(RECIPE_JSON) \
	  --gam_L_rds $(GAM_L_RDS) \
	  --blend_with_phylo true \
	  --alpha_per_axis $(ALPHA_PER_AXIS) \
	  --phylogeny_newick $(PHYLO_NEWICK) \
	  --reference_eive_csv $(REF_EIVE) \
	  --reference_species_col $(REF_SPECIES_COL) \
	  --target_species_col $(TARGET_SPECIES_COL) \
	  --x $(X_EXP) --k_trunc $(K_TRUNC)

# Turn predictions into gardening requirements (per-axis bins/confidence)
stage6_requirements:
	$(R) src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R \
	  --predictions_csv $(PRED_CSV) \
	  --output_csv $(RECS_OUT) \
	  --bins 0:3.5,3.5:6.5,6.5:10 \
	  --borderline_width 0.5

# Batch joint suitability for default presets
stage6_joint_default:
	$(R) src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R \
	  --predictions_csv $(PRED_CSV) \
	  --copulas_json $(COPULAS_JSON) \
	  --metrics_dir $(METRICS_DIR) \
	  --presets_csv $(PRESETS) \
	  --nsim 20000 \
	  --summary_csv $(SUMMARY_CSV)

# Batch joint suitability for R-excluded presets
stage6_joint_noR:
	$(R) src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R \
	  --predictions_csv $(PRED_CSV) \
	  --copulas_json $(COPULAS_JSON) \
	  --metrics_dir $(METRICS_DIR) \
	  --presets_csv $(PRESETS_NOR) \
	  --nsim 20000 \
	  --summary_csv $(SUMMARY_CSV_NOR)

# Copy GBIF occurrences for model species
copy_gbif:
	@echo "Copying GBIF occurrences for model species..."
	@bash scripts/copy_gbif_occurrences_parallel.sh || { exit_code=$$?; if [ $$exit_code -eq 141 ]; then echo "Note: SIGPIPE error (141) ignored - copy completed successfully"; true; else exit $$exit_code; fi; }

# Extract bioclim values from WorldClim for GBIF occurrences
extract_bioclim: copy_gbif
	@echo "Extracting bioclim values for GBIF occurrences..."
	@python3 scripts/extract_bioclim_pipeline.py

# Alternative: Use R version for bioclim extraction
extract_bioclim_r: copy_gbif
	@echo "Extracting bioclim values using R..."
	@$(R) scripts/extract_bioclim_pipeline.R

# Clean GBIF data and extract bioclim (R version with CoordinateCleaner)
clean_extract_bioclim:
	@if [ ! -d "data/gbif_occurrences_model_species" ] || [ -z "$$(ls -A data/gbif_occurrences_model_species 2>/dev/null)" ]; then \
		echo "GBIF files not found. Running copy_gbif first..."; \
		$(MAKE) copy_gbif; \
	else \
		echo "GBIF files already present in data/gbif_occurrences_model_species"; \
	fi
	@echo "Cleaning GBIF data and extracting bioclim values..."
	@$(R) scripts/clean_gbif_extract_bioclim.R

# Clean GBIF data and extract bioclim (Improved v2 with parallel processing)
clean_extract_bioclim_v2:
	@if [ ! -d "data/gbif_occurrences_model_species" ] || [ -z "$$(ls -A data/gbif_occurrences_model_species 2>/dev/null)" ]; then \
		echo "GBIF files not found. Running copy_gbif first..."; \
		$(MAKE) copy_gbif; \
	else \
		echo "GBIF files already present in data/gbif_occurrences_model_species"; \
	fi
	@echo "Cleaning GBIF data and extracting bioclim values (v2)..."
	@$(R) scripts/clean_gbif_extract_bioclim_v2.R

# Clean GBIF data and extract bioclim (Python version)
clean_extract_bioclim_py:
	@if [ ! -d "data/gbif_occurrences_model_species" ] || [ -z "$$(ls -A data/gbif_occurrences_model_species 2>/dev/null)" ]; then \
		echo "GBIF files not found. Running copy_gbif first..."; \
		$(MAKE) copy_gbif; \
	else \
		echo "GBIF files already present in data/gbif_occurrences_model_species"; \
	fi
	@echo "Cleaning GBIF data and extracting bioclim values (Python)..."
	@python3 scripts/clean_gbif_extract_bioclim.py

# Setup R environment - install required packages
setup_r_env:
	@echo "Setting up R environment and installing packages..."
	@$(R) scripts/setup_r_environment.R

# Pre-download all reference data with aria2
predownload:
	@echo "Pre-downloading reference data with aria2..."
	@bash scripts/predownload_reference_data.sh

# Minimal cleaning pipeline - uses only essential packages
clean_extract_bioclim_minimal:
	@if [ ! -d "data/gbif_occurrences_model_species" ] || [ -z "$$(ls -A data/gbif_occurrences_model_species 2>/dev/null)" ]; then \
		echo "GBIF files not found. Running copy_gbif first..."; \
		$(MAKE) copy_gbif; \
	else \
		echo "GBIF files already present in data/gbif_occurrences_model_species"; \
	fi
	@echo "Running minimal cleaning pipeline (limited dependencies)..."
	@$(R) scripts/clean_gbif_extract_bioclim_minimal.R

# Stage 1: Bioclim-first extraction (duplicates preserved) + species summary + trait merge (>=3)
bioclim_first:
	@echo "Running Stage 1 bioclim-first pipeline (extract -> clean -> summarize -> merge/filter >=3)..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" Rscript src/Stage_1_Data_Extraction/gbif_bioclim/extract_bioclim_then_clean.R
	@echo "Done. Key outputs:"
	@echo "  - data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv"
	@echo "  - data/bioclim_extractions_bioclim_first/summary_stats/species_bioclim_summary.csv"
	@echo "  - artifacts/model_data_bioclim_subset.csv (traits filtered to species with >=3 occurrences)"

# Stage 1: Extract additional TRY traits (leaf thickness, phenology, photosynthesis pathway, frost tolerance)
try_extract_traits:
	@echo "Extracting additional TRY traits (leaf thickness, phenology, photosynthesis, frost tolerance)..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" Rscript src/Stage_1_Data_Extraction/extract_try_traits.R
	@echo "Expected outputs in /home/olier/ellenberg/artifacts/stage1_data_extraction:"
	@ls -lh /home/olier/ellenberg/artifacts/stage1_data_extraction/trait_{46_leaf_thickness,37_leaf_phenology_type,22_photosynthesis_pathway,31_species_tolerance_to_frost}.rds 2>/dev/null || true
	@ls -lh /home/olier/ellenberg/artifacts/stage1_data_extraction/extracted_traits_summary.csv 2>/dev/null || true

# Merge newly extracted TRY traits into model datasets (full and bioclim subset)
try_merge_enhanced_full:
	@echo "Merging enhanced TRY traits into full model dataset..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript src/Stage_2_Data_Processing/assemble_model_data_with_enhanced_traits.R \
	    --existing_model=artifacts/model_data_complete_case_with_myco.csv \
	    --out_full=artifacts/model_data_enhanced_traits_full.csv \
	    --out_complete=artifacts/model_data_enhanced_traits_complete.csv
	@echo "Outputs:"
	@ls -lh artifacts/model_data_enhanced_traits_full.csv artifacts/model_data_enhanced_traits_complete.csv

try_merge_enhanced_subset:
	@echo "Merging enhanced TRY traits into bioclim subset (expanded600)..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript src/Stage_2_Data_Processing/assemble_model_data_with_enhanced_traits.R \
	    --existing_model=artifacts/model_data_bioclim_subset.csv \
	    --out_full=artifacts/model_data_bioclim_subset_enhanced.csv \
	    --out_complete=artifacts/model_data_bioclim_subset_enhanced_complete.csv
	@echo "Outputs:"
	@ls -lh artifacts/model_data_bioclim_subset_enhanced.csv artifacts/model_data_bioclim_subset_enhanced_complete.csv

# ----------------------------------------------------------------------------
# SoilGrids extraction and integration
# ----------------------------------------------------------------------------

.PHONY: soil_extract soil_aggregate soil_merge soil_pipeline

# Paths (override on command line if needed)
SOIL_OCC_FILE ?= /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654_with_soil.csv
SOIL_SUMMARY  ?= /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary.csv
BIOCLIM_SUMMARY ?= /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_bioclim_summary.csv
TRAIT_CSV ?= artifacts/model_data_bioclim_subset.csv
WFO_BACKBONE ?= /home/olier/ellenberg/data/classification.csv
MERGED_SOIL_OUT ?= artifacts/model_data_trait_bioclim_soil_merged_wfo.csv

# Conservative GDAL tuning for VRT reading
GDAL_CACHE ?= 1024
VRT_THREADS ?= ALL_CPUS
VRT_POOL ?= 450

# Step 1: Extract SoilGrids for unique coords, merge back to all occurrences (duplicates preserved)
soil_extract:
	@echo "[Soil] Extracting SoilGrids for GBIF occurrences (conservative settings)..."
	@GDAL_CACHEMAX=$(GDAL_CACHE) VRT_NUM_THREADS=$(VRT_THREADS) GDAL_MAX_DATASET_POOL_SIZE=$(VRT_POOL) \
	  R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript scripts/extract_soilgrids_efficient.R
	@echo "[Soil] Output: $(SOIL_OCC_FILE)"

	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" Rscript scripts/print_csv_summary.R --input $(SOIL_OCC_FILE) --type occ_soil || true

# Step 2: Aggregate to species-level means/sds/n_valid, flagging has_sufficient_data (>=3)
soil_aggregate:
	@echo "[Soil] Aggregating occurrence-level soil to species-level summary..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript scripts/aggregate_soilgrids_species.R \
	    --input $(SOIL_OCC_FILE) \
	    --species_col species_clean \
	    --min_occ 3 \
	    --output $(SOIL_SUMMARY)
	@echo "[Soil] Output: $(SOIL_SUMMARY)"

	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" Rscript scripts/print_csv_summary.R --input $(SOIL_SUMMARY) --type soil_summary || true

# Step 3: Merge traits + bioclim + soil using WFO normalization
soil_merge:
	@echo "[Soil] Merging trait + bioclim + soil with WFO alignment..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript scripts/merge_trait_bioclim_soil_wfo.R \
	    --trait_csv $(TRAIT_CSV) \
	    --bioclim_summary $(BIOCLIM_SUMMARY) \
	    --soil_summary $(SOIL_SUMMARY) \
	    --wfo_backbone $(WFO_BACKBONE) \
	    --output $(MERGED_SOIL_OUT)
	@echo "[Soil] Output: $(MERGED_SOIL_OUT)"

	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" Rscript scripts/print_csv_summary.R --input $(MERGED_SOIL_OUT) --type merged || true

# One-shot pipeline: extract -> aggregate -> merge
soil_pipeline: soil_extract soil_aggregate soil_merge
	@echo "[Soil] Completed soil pipeline (extract -> aggregate -> merge)."
