#!/bin/bash
# Phase 2: Search for all list column accesses in Rust code

echo "================================================================================"
echo "PHASE 2: List Column Access Audit"
echo "================================================================================"

SRC_DIR="shipley_checks/src/Stage_4/guild_scorer_rust/src"

echo ""
echo "ORGANISM LIST COLUMNS:"
echo "--------------------------------------------------------------------------------"

for col in "pollinators" "herbivores" "pathogens" "flower_visitors" \
           "predators_hasHost" "predators_interactsWith" "predators_adjacentTo" \
           "fungivores_eats"; do
    echo ""
    echo "Column: $col"
    grep -rn "\.column(\"$col\")" "$SRC_DIR" --include="*.rs" 2>/dev/null | \
        sed 's/^/  /' || echo "  (no direct accesses found)"
done

echo ""
echo ""
echo "FUNGI LIST COLUMNS:"
echo "--------------------------------------------------------------------------------"

for col in "pathogenic_fungi" "pathogenic_fungi_host_specific" "mycoparasite_fungi" \
           "entomopathogenic_fungi" "amf_fungi" "emf_fungi" "endophytic_fungi" \
           "saprotrophic_fungi"; do
    echo ""
    echo "Column: $col"
    grep -rn "\.column(\"$col\")" "$SRC_DIR" --include="*.rs" 2>/dev/null | \
        sed 's/^/  /' || echo "  (no direct accesses found)"
done

echo ""
echo "================================================================================"
echo "Files to audit in detail:"
echo "================================================================================"
echo ""

# Get unique files that access any list column
echo "Finding all files accessing list columns..."
{
    for col in "pollinators" "herbivores" "pathogens" "flower_visitors" \
               "predators_hasHost" "predators_interactsWith" "predators_adjacentTo" \
               "fungivores_eats" "pathogenic_fungi" "pathogenic_fungi_host_specific" \
               "mycoparasite_fungi" "entomopathogenic_fungi" "amf_fungi" "emf_fungi" \
               "endophytic_fungi" "saprotrophic_fungi"; do
        grep -rl "\.column(\"$col\")" "$SRC_DIR" --include="*.rs" 2>/dev/null
    done
} | sort -u | while read file; do
    echo "  $file"
done
