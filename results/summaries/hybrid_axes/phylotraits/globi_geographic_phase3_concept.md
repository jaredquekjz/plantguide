# GloBI Geographic Data & Phase 3 Concept

## Current Geographic Data Availability

### 1. GloBI Raw Data (Available but Not Extracted)
The GloBI interactions database **DOES** contain geographic coordinates:
- `decimalLatitude` - Latitude of interaction observation
- `decimalLongitude` - Longitude of interaction observation
- `localityId` - Location identifier
- `localityName` - Location name/description

**Current limitation**: Our pipeline (`scripts/globi_join_stage3.py`) doesn't extract these fields - it only extracts:
- Species names
- Interaction types
- Partner kingdoms/families
- References (DOI/URL)

### 2. GBIF Occurrence Data (Already Available)
We have comprehensive plant occurrence data:
- **Location**: `/home/olier/plantsdatabase/data/Stage_4/gbif_occurrences_complete/`
- **Format**: CSV.gz files with full GBIF occurrence records
- **Fields**: decimalLatitude, decimalLongitude, country, year, elevation, etc.
- **Coverage**: All 654 species have GBIF occurrence files

### 3. Current Encyclopedia Profiles
Limited geographic data:
- Only 3 sample coordinates per species (for map display)
- Example: Quercus robur has 3 coordinates from Netherlands

## Phase 3 Geographic Interaction Patterns - The Vision

### What It Would Show

#### 1. **Interaction Geography Maps**
Overlay interaction data on occurrence maps showing:
- Where specific pollinators visit the plant
- Regional herbivory patterns
- Disease/pathogen hotspots
- Interaction diversity by region

Example visualization:
```
[World Map of Quercus robur]
🟢 Pollination hotspots (UK has different pollinators than Spain)
🟡 Heavy herbivory zones (Central Europe gall wasps)
🔴 Disease pressure areas (Powdery mildew in humid regions)
```

#### 2. **Regional Partner Differences**
Show how interaction partners vary geographically:

**Northern Range** (Scandinavia):
- Pollinators: Cold-adapted bees
- Herbivores: Winter moth
- Pathogens: Frost-related fungi

**Southern Range** (Mediterranean):
- Pollinators: Different bee species
- Herbivores: Cork oak moth
- Pathogens: Drought-stress pathogens

#### 3. **Climate-Linked Patterns**
Correlate interactions with climate zones:
- Tropical interactions vs temperate
- Elevation gradients affecting partners
- Seasonal variation by latitude

### Implementation Approach

#### Step 1: Enhance GloBI Extraction
Modify `globi_join_stage3.py` to extract:
```python
"decimalLatitude",
"decimalLongitude",
"localityName",
"eventDate"  # For temporal patterns
```

#### Step 2: Build Geographic Index
Create interaction-location database:
```python
{
  "Quercus robur": {
    "pollination": [
      {"partner": "Apis mellifera", "lat": 51.5, "lon": -0.1, "country": "UK"},
      {"partner": "Bombus terrestris", "lat": 48.8, "lon": 2.3, "country": "FR"}
    ],
    "herbivory": [...]
  }
}
```

#### Step 3: Visualization Components

**A. Interactive Map Layer**
```typescript
<GBIFOccurrenceMap>
  <InteractionOverlay
    type="pollination"
    showDensity={true}
    clusterByPartner={true}
  />
</GBIFOccurrenceMap>
```

**B. Regional Comparison Cards**
```typescript
<RegionalInteractions>
  <RegionCard region="Northern Europe">
    - 15 pollinator species
    - Peak: June-July
    - Key partner: Bombus spp.
  </RegionCard>
  <RegionCard region="Southern Europe">
    - 22 pollinator species
    - Peak: April-May
    - Key partner: Apis mellifera
  </RegionCard>
</RegionalInteractions>
```

**C. Climate Correlation Charts**
```typescript
<ClimateInteractionPlot
  xAxis="Mean Annual Temperature"
  yAxis="Pollinator Diversity"
  showTrendLine={true}
/>
```

### Data Enrichment Strategy

1. **Cross-reference GBIF × GloBI**
   - Match plant occurrences with nearby interactions
   - Build regional interaction profiles

2. **Climate Layer Integration**
   - Use Köppen climate zones
   - Correlate with WorldClim data
   - Show interaction shifts with climate change

3. **Temporal Patterns**
   - Extract eventDate from both datasets
   - Show seasonal interaction calendars
   - Historical changes over decades

### User Benefits

#### For Gardeners:
- "Which pollinators will visit in my region?"
- "What pests should I watch for in my climate?"
- "Will this plant attract local wildlife?"

#### For Ecologists:
- Biogeographic interaction patterns
- Climate change impact on mutualisms
- Regional conservation priorities

#### For Plant Breeders:
- Regional disease pressure maps
- Pollinator availability by location
- Adaptation requirements

### Technical Challenges

1. **Data Sparsity**: GloBI may not have coordinates for all interactions
2. **Scale Mismatch**: Plant occurrences (thousands) vs interactions (hundreds)
3. **Computational Load**: Processing geographic joins for 654 species
4. **Visualization Complexity**: Showing multiple data layers clearly

### Phase 3 Deliverables

1. **Enhanced Data Pipeline**
   - GloBI geographic extraction
   - GBIF-GloBI cross-referencing
   - Regional summary statistics

2. **Map Visualizations**
   - Heatmaps of interaction intensity
   - Partner species range overlaps
   - Migration/expansion patterns

3. **Analytics Dashboard**
   - Regional diversity metrics
   - Climate correlation charts
   - Temporal trend analysis

4. **Predictive Features**
   - "Expected interactions at location X"
   - Climate change projections
   - Invasion risk assessments

## Why This Matters

Geographic interaction patterns reveal:
- **Hidden Biodiversity**: Same plant, different ecological roles
- **Climate Adaptation**: How interactions shift with environment
- **Conservation Priorities**: Where key mutualisms are threatened
- **Garden Planning**: What actually happens in your specific location

The combination of GBIF occurrence data + GloBI interaction data + climate layers would create an unprecedented view of plant ecology across geographic space.