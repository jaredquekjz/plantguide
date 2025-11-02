# Test Guild Selection Strategy

## Overview

Strategy for selecting 5-plant guilds to validate the guild compatibility scoring framework. Goal: Create clear examples of BAD guilds (score → -1) and GOOD guilds (score → +1) to test framework discrimination.

---

## Scoring Components Recap

### NEGATIVE FACTORS (Higher = Worse)
- **N1 (40%)**: Pathogenic fungi overlap - shared disease vulnerabilities
- **N2 (30%)**: Herbivore overlap - shared pest vulnerabilities
- **N3 (30%)**: Non-fungal pathogen overlap - bacterial/viral vulnerabilities

### POSITIVE FACTORS (Higher = Better)
- **P1 (30%)**: Herbivore control - cross-plant biocontrol via predators + entomopathogenic fungi
- **P2 (30%)**: Pathogen control - disease suppression via antagonists + mycoparasites
- **P3 (25%)**: Shared beneficial fungi - mycorrhizae, endophytes, saprotrophs networks
- **P4 (15%)**: Taxonomic diversity - different families reduce transmission risk

**Final Score**: `guild_score = positive_benefit_score - negative_risk_score` → [-1, +1]

---

## BAD GUILD Selection Strategy

**Goal**: Maximize negative_risk_score (→ 1.0), minimize positive_benefit_score (→ 0.0)

### Step 1: Query for High Pathogen Overlap

```sql
-- Find genera/families with many shared pathogenic fungi
WITH plant_pathogens AS (
    SELECT
        plant_wfo_id,
        wfo_scientific_name,
        genus,
        family,
        pathogenic_fungi,
        pathogenic_fungi_count
    FROM read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet')
    WHERE pathogenic_fungi_count >= 10  -- High pathogen load
),
pathogen_overlap AS (
    SELECT
        a.genus,
        a.family,
        UNNEST(a.pathogenic_fungi) as fungus,
        COUNT(DISTINCT a.plant_wfo_id) as plant_count
    FROM plant_pathogens a
    GROUP BY a.genus, a.family, fungus
    HAVING plant_count >= 3  -- Shared across 3+ plants
)
SELECT
    genus,
    family,
    COUNT(DISTINCT fungus) as shared_fungi_count,
    AVG(plant_count) as avg_plants_per_fungus
FROM pathogen_overlap
GROUP BY genus, family
ORDER BY shared_fungi_count DESC, avg_plants_per_fungus DESC
LIMIT 10
```

**Selection criteria for BAD guild:**
1. **Same genus** (e.g., all Acacia, all Rosa, all Solanum)
2. **High pathogenic fungi count per plant** (15+ fungi each)
3. **High overlap** (20+ fungi shared across 4-5 plants)
4. **Host-specific pathogens** (severity weight = 1.0)
5. **No cross-plant benefits** (different ecological niches, no shared visitors/predators)
6. **Low beneficial fungi** (few mycorrhizae, endophytes, saprotrophs)

### Step 2: Validate Shared Herbivores

```sql
-- Check herbivore overlap for candidate plants
WITH candidate_plants AS (
    SELECT UNNEST([
        'wfo-0000173762',  -- Candidate 1
        'wfo-0000173754',  -- Candidate 2
        'wfo-0000204086',  -- Candidate 3
        'wfo-0000202567',  -- Candidate 4
        'wfo-0000186352'   -- Candidate 5
    ]) as plant_wfo_id
),
plant_herbivores AS (
    SELECT
        plant_wfo_id,
        UNNEST(herbivores) as herbivore
    FROM read_parquet('data/stage4/plant_organism_profiles.parquet')
    WHERE plant_wfo_id IN (SELECT plant_wfo_id FROM candidate_plants)
)
SELECT
    herbivore,
    COUNT(DISTINCT plant_wfo_id) as plant_count
FROM plant_herbivores
GROUP BY herbivore
HAVING plant_count >= 2
ORDER BY plant_count DESC
```

**Target**: 5+ shared herbivores across 3-5 plants

### Step 3: Check for Absence of Benefits

```sql
-- Verify NO cross-plant benefits exist
SELECT
    plant_a,
    plant_b,
    beneficial_predator_count
FROM read_parquet('data/stage4/cross_plant_benefits.parquet')
WHERE plant_a IN (SELECT * FROM candidate_plants)
  AND plant_b IN (SELECT * FROM candidate_plants)
```

