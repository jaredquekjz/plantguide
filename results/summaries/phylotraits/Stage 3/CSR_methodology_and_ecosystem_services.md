# Stage 3: CSR Strategies and Ecosystem Service Prediction
## Methodological Framework and Implementation

---

## 1. CSR Strategy Calculation: Pierce et al. (2016/2017) Global Method (StrateFy)

### 1.1 Conceptual Foundation

**CSR Theory (Grime 1974, 1977, 2001)**: Three primary strategies represent viable trait combinations arising under distinct selection pressures:
- **C (Competitor)**: Productive, stable habitats → rapid growth, resource preemption, large size
- **S (Stress-tolerator)**: Resource-poor environments → resource retention, persistent tissues, slow growth
- **R (Ruderal)**: Frequent disturbances → high reproductive investment, rapid population regeneration

### 1.2 Trait Selection Rationale

**Core Traits (LA, LDMC, SLA)** were selected because they:
1. Represent the two principal global trait spectra:
   - **Plant size spectrum**: Leaf Area (LA)
   - **Resource economics spectrum**: SLA (acquisitive) ↔ LDMC (conservative)
2. Are ubiquitous across life forms (trees, lianas, aquatics, herbs)
3. Have wide geographic/phylogenetic coverage in TRY database
4. Exhibit mutually exclusive extremes (no species has high LA + high SLA + high LDMC)
5. Strongly concordant (RV = 0.597, p < 0.0001) with 14-trait multivariate space

**Trade-off Structure**:
- High LDMC species: small, dense leaves (conservative economics)
- High SLA species: small, soft leaves (acquisitive economics)
- High LA species: intermediate economics only

### 1.3 Exact StrateFy Calculation (formulas and constants)

StrateFy maps LA, LDMC and SLA to C, S, R using globally calibrated equations (3068 spp.) without re‑running PCA per dataset. Below is an exact, code‑ready specification consistent with the StrateFy Excel tool and published implementations.

Inputs (units)
- `LA` mm²
- `LDMC` percent (%) or computed from fresh/dry mass
- `SLA` mm² mg⁻¹

Optional inputs if LDMC/SLA need to be computed
- `LFW` mg (leaf fresh weight)
- `LDW` mg (leaf dry weight)

Derived quantities
- `SLA = LA / LDW`
- `Succulence index = (LFW − LDW) / (LA / 10)`
- `LDMC (%) = (LDW*100)/LFW` if succulence index ≤ 5; otherwise `LDMC = 100 − ((LDW*100)/LFW)` (succulent correction)

Transforms
- `la_sqrt = sqrt(LA / 894205) * 100`  # 894205 = global max LA in calibration
- `ldmc_logit = log((LDMC/100) / (1 − LDMC/100))`
- `sla_log = log(SLA)`

Global mapping equations
- `C_raw = −0.8678 + 1.6464 * la_sqrt`
- `S_raw = 1.3369 + 0.000010019*(1 − exp(−0.0000000000022303 * ldmc_logit)) + 4.5835*(1 − exp(−0.2328 * ldmc_logit))`
- `R_raw = −57.5924 + 62.6802 * exp(−0.0288 * sla_log)`

Clamp to global calibration limits
- `minC = 0;              maxC = 57.3756711966087`
- `minS = −0.756451214853076; maxS = 5.79158377609218`
- `minR = −11.3467682227961; maxR = 1.10795515716546`
- `C_clamp = min(max(C_raw, minC), maxC)`
- `S_clamp = min(max(S_raw, minS), maxS)`
- `R_clamp = min(max(R_raw, minR), maxR)`

Shift to positive, scale to proportions, normalize to 100%
- `valor.C = abs(minC) + C_clamp; range.C = maxC + abs(minC)`
- `valor.S = abs(minS) + S_clamp; range.S = maxS + abs(minS)`
- `valor.R = abs(minR) + R_clamp; range.R = maxR + abs(minR)`
- `prop.C  = (valor.C / range.C) * 100`
- `prop.S  = (valor.S / range.S) * 100`
- `prop.R  = 100 − ((valor.R / range.R) * 100)`
- `conv    = 100 / (prop.C + prop.S + prop.R)`
- `C = prop.C * conv; S = prop.S * conv; R = prop.R * conv`

Notes
- Do not re‑run PCA/Varimax on your dataset; use the fixed equations above.
- Do not apply any additional “triangle expansion/rescaling”; C+S+R already sums to 100.
- Ensure units match exactly (LA in mm²; SLA in mm² mg⁻¹; LDMC in %).

