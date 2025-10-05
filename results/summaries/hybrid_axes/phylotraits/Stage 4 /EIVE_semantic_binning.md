# EIVE 0–10 Semantic Binning

This note documents how we derived reusable qualitative bands for the continuous EIVE scores so they can be compared with legacy textual descriptions (e.g. the Stage 7 Gemini profiles).

## Workflow Summary

1. **Load the consolidated source systems**  
   The file `data/EIVE/vegetation_classification_and_survey-004-007-g002.xlsx` (Suppl. Material 2 of Dengler et al. 2023) lists every regional indicator system. For each taxon and axis it contains:  
   - `*.o` – the original ordinal class from that source;  
   - `*.EIVE` – the harmonised 0–10 score;  
   - `*.o-var` / `*.EIVE.nw` – the original and harmonised niche-width classes.

2. **Select anchor sources per axis**  
   These are the systems that still provide clear qualitative wording:  
   - Light (L), Moisture (M ≡ F), Reaction (R), Nitrogen (N): `British_Isles` + `Germany`.  
   - Temperature (T): `Germany`, `France`, `Italy` (captures warm Mediterranean classes up to 12).  

3. **Normalise the classes**  
   `L.o`, `M.o`, etc. were rounded to the nearest integer to collapse half-step entries (e.g. 3.5 in the German table). The underlying semantics still follow the classic Ellenberg bands.

4. **Compute the numeric midpoints**  
   For each integer class:  
   - Take the median EIVE value across all taxa in that class.  
   - Enforce monotonicity (later classes must not have lower medians).  
   - Derive lower/upper cut-offs as the midpoints between adjacent medians.  
   - Clip the outer ranges to `[0, 10]`.

5. **Attach legacy wording**  
   Labels are taken from Hill et al. (1999) for L/M/R/N and from Wirth (2010) for T (extended to classes 10–12 for the Mediterranean additions).

6. **Write lookup tables**  
   The resulting bands live in `data/mappings/*_bins.csv` and include:  
   - `label` – descriptive phrase;  
   - `count` – number of taxa used for the class;  
   - `median_EIVE` – median 0–10 value;  
   - `lower`, `upper` – numeric cut-offs.

## Example Bands

### Light (L)
Source systems: British Isles + Germany.  Sample cut-offs:

| L class | label | median_EIVE | lower | upper |
|---------|-------|-------------|-------|-------|
| 1 | deep shade plant (<1% relative illumination) | 0.81 | 0.00 | 1.61 |
| 3 | shade plant (mostly <5% relative illumination) | 2.82 | 2.44 | 3.20 |
| 5 | semi-shade plant (>10% illumination, seldom full light) | 4.84 | 4.23 | 5.45 |
| 7 | half-light plant (mostly well lit but tolerates shade) | 7.41 | 6.51 | 7.47 |
| 9 | full-light plant (requires full sun) | 9.19 | 8.37 | 10.00 |

### Moisture (M)
Source systems: British Isles + Germany + Italy.  Sample cut-offs:

| M class | label | median_EIVE | lower | upper |
|---------|-------|-------------|-------|-------|
| 1 | indicator of extreme dryness; soils often dry out | 1.41 | 0.00 | 1.51 |
| 4 | moderately dry; also in dry sites with humidity | 3.66 | 3.29 | 3.99 |
| 7 | constantly moist or damp but not wet | 5.55 | 5.26 | 6.07 |
| 10 | shallow water sites; often temporarily flooded | 7.69 | 7.54 | 8.40 |
| 11 | rooted in water, emergent or floating | 8.98 | 8.40 | 10.00 |

### Temperature (T)
Source systems: Germany + France + Italy.  Sample cut-offs:

| T class | label | median_EIVE | lower | upper |
|---------|-------|-------------|-------|-------|
| 1 | very cold climates (high alpine / arctic-boreal) | 0.46 | 0.00 | 0.91 |
| 4 | rather cool montane climates | 3.22 | 2.74 | 3.68 |
| 7 | warm; colline, extending to mild northern areas | 5.52 | 4.98 | 6.41 |
| 10 | hot-submediterranean; warm Mediterranean foothills | 8.12 | 7.74 | 8.50 |
| 12 | very hot / subtropical Mediterranean extremes | 9.66 | 9.21 | 10.00 |

(Full tables are in `data/mappings/L_bins.csv`, `M_bins.csv`, `R_bins.csv`, `N_bins.csv`, `T_bins.csv`.)

## How to Use the Bins

1. **Model outputs → qualitative labels**  
   Drop the predicted `EIVEres-<Axis>` value into the corresponding bin to obtain the narrative phrase (e.g. `L=8.4` → “light-loving plant”).

2. **Legacy text → numeric check**  
   Search the Stage 7 Gemini JSONs for synonyms (e.g. “full sun”, “bog sites”). Map the detected phrase back to its numeric band to compare with model outputs.

3. **Applies to new species**  
   Because the bins are defined in the harmonised 0–10 space, they work even for taxa that never had original Ellenberg scores.

## Sanity Checks

- The counts per class are large (hundreds/thousands for major classes), so medians are stable.  
- Upper bounds reach 10 for the warmest/wettest classes, while the lowest classes start at 0.  
- The median progression is monotonic after smoothing; no class overlaps with a cooler/drier neighbour.

With these lookup tables in place, you can translate any predicted EIVE score into the same vocabulary used by the historical indicator systems, making validation against qualitative narratives straightforward.

