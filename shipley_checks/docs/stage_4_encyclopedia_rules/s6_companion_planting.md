# S6: Guild Potential (Companion Planting)

Static recommendations based on THIS plant's characteristics, derived from GuildBuilder metric logic. Each subsection shows the plant's guild-relevant traits and provides companion selection guidance.

**Scope**: Static encyclopedia shows individual plant contributions. Dynamic GuildBuilder does actual pairwise scoring.

**Data provenance**: Biotic interaction data (herbivores, pathogens, pollinators, fungi, predators) are derived from **GloBI (Global Biotic Interactions)** observation records. Counts reflect the number of distinct taxa with documented interactions, not interaction frequency or severity.

---

## GP1: Phylogenetic Independence (from M1)

**Data source**: `family`, `genus` columns

**Scientific basis**: Most pests and pathogens are genus- or family-specific. Phylogenetic diversity reduces shared vulnerability through dilution effect and associational resistance.

### Static Output

```markdown
**Taxonomic Position**: {family} → {genus}

**Companion Strategy**: Seek plants from different families to reduce shared pest/pathogen risk.
```

### Recommendation Rules

The GuildBuilder calculates Faith's Phylogenetic Diversity (PD) - the sum of evolutionary branch lengths connecting guild members. Higher PD = greater pest/pathogen independence.

**General principles**:
- Plants in the SAME genus share the most pests/pathogens → avoid clustering
- Plants in the SAME family share many pests/pathogens → diversify
- Plants in DIFFERENT families have fewer shared vulnerabilities
- Maximum diversity: different orders or higher taxonomic levels

### Output Format

```markdown
### Phylogenetic Independence

**Family**: {family}
**Genus**: {genus}

**Guild Recommendation**:
- Avoid clustering plants from the same genus (highest shared pest risk)
- Diversify beyond this family for reduced pathogen transmission
- Seek maximum taxonomic distance for pest dilution effect
```

### Decision Tree

```
ALWAYS:
  "Seek companions from different families to reduce shared pest/pathogen risk."
  "Avoid clustering multiple plants of the same genus."
  "Greater taxonomic distance = lower shared vulnerability."
```

---

## GP2: Growth Compatibility (from M2)

**Data source**: `C`, `S`, `R` scores (CSR strategy), `height_m`, `try_growth_form`, `EIVEres-L_complete`

**Scientific basis**: CSR strategy conflicts cause competition failures. C-C pairs compete destructively; C-S pairs may shade out S-plants unless S is shade-tolerant.

### CSR Percentile Classification

| Percentile | Classification | Meaning |
|------------|---------------|---------|
| > 75% C | High Competitor | Vigorous, resource-acquiring |
| > 75% S | High Stress-tolerator | Slow, persistent, conservative |
| > 75% R | High Ruderal | Fast, short-lived, opportunistic |
| < 75% all | Mixed/Balanced | Generalist strategy |

### Conflict Rules (from M2 logic)

**C-C Conflict** (base severity 1.0):
- Reduced to 0.2 if vine + tree (vine climbs)
- Reduced to 0.4 if tree + herb (different vertical niches)
- Reduced by height separation (>5m → 0.3×)

**C-S Conflict** (base severity 0.6):
- **Zero conflict** if S plant has EIVE-L < 3.2 (shade-adapted)
- **High conflict (0.9)** if S plant has EIVE-L > 7.47 (sun-loving)
- Reduced if height difference > 8m

**C-R Conflict** (base severity 0.8):
- Reduced to 0.24 if height difference > 5m (R exploits gaps)

**R-R Conflict** (low severity 0.3):
- Both short-lived; succession planning needed

### Output Format

```markdown
### Growth Compatibility

**CSR Profile**: C: {c_pct}% | S: {s_pct}% | R: {r_pct}%
**Strategy**: {dominant_strategy}
**Height**: {height_m}m
**Light Preference**: EIVE-L {light_pref}

**Guild Recommendations**:
- {strategy-specific guidance}
- {height-specific guidance}
- {light-specific guidance}
```

### Decision Tree

