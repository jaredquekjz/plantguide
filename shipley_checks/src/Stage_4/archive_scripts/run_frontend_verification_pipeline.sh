#!/bin/bash
#
# Frontend Verification Pipeline
#
# Purpose: Run complete verification of Python vs R guild scorers
#

set -e  # Exit on error

echo "=========================================="
echo "Frontend Verification Pipeline"
echo "=========================================="
echo ""

# Step 1: Test dataset already generated
echo "Step 1: Checking test dataset..."
if [ -f "shipley_checks/stage4/100_guild_testset.json" ]; then
    echo "✓ Test dataset exists ($(wc -l < shipley_checks/stage4/100_guild_testset.json) lines)"
else
    echo "Generating test dataset..."
    env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
      /usr/bin/Rscript shipley_checks/src/Stage_4/generate_100_guild_testset.R
    echo "✓ Test dataset generated"
fi
echo ""

# Step 2: Run Python scorer
echo "Step 2: Scoring guilds with Python frontend..."
/home/olier/miniconda3/envs/AI/bin/python \
  shipley_checks/src/Stage_4/python_baseline/score_100_guilds_export_csv.py

echo "✓ Python scoring complete"
echo ""

# Step 3: Run R scorer
echo "Step 3: Scoring guilds with R frontend..."
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript shipley_checks/src/Stage_4/score_guilds_export_csv.R

echo "✓ R scoring complete"
echo ""

# Step 4: Verify parity
echo "Step 4: Verifying checksum parity..."
/home/olier/miniconda3/envs/AI/bin/python \
  shipley_checks/src/Stage_4/verify_frontend_parity.py

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✅ PIPELINE SUCCESS"
    echo "=========================================="
    echo "Gold standard verified. Ready for Rust implementation."
else
    echo ""
    echo "=========================================="
    echo "❌ PIPELINE FAILED"
    echo "=========================================="
    echo "Fix scorer implementations and re-run."
    exit 1
fi
