R ?= Rscript
BHPMF_R ?= Rscript

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
.PHONY: cleaned_summary_from_bioclim_first
.PHONY: try_extract_traits
.PHONY: try_merge_enhanced_full try_merge_enhanced_subset
.PHONY: phylotraits_impute phylotraits_run
.PHONY: phylotraits_impute_categorical phylotraits_impute_all phylotraits_run_cat
.PHONY: install_bhpmf
.PHONY: install_bhpmf_patched
.PHONY: hybrid_tmux

# ----------------------------------------------------------------------------
# PDF -> MMD conversion (Mathpix API)
# ----------------------------------------------------------------------------

.PHONY: mmd mmd-papers

MATHPIX_CONVERT ?= src/Stage_1_Data_Extraction/convert_to_mmd.py
JOBS ?= 2

# Convert a single PDF to MMD using Mathpix.
# Usage: make mmd FILE='papers/Foo.pdf' [OUT='papers/mmd/Foo.mmd']
mmd:
	@if [ -z "$(FILE)" ]; then echo "Usage: make mmd FILE='papers/Foo.pdf' [OUT='papers/mmd/Foo.mmd']"; exit 1; fi
	@OUT="$(OUT)"; \
	if [ -z "$$OUT" ]; then \
	  base=$$(basename "$(FILE)"); stem=$${base%.pdf}; \
	  if [ "$$PWD" != "/home/olier/ellenberg" ]; then echo "[mmd] Please run from repo root so .env is loaded."; fi; \
	  if [ "$$(dirname "$(FILE)")" = "papers" ]; then \
	    mkdir -p papers/mmd; OUT="papers/mmd/$${stem}.mmd"; \
	  else \
	    OUT="$$(dirname "$(FILE)")/$${stem}.mmd"; \
	  fi; \
	fi; \
	echo "[mmd] Converting '$(FILE)' -> '$$OUT'"; \
	python3 "$(MATHPIX_CONVERT)" "$(FILE)" "$$OUT"

# Convert all PDFs in papers/ (non-recursive) to papers/mmd/*.mmd in parallel.
# Usage: make mmd-papers [JOBS=2]
mmd-papers:
	@mkdir -p papers/mmd
	@J=$(JOBS); \
	echo "[mmd] Converting all PDFs in papers/ to papers/mmd/ with $$J parallel jobs"; \
	find papers -maxdepth 1 -type f -name '*.pdf' -print0 | xargs -0 -I{} -P $$J bash -lc '
	  f="{}"; base=$$(basename "$$f"); stem=$${base%.pdf}; out="papers/mmd/$${stem}.mmd"; \
	  echo "[mmd] $$f -> $$out"; python3 "$(MATHPIX_CONVERT)" "$$f" "$$out"'

# ----------------------------------------------------------------------------
# Stage 1 Discovery (RF + XGBoost, no_pk and pk) — one‑shot launcher
# ----------------------------------------------------------------------------

.PHONY: stage1_discovery stage1_discovery_5axes

# Defaults for discovery runs
DISC_LABEL ?= phylotraits_cleanedAI_discovery_gpu
DISC_AXES  ?= T,M,L,N                  # set to T,M,L,N,R for all five
DISC_FOLDS ?= 10
DISC_X_EXP ?= 2
DISC_KTRUNC ?= 0
DISC_XGB_GPU ?= true

stage1_discovery:
	@echo "[discovery] Launching Stage 1 (RF + XGBoost, GPU=$(DISC_XGB_GPU)) for axes: $(DISC_AXES)"
	@bash scripts/run_stage1_discovery_tmux.sh \
	  --label $(DISC_LABEL) \
	  --trait_csv $(TRAIT_CSV) \
	  --bioclim_summary $(BIOCLIM_SUMMARY_OUT_AIMONTH) \
	  --axes $(DISC_AXES) \
	  --folds $(DISC_FOLDS) \
	  --x_exp $(DISC_X_EXP) \
	  --k_trunc $(DISC_KTRUNC) \
	  --xgb_gpu $(DISC_XGB_GPU)

