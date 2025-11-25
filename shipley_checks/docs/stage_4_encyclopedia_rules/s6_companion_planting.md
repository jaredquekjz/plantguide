# S6: Guild Potential (Companion Planting)

Static recommendations based on THIS plant's characteristics, derived from GuildBuilder metric logic. Each subsection shows the plant's guild-relevant traits and provides companion selection guidance.

**Scope**: Static encyclopedia shows individual plant contributions. Dynamic GuildBuilder does actual pairwise scoring.

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

| Plant's Family | Companion Guidance |
|----------------|-------------------|
| Rosaceae | Avoid other Rosaceae (shared rust, aphids). Pair with Lamiaceae, Asteraceae |
| Fabaceae | Nitrogen-fixer. Pair with heavy feeders from any family |
| Brassicaceae | Avoid other Brassicaceae (shared clubroot, cabbage pests). Pair with Allium |
| Solanaceae | Avoid other Solanaceae (shared blight, Colorado beetle). Pair with legumes |
| Poaceae | Grasses share many pests. Mix with broadleaf plants |
| Apiaceae | Avoid other Apiaceae (shared carrot fly). Pair with Allium |

### Output Format

```markdown
### Phylogenetic Independence

**Family**: Rosaceae
**Genus**: Malus

**Guild Recommendation**:
- Avoid pairing with other Rosaceae (Rosa, Prunus, Rubus) - shared apple scab, rust, aphids
- Excellent companions: Allium (pest deterrent), Lamiaceae (aromatic distraction)
- Seek maximum taxonomic distance for pest dilution
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

**CSR Profile**: C: 65% | S: 20% | R: 15%
**Strategy**: Competitive (C-dominant)
**Height**: 4.5m
**Light Preference**: EIVE-L 7 (full sun)

**Guild Recommendations**:
- **Avoid**: Other C-dominant plants at same height (resource competition)
- **Good companions**:
  - S-dominant shade-tolerant understory (EIVE-L < 3.2)
  - Vines that can climb this plant
  - Low herbs with different vertical niche
- **Spacing**: Give extra space to other competitive plants
- **Succession**: R-dominant plants can fill temporary gaps
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

**Data source**: `herbivores` list, `herbivore_count`, `flower_visitors`, predator columns

**Scientific basis**: Plants hosting predators of neighbouring plants' herbivores provide biocontrol. Entomopathogenic fungi on one plant can suppress pests on companions.

### Static Data Display

| Field | Source | Guild Relevance |
|-------|--------|-----------------|
| Herbivore count | `herbivore_count` | Pest pressure level |
| Key herbivores | `herbivores` list | What attacks this plant |
| Flower visitors | `flower_visitors` | Potential predator habitat |

### Pest Pressure Classification

| Herbivore Count | Level | Implication |
|-----------------|-------|-------------|
| > 15 | High | Multiple pest species; needs diverse biocontrol |
| 5-15 | Moderate | Some pest pressure; benefits from predator plants |
| < 5 | Low | Few documented pests; may provide predator habitat |
| 0 | Unknown | Not well-studied |

### Output Format

```markdown
### Pest Control Potential

**Herbivore Load**: 12 taxa documented (Moderate)
**Key Pests**: Aphids (Myzus persicae), Caterpillars (Operophtera brumata)

**Guild Recommendations**:
- **Seek companions hosting**: Ladybirds, parasitic wasps, hoverflies
- **Beneficial neighbours**: Umbellifer family (parasitoid habitat), Asteraceae (hoverfly habitat)
- **Biocontrol synergy**: Plants with similar pest profiles share predator communities

**This Plant Provides**:
- Habitat for {n} beneficial insects visiting flowers
- Potential predator refuge if unpruned/unharvested
```

### Guidance Rules

```
IF herbivore_count > 15:
  "High pest pressure. Prioritise companions hosting known predators."
  "Consider: Yarrow, fennel, dill (parasitoid wasps); native wildflowers (general predators)"

IF herbivore_count 5-15:
  "Moderate pest pressure. Diverse plantings provide natural balance."

