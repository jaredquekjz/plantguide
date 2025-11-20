# The Guild Scorer Metrics: A Comprehensive Guide

**Date:** 2025-11-20
**Subject:** Technical, Scientific, and Practical Guide to Guild Metrics (M1-M7)

## Introduction

This document provides a complete overview of the 7 ecological metrics used to score plant guilds. It combines a friendly explanation of **how the code calculates the score**, the **scientific theory** behind it, and its **practical use** for gardeners and designers.

---

## M1: Pest & Pathogen Independence
*Risk Management through Diversity*

### How It Works (The Code)
Imagine a family tree of all plants. The code looks at your list of plants and measures the total "evolutionary distance" connecting them on this tree (using a metric called **Faith's Phylogenetic Diversity**).
*   **Calculation:** It sums up the branch lengths of the tree connecting your species.
*   **Scoring:** It applies a formula (`risk = exp(-0.001 * diversity)`) where more diversity equals lower risk.
*   **Result:** A high score means your plants are distantly related (e.g., a Pine, a Bean, and a Squash). A low score means they are closely related (e.g., three types of Cabbage).

### Scientific Basis (Soundness: High)
This is based on the **Dilution Effect** and **Associational Resistance**. Closely related plants (like those in the Rose family or Cabbage family) often share the same pests and diseases. By planting distantly related species together, you break the "bridge" that allows pests to jump easily from plant to plant.

### Horticultural Usefulness (Medium-High)
*   **Actionable Advice:** "Don't put all your eggs in one basket."
*   **Use Case:** Prevents monoculture-style failures. If you plant a guild of only *Prunus* species (Plums, Cherries, Peaches), a single disease could wipe them all out. This metric warns you against that.

---

## M2: Growth Compatibility
*Preventing the "Bully" Problem*

### How It Works (The Code)
The code assigns every plant a strategy based on Grime's CSR theory: **Competitors** (fast growers), **Stress-tolerators** (slow, hardy), and **Ruderals** (weedy, fast seeders). It then checks for "fights":
*   **The Bully Check:** Is a strong Competitor planted next to a slow Stress-tolerator?
*   **The Sun Check:** If the slow plant loves shade, the "bully" might actually be a helpful "nurse plant" (providing shade). The code checks light preferences to decide if it's a fight or a friendship.
*   **The Height Check:** If the plants are at very different heights (e.g., a tree and a groundcover), they don't fight.

### Scientific Basis (Soundness: High)
Grime's CSR theory is a cornerstone of ecology. It accurately predicts that a fast-growing, resource-hungry plant will kill a slow-growing specialist if they compete for the same resources. The code's addition of light and height modulations makes this highly realistic.

### Horticultural Usefulness (High)
*   **Actionable Advice:** "Don't plant a delicate alpine flower next to a vigorous mint."
*   **Use Case:** Saves you work! It prevents high-maintenance combinations where you have to constantly prune the aggressive plant to save the weak one.

---

## M3: Insect Control (Biocontrol)
*The Bodyguard System*

### How It Works (The Code)
The code acts like a matchmaker using a massive database of "who eats whom."
1.  **Identify Villains:** It lists all herbivores that eat your plants.
2.  **Identify Heroes:** It looks at the other plants to see if they attract predators (ladybugs, wasps) or fungi that eat those specific villains.
3.  **Scoring:** You get points for "Specific Matches" (Plant A attracts a wasp that eats Plant B's pest) and "General Protection" (Plant A attracts lots of predators in general).

### Scientific Basis (Soundness: Moderate)
**Conservation Biological Control** is real: diverse gardens attract beneficial insects. However, the metric relies on data that is often incomplete. A "zero" score might just mean "we don't know," not "no protection."

### Horticultural Usefulness (High)
*   **Actionable Advice:** "Plant Yarrow to attract wasps that eat the aphids on your Broccoli."
*   **Use Case:** The holy grail of organic gardening. When it works, it reduces the need for pesticides. Treat positive scores as a verified bonus.

---

## M4: Disease Control
*The Soil Immune System*

### How It Works (The Code)
Similar to M3, but for diseases.
1.  **Identify Pathogens:** Lists fungi that make your plants sick.
2.  **Identify Doctors:** Checks if other plants host "mycoparasites" (fungi that eat other fungi, like *Trichoderma*) or tiny animals that eat fungus.
3.  **Scoring:** Points for specific matches and general presence of these beneficial "soil doctors."

### Scientific Basis (Soundness: Moderate)
Mycoparasites are proven biocontrol agents. However, soil ecology is complex; just having the good fungus doesn't guarantee it will cure the disease. It's a good indicator of potential resilience.

### Horticultural Usefulness (Moderate)
*   **Actionable Advice:** "Build healthy soil life."
*   **Use Case:** Harder to see than insects, but valuable for long-term garden health. Think of it as a "resilience booster."

---

## M5: Beneficial Fungi Networks
*The Wood Wide Web*

### How It Works (The Code)
This metric looks for plants that can "plug in" to the same fungal internet.
*   **Network Score:** Do your plants share the same type of mycorrhizal fungi (AMF or EMF)? If yes, they *could* theoretically share resources.
*   **Coverage Score:** What percentage of your plants support *any* beneficial fungi?

### Scientific Basis (Soundness: Low-Moderate)
Common Mycorrhizal Networks (CMNs) exist, but their benefits are debated. Sometimes they transfer nutrients, sometimes they don't. The "Coverage" part (just having fungi) is scientifically very sound—most plants grow better with fungal partners.

### Horticultural Usefulness (Moderate)
*   **Actionable Advice:** "Plant species that support soil fungi."
*   **Use Case:** Good for soil restoration and general ecosystem health. Don't rely on it to magically feed your plants, but know that it helps them access soil nutrients.

---

## M6: Structural Diversity
*The Architecture of Light*

### How It Works (The Code)
This metric is the architect of the guild. It looks at **Height** and **Light**.
1.  **Stratification:** It checks if you have plants at different layers (Canopy, Shrub, Herb).
2.  **The Shade Test:** If you put a short plant under a tall one, the code asks: "Does the short plant *like* shade?"
    *   If **Yes**: Great! You get points for efficient stacking.
    *   If **No** (it loves sun): Penalty! You're starving it of light.

### Scientific Basis (Soundness: High)
This is **Niche Partitioning**. Plants can grow densely if they don't fight for the same space or light. The code's "Shade Test" is scientifically rigorous and prevents overcrowding mistakes.

### Horticultural Usefulness (Very High)
*   **Actionable Advice:** "Plant shade-lovers under your fruit trees."
*   **Use Case:** The key to high yields in small spaces. It guides the physical layout of your garden, ensuring every plant gets the light it needs.

---

## M7: Pollinator Support
*The Bee Magnet*

### How It Works (The Code)
This metric calculates how many of your plants share the same pollinators.
*   **The "Buzz" Calculation:** It uses a "quadratic weighting" formula. This means 5 plants sharing a bee are worth *much more* than 5 separate plants each attracting 1 bee. It rewards creating a "hotspot."

### Scientific Basis (Soundness: Moderate)
**Pollinator Facilitation**: A dense patch of flowers attracts more pollinators than scattered ones. The math correctly models this "magnet effect."

### Horticultural Usefulness (High)
*   **Actionable Advice:** "Create a pollinator strip."
*   **Use Case:** Essential for fruit set (yield) and supporting wildlife. A high score ensures your garden is buzzing with activity.

---

## Summary Recommendation

*   **Start with M6 (Structure) and M2 (Growth):** These ensure your plants will physically fit and won't kill each other.
*   **Check M1 (Pest Independence):** To avoid catastrophic disease risk.
*   **Optimize M3 (Insects) and M7 (Pollinators):** To boost ecosystem services and yield.
*   **Treat M4 and M5:** As indicators of long-term soil health and resilience.