# Convenience: five axes (T,M,L,N,R)
stage1_discovery_5axes:
	$(MAKE) -f $(lastword $(MAKEFILE_LIST)) stage1_discovery DISC_AXES=T,M,L,N,R

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
	@echo "[cleaned] Running canonical cleaned pipeline (unique-coordinate summary): noDups"; \
	R_LIBS_USER="/home/olier/ellenberg/.Rlib" Rscript src/Stage_1_Data_Extraction/gbif_bioclim/clean_gbif_extract_bioclim_noDups.R

# Clean GBIF data and extract bioclim (Improved v2 with parallel processing)
clean_extract_bioclim_v2:
	@if [ ! -d "data/gbif_occurrences_model_species" ] || [ -z "$$(ls -A data/gbif_occurrences_model_species 2>/dev/null)" ]; then \
		echo "GBIF files not found. Running copy_gbif first..."; \
		$(MAKE) copy_gbif; \
	else \
		echo "GBIF files already present in data/gbif_occurrences_model_species"; \
	fi
	@echo "Cleaning GBIF data and extracting bioclim values (v2)..."
	@echo "[DEPRECATED] v2 (noSea) is now an alias of noDups (unique-coordinate summary)."; \
	R_LIBS_USER="/home/olier/ellenberg/.Rlib" Rscript src/Stage_1_Data_Extraction/gbif_bioclim/clean_gbif_extract_bioclim_noDups.R

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

# Quick rebuild of CLEANED species summary from bioclim-first occurrences
cleaned_summary_from_bioclim_first:
	@echo "[cleaned] Rebuilding cleaned species summary from bioclim-first occurrences (unique-coordinate means/SDs)"
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript src/Stage_1_Data_Extraction/gbif_bioclim/make_cleaned_summary_from_bioclim_first.R \
	    --occurrences_csv /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv \
	    --output_summary /home/olier/ellenberg/data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv \
	    --min_occ 3

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

.PHONY: soil_extract soil_aggregate soil_merge soil_pipeline soil_extract_global soil_pipeline_global

# Paths (override on command line if needed)
SOIL_INPUT_CSV ?= /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654.csv
SOIL_OCC_FILE ?= /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654_with_soil.csv
SOIL_SUMMARY  ?= /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary.csv
BIOCLIM_SUMMARY ?= /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_bioclim_summary.csv
TRAIT_CSV ?= artifacts/model_data_bioclim_subset.csv
WFO_BACKBONE ?= /home/olier/ellenberg/data/classification.csv
MERGED_SOIL_OUT ?= artifacts/model_data_trait_bioclim_soil_merged_wfo.csv

# Global 250m extractor defaults
SOIL_GLOBAL_INPUT_CSV ?= /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv
SOIL_GLOBAL_OCC_FILE ?= /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_with_soilglobal.csv
SOIL_GLOBAL_SUMMARY ?= /home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_summary_global.csv
MERGED_SOIL_OUT_GLOBAL ?= artifacts/model_data_trait_bioclim_soil_merged_wfo_global.csv

# Conservative GDAL tuning for VRT reading
GDAL_CACHE ?= 1024
VRT_THREADS ?= ALL_CPUS
VRT_POOL ?= 450

# Step 1: Extract SoilGrids for unique coords, merge back to all occurrences (duplicates preserved)
SOIL_ALL_PROPS := phh2o,soc,clay,sand,cec,nitrogen,bdod
PROPERTIES ?=

