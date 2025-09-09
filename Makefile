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

.PHONY: mag_predict mag_predict_blended stage6_requirements stage6_joint_default stage6_joint_noR copy_gbif extract_bioclim extract_bioclim_r clean_extract_bioclim clean_extract_bioclim_v2 clean_extract_bioclim_py clean_extract_bioclim_minimal setup_r_env predownload

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

