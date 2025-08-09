#!/bin/bash

# Test the improved normalize_eive_to_wfo.R script
echo "Testing improved normalize_eive_to_wfo.R script..."

# Remove any existing test output
rm -f data/test_EIVE_TaxonConcept_WFO.csv

# Run with fuzzy=0 to test exact matches only
echo "Test 1: Exact matches only (fuzzy=0)..."
Rscript scripts/normalize_eive_to_wfo.R \
  --eive_csv=data/EIVE_Paper_1.0_SM_08_csv/mainTable.csv \
  --wfo_csv=data/WFO_Backbone/_WFOCompleteBackbone/classification.csv \
  --out=data/test_EIVE_TaxonConcept_WFO.csv \
  --fuzzy=0 \
  --batch_size=100

echo ""
echo "Checking output file..."
if [ -f data/test_EIVE_TaxonConcept_WFO.csv ]; then
    echo "Output file created successfully"
    echo "First 5 lines:"
    head -5 data/test_EIVE_TaxonConcept_WFO.csv
    echo ""
    echo "Line count:"
    wc -l data/test_EIVE_TaxonConcept_WFO.csv
else
    echo "ERROR: Output file not created"
fi

echo ""
echo "Test complete!"