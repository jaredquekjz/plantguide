# Phase 8 DataFusion API Test Plan

## Overview

Test plan for the Rust-based DataFusion query engine and REST API serving plant ecological data from Phase 7 SQL-optimized parquets.

**Server:** `cargo run --features api --bin api_server`
**Default port:** 3000
**Base URL:** `http://localhost:3000`

## Data Summary

| Dataset | Records | Columns | Description |
|---------|---------|---------|-------------|
| plants | 11,713 | 68 | Plant encyclopedia with EIVE, CSR, traits, ecosystem services |
| organisms | 290,880 | 9 | Plant-organism interactions (pollinators, pests, biocontrol) |
| fungi | 100,013 | 17 | Plant-fungus associations (mycorrhizal, pathogenic, biocontrol) |

---

## 1. Health Check

```bash
curl http://localhost:3000/health
```

**Expected:** `{"status":"healthy","timestamp":"..."}`

---

## 2. Plant Search Endpoints

### 2.1 Basic EIVE Filtering

**Sun-loving, drought-tolerant plants (Mediterranean garden):**
```bash
curl "http://localhost:3000/api/plants/search?min_light=7&max_moisture=4&limit=20"
```

**Shade plants for woodland understory:**
```bash
curl "http://localhost:3000/api/plants/search?max_light=4&min_moisture=5&limit=20"
```

**Acid-loving plants (heathland/bog):**
```bash
curl "http://localhost:3000/api/plants/search?max_ph=4&min_moisture=6&limit=20"
```

**Alkaline-tolerant plants (chalk grassland):**
```bash
curl "http://localhost:3000/api/plants/search?min_ph=7&limit=20"
```

### 2.2 CSR Strategy Filtering

**Competitive dominants (canopy trees):**
```bash
curl "http://localhost:3000/api/plants/search?min_c=0.6&limit=20"
```

**Stress-tolerant plants (rock gardens, green roofs):**
```bash
curl "http://localhost:3000/api/plants/search?min_s=0.6&limit=20"
```

**Ruderal colonizers (pioneer species):**
```bash
curl "http://localhost:3000/api/plants/search?min_r=0.6&limit=20"
```

### 2.3 Boolean Trait Filters

**Low-maintenance drought-tolerant plants:**
```bash
curl "http://localhost:3000/api/plants/search?drought_tolerant=true&maintenance_level=low&limit=20"
```

**Fast-growing plants for quick establishment:**
```bash
curl "http://localhost:3000/api/plants/search?fast_growing=true&limit=20"
```

### 2.4 Combined Ecological Queries

**Nitrogen-fixing shade plants (forest food guild):**
```bash
curl "http://localhost:3000/api/plants/search?max_light=5&nitrogen_lover=true&limit=20"
```

**Full-sun alkaline-tolerant plants (prairie restoration):**
```bash
curl "http://localhost:3000/api/plants/search?full_sun=true&alkaline_soil=true&limit=20"
```

---

## 3. Single Plant Lookup

### 3.1 By WFO ID

```bash
# Common oak (Quercus robur)
curl "http://localhost:3000/api/plants/wfo-0000512325"

# Common nettle (Urtica dioica)
curl "http://localhost:3000/api/plants/wfo-0000511042"
```

**Expected:** Full plant record with all 68 columns

---

## 4. Organism Interactions

### 4.1 All Organisms for a Plant

```bash
curl "http://localhost:3000/api/plants/wfo-0000512325/organisms"
```

### 4.2 Filter by Interaction Type

**Pollinators only:**
```bash
curl "http://localhost:3000/api/plants/wfo-0000512325/organisms?interaction_type=pollinators"
```

**Herbivores (pests):**
```bash
curl "http://localhost:3000/api/plants/wfo-0000512325/organisms?interaction_type=herbivores"
```

**Biocontrol agents:**
```bash
curl "http://localhost:3000/api/plants/wfo-0000512325/organisms?interaction_type=predators_hasHost"
```

---

## 5. Fungal Associations