soil_extract:
	@echo "[Soil] Preflight: ensuring VRT-referenced tiles exist locally..."
	@PROPS_TO_FETCH=$$( [ -n "$(PROPERTIES)" ] && echo "$(PROPERTIES)" || echo "$(SOIL_ALL_PROPS)" ); \
	  bash scripts/preflight_fetch_soilgrids_tiles.sh --properties "$$PROPS_TO_FETCH"
	@echo "[Soil] Extracting SoilGrids for GBIF occurrences (conservative settings)..."
	@OUT=$$( if [ -n "$(PROPERTIES)" ]; then suf=$$(echo "$(PROPERTIES)" | tr ',' '_'); echo "$(SOIL_INPUT_CSV)" | sed -E 's/\.csv$$/_with_'"$$suf"'\.csv/'; else echo "$(SOIL_OCC_FILE)"; fi ); \
	  echo "[Soil] OUT=$$OUT"; \
	  GDAL_CACHEMAX=$(GDAL_CACHE) VRT_NUM_THREADS=$(VRT_THREADS) GDAL_MAX_DATASET_POOL_SIZE=$(VRT_POOL) \
	  R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  bash -lc 'ARGS="--input $(SOIL_INPUT_CSV) --output '"$$OUT"'"; [ -n "$(PROPERTIES)" ] && ARGS="$$ARGS --properties $(PROPERTIES)"; \
	    Rscript scripts/extract_soilgrids_efficient.R $$ARGS'; \
	  echo "[Soil] Output: $$OUT"; \
	  R_LIBS_USER="/home/olier/ellenberg/.Rlib" Rscript scripts/print_csv_summary.R --input "$$OUT" --type occ_soil || true

# Step 1 (alternative): Extract using local global 250m GeoTIFFs
soil_extract_global:
	@echo "[Soil-Global] Extracting SoilGrids (global 250m) for GBIF occurrences..."
	@OUT=$$( if [ -n "$(PROPERTIES)" ]; then suf=$$(echo "$(PROPERTIES)" | tr ',' '_'); echo "$(SOIL_GLOBAL_INPUT_CSV)" | sed -E 's/\.csv$$/_with_soilglobal_'"$$suf"'\.csv/'; else echo "$(SOIL_GLOBAL_OCC_FILE)"; fi ); \
	  echo "[Soil-Global] OUT=$$OUT"; \
	  ARGS="--input $(SOIL_GLOBAL_INPUT_CSV) --output $$OUT"; \
	  [ -n "$(PROPERTIES)" ] && ARGS="$$ARGS --properties $(PROPERTIES)"; \
	  [ -n "$(CHUNK)" ] && ARGS="$$ARGS --chunk $(CHUNK)"; \
	  R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript src/Stage_1_Data_Extraction/extract_soilgrids_global_250m.R $$ARGS; \
	  echo "[Soil-Global] Output: $$OUT"; \
	  R_LIBS_USER="/home/olier/ellenberg/.Rlib" Rscript scripts/print_csv_summary.R --input "$$OUT" --type occ_soil || true

# Step 2: Aggregate to species-level means/sds/n_valid, flagging has_sufficient_data (>=3)
soil_aggregate:
	@echo "[Soil] Aggregating occurrence-level soil to species-level summary..."
	@IN=$$( \
	  if [ -n "$(PROPERTIES)" ]; then \
	    suf=$$(echo "$(PROPERTIES)" | tr ',' '_'); \
	    echo "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654.csv" | sed -E 's/\.csv$$/_with_'"$$suf"'\.csv/'; \
	  else \
	    echo "$(SOIL_OCC_FILE)"; \
	  fi ); \
	  OUT=$$( \
	  if [ -n "$(PROPERTIES)" ]; then \
	    suf=$$(echo "$(PROPERTIES)" | tr ',' '_'); \
	    echo "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_""$$suf""_summary.csv"; \
	  else \
	    echo "$(SOIL_SUMMARY)"; \
	  fi ); \
	  echo "[Soil] IN=$$IN"; echo "[Soil] OUT=$$OUT"; \
	  R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript scripts/aggregate_soilgrids_species.R \
	    --input "$$IN" \
	    --species_col species_clean \
	    --min_occ 3 \
	    --output "$$OUT"
	@echo "[Soil] Output written."

	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" Rscript scripts/print_csv_summary.R --input "$$OUT" --type soil_summary || true

