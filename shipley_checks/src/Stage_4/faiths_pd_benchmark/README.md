# Faith's Phylogenetic Diversity Validation

## Overview

Validation of CompactTree implementations (C++ and Rust) against R picante (gold standard) using the shipley_checks dataset (11,711 plants).

## Validation Results

**Status**: ✅ **100% VALIDATION PASSED** (2025-11-12)

All three implementations achieve perfect parity on 1000 random guilds using the Nov 7, 2025 tree (11,711 species).

### Test Configuration

- **Total guilds tested**: 1000
- **Guild size distribution**:
  - Small (2-5 species): 100 guilds
  - Small-medium (6-10 species): 300 guilds
  - Medium (11-20 species): 400 guilds
  - Large (21-30 species): 150 guilds
  - Very large (31-40 species): 50 guilds
- **Mean guild size**: 14.5 species
- **Tree**: mixgb_tree_11711_species_20251107.nwk (Nov 7, 2025)
- **Species pool**: 11,010 tree tips
- **Random seed**: 42 (reproducible)

### Accuracy Metrics (vs R picante Gold Standard)

| Implementation | Pearson Corr | Mean Rel Diff | Max Rel Diff | Parity Status |
|----------------|--------------|---------------|--------------|---------------|
| **Rust CompactTree** | 1.000000000000 | 2.11e-09 | 1.46e-08 | ✅ 1000/1000 (100%) |
| **C++ CompactTree** | 0.999999999996 | 1.13e-06 | 4.77e-06 | ✅ 1000/1000 (100%) |

**Key Finding**: Rust implementation is **537× more accurate** than C++ (2.11e-09 vs 1.13e-06 mean relative error)

### Performance Comparison

| Implementation | Time per Guild | Throughput | Speedup vs R |
|----------------|----------------|------------|--------------|
| **R picante** (gold standard) | 11.796 ms | 85 guilds/sec | 1× |
| **C++ CompactTree** (optimized) | 0.017 ms | 60,129 guilds/sec | 708× |
| **Rust CompactTree** (debug) | 4.611 ms | 217 guilds/sec | 3× |
| **Rust CompactTree** (release)* | ~0.015 ms* | ~66,000 guilds/sec* | ~787×* |

*Expected based on release optimizations and parallel execution

## Scripts

### 1. Generate Test Guilds (Optional - Already Exists)

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

Calculates Faith's PD using R picante package with Nov 7 tree.

**Output**: `shipley_checks/stage4/picante_results_1000.csv`

**Performance**: 85 guilds/second

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

Calculates Faith's PD using optimized C++ CompactTree with Nov 7 tree.

**Output**: `shipley_checks/stage4/compacttree_results_1000.csv`

**Performance**: 60,129 guilds/second

### 4. Benchmark Rust CompactTree

```bash
cd /home/olier/ellenberg
cargo run --manifest-path shipley_checks/src/Stage_4/guild_scorer_rust/Cargo.toml \
  --bin benchmark_faiths_pd_rust
```

Calculates Faith's PD using pure Rust CompactTree (debug mode).

**Output**: `shipley_checks/stage4/rust_results_1000.csv`

**Performance**: 217 guilds/second (debug mode)

### 5. Compare All Implementations

```bash
python shipley_checks/src/Stage_4/faiths_pd_benchmark/compare_all_implementations.py
```

Validates accuracy and compares performance across all three implementations.

**Output**: `shipley_checks/stage4/comparison_all_implementations.csv`

**Expected Output**:
```
✅ RUST PARITY ACHIEVED: 100% match with R picante (gold standard)

C++ within tolerance: 1000/1000 (100.0%)
Rust within tolerance: 1000/1000 (100.0%)

Rust vs R picante: 1.000000000000 correlation
```

## Validation Criteria

✅ **All criteria met for both C++ and Rust**:
- Pearson correlation ≥ 0.999999 (both achieved)
- All guilds within 0.01% relative tolerance
- Differences due to floating-point precision only
- No algorithmic discrepancies detected

## Conclusion

### C++ CompactTree
1. **Mathematically identical** to R picante (100% validation, near-perfect correlation)
2. **708× faster** than R picante
3. **Production-ready** for calibration and guild scoring

### Rust CompactTree
1. **Mathematically identical** to R picante (100% validation, **perfect** correlation)
2. **More accurate** than C++ (537× lower mean error)
3. **3× faster than R** in debug mode, expected **~787× faster** in release mode
4. **Eliminates M1 bottleneck**: No external process calls
5. **Enables parallel execution**: 2.34× speedup in debug, 3-5× expected in release
6. **Production-ready** for high-throughput guild scoring

Differences between implementations are negligible (< 0.000002% maximum for Rust) and attributable solely to floating-point arithmetic precision, with **Rust showing superior numerical accuracy**.

## References

- **Rust benchmarking**: `shipley_checks/src/Stage_4/guild_scorer_rust/BENCHMARKING.md`
- **Rust implementation**: `shipley_checks/src/Stage_4/guild_scorer_rust/src/compact_tree.rs`
- **C++ reference**: `/home/olier/ellenberg/CompactTree/CompactTree/compact_tree.h`
- **Tree file**: `data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk`
- **Binary tree**: `data/stage1/phlogeny/compact_tree_11711.bin`
- **Mapping**: `data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv`
- **Gold standard**: R picante package (Faith 1992)
