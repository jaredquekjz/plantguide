# Missing TRY Traits Analysis for EIVE Multi-Organ Modeling

## Executive Summary
After analyzing the TRY database trait list against our extracted data, we're missing several CRITICAL traits that have good coverage. The "surprisingly incomplete" leaf data is because we got SLA variant 3117 but missed the main leaf area traits!

## 🚨 CRITICAL MISSING TRAITS TO REQUEST

### 1. LEAF TRAITS (We got SLA but missed actual leaf area!)
| TraitID | Trait Name | Species Available | Priority |
|---------|------------|-------------------|----------|
| **3114** | Leaf area (undefined if compound) | **8,770 species** | ESSENTIAL |
| **3110** | Leaf area (petiole included) | 3,990 species | HIGH |
| **3112** | Leaf area (undefined petiole) | 7,467 species | HIGH |
| **3108** | Leaf area (petiole excluded) | 3,284 species | MEDIUM |
| **125** | Leaf area per fresh mass | 772 species | LOW |
| **3115** | SLA (petiole excluded) | 8,120 species | MEDIUM |
| **3116** | SLA (petiole included) | 8,245 species | MEDIUM |

### 2. ROOT TRAITS (Available but not extracted!)
| TraitID | Trait Name | Species Available | Priority |
|---------|------------|-------------------|----------|
| **614** | Fine root SRL | **1,308 species** | ESSENTIAL |
| **896** | Fine root diameter | **1,147 species** | ESSENTIAL |
| **1781** | Fine root tissue density | **881 species** | ESSENTIAL |
| **475** | Fine root nitrogen content | **796 species** | ESSENTIAL |
| **80** | Root tissue density (general) | 1,562 species | HIGH |
| **82** | Root diameter (general) | 1,919 species | HIGH |
| **83** | Root nitrogen content | 1,945 species | HIGH |
| **6** | Root rooting depth | 1,635 species | MEDIUM |
| **1080** | Root SRL (general) | 1,421 species | HIGH |

### 3. WOOD TRAITS 
| TraitID | Trait Name | TRY Total | EIVE Coverage | Priority | Notes |
|---------|------------|-----------|---------------|----------|-------|
| **4** | Wood density | **12,812 total** | **673 EIVE (6.6%)** | - | Already extracted |
| **282** | Stem conduit diameter | 737 total | Unknown | HIGH | Need to request |
| **287** | Stem vessel density | 1,337 total | Unknown | HIGH | Need to request |
| **319** | Stem sapwood specific conductivity | 416 total | Unknown | MEDIUM | Need to request |
| **419** | Stem dry mass | 3,024 total | Unknown | MEDIUM | Need to request |

**Note**: Wood density (TraitID 4) has excellent GLOBAL coverage (12,812 species) but only 673 EIVE species have data. This is likely because most woody EIVE species are herbaceous, and wood density data is concentrated on trees from other regions (tropical, boreal, etc.).

### 4. MYCORRHIZAL TRAITS
| TraitID | Trait Name | Species Available | Priority |
|---------|------------|-------------------|----------|
| **1498** | Mycorrhizal colonization (%) | ~500 species | MEDIUM |
| **3488** | Species nutritional relationships | 685 species | MEDIUM |

### 5. ARCHITECTURE/FORM TRAITS (Good alternatives to what we have)
| TraitID | Trait Name | Species Available | Priority |
|---------|------------|-------------------|----------|
| **368** | Plant growth rate | 2,395 species | HIGH |
| **2** | Plant ontogeny | 4,000+ species | MEDIUM |
| **93** | Leaf lifespan | 3,316 species | HIGH |

## WHY WE MISSED THESE

1. **Multiple trait variants**: TRY has many versions of the same trait (e.g., 10+ leaf area definitions)
2. **We only searched for specific IDs**: Our extraction used exact TraitIDs, missing alternatives
3. **Root traits ARE available**: Contrary to our assumption, TRY has decent root trait coverage (~10% of EIVE species)

## RECOMMENDED ACTION PLAN

### Immediate Priority: Request Additional TRY Data
Submit new TRY request for EIVE species with these traits:
```
Essential Traits (MUST HAVE):
- 3114, 3110, 3112 (Leaf area variants)
- 614, 896, 1781, 475 (Fine root traits)
- 80, 82, 83, 1080 (General root traits)
- 282, 287 (Wood hydraulics)

Secondary Traits (NICE TO HAVE):
- 3115, 3116 (Additional SLA variants)
- 319 (Stem conductivity)
- 1498, 3488 (Mycorrhizal)
- 93 (Leaf lifespan)
```

### Data Coverage After New Request
If we get these traits, expected coverage for EIVE taxa:
- **Leaf traits**: ~60% (up from 32%)
- **Root traits**: ~10% (up from 0%!)
- **Wood traits**: ~15% (up from 6.6%)
- **Overall model viability**: MUCH improved!

## COMPARISON WITH CURRENT EXTRACTION

### What We Successfully Got:
- SLA (3117): 3,282 species ✓
- LDMC (47): 3,286 species ✓
- Leaf N (14): 2,338 species ✓
- Seed mass (26): 6,618 species ✓
- Plant height (18, 3106, 3107): 2,790-6,491 species ✓
- Wood density (4): 673 species ✓
- Mycorrhiza type (7): 2,802 species ✓

### What We Completely Missed:
- **Leaf area**: 0 species (but 8,770 available!) ✗
- **ALL root traits**: 0 species (but 1,000+ available per trait!) ✗
- **Wood hydraulics**: Limited coverage ✗

## GROOT DATABASE NOTE
Since you're getting GROOT separately for roots, we might have better root coverage than TRY alone. GROOT focuses specifically on root traits and likely has:
- More complete root trait coverage
- Better standardization
- Additional root architectural traits

## KEY INSIGHT
**The leaf data isn't "surprisingly incomplete" - we just didn't request the right trait IDs!** TRY has excellent leaf area coverage (8,770 species for trait 3114), we simply need to request it.