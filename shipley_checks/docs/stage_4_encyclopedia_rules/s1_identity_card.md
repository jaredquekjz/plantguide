# S1: Identity Card Rules

Rules for generating the plant identity/header section of encyclopedia articles. This section provides at-a-glance identification and key morphological traits for gardeners.

## Output Structure

```markdown
# {Scientific Name}
**Common Names**: {English vernacular names, semicolon-separated, Title Case}
**Chinese**: {Chinese vernacular names}
**Family**: {family}
**Type**: {growth form with phenology, e.g., "Deciduous tree", "Evergreen shrub"}
**Mature Height**: {height}m — {friendly description}
**Leaves**: {leaf type}, {area}cm² — {size description}
**Seeds**: {mass} — {gardening implications}
```

## Example Output

```markdown
# Quercus robur
**Common Names**: Pedunculate Oak; Common Oak; English Oak; Truffle Oak; Acorn Tree
**Chinese**: 歐洲白櫟; 夏櫟; 夏栎
**Family**: Fagaceae
**Type**: Deciduous tree
**Mature Height**: 27m — Large tree, needs significant space
**Leaves**: Broadleaved, 30cm² — Medium-sized
**Seeds**: 3.0g — Medium seeds, bird food
```

---

## Data Sources

| Field | Column | Source | Notes |
|-------|--------|--------|-------|
| Scientific name | `wfo_scientific_name` | World Flora Online | WFO-verified canonical name |
| Family | `family` | WFO/TRY | Taxonomic family |
| Growth form | `try_growth_form` | TRY database | tree/shrub/herb/vine/etc. |
| Leaf phenology | `try_leaf_phenology` | TRY database | evergreen/deciduous |
| Woodiness | `try_woodiness` | TRY database | woody/herbaceous |
| Mature height | `height_m` | TRY Global Spectrum | Adult plant height at maturity |
| Leaf area | `LA` | TRY Global Spectrum | Leaf area in mm² |
| Seed mass | `logSM` | TRY Global Spectrum | Log seed mass (convert with exp()) |
| Leaf type | `try_leaf_type` | TRY database | broadleaved/needleleaved |
| English names | `vernacular_name_en` | iNaturalist | Via Phase 1 extraction |
| Chinese names | `vernacular_name_zh` | iNaturalist | Via Phase 1 extraction |

### TRY Global Spectrum Dataset

The morphological traits (height, leaf area, seed mass) come from the **TRY Global Spectrum** dataset, a curated compilation of plant trait data from TRY and AusTraits databases.

**Reference**: Díaz et al. (2016) "The global spectrum of plant form and function", Nature 529:167-171.

**Key definitions**:
- **Plant height (H)**: Adult plant height - the typical height of the upper boundary of the main photosynthetic tissues at maturity (unit: metres)
- **Leaf area (LA)**: One-sided projected area of an individual leaf or leaflet (unit: mm²)
- **Seed mass (SM)**: Oven-dry mass of an individual seed or seed-equivalent dispersal unit (unit: mg; stored as log-transformed values)

---

## Field Rules

### Type (Growth Form + Phenology)

Combines `try_growth_form`, `try_woodiness`, and `try_leaf_phenology` into a single readable label.

**Implementation**: `translate_growth_form_full()` in s1_identity.rs

**Translation logic**:

| Growth Form | Phenology | Output |
|-------------|-----------|--------|
| tree | deciduous | Deciduous tree |
| tree | evergreen | Evergreen tree |
| tree | - | Tree |
| shrub | deciduous | Deciduous shrub |
| shrub | evergreen | Evergreen shrub |
| shrub | - | Shrub |
| herb | - | Herbaceous perennial |
| graminoid/grass | - | Grass or sedge |
| vine/liana/climber | woody | Scrambling shrub |
| vine/liana/climber | woody + deciduous | Scrambling shrub (deciduous) |
| vine/liana/climber | herbaceous | Climbing vine |
| fern | - | Fern |
| succulent | - | Succulent |

**Special case**: Woody climbers (e.g., Rosa canina) are labelled "Scrambling shrub" rather than "Climbing vine" as this better reflects their garden behaviour.

### Mature Height

Height is the **adult plant height at maturity** from TRY Global Spectrum.

| Height Range | Format | Description |
|--------------|--------|-------------|
| >= 20m | `{:.0}m` | Large tree, needs significant space |
| 10-20m | `{:.0}m` | Medium tree |
| 4-10m | `{:.0}m` | Small tree or large shrub |
| 1.5-4m | `{:.1}m` | Shrub height |
| 0.5-1.5m | `{:.1}m` | Low shrub or tall groundcover |
| 0.1-0.5m | `{:.0}cm` | Low groundcover |
| < 0.1m | `{:.0}cm` | Creeping or mat-forming |

### Leaves

Combines leaf type and leaf area for gardener-friendly description.

**Leaf type** (from `try_leaf_type`):
- "needle" → "Needles"
- "scale" → "Scale-like leaves"
- other/missing → "Broadleaved"

**Leaf area** (from `LA`, convert mm² to cm²):

| Area (cm²) | Description |
|------------|-------------|
| > 100 | Very large, bold foliage |
| 30-100 | Large leaves |
| 10-30 | Medium-sized |
| 3-10 | Small leaves |
| < 3 | Fine-textured foliage |

**Output format**: `{Leaf type}, {area}cm² — {description}`

Example: `Broadleaved, 30cm² — Medium-sized`

### Seeds

Seed mass helps gardeners understand self-seeding potential and wildlife value.

**Input**: `logSM` (log-transformed seed mass). Convert to mg with `exp(logSM)`.

