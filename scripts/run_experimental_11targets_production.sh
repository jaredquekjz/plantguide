#!/bin/bash
# Production 11-target joint imputation on 11,680 species
# Joint imputation: 6 log traits + 5 EIVE axes
# Optimal hyperparameters from 1.7b Section 8

export R_LIBS_USER=/home/olier/ellenberg/.Rlib
export PATH=/home/olier/miniconda3/envs/AI/bin:/usr/bin:/bin

echo "Starting experimental 11-target production run..."
echo "Configuration:"
echo "  Species: 11,680"
echo "  Targets: 11 (6 log traits + 5 EIVE)"
echo "  CV: 10-fold"
echo "  Production: 10 imputations"
echo "  nrounds: 3000"
echo "  eta: 0.025"
echo "  Estimated runtime: 10-12 hours"
echo ""

nohup /home/olier/miniconda3/envs/AI/bin/Rscript \
  src/Stage_1/mixgb/train_experimental_11targets.R \
  --input_csv=model_data/inputs/mixgb_experimental_11targets/mixgb_input_11targets_efficient_11680_20251029.csv \
  --cv_output_dir=results/experiments/experimental_11targets_20251029 \
  --prod_output_dir=model_data/outputs/experimental_11targets_20251029 \
  --prod_output_prefix=experimental_11targets \
  --nrounds=3000 \
  --eta=0.025 \
  --folds=10 \
  --m=10 \
  --device=cuda \
  --clean=true \
  --seed=20251029 \
  > logs/experimental_11targets_production_20251029.log 2>&1 &

PID=$!
echo "Job launched in background with PID: $PID"
echo "Monitor with: tail -f logs/experimental_11targets_production_20251029.log"
echo ""
echo "To check progress:"
echo "  grep 'Mean RMSE' logs/experimental_11targets_production_20251029.log"
echo ""
echo "Job will complete in approximately 10-12 hours"