```
IF C > 75%:
  IF height > 5m:
    "Canopy competitor. Understory shade-tolerant plants benefit from protection."
  ELSE:
    "Vigorous mid-layer competitor. Give space; avoid other C-dominant at same height."

IF S > 75%:
  IF EIVE-L < 3.2:
    "Shade-tolerant stress-tolerator. Thrives under canopy trees."
  ELSE IF EIVE-L > 7.47:
    "Sun-loving stress-tolerator. Avoid being shaded by C-dominant plants."
  ELSE:
    "Flexible stress-tolerator. Pairs well with most strategies."

IF R > 75%:
  "Short-lived opportunist. Use for gap-filling; pair with longer-lived plants for succession."

IF balanced (no > 75%):
  "Generalist. Compatible with most strategies."
```

---

## GP3: Pest Control Contribution (from M3)

**Data source** (GloBI observations):
- `herbivores` list, `herbivore_count` - taxa observed feeding on this plant (eats, preysOn, hasHost)
- `flower_visitors`, `visitor_count` - taxa observed visiting flowers
- `predators_hasHost`, `predators_interactsWith`, `predators_adjacentTo` (+ counts) - predatory taxa observed on this plant
- `entomopathogenic_fungi`, `entomopathogenic_fungi_count` - insect-pathogenic fungi observed on this plant

**Scientific basis**: Plants hosting predators of neighbouring plants' herbivores provide biocontrol. Entomopathogenic fungi on one plant can suppress pests on companions.

### Static Data Display

| Field | Source | Guild Relevance |
|-------|--------|-----------------|
| Herbivore count | `herbivore_count` | Number of taxa observed feeding on this plant |
| Key herbivores | `herbivores` list | Taxa observed as herbivores/parasites |
| Beneficial predators | predator columns | Predatory taxa observed visiting this plant |
| Entomopathogenic fungi | `entomopathogenic_fungi` | Insect-killing fungi observed |

### Pest Pressure Classification

| Herbivore Count | Level | Implication |
|-----------------|-------|-------------|
| > 15 | High | Many herbivore taxa observed; likely needs diverse biocontrol |
| 5-15 | Moderate | Several herbivore taxa observed |
| < 5 | Low | Few herbivore taxa observed; may provide predator habitat |
| 0 | No data | No herbivore observations in GloBI |

### Biocontrol Contribution Classification

| Metric | Guild Value |
|--------|-------------|
| Predator count > 10 | Many predatory taxa observed - high biocontrol habitat |
| Predator count 3-10 | Several predatory taxa observed |
| Predator count < 3 | Few predatory taxa observed |
| Entomopathogenic fungi > 0 | Insect-killing fungi observed on this plant |

### Output Format

```markdown
### Pest Control Potential

**Observed Herbivores**: {herbivore_count} taxa recorded feeding on this plant ({level})
**Key Herbivores**: {top 3-5 from herbivores list}

**Observed Biocontrol Agents**:
- {predator_count} predatory taxa observed visiting this plant
- {entomo_fungi_count} entomopathogenic fungi species observed

**Guild Recommendations**:
- {pest-level-specific guidance}
- {predator-specific guidance}

**This Plant Provides**:
- Observed habitat for {predator_count} predatory taxa
- {entomopathogenic fungi contribution if any}
```

### Decision Tree

```
IF herbivore_count > 15:
  "High pest pressure. Benefits significantly from companions hosting predators of these pests."

IF herbivore_count 5-15:
  "Moderate pest pressure. Diverse plantings provide natural balance."

IF herbivore_count < 5:
  "Low documented pest pressure. May provide predator habitat for neighbours."

IF predator_count > 10:
  "Strong biocontrol habitat. This plant hosts many beneficial predators that protect neighbours."

IF predator_count 3-10:
  "Moderate biocontrol value. Contributes predator habitat to guild."

IF entomopathogenic_fungi_count > 0:
  "Hosts {entomopathogenic_fungi_count} insect-killing fungi species that may suppress pests on neighbouring plants."
```

---

## GP4: Disease Control Contribution (from M4)

**Data source** (GloBI observations):
- `pathogenic_fungi` list, `pathogenic_fungi_count` - fungal pathogens observed on this plant (pathogenOf, parasiteOf)
- `mycoparasite_fungi`, `mycoparasite_fungi_count` - mycoparasitic fungi observed (parasitize other fungi)
- `fungivores_eats`, `fungivores_eats_count` - fungivorous animals observed eating fungi on this plant

