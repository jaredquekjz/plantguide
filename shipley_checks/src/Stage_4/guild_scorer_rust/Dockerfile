# Phase 8.7: Dockerfile for API Server
#
# Multi-stage build for minimal production image

# Stage 1: Build
FROM rust:latest AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy manifests from guild_scorer_rust
COPY shipley_checks/src/Stage_4/guild_scorer_rust/Cargo.toml \
     shipley_checks/src/Stage_4/guild_scorer_rust/Cargo.lock ./

# Copy source code
COPY shipley_checks/src/Stage_4/guild_scorer_rust/src ./src

# Build release binary with api feature
RUN cargo build --release --features api --bin api_server

# Stage 2: Runtime - use same debian base as rust:latest to match glibc
FROM debian:trixie-slim

# Install runtime dependencies (curl for healthcheck)
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3t64 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1000 appuser

# WORKDIR at root - the code expects shipley_checks/... paths
WORKDIR /

# Copy binary from builder
COPY --from=builder /build/target/release/api_server /app/api_server

# Create expected directory structure for calibration files
# The GuildScorer looks for: shipley_checks/stage4/phase5_output/...
RUN mkdir -p /shipley_checks/stage4/phase5_output \
             /shipley_checks/stage4/phase7_output \
             /shipley_checks/stage4/phase0_output

# Copy calibration files
COPY shipley_checks/stage4/phase5_output/normalization_params_7plant.json \
     /shipley_checks/stage4/phase5_output/
COPY shipley_checks/stage4/phase5_output/normalization_params_2plant.json \
     /shipley_checks/stage4/phase5_output/
COPY shipley_checks/stage4/phase5_output/csr_percentile_calibration_global.json \
     /shipley_checks/stage4/phase5_output/

# Copy Phase 7 parquet data (for DataFusion query engine)
COPY shipley_checks/stage4/phase7_output /shipley_checks/stage4/phase7_output

# Copy Phase 0 data (for GuildScorer data loading)
COPY shipley_checks/stage4/phase0_output /shipley_checks/stage4/phase0_output

# Copy Phase 4 data (plants dataset)
COPY shipley_checks/stage4/phase4_output /shipley_checks/stage4/phase4_output

# Copy phylogenetic data (for M1 Faith's PD calculation)
COPY data/stage1/phlogeny /data/stage1/phlogeny

# Set ownership
RUN chown -R appuser:appuser /app /shipley_checks /data

USER appuser

# Environment variables
ENV DATA_DIR=/shipley_checks/stage4/phase7_output
ENV CLIMATE_TIER=tier_3_humid_temperate
ENV PORT=3000
ENV RUST_LOG=info

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Run server
CMD ["/app/api_server"]
