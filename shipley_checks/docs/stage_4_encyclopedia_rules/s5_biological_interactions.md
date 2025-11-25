# S5: Biological Interactions Rules

Rules for generating the biological interactions section from GloBI (Global Biotic Interactions) data.

## Scientific Foundation

**Data Sources**:
- GloBI database - species-level interaction records (organisms_searchable.parquet)
- FungalTraits + FunGuild - fungal guild classifications (fungi_searchable.parquet)
- Entomopathogen database - insect-killing fungi (insect_fungal_parasites_11711.parquet)

**Interaction Types**:
- Pollinators (strict definition)
- Herbivores (invertebrate and vertebrate)
- Pathogens (plant-associated diseases)
- Natural enemies (predators/parasitoids of herbivores)
- Beneficial biocontrol organisms
- Beneficial fungi (mycorrhizal, entomopathogenic, mycoparasitic)

---

## M7: Pollinator Support

**What it measures**: Diversity of pollinator taxa visiting the plant

**Data source**: GloBI `pollinators` column (strict definition only, not `flower_visitors` which includes non-pollinators)

### Interpretation

| Count | Rating | Interpretation |
|-------|--------|----------------|
| > 20 | Very High | Major pollinator resource |
| 11-20 | High | Good pollinator support |
| 5-10 | Moderate | Moderate support |
| 1-4 | Low | Limited pollinator value |
| 0 | Very Low | Not documented as pollinator plant |

### Output Format

```markdown
**Pollinator Support**: High (15 taxa recorded)
Documented pollinators include: Apis mellifera, Bombus terrestris, various Syrphidae
```

---

## Herbivore Associations

**What it measures**: Documented herbivore interactions

### Categories

| Type | Examples |
|------|----------|
| Invertebrate herbivores | Lepidoptera larvae, aphids, leaf beetles |
| Vertebrate herbivores | Deer, rabbits, birds |

### Risk Interpretation

| Herbivore Count | Risk Level | Advice |
|-----------------|------------|--------|
| > 15 | High | Monitor closely; may need protection |
| 5-15 | Moderate | Occasional damage likely |
| < 5 | Low | Limited pest pressure documented |

### Output Format

```markdown
**Herbivore Associations**: 12 taxa documented
- **Invertebrates**: Various Lepidoptera, aphids (Aphididae)
- **Vertebrates**: Deer, rabbits
- **Risk**: Moderate - occasional damage likely; consider netting in deer areas
```

---

## Pathogen Associations

**What it measures**: Documented plant pathogens affecting the species

### Categories

| Type | Examples |
|------|----------|
| Fungal | Powdery mildew, rust, root rot |
| Bacterial | Bacterial leaf spot, crown gall |
| Viral | Mosaic virus, ring spot |

### Output Format

```markdown
**Pathogen Susceptibility**: 5 pathogens documented
- Powdery mildew (Erysiphe spp.) - common in humid conditions
- Rust (Puccinia spp.) - monitor in wet seasons
- **Prevention**: Good air circulation, avoid overhead watering
```

---

## Natural Enemy Support

**What it measures**: Predators and parasitoids associated with the plant's herbivore community

### Garden Value

| Enemy Count | Interpretation |
|-------------|----------------|
| > 10 | Excellent biocontrol potential |
| 5-10 | Good natural pest control |
| < 5 | Limited natural enemy support |

### Output Format

```markdown
**Natural Enemy Support**: High (8 predator/parasitoid taxa)
Supports: Ladybirds (Coccinellidae), hoverflies (Syrphidae), parasitic wasps
**Garden Value**: Excellent for integrated pest management
```

---

## Beneficial Biocontrol Organisms (Predators of Herbivores)

**Data source**: `herbivore_predators_11711.parquet` (from Phase 0, Script 4)

**Extraction method**:
```sql
-- From full GloBI: find animals that EAT herbivores on our plants
WHERE interactionTypeName IN ('eats', 'preysOn')
AND targetTaxonName IN (herbivores found on our 11,711 plants)
```

