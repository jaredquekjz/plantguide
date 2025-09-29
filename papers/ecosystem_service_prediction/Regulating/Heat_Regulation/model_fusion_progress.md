# Heat Regulation Model-Fusion Progress (Methods 1 & 2)

This note summarises the cooling/insulation evidence contained in the green-roof studies stored here:

- Monteiro et al. 2017 – detailed energy-balance measurements for six genotypes (Salvia, Stachys, Sedum, Sempervivum, two Heuchera cultivars) across two summers.
- Lundholm et al. 2014 – four-year trait/growth experiment linking 13 species’ traits (SLA, CSR strategies) to canopy development in mono- and polycultures.

All PDFs and Mathpix `.mmd` transcriptions are in this folder.

---

## Method 1 – Meta-Regression Feasibility

| Paper | Response variable(s) | Extracted quantitative signal | Gaps preventing pooling |
| --- | --- | --- | --- |
| Monteiro et al. 2017 | Net radiation partitioning (H, LE, G), substrate heat flux, canopy surface temperature | Tabulated LAI, albedo, canopy height per species; Table 4 gives %Rn routed to H/LE/G (e.g. Salvia allocates 96 % to LE vs. 57 % for Sempervivum). Stomatal conductance and LAI clearly linked to higher latent heat flux and insulation. | No regression coefficients or standard errors for trait → flux relationships; cooling reported per cultivar rather than as continuous trait models. |
| Lundholm et al. 2014 | Change in canopy density, final aboveground biomass (proxy for shading) | Multiple regression identified SLA as the strongest predictor of canopy expansion (ruderal, high-SLA species dominate). | Only standardized regression summaries; no standard errors for trait slopes; responses are growth rather than direct temperature metrics. |

To run a formal meta-regression we would need: (i) trait–flux slopes with SE (e.g. LAI vs. sensible heat), (ii) consistent responses (temperature reduction, substrate heat flux), and (iii) moderator data (irrigation status, substrate depth). The current papers provide direction and magnitude hierarchy but insufficient error structure for pooled estimates.

---

## Method 2 – Surrogate Stacking

### Trait rules distilled from the literature

- **Leaf area index (LAI)** – high LAI broadleaf canopies (Salvia, Stachys) dissipate >90 % of net radiation as latent heat, strongly cooling roofs.
- **Stomatal conductance** – well-watered canopies with high g<sub>s</sub> maximise transpiration and substrate insulation.
- **Light leaf colour / albedo** – pale foliage (e.g. silver-leaved cultivars) reduces absorbed shortwave radiation.
- **Canopy height** – taller, denser canopies shield the substrate and improve nocturnal insulation.
- **Specific leaf area (SLA)** – high SLA (ruderal strategy) predicts rapid canopy closure, enhancing shading (Lundholm 2014).
- **Succulence / leaf thickness** – thick, low-SLA succulents (Sedum, Sempervivum) have low transpiration and store heat, lowering cooling potential.

### Vote-derived weights

| Trait | Vote score | Normalized weight |
| --- | --- | --- |
| LAI | 1.0 | +0.182 |
| Stomatal conductance | 1.0 | +0.182 |
| Leaf albedo / brightness | 1.0 | +0.182 |
| Canopy height | 0.5 | +0.091 |
| SLA | 0.5 | +0.091 |
| Succulence | -1.0 | -0.182 |
| Leaf thickness | -0.5 | -0.091 |

### Example ensemble scores (traits scaled 0–1)

| Scenario | Trait highlights | Cooling index |
| --- | --- | --- |
| Broadleaf canopy (Salvia/Stachys-like) | LAI 0.8, g<sub>s</sub> 0.8, bright foliage 0.7, height 0.6, SLA 0.6, low succulence | **0.49** |
| Succulent mat (Sedum/Sempervivum) | LAI 0.3, g<sub>s</sub> 0.2, albedo 0.4, succulence 0.9, thick leaves | **≈ 0.00** |
| Mixed planting | Intermediate traits | **0.29** |

Higher indices indicate greater expected summer cooling and substrate insulation. The succulents’ low score mirrors Monteiro et al.’s finding that they route a larger share of net radiation into sensible and ground heat.

### TODOs for Method 2

1. Digitise Figure/Tabular data to recover quantitative trait → flux slopes (e.g. LAI vs. sensible heat at noon) with SE to refine weights.
2. Add uncertainty bands by bootstrapping the vote table or by propagating cross-species variance in the Monteiro dataset.
3. Incorporate winter insulation behaviour once colder-season data are extracted (same papers contain nocturnal fluxes).

---

## Next Steps

- Harvest supplementary data (if available) for Monteiro et al. to obtain standard deviations for flux differences.
- Extend the rule set with additional species trials (e.g. rooftop experiments in other climates) when PDFs are available.
- Once roof-trait surveys exist, apply the surrogate stack to score candidate planting palettes (report index + uncertainty).