### 5.1 All Fungi for a Plant

```bash
curl "http://localhost:3000/api/plants/wfo-0000512325/fungi"
```

### 5.2 Filter by Guild Category

**Mycorrhizal partners:**
```bash
curl "http://localhost:3000/api/plants/wfo-0000512325/fungi?guild_category=mycorrhizal"
```

**Pathogenic fungi:**
```bash
curl "http://localhost:3000/api/plants/wfo-0000512325/fungi?guild_category=pathogenic"
```

**Biocontrol fungi (entomopathogenic, mycoparasitic):**
```bash
curl "http://localhost:3000/api/plants/wfo-0000512325/fungi?guild_category=biocontrol"
```

---

## 6. Similarity Search

Find ecologically similar plants based on EIVE Euclidean distance in 5D space (L, M, T, N, R).

### 6.1 Basic Similarity

```bash
curl -X POST http://localhost:3000/api/plants/similar \
  -H "Content-Type: application/json" \
  -d '{"plant_id": "wfo-0000512325", "top_k": 10}'
```

### 6.2 Extended Similarity Search

```bash
curl -X POST http://localhost:3000/api/plants/similar \
  -H "Content-Type: application/json" \
  -d '{"plant_id": "wfo-0000511042", "top_k": 50}'
```

**Use case:** Find substitutes for a plant that won't grow in your climate.

---

## 7. Guild Scoring

Score a plant combination using the 7-metric guild compatibility system.

### 7.1 Forest Garden Guild (Classic 7-layer)

```bash
curl -X POST http://localhost:3000/api/guilds/score \
  -H "Content-Type: application/json" \
  -d '{
    "plant_ids": [
      "wfo-0000512325",
      "wfo-0000511042",
      "wfo-0000203882",
      "wfo-0000189913",
      "wfo-0000511356"
    ]
  }'
```

### 7.2 Minimal Guild (3 plants)

```bash
curl -X POST http://localhost:3000/api/guilds/score \
  -H "Content-Type: application/json" \
  -d '{
    "plant_ids": [
      "wfo-0000512325",
      "wfo-0000511042",
      "wfo-0000203882"
    ]
  }'
```

**Expected response:**
```json
{
  "guild_size": 5,
  "overall_score": 72.5,
  "metrics": {
    "m1_phylogenetic_diversity": 85.2,
    "m2_csr_balance": 68.4,
    "m3_eive_compatibility": 71.0,
    "m4_pollinator_pest_balance": 65.8,
    "m5_pest_biocontrol": 78.3,
    "m6_growth_form_diversity": 82.1,
    "m7_nutrient_cycling": 56.7
  }
}
```

---

## 8. Performance Benchmarks

### 8.1 Search Latency

```bash
# Time 100 search requests
for i in {1..100}; do
  curl -s -o /dev/null -w "%{time_total}\n" \
    "http://localhost:3000/api/plants/search?min_light=7&limit=10"
done | awk '{sum+=$1} END {print "Avg:", sum/NR*1000, "ms"}'
```

**Target:** <10ms average

### 8.2 Guild Scoring Latency

```bash
# Time 50 guild scoring requests
for i in {1..50}; do
  curl -s -o /dev/null -w "%{time_total}\n" -X POST \
    http://localhost:3000/api/guilds/score \
    -H "Content-Type: application/json" \
    -d '{"plant_ids":["wfo-0000512325","wfo-0000511042","wfo-0000203882"]}'
done | awk '{sum+=$1} END {print "Avg:", sum/NR*1000, "ms"}'
```

**Target:** <500ms average

### 8.3 Cache Effectiveness

```bash
# First request (cache miss)
time curl -s "http://localhost:3000/api/plants/search?min_light=7&limit=10" > /dev/null

# Second request (cache hit)
time curl -s "http://localhost:3000/api/plants/search?min_light=7&limit=10" > /dev/null
```

**Expected:** Cache hit should be <1ms

---

## 9. Error Handling Tests

### 9.1 Non-existent Plant