**Coverage**: 1,142 herbivore → predator mappings

**What it measures**: Animals documented in GloBI as eating/preying on herbivores that attack our plants

### Examples

| Herbivore | Predators |
|-----------|-----------|
| Abagrotis alternata (moth) | Bats: Corynorhinus townsendii, Myotis spp., Eptesicus fuscus |
| Abraxas sylvata (moth) | Formica rufa (wood ant) |
| Acanalonia conica (planthopper) | Spiders, bats, assassin bugs |

### Categories

| Type | Examples | Garden Benefit |
|------|----------|----------------|
| Insectivorous bats | Myotis, Eptesicus | Consume night-flying moths |
| Predatory insects | Ladybirds, lacewings, ground beetles | Consume aphids, caterpillars |
| Parasitoid wasps | Ichneumonidae, Braconidae | Parasitise caterpillars, aphids |
| Spiders | Various families | Generalist predators |
| Predatory ants | Formica spp. | Colony-based predation |

### Algorithm (M3 Metric)

The GuildBuilder uses pairwise analysis:
1. Get herbivores from plant A
2. Look up known predators from `herbivore_predators_11711.parquet`
3. Check if those predators are present on plant B (from organism profiles)
4. Count matches as biocontrol mechanisms

### Output Format

```markdown
**Biocontrol Network**:
- Herbivores on this plant: 8 taxa
- Known predators of those herbivores: 15 taxa
- Predators present in guild: 5 taxa (matched)
**IPM Value**: High - guild contains predators of this plant's pests
```

**Note**: The `is_biocontrol` flag in `organisms_searchable.parquet` is legacy/misleading - it labels all plant-associated animals, not verified predators. Use the lookup table instead.

---

## Beneficial Fungi

**Data source**: `fungi_searchable.parquet`

**Categories**:

### Mycorrhizal Fungi (Mutualistic)

| Type | Column | Count | Benefit |
|------|--------|-------|---------|
| Arbuscular mycorrhizal (AMF) | `is_amf` | 439 | Phosphorus uptake, drought tolerance |
| Ectomycorrhizal (EMF) | `is_emf` | 942 | Nutrient uptake, disease resistance |
| General mycorrhizal | `is_mycorrhizal` | 1,381 | Root health, nutrient exchange |

**Output**:
```markdown
**Mycorrhizal Associations**: 5 fungi documented
- Arbuscular mycorrhizal: Glomus, Claroideoglomus
- Ectomycorrhizal: Cortinarius, Russula
**Garden Note**: Avoid disturbing soil to preserve mycorrhizal networks
```

### Entomopathogenic Fungi (Pest-killing)

**Data source**: `insect_fungal_parasites_11711.parquet`

**What they do**: Kill herbivorous insects that feed on the plant

| Type | Examples | Target Pests |
|------|----------|--------------|
| Entomopathogenic | Beauveria, Metarhizium, Cordyceps | Aphids, caterpillars, beetles |
| Counts | `is_entomopathogen` | 620 fungi |

**Output**:
```markdown
**Entomopathogenic Fungi**: 8 insect-killing fungi documented
- Beauveria bassiana - kills aphids, whiteflies
- Metarhizium anisopliae - kills beetles, caterpillars
**IPM Potential**: High - natural pest control from associated fungi
```

### Mycoparasitic Fungi (Disease-fighting)

**What they do**: Attack and kill plant-pathogenic fungi

| Type | Examples | Targets |
|------|----------|---------|
| Mycoparasites | Trichoderma, Clonostachys | Root rot fungi, mildews |
| Count | `is_mycoparasite` | 508 fungi |

**Output**:
```markdown
**Mycoparasites**: 3 fungi documented
- Trichoderma spp. - attacks root rot pathogens
**Disease Suppression**: Good natural protection from pathogenic fungi
```

### Endophytic Fungi

**What they do**: Live within plant tissues without causing disease; often protective

| Type | Benefits |
|------|----------|
| Protective endophytes | Produce compounds deterring herbivores |
| Stress-tolerance endophytes | Improve drought/heat tolerance |
| Count | `is_endophytic` | 4,907 associations |