IF herbivore_count < 5:
  "Low documented pest pressure. This plant may provide predator habitat for neighbours."

IF family == "Apiaceae":
  "Umbellifer flowers attract parasitic wasps - excellent biocontrol habitat."

IF family == "Asteraceae":
  "Composite flowers attract hoverflies and predatory beetles."
```

---

## GP4: Disease Control Contribution (from M4)

**Data source**: `pathogens` list, `pathogen_count`, `mycoparasite_fungi`, `fungivores_eats`

**Scientific basis**: Mycoparasitic fungi attack plant pathogens. Fungivorous animals consume pathogenic fungi. Plants hosting these provide disease suppression.

### Static Data Display

| Field | Source | Guild Relevance |
|-------|--------|-----------------|
| Pathogen count | `pathogen_count` | Disease pressure level |
| Key pathogens | `pathogens` list | What diseases affect this plant |
| Mycoparasites hosted | `mycoparasite_fungi` | Beneficial fungi this plant supports |

### Disease Pressure Classification

| Pathogen Count | Level | Implication |
|----------------|-------|-------------|
| > 10 | High | Multiple disease risks; needs diverse biocontrol |
| 3-10 | Moderate | Some disease pressure |
| < 3 | Low | Few documented diseases |
| 0 | Unknown | Not well-studied |

### Output Format

```markdown
### Disease Control Potential

**Pathogen Load**: 5 taxa documented (Moderate)
**Key Diseases**: Powdery mildew (Erysiphe), Rust (Puccinia)

**Guild Recommendations**:
- **Seek companions with**: Mycoparasitic fungi (Trichoderma, Ampelomyces)
- **Avoid clustering**: Plants with identical pathogens (amplifies inoculum)
- **Airflow**: Space plants to reduce humidity-driven disease spread

**This Plant Provides**:
- Hosts {n} mycoparasitic fungi that may protect neighbours
- Soil microbiome contribution to disease suppression
```

### Guidance Rules

```
IF pathogen_count > 10:
  "High disease pressure. Avoid planting with species sharing same pathogens."
  "Seek companions hosting mycoparasitic Trichoderma spp."

IF family == "Rosaceae" AND pathogen includes "rust" OR "scab":
  "Common Rosaceae diseases. Improve airflow; avoid clustering rose family plants."

IF mycoparasite_fungi count > 0:
  "This plant hosts beneficial mycoparasites that may protect neighbours from fungal diseases."
```

---

## GP5: Mycorrhizal Network (from M5)

**Data source**: `is_amf`, `is_emf`, `amf_fungi`, `emf_fungi`, `endophytic_fungi`

**Scientific basis**: Plants sharing mycorrhizal fungi form Common Mycorrhizal Networks (CMNs) enabling nutrient sharing and chemical signaling. AMF and EMF are largely incompatible networks.

### Mycorrhizal Classification

| Type | Typical Plants | Network Properties |
|------|---------------|-------------------|
| AMF (Arbuscular) | Most herbs, grasses, many shrubs | Broad networks, phosphorus transfer |
| EMF (Ectomycorrhizal) | Oaks, beeches, birches, pines | Tree-dominated, nutrient + defense signaling |
| Dual | Some plants form both | Flexible network membership |
| Non-mycorrhizal | Brassicaceae, Chenopodiaceae | No network participation |

### Network Compatibility Rules

| Plant Type | Compatible With | Incompatible With |
|------------|-----------------|-------------------|
| AMF-only | Other AMF plants | EMF-only plants |
| EMF-only | Other EMF plants | AMF-only plants |
| Dual | Both networks | None |
| Non-mycorrhizal | Any (no network effect) | None |

### Output Format

```markdown
### Mycorrhizal Network

**Association**: AMF (Arbuscular Mycorrhizal)
**Documented Fungi**: Glomus spp., Rhizophagus irregularis