| Seed Mass | Format | Description |
|-----------|--------|-------------|
| >= 5000mg (5g) | `{:.0}g` | Large seeds/nuts, wildlife food |
| 500-5000mg | `{:.1}g` | Medium seeds, bird food |
| 10-500mg | `{:.0}mg` | Small seeds |
| 1-10mg | `{:.1}mg` | Tiny seeds, may self-sow |
| < 1mg | `{:.2}mg` | Dust-like, spreads freely |

**Examples**:
- Quercus robur (oak acorn): 3.0g — Medium seeds, bird food
- Rosa canina (rose hip): 18mg — Small seeds
- Trifolium repens (clover): 0.53mg — Dust-like, spreads freely

### Vernacular Names

**English names** (`vernacular_name_en`):
- Split by semicolon
- Convert to Title Case
- Rejoin with semicolon separator

**Chinese names** (`vernacular_name_zh`):
- Display as-is (semicolon-separated)
- Include both traditional and simplified characters where available

**Output**: Only display if non-empty and not "NA".

---

## Vernacular Names Reference (61 Languages)

**Data Source**: iNaturalist taxon vernaculars (Phase 1 extraction)

**Coverage**: Variable by species and language. English has highest coverage.

### Language Codes (Full Reference)

| Code | Language | Code | Language | Code | Language |
|------|----------|------|----------|------|----------|
| af | Afrikaans | hu | Hungarian | pt | Portuguese |
| ar | Arabic | id | Indonesian | ro | Romanian |
| be | Belarusian | it | Italian | ru | Russian |
| bg | Bulgarian | ja | Japanese | sat | Santali |
| br | Breton | ka | Georgian | si | Sinhala |
| ca | Catalan | kk | Kazakh | sk | Slovak |
| cs | Czech | kn | Kannada | sl | Slovenian |
| da | Danish | ko | Korean | sq | Albanian |
| de | German | lb | Luxembourgish | sr | Serbian |
| el | Greek | lt | Lithuanian | sv | Swedish |
| en | English | lv | Latvian | sw | Swahili |
| eo | Esperanto | mi | Māori | th | Thai |
| es | Spanish | mk | Macedonian | tr | Turkish |
| et | Estonian | mr | Marathi | uk | Ukrainian |
| eu | Basque | myn | Mayan | vi | Vietnamese |
| fa | Persian | nb | Norwegian Bokmål | zh | Chinese |
| fi | Finnish | nl | Dutch | | |
| fil | Filipino | oc | Occitan | | |
| fr | French | oj | Ojibwe | | |
| gl | Galician | pl | Polish | | |
| haw | Hawaiian | | | | |
| he | Hebrew | | | | |
| hr | Croatian | | | | |

**Current implementation**: Display English and Chinese only.

**Future UI**: May filter to user's locale preference.

---

## Closest Relatives (Subsection)

Shows the 5 closest phylogenetic relatives within the same genus, helping gardeners find alternatives with similar care requirements.

### Data Sources

| Field | Source | Notes |
|-------|--------|-------|
| Phylogenetic distance | `compact_tree_11711.bin` | Pre-computed tree from V.PhyloMaker2 |
| Species mapping | `mixgb_wfo_to_tree_mapping_11711.csv` | WFO ID to tree tip mapping |
| Genus | `genus` | From plant parquet |

### Output Format

```markdown
### Closest Relatives

*5 closest oaks (from 42 *Quercus* species in database, by evolutionary distance):*

| Species | Common Name | Relatedness |
|---------|-------------|-------------|
| *Quercus petraea* | Sessile Oak | Very close |
| *Quercus pubescens* | Downy Oak | Close |
| ... | ... | ... |

*These oaks need similar soil, water, and care—handy if you want alternatives. But they catch the same bugs and diseases, so mix in plants from different families.*
```

### Distance Thresholds

Phylogenetic distance (branch lengths in Myr) mapped to labels:

| Distance | Label |
|----------|-------|
| < 5 | Very close |
| 5-15 | Close |
| 15-40 | Moderate |
| 40-80 | Distant |
| >= 80 | Very distant |

### Genus Plurals

Common genera use friendly plural names:

| Genus | Plural | Genus | Plural |
|-------|--------|-------|--------|
| Quercus | oaks | Trifolium | clovers |
| Rosa | roses | Vicia | vetches |
| Acer | maples | Geranium | geraniums |
| Prunus | cherries/plums | Ranunculus | buttercups |
| Salix | willows | Carex | sedges |
| Pinus | pines | Festuca | fescues |
| Betula | birches | Poa | meadow-grasses |
| Fagus | beeches | | |
| Fraxinus | ashes | | |
| Malus | apples | | |
| Pyrus | pears | | |
| Sorbus | rowans | | |
| Crataegus | hawthorns | | |
| Cornus | dogwoods | | |
| Viburnum | viburnums | | |
| Rhododendron | rhododendrons | | |

Other genera default to "species".

### Edge Cases

- **Only one species in genus**: Show message "*This is the only *{Genus}* species in our database.*"
- **Distance calculation failed**: Show message "*Could not calculate evolutionary distances for *{Genus}* species.*"

---

## Edge Cases (General)

- **Missing height**: Omit the Mature Height line
- **Missing leaf area**: Omit the Leaves line
- **Missing seed mass**: Omit the Seeds line
- **Missing leaf phenology**: Use growth form alone (e.g., "Tree" instead of "Deciduous tree")
- **Missing growth form**: Fall back to woodiness ("Woody plant" or "Herbaceous plant")
- **Missing vernacular names**: Omit the line entirely