# Step 3: Merge traits + bioclim + soil using WFO normalization
soil_merge:
	@echo "[Soil] Merging trait + bioclim + soil with WFO alignment..."
	@SSUM=$$( if [ -n "$(PROPERTIES)" ]; then \
	    suf=$$(echo "$(PROPERTIES)" | tr ',' '_'); \
	    echo "/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/summary_stats/species_soil_""$$suf""_summary.csv"; \
	  else \
	    echo "$(SOIL_SUMMARY)"; \
	  fi ); \
	  OUT=$$( if [ -n "$(PROPERTIES)" ]; then \
	    suf=$$(echo "$(PROPERTIES)" | tr ',' '_'); \
	    echo "artifacts/model_data_trait_bioclim_soil_merged_wfo_""$$suf"".csv"; \
	  else \
	    echo "$(MERGED_SOIL_OUT)"; \
	  fi ); \
	  echo "[Soil] SOIL_SUMMARY=$$SSUM"; echo "[Soil] OUT=$$OUT"; \
	  R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript scripts/merge_trait_bioclim_soil_wfo.R \
	    --trait_csv $(TRAIT_CSV) \
	    --bioclim_summary $(BIOCLIM_SUMMARY) \
	    --soil_summary "$$SSUM" \
	    --wfo_backbone $(WFO_BACKBONE) \
	    --output "$$OUT"; \
	  echo "[Soil] Output: $$OUT"; \
	  R_LIBS_USER="/home/olier/ellenberg/.Rlib" Rscript scripts/print_csv_summary.R --input "$$OUT" --type merged || true

# One-shot pipeline: extract -> aggregate -> merge
soil_pipeline: soil_extract soil_aggregate soil_merge
	@echo "[Soil] Completed soil pipeline (extract -> aggregate -> merge)."

# One-shot pipeline using global GeoTIFFs
soil_pipeline_global:
	@echo "[Soil-Global] Pipeline start..."
	@OUT=$$( if [ -n "$(PROPERTIES)" ]; then suf=$$(echo "$(PROPERTIES)" | tr ',' '_'); echo "$(SOIL_GLOBAL_INPUT_CSV)" | sed -E 's/\.csv$$/_with_soilglobal_'"$$suf"'\.csv/'; else echo "$(SOIL_GLOBAL_OCC_FILE)"; fi ); \
	  make soil_extract_global PROPERTIES="$(PROPERTIES)" CHUNK="$(CHUNK)" SOIL_GLOBAL_INPUT_CSV="$(SOIL_GLOBAL_INPUT_CSV)" SOIL_GLOBAL_OCC_FILE="$$OUT"; \
	  make soil_aggregate PROPERTIES= SOIL_OCC_FILE="$$OUT" SOIL_SUMMARY="$(SOIL_GLOBAL_SUMMARY)"; \
	  make soil_merge PROPERTIES= SOIL_SUMMARY="$(SOIL_GLOBAL_SUMMARY)" MERGED_SOIL_OUT="$(MERGED_SOIL_OUT_GLOBAL)"; \
	  echo "[Soil-Global] Pipeline complete."

# Optional preflight: ensure all VRT-referenced tiles exist locally
.PHONY: soil_preflight
SOIL_PROPS ?= nitrogen
soil_preflight:
	@echo "[Soil] Preflight: fetching any missing tiles for properties=$(SOIL_PROPS) ..."
	@bash scripts/preflight_fetch_soilgrids_tiles.sh --properties $(SOIL_PROPS)
	@echo "[Soil] Preflight complete. See artifacts/logs/preflight_fetch_*.log"

# ----------------------------------------------------------------------------
# Phylotraits: BHPMF imputation for enhanced traits + run hybrid
# ----------------------------------------------------------------------------

# Default paths
IMPUTE_IN ?= artifacts/model_data_bioclim_subset_enhanced.csv
IMPUTE_OUT ?= artifacts/model_data_bioclim_subset_enhanced_imputed.csv
IMPUTE_DIAG ?= artifacts/phylotraits_impute
IMPUTE_TMP ?= $(IMPUTE_DIAG)/tmp_bhpmf
IMPUTE_TRAITS ?= Leaf_thickness_mm,Frost_tolerance_score,Leaf_N_per_area
# Make used/prediction levels configurable (defaults preserve prior behavior)
IMPUTE_USED_LEVELS ?= 2
IMPUTE_PRED_LEVEL ?= 3

