# S1: Identity Card Rules

Rules for generating the plant identity/header section of encyclopedia articles.

## Data Sources

| Field | Column | Source |
|-------|--------|--------|
| Scientific name | `wfo_scientific_name` | WFO-verified |
| WFO ID | `wfo_taxon_id` | WFO backbone |
| Family | `family` | WFO/TRY |
| Genus | `genus` | WFO/TRY |
| Growth form | `try_growth_form` | TRY database |
| Life form | `life_form_simple` | Derived |
| Height | `height_m` | TRY database |
| Leaf persistence | `try_leaf_phenology` | TRY database |
| Woodiness | `try_woodiness` | TRY database |
| Vernacular names | `vernacular_name_*` | iNaturalist (61 languages) |

---

## Vernacular Names (61 Languages)

**Data Source**: iNaturalist taxon vernaculars (Phase 1 extraction)

**Coverage**: Variable by species and language. English has highest coverage.

### Language Codes

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

### Output Rules

**Current generation**: Output ALL available vernacular names for comprehensive documentation.

**Future UI**: Filter to show:
- English (primary)
- Chinese (if English unavailable)
- User's locale preference

### Column Reference

| Column | Description |
|--------|-------------|
| `vernacular_name_en` | English common name |
| `vernacular_name_zh` | Chinese common name |
| `vernacular_name_de` | German common name |
| ... | (61 language columns total) |
| `n_vernaculars_total` | Count of languages with names |

### Output Format

```markdown
## Common Names

**English**: English Oak, Pedunculate Oak
**German**: Stieleiche
**French**: Chêne pédonculé
**Spanish**: Roble común
**Chinese**: 夏栎
**Japanese**: ヨーロッパナラ
... (all available languages)

*Names available in 35 languages*
```

## Output Structure

```markdown
# {Scientific Name}

**Family**: {family}
**Growth Form**: {growth_form_label}
**Height**: {height_range}
**Leaf Type**: {leaf_phenology_label}
**Hardiness**: {hardiness_zone}
**Native Climate**: {koppen_zones}
```

## Translation Rules

### Growth Form (`try_growth_form`)

| Value | Label | Icon |
|-------|-------|------|
| `tree` | Tree | 🌳 |
| `shrub` | Shrub | 🌿 |
| `herb` | Herbaceous | 🌱 |
| `graminoid` | Grass/Sedge | 🌾 |
| `vine` | Climber | 🌿 |
| `fern` | Fern | 🌿 |
| `succulent` | Succulent | 🌵 |
| NA | Unknown | - |

### Leaf Phenology (`try_leaf_phenology`)

| Value | Label |
|-------|-------|
| `evergreen` | Evergreen |
| `deciduous` | Deciduous |
| `semi_deciduous` | Semi-evergreen |
| NA | Not specified |

**Coverage**: ~50% of species have leaf phenology data

### Height Classification (`height_m`)

| Height (m) | Category | Typical Use |
|------------|----------|-------------|
| < 0.3 | Ground cover | Edges, rockeries |
| 0.3 - 1.0 | Low | Borders, containers |
| 1.0 - 3.0 | Medium | Hedging, screening |
| 3.0 - 10.0 | Tall shrub/Small tree | Specimen, structure |
| 10.0 - 20.0 | Medium tree | Shade, shelter |
| > 20.0 | Large tree | Parkland, woodland |

### Hardiness Zone (from `TNn_q05`)

Derive USDA hardiness zone from absolute minimum temperature:

| TNn_q05 (°C) | USDA Zone | Label |
|--------------|-----------|-------|
| < -45.6 | 1 | Extreme arctic |
| -45.6 to -40.0 | 2 | Subarctic |
| -40.0 to -34.4 | 3 | Very cold |
| -34.4 to -28.9 | 4 | Cold |
| -28.9 to -23.3 | 5 | Cold temperate |
| -23.3 to -17.8 | 6 | Cool temperate |
| -17.8 to -12.2 | 7 | Mild temperate |
| -12.2 to -6.7 | 8 | Warm temperate |
| -6.7 to -1.1 | 9 | Subtropical |
| -1.1 to 4.4 | 10 | Tropical margin |
| > 4.4 | 11+ | Tropical |

### Köppen Climate Zones

From Stage 4 classification (when available). Present as:
- Primary zone(s) where most occurrences found
- Interpretation for gardeners

Example output:
```
**Native Climate**: Cfb (Temperate oceanic), Csa (Mediterranean)
Thrives in temperate maritime climates; tolerates Mediterranean dry summers.
```

## Example Output

```markdown
# Quercus robur

**Family**: Fagaceae
**Growth Form**: Tree
**Height**: 20-35m (large tree)
**Leaf Type**: Deciduous
**Hardiness**: Zone 5 (-28°C)
**Native Climate**: Cfb (Temperate oceanic)

A long-lived deciduous oak native to Europe, forming a broad spreading crown.
Widely planted as a specimen and parkland tree.
```

## Edge Cases

- **Missing height**: Use growth form to infer typical range
- **Missing leaf phenology**: Omit or state "Not specified"
- **Missing TNn data**: Use BIO_6_q05 as fallback (less precise)
- **Non-European species**: Köppen zones may be incomplete; rely more on climate envelope