**Scientific basis**: Mycoparasitic fungi attack plant pathogens. Fungivorous animals consume pathogenic fungi. Plants hosting these provide disease suppression.

### Static Data Display

| Field | Source | Guild Relevance |
|-------|--------|-----------------|
| Pathogen count | `pathogenic_fungi_count` | Number of pathogenic fungi observed on this plant |
| Key pathogens | `pathogenic_fungi` list | Fungal pathogens observed |
| Mycoparasites | `mycoparasite_fungi`, `mycoparasite_fungi_count` | Fungi observed parasitizing other fungi |
| Fungivores | `fungivores_eats`, `fungivores_eats_count` | Animals observed eating fungi |

### Disease Pressure Classification

| Pathogen Count | Level | Implication |
|----------------|-------|-------------|
| > 10 | High | Many pathogenic fungi observed; avoid clustering with plants sharing same pathogens |
| 3-10 | Moderate | Several pathogenic fungi observed |
| < 3 | Low | Few pathogenic fungi observed |
| 0 | No data | No pathogen observations in GloBI |

### Disease Control Contribution Classification

| Metric | Guild Value |
|--------|-------------|
| Mycoparasite count > 5 | Many mycoparasitic fungi observed - high disease suppression potential |
| Mycoparasite count 1-5 | Some mycoparasitic fungi observed |
| Fungivore count > 3 | Several fungivorous animals observed |
| Fungivore count 1-3 | Few fungivorous animals observed |

### Output Format

```markdown
### Disease Control Potential

**Observed Pathogens**: {pathogenic_fungi_count} pathogenic fungi recorded on this plant ({level})
**Key Pathogens**: {top 3-5 from pathogenic_fungi list}

**Observed Biocontrol Agents**:
- {mycoparasite_fungi_count} mycoparasitic fungi observed (parasitize plant pathogens)
- {fungivores_eats_count} fungivorous animals observed (consume fungi)

**Guild Recommendations**:
- {disease-level-specific guidance}
- {biocontrol-specific guidance}

**This Plant Provides**:
- {mycoparasite contribution if any}
- {fungivore contribution if any}
```

### Decision Tree

```
IF pathogenic_fungi_count > 10:
  "High disease pressure. Avoid clustering with plants sharing the same pathogens."
  "Improve airflow by spacing to reduce humidity-driven disease spread."

IF pathogenic_fungi_count 3-10:
  "Moderate disease pressure. Benefits from companions hosting disease antagonists."

IF pathogenic_fungi_count < 3:
  "Low documented disease pressure."

IF mycoparasite_fungi_count > 0:
  "Hosts mycoparasitic fungi that may protect neighbours from fungal diseases."

IF fungivores_eats_count > 0:
  "Hosts fungivorous animals that consume pathogenic fungi - contributes to guild disease suppression."
```

---

## GP5: Mycorrhizal Network (from M5)

**Data source** (GloBI + FungalTraits/FunGuild):
- `amf_fungi`, `amf_fungi_count` - arbuscular mycorrhizal fungi observed on this plant
- `emf_fungi`, `emf_fungi_count` - ectomycorrhizal fungi observed on this plant
- `endophytic_fungi` - endophytic fungi observed
- `saprotrophic_fungi` - saprotrophic fungi observed

**Scientific basis**: Plants sharing mycorrhizal fungi form Common Mycorrhizal Networks (CMNs) enabling nutrient sharing (carbon, phosphorus, nitrogen) and chemical stress signaling. AMF and EMF fungi form separate network types that cannot interconnect.

### Mycorrhizal Classification

| Type | Description | Network Properties |
|------|-------------|-------------------|
| AMF (Arbuscular) | Forms arbuscules inside root cells | Broad low-specificity networks, phosphorus transfer |
| EMF (Ectomycorrhizal) | Forms sheath around root tips | Higher host specificity, nutrient + defense signaling |
| Dual | Associates with both AMF and EMF | Can participate in either network type |
| Non-mycorrhizal | Does not form mycorrhizal associations | No network participation |

### Network Compatibility Rules

