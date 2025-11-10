# Faith's Phylogenetic Diversity Validation

## Overview

Validation of C++ CompactTree implementation against R picante (gold standard) using the shipley_checks dataset (11,711 plants).

## Validation Results

**Status**: ✅ **100% VALIDATION PASSED** (2025-11-10)

### Test Configuration
- **Total guilds tested**: 1000
- **Guild size distribution**:
  - Small (2-5 species): 100 guilds
  - Small-medium (6-10 species): 300 guilds
  - Medium (11-20 species): 400 guilds
  - Large (21-30 species): 150 guilds
  - Very large (31-40 species): 50 guilds
- **Mean guild size**: 14.5 species
- **Species pool**: 11,638 tree tips
- **Random seed**: 42 (reproducible)

### Accuracy Metrics

| Metric | Value |
|--------|-------|
| **Pearson correlation** | 1.0000000000 (perfect) |
| **Mean absolute difference** | 0.001897 |
| **Max absolute difference** | 0.004998 |
| **Mean relative difference** | 0.000115% |
| **Max relative difference** | 0.000477% |
| **Guilds within 0.01% tolerance** | 1000 (100%) |

### Performance Comparison

| Implementation | Time per Guild | Throughput | Speedup |
|----------------|----------------|------------|---------|
| **R picante** (gold standard) | 11.668 ms | 86 guilds/sec | 1× |
| **CompactTree C++** (optimized) | 0.016433 ms | 60,853 guilds/sec | **708×** |

## Scripts

### 1. Generate Test Guilds
```bash
python shipley_checks/src/Stage_4/faiths_pd_benchmark/generate_random_guilds.py
```

Generates 1000 random guilds with realistic size distribution.

**Output**: `shipley_checks/stage4/test_guilds_1000.csv`

### 2. Benchmark R Picante (Gold Standard)
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript shipley_checks/src/Stage_4/faiths_pd_benchmark/benchmark_picante_1000_guilds.R
```

Calculates Faith's PD using R picante package.

**Output**: `shipley_checks/stage4/picante_results_1000.csv`

### 3. Benchmark C++ CompactTree
```bash
# Compile
cd shipley_checks/src/Stage_4/faiths_pd_benchmark
g++ -O3 -std=c++11 -march=native \
  -o benchmark_compacttree_1000_guilds \
  benchmark_compacttree_1000_guilds.cpp \
  -I ../../../../CompactTree/CompactTree

# Run from repo root
cd /home/olier/ellenberg
./shipley_checks/src/Stage_4/faiths_pd_benchmark/benchmark_compacttree_1000_guilds
```

Calculates Faith's PD using optimized C++ CompactTree.

**Output**: `shipley_checks/stage4/compacttree_results_1000.csv`

### 4. Compare Results
```bash
python shipley_checks/src/Stage_4/faiths_pd_benchmark/compare_faiths_pd_results.py
```

Validates accuracy and compares performance.

**Output**: `shipley_checks/stage4/comparison_results.csv`

## Validation Criteria

✅ **All criteria met**:
- Pearson correlation = 1.0 (perfect)
- All guilds within 0.01% relative tolerance
- Differences due to floating-point precision only
- No algorithmic discrepancies detected

## Conclusion

The C++ CompactTree implementation is:
1. **Mathematically identical** to R picante (100% validation, perfect correlation)
2. **708× faster** than R picante
3. **Production-ready** for calibration and guild scoring

Differences between implementations are negligible (< 0.005% maximum) and attributable solely to floating-point arithmetic precision differences between R and C++.

## References

- Validation documentation: `/home/olier/ellenberg/results/summaries/phylotraits/Stage_4/4.6_Phylogenetic_Embedding_Generation.md`
- CompactTree library: `/home/olier/ellenberg/CompactTree/`
- Tree file: `data/stage1/phlogeny/mixgb_tree_11676_species_20251027.nwk`
- Mapping: `data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11676.csv`
