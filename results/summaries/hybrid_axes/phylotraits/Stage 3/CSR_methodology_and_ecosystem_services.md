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

- StrateFy Excel calculator (Pierce et al. 2016/2017 Supporting Information)
- Open implementations: R code reproducing the Excel logic (constants and equations) are publicly available and match the formulas above.

### 1.6 Reproducible Commands (this repository)

We ship a small Python tool that implements the exact formulas above.

- Compute CSR from LA/LDMC/SLA columns (ensure units: mm², %, mm²·mg⁻¹):

```
conda run -n AI python src/Stage_3_CSR/calculate_stratefy_csr.py \
  --input_csv data/your_traits.csv \
  --output_csv results/csr_out.csv \
  --species_col wfo_accepted_name \
  --la_col LA \
  --ldmc_col LDMC \
  --sla_col SLA
```

- Or from LA + fresh/dry masses (mg) with succulent correction (LDMC/SLA derived):

```
conda run -n AI python src/Stage_3_CSR/calculate_stratefy_csr.py \
  --input_csv data/your_traits_with_masses.csv \
  --output_csv results/csr_out.csv \
  --species_col wfo_accepted_name \
  --la_col LA \
  --lfw_col LFW \
  --ldw_col LDW
```

- Makefile wrapper (preferred for reproducibility):

```
make csr FILE='data/your_traits.csv' OUT='results/csr_out.csv' \
  SPECIES_COL='wfo_accepted_name' LA_COL='LA' LDMC_COL='LDMC' SLA_COL='SLA'

# or, with masses
make csr FILE='data/your_traits_with_masses.csv' OUT='results/csr_out.csv' \
  SPECIES_COL='wfo_accepted_name' LA_COL='LA' LFW_COL='LFW' LDW_COL='LDW'
```

Outputs add `C`,`S`,`R` columns that sum to 100.

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
✓ Net Primary Productivity
✓ Litter Decomposition
✓ Carbon Storage (partial - above-ground focus)
✓ Nutrient Cycling
✓ Nutrient Retention/Loss
✓ Soil Erosion (low confidence)

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
- Shipley (2025) Personal communication - CSR and ecosystem services
- Garnier & Navas (2013) Diversité fonctionnelle des plantes
- Vile et al. (2006) Ecology Letters 9:1061-1067 - NPP from RGR_max

**Gap Analysis**:
- Repository model fusion summaries (Water, Heat, Soil, Biomass services)
- Stage 3 ecosystem services gap analysis (this volume)
### 2.1 Rule-Based Qualitative Ratings from CSR

To remain faithful to Bill Shipley’s qualitative guidance (and avoid implying quantitative precision), we convert species‑level CSR (C,S,R) into ordinal ratings for key ecosystem properties/services using simple rules that enforce his rank orders. Each service also carries a confidence tag reflecting the strength of evidence in Bill’s note.

Rating scale
- Very Low / Low / Moderate / High / Very High (no numeric values shown in UI)

Rules (C,S,R are percentages)
- NPP (Very High confidence; C > R > S)
  - Very High: C ≥ 60
  - High: C ≥ 50 or R ≥ 50
  - Low: S ≥ 60
  - Else: Moderate
- Decomposition (Very High; R ≈ C > S)
  - Very High: R ≥ 60 or C ≥ 60
  - High: R ≥ 50 or C ≥ 50
  - Low: S ≥ 60
  - Else: Moderate
- Nutrient Cycling (Very High; R ≈ C > S)
  - Same rules as Decomposition
- Nutrient Retention (Very High; C > S > R)
  - Very High: C ≥ 60
  - High: (C ≥ 50 and S ≥ 30) or S ≥ 60
  - Low: R ≥ 50
  - Else: Moderate
- Nutrient Loss (Very High; inverse of retention, render as caution)
  - Very High: R ≥ 60
  - High: R ≥ 50
  - Very Low: C ≥ 60
  - Low: C ≥ 50
  - Else: Moderate
- Carbon Storage — Biomass (High; dominated by C)
  - Very High / High / Moderate / Low / Very Low based on C bands: ≥60 / ≥50 / ≥40 / ≥30 / <30
- Carbon Storage — Recalcitrant (High; dominated by S)
  - Same bands using S
- Carbon Storage — Total (High; C ≈ S > R)
  - Very High: (C ≥ 50 and S ≥ 40) or (S ≥ 50 and C ≥ 40)
  - High: C ≥ 50 or S ≥ 50
  - Moderate: C ≥ 40 or S ≥ 40
  - Very Low: C < 30 and S < 30
  - Else: Low
- Erosion Protection (Moderate; C > S > R)
  - Very High: C ≥ 60 or (C ≥ 50 and S ≥ 40)
  - High: C ≥ 50 or S ≥ 50
  - Low: R ≥ 50
  - Else: Moderate

Confidence tags (from Bill’s note)
- Very High: NPP, Decomposition, Nutrient Cycling, Nutrient Retention/Loss
- High: Carbon Storage (biomass, recalcitrant, total)
- Moderate: Erosion Protection

Implementation
- Script: `src/Stage_3_CSR/compute_rule_based_ecoservices.py`
- Input: `artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2_with_csr.csv` (per‑species CSR)
- Output: `artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2_with_csr_services.csv` (appended rating + confidence columns)
