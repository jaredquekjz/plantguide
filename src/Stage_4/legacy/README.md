# Stage 4 Legacy Scripts

This folder contains scripts that are no longer part of the active Stage 4 pipeline but are preserved for reference.

---

## Archived Scripts

### `guild_builder_prototype.py`
**Status**: Superseded by modular pipeline
**Date**: 2025-10-31
**Reason**: Early monolithic prototype replaced by 01-05 pipeline scripts

### `analyze_guild_coverage.py`
**Status**: One-off analysis script
**Date**: 2025-11-01
**Reason**: Created for session analysis, coverage now documented in 4.5_Fungal_Guild_Classification_Final.md

### `extract_globi_interactions_final_dataset.py`
**Status**: Data preparation script
**Date**: 2025-10-31
**Reason**: Not documented in current pipeline; GloBI data already prepared

---

## Active Pipeline

See parent directory for current pipeline scripts:

**Fungal Guild Extraction:**
- `01_extract_fungal_guilds_hybrid.py` (PRODUCTION)
- `01b_extract_fungal_guilds.py` (FungalTraits only)
- `01c_extract_fungal_guilds_funguild_primary.py` (FunGuild only)

**Pipeline Components:**
- `01_extract_organism_profiles.py`
- `02_build_multitrophic_network.py`
- `03_compute_cross_plant_benefits.py`
- `04_compute_compatibility_matrix.py`
- `05_validate_compatibility_matrix.py`

---

**Archived**: 2025-11-01
