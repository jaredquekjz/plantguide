# Essential Papers for Multi-Organ Ellenberg Prediction Project
## Organized by Priority and Topic

### 🔴 CRITICAL - Must Have (Shipley's Core Work)

#### 1. **Shipley et al. (2017) - The Foundation**
- **Title**: "Predicting habitat affinities of plant species using commonly measured functional traits"
- **Journal**: Journal of Vegetation Science
- **Why**: Your baseline model - the paper you're extending
- **Key content**: Cumulative link models, 4 traits → Ellenberg scores
- **File**: `Papers/Shipley_et_al-2017-Journal_of_Vegetation_Science.txt` ✓ (Already have!)

#### 2. **Shipley (2016) - The Theory Book**
- **Title**: "Cause and Correlation in Biology: A User's Guide to Path Analysis, Structural Equations and Causal Inference with R" (2nd Edition)
- **Publisher**: Cambridge University Press
- **Why**: His causal inference framework, d-separation tests
- **Key content**: Chapters on DAGs, d-sep tests, path analysis
- **Download**: University library or purchase

#### 3. **Shipley & Douma (2023) - Hierarchical Methods**
- **Title**: "Testing Model Fit in Path Models with Dependent Errors Given Non-Normality, Non-Linearity and Hierarchical Data"
- **Journal**: Structural Equation Modeling: A Multidisciplinary Journal
- **DOI**: 10.1080/10705511.2022.2112199
- **Why**: Methods for handling your complex multi-organ data
- **Key content**: Copulas, hierarchical structures, non-normal distributions

#### 4. **Douma & Shipley (2021) - Multi-group Extension**
- **Title**: "A multigroup extension to piecewise path analysis"
- **Journal**: Ecosphere 12(5):e03502
- **DOI**: 10.1002/ecs2.3502
- **Why**: Methods for thin vs thick root strategies
- **Key content**: Multi-group SEM, piecewise analysis

#### 5. **Shipley & Douma (2020) - Statistical Framework**
- **Title**: "Generalized AIC and chi-squared statistics for path models consistent with directed acyclic graphs"
- **Journal**: Ecology 101(3):e02960
- **DOI**: 10.1890/19-1066.1
- **Why**: Statistical tests for your causal models

### 🟡 IMPORTANT - Multi-Organ Economics Papers

#### 6. **Guerrero-Ramirez et al. (2021) - GROOT Database**
- **Title**: "Global Root Traits (GRooT) Database"
- **Journal**: Global Ecology and Biogeography 30(1):25-37
- **DOI**: 10.1111/geb.13179
- **Why**: Shipley is co-author! Root trait standardization
- **Key content**: Root economics spectrum, trait definitions

#### 7. **Chave et al. (2009) - Wood Economics Spectrum**
- **Title**: "Towards a worldwide wood economics spectrum"
- **Journal**: Ecology Letters 12(4):351-366
- **DOI**: 10.1111/j.1461-0248.2009.01285.x
- **Why**: Foundation of wood density as master trait
- **Key content**: Wood density-survival relationships

#### 8. **Bergmann et al. (2020) - Root Economics Update**
- **Title**: "The fungal collaboration gradient dominates the root economics space in plants"
- **Journal**: Science Advances 6(27):eaba3756
- **DOI**: 10.1126/sciadv.aba3756
- **Why**: Explains the root diameter dilemma!
- **Key content**: Do-it-yourself vs outsourcing strategies

#### 9. **Reich (2014) - Whole-Plant Economics**
- **Title**: "The world-wide 'fast-slow' plant economics spectrum: a traits manifesto"
- **Journal**: Journal of Ecology 102(2):275-301
- **DOI**: 10.1111/1365-2745.12211
- **Why**: Integration across organs concept

### 🟢 SUPPORTING - Methods & Applications

#### 10. **Lefcheck (2016) - piecewiseSEM**
- **Title**: "piecewiseSEM: Piecewise structural equation modelling in R for ecology, evolution, and systematics"
- **Journal**: Methods in Ecology and Evolution 7(5):573-579
- **DOI**: 10.1111/2041-210X.12512
- **Why**: R package you'll use for analysis

#### 11. **Díaz et al. (2016) - Global Spectrum**
- **Title**: "The global spectrum of plant form and function"
- **Journal**: Nature 529:167-171
- **DOI**: 10.1038/nature16489
- **Why**: Shows scale-dependency of trait relationships

#### 12. **Bruelheide et al. (2018) - TRY Database**
- **Title**: "Global trait-environment relationships of plant communities"
- **Journal**: Nature Ecology & Evolution 2:1906-1917
- **DOI**: 10.1038/s41559-018-0699-8
- **Why**: Source of trait data, methods for trait-environment links

