# S5: Biological Interactions Rules

Rules for generating the biological interactions section of static encyclopedia articles.

## Scope

**Static encyclopedia** shows interactions documented for THIS plant:
- Pollinators visiting this plant
- Herbivores attacking this plant
- Pathogens/parasites affecting this plant
- Fungi associated with this plant (pathogenic and beneficial)

**Dynamic features** (future SQL-based UI, not in static encyclopedia):
- "Care plan" generation using predator lookups
- Companion plant suggestions based on shared biocontrol agents

---

## Data Sources

**Source parquets** (Phase 0 output, used by GuildBuilder):

| Data | Source File | Location |
|------|-------------|----------|
| Pollinators, Herbivores, Predators, Fungivores | `organism_profiles_11711.parquet` | `shipley_checks/stage4/phase0_output/` |
| Pathogenic fungi, Mycorrhizae, Beneficial fungi | `fungal_guilds_hybrid_11711.parquet` | `shipley_checks/stage4/phase0_output/` |

**Key columns by parquet:**

| organism_profiles_11711.parquet | fungal_guilds_hybrid_11711.parquet |
|--------------------------------|-----------------------------------|
| `pollinators`, `pollinator_count` | `pathogenic_fungi`, `pathogenic_fungi_count` |
| `herbivores`, `herbivore_count` | `amf_fungi`, `amf_fungi_count` |
| `pathogens`, `pathogen_count` | `emf_fungi`, `emf_fungi_count` |
| `predators_hasHost`, etc. | `mycoparasite_fungi`, `mycoparasite_fungi_count` |
| `fungivores_eats`, `fungivores_eats_count` | `entomopathogenic_fungi`, `entomopathogenic_fungi_count` |
| `flower_visitors`, `visitor_count` | `endophytic_fungi`, `saprotrophic_fungi` |

**Note on pathogen columns:**
- `pathogens` (organism_profiles): Species-level pathogen names from GloBI (63% coverage)
- `pathogenic_fungi` (fungal_guilds): Genus-level fungal pathogens from FungalTraits/FunGuild (62% coverage)

---

## M7: Pollinator Support

**Data source**: `pollinators` column (strict GloBI `pollinates` relationship)

### Interpretation

| Count | Rating | Interpretation |
|-------|--------|----------------|
| > 20 | Very High | Major pollinator resource |
| 11-20 | High | Good pollinator support |
| 5-10 | Moderate | Moderate support |
| 1-4 | Low | Limited pollinator value |
| 0 | No data | Not documented (may still be visited) |

### Output Format

```markdown
**Pollinators**: 15 taxa documented
- Apis mellifera (honeybee)
- Bombus terrestris (buff-tailed bumblebee)
- Various Syrphidae (hoverflies)
```

---

## Herbivore Associations

**Data source**: `herbivores` column (from `matched_herbivores_per_plant.parquet`)

**Extraction logic**:
- Relationships: `eats`, `preysOn`, `hasHost`
- Filtered to **invertebrates only**: Insecta, Arachnida, Chilopoda, Diplopoda, Malacostraca, Gastropoda, Bivalvia
- Excludes: pollinators, bee families, predator families

**What it includes**:
- True herbivores (leaf-eaters, sap-suckers, root-feeders)
- Invertebrate parasites (gall-formers, leaf-miners via `hasHost`)

### Risk Interpretation

| Count | Risk Level | Advice |
|-------|------------|--------|
| > 15 | High | Multiple pest species; monitor closely |
| 5-15 | Moderate | Some pest pressure expected |
| < 5 | Low | Few documented pests |
| 0 | No data | Not well-studied or pest-free |

### Output Format

```markdown
**Herbivores**: 8 taxa documented
- Operophtera brumata (winter moth) - caterpillars on leaves
- Myzus persicae (peach-potato aphid) - sap feeder
- Otiorrhynchus sulcatus (vine weevil) - root damage

**Pest Pressure**: Moderate
```

---

## Pathogen/Disease Associations

**Data source**: `pathogenic_fungi`, `pathogenic_fungi_count` from `fungal_guilds_hybrid_11711.parquet`

**Extraction logic** (Phase 0):
- Relationships: `pathogenOf`, `parasiteOf`, `hasHost`
- Filtered to fungal pathogens via FungalTraits/FunGuild guild classification
- Includes host-specific pathogens in separate column

**What it includes**:
- Fungal pathogens (rusts, mildews, rots, smuts)
- Oomycetes (water moulds)
- Other microbial plant parasites

### Output Format

```markdown
**Diseases**: 5 species observed
- Erysiphe spp. (powdery mildew)
- Puccinia spp. (rust)
- Botrytis cinerea (grey mould)

**Disease Risk**: Moderate - monitor in humid conditions
```

---

## Fungal Associations

**Data source**: `fungal_guilds_hybrid_11711.parquet` (Phase 0 output)

### Beneficial Fungi (Mycorrhizae)

| Column | Meaning |
|--------|---------|
| `amf_fungi`, `amf_fungi_count` | Arbuscular mycorrhizal fungi (most herbs, grasses) |
| `emf_fungi`, `emf_fungi_count` | Ectomycorrhizal fungi (trees, some shrubs) |
| `endophytic_fungi`, `endophytic_fungi_count` | Live in plant tissue (often protective) |
| `saprotrophic_fungi`, `saprotrophic_fungi_count` | Decomposers in soil around plant |

