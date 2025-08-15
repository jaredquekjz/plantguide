# Stage 5 MAG prediction convenience targets

MAG_INPUT ?= examples/mag_dryrun_input.csv
MAG_OUTPUT ?= results/mag_predictions.csv
MAG_EQUATIONS ?= results/mag_equations.json
MAG_COMPOSITES ?= results/composite_recipe.json

.PHONY: mag_predict mag_dryrun

mag_predict:
	@echo "Running MAG prediction: input=$(MAG_INPUT) output=$(MAG_OUTPUT)" \
	 && Rscript src/Stage_5_MAG/apply_mag.R \
	    --input_csv $(MAG_INPUT) \
	    --output_csv $(MAG_OUTPUT) \
	    --equations_json $(MAG_EQUATIONS) \
	    --composites_json $(MAG_COMPOSITES)

mag_dryrun:
	@$(MAKE) mag_predict MAG_INPUT=examples/mag_dryrun_input.csv MAG_OUTPUT=results/mag_predictions_dryrun.csv