CMNs require shared fungal partners. Plants using the same mycorrhizal type CAN share networks; plants using different types CANNOT transfer resources between networks.

| Plant Type | Network Potential | Notes |
|------------|-------------------|-------|
| AMF observed | Can connect to other AMF plants | Forms broad networks with herbs, grasses, many shrubs |
| EMF observed | Can connect to other EMF plants | Forms networks with specific tree genera |
| Both observed | Bridges both network types | Versatile guild member |
| Neither observed | No documented network | May still form associations (data gap) |

**Key insight**: AMF and EMF are not "incompatible" in a harmful sense - they simply form separate underground networks. A guild can contain both, but they won't share resources across network types.

### Output Format

```markdown
### Mycorrhizal Network

**Observed Association**: {AMF / EMF / Dual / None documented}
**Documented Fungi**: {list of specific fungi observed, if available}

**Guild Recommendations**:
- **Network-compatible plants**: Other plants with {AMF/EMF} fungi observed
- **Network benefit**: Can potentially share {nutrients/signals} with compatible plants
- **Soil management**: Avoid excessive tillage to preserve hyphal networks

**This Plant Contributes**:
- {Connection point description based on observed associations}
```

### Decision Tree

```
IF amf_fungi_count > 0 AND emf_fungi_count == 0:
  "AMF-associated. Forms underground networks with other AMF plants."
  "Network bonus: Can share phosphorus and carbon with AMF-compatible neighbours."
  "Soil tip: Minimize tillage to preserve fungal hyphal connections."

IF emf_fungi_count > 0 AND amf_fungi_count == 0:
  "EMF-associated. Forms underground networks with other EMF plants."
  "Network bonus: Can share nutrients and defense signals with EMF-compatible neighbours."
  "Creates forest-type nutrient-sharing network."

IF amf_fungi_count > 0 AND emf_fungi_count > 0:
  "Dual mycorrhizal. Can connect to both AMF and EMF network types."
  "Versatile guild member - bridges different plant communities."

IF amf_fungi_count == 0 AND emf_fungi_count == 0:
  "Non-mycorrhizal or undocumented. May not participate in underground fungal networks."
  "No network conflict, but no documented network benefit from CMN."
```

---

## GP6: Structural Role (from M6)

**Data source**: `height_m`, `try_growth_form`, `EIVEres-L_complete`

**Scientific basis**: Vertical stratification creates microhabitats. Taller plants shade shorter ones - beneficial only if shorter plants are shade-tolerant. The GuildBuilder validates height differences against light preferences.

### Layer Classification

| Height | Layer | Ecological Role |
|--------|-------|-----------------|
| > 10m | Canopy | Primary shade provider, wind break |
| 5-10m | Sub-canopy | Secondary structure, filtered light |
| 2-5m | Tall shrub | Mid-layer, partial shade |
| 0.5-2m | Understory | Shade utilization, mid habitat |
| < 0.5m | Ground cover | Soil protection, weed suppression |

### Light Compatibility Matrix

| Taller Plant | Shorter Plant EIVE-L | Compatibility |
|--------------|---------------------|---------------|
| Any | < 3.2 (shade-loving) | Excellent - shorter plant benefits from shade |
| Any | 3.2-7.47 (flexible) | Good - partial shade tolerated |
| Any | > 7.47 (sun-loving) | Poor - shorter plant will be shaded out |

### Growth Form Synergies

| Form Combination | Synergy | Notes |
|-----------------|---------|-------|
| Tree + Vine | High | Vine uses tree as climbing structure |
| Tree + Shade-tolerant herb | High | Herb benefits from canopy |
| Tree + Sun-loving herb | Low | Herb shaded out |
| Shrub + Ground cover | High | Different vertical niches |
| Herb + Herb (same height) | Variable | Depends on CSR and resource overlap |

### Output Format

```markdown
### Structural Role

**Layer**: {layer_name} ({height_m}m)
**Growth Form**: {try_growth_form}
**Light Preference**: EIVE-L {light_pref}

**Guild Recommendations**:
- **Below this plant**: {shade-tolerance requirements}
- **Same layer**: {competition considerations}
- **Above this plant**: {canopy compatibility}
- **Climbing**: {suitability as climbing structure}

**Structural Contribution**:
- {shade/wind/habitat provision}
```