**Output**:
```markdown
**Mycorrhizal Associations**: 2 species observed
- Glomus spp. (AMF) - aids phosphorus uptake
- Rhizophagus irregularis (AMF) - drought tolerance

**Garden Note**: Avoid excessive tillage to preserve mycorrhizal networks
```

### Biocontrol Fungi

| Column | Meaning |
|--------|---------|
| `mycoparasite_fungi`, `mycoparasite_fungi_count` | Fungi that attack plant pathogens |
| `entomopathogenic_fungi`, `entomopathogenic_fungi_count` | Fungi that kill pest insects |

**Output**:
```markdown
**Biocontrol Fungi**:
- 1 mycoparasitic fungus observed (attacks plant diseases)
- 2 insect-killing fungi observed (natural pest control)
```

---

## Integrated Output Format

```markdown
## Biological Interactions

### Pollinators
**Rating**: High (15 taxa)
Key visitors: Bumblebees, honeybees, hoverflies

### Herbivores
**Documented**: 8 taxa
- Winter moth, vine weevil, aphids
**Pest Pressure**: Moderate

### Diseases
**Fungal**: Powdery mildew, rust
**Other pathogens**: 2 bacterial/viral
**Disease Risk**: Moderate in humid conditions

### Beneficial Associations
**Mycorrhizal**: AMF associations documented
**Advice**: Maintain soil health for natural disease resistance
```

---

## Data Column Reference

### Organism Profiles (`organism_profiles_11711.parquet`)

Location: `shipley_checks/stage4/phase0_output/`

| Column | Description |
|--------|-------------|
| `plant_wfo_id` | Plant identifier |
| `pollinators` | List of pollinator species (GloBI `pollinates`) |
| `pollinator_count` | Number of pollinator species |
| `herbivores` | List of pest species (feeding on or parasitizing plant) |
| `herbivore_count` | Number of pest species |
| `pathogens` | List of pathogen species (GloBI `pathogenOf`/`parasiteOf`) |
| `pathogen_count` | Number of pathogen species |
| `flower_visitors` | Broader list (includes non-pollinators) |
| `visitor_count` | Number of flower visitors |
| `predators_hasHost` | Animals with hasHost relationship to plant |
| `predators_hasHost_count` | Count of hasHost animals |
| `predators_interactsWith` | Animals with interactsWith relationship |
| `predators_interactsWith_count` | Count of interactsWith animals |
| `predators_adjacentTo` | Animals with adjacentTo relationship |
| `predators_adjacentTo_count` | Count of adjacentTo animals |
| `fungivores_eats` | Animals observed eating fungi |
| `fungivores_eats_count` | Number of fungus-eating animals |

### Fungi (`fungal_guilds_hybrid_11711.parquet`)

Location: `shipley_checks/stage4/phase0_output/`

| Column | Description |
|--------|-------------|
| `plant_wfo_id` | Plant identifier |
| `pathogenic_fungi` | List of disease-causing fungi |
| `pathogenic_fungi_count` | Number of pathogenic fungi |
| `amf_fungi` | Arbuscular mycorrhizal fungi list |
| `amf_fungi_count` | Number of AMF species |
| `emf_fungi` | Ectomycorrhizal fungi list |
| `emf_fungi_count` | Number of EMF species |
| `mycoparasite_fungi` | Fungi that attack other fungi |
| `mycoparasite_fungi_count` | Number of mycoparasitic fungi |
| `entomopathogenic_fungi` | Fungi that kill insects |
| `entomopathogenic_fungi_count` | Number of insect-killing fungi |
| `endophytic_fungi` | Fungi living within plant tissue |
| `saprotrophic_fungi` | Decomposer fungi |

---

## Not Included in Static Encyclopedia

The following are used for **guild scoring** and **dynamic care plans**, not static articles:

| Data | Purpose | Used By |
|------|---------|---------|
| `herbivore_predators_11711.parquet` | Herbivore → known predators | M3 metric, SQL care plan |
| `insect_fungal_parasites_11711.parquet` | Herbivore → entomopathogenic fungi | M3 metric, SQL care plan |
| `pathogen_antagonists_11711.parquet` | Pathogen → antagonist organisms | M4 metric, SQL care plan |

These enable future UI features like "Generate care plan" which would:
1. Look up predators of this plant's herbivores
2. Find companion plants that host those predators
3. Suggest biocontrol-optimized planting combinations

---

## Known Issues / Future Investigation

### Erroneous `is_biocontrol` flag in `organisms_searchable.parquet`

**Location**: `shipley_checks/stage4/phase7_output/organisms_searchable.parquet`

**Problem**: The `is_biocontrol` boolean flag incorrectly labels ALL animals from `predators_hasHost`, `predators_interactsWith`, `predators_adjacentTo` columns as biocontrol agents.

**Reality**: These columns contain animals with various relationships TO THE PLANT (hasHost, interactsWith, adjacentTo) - NOT predators of herbivores. They include herbivores, commensals, and incidental visitors.

**Source of error**: `Phase_7_datafusion/convert_organisms_for_sql.R` lines 119-120:
```r
is_biocontrol = interaction_type %in% c("predators_hasHost", "predators_interactsWith",
                                         "predators_adjacentTo"),
```

**Correct biocontrol data**: Use `herbivore_predators_11711.parquet` which contains actual predator-prey relationships extracted via GloBI `eats`/`preysOn`.

**Action needed**: When refining SQL engine, either:
1. Remove misleading `is_biocontrol` column from organisms_searchable
2. Or rename to `is_plant_associated_animal` to reflect actual meaning
3. Add proper biocontrol column derived from herbivore_predators lookup
