# Test Guild Explanations

**Generated**: 2025-11-02
**Script**: `src/Stage_4/05b_explain_guild_score.py`

User-friendly explanations for why each test guild scored the way it did.

---

## BAD GUILD: 5 Acacias (Score: -0.159)

### Verdict
⚠️  **POOR GUILD - Risks outweigh benefits**

### Why This Score?
- Positive Factors (Benefits): 0.292 / 1.0
- Negative Factors (Risks): 0.451 / 1.0
- **Final Score** = 0.292 - 0.451 = **-0.159**

### Main Problems

**1. CRITICAL: 40 Shared Pathogenic Fungi** (Score: 0.719)
- 7 fungi affect 80%+ of plants
- Example diseases: *Meliola*, *Ganoderma*, *Fusarium*
- **Risk**: One disease outbreak could destroy entire guild

**2. MONOCULTURE: Only 1 Plant Family** (Score: 0.120)
- All plants from Fabaceae
- **Risk**: Disease can easily jump between plants with no barriers

**3. Beneficial Fungi Penalty Applied**
- 49 shared beneficial fungi (normally good!)
- BUT reduced 50% due to high pathogen load
- **Reality**: Beneficial fungi don't matter if all plants die from disease

### Recommendations
❌ This guild has significant risks - consider alternatives

**Suggested changes:**
1. Replace some plants with different families
2. Choose plants with fewer shared diseases
3. Increase taxonomic diversity

---

## GOOD GUILD #1: Taxonomically Diverse (Score: +0.322)

### Verdict
✅ **GOOD GUILD - These plants work well together!**

### Why This Score?
- Positive Factors (Benefits): 0.352 / 1.0
- Negative Factors (Risks): 0.030 / 1.0
- **Final Score** = 0.352 - 0.030 = **+0.322**

### What Makes It Good

**1. Minimal Shared Diseases** (Score: 0.060)
- Only 5 shared pathogenic fungi
- **Benefit**: Low disease transmission risk

**2. Zero Shared Pests** (Score: 0.000)
- Different herbivores for each plant
- **Benefit**: Pests can't build up and jump between plants

**3. Excellent Beneficial Fungi Network** (Score: 0.798)
- 12 shared beneficial fungi
- Mycorrhizae, endophytes, and decomposers connect plants
- **Benefit**: Nutrient sharing and soil health

**4. Good Taxonomic Diversity** (Score: 0.622)
- 3 different plant families
- **Benefit**: Disease barriers between families

### Recommendations
✅ This guild should work well together!

**What makes it work:**
- Good plant diversity reduces disease transmission
- Minimal shared diseases
- Different pests (no concentration)

**Weakness**: No cross-plant biocontrol (P1 = 0.000)
- Plants don't attract predators of each other's pests
- Could be improved by adding pollinator-attracting plants

---

## GOOD GUILD #2: Native Pollinator Plants (Score: +0.028)

### Verdict
⚠️  **NEUTRAL GUILD - Mixed benefits and risks**

### Why This Score?
- Positive Factors (Benefits): 0.540 / 1.0
- Negative Factors (Risks): 0.512 / 1.0
- **Final Score** = 0.540 - 0.512 = **+0.028** (nearly balanced!)

### The Tradeoff

**HIGH RISK: 60 Shared Herbivores** (Score: 0.938)
- Example pests: *Bombus impatiens*, *Melissodes bimaculatus*, *Bombus griseocollis*
- Many generalist pollinators/visitors also recorded as "pests"
- **Concern**: High pest concentration

**BUT... EXCELLENT BIOCONTROL: 295 Predators** (Score: 1.000)
- 100% plant pair coverage with beneficial predators
- Plants attract insects that eat each other's pests
- **Benefit**: Natural biological control network

### What Makes It Interesting

**1. Minimal Disease Risk** (Score: 0.087)
- Only 6 shared pathogenic fungi
- **Safe**: Low disease transmission

**2. Excellent Diversity** (Score: 0.811)
- 4 different plant families
- **Safe**: High taxonomic barriers

**3. Perfect Biocontrol Coverage** (Score: 1.000)
- Every plant pair has cross-plant pest control
- **Sustainable**: Natural predator network

### Ecological Interpretation

This guild represents a **sustainable pest management system**:
- Many "pests" are actually beneficial pollinators (recorded as both visitors AND herbivores)
- Plants share their predators, creating natural biological control
- High diversity prevents disease jumping

**The score reflects reality**: High pest pressure + excellent biocontrol = marginal net benefit

### Recommendations
⚠️  This guild has mixed benefits and risks

**Key insight**: The high herbivore overlap is mitigated by perfect biocontrol. This is a **naturally balanced system** typical of native plant communities.

**Consider**: If you want higher scores, reduce pest overlap. But ecologically, this guild is **sustainable and self-regulating**.

---

## Comparison Summary

| Guild | Score | Verdict | Key Strength | Key Weakness |
|-------|-------|---------|--------------|--------------|
| **BAD** (Acacias) | -0.159 | Poor | 49 beneficial fungi | 40 shared pathogens, monoculture |
| **GOOD #1** (Diverse) | +0.322 | Good | Minimal overlap, 12 beneficial fungi | No biocontrol |
| **GOOD #2** (Pollinator) | +0.028 | Neutral | Perfect biocontrol (295 predators) | 60 shared herbivores |

### Key Lessons

**From BAD Guild:**
- Monoculture = catastrophic disease risk
- Beneficial fungi can't save you from shared pathogens
- Taxonomic diversity is CRITICAL

**From GOOD Guild #1:**
- Taxonomic diversity works!
- Different families = disease barriers
- Beneficial fungi networks add value

**From GOOD Guild #2:**
- High pest overlap can be sustainable with biocontrol
- Native plant communities self-regulate
- Pollinator plants create predator networks

---

## User Guide

**How to interpret scores:**

- **> +0.3**: Excellent, plant with confidence
- **0.0 to +0.3**: Good, manageable risks
- **-0.3 to 0.0**: Neutral, watch for problems
- **< -0.3**: Poor, consider alternatives

**When to worry:**
- N1 (Pathogen fungi) > 0.5 → Disease outbreak risk
- P4 (Diversity) < 0.2 → Monoculture vulnerability
- High N2 (Herbivores) without high P1 (Biocontrol) → Pest buildup

**When to celebrate:**
- P1 (Biocontrol) > 0.7 → Excellent pest management
- N1 + N2 < 0.2 → Very low transmission risk
- P4 (Diversity) > 0.7 → Strong resilience
