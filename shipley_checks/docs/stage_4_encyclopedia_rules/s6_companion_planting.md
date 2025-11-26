# S6: Guild Potential (Companion Planting)

Static recommendations based on THIS plant's characteristics, derived from GuildBuilder metric logic. Each subsection shows the plant's guild-relevant traits and provides companion selection guidance.

**Scope**: Static encyclopedia shows individual plant contributions. Dynamic GuildBuilder does actual pairwise scoring.

**Data provenance**: Biotic interaction data (pests, diseases, pollinators, fungi, beneficial insects) are derived from **GloBI (Global Biotic Interactions)** observation records. Counts reflect the number of distinct species observed interacting with this plant, not how often interactions occur.

---

## Data Distribution Reference

Percentile thresholds for classifying observation counts. Based on 11,711 European plants.

**Source parquets:**
- Pests, pollinators, predators: `shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet`
- Diseases, beneficial fungi: `shipley_checks/stage4/phase0_output/fungal_guilds_hybrid_11711.parquet`

### Herbivores/Pests (33.6% of plants have data)

Source: `herbivore_count` from `organism_profiles_11711.parquet`

| Percentile | Count | Interpretation |
|------------|-------|----------------|
| p25 | 1 | Few pests observed |
| p50 (median) | 2 | Typical |
| p75 | 6 | Above average |
| p90 | 15 | High pest diversity observed |

### Pollinators (13.4% of plants have data)

Source: `pollinator_count` from `organism_profiles_11711.parquet`

| Percentile | Count | Interpretation |
|------------|-------|----------------|
| p25 | 2 | Few pollinators observed |
| p50 (median) | 6 | Typical |
| p75 | 20 | Above average |
| p90 | 45 | Pollinator hotspot |

### Pathogenic Fungi (61.6% of plants have data)

Source: `pathogenic_fungi_count` from `fungal_guilds_hybrid_11711.parquet`

| Percentile | Count | Interpretation |
|------------|-------|----------------|
| p25 | 1 | Few pathogens observed |
| p50 (median) | 3 | Typical |
| p75 | 7 | Above average |
| p90 | 15 | High disease diversity observed |

### Beneficial Predators (35.1% of plants have data)

Source: `predators_hasHost_count + predators_interactsWith_count + predators_adjacentTo_count` from `organism_profiles_11711.parquet`

| Percentile | Count | Interpretation |
|------------|-------|----------------|
| p25 | 1 | Few predators observed |
| p50 (median) | 3 | Typical |
| p75 | 9 | Above average |
| p90 | 29 | Strong predator habitat |

**Note**: Many plants have zero observations due to GloBI data gaps, not necessarily absence of interactions.

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

**Scientific basis**: CSR strategy conflicts cause competition failures. C-C pairs compete destructively; C-S pairs may shade out S-plants unless S is shade-tolerant. Growth form and height modulate these conflicts.

### CSR Classification

| Condition | Classification |
|-----------|---------------|
| C > 60% | C-dominant (Competitor) |
| S > 60% | S-dominant (Stress-tolerator) |
| R > 60% | R-dominant (Ruderal) |
| No single > 60% | Balanced/Generalist |

---

### Companion Compatibility Matrix (CSR × CSR)

The GuildBuilder calculates pairwise conflict scores. This matrix shows base compatibility.

| This Plant ↓ / Companion → | C-dominant | S-dominant | R-dominant | Balanced |
|---------------------------|------------|------------|------------|----------|
| **C-dominant** | Poor (compete) | Conditional | Moderate | Good |
| **S-dominant** | Conditional | Good | Good | Good |
| **R-dominant** | Moderate | Good | Moderate | Good |
| **Balanced** | Good | Good | Good | Good |

**Key interactions:**
- **C + C**: Direct competition for resources. Avoid unless height separation > 5m.
- **C + S**: Works IF the S-plant is shade-tolerant (EIVE-L < 3.2). Fails if S-plant needs sun.
- **C + R**: R-plants exploit gaps around vigorous C-plants. Moderate compatibility.
- **S + S**: Both conservative; minimal competition. Good pairing.
- **R + R**: Both short-lived; plan for succession. Neither provides long-term structure.

---

### Height and Growth Form Modifiers

Conflict severity is modified by structural relationships.

#### Conflict Reduction Rules (from M2)