### 🔵 OPTIONAL - Deep Dives

#### 13. **Shipley (2013) - AIC for Path Models**
- **Title**: "The AIC model selection method applied to path analytic models compared using a d-separation test"
- **Journal**: Ecology 94(3):560-564
- **Why**: Model selection methods

#### 14. **Shipley (2009) - Confirmatory Path Analysis**
- **Title**: "Confirmatory path analysis in a generalized multilevel context"
- **Journal**: Ecology 90(2):363-368
- **Why**: Multilevel modeling framework

#### 15. **Shipley et al. (2006) - Trait Integration**
- **Title**: "From plant traits to plant communities: a statistical mechanistic approach to biodiversity"
- **Journal**: Science 314(5800):812-814
- **Why**: Shows his broader vision

## 📂 Recommended Folder Structure

```
ellenberg/
├── Papers/
│   ├── Core_Shipley/
│   │   ├── Shipley_2017_habitat_prediction.pdf  ✓
│   │   ├── Shipley_Douma_2023_hierarchical.pdf
│   │   ├── Douma_Shipley_2021_multigroup.pdf
│   │   └── Shipley_Douma_2020_generalized_AIC.pdf
│   ├── Multi_Organ_Economics/
│   │   ├── GROOT_2021_database.pdf
│   │   ├── Chave_2009_wood_economics.pdf
│   │   ├── Bergmann_2020_root_strategies.pdf
│   │   └── Reich_2014_whole_plant.pdf
│   ├── Methods/
│   │   ├── Lefcheck_2016_piecewiseSEM.pdf
│   │   └── Shipley_2016_book_chapters.pdf
│   └── Supporting/
│       ├── Diaz_2016_global_spectrum.pdf
│       └── Bruelheide_2018_TRY.pdf
```

## 🎯 Download Priority Order

1. **First Wave** (Before Shipley meeting):
   - Shipley & Douma 2023 (hierarchical methods)
   - GROOT 2021 (he's co-author!)
   - Bergmann 2020 (root strategies)
   - Chave 2009 (wood economics)

2. **Second Wave** (For implementation):
   - Lefcheck 2016 (piecewiseSEM guide)
   - Douma & Shipley 2021 (multi-group)
   - Reich 2014 (whole-plant concept)

3. **Third Wave** (For publication):
   - All supporting papers for citations
   - Methods papers for technical details

## 🔍 Where to Find These Papers

### Open Access:
- GROOT database: https://groot-database.github.io/GRooT/
- Science Advances (Bergmann): Open access journal
- Ecosphere (Douma & Shipley 2021): Open access

### Institutional Access Needed:
- Journal of Vegetation Science (Shipley 2017) ✓
- Structural Equation Modeling journal (2023)
- Ecology Letters (Chave 2009)
- Nature journals

### Preprints/Alternatives:
- Check ResearchGate for author uploads
- bioRxiv/EcoEvoRxiv for preprints
- Email authors directly (they usually share!)

## 💡 Pro Tips for Paper Management

1. **Name files consistently**: 
   `FirstAuthor_Year_KeyTopic.pdf`

2. **Keep a bibtex file**:
   `references.bib` for easy citation

3. **Make notes files**:
   For each paper: `PaperName_NOTES.md` with:
   - Key findings relevant to your project
   - Methods you'll use
   - Figures/tables to reference
   - Quotes for the Shipley pitch

4. **Track what Shipley would care about**:
   - His methods being used correctly
   - Proper attribution
   - Causal interpretation (not just correlation)
   - Scale-dependency acknowledged

## 📝 Reading Strategy

**Week 1 - Understand the Evolution**:
1. Re-read Shipley 2017 thoroughly
2. Read Shipley-Douma 2023 (hierarchical)
3. Skim GROOT paper (focus on Shipley's contribution)

**Week 2 - Master the Methods**:
1. Deep dive piecewiseSEM documentation
2. Understand multi-group extension (Douma 2021)
3. Study wood & root economics papers

**Week 3 - Integration**:
1. Connect all concepts
2. Draft how each paper supports your approach
3. Prepare citations for Shipley discussion

## 🎯 The Most Important Insight

The papers show a clear evolution:
- **2017**: Traits → Habitat (correlation)
- **2020-2021**: Multi-group & hierarchical methods
- **2021**: GROOT database (multi-organ data)
- **2023**: Non-normal, hierarchical complexity
- **2024**: YOUR WORK - Completing the vision!

Each paper builds toward the COMPLETE multi-organ causal framework. You're not contradicting Shipley - you're completing his trajectory!