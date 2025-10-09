# CSR Strategies for Ecosystem Service Prediction
## Based on Bill Shipley's Analysis

### Overview
CSR scores provide scientifically-supported **qualitative predictions** of ecosystem properties and services. Quantitative predictions would require site-level trait × environment interactions that are difficult to obtain comprehensively.

---

## CSR Strategy Definitions

### Trait-Based Characterization
The S → (C,R) gradient aligns with the Leaf Economics Spectrum:

| Strategy | Growth Rate | Tissue Quality | Biomass | Persistence |
|----------|------------|----------------|---------|-------------|
| **S** (Stress-tolerant) | Slow | Recalcitrant (high LDMC, low SLA, high lignin) | Low-Moderate | Long-lived |
| **C** (Competitive) | Fast | High quality (low LDMC, high SLA, high N) | High | Moderate |
| **R** (Ruderal) | Fast | High quality (low LDMC, high SLA, high N) | Low | Short-lived |

**Key distinction**: C vs R primarily differs in disturbance regime, not growth traits
- C: Low disturbance → large standing biomass
- R: High disturbance → small standing biomass despite high growth potential

---

## Ecosystem Services by CSR Position

### 1. Net Primary Productivity (NPP)
**Confidence: Very High**

Mathematical basis: NPP = Standing Biomass × Specific Growth Rate

| Strategy | NPP Level | Mechanism |
|----------|-----------|-----------|
| **S** | Low | Slow growth rate dominates |
| **C** | **Highest** | High growth × large biomass |
| **R** | Moderate | High growth but small biomass |

### 2. Litter Decomposition Rate
**Confidence: Very High**

Trait drivers: SLA (+), LDMC (-), Leaf N (+), Lignin (-)

| Strategy | Decomposition | Litter Quality |
|----------|---------------|----------------|
| **S** | Slow | Poor (high LDMC, lignin) |
| **C** | Fast | High (high SLA, N) |
| **R** | Fast | High (high SLA, N) |

### 3. Carbon Storage & Sequestration
**Confidence: High**

Balance: NPP (C capture) - Decomposition (C release)

| Strategy | C Storage | Living Biomass | Dead Biomass | Total |
|----------|-----------|----------------|--------------|-------|
| **S** | **High** | Moderate | High (slow decay) | **High** |
| **C** | **High** | Very High | Moderate | **High** |
| **R** | Low | Low | Low (fast decay) | Low |

### 4. Nutrient Cycling Rate
**Confidence: Very High**

Flow: Soil → Plant → Litter → Soil

| Strategy | Cycling Rate | Mechanism |
|----------|--------------|-----------|
| **S** | Slow | Nutrients locked in recalcitrant tissues |
| **C** | Fast | Rapid uptake and decomposition |
| **R** | Fast | Quick turnover of tissues |

### 5. Nutrient Retention vs Loss
**Confidence: Very High**

| Strategy | Nutrient Loss | Reason |
|----------|---------------|---------|
| **S** | Low | Slow release from tissues |
| **C** | **Low** | Large biomass recaptures nutrients |
| **R** | **High** | Nutrients leach before recapture |

### 6. Soil Erosion Protection
**Confidence: Moderate** (limited research)

| Strategy | Protection | Mechanism |
|----------|------------|-----------|
| **S** | Intermediate | Moderate cover |
| **C** | **Best** | Dense growth, large standing biomass |
| **R** | Poor | Frequent biomass removal |

---

## Visual Summary: CSR Triangle Mapping

```
        C (Competitive)
        ├─ Highest NPP
        ├─ Fast decomposition
        ├─ High C storage
        ├─ Fast cycling, low loss
        └─ Best erosion control
       / \
      /   \
     /     \
    /       \
   /         \
  S           R
(Stress)    (Ruderal)
  │           │
  ├ Low NPP   ├ Moderate NPP
  ├ Slow decomp├ Fast decomp
  ├ High C    ├ Low C storage
  ├ Slow cycle├ Fast cycle, HIGH loss
  └ Med erosion└ Poor erosion control
```

---

## Implementation Recommendations

### For Quantitative Predictions
**Requirements** (currently impractical):
1. Site-level ecosystem measurements
2. Georeferenced species abundances (sPlot, VegBank, LOTVS, EVA)
3. Species traits (TRY database)
4. Climate data
5. Matching spatial-temporal coverage

### For Qualitative Predictions (Recommended)
**Use existing CSR scores to predict**:
- Relative ecosystem service provision
- Trade-offs between services
- Response to management changes

### Key Equations
- **NPP**: Community-weighted RGR_max × Standing biomass
- **Decomposition**: f(SLA, LDMC, Leaf N, Lignin)
- **C Storage**: ∫(NPP - Decomposition)dt
- **Nutrient flux**: NPP × tissue [nutrient] × turnover rate

---

## Scientific Basis

### Primary References
- **Garnier & Navas (2013)**: Functional diversity framework, Chapter 6 on ecosystem properties
- **Garnier et al. (2016)**: English version, trait-ecosystem linkages
- **Pierce et al. (2017)**: Global CSR calculation method
- **Vile et al. (2006)**: NPP prediction from RGR_max and species abundance

### Historical Note
Original CSR ordination used RGR_max as the S→(C,R) axis variable; trait correlations enabled simpler trait-based methods.

---

## Limitations & Uncertainties

1. **Site-specificity**: Trait effects modulated by environment
2. **Soil processes**: Recalcitrant C formation poorly understood
3. **Erosion control**: Limited trait-erosion research
4. **Scale dependency**: Global patterns may not apply locally
5. **Management effects**: Anthropogenic disturbances alter CSR-service relationships

---

## Summary Message
CSR strategies provide robust **qualitative** predictions for most ecosystem services through well-understood trait-mediated mechanisms. The framework is strongest for productivity, decomposition, and nutrient dynamics, with moderate confidence for carbon storage and erosion control.