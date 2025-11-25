# S5: Biological Interactions Rules

Rules for generating the biological interactions section from GloBI (Global Biotic Interactions) data.

## Scientific Foundation

**Data Source**: GloBI database - species-level interaction records

**Interaction Types**:
- Pollinators (strict definition)
- Herbivores (invertebrate and vertebrate)
- Pathogens (plant-associated diseases)
- Natural enemies (predators/parasitoids of herbivores)

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

| Column | Description |
|--------|-------------|
| `pollinators` | Count/list of strict pollinator taxa |
| `flower_visitors` | Count/list of all flower visitors (not used for M7) |
| `herbivores_invertebrate` | Invertebrate herbivore count/list |
| `herbivores_vertebrate` | Vertebrate herbivore count/list |
| `pathogens` | Pathogen count/list |
| `parasites` | Parasite count/list |
| `predators_of_herbivores` | Natural enemy count/list |

**Note**: GloBI data coverage varies by species. Well-studied species have more complete interaction records.