| Structural Relationship | Effect on Conflict | Example |
|------------------------|-------------------|---------|
| Vine + Tree | Conflict ×0.2 | Vine uses tree as support; synergy |
| Tree + Herb (C-dominant both) | Conflict ×0.4 | Different vertical niches |
| Height difference > 5m | Conflict ×0.3 | Vertical stratification reduces overlap |
| Height difference > 8m (C+S) | Conflict reduced | C-tree, S-ground cover = no competition |

#### Growth Form Pairing Guide

| This Plant's Form | Best Companions | Avoid |
|-------------------|-----------------|-------|
| Tree (>5m) | Shade-tolerant understory, vines | Sun-loving herbs in shade zone |
| Shrub (1-5m) | Ground covers, compatible shrubs | Same-height C-dominant shrubs |
| Herb (<1m) | Taller protective plants, other herbs | Aggressive C-dominant at same height |
| Vine | Trees or tall shrubs as hosts | Other aggressive vines on same support |

---

### Light Preference Integration (EIVE-L)

For S-plants paired with taller C-plants, light preference determines success.

| S-plant EIVE-L | Interpretation | Under C-Canopy |
|----------------|---------------|----------------|
| < 3.2 | Shade-loving | Thrives (zero conflict) |
| 3.2 - 7.47 | Flexible | Tolerates some shade |
| > 7.47 | Sun-demanding | Will fail under canopy (conflict 0.9) |

---

### Output Format

```markdown
### Growth Compatibility

**CSR Profile**: C: {c_pct}% | S: {s_pct}% | R: {r_pct}%
**Classification**: {C-dominant / S-dominant / R-dominant / Balanced}
**Growth Form**: {tree / shrub / herb / vine}
**Height**: {height_m}m
**Light Preference**: EIVE-L {light_pref}

**Companion Strategy**:
- {CSR-based pairing advice}
- {height/form-based pairing advice}
- {light-based caution if applicable}

**Good Companions**:
- {form-specific recommendations}

**Avoid Pairing With**:
- {conflict situations}
```

---

### Decision Tree

```
STEP 1: Determine CSR classification
  C > 60%: C-dominant
  S > 60%: S-dominant
  R > 60%: R-dominant
  else: Balanced

STEP 2: Determine growth form category
  IF try_growth_form CONTAINS "vine" OR "liana": Vine
  ELSE IF height > 5m: Tree
  ELSE IF height > 1m: Shrub
  ELSE: Herb

STEP 3: Generate advice by CSR × Form

IF C-dominant:
  IF Tree:
    "Canopy competitor. Pairs well with shade-tolerant understory (EIVE-L < 5)."
    "Avoid other large C-dominant trees nearby; root and light competition."
    "Vines can use as support without conflict."
  IF Shrub:
    "Vigorous mid-layer. Give wide spacing from other C-dominant shrubs."
    "Good with S-dominant ground covers; provides protection."
  IF Herb:
    "Spreading competitor. May outcompete neighbouring herbs."
    "Best with well-spaced, resilient companions or as solo planting."
  IF Vine:
    "Aggressive climber. Needs robust host tree or structure."
    "May smother less vigorous plants; keep away from delicate shrubs."

IF S-dominant:
  IF EIVE-L < 3.2:
    "Shade-tolerant. Thrives under C-dominant canopy trees."
    "Ideal understory plant for layered guilds."
  ELSE IF EIVE-L > 7.47:
    "Sun-demanding despite S-strategy. Needs open position."
    "Avoid planting under tall C-dominant plants."
  ELSE:
    "Flexible S-plant. Tolerates range of companions."

  All forms:
    "Low competition profile. Pairs well with most strategies."
    "Long-lived and persistent; good structural backbone for guilds."

IF R-dominant:
  "Short-lived opportunist. Use for seasonal colour or gap-filling."
  "Pair with longer-lived S or balanced plants for continuity."
  "Will not persist; plan for succession or self-seeding."
  IF Herb:
    "Annual/biennial. Good for dynamic, changing plantings."
  IF Vine:
    "May die back; regrows rapidly from base or seed."

IF Balanced:
  "Generalist strategy. Compatible with most companion types."
  "Moderate vigour; neither dominates nor is dominated."
  "Flexible in guild positioning."
```

---

## GP3: Pest Control Contribution (from M3)

**Data source** (GloBI observations):
- `herbivores` list, `herbivore_count` - species observed feeding on or parasitizing this plant
- `flower_visitors`, `visitor_count` - species observed visiting flowers
- `predators_hasHost`, `predators_interactsWith`, `predators_adjacentTo` (+ counts) - beneficial predators observed on this plant
- `entomopathogenic_fungi`, `entomopathogenic_fungi_count` - insect-killing fungi observed

