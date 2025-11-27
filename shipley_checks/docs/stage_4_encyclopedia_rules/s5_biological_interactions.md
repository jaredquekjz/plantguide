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

**Source parquets** (Phase 0 and Phase 7 output):

| Data | Source File | Location |
|------|-------------|----------|
| Pollinators, Herbivores, Predators (flat list) | `organisms_flat.parquet` | `shipley_checks/stage4/phase7_output/` |
| Pathogenic fungi, Mycorrhizae, Beneficial fungi | `fungi_flat.parquet` | `shipley_checks/stage4/phase7_output/` |
| Organism category labels (Kimi AI) | `kimi_gardener_labels.csv` | `data/taxonomy/` |

**Categorization**: Organism names are grouped into gardener-friendly categories using:
1. Kimi AI genus-level category labels (5996 genera mapped)
2. Fallback regex patterns for unmapped genera (defined in `unified_taxonomy.rs`)

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

Pollinators are grouped by category with counts, showing up to 3 species names per category:

```markdown
### Pollinators
**Very High** (40 taxa documented)
*Strong pollinator magnet*

- **Hoverflies** (11): Platycheirus albimanus, Eristalis pertinax, Chrysotoxum bicincta, +8 more
- **Bumblebees** (8): Bombus sylvestris, Bombus lapidarius, Bombus lucorum, +5 more
- **Flies** (3): Empis livida, Phaonia, Phaonia angelicae
- **Solitary Bees** (3): Andrena coitana, Lasioglossum fulvicorne, Andrena cineraria
- **Honey Bees** (1): Apis mellifera
```

**Rating thresholds**:
| Count | Rating | Interpretation |
|-------|--------|----------------|
| ≥100 | Exceptional | Major pollinator resource (top 10%) |
| 20-99 | Very High | Strong pollinator magnet |
| 10-19 | High | Good pollinator support |
| 5-9 | Above average | Moderate support |
| 1-4 | Typical | Average pollinator observations |
| 0 | No data | Not documented (may still be visited) |

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

Herbivores (including parasites) are grouped by category:

```markdown
### Herbivores & Parasites
**High** (19 taxa documented)
*Multiple pest species; monitor closely*

- **Other Herbivores** (15): Phaneta pauperana, Cidaria fulvata, Pseudothyatira cymatophoroides, +12 more
- **Caterpillars** (1): Grapholita tenebrosana
- **Mites** (1): Tetranychus urticae
- **Moths** (1): Malacosoma californica pluvialis
- **Scale Insects** (1): Chorizococcus
```

**Note**: "Herbivores" in GloBI include all organisms with `eats`, `preysOn`, or `hasHost` relationships to the plant, including:
- True herbivores (leaf-eaters, sap-suckers)
- Invertebrate parasites (gall-formers, leaf-miners)

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

The full biological interactions section groups organisms by category with species names:

```markdown
## Biological Interactions

*Organisms documented interacting with this plant from GloBI (Global Biotic Interactions) records.*

### Pollinators
**Very High** (40 taxa documented)
*Strong pollinator magnet*

- **Hoverflies** (11): Platycheirus albimanus, Eristalis pertinax, Chrysotoxum bicincta, +8 more
- **Bumblebees** (8): Bombus sylvestris, Bombus lapidarius, Bombus lucorum, +5 more
- **Flies** (3): Empis livida, Phaonia, Phaonia angelicae
- **Solitary Bees** (3): Andrena coitana, Lasioglossum fulvicorne, Andrena cineraria
- **Honey Bees** (1): Apis mellifera

### Herbivores & Parasites
**High** (19 taxa documented)
*Multiple pest species; monitor closely*

- **Other Herbivores** (15): Phaneta pauperana, Cidaria fulvata, +12 more
- **Caterpillars** (1): Grapholita tenebrosana
- **Mites** (1): Tetranychus urticae

### Beneficial Insects
No predator/beneficial insect records available.
*This plant may benefit from companions that attract pest predators.*

### Diseases
**Fungal Diseases**: 68 species observed
**Disease Risk**: High - Many diseases observed; avoid clustering same-disease plants
*Monitor in humid conditions; ensure good airflow*

### Beneficial Associations
**Mycorrhizal**: Non-mycorrhizal/Undocumented
- 7 endophytic fungi observed (often protective)

**Biocontrol Fungi**:
- 1 mycoparasitic fungi observed (attack plant diseases)
```

**Category sorting**: Categories are sorted by count (descending), showing the most diverse groups first.

---

## Organism Categories

The following gardener-friendly categories are used for grouping organisms:

### Pollinator Categories
| Category | Examples |
|----------|----------|
| Honey Bees | Apis mellifera |
| Bumblebees | Bombus spp. |
| Solitary Bees | Andrena, Lasioglossum, Osmia |
| Hoverflies | Syrphidae (Eristalis, Episyrphus) |
| Butterflies | Pieridae, Nymphalidae |
| Moths | Noctuidae, Geometridae |
| Wasps | Vespidae, Crabronidae |
| Flies | Non-syrphid Diptera |
| Beetles | Non-weevil Coleoptera |
| Other Pollinators | Unmatched genera |

### Herbivore/Pest Categories
| Category | Examples |
|----------|----------|
| Aphids | Myzus, Aphis, Acyrthosiphon |
| Caterpillars | Lepidoptera larvae |
| Weevils | Curculionidae |
| Leafhoppers | Cicadellidae |
| Mites | Tetranychidae |
| Scale Insects | Coccoidea |
| Beetles | Chrysomelidae, Scarabaeidae |
| Moths | Adult Lepidoptera |
| Butterflies | Adult Lepidoptera |
| Flies | Diptera |
| Other Herbivores | Unmatched genera |

### Predator/Beneficial Categories
| Category | Examples |
|----------|----------|
| Ladybugs | Coccinellidae |
| Lacewings | Chrysopidae |
| Ground Beetles | Carabidae |
| Parasitic Wasps | Braconidae, Ichneumonidae |
| Hoverflies | Syrphidae (larvae are predators) |
| Predatory Bugs | Miridae, Anthocoridae |
| Soldier Beetles | Cantharidae |
| Spiders | Araneae |
| Other Predators | Unmatched genera |

**Source**: Categories defined in `src/explanation/unified_taxonomy.rs` with Kimi AI labels from `data/taxonomy/kimi_gardener_labels.csv`.

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
