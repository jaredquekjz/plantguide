# Phase 8 API Server Architecture Evaluation

## Executive Summary

The proposed architecture (Axum + DataFusion + Polars) is **highly suitable** for the project's requirements, offering a robust hybrid approach for high-performance search (DataFusion) and complex ecological scoring (Polars). The separation of concerns is clear, and the chosen technologies are industry-standard for Rust data engineering.

However, there are **critical discrepancies** between the plan and the actual Phase 7 implementation regarding file paths and names that must be resolved before implementation.

## Detailed Analysis

### 1. Core Architecture (Strong)
-   **Hybrid Engine**: Combining **DataFusion** for low-latency SQL queries (90% traffic) with **Polars** for CPU-bound scoring (10% traffic) is the correct architectural choice. It leverages the strengths of both engines without unnecessary overhead.
-   **Concurrency Model**: Using `tokio` for I/O-bound tasks (DataFusion, HTTP) and `spawn_blocking` for CPU-bound tasks (Polars) is the correct pattern to avoid blocking the async runtime.
-   **State Management**: Wrapping `GuildScorer` in `Arc` is valid. Code review of `scorer.rs` confirms `GuildScorer` is thread-safe (Sync) and designed for concurrent access (using `Rayon` internally for parallel scoring).

### 2. Discrepancies & Action Items

> [!WARNING]
> The following discrepancies will cause the implementation to fail if not addressed.

| Item | Plan Expectation | Actual Phase 7 Output | Action Required |
|------|------------------|-----------------------|-----------------|
| **Plants File** | `plants_sql.parquet` | `plants_searchable_11711.parquet` | Update plan to match actual filename |
| **Organisms File** | `organisms_sql.parquet` | `organisms_searchable.parquet` | Update plan to match actual filename |
| **Fungi File** | `fungi_sql.parquet` | `fungi_searchable.parquet` | Update plan to match actual filename |
| **Data Directory** | `./shipley_checks/stage3` | `shipley_checks/stage4/phase7_output` | Update default `DATA_DIR` in `main.rs` |

### 3. Recommendations

#### A. Configuration Management
**Current**: Hardcoded paths and raw `std::env::var`.
**Recommendation**: Introduce a typed configuration struct (e.g., using `config` crate or `clap` for CLI args) to manage:
-   Data directory path
-   Server port
-   Cache settings (TTL, capacity)
-   Worker thread pool size

#### B. Error Handling
**Current**: Basic `(StatusCode, String)` tuples.
**Recommendation**: Implement a custom `AppError` type deriving `thiserror` and implementing `IntoResponse`. This allows for:
-   Structured error logging
-   Consistent error responses (JSON)
-   Better separation of internal vs. external error messages

#### C. API Documentation
**Current**: None.
**Recommendation**: Add `utoipa` or similar to generate OpenAPI (Swagger) documentation automatically from Rust structs. This is crucial for the frontend team (Phase 13).

#### D. Graceful Shutdown
**Current**: Not explicitly detailed.
**Recommendation**: Implement `signal::ctrl_c` handling to gracefully shut down the Axum server and flush any pending logs/metrics.

### 4. Verification of Existing Code
-   **`GuildScorer`**: Confirmed to be thread-safe. It loads data into `Arc<LazyFrame>` or similar read-only structures.
-   **`Rayon`**: The existing `score_guild_parallel` uses Rayon. Note that running Rayon inside `spawn_blocking` is fine, but ensure the global Rayon thread pool is configured correctly or use a local thread pool to avoid contention if load is high.

## Conclusion

The plan is solid but needs minor adjustments to align with the actual data pipeline outputs. Proceed with Phase 8 implementation after updating the file paths in the plan.