**Scientific basis**: Plants hosting predators of neighbouring plants' pests provide natural pest control. Insect-killing fungi on one plant can suppress pests on companions.

### Static Data Display

| Field | Source | Guild Relevance |
|-------|--------|-----------------|
| Pest count | `herbivore_count` | Number of pest species observed |
| Key pests | `herbivores` list | Species observed feeding on or parasitizing this plant |
| Beneficial predators | predator columns | Predatory insects observed visiting this plant |
| Insect-killing fungi | `entomopathogenic_fungi` | Fungi that kill pest insects |

### Pest Pressure Classification (percentile-based)

| Pest Count | Level | Percentile | Implication |
|------------|-------|------------|-------------|
| ≥15 | High | top 10% | Many pest species observed; benefits from diverse companions |
| 6-14 | Above average | 75th-90th | More pests than typical |
| 2-5 | Typical | 25th-75th | Average pest observations |
| 1 | Low | bottom 25% | Few pests observed |
| 0 | No data | — | No pest observations in GloBI (data gap) |

### Biocontrol Contribution Classification (percentile-based)

| Predator Count | Level | Percentile | Guild Value |
|----------------|-------|------------|-------------|
| ≥29 | Very high | top 10% | Excellent habitat for beneficial insects |
| 9-28 | Above average | 75th-90th | Good predator habitat |
| 3-8 | Typical | 25th-75th | Average predator observations |
| 1-2 | Low | bottom 25% | Few predators observed |
| 0 | No data | — | No predator observations (data gap) |

### Output Format

```markdown
### Pest Control Potential

**Observed Pests**: {herbivore_count} species recorded feeding on or parasitizing this plant ({level})
**Key Pests**: {top 3-5 from herbivores list}

**Observed Beneficial Insects**:
- {predator_count} predatory species observed on this plant
- {entomo_fungi_count} insect-killing fungi species observed

**Guild Recommendations**:
- {pest-level-specific guidance}
- {predator-specific guidance}

**This Plant Provides**:
- Habitat for {predator_count} beneficial predators
- {insect-killing fungi contribution if any}
```

### Decision Tree

```
IF herbivore_count >= 15:
  "High pest diversity observed (top 10%). Benefits from companions that attract pest predators."

IF herbivore_count 6-14:
  "Above-average pest observations. Diverse plantings help maintain natural balance."

IF herbivore_count 2-5:
  "Typical pest observations. Standard companion planting applies."

IF herbivore_count 1:
  "Few pests observed. May provide good habitat for beneficial insects."

IF herbivore_count 0:
  "No pest data in GloBI. Likely a data gap rather than pest-free plant."

IF predator_count >= 29:
  "Excellent predator habitat (top 10%). This plant attracts many beneficial insects that protect neighbours."

IF predator_count 9-28:
  "Good predator habitat. Contributes beneficial insects to the garden."

IF predator_count 3-8:
  "Typical predator observations."

IF entomopathogenic_fungi_count > 0:
  "Hosts {entomopathogenic_fungi_count} insect-killing fungi that may help control pests on neighbouring plants."
```

---

## GP4: Disease Control Contribution (from M4)

**Data source** (GloBI observations):
- `pathogenic_fungi` list, `pathogenic_fungi_count` - disease-causing fungi observed on this plant
- `mycoparasite_fungi`, `mycoparasite_fungi_count` - beneficial fungi that attack disease fungi
- `fungivores_eats`, `fungivores_eats_count` - animals observed eating fungi

**Scientific basis**: Some fungi parasitize disease-causing fungi. Some animals eat fungal pathogens. Plants hosting these provide natural disease suppression.

### Static Data Display

| Field | Source | Guild Relevance |
|-------|--------|-----------------|
| Disease count | `pathogenic_fungi_count` | Number of disease-causing fungi observed |
| Key diseases | `pathogenic_fungi` list | Fungal diseases observed on this plant |
| Beneficial fungi | `mycoparasite_fungi` | Fungi that attack plant diseases |
| Fungus-eating animals | `fungivores_eats` | Animals that consume fungi |

### Disease Pressure Classification (percentile-based)

| Pathogen Count | Level | Percentile | Implication |
|----------------|-------|------------|-------------|
| ≥15 | High | top 10% | Many diseases observed; avoid clustering same-disease plants |
| 7-14 | Above average | 75th-90th | More diseases than typical |
| 3-6 | Typical | 25th-75th | Average disease observations |
| 1-2 | Low | bottom 25% | Few diseases observed |
| 0 | No data | — | No disease observations in GloBI (data gap) |