```bash
curl "http://localhost:3000/api/plants/wfo-9999999999"
```

**Expected:** `404 Not Found` with error message

### 9.2 Invalid Filter Values

```bash
curl "http://localhost:3000/api/plants/search?min_light=invalid"
```

**Expected:** `400 Bad Request` or graceful handling

### 9.3 Empty Guild

```bash
curl -X POST http://localhost:3000/api/guilds/score \
  -H "Content-Type: application/json" \
  -d '{"plant_ids": []}'
```

**Expected:** Error or minimum guild size warning

---

## 10. Practical Use Case Tests

### 10.1 Pollinator Garden Design

Find plants that support pollinators and have complementary bloom times:

```bash
# Step 1: Find full-sun flowering plants
curl "http://localhost:3000/api/plants/search?full_sun=true&limit=50" | \
  jq '.data[].wfo_taxon_id'

# Step 2: Check pollinator associations for each
curl "http://localhost:3000/api/plants/wfo-XXXXX/organisms?interaction_type=pollinators"

# Step 3: Score the final guild
curl -X POST http://localhost:3000/api/guilds/score -H "Content-Type: application/json" \
  -d '{"plant_ids": ["wfo-...", "wfo-...", "wfo-..."]}'
```

### 10.2 Biocontrol-Optimized Guild

Find plants that host entomopathogenic fungi:

```bash
# Find plants with biocontrol fungi
curl "http://localhost:3000/api/plants/wfo-0000512325/fungi?guild_category=biocontrol"
```

### 10.3 Low-Maintenance Xeriscape

```bash
# Find drought-tolerant, low-maintenance plants
curl "http://localhost:3000/api/plants/search?drought_tolerant=true&maintenance_level=low&max_moisture=4&limit=30"
```

---

## Appendix: Column Reference

### Plants Table (68 columns)

| Category | Columns |
|----------|---------|
| Identity | wfo_taxon_id, wfo_scientific_name, family, genus |
| EIVE | EIVE_L, EIVE_M, EIVE_T, EIVE_N, EIVE_R (+ _complete flags) |
| CSR | C, S, R, C_norm, S_norm, R_norm |
| Boolean traits | drought_tolerant, fast_growing, shade_tolerant, full_sun, nitrogen_lover, low_nitrogen, acid_soil, alkaline_soil, wet_soil, dry_soil |
| Ecosystem services | npp_rating, decomposition_rating, nitrogen_fixation_rating (+ confidence) |
| Vernaculars | vernacular_name_{en,es,fr,de,it,pt,nl,zh,ja,ar}, vernacular_source |
| TRY traits | try_woodiness, try_growth_form, try_habitat_adaptation, try_leaf_type, try_leaf_phenology, try_photosynthesis_pathway, try_mycorrhiza_type |
| Physical | height_m, LA, LDMC, SLA, logLA, logNmass, logLDMC, logSLA, logH, logSM |

### Organisms Table (9 columns)

| Column | Description |
|--------|-------------|
| plant_wfo_id | Foreign key to plants |
| organism_taxon | Scientific name of organism |
| interaction_type | pollinators, herbivores, pathogens, flower_visitors, predators_*, fungivores_eats |
| interaction_category | beneficial, pest, biocontrol, fungivore |
| is_* | Boolean filters: is_pollinator, is_pest, is_biocontrol, is_pathogen, is_herbivore |

### Fungi Table (17 columns)

| Column | Description |
|--------|-------------|
| plant_wfo_id | Foreign key to plants |
| fungus_taxon | Scientific name of fungus |
| guild_type | amf_fungi, emf_fungi, pathogenic_fungi, entomopathogenic_fungi, etc. |
| guild_category | mycorrhizal, pathogenic, biocontrol, endophytic, saprotrophic |
| functional_role | beneficial, harmful, biocontrol, neutral |
| is_* | Boolean filters: is_mycorrhizal, is_amf, is_emf, is_pathogenic, is_biocontrol, is_entomopathogen, is_mycoparasite, is_endophytic, is_saprotrophic |
