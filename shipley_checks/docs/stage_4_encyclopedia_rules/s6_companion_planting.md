# S6: Guild Potential (Companion Planting Teaser)

Brief static section highlighting this plant's guild-relevant traits, with call-to-action for dynamic GuildBuilder.

## Scope

**Static encyclopedia**: Shows THIS plant's traits relevant to guild assembly
**Dynamic GuildBuilder**: Does actual pairwise compatibility analysis

Most companion planting logic requires comparing Plant A to Plant B - this is the GuildBuilder's job, not static encyclopedia content.

---

## Static Content: Guild-Relevant Traits

### From Existing Sections (Cross-Reference)

| Trait | Source Section | Guild Relevance |
|-------|---------------|-----------------|
| CSR strategy | S3: Maintenance Profile | Competition/compatibility |
| EIVE values | S2: Growing Requirements | Requirement matching |
| Height | S1: Identity Card | Structural layering |
| Nitrogen fixation | S4: Ecosystem Services | Soil enrichment potential |
| Pollinator count | S5: Biological Interactions | Pollinator guild value |
| Mycorrhizal type | S5: Biological Interactions | Network compatibility |

### New Fields for Guild Potential

| Field | Data Source | Output |
|-------|-------------|--------|
| Structural layer | `height_m` | Canopy / Understory / Ground cover |
| Competition potential | `C` score | High competitor / Balanced / Non-competitive |
| Mycorrhizal network | `is_amf`, `is_emf` | AMF-compatible / EMF-compatible / Unknown |

---

## Output Format

```markdown
## Guild Potential

**Structural Role**: Understory (1.5m)
**Competition**: Moderate (C: 45%)
**Special Value**: Nitrogen-fixer (Fabaceae)
**Mycorrhizal**: AMF-compatible

### Compatibility Hints
- Pairs well with: Canopy trees, ground covers
- Benefits neighbours: Soil nitrogen enrichment
- Prefers similar conditions: EIVE-M 5, EIVE-L 6, EIVE-R 5

### Cautions
- May be outcompeted by C-dominant plants
- Requires similar moisture regime as companions

**→ Use the GuildBuilder to find optimal companions for this plant**
```

---

## Structural Layer Classification

| Height | Layer | Guild Role |
|--------|-------|------------|
| > 5m | Canopy | Shade provider, wind break |
| 2-5m | Sub-canopy | Filtered light, structure |
| 0.5-2m | Understory | Mid-layer, habitat |
| < 0.5m | Ground cover | Soil protection, weed suppression |

---

## Competition Potential (from CSR)

| C Score | Label | Implication |
|---------|-------|-------------|
| > 60% | High competitor | May outcompete neighbours; give space |
| 40-60% | Moderate | Standard spacing |
| < 40% | Non-competitive | Tolerates close planting |

---

## Special Guild Values

### Nitrogen Fixers
```markdown
**Special Value**: Nitrogen-fixer
Benefits heavy-feeding neighbours through soil enrichment.
```
**Detection**: `nitrogen_fixation_rating` in (Very High, High) OR family = Fabaceae

### Pollinator Magnets
```markdown
**Special Value**: Pollinator magnet (25+ taxa)
Attracts diverse pollinators; benefits neighbouring crops.
```
**Detection**: `pollinator_count` > 20

### Deep Rooters (if height data suggests tree/large shrub)
```markdown
**Special Value**: Deep-rooted
May access nutrients from deeper soil layers; potential hydraulic lift.
```

---

## GuildBuilder Call-to-Action

The static encyclopedia provides traits. The dynamic GuildBuilder uses these traits to:

1. **Find compatible plants** - EIVE similarity, CSR compatibility
2. **Optimize pest control** - Shared biocontrol networks
3. **Design food forests** - Multi-layer structural guilds
4. **Maximize pollination** - Pollinator community overlap

```markdown
**→ Build a Guild**
Create an optimized planting combination using the GuildBuilder.
[Launch GuildBuilder with this plant]
```

---

## What's NOT in Static Encyclopedia

The following require dynamic pairwise analysis (GuildBuilder territory):

| Feature | Why Dynamic |
|---------|-------------|
| "Good companions" list | Requires comparing to all 11,711 plants |
| Mycorrhizal network matches | O(n²) fungal overlap calculation |
| Biocontrol synergies | Cross-plant herbivore-predator matching |
| Entomopathogen zones | Herbivore → fungi → plant chain analysis |
| EIVE similarity ranking | Pairwise distance calculation |

These are documented in GuildBuilder/explanation engine documentation, not encyclopedia rules.