phylotraits_impute:
	@echo "[Phylotraits] Imputing enhanced traits with BHPMF..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  $(BHPMF_R) src/Stage_2_Data_Processing/phylo_impute_traits_bhpmf.R \
	    --input_csv=$(IMPUTE_IN) \
	    --out_csv=$(IMPUTE_OUT) \
	    --diag_dir=$(IMPUTE_DIAG) \
	    --tmp_dir=$(IMPUTE_TMP) \
	    --traits_to_impute=$(IMPUTE_TRAITS) \
	    --add_env_covars=$(IMPUTE_ADD_ENV) \
	    --env_csv=$(IMPUTE_ENV_CSV) \
	    --env_cols_regex=$(IMPUTE_ENV_REGEX) \
	    --env_center_scale=$(IMPUTE_ENV_CENTER) \
    --used_levels=$(IMPUTE_USED_LEVELS) --prediction_level=$(IMPUTE_PRED_LEVEL) \
	    --num_samples=1000 --burn=100 --gaps=2 --num_latent=10 --tuning=false --verbose=false
	@echo "[Phylotraits] Outputs:"
	@ls -lh $(IMPUTE_OUT) $(IMPUTE_DIAG)/coverage_before_after.csv 2>/dev/null || true

# Convenience: run hybrid using imputed traits table
phylotraits_run:
	@echo "[Phylotraits] Running hybrid CV with imputed trait table..."
	@make -f Makefile.hybrid hybrid_cv AXIS=T OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed TRAIT_CSV=$(IMPUTE_OUT) BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000
	@make -f Makefile.hybrid hybrid_cv AXIS=M OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed TRAIT_CSV=$(IMPUTE_OUT) BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000
	@make -f Makefile.hybrid hybrid_cv AXIS=L OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed TRAIT_CSV=$(IMPUTE_OUT) BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000
	@echo "[Phylotraits] Hybrid runs (T,M,L) completed with imputed table."

# Categorical imputation (phylo-weighted kNN majority vote)
IMPUTE_CAT_IN ?= $(IMPUTE_OUT)
IMPUTE_CAT_OUT ?= artifacts/model_data_bioclim_subset_enhanced_imputed_cat.csv
TRAITS_CAT ?= Leaf_phenology,Photosynthesis_pathway
TREE ?= data/phylogeny/eive_try_tree.nwk


phylotraits_impute_categorical:
	@echo "[Phylotraits] Imputing categorical traits (phylo-weighted votes)..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  $(R) src/Stage_2_Data_Processing/phylo_impute_traits_categorical.R \
	    --input_csv=$(IMPUTE_CAT_IN) \
	    --out_csv=$(IMPUTE_CAT_OUT) \
	    --diag_dir=$(IMPUTE_DIAG) \
	    --traits_cat=$(TRAITS_CAT) \
	    --tree=$(TREE) \
	    --x_exp=$(X_EXP) --k_trunc=$(K_TRUNC)
	@echo "[Phylotraits] Outputs:"
	@ls -lh $(IMPUTE_CAT_OUT) $(IMPUTE_DIAG)/categorical_coverage_before_after.csv 2>/dev/null || true

# Convenience: numeric + categorical imputation in one go
IMPUTE_ADD_ENV ?= false
IMPUTE_ENV_CSV ?= data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv
IMPUTE_ENV_REGEX ?= ^bio[0-9]{1,2}_mean$
IMPUTE_ENV_CENTER ?= true

phylotraits_impute_all: phylotraits_impute phylotraits_impute_categorical
	@echo "[Phylotraits] Completed numeric + categorical imputation."