**Guild Recommendations**:
- **Network-compatible**: Other AMF plants (most herbs, grasses, shrubs)
- **Potential conflict**: EMF-exclusive trees (oaks, pines) - different networks
- **Soil management**: Avoid excessive tillage to preserve hyphal networks

**This Plant Contributes**:
- Connection point for carbon/phosphorus sharing network
- Potential stress signal relay to network partners
```

### Guidance Rules

```
IF is_amf == TRUE AND is_emf == FALSE:
  "AMF-exclusive. Best paired with other AMF plants (herbs, grasses, most shrubs)."
  "Network bonus with: legumes, Asteraceae, Poaceae"

IF is_emf == TRUE AND is_amf == FALSE:
  "EMF-exclusive. Best paired with other EMF trees (oaks, beeches, birches, pines)."
  "Creates forest-type nutrient-sharing network."

IF is_amf == TRUE AND is_emf == TRUE:
  "Dual mycorrhizal. Can connect to both network types - versatile guild member."

IF family IN ("Brassicaceae", "Chenopodiaceae", "Amaranthaceae"):
  "Non-mycorrhizal family. Does not participate in underground networks."
  "No network conflict, but no network benefit either."
```

---

## GP6: Structural Role (from M6)

**Data source**: `height_m`, `try_growth_form`, `EIVEres-L_complete`

**Scientific basis**: Vertical stratification creates microhabitats. Taller plants shade shorter ones - beneficial only if shorter plants are shade-tolerant.

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
| Tree + Shade herb | High | Herb benefits from canopy |
| Tree + Sun herb | Low | Herb shaded out |
| Shrub + Ground cover | High | Different vertical niches |
| Herb + Herb (same height) | Variable | Depends on resource overlap |

### Output Format

```markdown
### Structural Role

**Layer**: Sub-canopy (7m)
**Growth Form**: Tree
**Light Preference**: EIVE-L 6 (partial sun)

**Guild Recommendations**:
- **Below this plant**: Shade-tolerant herbs (EIVE-L < 5), ferns, woodland groundcovers
- **Same layer**: Avoid other sub-canopy trees (competition for filtered light)
- **Above this plant**: Pairs well under taller canopy trees
- **Climbing**: Suitable structure for shade-tolerant vines

**Structural Contribution**:
- Provides filtered shade for 2-5m zone
- Wind reduction for shorter plants
- Habitat structure for wildlife
```

### Decision Tree

```
IF height > 10m:
  "Canopy layer. Creates significant shade below."
  "Pair with: shade-tolerant understory, woodland herbs, ferns"
  "Avoid pairing with: sun-loving plants in shade zone"

IF height 5-10m:
  "Sub-canopy. Provides partial shade, benefits from canopy protection."
  "Pair with: ground covers, shade-tolerant shrubs"

IF height 2-5m:
  "Tall shrub layer. Mid-structure role."
  "Pair with: low herbs, ground covers below; tolerates taller trees above"

IF height 0.5-2m:
  "Understory. Consider light requirements."
  IF EIVE-L < 3.2:
    "Shade-adapted. Place under trees/tall shrubs."
  ELSE IF EIVE-L > 7.47:
    "Sun-loving. Needs open position, not under canopy."
  ELSE:
    "Flexible. Tolerates range of light conditions."

IF height < 0.5m:
  "Ground cover. Soil protection, weed suppression role."
  "Pair with: any taller plants (provides living mulch)"

IF growth_form == "vine" OR growth_form == "liana":
  "Climber. Needs vertical structure (trees, trellises)."
  "Pair with: trees or tall shrubs as climbing hosts"
