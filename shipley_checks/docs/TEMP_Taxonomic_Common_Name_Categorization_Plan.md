# Taxonomic Common Name and Functional Categorization Plan

## Objective

Systematically assign common names and functional ecological categories to:
- **11,711 plant species** (WFO normalized scientific names)
- **5,910 unique herbivores**
- **7,403 unique pollinators**
- **19,621 unique predators**

This enables rigorous, scientifically-grounded functional categorization across the entire dataset.

## Current State

### Data Sources Available
1. **GBIF Plantae Occurrence** (`data/gbif/occurrence_plantae.parquet`)
   - 226 columns including: `vernacularName`, `kingdom`, `order`, `family`, `genus`
   - Contains common names for plant taxa

2. **Final Dataset** (`shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.csv`)
   - 11,711 plants with WFO normalized scientific names
   - 799 columns (traits + EIVE + ecosystem services)

3. **Organism Profiles** (`shipley_checks/validation/organism_profiles_pure_r.parquet`)
   - Pipe-separated lists of herbivores, pollinators, predators per plant
   - Source of all organism names

4. **taxizedb R Package** (cloned to `/tmp/taxizedb`)
   - Downloads full taxonomic databases locally (NCBI, ITIS, GBIF)
   - Offline SQL queries - fast, no rate limits
   - NCBI: `names.dmp` includes common names (`name_class` field)
   - ITIS: `VernacularName.tsv` table with common names
   - Full taxonomic hierarchy (kingdom → genus)

### Current Categorization Status
- **Herbivores**: 70.6% categorized as "Other Herbivores"
- **Pollinators**: 63.3% categorized as "Other Pollinators"
- **Predators**: 73.1% categorized as "Other Predators"

**Target**: < 5% "Other" for each role

## Proposed Solution: Three-Phase Approach

### Phase 1: Taxonomic Enrichment (Build Lookup Tables)

**1.1 Download Local Taxonomy Databases (One-time)**
```r
library(taxizedb)

# Download NCBI taxonomy (~500MB, includes common names)
db_download_ncbi()

# Download ITIS taxonomy (~350MB, includes vernacular names)
db_download_itis()

# These are stored locally as SQLite databases
# Future queries are instant and offline
```

**1.2 Extract All Unique Organisms**
- Parse organism profiles to get unique names for each role
- Extract genus from scientific name (first word)
- Total: ~10,540 unique genera across all organisms

**1.3 Query Local Taxonomy Databases**
```r
library(taxizedb)
library(duckdb)

# Connect to local taxonomy databases
src_ncbi <- src_ncbi()
src_itis <- src_itis()

# For each organism scientific name:
# 1. Get taxonomic classification (family, order, class)
classification_result <- classification(organism_name, db = "ncbi")

# 2. Get common/vernacular names from NCBI names.dmp
# name_class field includes: "scientific name", "common name", "synonym", etc.
ncbi_names <- dbGetQuery(src_ncbi$con,
  "SELECT name_txt, name_class FROM names WHERE tax_id = ?",
  params = list(tax_id))

# 3. Get vernacular names from ITIS
itis_vernacular <- dbGetQuery(src_itis$con,
  "SELECT vernacularName FROM vernacular WHERE taxonID = ?",
  params = list(taxon_id))

# Build enriched lookup table:
# organism_name → genus, family, order, common_names (NCBI), vernacular_names (ITIS)
```

**1.4 Query Plant Common Names**
```r
# For 11,711 WFO plant names:
# 1. Query local GBIF parquet vernacularName (fast, already have file)
# 2. Query taxizedb NCBI/ITIS for plants without GBIF match
# 3. Fallback: use genus common name or family name
```

**Output**:
- `data/taxonomy/organism_taxonomy_enriched.parquet`
  - Columns: organism_name, genus, family, order, class, ncbi_common_names, itis_vernacular_names
- `data/taxonomy/plant_common_names.parquet`
  - Columns: wfo_scientific_name, common_name, vernacular_name, source

### Phase 2: Family → Functional Category Mapping

**2.1 Create Taxonomic Family Mappings**

Based on ecological function, map families to categories:

**Insects:**
```
Culicidae → Flies
Pompilidae → Wasps
Apidae → Honey Bees
Andrenidae → Solitary Bees
Syrphidae → Hoverflies
Formicidae → Ants
Noctuidae → Moths
Pieridae → Butterflies
Aphididae → Aphids
Diaspididae → Scale Insects
Eriophyidae → Mites
Buprestidae → Beetles
Curculionidae → Weevils
Chrysomelidae → Leaf Beetles
... (comprehensive family list)
```

**Approach:**
1. Extract all unique families from Phase 1 enrichment
2. Manually research and assign functional category to each family
3. Use vernacular names to aid categorization (e.g., "jewel beetle" → Beetles)
4. Store in: `data/taxonomy/family_to_functional_category.csv`

**2.2 Handle Multi-Role Families**
Some families appear in multiple roles:
- Syrphidae: Hoverflies (larvae = predators, adults = pollinators)
- Lepidoptera: Moths/Butterflies (larvae = herbivores, adults = pollinators)

Solution: Role-contextual categorization (already in unified_taxonomy.R)

**Output**:
- `data/taxonomy/family_to_functional_category.csv`

### Phase 3: NLP-Based Clustering for Edge Cases

For organisms that don't match family mappings (< 5%), use NLP:

**3.1 Feature Extraction**
```python
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.cluster import KMeans

# Extract features from vernacular names
features = TfidfVectorizer(max_features=100)
X = features.fit_transform(vernacular_names)

# Cluster similar organisms
clusters = KMeans(n_clusters=50).fit_predict(X)
```