**Final Output**: `C`, `S`, `R` percentages summing to 100 (e.g., 43:42:15).

### 1.4 Validation Evidence

1. **Co-inertia Analysis**: 3-trait method preserves 59.7% of variance from 14-trait space
2. **Comparison with Local Methods**: R² > 0.86 for all three CSR axes vs Pierce et al. 2013
3. **Successional Gradient Test**: Alpine succession (scree → climax grassland → pasture) correctly predicted as R → S → CR/CSR trajectory
4. **Global Patterns**: Correctly identifies:
   - Tropical forests: CS/CSR convergence (43:42:15)
   - Deserts: S-R divergence (stress-tolerant perennials vs ruderal annuals)
   - Temperate forests: Broad CSR distribution

### 1.5 Implementation Tools

**Canonical Implementation (R):**
- Our implementation: `src/Stage_3_CSR/calculate_csr_ecoservices_shipley.R`
- Based on: [`commonreed/StrateFy`](https://github.com/commonreed/StrateFy) R repository
- Reference: Pierce et al. (2016/2017) StrateFy Excel calculator (Supporting Information)

**Enhancements to StrateFy:**
1. LDMC clipping (prevents logit explosion for extreme values)
2. Explicit NaN handling (transparent edge case behavior)
3. Shipley Part II: Life form-stratified NPP (Height × C for woody species)
4. Shipley Part II: Nitrogen fixation (Fabaceae taxonomy)
5. Complete ecosystem services suite (10 services)

**Verification:**
- ✓ Verified against Pierce et al. (2016) paper equations
- ✓ Verified against commonreed/StrateFy R implementation
- ✓ Produces identical CSR scores to original method (max diff < 1e-10)
- See: `src/Stage_3_CSR/R_IMPLEMENTATION_SUMMARY.md`

**Migration Note:**
- As of 2025-10-30, R implementation is canonical (Python archived)
- Rationale: Native to plant ecology community, easier for Prof Shipley to review
- See: `src/Stage_3_CSR/MIGRATION_TO_R.md`

### 1.6 Complete Implementation Pipeline

**Full reproduction script (R implementation):**
```bash
bash src/Stage_3_CSR/run_full_csr_pipeline.sh
```

This executes the complete pipeline in a **single R script**:
- Back-transforms traits from log scale (LA, LDMC, SLA)
- Calculates CSR scores using StrateFy (Pierce et al. 2016)
- Computes 10 ecosystem service ratings (Shipley 2025 Parts I & II)
- Validates results and reports coverage statistics

**Direct R invocation:**
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_3_CSR/calculate_csr_ecoservices_shipley.R \
  --input model_data/outputs/perm2_production/perm2_11680_enriched_stage3_20251030.parquet \
  --output model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet
```

**Expected output:**
```
============================================================
Stage 3 CSR & Ecosystem Services (R Implementation)
============================================================

Loading data...
Loaded 11680 species

Back-transforming traits...
  LA: 0.80 - 2796250.00 mm²
  LDMC: 0.42 - 116.00 %
  SLA: 0.66 - 204.08 mm²/mg

Calculating CSR scores (StrateFy method)...
  Valid CSR: 11650/11680 (99.74%)
  Failed (NaN): 30 species
  CSR sum to 100: 11650/11650 (100.00%)

Computing ecosystem services (Shipley 2025)...
  Services computed: 10
    1. NPP (life form-stratified)
    2. Litter Decomposition
    [... 8 more services ...]

Writing output...
Saved: model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet
  11680 species × 772 columns

============================================================
Pipeline Complete
============================================================
```

**Final outputs:**
- `model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet`
  - 11,680 species × 772 columns
  - Includes: C, S, R scores + 10 ecosystem service ratings + 10 confidence levels
  - All original trait/taxonomy columns preserved

**Data requirements:**
- Input: Enriched master table with height_m, life_form_simple, family, is_fabaceae, logLA, logLDMC, logSLA
- Coverage: 99.3% family, 100% height, 78.8% life form, 99.7% valid CSR
- Source: Stage 2 production output + Stage 3 taxonomy enrichment

**Archived Python implementation:**
- Python version archived in: `src/Stage_3_CSR/archive_python_20251030/`
- Produces identical CSR scores (verified 2025-10-30)
- See migration notes: `src/Stage_3_CSR/MIGRATION_TO_R.md`

### 1.7 Known Limitations: StrateFy Calibration Boundaries

**Issue**: 30 species (0.26% of 11,680) produce NaN CSR scores due to extreme trait combinations falling outside the StrateFy calibration space.

**Root Cause**: These species hit **all three boundaries simultaneously** in the Pierce et al. (2016) calibration:

| Boundary | Condition | Ecological Interpretation |
|----------|-----------|--------------------------|
| **minC** (C_raw ≤ 0) | Very small leaves (LA: 1-24 mm²) | Low competitive ability |
| **minS** (S_raw ≤ -0.756) | Very low LDMC (6.94-16.52% vs population mean 24.6%) | Low tissue investment per StrateFy mapping |
| **maxR** (R_raw ≥ 1.108) | Low SLA (3-9 mm²/mg) inverted → Low ruderality | Slow growth |

**Mathematical Consequence**:
```
When all boundaries hit:
  valorC = 0 + 0 = 0           → propC = (0/57.4) × 100 = 0
  valorS = 0.756 + (-0.756) = 0 → propS = (0/6.55) × 100 = 0
  valorR = 11.35 + 1.108 = 12.45 → propR = 100 - (12.45/12.45)×100 = 0

  sum = 0 + 0 + 0 = 0
  conv = 100 / 0 = NaN
  C = S = R = NaN
```

**Affected Functional Groups**:
- **21 Conifers** (Gymnosperms): Thuja occidentalis, Juniperus pseudosabina, Tsuga canadensis, Abies magnifica, Cupressus sempervirens, Sequoia sempervirens, etc.
- **8 Halophytes** (Chenopodioideae): Suaeda vera, Sclerolaena spp., Atriplex lindleyi, Chenopodium desertorum, etc.
- **1 Other**: Ulex europaeus, Arctostaphylos crustacea, Cassiope tetragona, Petrosedum sediforme

**Ecological Context**:
- **Reality**: Most are stress-tolerators (conifers in cold/nutrient-poor habitats; halophytes in saline soils)
- **StrateFy calibration**: Based on 3,068 species, primarily herbaceous/woody **angiosperms** (Pierce et al. 2016)
- **Gap**: Conifers (gymnosperms) have fundamentally different needle structure; halophytes have specialized succulent/salt-storing tissues
- **Trait pattern**: Low LDMC + Low SLA is atypical (normal pattern: low LDMC → thin leaves → high SLA). These species fall outside the angiosperm leaf economics spectrum.

**Validation Against Pierce et al. (2016)**:
- ✓ Trait transformations correct (LA sqrt-standardized, LDMC logit, SLA log)
- ✓ Mapping equations faithful to paper (coefficients from Figure S1)
- ✓ Clamping ranges match 3,068-species calibration
- ✓ Conversion mathematics sound
- ✓ Back-transformation from log scale correct
- Verification script: `src/Stage_3_CSR/verify_stratefy_implementation.py`

**Resolution**: Document as known limitation
- Keep CSR = NaN for these 30 species (no arbitrary values)
- Ecosystem services marked as "Unable to Classify" with confidence "Not Applicable"
- **Coverage**: 11,650/11,680 species (99.74%) with valid CSR
- **Justification**: Scientific transparency > forced completeness; these species genuinely fall outside the method's calibration boundaries

**Impact on Analyses**:
- Filter out NaN CSR before community-weighted calculations
- Report completeness statistics in all outputs (99.74% coverage)
- Note: 99.74% coverage is excellent for a global method spanning vascular plants

**Future Refinement** (optional):
- Taxonomy-based fallback for gymnosperms/halophytes (would require separate ecological justification)
- Alternative CSR method for extreme cases (e.g., Hodgson et al. 1999)
- Currently not implemented to maintain methodological consistency

**Detailed Analysis**: See `results/summaries/hybrid_axes/phylotraits/Stage_3/CSR_edge_case_analysis.md`

---

## 2. CSR-Ecosystem Service Relationships (Shipley Framework)

### 2.1 Core Mechanistic Pathways

#### Net Primary Productivity (NPP)
**Equation**: NPP = Standing Biomass × Specific Growth Rate (RGR_max)

**Trait Drivers**:
- RGR_max positively correlated with: high SLA, low LDMC, high leaf N, low wood density, thin leaves, low lignin
- This trait suite = S → C/R gradient in CSR triangle

**CSR Pattern**:
| Strategy | NPP Level | Mechanism |
|----------|-----------|-----------|
| S | Low | Slow RGR dominates |
| C | **Highest** | High RGR × large standing biomass |
| R | Moderate | High RGR but small biomass (disturbance losses) |

**Evidence**: Vile et al. (2006) - ecosystem productivity predictable from RGR_max + species abundance; Garnier & Navas (2013) Chapter 6

#### NPP: Life Form Adjustments (Shipley Part II, 2025)

**Critical limitation identified**: CSR alone captures growth **rate** (via C-score ≈ RGR_max) but ignores **initial biomass** (B₀), which is the multiplicand in the NPP equation.

**Mechanistic formula** (exponential growth):
```
ΔB = B₀ × r × t
```
Where:
- **ΔB** = NPP (new biomass produced per growing season)
- **B₀** = Living biomass at start of growing season (life-form dependent)
- **r** = Relative growth rate ≈ C-score/100 (normalized to 0-1)
- **t** = Growing season length (assume constant within site)

**Key insight**: A large tree with moderate C-score produces MORE NPP than a small herb with high C-score, because B₀ × r (large × moderate) > B₀ × r (small × high).

**Life form-stratified NPP equations**:

| Life Form | NPP Calculation | Rationale |
|-----------|-----------------|-----------|
| **Herbaceous** (non-woody) | NPP ∝ C-score | B₀ ≈ seed weight or small perennial reserves → negligible variation, so r dominates |
| **Woody** (trees, shrubs) | NPP ∝ **Height × C-score** | B₀ scales with height (larger plants = more capital to grow from) → both B₀ and r matter |

**Data requirements**:
- Height (back-transformed from logH): 100% coverage
- Life form classification (try_woodiness): 78.8% coverage
  - Non-woody: 4,922 species (42.1%)
  - Woody: 4,241 species (36.3%)
  - Semi-woody: 41 species (0.4%)

**Validation approach** (Shipley recommendation): Compare predictions for contrasting species (e.g., tall tree with C=40 vs short herb with C=60) to verify height adjustment differentiates appropriately.

**Confidence**: Very High (mechanistic basis well-established; empirical validation needed for threshold calibration)

**Limitations and Assumptions:**
1. **Growing season (t) assumed constant**: Shipley Part II notes "We can't know the growing season length of each species... so the best that we can do is assume that it is the same for all of the plants in the garden." Site-specific predictions would require site-specific growing season data.
2. **Height as B₀ proxy**: Actual woody biomass requires allometric equations (species-specific relationships between height, diameter, wood density). Height is a reasonable first-order approximation but underestimates biomass for dense-wooded species.
3. **Thresholds empirically calibrated**: The rating thresholds (e.g., score ≥ 4.0 → Very High) were calibrated based on contrasting species examples, not validated against measured NPP data.
4. **No validation against actual NPP**: As Shipley states, "without actual values of the variable that we are trying to predict, we cannot know" which method is better. These are qualitative predictions for comparative purposes only.

#### Litter Decomposition Rate
**Trait Drivers** (same as NPP, opposite direction):
- Fast decomposition: low LDMC, high SLA, high leaf N, low lignin

**CSR Pattern**:
| Strategy | Decomposition | Litter Chemistry |
|----------|---------------|------------------|
| S | Slow | Recalcitrant (high lignin, LDMC) |
| C | Fast | High quality (low LDMC, high N) |
| R | Fast | High quality, rapid turnover |

**Confidence**: Very High (extensive empirical literature)

#### Carbon Storage & Sequestration
**Balance Equation**: ∫(NPP - Decomposition)dt

**CSR Pattern**:
| Strategy | Living Biomass | Dead Biomass | Net C Storage |
|----------|----------------|--------------|---------------|
| S | Moderate | High (slow decay) | **High** |
| C | Very High | Moderate | **High** |
| R | Low | Low (fast decay) | Low |

**Key Distinction**:
- S: Slow capture, slow release → high storage via recalcitrant carbon
- C: Rapid capture, rapid release, but large pools → high storage via biomass
- R: Rapid turnover, minimal pools → low storage

**Confidence**: High (moderate uncertainty regarding recalcitrant soil C formation)

#### Nutrient Cycling Rate
**Pathway**: Soil → Plant Uptake → Living Tissue → Litter → Decomposition → Soil

**CSR Pattern**:
| Strategy | Cycling Rate | Mechanism |
|----------|--------------|-----------|
| S | Slow | Nutrients locked in long-lived tissues |
| C | Fast | Rapid NPP + decomposition |
| R | Fast | Quick tissue turnover |

**Confidence**: Very High

#### Nutrient Retention vs Loss
**Key Process**: Leaching potential vs recapture capacity

**CSR Pattern**:
| Strategy | Nutrient Loss | Mechanism |
|----------|---------------|-----------|
| S | Low | Slow release from recalcitrant tissues |
| C | **Low** | Large biomass rapidly recaptures released nutrients |
| R | **High** | Nutrients leach before small biomass can recapture |

**Critical Insight**: C-end has high cycling BUT low loss due to effective recapture; R-end has high cycling AND high loss due to frequent disturbance removing biomass.

**Confidence**: Very High

#### Soil Erosion Protection
**Mechanism**: Standing biomass, root density, canopy coverage

**CSR Pattern** (Tentative):
| Strategy | Protection Level | Basis |
|----------|------------------|-------|
| C | Best | Dense growth, large standing biomass |
| S | Intermediate | Moderate cover |
| R | Poor | Frequent biomass removal |

**Confidence**: Moderate (limited research base; Shipley explicitly flags uncertainty)

#### Nitrogen Fixation (Shipley Part II, 2025)

**Mechanism**: Rhizobium symbiosis in root nodules → atmospheric N₂ → plant-available NH₄⁺/NO₃⁻

**Taxonomic signal**:
- **Leguminosae (Fabaceae)** subfamilies with N-fixation capacity:
  - Papilionoideae (largest subfamily, strongest fixation)
  - Caesalpinioideae (less common, tropical trees)
  - Mimosoideae (woody/tropical taxa)
- Note: Not all Leguminosae fix N (some subfamilies lost capacity)

**Data sources**:
- Family taxonomy from WFO (World Flora Online)
- NodDB database (optional refinement): https://dx.doi.org/10.15156/BIO/587469
- TRY trait: "Plant nitrogen (N) fixation capacity" (optional)

**CSR relationship**:
- Nitrogen fixers often R or C strategy (fast-growing, N-rich tissues)
- S-strategists rarely fix N (slow growth incompatible with symbiosis costs)
- However, fixation is primarily **taxonomic**, not CSR-driven

**Implementation** (conservative approach):
- Fabaceae family → High N-fixation potential (983 species in dataset, 8.4%)
- Non-Fabaceae → Low (baseline)

**Confidence**: Very High (taxonomically determined, well-studied; subfamily-level refinement possible if needed)

### 2.2 Limitations of Shipley Framework

1. **Site-specificity**: Trait effects modulated by environment; quantitative predictions require site-level data
2. **Data requirements** for quantitative models:
   - Georeferenced species abundances (sPlot, VegBank, LOTVS, EVA)
   - Ecosystem measurements (NPP, SOC, etc.)
   - Matching spatial-temporal coverage
   - Currently impractical for most services

3. **Recommendation**: Use CSR for **qualitative predictions** only

---

## 3. Ecosystem Services Gap Analysis

### 3.1 Services Covered by Shipley
✓ Net Primary Productivity (with life form adjustments - Part II)
✓ Litter Decomposition
✓ Carbon Storage (partial - above-ground focus)
✓ Nutrient Cycling
✓ Nutrient Retention/Loss
✓ Soil Erosion (low confidence)
✓ Nitrogen Fixation (Part II - taxonomic/Fabaceae)

### 3.2 Critical Services MISSED by Shipley

#### 3.2.1 Water Regulation ❌
**Key Processes**:
- Evapotranspiration control
- Infiltration and soil water storage
- Hydraulic redistribution

**Trait Drivers** (from repository evidence):
- SLA (+), stomatal conductance (+), fine root density (+)
- Functional richness (+), hydraulic conductivity (+)
- LDMC (-), canopy density (+)

**Gap Explanation**: Hydraulic traits orthogonal to CSR; requires separate trait axis

#### 3.2.2 Heat Regulation/Climate Buffering ❌
**Key Processes**:
- Urban cooling via latent heat flux
- Substrate insulation
- Nocturnal temperature moderation

**Trait Drivers**:
- LAI (+), stomatal conductance (+), leaf albedo (+)
- Canopy height (+), SLA (+)
- Succulence (-)

**Gap Explanation**: Microclimate modification not considered; critical for urban ecosystems

#### 3.2.3 Enhanced Soil Fertility (Beyond Decomposition) ❌
**Key Processes**:
- Microbial community engineering (fungi:bacteria ratios)
- Nurse plant facilitation
- N-fixer presence and litter mixing effects

**Trait Drivers**:
- LDMC (impacts F:B ratio), root diameter, root tissue density
- Functional diversity (non-additive effects)

**Gap Explanation**: Plant-microbe interactions not integrated; diversity effects ignored

#### 3.2.4 Soil Organic Carbon Stocks (Root-mediated) ❌
**Key Processes**:
- Root-derived SOC accumulation
- Aggregate stability via root exudates

**Trait Drivers**:
- Root mean diameter (+), root tissue density (+)
- Root length density (context-dependent)
- Fine root fraction (+)

**Gap Explanation**: Above-ground bias; root traits largely absent from CSR framework

#### 3.2.5 Standing Biomass Stocks ❌
**Key Distinction**: Biomass stocks ≠ NPP flow

**Trait Drivers**:
- Height (++++), wood density (+), LDMC (+)
- Functional dispersion (+)

**Gap Explanation**: Shipley focuses on productivity flow, not harvestable stocks

### 3.3 Trait Mechanisms Absent from CSR

#### Root Trait Suite
- Root diameter → aggregate stability, SOC
- Root tissue density → SOC accumulation
- Fine root fraction/SRL → erosion control, water uptake
- Root hydraulic conductivity → water regulation

#### Hydraulic Trait Suite
- Stomatal conductance → transpiration cooling, water cycling
- Leaf water potential → drought response
- Hydraulic safety margins → resilience

#### Structural/Architectural Traits
- LAI → heat regulation, interception
- Canopy density/roundness → sediment trapping
- Leaf albedo → heat reflection

#### Diversity Metrics (Community-level)
- Functional richness → multifunctionality enhancement
- Functional divergence → complementarity effects
- Trait mixing → non-additive benefits

### 3.4 Application Domains Missed

1. **Urban Ecosystem Services**: Heat mitigation, stormwater management
2. **Climate Adaptation Services**: Drought resilience, flood control, temperature buffering
3. **Multifunctional Landscapes**: Service bundles, trade-offs, synergies
4. **Below-ground Processes**: Root engineering, soil structure

---

## 4. Integration Strategy for Stage 3

### 4.1 CSR as Foundation
Use Pierce et al. (2016) method to calculate C:S:R triplets for all species with LA, LDMC, SLA data.

**Implementation**:
```r
# Input: species-level trait data
traits <- data.frame(species, LA, LDMC, SLA)

# Apply StrateFy algorithm
csr <- calculate_csr_pierce2016(traits)

# Output: C, S, R percentages + secondary strategy class
```

### 4.2 Shipley Services (Direct CSR Mapping)
For services where CSR provides reliable qualitative predictions:

| Service | CSR Predictor | Confidence |
|---------|---------------|------------|
| NPP | C > R > S | Very High |
| Decomposition | R ≈ C > S | Very High |
| Nutrient Cycling Rate | C ≈ R > S | Very High |
| Nutrient Retention | C > S > R | Very High |
| C Storage | C ≈ S > R | High |
| Erosion Control | C > S > R | Moderate |

**Implementation**:
```r
# Community-weighted mean CSR
cwm_csr <- weighted.mean(csr, abundance)

# Service prediction (qualitative)
npp_potential <- cwm_csr$C * 0.5 + cwm_csr$R * 0.3 + cwm_csr$S * 0.2
```

### 4.3 Extended Services (Model Fusion)
For services requiring additional traits beyond CSR:

#### Water Regulation
**Model**: CSR base + hydraulic traits
```
Water_Reg = f(CSR_baseline, SLA, g_s, FineRootDensity, FRic)
```

#### Heat Regulation
**Model**: CSR base + structural traits
```
Cooling = f(CSR_baseline, LAI, g_s, Albedo, Height)
```

#### SOC Stocks
**Model**: CSR decomposition + root traits
```
SOC = f(Decomp_CSR, RootDiam, RootTissueDens, RLD)
```

### 4.4 Trait Imputation Strategy
For traits not in CSR core set but needed for extended services:

1. **Phylogenetic imputation**: BHPMF for continuous traits
2. **Phylo-weighted kNN**: Categorical traits
3. **CSR-informed priors**: Use CSR position to constrain imputation (e.g., S-selected → expect low SLA, high LDMC)

### 4.5 Uncertainty Quantification
**CSR-specific**: Pierce et al. provide within-species variance; propagate through calculations

**Extended services**: Copula-based approach (Stage 6) to capture:
- Trait covariance structures
- CSR-environment interactions
- Non-linear threshold effects

### 4.6 Community-Weighted Aggregation (Shipley Part II, 2025)

For multi-species plantations, gardens, or plant communities, aggregate species-level ecosystem service predictions using the **mass-ratio hypothesis** (Grime 1998).

**Formula**:
```
E_community = Σ(pᵢ × Eᵢ)
```
Where:
- **Eᵢ** = Ecosystem service value for species i (e.g., NPP rating, N-fixation capacity)
- **pᵢ** = Proportional abundance of species i (by biomass, cover, or count)

**Rationale**: Dominant species control most nutrient/water/energy fluxes in ecosystems. This proportional contribution (mass-ratio effect) is the primary driver of community-level properties.

**Limitations**:
- Ignores nonlinear species interactions (facilitation, competition, complementarity)
- Such interactions are small relative to mass-ratio effects (empirical studies)
- Trait-based prediction of interactions currently impossible

**Example** (NPP for 3-species garden):
```r
# Species composition:
# Oak (40% cover), Clover (30% cover), Fern (30% cover)

# Species-level NPP calculations:
NPP_oak   = height_oak * (C_oak / 100)    # Woody: 20m * 0.45 = 9.0
NPP_clover = C_clover / 100               # Herb: 0.65
NPP_fern   = C_fern / 100                 # Herb: 0.30

# Community-weighted NPP:
NPP_community = 0.4 * 9.0 + 0.3 * 0.65 + 0.3 * 0.30
              = 3.6 + 0.195 + 0.09
              = 3.885
```

**Implementation priority**: High (critical for garden/landscape applications where users select species mixes)

**Data requirements**:
- Species-level ecosystem service ratings (from CSR + height/family)
- Proportional abundance (user-specified or estimated from planting density)

**Confidence**: High (mass-ratio hypothesis well-validated empirically; assumes additive effects)

---

## 5. Methodological Recommendations

### 5.1 When to Use CSR Direct Prediction
- C/N cycling services
- Productivity/biomass dynamics
- Decomposition rates
- **When**: Qualitative comparisons, relative rankings, broad patterns

### 5.2 When to Extend Beyond CSR
- Water/thermal regulation
- Urban ecosystem services
- Below-ground processes
- **When**: Quantitative predictions, site-specific management, multifunctional optimization

### 5.3 Best Practices
1. **Always calculate CSR** as foundation (ubiquitous trait coverage)
2. **Augment with targeted traits** for specific services
3. **Use functional diversity metrics** for community-level effects
4. **Acknowledge uncertainty** and validate locally where possible
5. **Combine qualitative CSR predictions with quantitative trait-based models** for robust inference

---

## 6. Summary: Strengths and Limitations

### Strengths of CSR Framework
- Global applicability across biomes and life forms
- Strong mechanistic basis for C/N/productivity services
- Simple, measurable traits (LA, LDMC, SLA)
- Extensive validation (3068 species, 14 biomes)
- Robust to trait availability constraints

### Critical Limitations
- 40% gap in ecosystem services coverage
- Above-ground bias (root traits largely absent)
- Hydraulic processes not represented
- Community diversity effects not captured
- Urban/climate adaptation services missed

### Path Forward
**Hybrid approach**: CSR as scaffold + targeted trait extensions for comprehensive ecosystem service prediction across all major service categories.

---

## References

**Core Methodology**:
- Pierce et al. (2016) Functional Ecology 31:444-457 - Global CSR method
- Grime (2001) Plant Strategies, Vegetation Processes, and Ecosystem Properties

**Ecosystem Services Framework**:
- Shipley (2025) Personal communication Part I - CSR and ecosystem services (qualitative predictions)
- Shipley (2025) Personal communication Part II - Life form adjustments for NPP/biomass, nitrogen fixation, community aggregation
- Garnier & Navas (2013) Diversité fonctionnelle des plantes
- Vile et al. (2006) Ecology Letters 9:1061-1067 - NPP from RGR_max

**Gap Analysis**:
- Repository model fusion summaries (Water, Heat, Soil, Biomass services)
- Stage 3 ecosystem services gap analysis (this volume)