### Decision Tree

```
IF height > 10m:
  "Canopy layer. Creates significant shade below."
  "Pair with: shade-tolerant understory plants (EIVE-L < 5)"
  "Avoid pairing with: sun-loving plants in the shade zone"

IF height 5-10m:
  "Sub-canopy. Provides partial shade, benefits from canopy protection."
  "Pair with: ground covers, shade-tolerant shrubs"

IF height 2-5m:
  "Tall shrub layer. Mid-structure role."
  "Pair with: low herbs, ground covers below; tolerates taller trees above"

IF height 0.5-2m:
  "Understory. Consider light requirements."
  IF EIVE-L < 3.2:
    "Shade-adapted. Thrives under trees/tall shrubs."
  ELSE IF EIVE-L > 7.47:
    "Sun-loving. Needs open position, not under canopy."
  ELSE:
    "Flexible. Tolerates range of light conditions."

IF height < 0.5m:
  "Ground cover. Soil protection, weed suppression role."
  "Pair with: any taller plants (provides living mulch)"

IF growth_form CONTAINS "vine" OR "liana":
  "Climber. Needs vertical structure."
  "Pair with: trees or tall shrubs as climbing hosts"
```

---

## GP7: Pollinator Contribution (from M7)

**Data source** (GloBI observations):
- `pollinators` list - taxa observed pollinating this plant (interactionTypeName = 'pollinates')
- `pollinator_count` - number of distinct pollinator taxa observed

**Scientific basis**: Plants sharing pollinators create mutual attraction effects. The GuildBuilder uses quadratic weighting - more shared pollinators = non-linearly better pollination for both plants.

### Pollinator Value Classification

| Pollinator Count | Value | Guild Contribution |
|------------------|-------|-------------------|
| > 20 | Very High | Many pollinator taxa observed - major pollinator hub |
| 11-20 | High | Several pollinator taxa observed |
| 5-10 | Moderate | Some pollinator taxa observed |
| 1-4 | Low | Few pollinator taxa observed |
| 0 | No data | No pollinator observations in GloBI |

### Pollinator Guild Synergies

| Pollinator Type | Plant Traits | Guild Benefit |
|-----------------|--------------|---------------|
| Bumblebees | Tubular flowers, blue/purple | Extended season if combined |
| Honeybees | Open flowers, yellow/white | High visit frequency |
| Hoverflies | Open/flat flowers | Dual benefit: pollination + biocontrol |
| Butterflies | Flat-topped clusters | Nectar corridor when grouped |
| Specialist bees | Specific flower forms | Support rare/important species |

### Output Format

```markdown
### Pollinator Support

**Observed Pollinators**: {pollinator_count} taxa recorded pollinating this plant ({level})
**Key Pollinators**: {top pollinators from list}

**Guild Recommendations**:
- **Complement flowering times**: Pair with early/late bloomers for season-long support
- **Shared pollinators**: Plants with overlapping observed pollinators benefit each other
- **Proximity bonus**: Nearby plants with shared pollinators get increased visits

**This Plant Provides**:
- Observed nectar/pollen source for {pollinator_count} pollinator taxa
- Attraction effect may increase visits to neighbouring plants
```

### Decision Tree

```
IF pollinator_count > 20:
  "Many pollinators observed. Central to guild pollination success."
  "Benefits ALL flowering neighbours through attraction effect."

IF pollinator_count 11-20:
  "Several pollinators observed. Valuable addition to any guild."

IF pollinator_count 5-10:
  "Some pollinators observed. Combine with pollinator-rich plants for synergy."

IF pollinator_count < 5:
  "Few pollinators observed. May have specialist visitors not yet documented."
  "Consider pairing with pollinator-rich plants for cross-pollination support."
```

---

## Integrated Guild Potential Output

