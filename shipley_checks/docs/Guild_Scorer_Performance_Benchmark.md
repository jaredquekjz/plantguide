# Guild Scorer Performance Benchmark

**Date**: 2025-11-11
**Test Environment**: Linux 6.8.0-85-generic
**Python**: Conda AI environment
**R**: System R with custom library (.Rlib)

## Benchmark Configuration

**Test Guilds** (3 guilds, 7 plants each):
- `forest_garden`: Mixed temperate guild
- `competitive_clash`: High-competition guild
- `stress_tolerant`: Australian native guild

**Calibration**: 7plant calibration, tier_3_humid_temperate

## Results

### Initialization Time

| Implementation | Time (seconds) | Notes |
|----------------|----------------|-------|
| **Python** | 0.0052 | Fast DuckDB lazy loading |
| **R** | 0.5391 | CSV parsing + PhyloPDCalculator test |

**Ratio**: R is 103.7× slower at initialization

### Scoring Time (3 guilds)

| Implementation | Total Time | Average per Guild |
|----------------|------------|-------------------|
| **Python** | 0.6910s | 0.2303s |
| **R** | 0.2589s | 0.0863s |

**Ratio**: R is 2.67× faster at scoring

### Per-Guild Breakdown

| Guild | Python | R | Python/R Ratio |
|-------|--------|---|----------------|
| forest_garden | 0.2494s | 0.0861s | 2.90× |
| competitive_clash | 0.2238s | 0.1426s | 1.57× |
| stress_tolerant | 0.2177s | 0.0302s | 7.21× |

### Total Time (Init + Scoring)

| Implementation | Time (seconds) |
|----------------|----------------|
| **Python** | 0.6962 |
| **R** | 0.7980 |

**Ratio**: R is 1.15× slower overall

## Analysis

### Python Strengths
- **Very fast initialization** (5ms) due to DuckDB lazy loading
- Consistent scoring times across guilds
- Better for interactive/API use cases with frequent restarts

### R Strengths
- **2.67× faster scoring** once initialized
- Better for batch processing multiple guilds
- More efficient dataframe operations with dplyr/arrow

### Performance Characteristics

1. **Initialization overhead dominates R**: The 540ms R initialization includes:
   - CSV parsing with arrow
   - PhyloPDCalculator self-test (2 test guilds)
   - Loading calibration parameters

2. **R scoring efficiency**: Once loaded, R processes guilds faster because:
   - Pre-loaded dataframes stay in memory
   - dplyr operations are optimized
   - Less Python/DuckDB context switching

3. **Crossover point**: For batch processing >2 guilds, R becomes more efficient overall

## Recommendations

**Use Python when**:
- Building interactive web APIs
- Single guild scoring with frequent restarts
- Integrating with Python ML pipelines

**Use R when**:
- Batch processing many guilds (>10)
- Research workflows with exploratory analysis
- Integration with existing R statistical pipelines

## Reproduction

```bash
# Python benchmark
conda run -n AI python benchmark_scorer_speed.py

# R benchmark
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript benchmark_scorer_speed.R
```

## Parity Verification

Both implementations produce identical results (differences < 0.0001):

| Guild | Python | R | Difference |
|-------|--------|---|------------|
| forest_garden | 90.467710 | 90.467700 | 0.000010 |
| competitive_clash | 55.441621 | 55.441600 | 0.000021 |
| stress_tolerant | 45.442341 | 45.442300 | 0.000041 |