```

---

## GP7: Pollinator Contribution (from M7)

**Data source**: `pollinators` list, `pollinator_count`

**Scientific basis**: Plants sharing pollinators create mutual attraction. Quadratic benefit: more overlap = non-linearly better pollination for both plants.

### Pollinator Value Classification

| Pollinator Count | Value | Guild Contribution |
|------------------|-------|-------------------|
| > 20 | Very High | Major pollinator hub - benefits all neighbours |
| 11-20 | High | Significant pollinator attraction |
| 5-10 | Moderate | Useful pollinator support |
| 1-4 | Low | Limited documented pollinator visits |
| 0 | Unknown | May still support pollinators (undocumented) |

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

**Pollinator Value**: High (18 taxa documented)
**Key Visitors**: Bumblebees (Bombus spp.), Honeybees (Apis mellifera), Hoverflies

**Guild Recommendations**:
- **Complement flowering times**: Pair with early/late bloomers for season-long support
- **Pollinator magnet**: This plant attracts pollinators that benefit neighbours
- **Proximity bonus**: Nearby plants with shared pollinators get increased visits

**This Plant Provides**:
- Nectar/pollen for 18+ pollinator species
- Attraction effect increases visits to neighbouring plants
- Supports both generalist and specialist pollinators
```

### Guidance Rules

```
IF pollinator_count > 20:
  "Pollinator champion. Central to guild pollination success."
  "Benefits ALL flowering neighbours through attraction effect."

IF pollinator_count 11-20:
  "Strong pollinator support. Valuable addition to any guild."

IF pollinator_count 5-10:
  "Moderate pollinator support. Combine with high-value plants."

IF pollinator_count < 5:
  "Limited documented pollinators. May have specialist visitors."
  "Consider pairing with pollinator magnets for cross-pollination."

IF family == "Lamiaceae":
  "Mint family - typically excellent for bumblebees and hoverflies."

IF family == "Asteraceae":
  "Daisy family - open florets attract diverse pollinators including hoverflies."

IF family == "Fabaceae":
  "Legume family - important for long-tongued bees."
```

---

## Integrated Guild Potential Output

```markdown
## Guild Potential

### Summary Card

| Metric | Value | Guild Contribution |
|--------|-------|-------------------|
| Phylogenetic | Rosaceae → Malus | Seek non-Rosaceae companions |
| CSR Strategy | C: 65% (Competitive) | Avoid other C-dominant at same height |
| Structural | Sub-canopy (7m) | Provides shade, supports climbers |
| Mycorrhizal | AMF-compatible | Network with herbs, grasses |
| Pest Control | 12 herbivores | Benefits from predator plants |
| Disease Control | 5 pathogens | Avoid pathogen clustering |
| Pollinator | High (18 taxa) | Attracts pollinators for neighbours |

### Top Companion Recommendations

Based on this plant's characteristics:

1. **Shade-tolerant ground cover** (EIVE-L < 3.2) - benefits from canopy
2. **Umbellifer herbs** (Apiaceae) - different family, hosts parasitoid wasps
3. **Aromatic Lamiaceae** - pest-deterrent, pollinator support, different family
4. **Nitrogen-fixing legumes** - soil enrichment, different family, AMF-compatible

### Avoid

- Other Rosaceae at same height (shared pests, competition)
- Sun-loving herbs directly below (will be shaded out)
- EMF-exclusive trees (network incompatibility)

**→ [Launch GuildBuilder]** for optimised companion scoring with specific plants
```

---

## Data Column Reference

| Column | Source | Used For |
|--------|--------|----------|
| `family` | WFO | GP1 - Phylogenetic |
| `genus` | WFO | GP1 - Phylogenetic |
| `C`, `S`, `R` | Stage 3 CSR | GP2 - Growth compatibility |
| `height_m` | TRY | GP2, GP6 - Structure |
| `EIVEres-L_complete` | Stage 2 | GP2, GP6 - Light compatibility |
| `try_growth_form` | TRY | GP2, GP6 - Structure |
| `herbivores` | Phase 0 | GP3 - Pest control |
| `herbivore_count` | Phase 0 | GP3 - Pest control |
| `pathogens` | Phase 0 | GP4 - Disease control |
| `pathogen_count` | Phase 0 | GP4 - Disease control |
| `is_amf`, `is_emf` | Phase 0 | GP5 - Mycorrhizal |
| `pollinators` | Phase 0 | GP7 - Pollinator support |
| `pollinator_count` | Phase 0 | GP7 - Pollinator support |

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
