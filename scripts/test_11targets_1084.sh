#!/bin/bash
# Test 11-target joint imputation on 1084 species

export R_LIBS_USER=/home/olier/ellenberg/.Rlib
export PATH=/home/olier/miniconda3/envs/AI/bin:/usr/bin:/bin

/home/olier/miniconda3/envs/AI/bin/Rscript \
  src/Stage_1/mixgb/train_experimental_11targets.R \
  --input_csv=model_data/inputs/mixgb_perm123_1084/mixgb_input_perm2_1084_20251027.csv \
  --cv_output_dir=results/experiments/test_11targets_1084 \
  --prod_output_dir=model_data/outputs/test_11targets_1084 \
  --prod_output_prefix=test_11targets \
  --nrounds=1000 \
  --eta=0.1 \
  --folds=3 \
  --m=2 \
  --clean=true \
  --seed=20251029