### Disease Control Contribution Classification

| Metric | Guild Value |
|--------|-------------|
| Mycoparasite fungi > 0 | Hosts beneficial fungi that attack plant diseases (rare - only 0.04% of plants) |
| Fungivore animals > 0 | Hosts animals that eat fungi |

### Output Format

```markdown
### Disease Control Potential

**Observed Diseases**: {pathogenic_fungi_count} disease-causing fungi recorded ({level})
**Key Diseases**: {top 3-5 from pathogenic_fungi list}

**Observed Disease Fighters**:
- {mycoparasite_fungi_count} beneficial fungi that attack plant diseases
- {fungivores_eats_count} fungus-eating animals observed

**Guild Recommendations**:
- {disease-level-specific guidance}
- {biocontrol-specific guidance}

**This Plant Provides**:
- {mycoparasite contribution if any}
- {fungivore contribution if any}
```

### Decision Tree

```
IF pathogenic_fungi_count >= 15:
  "High disease diversity observed (top 10%). Avoid clustering with plants that share the same diseases."
  "Good airflow between plants helps reduce humidity-driven disease spread."

IF pathogenic_fungi_count 7-14:
  "Above-average disease observations. Benefits from companions that host disease-fighting fungi."

IF pathogenic_fungi_count 3-6:
  "Typical disease observations. Standard spacing and airflow practices apply."

IF pathogenic_fungi_count 1-2:
  "Few diseases observed."

IF pathogenic_fungi_count 0:
  "No disease data in GloBI. Likely a data gap rather than disease-free plant."

IF mycoparasite_fungi_count > 0:
  "Hosts beneficial fungi that attack plant diseases - may help protect neighbouring plants."

IF fungivores_eats_count > 0:
  "Hosts fungus-eating animals that may help suppress diseases in the garden."
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
- `pollinators` list - species observed pollinating this plant
- `pollinator_count` - number of distinct pollinator species observed

**Scientific basis**: Plants sharing pollinators create mutual attraction effects. The GuildBuilder uses quadratic weighting - more shared pollinators = stronger benefit for both plants.

### Pollinator Value Classification (percentile-based)

| Pollinator Count | Level | Percentile | Guild Contribution |
|------------------|-------|------------|-------------------|
| ≥45 | Exceptional | top 10% | Pollinator hotspot - major attraction |
| 20-44 | Very high | 75th-90th | Strong pollinator magnet |
| 6-19 | Typical | 25th-75th | Average pollinator observations |
| 2-5 | Low | bottom 25% | Few pollinators observed |
| 0-1 | Minimal/No data | — | Little or no pollinator data in GloBI |

### Pollinator Guild Synergies

| Pollinator Type | Plant Traits | Guild Benefit |
|-----------------|--------------|---------------|
| Bumblebees | Tubular flowers, blue/purple | Extended season if combined |
| Honeybees | Open flowers, yellow/white | High visit frequency |
| Hoverflies | Open/flat flowers | Dual benefit: pollination + pest control |
| Butterflies | Flat-topped clusters | Nectar corridor when grouped |
| Specialist bees | Specific flower forms | Support rare/important species |

### Output Format

```markdown
### Pollinator Support

**Observed Pollinators**: {pollinator_count} species recorded pollinating this plant ({level})
**Key Pollinators**: {top pollinators from list}

**Guild Recommendations**:
- **Complement flowering times**: Pair with early/late bloomers for season-long support
- **Shared pollinators**: Plants with overlapping pollinators benefit each other
- **Proximity bonus**: Nearby plants with shared pollinators get increased visits

**This Plant Provides**:
- Nectar/pollen source for {pollinator_count} pollinator species
- Attraction effect may increase visits to neighbouring plants
```

### Decision Tree

```
IF pollinator_count >= 45:
  "Pollinator hotspot (top 10%). Central to garden pollination success."
  "Benefits ALL flowering neighbours through strong attraction effect."

IF pollinator_count 20-44:
  "Strong pollinator magnet. Valuable addition to any garden."

IF pollinator_count 6-19:
  "Typical pollinator observations. Good companion for other flowering plants."

IF pollinator_count 2-5:
  "Few pollinators observed. May have specialist visitors not yet documented."
  "Consider pairing with pollinator-rich plants for better cross-pollination."

IF pollinator_count 0-1:
  "Little or no pollinator data in GloBI. Likely a data gap - most flowering plants attract pollinators."
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