**3.2 Manual Review & Labeling**
- Review cluster centroids
- Assign functional category to each cluster
- Validate with domain knowledge

**Output**:
- `data/taxonomy/nlp_organism_categories.csv`

### Phase 4: Integration & Validation

**4.1 Update unified_taxonomy.R**

Replace pattern-based matching with taxonomy-based lookup:
```r
categorize_organism <- function(name, role = NULL) {
  # 1. Extract genus
  genus <- strsplit(name, " ")[[1]][1]

  # 2. Lookup family from enriched taxonomy
  family <- taxonomy_lookup[[genus]]$family

  # 3. Lookup functional category from family mapping
  category <- family_to_category[[family]]

  # 4. Fallback to NLP clusters if needed
  if (is.na(category)) {
    category <- nlp_cluster_category[[name]]
  }

  # 5. Role-specific fallback
  if (is.na(category)) {
    return(paste0("Other ", tools::toTitleCase(role), "s"))
  }

  return(category)
}
```

**4.2 Validate Coverage**
```r
# Re-run coverage analysis
# Target: < 5% "Other" for each role
# If not met, iterate on family mappings
```

**4.3 Add Common Names to Dataset**
```r
# Add plant common names to final dataset
bill_with_common_names <- bill %>%
  left_join(plant_common_names, by = "wfo_scientific_name")

# Save: shipley_checks/stage3/bill_with_common_names_11711.csv
```

## Implementation Steps

### Step 1: Download Taxonomy Databases (One-time, 30 min)
```r
library(taxizedb)

# One-time download (~850MB total)
db_download_ncbi()  # ~500MB, 10-15 min
db_download_itis()  # ~350MB, 10-15 min

# Databases stored in taxizedb cache directory
# All future queries are instant and offline
```

### Step 2: Build Taxonomy Enrichment (2-3 hours)
```r
# Extract all unique organisms (10,540 genera)
# Query local NCBI/ITIS databases via SQL
# No rate limits - process all organisms in minutes
# Build: organism_name → genus, family, order, common_names
# Save: data/taxonomy/organism_taxonomy_enriched.parquet
```

### Step 3: Family Mapping (2-3 hours)
```r
# Manual research of ~200-300 unique families
# Use common names from Step 2 to aid categorization
# Create family_to_functional_category.csv
```

### Step 4: NLP Clustering (1-2 hours)
```python
# Cluster remaining uncategorized organisms
# Use vernacular names from taxizedb
# Review and label clusters
```

### Step 5: Integration & Testing (1 hour)
```r
# Update unified_taxonomy.R
# Validate < 5% Other for all roles
# Regenerate reports
```

**Total Estimated Time**: 6.5-9.5 hours (faster than API approach!)

## Benefits of This Approach

1. **Scientifically Rigorous**: Based on taxonomic classification from authoritative databases (NCBI, ITIS)
2. **Fast & Offline**: Local databases enable instant queries with no rate limits or API dependencies
3. **Reusable**: Works for any new organisms added to dataset
4. **Transparent**: Clear mapping from taxonomy → functional category
5. **Comprehensive**: Covers all 11,711 plants + all organisms (~30,000 unique organisms)
6. **Maintainable**: Easy to update family mappings as needed
7. **NLP Validation**: Machine learning validates manual categorizations
8. **Reproducible**: Offline databases ensure consistent results across runs

## Deliverables

1. **Data Artifacts**:
   - `data/taxonomy/organism_taxonomy_enriched.parquet`
   - `data/taxonomy/plant_common_names.parquet`
   - `data/taxonomy/family_to_functional_category.csv`
   - `data/taxonomy/nlp_organism_categories.csv`

2. **Code**:
   - `src/Stage_1/taxonomy/build_taxonomy_enrichment.R`
   - `src/Stage_1/taxonomy/build_family_mappings.R`
   - `src/Stage_1/taxonomy/nlp_cluster_organisms.py`
   - Updated `shipley_checks/src/Stage_4/explanation/unified_taxonomy.R`

3. **Documentation**:
   - This plan document
   - Family mapping methodology notes
   - Validation reports showing < 5% Other coverage

## Next Steps

1. Review and approve this plan
2. Install taxizedb: `install.packages("taxizedb")`
3. Download taxonomy databases (one-time, ~30 min, ~850MB)
4. Begin Phase 1: Build taxonomy enrichment from local databases
5. Create family → functional category mappings
6. Iterate until < 5% Other for all roles

## Rejected Approach: TaxoNERD

**TaxoNERD** (Deep neural models for taxonomic entity recognition) was considered but rejected because:

**What TaxoNERD does:**
- Named Entity Recognition (NER) - extracts/recognizes taxon names FROM unstructured text
- Example: Given "The monarch butterfly (Danaus plexippus) migrates...", it identifies taxon mentions
- Use case: Information extraction from scientific papers, literature mining

**What we need:**
- Scientific name → common name lookup
- Scientific name → functional category assignment
- Direct taxonomy queries, not text extraction

**Conclusion:** TaxoNERD solves a different problem (information extraction from text) rather than taxonomy lookup. Not applicable to our use case.

## Comparison: taxizedb vs taxize API

| Aspect | taxizedb (LOCAL) | taxize (API) |
|--------|------------------|--------------|
| Speed | Instant SQL queries | 3-10 req/sec (rate limited) |
| Time for 30K organisms | Minutes | 2-3 hours minimum |
| Internet required | No (after download) | Yes (every query) |
| Reproducibility | Perfect (same DB version) | Variable (APIs change) |
| Cost | Free | Free (but limited) |
| Initial setup | 30 min download | None |
| Coverage | NCBI + ITIS + GBIF | Same sources |

**Recommendation: Use taxizedb** - faster, offline, more reproducible
