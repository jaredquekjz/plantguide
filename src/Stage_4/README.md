# Stage 4: Guild Builder Pipeline Scripts

This directory contains the production scripts for the Guild Builder pipeline that computes plant compatibility scores based on multi-trophic ecological networks.

---

## Fungal Guild Extraction

**Primary Production Script:**

### `01_extract_fungal_guilds_hybrid.py` ⭐
**Approach**: FungalTraits PRIMARY + FunGuild FALLBACK (research-validated)
**Output**: `data/stage4/plant_fungal_guilds_hybrid.parquet`
**Coverage**: 11,680 plants, 5 guilds, 99.4% FungalTraits + 0.6% FunGuild
**Reference**: Tanunchai et al. (2022) Microbial Ecology

**Usage**:
```bash
python src/Stage_4/01_extract_fungal_guilds_hybrid.py
```

**Comparison Scripts:**

### `01b_extract_fungal_guilds.py`
**Approach**: FungalTraits only
**Purpose**: Comparison baseline for hybrid validation

### `01c_extract_fungal_guilds_funguild_primary.py`
**Approach**: FunGuild primary (confidence-filtered)
**Purpose**: Comparison alternative for hybrid validation

---

## Guild Builder Pipeline

### `01_extract_organism_profiles.py`
**Purpose**: Extract direct plant-organism interactions from GloBI
**Outputs**: Pollinators, herbivores, pathogens, flower visitors
**Input**: GloBI interactions dataset
**Output**: Organism profile parquets

### `02_build_multitrophic_network.py`
**Purpose**: Construct predator-prey food web networks
**Outputs**: Multi-trophic network for indirect effects
**Input**: Flower visitor data
**Output**: Network edge lists

### `03_compute_cross_plant_benefits.py`
**Purpose**: Compute beneficial predator relationships between plants
**Outputs**: Cross-plant biocontrol benefits
**Input**: Multi-trophic networks
**Output**: Benefit matrices

### `04_compute_compatibility_matrix.py`
**Purpose**: Compute final plant-plant compatibility scores
**Outputs**: Compatibility matrix with all 16 components
**Input**: Organism profiles, fungal guilds, benefits
**Output**: `data/stage4/compatibility_matrix_full.parquet`

**Components**:
- 1-8: Non-fungal (pollinators, herbivores, pathogens, etc.)
- 9-16: Fungal guilds (pathogenic, mycorrhizal, biocontrol, endophytic, saprotrophic, multi-guild, synergy)

### `05_validate_compatibility_matrix.py`
**Purpose**: Validate compatibility scores and component contributions
**Outputs**: Validation statistics and diagnostics
**Input**: Compatibility matrix
**Output**: Validation reports

---

## Pipeline Execution Order

```bash
# 1. Extract fungal guilds (HYBRID APPROACH)
python src/Stage_4/01_extract_fungal_guilds_hybrid.py

# 2. Extract organism profiles
python src/Stage_4/01_extract_organism_profiles.py

# 3. Build multi-trophic network (if needed)
python src/Stage_4/02_build_multitrophic_network.py

# 4. Compute cross-plant benefits (if needed)
python src/Stage_4/03_compute_cross_plant_benefits.py

# 5. Compute compatibility matrix
python src/Stage_4/04_compute_compatibility_matrix.py

# 6. Validate results
python src/Stage_4/05_validate_compatibility_matrix.py
```

---

## Key Outputs

**Fungal Guilds** (USE THIS):
- `data/stage4/plant_fungal_guilds_hybrid.parquet`

**Compatibility Matrix**:
- `data/stage4/compatibility_matrix_full.parquet`

**Organism Profiles**:
- `data/stage4/plant_pollinators.parquet`
- `data/stage4/plant_herbivores.parquet`
- `data/stage4/plant_pathogens.parquet`

---

## Documentation

See `results/summaries/phylotraits/Stage_4/` for detailed documentation:

- **README.md** - Documentation index
- **4.5_Fungal_Guild_Classification_Final.md** - Fungal guild implementation (comprehensive)
- **4.1_GloBI_Data_Structure_Analysis.md** - GloBI foundation
- **4.2_Implementation_Plan_DuckDB.md** - Pipeline architecture
- **4.3_Guild_Builder_Design.md** - Compatibility framework

---

## Environment

**Python**: Use conda environment `AI`
```bash
/home/olier/miniconda3/envs/AI/bin/python
```

**Requirements**:
- DuckDB (mandated for all data operations)
- Pandas (minimal use)
- NumPy

**Performance**:
- All scripts use DuckDB for fast parquet operations
- Parallel processing where applicable
- Runtime: seconds to minutes (11,680 plants)

---

**Last Updated**: 2025-11-01
