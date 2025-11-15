#!/usr/bin/env bash
#
# Complete Taxonomic Vernacular Pipeline
#
# Runs the complete end-to-end taxonomic vernacular categorization pipeline:
# 1. Initial assignment (P1 iNat + P3 ITIS only)
# 2. Derive categories from species vernaculars (P2 genus, P4 family)
# 3. Final assignment with all priority levels
#
# Author: Claude Code
# Date: 2025-11-15

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="/home/olier/ellenberg/data/taxonomy"

echo "================================================================================"
echo "TAXONOMIC VERNACULAR CATEGORIZATION - COMPLETE PIPELINE"
echo "================================================================================"
echo ""

# ============================================================================
# Step 1: Initial Assignment (P1 + P3 only)
# ============================================================================

echo "STEP 1: Initial vernacular assignment (P1 iNat species + P3 ITIS family)"
echo "--------------------------------------------------------------------------------"
echo "This creates the base files needed for derivation."
echo ""

# Create empty stub files for derived categories
# (Pipeline will skip P2/P4 if these are empty)
cat > "$DATA_DIR/animal_genus_vernaculars_derived.parquet" <<'EOF'
PAR1
EOF

cat > "$DATA_DIR/animal_family_vernaculars_derived.parquet" <<'EOF'
PAR1
EOF

cat > "$DATA_DIR/plant_genus_vernaculars_derived.parquet" <<'EOF'
PAR1
EOF

cat > "$DATA_DIR/plant_family_vernaculars_derived.parquet" <<'EOF'
PAR1
EOF

# Run initial assignment
R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript "$SCRIPT_DIR/assign_vernacular_names.R"

echo ""
echo "✓ Step 1 complete: Base vernacular files created"
echo ""

# ============================================================================
# Step 2: Derive Categories from Species Vernaculars
# ============================================================================

echo "================================================================================"
echo "STEP 2: Derive genus and family categories from species vernaculars"
echo "================================================================================"
echo ""

for organism_type in animal plant; do
  for level in genus family; do
    echo "Deriving ${organism_type} ${level} categories..."
    R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
      /usr/bin/Rscript "$SCRIPT_DIR/derive_all_vernaculars.R" \
      --organism-type "$organism_type" \
      --level "$level" \
      --data-dir "$DATA_DIR"
    echo ""
  done
done

echo "✓ Step 2 complete: All derived categories generated"
echo ""

# ============================================================================
# Step 3: Final Assignment with All Priority Levels
# ============================================================================

echo "================================================================================"
echo "STEP 3: Final vernacular assignment (all priority levels P1-P4)"
echo "================================================================================"
echo ""

R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript "$SCRIPT_DIR/assign_vernacular_names.R"

echo ""
echo "================================================================================"
echo "PIPELINE COMPLETE"
echo "================================================================================"
echo ""
echo "Output files:"
echo "  - $DATA_DIR/plants_vernacular_final.parquet"
echo "  - $DATA_DIR/organisms_vernacular_final.parquet"
echo "  - $DATA_DIR/all_taxa_vernacular_final.parquet"
echo ""
echo "Derived categories:"
echo "  - $DATA_DIR/animal_genus_vernaculars_derived.parquet"
echo "  - $DATA_DIR/animal_family_vernaculars_derived.parquet"
echo "  - $DATA_DIR/plant_genus_vernaculars_derived.parquet"
echo "  - $DATA_DIR/plant_family_vernaculars_derived.parquet"
echo ""