**Target**: Zero or near-zero beneficial relationships

---

## GOOD GUILD Selection Strategy

**Goal**: Minimize negative_risk_score (→ 0.0), maximize positive_benefit_score (→ 1.0)

### Step 1: Query for High Taxonomic Diversity + Low Overlap

```sql
-- Find plants with diverse families, low pathogen overlap, high beneficial fungi
WITH diverse_candidates AS (
    SELECT
        plant_wfo_id,
        wfo_scientific_name,
        family,
        pathogenic_fungi_count,
        saprotrophic_fungi_count,
        endophytic_fungi_count,
        mycorrhizae_total_count,
        biocontrol_total_count
    FROM read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet')
    WHERE pathogenic_fungi_count <= 5  -- Low pathogen load
      AND (saprotrophic_fungi_count >= 3 OR endophytic_fungi_count >= 2 OR mycorrhizae_total_count >= 1)
)
SELECT * FROM diverse_candidates
ORDER BY
    mycorrhizae_total_count + endophytic_fungi_count + saprotrophic_fungi_count DESC,
    pathogenic_fungi_count ASC
LIMIT 20
```

**Selection criteria for GOOD guild:**
1. **Different families** (5 plants from 5 families, or 5 plants from 3+ families)
2. **Low pathogenic fungi count** (<5 fungi each)
3. **Minimal overlap** (≤3 shared pathogens across 2 plants max)
4. **High beneficial fungi** (5+ mycorrhizae, endophytes, or saprotrophs each)
5. **Cross-plant benefits** (visitors/predators overlap)
6. **Complementary niches** (some attract pollinators, others host biocontrol fungi)

### Step 2: Check for Cross-Plant Benefits

```sql
-- Find plant pairs with HIGH beneficial predator counts
WITH top_beneficiaries AS (
    SELECT
        plant_a,
        plant_b,
        beneficial_predator_count
    FROM read_parquet('data/stage4/cross_plant_benefits.parquet')
    WHERE beneficial_predator_count >= 5
    ORDER BY beneficial_predator_count DESC
    LIMIT 50
)
-- Build connected components: find sets of plants with mutual benefits
SELECT plant_a FROM top_beneficiaries
UNION
SELECT plant_b FROM top_beneficiaries
```

**Target**: 3-5 cross-plant beneficial relationships (avg 5+ predators each)

### Step 3: Check for Shared Beneficial Fungi

```sql
-- Find plants with overlapping beneficial fungi
WITH candidate_plants AS (
    SELECT UNNEST([...]) as plant_wfo_id
),
beneficial_overlap AS (
    SELECT
        UNNEST(amf_fungi || emf_fungi || endophytic_fungi || saprotrophic_fungi) as fungus,
        COUNT(DISTINCT plant_wfo_id) as plant_count
    FROM read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet')
    WHERE plant_wfo_id IN (SELECT * FROM candidate_plants)
    GROUP BY fungus
    HAVING plant_count >= 2
)
SELECT COUNT(*) as shared_beneficial_fungi FROM beneficial_overlap
```

**Target**: 5+ shared beneficial fungi across 3-5 plants

### Step 4: Verify Low Herbivore/Pathogen Overlap

```sql
-- Check that shared vulnerabilities are minimal
-- (Same queries as BAD guild validation, but expecting near-zero results)
```

**Target**: 0-2 shared herbivores, 0-3 shared pathogens

---

## Existing Test Guilds Validation Plan

### BAD Guild (5 Acacias) - From README

**Plants**: Acacia koa, A. auriculiformis, A. melanoxylon, A. mangium, A. harpophylla

**Validation queries:**
```sql
-- Count pathogenic fungi overlap
-- Count herbivore overlap
-- Check taxonomic diversity (should be 0.2 - all same genus)
-- Check for any cross-benefits (should be ~0)
```

**Expected score**: -0.75 to -0.85

### GOOD Guild (Diverse) - From README

**Plants**: Abrus precatorius (Fabaceae), Abies concolor (Pinaceae), Acacia koa (Fabaceae), Abutilon grandifolium (Malvaceae), Abelmoschus moschatus (Malvaceae)

