# Guild Reports Ecological Review - Preliminary Findings

**Date:** 2025-11-21
**Reports Reviewed:** 4 guild explanation reports (Forest Garden, Competitive Clash, Stress-Tolerant, Biocontrol Powerhouse)

## Critical Issues Identified

### 1. Saprotrophic fungi labeled as "mycorrhizal fungi"
**Reports:** All reports
**Type:** Terminology/categorization issue

Reports consistently state "X shared mycorrhizal fungal species" but composition shows:
- Forest Garden: "147 shared mycorrhizal fungal species" → 86.4% saprotrophic, only 3.4% mycorrhizal (5 species)
- Biocontrol Powerhouse: "385 shared mycorrhizal fungal species" → 85.2% saprotrophic, only 6.5% mycorrhizal (25 species)

**Investigation needed:** Check if this is labeling error in report generation or data categorization issue.

### 2. Oak (Quercus robur) showing insect pollinators
**Report:** Biocontrol Powerhouse
**Type:** Potential data error vs ecological knowledge conflict

Pollinator network shows Quercus robur with 14 pollinator species (8 wasps, 6 other).

**Prior knowledge:** Oaks are wind-pollinated, not insect-pollinated.

**Investigation needed:**
- Check GloBI raw data for Quercus robur pollinators
- Verify if these are true pollination interactions or other interaction types
- Web search to confirm oak pollination mechanism

### 3. Carex mucronata extreme alkalinity (pH >8, EIVE R = 9.1)
**Report:** Stress-Tolerant
**Type:** Potential data error

Listed as "Strongly Alkaline (pH >8)" with EIVE R value of 9.1, creating guild pH range of 5.1-9.1 (4.0 units).

**Investigation needed:** Check EIVE database for Carex mucronata R value accuracy.

## Moderate Issues

### 4. Rubus moorei height classification (0.5m ground layer)
**Report:** Forest Garden
**Type:** Potential data vs ecological knowledge conflict

Listed as ground layer at 0.5m, but Rubus moorei is known as climbing species.

**Investigation needed:** Check TRY database height value and verify species identity.

### 5. Zero pollinators/fungi for multiple species
**Reports:** Multiple
**Type:** Data completeness issue

Many species show 0 pollinators or 0 fungi (e.g., Deutzia scabra, Rubus moorei, Eucalyptus melanophloia).

**Investigation needed:** Verify if GloBI/interaction databases lack data vs. true ecological absence.

### 6. CSR strategy count mismatch
**Report:** Competitive Clash
**Type:** Calculation error

States "5 Competitive, 1 Stress-tolerant" but guild has 7 plants (1 unaccounted).

**Investigation needed:** Check actual CSR values for all 7 species.

### 7. M5 coverage 71.4% with score 100/100
**Report:** Forest Garden
**Type:** Scoring logic question

Perfect score despite 2 plants having 0 fungi.

**Investigation needed:** Check M5 scoring algorithm - is this correct behavior?

## Design Issues (Not Errors)

### 8. Geographic mixing of species
**Reports:** Multiple
**Type:** Intentional design choice

Guilds mix species from different continents (e.g., Hawaiian + South American + European).

**Assessment:** Ecologically unrealistic for natural communities, but valid for permaculture/designed guilds.

---

## Investigation Plan

1. Check saprotrophic vs mycorrhizal categorization in fungi data
2. Query GloBI for Quercus robur pollinator interactions
3. Web search oak pollination mechanism
4. Check EIVE database for Carex mucronata
5. Verify TRY height data for Rubus moorei
6. Check CSR values for Competitive Clash guild
7. Review M5 scoring algorithm
8. Check GloBI data completeness for zero-interaction species