**Output**:
```markdown
**Endophytic Fungi**: 15 documented
**Function**: May provide pest deterrence and stress tolerance
```

---

## Integrated Pest/Disease Risk Assessment

Combine herbivore and pathogen data:

### Risk Matrix

| Herbivores | Pathogens | Overall Risk | Advice |
|------------|-----------|--------------|--------|
| High | High | Very High | Regular monitoring essential |
| High | Low | Moderate-High | Focus on physical pest barriers |
| Low | High | Moderate-High | Focus on disease prevention |
| Low | Low | Low | Generally trouble-free |

---

## Output Format (Complete Section)

```markdown
## Biological Interactions

### Pollinator Value
**Rating**: High (15 taxa)
Key pollinators: Bumblebees, honeybees, hoverflies

### Wildlife Associations
**Herbivores**: 8 taxa documented (Moderate pressure)
- Caterpillars (various Lepidoptera)
- Aphids
**Natural Enemies**: 6 taxa (Good biocontrol potential)
- Ladybirds, parasitic wasps

### Pest & Disease Risk
**Pathogens**: 3 documented
- Powdery mildew (humid conditions)
- Honey fungus (waterlogged sites)
**Overall Risk**: Moderate
**Management**: Good air circulation, avoid waterlogging
```

---

## Data Column Reference

### Organism Profiles (organism_profiles_11711.parquet)

| Column | Description |
|--------|-------------|
| `plant_wfo_id` | Plant identifier |
| `pollinators` | List of strict pollinator taxa |
| `herbivores` | List of herbivore taxa |
| `pathogens` | List of pathogen taxa |
| `flower_visitors` | List of flower visitors (broader than pollinators) |
| `predators_hasHost` | Animals with hasHost relationship to plant (legacy) |
| `predators_interactsWith` | Animals with interactsWith relationship (legacy) |
| `predators_adjacentTo` | Animals with adjacentTo relationship (legacy) |

### Biocontrol Lookup (herbivore_predators_11711.parquet)

| Column | Description |
|--------|-------------|
| `herbivore` | Herbivore taxon name |
| `predators` | List of known predators (from GloBI eats/preysOn) |
| `predator_count` | Number of known predators |

### Pathogen Antagonists (pathogen_antagonists_11711.parquet)

| Column | Description |
|--------|-------------|
| `pathogen` | Pathogen taxon name |
| `antagonists` | List of antagonists (from GloBI eats/preysOn/parasiteOf/pathogenOf) |
| `antagonist_count` | Number of known antagonists |

### Fungi (fungi_searchable.parquet)

| Column | Description |
|--------|-------------|
| `plant_wfo_id` | Plant identifier |
| `fungus_taxon` | Fungus name |
| `guild_type` | Primary guild classification |
| `guild_category` | Functional category |
| `functional_role` | beneficial/pathogenic/neutral |
| `is_mycorrhizal` | Boolean: any mycorrhizal association |
| `is_amf` | Boolean: arbuscular mycorrhizal |
| `is_emf` | Boolean: ectomycorrhizal |
| `is_pathogenic` | Boolean: plant pathogen |
| `is_biocontrol` | Boolean: biocontrol fungus |
| `is_entomopathogen` | Boolean: insect-killing fungus |
| `is_mycoparasite` | Boolean: fungus-killing fungus |
| `is_endophytic` | Boolean: endophyte |
| `is_saprotrophic` | Boolean: decomposer |

### Entomopathogen Links (insect_fungal_parasites_11711.parquet)

| Column | Description |
|--------|-------------|
| `herbivore` | Herbivore insect name |
| `herbivore_family` | Insect family |
| `herbivore_order` | Insect order |
| `entomopathogenic_fungi` | List of fungi that kill this herbivore |
| `fungal_parasite_count` | Number of entomopathogenic fungi |

**Note**: GloBI and fungal data coverage varies by species. Well-studied species have more complete interaction records.