**Validation queries:**
```sql
-- Count pathogenic fungi overlap (should be ≤5)
-- Count shared beneficial fungi (should be 10+)
-- Count cross-benefits (should be 2+)
-- Check taxonomic diversity (should be 0.6+ - 3 families)
```

**Expected score**: +0.45 to +0.60

---

## Alternative Candidate Guilds

### Alternative BAD Guild: All Solanaceae (Nightshades)

**Strategy**: Select 5 Solanaceae with overlapping pests/diseases
- Many shared pathogens (late blight, early blight, mosaic viruses)
- Shared herbivores (tomato hornworm, aphids, whiteflies)
- Same family (diversity = 0.2)

**Candidate plants:**
- Solanum lycopersicum (tomato)
- Solanum tuberosum (potato)
- Solanum melongena (eggplant)
- Capsicum annuum (pepper)
- Nicotiana tabacum (tobacco)

**Expected score**: -0.80 to -0.90 (worse than Acacia due to intensive agriculture → more recorded pests)

### Alternative GOOD Guild: Three Sisters + Beneficial Companions

**Strategy**: Select plants with known companion planting benefits
- High taxonomic diversity
- Complementary niches (nitrogen fixation, pest repellent, structural support)
- Cross-plant benefits (predators, mycorrhizae)

**Candidate plants:**
- Zea mays (corn) - tall structure
- Phaseolus vulgaris (beans) - nitrogen fixation
- Cucurbita pepo (squash) - ground cover
- Tagetes erecta (marigold) - pest repellent, attracts beneficial insects
- Allium cepa (onion) - pest repellent

**Expected score**: +0.60 to +0.80 (high due to known synergies)

---

## Implementation Steps

1. **Run validation queries** on existing test guilds to confirm expectations
2. **Query for alternative candidates** using strategies above
3. **Build candidate shortlist** (10 bad candidates, 10 good candidates)
4. **Preview scores** using simple overlap counts before full implementation
5. **Select final 5+5 guilds** based on:
   - Clear separation in expected scores (bad ≤ -0.6, good ≥ +0.4)
   - Representative of different ecological scenarios
   - Data completeness (all components have data)

---

## Data Completeness Check

Before finalizing guilds, verify data availability:

```sql
-- Check data completeness for candidate plants
SELECT
    p.plant_wfo_id,
    p.wfo_scientific_name,
    -- Fungal data
    f.pathogenic_fungi_count,
    f.mycorrhizae_total_count,
    f.biocontrol_total_count,
    f.endophytic_fungi_count,
    f.saprotrophic_fungi_count,
    -- Organism data
    o.herbivore_count,
    o.pathogen_count,
    o.pollinator_count,
    o.visitor_count,
    -- Cross-benefits
    (SELECT COUNT(*) FROM read_parquet('data/stage4/cross_plant_benefits.parquet') cb
     WHERE cb.plant_a = p.plant_wfo_id) as benefits_as_donor
FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet') p
LEFT JOIN read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet') f USING (plant_wfo_id)
LEFT JOIN read_parquet('data/stage4/plant_organism_profiles.parquet') o ON p.wfo_taxon_id = o.plant_wfo_id
WHERE p.wfo_taxon_id IN (SELECT UNNEST([...candidate IDs...]))
```

**Requirement**: All components should have non-zero data for meaningful scoring

---

## Next Actions

1. Run validation queries on existing README test guilds
2. Generate alternative candidates using query strategies
3. Create shortlist of 10 BAD + 10 GOOD candidates
4. Preview expected scores
5. Finalize 5 BAD + 5 GOOD guilds for testing
6. Document selected guilds with expected score ranges

**Output format for each guild:**
```
Guild Name: [Descriptive Name]
Plants: [5 WFO IDs + scientific names + families]
Expected Score: [Range]
Rationale:
  - N1 (Pathogen overlap): [High/Med/Low] - [Details]
  - N2 (Herbivore overlap): [High/Med/Low] - [Details]
  - N3 (Other pathogen overlap): [High/Med/Low] - [Details]
  - P1 (Herbivore control): [High/Med/Low] - [Details]
  - P2 (Pathogen control): [High/Med/Low] - [Details]
  - P3 (Beneficial fungi): [High/Med/Low] - [Details]
  - P4 (Diversity): [High/Med/Low] - [Details]
```
