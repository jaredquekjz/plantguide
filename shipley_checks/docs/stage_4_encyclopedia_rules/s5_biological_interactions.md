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

| Data | Source File | Key Columns |
|------|-------------|-------------|
| Pollinators, Herbivores, Pathogens | `organism_profiles_11711.parquet` | `pollinators`, `herbivores`, `pathogens` |
| Fungal associations | `fungi_searchable.parquet` | `fungus_taxon`, `is_pathogenic`, `is_mycorrhizal`, etc. |

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

## Pathogen Associations

**Data source**: `pathogens` column (from `organism_profiles_11711.parquet`)

**Extraction logic**:
- Relationships: `pathogenOf`, `parasiteOf`, `hasHost` (Fungi only)
- Filtered to **exclude Plantae and Animalia** (microbial only)
- Excludes: Generic names (Fungi, Bacteria, Viruses, Insecta, Plantae, Animalia)

**What it includes**:
- Fungal pathogens (rusts, mildews, rots)
- Bacterial pathogens
- Viral pathogens
- Oomycetes (water moulds)
- Microbial parasites

### Output Format

```markdown
**Pathogens**: 5 taxa documented
- Erysiphe spp. (powdery mildew)
- Puccinia spp. (rust)
- Botrytis cinerea (grey mould)

**Disease Risk**: Moderate - monitor in humid conditions
```

---

## Fungal Associations

**Data source**: `fungi_searchable.parquet`

### Pathogenic Fungi

| Column | Meaning |
|--------|---------|
| `is_pathogenic = true` | Harmful fungal association |
| `functional_role = 'harmful'` | Disease-causing |

**Output**:
```markdown
**Fungal Diseases**: 3 documented
- Puccinia (rust) - leaf spots, yellow pustules
- Entyloma (leaf smut) - dark lesions
- Coleosporium (rust) - orange spores
```

### Beneficial Fungi

| Column | Meaning |
|--------|---------|
| `is_mycorrhizal = true` | Mutualistic root association |
| `is_amf = true` | Arbuscular mycorrhizal (most herbs) |
| `is_emf = true` | Ectomycorrhizal (trees, some shrubs) |
| `is_endophytic = true` | Lives in plant tissue (often protective) |

**Output**:
```markdown
**Mycorrhizal Associations**: 2 documented
- Glomus spp. (AMF) - aids phosphorus uptake
- Rhizophagus irregularis (AMF) - drought tolerance

**Garden Note**: Avoid excessive tillage to preserve mycorrhizal networks
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

### Organism Profiles (organism_profiles_11711.parquet)

| Column | Description |
|--------|-------------|
| `plant_wfo_id` | Plant identifier |
| `pollinators` | List of pollinator taxa (GloBI `pollinates`) |
| `pollinator_count` | Number of pollinator taxa |
| `herbivores` | List of herbivore taxa |
| `herbivore_count` | Number of herbivore taxa |
| `pathogens` | List of pathogen taxa (includes parasites) |
| `pathogen_count` | Number of pathogen taxa |
| `flower_visitors` | Broader list (includes non-pollinators) |

### Fungi (fungi_searchable.parquet)

| Column | Description |
|--------|-------------|
| `plant_wfo_id` | Plant identifier |
| `fungus_taxon` | Fungus name |
| `guild_category` | pathogenic / mycorrhizal / saprotrophic / etc. |
| `functional_role` | harmful / beneficial / neutral / biocontrol |
| `is_pathogenic` | Boolean: causes disease |
| `is_mycorrhizal` | Boolean: mutualistic root association |
| `is_amf` | Boolean: arbuscular mycorrhizal |
| `is_emf` | Boolean: ectomycorrhizal |
| `is_endophytic` | Boolean: lives within plant tissue |

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