```markdown
## Guild Potential

### Summary Card

| Metric | Value | Guild Contribution |
|--------|-------|-------------------|
| Phylogenetic | {family} → {genus} | Seek different families |
| CSR Strategy | C: {c}% S: {s}% R: {r}% | {strategy guidance} |
| Structural | {layer} ({height}m) | {structural role} |
| Mycorrhizal | {AMF/EMF/Dual/Non} | {network compatibility} |
| Pest Control | {herbivore_count} pests, {predator_count} predators | {biocontrol role} |
| Disease Control | {pathogen_count} pathogens, {mycoparasite_count} antagonists | {disease role} |
| Pollinator | {pollinator_count} taxa | {pollinator value} |

### Top Companion Principles

Based on this plant's characteristics:

1. **Taxonomic diversity** - seek plants from different families
2. **CSR compatibility** - {strategy-specific guidance}
3. **Structural layering** - {height-appropriate companions}
4. **Mycorrhizal network** - {network-compatible plants}

### Cautions

- {family clustering warning}
- {CSR conflict warning if applicable}
- {light/shade conflict if applicable}

**→ [Launch GuildBuilder]** for optimised companion scoring with specific plants
```

---

## Data Column Reference

### Plants Master Dataset (Stage 3)

| Column | Source | Used For |
|--------|--------|----------|
| `family` | WFO | GP1 - Phylogenetic |
| `genus` | WFO | GP1 - Phylogenetic |
| `C`, `S`, `R` | Stage 3 CSR | GP2 - Growth compatibility |
| `height_m` | TRY | GP2, GP6 - Structure |
| `EIVEres-L_complete` | Stage 2 | GP2, GP6 - Light compatibility |
| `try_growth_form` | TRY | GP2, GP6 - Structure |

### Organisms Parquet (`organism_profiles_11711.parquet`)

| Column | Used For |
|--------|----------|
| `herbivores` | GP3 - Pest list |
| `herbivore_count` | GP3 - Pest pressure level |
| `flower_visitors` | GP3 - Potential predator habitat |
| `predators_hasHost` | GP3 - Beneficial predators |
| `predators_interactsWith` | GP3 - Beneficial predators |
| `predators_adjacentTo` | GP3 - Beneficial predators |
| `fungivores_eats` | GP4 - Fungivorous animals |
| `fungivores_eats_count` | GP4 - Fungivore count |
| `pollinators` | GP7 - Pollinator list |
| `pollinator_count` | GP7 - Pollinator count |

### Fungi Parquet (`fungal_guilds_hybrid_11711.parquet`)

| Column | Used For |
|--------|----------|
| `pathogenic_fungi` | GP4 - Disease list |
| `pathogenic_fungi_count` | GP4 - Disease pressure level |
| `mycoparasite_fungi` | GP4 - Mycoparasitic fungi |
| `mycoparasite_fungi_count` | GP4 - Mycoparasite count |
| `entomopathogenic_fungi` | GP3 - Insect-killing fungi |
| `entomopathogenic_fungi_count` | GP3 - Entomopathogen count |
| `amf_fungi` | GP5 - AMF species list |
| `amf_fungi_count` | GP5 - AMF presence/count |
| `emf_fungi` | GP5 - EMF species list |
| `emf_fungi_count` | GP5 - EMF presence/count |
| `endophytic_fungi` | GP5 - Endophytes |
| `saprotrophic_fungi` | GP5 - Saprotrophs |

---

## What's NOT in Static Encyclopedia

The following require pairwise analysis (GuildBuilder territory):

| Feature | Why Dynamic |
|---------|-------------|
| Specific companion scores | Requires scoring THIS plant vs CANDIDATE plant |
| Optimal guild composition | Requires multi-plant optimization |
| Phylogenetic distance calculation | Requires Faith's PD across multiple plants |
| Predator overlap analysis | Requires herbivore→predator lookup across pairs |
| Mycorrhizal network connectivity | Requires fungi overlap calculation |
| EIVE compatibility scoring | Requires pairwise distance calculation |

Static encyclopedia provides the traits. GuildBuilder uses those traits to score actual combinations.

---

## References

Mycorrhizal network science:
- [Common Mycorrhizal Networks: Theories and Mechanisms](https://pmc.ncbi.nlm.nih.gov/articles/PMC10512311/)
- [Inter-plant communication through mycorrhizal networks](https://pmc.ncbi.nlm.nih.gov/articles/PMC4497361/)
- [Common Mycorrhizae Network in Sustainable Agriculture](https://pmc.ncbi.nlm.nih.gov/articles/PMC11020090/)