# Hybrid runs with categorical-imputed table
phylotraits_run_cat:
	@echo "[Phylotraits] Running hybrid CV with categorical-imputed trait table..."
	@make -f Makefile.hybrid hybrid_cv AXIS=T OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed TRAIT_CSV=$(IMPUTE_CAT_OUT) BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000
	@make -f Makefile.hybrid hybrid_cv AXIS=M OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed TRAIT_CSV=$(IMPUTE_CAT_OUT) BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000
	@make -f Makefile.hybrid hybrid_cv AXIS=L OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed TRAIT_CSV=$(IMPUTE_CAT_OUT) BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000
	@echo "[Phylotraits] Hybrid runs (T,M,L) completed with categorical-imputed table."

# Install local BHPMF package into user library
install_bhpmf:
	@echo "[Setup] Installing local BHPMF package into /home/olier/ellenberg/.Rlib ..."
	@mkdir -p /home/olier/ellenberg/.Rlib
	@R CMD INSTALL -l "/home/olier/ellenberg/.Rlib" /home/olier/BHPMF
	@echo "[Setup] Done. Test with: Rscript -e 'library(BHPMF); packageVersion(\"BHPMF\")'"

install_bhpmf_patched:
	@echo "[Setup] Patching BHPMF for R>=4.2 BLAS/LAPACK interface and installing..."
	@set -e; \
	PATCH_DIR=third_party/BHPMF_patched; \
	rm -rf "$$PATCH_DIR"; mkdir -p "$$PATCH_DIR"; \
	cp -r /home/olier/BHPMF/* "$$PATCH_DIR"/; \
	# Patch latentNode.cpp (use F77_CALL and FCONE for char args) \
	sed -i 's/#include <R_ext\/Utils.h>/#include <R_ext\/Utils.h>\n#include <R_ext\/RS.h>/' "$$PATCH_DIR/src/latentNode.cpp"; \
	sed -i 's/F77_NAME(dgemm)(/F77_CALL(dgemm)(/g' "$$PATCH_DIR/src/latentNode.cpp"; \
	sed -i 's/&num_latent_features_);/&num_latent_features_ FCONE FCONE);/' "$$PATCH_DIR/src/latentNode.cpp"; \
	sed -i 's/F77_NAME(dgemv)(/F77_CALL(dgemv)(/g' "$$PATCH_DIR/src/latentNode.cpp"; \
	sed -i 's/&inc_one);/&inc_one FCONE);/' "$$PATCH_DIR/src/latentNode.cpp"; \
	sed -i 's/F77_NAME(dpotrf)(/F77_CALL(dpotrf)(/g' "$$PATCH_DIR/src/latentNode.cpp"; \
	sed -i 's/&info);/&info FCONE);/' "$$PATCH_DIR/src/latentNode.cpp"; \
	# Patch utillity.cpp (use F77_CALL and FCONE for dtrmv) \
	sed -i '1i #include <R_ext/RS.h>' "$$PATCH_DIR/src/utillity.cpp"; \
	sed -i 's/F77_NAME(dtrmv)(\"U\", \"T\", \"N\"/F77_CALL(dtrmv)(\"U\", \"T\", \"N\"/g' "$$PATCH_DIR/src/utillity.cpp"; \
	sed -i 's/F77_NAME(dtrmv)(\"L\", \"N\", \"N\"/F77_CALL(dtrmv)(\"L\", \"N\", \"N\"/g' "$$PATCH_DIR/src/utillity.cpp"; \
	sed -i 's/des, &inc);/des, &inc FCONE FCONE FCONE);/' "$$PATCH_DIR/src/utillity.cpp"; \
	R CMD INSTALL -l "/home/olier/ellenberg/.Rlib" "$$PATCH_DIR"; \
	echo "[Setup] Done. Verify with: R_LIBS_USER=\"/home/olier/ellenberg/.Rlib\" Rscript -e 'library(BHPMF); packageVersion(\"BHPMF\")'"

# ----------------------------------------------------------------------------
# TMUX orchestration for hybrid runs (all axes; phylo and non-phylo)
# ----------------------------------------------------------------------------

# Defaults (match expanded600)
TMUX_LABEL           ?= bioclim_subset
TMUX_TRAIT_CSV       ?= artifacts/model_data_bioclim_subset.csv
TMUX_BIOCLIM_SUMMARY ?= data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv
TMUX_AXES            ?= T,M,L,N,R
TMUX_SESSION         ?=
TMUX_FOLDS           ?= 10
TMUX_REPEATS         ?= 5
TMUX_BOOTSTRAP       ?= 1000
TMUX_X_EXP           ?= 2
TMUX_K_TRUNC         ?= 0
TMUX_TREE            ?=
# New variable; keep backward compatibility by inheriting old name if set
TMUX_OFFER_ALL_VARIABLES ?=
TMUX_OFFER_ALL_VARIABLES ?= $(TMUX_OFFER_ALL_CLIMATE)
TMUX_OFFER_ALL_VARIABLES_AXES ?=
TMUX_RF_ONLY         ?=

hybrid_tmux:
	@echo "[tmux] Launching hybrid runs in tmux..."
	@bash scripts/run_hybrid_axes_tmux.sh \
	  --label $(TMUX_LABEL) \
	  --trait_csv $(TMUX_TRAIT_CSV) \
	  --bioclim_summary $(TMUX_BIOCLIM_SUMMARY) \
	  --axes $(TMUX_AXES) \
	  $(if $(TMUX_SESSION),--session $(TMUX_SESSION),) \
	  --folds $(TMUX_FOLDS) \
	  --repeats $(TMUX_REPEATS) \
	  --bootstrap $(TMUX_BOOTSTRAP) \
	  --x_exp $(TMUX_X_EXP) \
	  --k_trunc $(TMUX_K_TRUNC) \
  $(if $(TMUX_TREE),--tree $(TMUX_TREE),) \
  $(if $(TMUX_OFFER_ALL_VARIABLES),--offer_all_variables $(TMUX_OFFER_ALL_VARIABLES),) \
  $(if $(TMUX_OFFER_ALL_VARIABLES_AXES),--offer_all_variables_axes $(TMUX_OFFER_ALL_VARIABLES_AXES),) \
  $(if $(TMUX_RF_ONLY),--rf_only $(TMUX_RF_ONLY),)

# ============================================================================
# Stage 2 GAM (canonical) workflows
# ============================================================================

.PHONY: prepare_climate_data stage2_T_enhanced stage2_L_fullfeature_pwsem

# Prepare enhanced climate+trait dataset for pwSEM legacy runs
prepare_climate_data:
	@echo "[Stage 2] Preparing enhanced climate+trait dataset for pwSEM..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript src/Stage_4_SEM_Analysis/prepare_enhanced_model_data.R
	@echo "[Stage 2] Enhanced dataset ready at artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv"

# Legacy pwSEM reproduction for T axis (climate-enriched branch)
stage2_T_enhanced: prepare_climate_data
	@echo "[Stage 2] Running climate-enriched pwSEM for T axis..."
	@out_dir=results/stage2_T_enhanced_$$(date +%Y%m%d_%H%M%S); \
	  mkdir -p $$out_dir; \
	  R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
	    --input_csv artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv \
	    --target T \
	    --repeats 5 \
	    --folds 10 \
	    --stratify true \
	    --standardize true \
	    --deconstruct_size true \
	    --phylogeny_newick data/phylogeny/eive_try_tree.nwk \
	    --out_dir $$out_dir \
	    2>&1 | tee $$out_dir/run.log
	@echo "[Stage 2] Outputs written to $$out_dir"

# Legacy pwSEM reproduction for L axis with full Stage-1 feature coverage
stage2_L_fullfeature_pwsem: prepare_climate_data
	@echo "[Stage 2] Running full-feature pwSEM for L axis..."
	@out_dir=results/stage2_L_fullfeature_pwsem_$$(date +%Y%m%d_%H%M%S); \
	  mkdir -p $$out_dir; \
	  R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
	    --input_csv artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv \
	    --target L \
	    --repeats 5 \
	    --folds 10 \
	    --stratify true \
	    --standardize true \
	    --les_components negLMA,Nmass \
	    --add_predictor logLA,LES_core,logSM,logSSD,SIZE,LDMC,is_woody,lma_precip,height_ssd,les_seasonality,LMA,Nmass,logH,precip_cv,tmin_mean \
	    --add_interaction 'ti(logLA,logH),ti(logH,logSSD),SIZE:mat_mean,SIZE:precip_mean,LES_core:temp_seasonality,LES_core:drought_min,LMA:precip_mean' \
	    --phylogeny_newick data/phylogeny/eive_try_tree.nwk \
	    --out_dir $$out_dir \
	    2>&1 | tee $$out_dir/run.log
	@echo "[Stage 2] Outputs written to $$out_dir"

# Prepare dataset with trait PCs for Stage 2 GAM runs
prepare_stage2_pc_data:
	@echo "[Stage 2] Preparing Stage 2 dataset with trait principal components..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript src/Stage_4_SEM_Analysis/prepare_stage2_pc_data.R
	@echo "[Stage 2] PC-enhanced data ready at artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2_pcs.csv"

# Temperature axis GAM (trait PCs + tensors)
stage2_T_gam: prepare_stage2_pc_data
	@echo "[Stage 2] Running canonical T-axis GAM (PC + tensors)..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript src/Stage_4_SEM_Analysis/run_aic_selection_T_pc.R

# Light axis GAM (trait PCs + pruned tensor)
stage2_L_gam: prepare_stage2_pc_data
	@echo "[Stage 2] Running canonical L-axis GAM (PC + pruned tensor)..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript src/Stage_4_SEM_Analysis/run_aic_selection_L_tensor_pruned.R

# Moisture axis GAM (Stage-1 predictors, smooth climate terms)
stage2_M_gam: prepare_stage2_pc_data
	@echo "[Stage 2] Running canonical M-axis GAM (PC tensors)..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript src/Stage_4_SEM_Analysis/run_aic_selection_M_tensor.R

# Moisture axis GAM with PC and optimized tensors (new canonical)
stage2_M_gam_pc: prepare_stage2_pc_data
	@echo "[Stage 2] Running optimized M-axis GAM (PC + targeted tensors + enhanced phylo)..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript src/Stage_4_SEM_Analysis/run_aic_selection_M_pc.R

# Quick test version with reduced CV (2x5 instead of 5x10)
stage2_M_gam_pc_quick: prepare_stage2_pc_data
	@echo "[Stage 2] Running M-axis GAM PC (quick 2x5 CV test)..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  CV_REPEATS=2 CV_FOLDS=5 Rscript src/Stage_4_SEM_Analysis/run_aic_selection_M_pc.R

# ============================================================================
# N Axis GAM with Full Features (addressing critical gaps)
# ============================================================================

# N axis GAM with ALL missing features (including co-dominant logLA)
stage2_N_gam_full:
	@echo "[Stage 2] Running N-axis GAM with FULL feature set (including logLA)..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript src/Stage_4_SEM_Analysis/run_aic_selection_N_full.R

# Quick test version with reduced CV (2x5 instead of 5x10)
stage2_N_gam_full_quick:
	@echo "[Stage 2] Running N-axis GAM full features (quick 2x5 CV test)..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  CV_REPEATS=2 CV_FOLDS=5 Rscript src/Stage_4_SEM_Analysis/run_aic_selection_N_full.R

# ============================================================================
# R Axis (Reaction/pH) GAM with Full Features including Soil pH
# ============================================================================

# R axis GAM with ALL features including critical soil pH profiles
stage2_R_gam_full:
	@echo "[Stage 2] Running R-axis GAM with FULL feature set (including soil pH profiles)..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  Rscript src/Stage_4_SEM_Analysis/run_aic_selection_R_full.R

# Quick test version with reduced CV (2x5 instead of 5x10)
stage2_R_gam_full_quick:
	@echo "[Stage 2] Running R-axis GAM full features (quick 2x5 CV test)..."
	@R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
	  CV_REPEATS=2 CV_FOLDS=5 Rscript src/Stage_4_SEM_Analysis/run_aic_selection_R_full.R
